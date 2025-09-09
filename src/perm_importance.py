# src/perm_importance.py
"""
Permutation Importance を原始列単位（元のDataFrame列ごと）で計算し、
PNG/CSV/JSON を artifacts/ に吐く。学習済みパイプラインは models/ からロード。
Usage:
  python -u src/perm_importance.py --dataset adult
  python -u src/perm_importance.py --dataset credit-g --n-repeats 10 --max-samples 5000
"""
from __future__ import annotations
import argparse, os, time, json
import numpy as np
import pandas as pd
from joblib import load
from threadpoolctl import threadpool_limits
from sklearn.metrics import get_scorer
from sklearn.model_selection import train_test_split

from datasets import load_dataset  # 既存

def default_model_path(dsname: str) -> str:
    return {
        "openml_adult": "models/model_openml_adult.joblib",
        "openml_credit_g": "models/model_openml_credit_g.joblib",
        "builtin_breast_cancer": "models/model_builtin_breast_cancer.joblib",
        "local_csv": "models/model_local_csv.joblib",
    }.get(dsname, f"models/model_{dsname}.joblib")

def compute_importance(model, X: pd.DataFrame, y: pd.Series, *, n_repeats: int, scorer_name: str, max_samples: int | None, seed: int = 42):
    rng = np.random.RandomState(seed)
    if max_samples and len(X) > max_samples:
        idx = rng.choice(len(X), size=max_samples, replace=False)
        X = X.iloc[idx].copy()
        y = y.iloc[idx].copy()
    else:
        X = X.copy()
        y = y.copy()

    # 列一覧（元データの列単位で測るので爆散したOneHotに比べて軽量・解釈容易）
    num_cols = list(X.select_dtypes(include=["number"]).columns)
    all_cols = list(X.columns)
    scorer = get_scorer(scorer_name)

    with threadpool_limits(1):
        baseline = float(scorer(model, X, y))

    results = []
    for col in all_cols:
        drops = []
        for r in range(n_repeats):
            Xp = X.copy()
            # 同列内でシャッフル（未知カテゴリは発生しない）
            Xp[col] = Xp[col].sample(frac=1.0, random_state=rng.randint(0, 2**31 - 1)).values
            with threadpool_limits(1):
                s = float(scorer(model, Xp, y))
            drops.append(baseline - s)
        results.append({
            "feature": col,
            "mean_drop": float(np.mean(drops)),
            "std_drop": float(np.std(drops)),
        })

    results.sort(key=lambda d: d["mean_drop"], reverse=True)
    return baseline, num_cols, results

def save_plot_png(results, out_png, scorer_name: str):
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt

    feats = [r["feature"] for r in results]
    means = [r["mean_drop"] for r in results]
    stds  = [r["std_drop"] for r in results]

    h = max(4, 0.4 * len(feats) + 1)
    fig, ax = plt.subplots(figsize=(9, h))
    y = np.arange(len(feats))
    ax.barh(y, means, xerr=stds, align="center")
    ax.set_yticks(y, labels=feats)
    ax.invert_yaxis()
    ax.set_xlabel(f"Permutation importance (Δ{scorer_name} = baseline - permuted)")
    ax.set_title(f"Permutation importance ({scorer_name})")
    fig.tight_layout()
    fig.savefig(out_png, dpi=200)
    plt.close(fig)

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dataset", choices=["builtin", "adult", "credit-g", "local"], required=True)
    ap.add_argument("--model-path", default=None)
    ap.add_argument("--n-repeats", type=int, default=10)
    ap.add_argument("--max-samples", type=int, default=5000)
    ap.add_argument("--scorer", default="roc_auc")
    args = ap.parse_args()

    X, y, dsname = load_dataset(args.dataset)
    # train.py と同じ holdout
    Xtr, Xte, ytr, yte = train_test_split(X, y, test_size=0.2, stratify=y, random_state=42)

    model_path = args.model_path or default_model_path(dsname)
    if not os.path.exists(model_path):
        raise SystemExit(f"model not found: {model_path}")
    model = load(model_path)

    baseline, num_cols, results = compute_importance(
        model, Xte, yte,
        n_repeats=args.n_repeats, scorer_name=args.scorer, max_samples=args.max_samples
    )

    os.makedirs("artifacts", exist_ok=True)
    stem = f"perm_importance_{dsname}"
    out_png = os.path.join("artifacts", f"{stem}.png")
    out_csv = os.path.join("artifacts", f"{stem}.csv")
    out_json= os.path.join("artifacts", f"{stem}.json")

    # 出力
    save_plot_png(results, out_png, args.scorer)
    pd.DataFrame(results).to_csv(out_csv, index=False)
    meta = {
        "dataset": dsname,
        "model_path": os.path.basename(model_path),
        "scorer": args.scorer,
        "baseline_score": baseline,
        "n_repeats": args.n_repeats,
        "max_samples": args.max_samples,
        "generated_at": int(time.time()),
        "top3": results[:3],
    }
    with open(out_json, "w") as f:
        json.dump(meta, f, indent=2)

    print(f"[PERM] ds={dsname} baseline={baseline:.4f} repeats={args.n_repeats} "
          f"features={len(results)} -> {out_png}")

if __name__ == "__main__":
    main()
