# Changelog

## 2025-09-07

### Infra / ECR
- GitHub Actions `release-ecr.yml` を整備（OIDC で AssumeRole、手動/タグ `v*` トリガ）。
- 環境 `ecr-prod` を作成し、`AWS_REGION=us-west-2`、`AWS_ROLE_TO_ASSUME=<IAM Role ARN>`、`ECR_REPO=mlops-sklearn-portfolio` を設定。
- ワークフローを実行し、ECR へ以下をプッシュ:
  - `<account>.dkr.ecr.us-west-2.amazonaws.com/mlops-sklearn-portfolio:v20250907-1`
  - `<account>.dkr.ecr.us-west-2.amazonaws.com/mlops-sklearn-portfolio:latest`
- ECR のスキャンは完了。重大/高は 0（中: 1）で検出なし。

### Artifacts / S3（“モデル棚”）
- `push-s3.yml` を追加（OIDC 認証で S3 に models/artifacts/logs を同期）。
- 初回の NoSuchBucket を解消し、バケット `s3://<BUCKET>/mlops-sklearn-portfolio` を使用。
- スナップショット: `snapshots/<UTC>/`、ミラー: `latest/` を更新。
- `artifacts/manifest.json` を生成し、SHA256/サイズ/生成時刻を保存。

### Build & Ops（Makefile/CI）
- `train` ターゲットの競合を解消。CI では `tee` で標準出力にログを流しつつファイル保存。
- 追加/整備:
  - `manifest`, `s3-push`, `s3-pull`, `ecr-login`, `docker-push`
  - venv スタンプ `venv/.ok` と `deps` ターゲット
  - BLAS 内スレ固定と低優先度実行を既定化
- CI（`release-ecr.yml` / `push-s3.yml`）は OIDC 経由で実行可能な状態に。

### API / 運用
- Docker 実運用化の手順を README に追記（`--workers 2` 推奨）。
- `/reload?path=...` によるモデル切替の実地確認を追加（adult/credit-g で動作確認）。
- P50/P95 計測手順（`williamyeh/hey` コンテナ）を README に追加。結果貼り付け用のテンプレも記載。

### Training（結果）
- `adult` を full で複数回実行（seed 変更の追試準備）。
  - 代表ログ（JST）:
    - `AUC=0.9257 / ACC=0.8726 / best={'lr':0.1,'max_depth':4,'leaf':31} / 18s`
    - `AUC=0.9255 / ACC=0.8707 / best={'lr':0.1,'max_depth':4,'leaf':31} / 18s`
    - `AUC=0.9259 / ACC=0.8729 / best={'lr':0.1,'max_depth':4,'leaf':31} / 18s`
    - `AUC=0.9262 / ACC=0.8719 / best={'lr':0.1,'max_depth':4,'leaf':31} / 22s`
    - `AUC=0.9256 / ACC=0.8706 / best={'lr':0.1,'max_depth':4,'leaf':31} / 18s`
- `artifacts/summary_openml_adult.json` と `models/model_openml_adult.joblib` を更新。

### Docs
- README に以下を追記・整理:
  - ECR へのリリース手順と成功スクリーンショット
  - S3 モデル棚（`models/<ver>/` と `models/latest/`）の運用メモ
  - ベンチ手順（RPS/Avg/P50/P95 の抜粋方法）
  - Docker 起動例と `/reload` 切替例

**Breaking Changes:** なし


## 2025-09-06
- 学習サマリに git_commit/python/sklearn/pandas を記録
- artifacts/manifest.json（SHA256/サイズ）
- API: /predict_batch, /reload?path=… と JSON1行ログ
- CI: slow マーカー登録、テスト＆Docker build 追加
- Docker 化（python:3.12-slim）

## 2025-09-02
- `adult`/`credit-g` full 実行、成果物反映。ログ運用・終了判定・スリープ抑止を整備。

## 2025-09-01
- リポ初期化、`breast_cancer` スモーク。