# Overview
- 目的: 再現性の高い学習ジョブと軽量推論API。ECSデプロイは別進行。
- タスク: 学習/評価/成果物化/API化/コンテナ化/CI。
- データ: OpenML `adult`（所得2値）/`credit-g`（与信）＋内蔵 `breast_cancer`（スモーク）。

## 前処理
- 数値: SimpleImputer → StandardScaler
- カテゴリ: SimpleImputer(most_frequent) → OneHotEncoder(ignore)
- ColumnTransformer + Pipeline でリーク防止。

## 指標
- 主: ROC-AUC、補助: Accuracy。必要に応じ較正。

## 成果物
- `models/model_*.joblib`
- `artifacts/summary_*.json`（git_commit/python/sklearn/pandas含む）
- `artifacts/cv_results_*.csv`