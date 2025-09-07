## CI

- トリガー: Push/PR/手動
- 環境: Ubuntu, Python 3.12, `libgomp1`
- インストール: `pip install -e .[dev]`
- スモーク: `tests/test_api_smoke.py`, `tests/test_train.py::test_train_builtin_fast`
- 低スレッド: `OMP_NUM_THREADS=1` 等で安定化
- Docker build（pushなし）
- Concurrency とタイムアウト設定あり

## ECR

運用方針: ECR push は GitHub Actions からのみ（ローカル鍵を持たない）

手順:

1. `git tag vYYYYMMDD-N && git push origin --tags`

2. Actions の `Release to ECR` を承認

3. ECR: `us-west-2` の `${account}.dkr.ecr.us-west-2.amazonaws.com/mlops-sklearn-portfolio:{tag,latest}`

検証: `aws ecr describe-images --repository-name mlops-sklearn-portfolio --region us-west-2`