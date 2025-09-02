from sklearn.datasets import fetch_openml, load_breast_cancer
import pandas as pd
from pathlib import Path

def load_dataset(name: str):
    if name == "builtin":
        data = load_breast_cancer(as_frame=True)
        df = data.frame.copy()
        y = df.pop("target")
        return df, y, "builtin_breast_cancer"
    if name == "adult":
        Xy = fetch_openml("adult", version=2, as_frame=True, data_home="data/openml_cache")
        df = Xy.frame.copy()
        y = df.pop("class").str.strip().map({">50K":1, "<=50K":0}).astype("int8")
        for col in ["age","fnlwgt","education-num","capital-gain","capital-loss","hours-per-week"]:
            if col in df.columns:
                df[col] = pd.to_numeric(df[col], errors="coerce")
        return df, y, "openml_adult"
    if name == "credit-g":
        Xy = fetch_openml("credit-g", version=1, as_frame=True, data_home="data/openml_cache")
        df = Xy.frame.copy()
        y = df.pop("class").map({"good":1, "bad":0}).astype("int8")
        return df, y, "openml_credit_g"
    if name == "local":
        df = pd.read_csv("data/train.csv")
        y = df.pop("target")
        return df, y, "local_csv"
    raise ValueError(f"unknown dataset: {name}")

def load_openml(name: str, version: int):
    return fetch_openml(name=name, version=version, as_frame=True,
                        cache=True, data_home="data_cache")

df_adult = load_openml("adult", version=2)      # バージョン固定推奨
df_credit = load_openml("credit-g", version=1)
