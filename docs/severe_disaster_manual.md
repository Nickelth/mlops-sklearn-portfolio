## 激甚時撤収手順（緊急・監査対応）

想定対象:
- ローカル/コンテナで稼働中の API（`uvicorn` または `docker run`）
- 学習ジョブ（`make train-full` 系）

前提:
- `awscli` 設定済み
- `S3_BUCKET` を `s3://<bucket>/mlops-sklearn-portfolio` の形式でエクスポート済み
- ローカルに `make manifest`, `make s3-push`, `make s3-pull` がある

### 0. 事前情報の固定（インシデントID発行）
```bash
# UTC基準のインシデントIDと退避ディレクトリ
export INCIDENT_ID="IR-$(date -u +%Y%m%dT%H%M%SZ)"
export EVD="evidence/${INCIDENT_ID}"
mkdir -p "$EVD"

# バージョン・コミット・時刻の記録
venv/bin/python - <<'PY' > "$EVD/envinfo.json"
import json,platform,subprocess,sys,datetime,sklearn,pandas
def git():
  try: return subprocess.check_output(["git","rev-parse","--short","HEAD"]).decode().strip()
  except Exception: return None
print(json.dumps({
  "incident_id": __import__("os").environ.get("INCIDENT_ID"),
  "ts_utc": datetime.datetime.utcnow().isoformat()+"Z",
  "python": platform.python_version(),
  "sklearn": sklearn.__version__,
  "pandas": pandas.__version__,
  "git_commit": git(),
}, indent=2))
PY
````

### 1. 新規投入の遮断（コーデン）

```bash
# 学習の新規起動を防ぐロック
exec 9>/tmp/ml-train.lock; flock -n 9 || true
```

### 2. API の停止

```bash
# ローカル uvicorn
pkill -f "uvicorn .*api.app" || true

# Docker の場合（Makefile 対応済み）
make docker-stop || true
```

### 3. 学習ジョブの穏当停止（優先: SIGINT）

```bash
# 実行中確認
pgrep -af "python -u src/train.py .* --mode full" || echo "no training"

# 停止（timeout が30s後にKILL）
pkill -f "python -u src/train.py .* --mode full" || true
```

### 4. 証跡採取（ログ・成果物・プロセス状況）

```bash
# プロセス・システム概況
ps -eo pid,ppid,pcpu,pmem,etime,cmd --sort=-pcpu | head -n 40 > "$EVD/ps_top.txt" || true
df -h > "$EVD/df.txt" || true
free -h > "$EVD/mem.txt" || true
dmesg | tail -n 200 > "$EVD/dmesg_tail.txt" || true

# 依存一覧
venv/bin/pip freeze > "$EVD/pip_freeze.txt" || true

# マニフェスト生成（SHA256）
make manifest
cp -f artifacts/manifest.json "$EVD/manifest.json" || true

# 主要ログを収集（存在すれば）
mkdir -p "$EVD/logs" "$EVD/artifacts" "$EVD/models"
cp -n logs/*.log "$EVD/logs/" 2>/dev/null || true
cp -n artifacts/summary_*.json "$EVD/artifacts/" 2>/dev/null || true
cp -n artifacts/cv_results_*.csv "$EVD/artifacts/" 2>/dev/null || true
cp -n models/model_*.joblib "$EVD/models/" 2>/dev/null || true
```

### 5. S3 退避（スナップショット＋latest 更新）

```bash
# スナップショット: incidents/<ID>/ と snapshots/<UTC>/ に保存
test -n "$S3_BUCKET" || { echo "ERROR: S3_BUCKET not set"; exit 1; }

# 成果物一式（Makefile タスク）
make s3-push

# 証跡フォルダ（インシデント固有）
aws s3 sync "$EVD/" "$S3_BUCKET/incidents/$INCIDENT_ID/evidence/" --only-show-errors
```

### 6. 退避確認

```bash
aws s3 ls "$S3_BUCKET/latest/models/"       --recursive | head
aws s3 ls "$S3_BUCKET/incidents/$INCIDENT_ID/evidence/" --recursive | head
```

### 7. 最小復旧（必要時）

```bash
# API 再起動（どちらか）
make api &  sleep 2  && curl -sf localhost:8000/health
# または
make docker-run IMAGE=mlops-sklearn-portfolio:local PORT=8000 & sleep 2 && curl -sf localhost:8000/health

# モデル誤差し替え時はリロード
curl -s -X POST "http://localhost:8000/reload?path=/app/models/model_openml_adult.joblib" || true
```

### 8. 記録（ポストモーテム用）

* 収集物: `evidence/<INCIDENT_ID>/` と `s3://…/incidents/<INCIDENT_ID>/evidence/`
* 必須項目: 事象概要、影響範囲、検知時刻（JST/UTC）、原因仮説、時系列、暫定対処、恒久対策、再発防止
* 参照: `artifacts/summary_*.json` の `git_commit / python / sklearn / pandas`

> 注: 「latest/」を壊したくない場合、`make s3-push` 実行前に `make s3-dryrun` で同期先を確認すること。