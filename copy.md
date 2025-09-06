長い。読む側の目は飴じゃない。分割しよう。
今のREADMEは「概要＋手順＋運用＋証跡＋日記」が全部乗り。採用レビューで秒で離脱コース。下の**最小README＋docs分割**に差し替えればスッキリする。

## ざっくり方針

* `README.md` は**名刺サイズ**だけ：目的、クイックスタート、主要リンク、バッジ。
* 詳細は `docs/` 配下に逃がす。
* 変更履歴は `CHANGELOG.md` に独立。
* 激甚対応はもう作った `severe_disaster_manual.md` にリンク。

## 置き換え用 README（短い版）

````markdown
# mlops-sklearn-portfolio

scikit-learn + Pipeline で表形式MLを**学習→成果物→推論API→コンテナ**まで最短導線で通すポートフォリオ。

[![CI](https://github.com/Nickelth/mlops-sklearn-portfolio/actions/workflows/ci.yml/badge.svg)](../../actions)

## Quick Start
```bash
make init EXTRAS=[dev]          # 依存
make train-full DS=adult        # 学習
make check                      # 成果物/ログ 確認
make docker-build && make docker-run   # API (Docker)
curl -s localhost:8000/health
````

## docs/ の中身テンプレ（必要最低限）
下の6ファイルを作ってコピペ。中身は短く要点だけ。詳細や長文は後から増やせばいい。

### `docs/overview.md`

```markdown
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
````

### `docs/training.md`

````markdown
# Training & Long-run Ops

## 基本コマンド
```bash
make train-fast DS=adult
make train-full DS=adult
make train-full DS=credit-g
make check
````

## 長時間実行の作法

* BLAS内スレ1固定: `export OMP_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 MKL_NUM_THREADS=1 NUMEXPR_NUM_THREADS=1`
* スリープ抑止: `systemd-inhibit --what=sleep --why="ml-train" ...`
* 放置ラッパ例は `README` 旧版 or severe\_disaster\_manual.md を参照。

## 安定化設定

* StratifiedKFold、`error_score=0.0`、小規模データは `min_resources` を引き上げ。
* OpenML は `version` 固定と `cache=True, data_home="data_cache"`。

````

### `docs/api.md`
```markdown
# API

- ベース: FastAPI（`api/app.py`）
- モデル: 起動時 `MODEL_PATH` をロード、`/reload?path=...` で切替可
- ログ: 1行JSONを `logs/api-YYYYMMDD.log`

## Endpoints
- `GET /health` → `{status, model, ts}`
- `GET /schema` → `{required_columns[], numeric_columns[]}`
- `POST /predict` → `{"features": {...}}` → `{pred} or {pred_proba}`
- `POST /predict_batch` → `{"rows": [{...}, ...]}` → 配列結果
- `POST /reload?path=/app/models/model_xxx.joblib`

## 最小例
```bash
curl -s -X POST localhost:8000/predict -H 'content-type: application/json' \
  -d '{"features":{"age":39,"education":"Bachelors","hours-per-week":40}}'
````

````

### `docs/docker.md`
```markdown
# Docker

```bash
make docker-build IMAGE=mlops-sklearn-portfolio:local
make docker-run   IMAGE=mlops-sklearn-portfolio:local PORT=8000
# health
curl -s localhost:8000/health | jq .
````

* モデル/ログはボリュームで渡す（`models/`, `logs/` を -v マウント）
* ARM→amd64 ビルド: `docker build --platform linux/amd64 -t <image> .`

````

### `docs/ci.md`
```markdown
# CI

- トリガー: Push/PR/手動
- 環境: Ubuntu, Python 3.12, `libgomp1`
- インストール: `pip install -e .[dev]`
- スモーク: `tests/test_api_smoke.py`, `tests/test_train.py::test_train_builtin_fast`
- 低スレッド: `OMP_NUM_THREADS=1` 等で安定化
- Docker build（pushなし）
- Concurrency とタイムアウト設定あり
````

### `docs/ops.md`

````markdown
# Ops（S3・ログ・Runbook）

## S3 同期
```bash
export S3_BUCKET=s3://<bucket>/mlops-sklearn-portfolio
make s3-push     # snapshots/<UTC>/ と latest/ 更新
make s3-pull     # latest/ を取得（SRC=... でスナップショット指定）
````

* `artifacts/manifest.json` に SHA256/サイズを記録。

## ログと確認

* 学習ログ: `logs/train-*.log`（`make check` でサマリ）
* APIログ: `logs/api-YYYYMMDD.log`（1行JSON）

## 緊急時

* 手順は `severe_disaster_manual.md` を参照（監査向け）。

````

### `CHANGELOG.md`（変更履歴だけ分離）
```markdown
# Changelog

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
```

## 作業手順（コピペで一気に分割）

```bash
mkdir -p docs
# 上の各ブロックを該当パスに保存
$EDITOR README.md docs/overview.md docs/training.md docs/api.md docs/docker.md docs/ci.md docs/ops.md CHANGELOG.md
git add README.md docs/*.md CHANGELOG.md
git commit -m "docs: split README into focused docs (overview/training/api/docker/ci/ops) and CHANGELOG"
```

## ルール（今後破らないやつ）

* README は**300行未満**、図鑑は docs。
* 詳細なコマンド羅列は `docs/training.md` と `docs/ops.md` に置く。
* 実行結果スクショや長表は S3 の成果物か `docs/` にリンクだけ。
* 変更履歴は **CHANGELOG** に一元化。README の「変更履歴」セクションは禁止。

これでREADMEは軽い。重いのはCPUだけで十分。
