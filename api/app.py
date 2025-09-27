# api/app.py
from fastapi import FastAPI, Query, HTTPException
from pydantic import BaseModel
import joblib, pandas as pd, os, time, threading, logging, json
from datetime import datetime
from typing import List, Set, Optional
import boto3
from botocore.exceptions import BotoCoreError, ClientError

MODEL_PATH = os.getenv("MODEL_PATH", "models/model_openml_adult.joblib")
MODEL_S3_URI = os.getenv("MODEL_S3_URI")
LOG_DIR = "logs"
LOG_FILE = os.path.join(LOG_DIR, f"api-{datetime.now().strftime('%Y%m%d')}.log")

app = FastAPI(title="mlops-sklearn-api")

_model = None
_lock = threading.Lock()
_REQUIRED_COLS: List[str] = []
_NUMERIC_COLS: Set[str] = set()

# ── JSON 1行ロガー（アプリ側でアクセスログを整形してファイル出力）
_logger = logging.getLogger("api.access")
_logger.setLevel(logging.INFO)
os.makedirs(LOG_DIR, exist_ok=True)
if not _logger.handlers:
    fh = logging.FileHandler(LOG_FILE, encoding="utf-8")
    fh.setFormatter(logging.Formatter("%(message)s"))
    _logger.addHandler(fh)

def _json_log(**fields):
    # ensure_ascii=False で日本語もそのまま、1行JSON
    _logger.info(json.dumps(fields, ensure_ascii=False))

def _extract_columns_from_model(model):
    try:
        pre = model.named_steps["pre"]
        transformers = getattr(pre, "transformers", None) or getattr(pre, "transformers_", None)
        required, numeric = [], set()
        for name, _trans, cols in transformers:
            if isinstance(cols, (list, tuple)):
                required.extend(list(cols))
                if name == "num":
                    numeric.update(cols)
        return list(required), numeric
    except Exception:
        return [], set()

def load_model(path: str):
    global _model, _REQUIRED_COLS, _NUMERIC_COLS, MODEL_PATH
    with _lock:
        _model = joblib.load(path)
        MODEL_PATH = path  # 実際に読んだものを現在値に
        _REQUIRED_COLS, _NUMERIC_COLS = _extract_columns_from_model(_model)
    return _model

def _ensure_model_local():
    """MODEL_PATH がローカルに無い場合、MODEL_S3_URI から取得を試みる。無ければ何もしない。"""
    path = MODEL_PATH
    if os.path.exists(path):
        return path
    if MODEL_S3_URI:
        os.makedirs(os.path.dirname(path), exist_ok=True)
        try:
            s3 = boto3.client("s3")
            # s3://bucket/key を分解
            if not MODEL_S3_URI.startswith("s3://"):
                return None
            _, _, rest = MODEL_S3_URI.partition("s3://")
            bucket, _, key = rest.partition("/")
            s3.download_file(bucket, key, path)
            return path if os.path.exists(path) else None
        except (BotoCoreError, ClientError) as e:
            _json_log(ts=time.time(), event="model_download_failed", s3=MODEL_S3_URI, err=str(e))
            return None
    return None

def _normalize_batch(rows: List[dict]) -> pd.DataFrame:
    # rows: [{col: val, ...}, ...]
    if not _REQUIRED_COLS:
        return pd.DataFrame(rows)
    df = pd.DataFrame(rows)
    # 余計な列は捨て、足りない列は None を補完
    for col in _REQUIRED_COLS:
        if col not in df.columns:
            df[col] = None
    df = df[_REQUIRED_COLS]
    # 数値列は to_numeric で NaN 許容（Imputer が面倒を見る）
    for col in _NUMERIC_COLS:
        if col in df.columns:
            df[col] = pd.to_numeric(df[col], errors="coerce")
    return df

class Row(BaseModel):
    features: dict

class Rows(BaseModel):
    rows: List[dict]

@app.on_event("startup")
def _startup():
    # 起動時は“可能なら”モデルを用意。失敗してもアプリは起動継続。
    local = _ensure_model_local()
    if local:
        try:
            load_model(local)
        except FileNotFoundError:
            pass
    _json_log(ts=time.time(), event="startup", model=os.path.basename(MODEL_PATH), exists=os.path.exists(MODEL_PATH))


@app.middleware("http")
async def access_log(request, call_next):
    t0 = time.time()
    try:
        resp = await call_next(request)
        status = resp.status_code
    except Exception as e:
        status = 500
        raise
    finally:
        t1 = time.time()
        _json_log(
            ts=t1,
            method=request.method,
            path=request.url.path,
            query=str(request.url.query),
            status=status,
            latency_ms=int((t1 - t0) * 1000),
            client=getattr(request.client, "host", None),
            ua=request.headers.get("user-agent"),
            model=os.path.basename(MODEL_PATH),
        )
    return resp

@app.get("/health")
def health():
    return {
        "status": "ok",
        "model": os.path.basename(MODEL_PATH),
        "ts": time.time(),
        "cols": len(_REQUIRED_COLS) or None,
        "model_exists": os.path.exists(MODEL_PATH)
    }

@app.get("/schema")
def schema():
    return {"required_columns": _REQUIRED_COLS, "numeric_columns": sorted(_NUMERIC_COLS)}

@app.post("/predict")
def predict(item: Row):
    if _model is None:
        local = _ensure_model_local()
        if not local:
            raise HTTPException(status_code=503, detail="Model not available")
        load_model(local)
    X = _normalize_batch([item.features])
    proba = getattr(_model, "predict_proba", None)
    if proba:
        return {"pred_proba": float(proba(X)[:, 1][0])}
    return {"pred": _model.predict(X)[0]}

@app.post("/predict_batch")
def predict_batch(items: Rows):
    if _model is None:
        local = _ensure_model_local()
        if not local:
            raise HTTPException(status_code=503, detail="Model not available")
        load_model(local)
    X = _normalize_batch(items.rows)
    proba = getattr(_model, "predict_proba", None)
    if proba:
        return {"pred_proba": [float(x) for x in proba(X)[:, 1].tolist()]}
    return {"pred": _model.predict(X).tolist()}

@app.post("/reload")
def reload_model(path: Optional[str] = Query(None, description="モデルファイルへのパス")):
    # ?path=... があればそれを優先、無ければ現行 MODEL_PATH を再読込
    target = path or _ensure_model_local() or MODEL_PATH
    load_model(target)
    return {"status": "reloaded", "model": os.path.basename(MODEL_PATH)}

# api/app.py の末尾あたりに追加（既存コードは触らない）
import time, os
START_TS = time.time()
VERSION = os.getenv("VERSION", "0.0.0-dev")
GIT_SHA = os.getenv("GIT_SHA", "0000000")

@app.get("/metrics")
def metrics():
    lines = [
        f'app_version_info{{version="{VERSION}",git_sha="{GIT_SHA}"}} 1',
        f'app_uptime_seconds {int(time.time() - START_TS)}',
        f'app_model_exists {1 if os.path.exists(MODEL_PATH) else 0}',
        f'app_required_cols {len(_REQUIRED_COLS) or 0}',
    ]
    return FastAPI.responses.PlainTextResponse("\n".join(lines))
