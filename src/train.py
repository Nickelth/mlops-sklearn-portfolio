# src/train.py
"""
Usage:
  python -u src/train.py --dataset builtin  --mode fast
  python -u src/train.py --dataset adult    --mode full
  python -u src/train.py --dataset credit-g --mode full
"""

from __future__ import annotations
import os, json, time, argparse, math
import pandas as pd
from joblib import dump, Memory
from threadpoolctl import threadpool_limits

# Successive Halving
from sklearn.experimental import enable_halving_search_cv  # noqa: F401
from sklearn.model_selection import (
    train_test_split, HalvingGridSearchCV, StratifiedKFold
)

# 前処理パイプライン
from sklearn.compose import ColumnTransformer
from sklearn.pipeline import Pipeline
from sklearn.impute import SimpleImputer
from sklearn.preprocessing import OneHotEncoder, StandardScaler

# モデルと評価
from sklearn.ensemble import HistGradientBoostingClassifier
from sklearn.metrics import roc_auc_score, accuracy_score

from datasets import load_dataset  # パッケージ src/datasets/loader.py
# 先頭のimportに追加
import platform, subprocess, sklearn

def _git_commit() -> str | None:
    try:
        out = subprocess.check_output(["git", "rev-parse", "--short", "HEAD"], stderr=subprocess.DEVNULL, timeout=2)
        return out.decode().strip()
    except Exception:
        return None

def build_preprocessor(df: pd.DataFrame) -> ColumnTransformer:
    num_cols = list(df.select_dtypes(include=["number"]).columns)
    cat_cols = list(df.select_dtypes(exclude=["number"]).columns)

    # scikit-learn 互換（古い版は sparse_output が無い）
    try:
        ohe = OneHotEncoder(handle_unknown="ignore", sparse_output=False, dtype="float32")
    except TypeError:
        ohe = OneHotEncoder(handle_unknown="ignore", sparse=False, dtype="float32")

    pre = ColumnTransformer([
        ("num", Pipeline([("imp", SimpleImputer()), ("sc", StandardScaler())]), num_cols),
        ("cat", Pipeline([("imp", SimpleImputer(strategy="most_frequent")), ("oh", ohe)]), cat_cols),
    ])
    return pre


def compute_min_resources(y: pd.Series, n_splits: int, mode: str) -> int | None:
    """
    小規模データでは SH の初期サンプルが小さすぎると fold で片クラスになりがち。
    少数派が各foldに最低2件は入る想定で下限を引き上げる。
    """
    N = len(y)
    if N > 1200:
        return None  # 大きいデータは自動推定に任せる

    freq = y.value_counts(normalize=True)
    f_min = float(freq.min()) if not freq.empty else 0.5
    base = math.ceil((2 * n_splits) / max(f_min, 1e-6))  # foldあたり2件×n_splits
    floor = 120 if mode == "fast" else 250
    m = max(floor, base)
    return min(m, N)


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--dataset", choices=["builtin", "adult", "credit-g", "local"], default="builtin")
    ap.add_argument("--mode",    choices=["fast", "full"], default="fast")
    args = ap.parse_args()

    X, y, dsname = load_dataset(args.dataset)

    pre = build_preprocessor(X)

    pipe = Pipeline(
        steps=[("pre", pre), ("clf", HistGradientBoostingClassifier(random_state=42))],
        memory=Memory("cache", verbose=0),
    )

    # 探索空間
    param_grid = {
        "clf__max_depth": [None, 4, 8],
        "clf__learning_rate": [0.05, 0.1, 0.2],
        "clf__max_leaf_nodes": [31, 63, 127],
    }

    # 速度/品質の切替
    n_splits = 3 if args.mode == "fast" else 5
    factor   = 2 if args.mode == "fast" else 3
    n_jobs   = 8  # i7-9700 実コア

    cv = StratifiedKFold(n_splits=n_splits, shuffle=True, random_state=42)
    min_res = compute_min_resources(y, n_splits, args.mode)

    os.makedirs("artifacts", exist_ok=True)
    os.makedirs("models", exist_ok=True)

    # 外側CVだけ並列、内側BLASは1
    with threadpool_limits(limits=1):
        Xtr, Xte, ytr, yte = train_test_split(
            X, y, test_size=0.2, stratify=y, random_state=42
        )

        search_kwargs = dict(
            estimator=pipe,
            param_grid=param_grid,
            scoring="roc_auc",
            cv=cv,
            factor=factor,
            n_jobs=n_jobs,
            error_score=0.0,   # 失敗は0点で足切り
            verbose=1,
        )
        if min_res is not None:
            search_kwargs["min_resources"] = min_res

        search = HalvingGridSearchCV(**search_kwargs)

        t0 = time.time()
        search.fit(Xtr, ytr)
        elapsed = int(time.time() - t0)

        proba = search.predict_proba(Xte)[:, 1]
        auc = float(roc_auc_score(yte, proba))
        acc = float(accuracy_score(yte, search.predict(Xte)))

    model_path = f"models/model_{dsname}.joblib"
    dump(search.best_estimator_, model_path)

    pd.DataFrame(search.cv_results_).to_csv(f"artifacts/cv_results_{dsname}.csv", index=False)

    meta = {
        "git_commit": _git_commit(),
        "python": platform.python_version(),
        "sklearn": sklearn.__version__,
        "pandas": pd.__version__,
    }

    with open(f"artifacts/summary_{dsname}.json", "w") as f:
        json.dump({
            "dataset": dsname,
            "mode": args.mode,
            "auc": auc,
            "accuracy": acc,
            "best_params": search.best_params_,
            "elapsed_sec": elapsed,
            "finished_at": int(time.time()),
            "min_resources": min_res,
            "cv_splits": n_splits,
            **meta,
        }, f, indent=2)

    print(
        f"[RESULT] ds={dsname} mode={args.mode} AUC={auc:.4f} ACC={acc:.4f} "
        f"best={search.best_params_} elapsed_sec={elapsed}"
    )
    print("=== TRAIN DONE ===")


if __name__ == "__main__":
    main()
