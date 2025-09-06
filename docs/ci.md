## CI

- トリガー: Push/PR/手動
- 環境: Ubuntu, Python 3.12, `libgomp1`
- インストール: `pip install -e .[dev]`
- スモーク: `tests/test_api_smoke.py`, `tests/test_train.py::test_train_builtin_fast`
- 低スレッド: `OMP_NUM_THREADS=1` 等で安定化
- Docker build（pushなし）
- Concurrency とタイムアウト設定あり