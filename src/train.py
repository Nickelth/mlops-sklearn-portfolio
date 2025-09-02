# src/train.py
"""
Usage:
  python -u src/train.py --dataset builtin --mode fast
  python -u src/train.py --dataset adult   --mode full
  python -u src/train.py --dataset credit-g --mode full
"""

import os, json, time, argparse, math
import pandas as pd
from joblib import dump, Memory
from threadpoolctl import threadpool_limits

# 検索系（Successive Halving）
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

from datasets import load_dataset  # 同じsrc配下

def build_pipeline():
    # 実データの列型に応じて前処理を組む
    num_sel = ["number"]

    def split_columns(df: pd.DataFrame):
        num_cols = df.select_dtypes(include=num_sel).columns
        cat_cols = df.select_dtypes(exclude=num_sel).columns
        return list(num_cols), list(cat_cols)

    def make_preprocessor(df: pd.DataFrame):
        num_cols, cat_cols = split_columns(df)
        try:
            ohe = OneHotEncoder(handle_unknown="ignore", sparse_output=False, dtype="float32")
        except TypeError:
            ohe = OneHotEncoder(handle_unknown="ignore", sparse=False, dtype="float32")
        pre = ColumnTransformer([
            ("num", Pipeline([("imp", SimpleImputer()), ("sc", StandardScaler())]), num_cols),
            ("cat", Pipeline([("imp", SimpleImputer(strategy="most_frequent")), ("oh", ohe)]), cat_cols)
        ])
        return pre

    return make_preprocessor

def compute_min_resources(y: pd.Series, n_splits: int, mode: str) -> int | None:
    """
    小規模データ（~1200行以下）では Successive Halving の初期サンプルが小さすぎると
    foldの検証側が片クラスになりやすい。最小リソースを安全側に引き上げる。
    でかいデータは None を返して sklearn の自動推定に任せる。
    """
    N = len(y)
    if N > 1200:
        return None  # adult 等は自動推定の方が安定

    # 少数派率を使って「各foldに少数派が最低1つ入る」期待条件から下限を作る。
    freq = y.value_counts(normalize=True)
    f_min = float(freq.min()) if not freq.empty else 0.5
    # “2サンプル/ fold は欲しい”という保守的な下限
    base = math.ceil((2 * n_splits) / max(f_min, 1e-6))
    # fast は少し下げ、full は余裕を持たせる
    floor = 120 if mode == "fast" else 250
    m = max(floor, base)
    # 上限はデータサイズ以内にクリップ
    return min(m, N)

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dataset", choices=["builtin","adult","credit-g","local"], default="builtin")
    ap.add_argument("--mode",    choices=["fast","full"], default="fast")
    args = ap.parse_args()

    X, y, dsname = load_dataset(args.dataset)

    # 前処理器は列を見てから組む
    make_preprocessor = build_pipeline()
    pre = make_preprocessor(X)

    pipe = Pipeline(
        steps=[("pre", pre), ("clf", HistGradientBoostingClassifier(random_state=42))],
        memory=Memory("cache", verbose=0)  # 重い前処理をキャッシュ
    )

    # 探索空間（まずは控えめ）
    param_grid = {
        "clf__max_depth": [None, 4, 8],
        "clf__learning_rate": [0.05, 0.1, 0.2],
        "clf__max_leaf_nodes": [31, 63, 127],
    }

    # 速度/品質の切替
    n_splits = 3 if args.mode == "fast" else 5
    factor   = 2 if args.mode == "fast" else 3
    n_jobs   = 8  # i7-9700 実コア

    # 層化CV（fold内のクラス偏りを抑える）
    cv = StratifiedKFold(n_splits=n_splits, shuffle=True, random_state=42)

    # 小規模データは最初から十分なサンプルで開始
    min_res = compute_min_resources(y, n_splits, args.mode)

    # 並列競合を避ける（外=CV並列, 内=BLASは1）
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
            error_score=0.0,   # 未定義スコアは0扱いで静かに足切り
            verbose=1,
            random_state=42,   # SHのサンプリング再現性
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

    os.makedirs("artifacts", exist_ok=True)
    os.makedirs("models", exist_ok=True)

    model_path = f"models/model_{dsname}.joblib"
    dump(search.best_estimator_, model_path)

    # cvの生データと要約を保存
    pd.DataFrame(search.cv_results_).to_csv(f"artifacts/cv_results_{dsname}.csv", index=False)
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
        }, f, indent=2)

    print(f"[RESULT] ds={dsname} mode={args.mode} AUC={auc:.4f} ACC={acc:.4f} "
          f"best={search.best_params_} elapsed_sec={elapsed}")

if __name__ == "__main__":
    main()
