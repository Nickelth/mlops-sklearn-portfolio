# 先頭のimportsに足してOK
import os, sys, json, time, argparse, math
import pandas as pd
from pathlib import Path
from joblib import dump, load, Memory
from threadpoolctl import threadpool_limits

from sklearn.model_selection import train_test_split
from sklearn.compose import ColumnTransformer
from sklearn.pipeline import Pipeline
from sklearn.impute import SimpleImputer
from sklearn.preprocessing import OneHotEncoder, StandardScaler
from sklearn.ensemble import HistGradientBoostingClassifier
from sklearn.metrics import roc_auc_score
from sklearn.inspection import permutation_importance

from datasets import load_dataset  # 既存のやつ

MODELS_DIR = Path("models")
ART_DIR    = Path("artifacts")
MODELS_DIR.mkdir(exist_ok=True)
ART_DIR.mkdir(exist_ok=True)

def build_preprocessor(df: pd.DataFrame) -> ColumnTransformer:
    num_cols = list(df.select_dtypes(include=["number"]).columns)
    cat_cols = list(df.select_dtypes(exclude=["number"]).columns)
    try:
        ohe = OneHotEncoder(handle_unknown="ignore", sparse_output=False, dtype="float32")
    except TypeError:
        ohe = OneHotEncoder(handle_unknown="ignore", sparse=False, dtype="float32")
    return ColumnTransformer([
        ("num", Pipeline([("imp", SimpleImputer()), ("sc", StandardScaler())]), num_cols),
        ("cat", Pipeline([("imp", SimpleImputer(strategy="most_frequent")), ("oh", ohe)]), cat_cols),
    ])

def ensure_model(dataset: str) -> tuple[Pipeline, pd.DataFrame, pd.Series, str]:
    X, y, dsname = load_dataset(dataset)
    model_path = MODELS_DIR / f"model_{dsname}.joblib"
    if model_path.exists():
        pipe = load(model_path)
        return pipe, X, y, dsname

    # 無ければ軽量に学習して保存（CI/初回実行向け）
    pre = build_preprocessor(X)
    pipe = Pipeline(
        steps=[("pre", pre), ("clf", HistGradientBoostingClassifier(random_state=42))],
        memory=Memory("cache", verbose=0),
    )
    with threadpool_limits(1):
        Xtr, Xte, ytr, yte = train_test_split(X, y, test_size=0.2, stratify=y, random_state=42)
        pipe.fit(Xtr, ytr)
        # ついでにベースラインAUCを保存
        base_auc = float(roc_auc_score(yte, pipe.predict_proba(Xte)[:, 1]))
    dump(pipe, model_path)
    print(f"[perm] trained lightweight model and saved -> {model_path} | baseline AUC={base_auc:.4f}", file=sys.stderr)
    return pipe, X, y, dsname

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dataset", required=True, choices=["builtin","adult","credit-g","local"])
    ap.add_argument("--n-repeats", type=int, default=8)
    ap.add_argument("--max-samples", type=int, default=5000)
    args = ap.parse_args()

    pipe, X, y, dsname = ensure_model(args.dataset)

    # 評価用ホールドアウト
    Xtr, Xte, ytr, yte = train_test_split(X, y, test_size=0.2, stratify=y, random_state=42)

    with threadpool_limits(1):
        base = float(roc_auc_score(yte, pipe.predict_proba(Xte)[:, 1]))
        r = permutation_importance(
            pipe, Xte, yte,
            n_repeats=args.n_repeats,
            scoring="roc_auc",
            random_state=42,
            n_jobs=1,
            max_samples=args.max_samples
        )

    # 保存（PNG/CSV/JSON）
    stem = f"perm_importance_{dsname}"
    # CSV
    import numpy as np
    cols = list(X.columns)
    df = pd.DataFrame({
        "feature": cols,
        "importance_mean": r.importances_mean,
        "importance_std": r.importances_std,
    }).sort_values("importance_mean", ascending=False)
    df.to_csv(ART_DIR / f"{stem}.csv", index=False)

    # PNG（縦長棒）
    import matplotlib.pyplot as plt
    plt.figure(figsize=(8, max(3, 0.35*len(cols))))
    plt.errorbar(df["importance_mean"], df["feature"], xerr=df["importance_std"], fmt="o")
    plt.xlabel("AUC decrease (mean ± std)")
    plt.ylabel("feature")
    plt.tight_layout()
    plt.savefig(ART_DIR / f"{stem}.png")
    plt.close()

    # JSONメタ
    meta = {
        "dataset": dsname,
        "baseline_score": base,
        "n_repeats": args.n_repeats,
        "max_samples": args.max_samples,
        "generated_at": int(time.time()),
        "top3": df.head(3).to_dict(orient="records"),
    }
    (ART_DIR / f"{stem}.json").write_text(json.dumps(meta, indent=2))
    print(f"[PERM] ds={dsname} baseline={base:.4f} repeats={args.n_repeats} features={len(cols)} -> {ART_DIR/(stem+'.png')}")
    
if __name__ == "__main__":
    main()
