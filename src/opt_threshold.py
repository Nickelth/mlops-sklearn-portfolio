# src/opt_threshold.py
"""
PR曲線からF1最大となる閾値を求めて JSON 保存。
Usage:
  python -u src/opt_threshold.py --dataset adult
  python -u src/opt_threshold.py --dataset credit-g --model-path models/model_openml_credit_g.joblib
"""
from __future__ import annotations
import argparse, json, os, time, math
import numpy as np
import pandas as pd
from joblib import load
from sklearn.metrics import precision_recall_curve
from sklearn.model_selection import train_test_split

from datasets import load_dataset  # 既存のローダを利用

def best_threshold_f1(y_true: np.ndarray, scores: np.ndarray):
    # precision_recall_curve は thresholds の長さが len(precision)-1
    p, r, t = precision_recall_curve(y_true, scores)
    f1 = (2 * p * r) / (p + r + 1e-12)
    # 最後の点は threshold 無しなので除外
    idx = int(np.nanargmax(f1[:-1])) if len(t) else 0
    return {
        "threshold": float(t[idx]) if len(t) else 0.5,
        "precision": float(p[idx]),
        "recall": float(r[idx]),
        "f1": float(f1[idx]),
        "curve_points": len(t)
    }

def default_model_path(dsname: str) -> str:
    # train.py の保存規約に合わせる
    return {
        "openml_adult": "models/model_openml_adult.joblib",
        "openml_credit_g": "models/model_openml_credit_g.joblib",
        "builtin_breast_cancer": "models/model_builtin_breast_cancer.joblib",
        "local_csv": "models/model_local_csv.joblib",
    }.get(dsname, f"models/model_{dsname}.joblib")

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dataset", choices=["builtin", "adult", "credit-g", "local"], required=True)
    ap.add_argument("--model-path", default=None)
    ap.add_argument("--out", default=None)
    args = ap.parse_args()

    X, y, dsname = load_dataset(args.dataset)

    # train.py と同じ分割規約で holdout を作る（再現性前提）
    Xtr, Xte, ytr, yte = train_test_split(
        X, y, test_size=0.2, stratify=y, random_state=42
    )

    model_path = args.model_path or default_model_path(dsname)
    if not os.path.exists(model_path):
        raise SystemExit(f"model not found: {model_path}")

    model = load(model_path)
    if hasattr(model, "predict_proba"):
        scores = model.predict_proba(pd.DataFrame(Xte))[:, 1]
    elif hasattr(model, "decision_function"):
        scores = model.decision_function(pd.DataFrame(Xte))
        # シグモイドに寄せるかは好み。ここではそのまま使う。
    else:
        # 苦肉の策。分類子なら {0,1} をscore扱い
        scores = model.predict(pd.DataFrame(Xte))

    y_true = np.asarray(yte).astype(int)
    stat = best_threshold_f1(y_true, np.asarray(scores, dtype=float))

    out_dir = "artifacts"
    os.makedirs(out_dir, exist_ok=True)
    out_file = args.out or os.path.join(out_dir, f"threshold_{dsname}.json")

    payload = {
        "dataset": dsname,
        "model_path": os.path.basename(model_path),
        "threshold": stat["threshold"],
        "precision": stat["precision"],
        "recall": stat["recall"],
        "f1": stat["f1"],
        "curve_points": stat["curve_points"],
        "n_pos": int(y_true.sum()),
        "n_neg": int((y_true == 0).sum()),
        "generated_at": int(time.time())
    }
    with open(out_file, "w") as f:
        json.dump(payload, f, indent=2)

    # 共通名にも出す（シンボリックリンク。失敗したらコピー）
    link = os.path.join(out_dir, "threshold.json")
    try:
        if os.path.islink(link) or os.path.exists(link):
            os.unlink(link)
        os.symlink(os.path.basename(out_file), link)
    except Exception:
        # Windowsや権限で失敗したら上書きコピー
        with open(link, "w") as f:
            json.dump(payload, f, indent=2)

    print(f"[THRESH] ds={dsname} thr={payload['threshold']:.4f} "
          f"F1={payload['f1']:.4f} P={payload['precision']:.4f} R={payload['recall']:.4f} "
          f"n_pos={payload['n_pos']} n_neg={payload['n_neg']} -> {out_file}")

if __name__ == "__main__":
    main()
