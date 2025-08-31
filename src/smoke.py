# src/smoke.py  ── scikit-learn 正式APIのみ版
import json, time, os
from joblib import dump, Memory
from threadpoolctl import threadpool_limits
from sklearn.datasets import load_breast_cancer
from sklearn.model_selection import StratifiedKFold, cross_val_score
from sklearn.compose import ColumnTransformer
from sklearn.pipeline import Pipeline
from sklearn.impute import SimpleImputer
from sklearn.preprocessing import StandardScaler
from sklearn.ensemble import HistGradientBoostingClassifier

# 並列度は環境変数で調整（デフォルト8）
N_JOBS = int(os.environ.get("N_JOBS", "8"))

Xy = load_breast_cancer(as_frame=True)
X, y = Xy.data, Xy.target
num_cols = X.columns

pre = ColumnTransformer([
    ("num", Pipeline([("imp", SimpleImputer()), ("sc", StandardScaler())]), num_cols)
])

pipe = Pipeline(
    [("pre", pre), ("clf", HistGradientBoostingClassifier(random_state=42))],
    memory=Memory("cache")
)

cv = StratifiedKFold(n_splits=2, shuffle=True, random_state=42)

os.makedirs("artifacts", exist_ok=True)
os.makedirs("models", exist_ok=True)

t0 = time.time()
# 内側BLASの並列は1にして外側(n_jobs)と競合させない
with threadpool_limits(1):
    scores = cross_val_score(
        pipe, X, y, cv=cv, scoring="roc_auc", n_jobs=N_JOBS, verbose=0
    )
elapsed = round(time.time() - t0, 2)

# 全データで一度fitして保存（推論テスト用）
pipe.fit(X, y)
dump(pipe, "models/model.joblib")

with open("artifacts/summary.json", "w") as f:
    json.dump(
        {"auc_mean": float(scores.mean()),
         "auc_std": float(scores.std()),
         "elapsed_sec": elapsed},
        f, indent=2
    )

print("SMOKE OK | AUC:", round(scores.mean(), 4), "| time(s):", elapsed)
