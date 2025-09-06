from fastapi import FastAPI
from pydantic import BaseModel
import joblib, pandas as pd, os, time, threading
from typing import List, Set

MODEL_PATH = os.getenv("MODEL_PATH", "models/model_openml_adult.joblib")
app = FastAPI(title="mlops-sklearn-api")

_model = None
_lock = threading.Lock()
_REQUIRED_COLS: List[str] = []
_NUMERIC_COLS: Set[str] = set()

def _extract_columns_from_model(model):
    """
    Pipeline(pre=ColumnTransformer(num=..., cat=...)) から
    学習時に想定した列名を吸い出す。num/cat の列リストがある前提。
    """
    try:
        pre = model.named_steps["pre"]  # Pipeline 必須
        transformers = getattr(pre, "transformers", None) or getattr(pre, "transformers_", None)
        required = []
        numeric = set()
        for name, _trans, cols in transformers:
            if isinstance(cols, (list, tuple)):
                required.extend(list(cols))
                if name == "num":
                    numeric.update(cols)
        return list(required), numeric
    except Exception:
        # 最悪スキーマ抽出に失敗しても API は立ち上げる
        return [], set()

def load_model(path: str = MODEL_PATH):
    global _model, _REQUIRED_COLS, _NUMERIC_COLS
    with _lock:
        m = joblib.load(path)
        _model = m
        _REQUIRED_COLS, _NUMERIC_COLS = _extract_columns_from_model(m)
    return _model

def _normalize_row(features: dict) -> pd.DataFrame:
    """
    学習スキーマに合わせて不足列を補完し、数値列は numeric に強制変換。
    余計な列は黙って捨てる。列順も学習時に合わせる。
    """
    if not _REQUIRED_COLS:
        # 最悪時は来たキーをそのまま使う（本質的には推奨しない）
        X = pd.DataFrame([features])
        return X

    row = {col: features.get(col, None) for col in _REQUIRED_COLS}
    X = pd.DataFrame([row], columns=_REQUIRED_COLS)
    for col in _NUMERIC_COLS:
        if col in X.columns:
            X[col] = pd.to_numeric(X[col], errors="coerce")
    return X

class Row(BaseModel):
    features: dict  # 学習時の列名で渡す（不足は自動補完）

@app.on_event("startup")
def _startup():
    load_model()

@app.get("/health")
def health():
    return {
        "status": "ok",
        "model": os.path.basename(MODEL_PATH),
        "ts": time.time(),
        "cols": len(_REQUIRED_COLS) or None,
    }

@app.get("/schema")
def schema():
    return {
        "required_columns": _REQUIRED_COLS,
        "numeric_columns": sorted(_NUMERIC_COLS),
    }

@app.post("/predict")
def predict(item: Row):
    if _model is None:
        load_model()
    X = _normalize_row(item.features)
    proba = getattr(_model, "predict_proba", None)
    if proba:
        return {"pred_proba": float(proba(X)[:, 1][0])}
    return {"pred": _model.predict(X)[0]}

@app.post("/reload")
def reload_model():
    load_model()
    return {"status": "reloaded", "model": os.path.basename(MODEL_PATH)}

class Rows(BaseModel):
    rows: list[dict]
@app.post("/predict_batch")
def predict_batch(items: Rows):
    X = pd.DataFrame(items.rows)
    X = pd.concat([_normalize_row(r) for r in items.rows], ignore_index=True)
    proba = _model.predict_proba(X)[:,1].tolist()
    return {"pred_proba": proba}
