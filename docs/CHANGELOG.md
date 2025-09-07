# Changelog

## 2025-09-07

### Added
- **GitHub Actions: `release-ecr.yml`**  
  タグ push（`v*`）および手動実行で Docker イメージを Build→ECR へ Push。
- **GitHub Actions: `push-s3.yml`**  
  `models/` と `artifacts/` を S3 に同期。`manifest.json` を自動生成し、スナップショットと `latest/` を更新。
- **Makefile ターゲット**  
  `deps`（依存自動インストール）、`train-file`（静音学習）、`manifest`、`s3-push`、`s3-pull`、`ecr-login`、`docker-push` を追加。
- **スクリプト**: `scripts/generate_manifest.py`（SHA256・サイズを収集して `artifacts/manifest.json` を生成）。

### Changed
- **学習系**: 既存の `train` を整理し、`deps` に依存させた上でログを `tee` で標準出力にも流す方式に変更。  
  `train-fast` / `train-full` / `train-both` は従来どおり `train` を呼び出し。
- **CI 実行の堅牢化**: 依存インストール（`pip install -e .[dev]`）と失敗時の学習ログ出力（tail）を追加。

### Infrastructure
- **ECR**: `us-west-2` のリポジトリ（`mlops-sklearn-portfolio`）に Push 成功。`latest` とリリースタグ（例 `v20250907-1`）で登録。イメージスキャン完了。
- **GitHub Environment**: `ecr-prod` を作成し、OIDC でのロール引受を構成。  
  リポジトリ Variables に `AWS_REGION` / `AWS_ROLE_TO_ASSUME` / `S3_BUCKET` を設定。
- **S3 “モデル棚”**: CI と Make からスナップショット（UTC 時刻）と `latest/` への同期を運用開始。

### Fixed
- **OIDC 失敗 (`AssumeRoleWithWebIdentity`)**  
  信頼ポリシー・変数設定を見直し、Roles/Environment/Vars の整合を取って解消。

### Notes
- ローカルと CI の両経路で S3 同期が可能に（CI は学習→同期、ローカルは `make s3-push`）。
- 既存機能や API 仕様の破壊的変更なし。


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