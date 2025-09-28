# Changelog

## (2025-09-28)

### 目的

- エンドポイント名の不一致解消（`/health` と `/healthz` の整合）
- ログの出力先: JSON 1行を **stdout→CloudWatch** へ（ファイル併用）
- 証跡: `curl /healthz` 成功、TG Healthy スクショ、ECS イベント抜粋

### 主要変更

- **API（`api/app.py`）**
  - 構造化ログを **FileHandler + StreamHandler(stdout)** で二重出力（CloudWatch 取り込み用）。
  - `/healthz` を提供（`/health` との互換維持）、`/metrics` は既存のまま。

- **ECS/ALB**
  - （切替前確認）ALB 経由 `/healthz` が 200 を返すことを事前検証。
  - **TG ヘルスチェックを `/healthz` に切替**（`HttpCode=200-399`, interval=10s, healthy=2）。
  - `aws ecs update-service --force-new-deployment` によりローリング更新。

### 証跡

```bash
docs/evidence/
├── 20250928_014728_healthz_200.txt                 # /healthz 200（事前確認）
├── 20250928_015634_healthz_200.txt                 # /healthz 200（再確認）
├── 20250928_015656_cwlogs_boot.txt                 # Uvicorn 起動ログ/構造化ログ
├── 20250928_015656_ecs_update_force_new.txt        # 強制再デプロイ実行ログ
├── 20250928_015656_health_200.txt                  # 互換のため /health 200
├── 20250928_015656_healthz_404.txt                 # 切替手順中の一時 404（整合性確認）
├── 20250928_020535_healthz_200_pre_switch.txt      # TG 切替前の /healthz 200
├── 20250928_020553_tg_hc_switch_to_healthz.txt     # TG を /healthz へ切替
├── 20250928_020553_tg_health_after_switch.txt      # 切替後 Healthy 確認
├── 20250928_020611_ecs_events.txt                  # ECS イベント抜粋
├── 20250928_020611_healthz_200_final.txt           # 最終 /healthz 200
└── 20250928_020611_metrics_200.txt                 # /metrics 200
```

コマンドは![付録：証跡用打鍵コマンド (2025-09-28)](CHANGELOG_2025-09-28.md)を参照。

### ロールアウト

1. 新タスク（`/healthz` 提供・stdout ログ化）を **`--force-new-deployment`** で展開。
2. **切替前**に ALB 経由 `curl /healthz` で 200 を確認（互換で `/health` も 200）。
3. **TG のヘルスチェックを `/healthz` に変更** → Target Healthy を確認。
4. `/metrics` 正常応答と CloudWatch 取り込みを確認。
5. すべてのコマンド出力を `docs/evidence/*.txt` に保存し証跡化。

### リスクと対策

- **ヘルスエンドポイント混在**: しばらく `/health` と `/healthz` を併存し互換維持。ダッシュボード/ALB は `/healthz` に統一。
- **一時的な 404/Unhealthy**: 切替は **事前 200 確認 → TG 切替 → Healthy 確認** の順で最小化。必要に応じ `grace` を延長。
- **ログ重複/出力過多**: File + stdout の二重出力は保守期間限定。必要に応じてサンプリング/フィルタを適用。

### 次アクション

- ダッシュボード（CW Logs Insights + `/metrics`）で SLO 可視化。
- `/health` の段階的廃止計画（依存の有無を調査 → アナウンス → 削除）。
- TG/ALB のヘルス関連 Alarm（`UnHealthyHostCount > 0` など）を追加。

---

## ECS無停止デプロイ（2025-09-14 → 2025-09-27）

### 目的

Fargate/ECS を ALB 配下で無停止更新。証跡で可観測・再現可能に。

### 主要変更

- Infra（ecs.tf）

  - deployment_circuit_breaker=on, health_check_grace_period_seconds=60
  - task_role_arn 追加 + s3:GetObject 付与（MODEL_S3_URI）
- API（api/app.py）

  - 起動時のモデルロードを「可能なら」に緩和、S3フェッチ、/metrics 追加
- Config（pyproject.toml）

  - boto3 追加、sklearn バージョン整合（警告解消）
- Makefile

  - /tmp で Terraform 実行、tg-health / svc-events / metrics 追加

### 証跡

- ALB DNS: `<ALB_DNS>`
- `/health` 200: `docs/evidence/20250927_054140_health.txt`
- Target Health: healthy（`make tg-health` 出力）
- CloudWatch Logs: Uvicorn 起動ログ + /health アクセス記録

### ロールアウト

1. GH Actions で `:latest` push
2. `aws ecs update-service --force-new-deployment`
3. `make tg-health` が healthy になったら `make evidence && make metrics`

### リスクと対策

- モデル未配置: /predict 初回 503、/reload or 先読み実行で回避
- 依存差異: sklearn pin、Artifacts にメタ付与
- ロールバック: Circuit breaker + 旧TaskDefinitionへの手動戻し

### 次アクション

- `/metrics` をダッシュボード集約
- モデル配布に署名/ハッシュ検証

---

## 2025-09-13

### 作業
- AWS CloudShell（Amazon Linux 2023）に **Terraform v1.13.2** をユーザー単位で導入（`~/bin/terraform`）。
  - `~/.bashrc` に `export PATH="$HOME/bin:$PATH"` を追記し `source ~/.bashrc` を実行。
  - 動作確認:
    ```bash
    $ terraform -version
    Terraform v1.13.2
    on linux_amd64
    ```

### 影響・備考
- IaC 着手のための環境準備のみ。インフラ定義（`infra/` 以下）や `terraform init/plan` は次回作業で実施。

---

## 2025-09-09

### ユーティリティ新規作成

- `src/opt_threshold.py` を追加。
  - 役割: 学習に使ったのと同一ルールの `holdout` 分割で `y_true` と `score` を作り、`precision_recall_curve` から F1 最大点と閾値を算出して保存。
  - 出力: `artifacts/threshold_<ds>.json `を作成し、`artifacts/threshold.json` へもシンボリックリンク（無理ならコピー）。

### Makefile 連携

- `make threshold DS=adult` で走るターゲットを追加。
- 既存 `venv/BLAS` 設定はそのまま引き継ぎ。

### 実行 & 確認

- `make threshold DS=adult`, `jq . artifacts/threshold.json` で内容確認。

### 軽いテスト

- 軽いスモーク: `tests/test_threshold.py`（実行→JSONのキー存在だけ検証）。
- `venv/bin/pytest -q tests/test_threshold.py`

---

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

---

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