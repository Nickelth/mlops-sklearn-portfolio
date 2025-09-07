## Ops（S3・ログ・Runbook）

### S3 同期

```bash
export S3_BUCKET=s3://<bucket>/mlops-sklearn-portfolio
make s3-push     # snapshots/<UTC>/ と latest/ 更新
make s3-pull     # latest/ を取得（SRC=... でスナップショット指定）
```

* `artifacts/manifest.json` に SHA256/サイズを記録。

## ログと確認

* 学習ログ: `logs/train-*.log`（`make check` でサマリ）
* APIログ: `logs/api-YYYYMMDD.log`（1行JSON）

## 緊急時

* 手順は `severe_disaster_manual.md` を参照（監査向け）。