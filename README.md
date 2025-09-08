## mlops-sklearn-portfolio

scikit-learn + Pipeline で表形式MLを**学習→成果物→推論API→コンテナ**まで最短導線で通すポートフォリオ。

[![CI](https://github.com/Nickelth/mlops-sklearn-portfolio/actions/workflows/ci.yml/badge.svg)](../../actions)
[![Release to ECR](https://github.com/Nickelth/mlops-sklearn-portfolio/actions/workflows/release-ecr.yml/badge.svg)](../../actions)
[![Publish Models to S3 Bucket](https://github.com/Nickelth/mlops-sklearn-portfolio/actions/workflows/push-s3.yml/badge.svg)](../../actions)

## ルール

* README は**300行未満**、図鑑は docs。
* 詳細なコマンド羅列は `docs/training.md` と `docs/ops.md` に置く。
* 実行結果スクショや長表は S3 の成果物か `docs/` にリンクだけ。
* 変更履歴は **CHANGELOG** に一元化。README の「変更履歴」セクションは禁止。

### Quick Start
```bash
make init EXTRAS=[dev]          # 依存
make train-full DS=adult        # 学習
make check                      # 成果物/ログ 確認
make docker-build && make docker-run   # API (Docker)
curl -s localhost:8000/health
```

### Docs

* アーキテクチャと課題設定: [docs/overview.md](docs/overview.md)
* 学習/実行/長時間運用: [docs/training.md](docs/training.md)
* API（/health, /schema, /predict, /predict\_batch, /reload）: [docs/api.md](docs/api.md)
* Docker: [docs/docker.md](docs/docker.md)
* CI: [docs/ci.md](docs/ci.md)
* 運用・S3同期・ログ: [docs/ops.md](docs/ops.md)
* 激甚時撤収: [severe\_disaster\_manual.md](docs/severe_disaster_manual.md)
* 変更履歴: [CHANGELOG.md](CHANGELOG.md)

### ディレクトリ

```
api/  src/  models/  artifacts/  logs/  tests/  docs/
```

- 「workers=1/2 の差」ひとこと比較（RPSの伸びと P95 の変化だけ）
- /reload の切替所要時間（ms）
- S3 latest/ とスナップショットの両立運用方針（既に書いてるならリンクだけ）

### 閾値最適化（PR曲線×F1最大）

- `make threshold DS=adult` で holdout 上の PR 曲線から F1 最大となる閾値を算出。
- 出力: `artifacts/threshold_<dataset>.json` と `artifacts/threshold.json`（共通名）。
- 将来: API 側で `?mode=binary` 時にこの閾値を使用する切替を追加予定。
