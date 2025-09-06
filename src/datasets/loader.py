from __future__ import annotations
from sklearn.datasets import fetch_openml, load_breast_cancer
import pandas as pd
from typing import Tuple

# OpenMLキャッシュの場所を統一
OPENML_CACHE = "data/openml_cache"

def _to_numeric(df: pd.DataFrame, cols) -> None:
    for col in cols:
        if col in df.columns:
            df[col] = pd.to_numeric(df[col], errors="coerce")

def load_dataset(name: str) -> Tuple[pd.DataFrame, pd.Series, str]:
    """
    返り値: (X, y, dsname)
    import 時に外部アクセスしない。必要なときだけ fetch_openml する。
    """
    if name == "builtin":
        data = load_breast_cancer(as_frame=True)
        df = data.frame.copy()
        y = df.pop("target")
        return df, y, "builtin_breast_cancer"

    if name == "adult":
        Xy = fetch_openml("adult", version=2, as_frame=True, data_home=OPENML_CACHE)
        df = Xy.frame.copy()
        # 目的変数
        y = df.pop("class").astype(str).str.strip().map({">50K": 1, "<=50K": 0}).astype("int8")
        # 数値に直す列
        _to_numeric(df, ["age","fnlwgt","education-num","capital-gain","capital-loss","hours-per-week"])
        return df, y, "openml_adult"

    if name == "credit-g":
        Xy = fetch_openml("credit-g", version=1, as_frame=True, data_home=OPENML_CACHE)
        df = Xy.frame.copy()
        y = df.pop("class").astype(str).map({"good": 1, "bad": 0}).astype("int8")
        return df, y, "openml_credit_g"

    if name == "local":
        df = pd.read_csv("data/train.csv")
        y = df.pop("target")
        return df, y, "local_csv"

    raise ValueError(f"unknown dataset: {name}")
