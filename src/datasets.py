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
        Xy = fetch_openml("adult", as_frame=True, data_home="data/openml_cache")
        df = Xy.frame.copy()
        y = df.pop("class").map({">50K":1, "<=50K":0}).astype("int8")
        return df, y, "openml_adult"
    if name == "credit-g":
        Xy = fetch_openml("credit-g", as_frame=True, data_home="data/openml_cache")
        df = Xy.frame.copy()
        y = df.pop("class").map({"good":1, "bad":0}).astype("int8")
        return df, y, "openml_credit_g"
    if name == "local":
        df = pd.read_csv("data/train.csv")
        y = df.pop("target")
        return df, y, "local_csv"
    raise ValueError(f"unknown dataset: {name}")
