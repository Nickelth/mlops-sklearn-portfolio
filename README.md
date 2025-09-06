## mlops-sklearn-portfolio

タブularデータ向けの機械学習を **scikit-learn + Pipeline** で実装し、学習の再現性と運用（API化・コンテナ化・デプロイ）までを最短導線でまとめるポートフォリオ。

* 目的: 再現性の高い学習ジョブと、軽量な推論APIを整備し、ECSへのデプロイまでを通す
* スコープ: 学習/評価/成果物化/API化/コンテナ化/デプロイ（ECSは別進行で構築）
* 対象データ: OpenML（`adult` / `credit-g`）と内蔵（`breast_cancer`）

---

### 1. 問題設定とビジネス想定

* **成人収入予測（OpenML: adult）**
  想定: 与信審査の事前スクリーニング、マーケティングのターゲティング。
  指標: 確率の較正と再現性が重要。一次評価は `ROC-AUC`、補助に `ACC`。

* **与信可否（OpenML: credit-g）**
  想定: クレジットスコア/リスク判定の予備判定。データは小規模で難易度が高い。
  指標: `ROC-AUC` を主とし、閾値調整前提で解釈する。

* **分類のベースライン（内蔵: breast\_cancer）**
  目的: パイプライン/評価/成果物生成のスモーク。

---

### 2. データの出所と取得方法

* **内蔵データ**: `sklearn.datasets.load_breast_cancer(as_frame=True)`
* **OpenML**: `sklearn.datasets.fetch_openml(name="adult"|"credit-g", as_frame=True, cache=True, data_home="data_cache")`

> OpenML はネットワーク起因で失敗することがあるため、`cache=True` と `data_home="data_cache"` を指定してローカルキャッシュを固定。

---

### 3. 前処理とリーク対策

* `Pipeline` と `ColumnTransformer` を用いて

  * 数値: `SimpleImputer()` → `StandardScaler()`
  * カテゴリ: `SimpleImputer(strategy="most_frequent")` → `OneHotEncoder(handle_unknown="ignore")`
* 学習/評価は `train_test_split(..., stratify=...)` とCVで統制。
* リーク回避: 前処理の統計量は訓練 folds からのみ学習し、CV内で一貫。

> 時系列データを扱う場合は `TimeSeriesSplit` を使用（本リポ内の現行データは i.i.d. 前提）。

---

### 4. 評価指標の選定理由

* 主指標: `ROC-AUC`（クラス不均衡や閾値未確定の初期段階で扱いやすい）
* 補助指標: `ACC`（簡易比較用。最終判断は閾値設計とコスト次第）
* 必要に応じて `CalibratedClassifierCV` で確率較正を実施予定。

---

### 5. 学習の再現コマンドと所要時間の目安

#### 環境準備

```bash
python3 -m venv venv && source venv/bin/activate
pip install -U pip wheel
python -m pip install -e .
```

#### 長時間実行時の推奨設定

```bash
# BLAS内側並列は1に固定（外側CVの並列と競合させない）
export OMP_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 MKL_NUM_THREADS=1 NUMEXPR_NUM_THREADS=1

# 学習中はスリープ禁止
systemd-inhibit --what=sleep --why="ml-train" bash -lc 'make train'
```

#### 代表コマンド

```bash
# 手早いスモーク（短時間）
make train-fast DS=adult

# 本気の探索（時間長め）
make train-full DS=adult
make train-full DS=credit-g

# バッチで回す（例: 12h上限×2本）
# すべての stdout/stderr を 時刻入りで1本のログに集約
# logs/latest.log にシンボリックリンク
# Pythonは非バッファ出力、BLASは1スレに固定
# 各DSの開始/終了/RCを行ごとに記録
# 実行日時: 2025-09-02 22:44〜

nohup bash -lc '
set -Eeuo pipefail
umask 077
mkdir -p logs
LOG="logs/train-$(date +%Y%m%d_%H%M%S).log"
ln -sfn "$LOG" logs/latest.log

# ここからの出力は全部ログへ。teeはお好みで（外部出力は捨てられるので -a でファイルだけ残ればOK）
exec > >(stdbuf -oL -eL tee -a "$LOG") 2>&1

echo "=== START $(date -Is) pid=$$ ==="
source venv/bin/activate
export PYTHONUNBUFFERED=1
export OMP_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 MKL_NUM_THREADS=1 NUMEXPR_NUM_THREADS=1

for ds in adult credit-g; do
  echo "--- DS=$ds start $(date -Is) ---"
  if timeout --signal=INT --kill-after=30s 12h make train-full DS="$ds"; then
    rc=$?
    echo "--- DS=$ds OK rc=$rc end=$(date -Is) ---"
  else
    rc=$?
    echo "--- DS=$ds FAIL rc=$rc end=$(date -Is) ---"
  fi
done

echo "=== END $(date -Is) ==="
' >/dev/null 2>&1 &

# 依存なし最小構成
make init EXTRAS=
make envinfo

# 依存と開発ツール込み
make init EXTRAS=[dev]
make envinfo

# 学習とAPIの生存確認
make train-full DS=adult
make check
make api &
sleep 2 &
curl -s localhost:8000/health

curl -s -X POST localhost:8000/predict -H 'content-type: application/json' \
  -d '{"features":{"age":39, "education":"Bachelors", "hours-per-week":40}}'
```

#### API スモークテストコマンド

```bash
# 依存を入れておく（dev込み）
make init EXTRAS=[dev]

# APIをバックグラウンド起動 → ヘルスチェック待ち
make api >/dev/null 2>&1 &                                  # uvicorn 起動
until curl -sf http://localhost:8000/health >/dev/null; do  # 起動待ち
  sleep 0.2
done

# APIスモークテスト（/schema 200 と /predict 正常系）
venv/bin/pytest -q tests/test_api_smoke.py

# 学習スモーク（builtin×fast、[RESULT]を検証）
venv/bin/pytest -q tests/test_train.py -k test_train_builtin_fast

# 後片付け（API停止）
pkill -f "uvicorn .*api.app" || true
```

#### 監査用コマンド

```bash
tail -f logs/latest.log
# 区切りは "DS=<name> start/end" をgrepすれば一目
grep -nE -- "--- DS=" logs/latest.log

grep -h "^\[RESULT\]" logs/train-*.log | tail -n 5

grep -h "^\[RESULT\]" logs/train-*.log |
  awk '{ds=$3; auc=$6; acc=$8; for(i=1;i<=NF;i++) if($i ~ /elapsed_sec=/){split($i,a,"="); sec=a[2]} print ds"\t"auc"\t"acc"\t"sec }'

# make train-full が稼働中かどうか確認
ps -ef | grep -E "[p]ython .*src/train.py .*--mode full" || echo "not running"

# schema の列一覧取得(最小構成)
curl -s -X POST localhost:8000/predict -H 'content-type: application/json' \
  -d '{"features":{"age":39,"education":"Bachelors","hours-per-week":40}}'
```

- `/predict_batch` は `{"rows":[{...},{...}]}` を受けて配列で返す。

- `/reload?path=…` で即切替。引数なしなら再読込。

#### サスペンド制御

`mask`でサスペンドを封印。`unmask`で封印解除。

```bash
sudo systemctl mask sleep.target suspend.target hibernate.target hybrid-sleep.target

sudo systemctl unmask sleep.target suspend.target hibernate.target hybrid-sleep.target
```


**所要時間の目安（i7-9700/32GB, GPUなし）**

* `adult`: 数十分〜数時間（パラメータ幅とCV数に依存）
* `credit-g`: 数分〜数十分（データが小さいため相対的に短い）
* 成果物は `models/*.joblib`, `artifacts/summary_*.json`, `artifacts/cv_results_*.csv` に保存

---

### 6. デプロイ手順とロールバック手順（進行中）

#### ローカル API（FastAPI）

```bash
uvicorn api.main:app --reload
# or Docker
docker build -t mlops-api .
docker run --rm -p 8000:8000 mlops-api
```

### ECS デプロイ（予定/設計方針）

* ECR: `mlops/api`
* ECS(Fargate) 1サービス/最小タスク数1、ALB経由で `/health`
* Secrets/SSM: モデルバケット名、パスなどを注入
* GitHub Actions: `build-and-push.yml`（ECRへ）、`deploy.yml`（ECS更新）
* **ロールバック**: 直前のタスク定義リビジョンへ切替、もしくは前タグのコンテナをデプロイ

> 具体的な IaC/Actions 定義は Week2〜3 で追記予定。

---

### 7. Evidence（実行ログ・成果物）

#### 生成物(2025-09-01)

```
artifacts/
  summary_builtin_breast_cancer.json
  summary_openml_adult.json
  summary_openml_credit_g.json
models/
  model_builtin_breast_cancer.joblib   (~236 KB)
  model_openml_adult.joblib            (~199 KB)
  model_openml_credit_g.joblib         (~155 KB)
logs/
  train-YYYYmmdd_HHMMSS.log
  latest.log -> 直近ログのシンボリックリンク
```

#### 2025-09-01〜02 実行結果（抜粋）

| dataset                 | mode |    AUC |    ACC | best                                                                           | elapsed\[s] |
| ----------------------- | ---- | -----: | -----: | ------------------------------------------------------------------------------ | ----------: |
| builtin\_breast\_cancer | fast | 0.9924 | 0.9649 | `{'clf__learning_rate': 0.2, 'clf__max_depth': 8, 'clf__max_leaf_nodes': 63}`  |           2 |
| openml\_adult           | full | 0.9253 | 0.8718 | `{'clf__learning_rate': 0.1, 'clf__max_depth': 4, 'clf__max_leaf_nodes': 31}`  |          18 |
| openml\_credit\_g       | full | 0.7570 | 0.7250 | `{'clf__learning_rate': 0.05, 'clf__max_depth': 4, 'clf__max_leaf_nodes': 31}` |           2 |
| openml\_adult           | full | 0.9253 | 0.8718 | `{'clf__learning_rate': 0.1, 'clf__max_depth': 4, 'clf__max_leaf_nodes': 127}`  | 19            |
| openml\_credit\_g       | full | 0.7570 | 0.7250 | `{'clf__learning_rate': 0.05, 'clf__max_depth': 4, 'clf__max_leaf_nodes': 127}` | 3             |
| openml\_adult           | full | 0.9253 | 0.8718 | `{'clf__learning_rate': 0.1, 'clf__max_depth': 4, 'clf__max_leaf_nodes': 31}` | 19          |
| openml\_adult           | full | 0.9253 | 0.8718 | `{'clf__learning_rate': 0.1, 'clf__max_depth': 4, 'clf__max_leaf_nodes': 63}` | 19          |

#### 直近結果(2525-09-06)
```bash
grep -h "^\[RESULT\]" logs/train-*.log | tail -n 7
[RESULT] ds=openml_credit_g mode=full AUC=0.7570 ACC=0.7250 best={'clf__learning_rate': 0.05, 'clf__max_depth': 4, 'clf__max_leaf_nodes': 31} elapsed_sec=2
[RESULT] ds=openml_adult mode=full AUC=0.9253 ACC=0.8718 best={'clf__learning_rate': 0.1, 'clf__max_depth': 4, 'clf__max_leaf_nodes': 127} elapsed_sec=19
[RESULT] ds=openml_adult mode=full AUC=0.9253 ACC=0.8718 best={'clf__learning_rate': 0.1, 'clf__max_depth': 4, 'clf__max_leaf_nodes': 127} elapsed_sec=19
[RESULT] ds=openml_credit_g mode=full AUC=0.7570 ACC=0.7250 best={'clf__learning_rate': 0.05, 'clf__max_depth': 4, 'clf__max_leaf_nodes': 127} elapsed_sec=3
[RESULT] ds=openml_credit_g mode=full AUC=0.7570 ACC=0.7250 best={'clf__learning_rate': 0.05, 'clf__max_depth': 4, 'clf__max_leaf_nodes': 127} elapsed_sec=3
[RESULT] ds=openml_adult mode=full AUC=0.9253 ACC=0.8718 best={'clf__learning_rate': 0.1, 'clf__max_depth': 4, 'clf__max_leaf_nodes': 31} elapsed_sec=19
[RESULT] ds=openml_adult mode=full AUC=0.9253 ACC=0.8718 best={'clf__learning_rate': 0.1, 'clf__max_depth': 4, 'clf__max_leaf_nodes': 63} elapsed_sec=19
```

```bash
grep -h "^\[RESULT\]" logs/train-*.log |
  awk '{ds=$3; auc=$6; acc=$8; for(i=1;i<=NF;i++) if($i ~ /elapsed_sec=/){split($i,a,"="); sec=a[2]} print ds"\t"auc"\t"acc"\t"sec }'
mode=fast       best={'clf__learning_rate':     'clf__max_depth':       2
mode=fast       best={'clf__learning_rate':     'clf__max_depth':       2
mode=fast       best={'clf__learning_rate':     'clf__max_depth':       19
mode=full       best={'clf__learning_rate':     'clf__max_depth':       18
mode=full       best={'clf__learning_rate':     'clf__max_depth':       3
mode=full       best={'clf__learning_rate':     'clf__max_depth':       18
mode=full       best={'clf__learning_rate':     'clf__max_depth':       2
mode=full       best={'clf__learning_rate':     'clf__max_depth':       18
mode=full       best={'clf__learning_rate':     'clf__max_depth':       2
mode=full       best={'clf__learning_rate':     'clf__max_depth':       19
mode=full       best={'clf__learning_rate':     'clf__max_depth':       19
mode=full       best={'clf__learning_rate':     'clf__max_depth':       3
mode=full       best={'clf__learning_rate':     'clf__max_depth':       3
mode=full       best={'clf__learning_rate':     'clf__max_depth':       19
```

#### envinfo結果 (2025-09-06)

```bash
$ make envinfo
PYTHON  : /home/user/mlops-sklearn-portfolio/venv/bin/python
py 3.12.3 sklearn 1.7.1 pandas 2.3.2
```

#### APIスモークテスト & 学習テスト結果 (2025-09-06)

```bash
$ venv/bin/pytest -q tests/test_api_smoke.py
venv/bin/pytest -q tests/test_train.py -k test_train_builtin_fast
.                                                                                                                                                                                                  [100%]
1 passed in 0.07s
.                                                                                                                                                                                                  [100%]
1 passed, 1 deselected in 2.79s
```

### 運用メモ（長時間実行・ログ・終了判定）

#### スリープ抑止と低優先度実行

```bash
export OMP_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 MKL_NUM_THREADS=1 NUMEXPR_NUM_THREADS=1
systemd-inhibit --what=sleep --why="ml-train" \
bash -lc 'nice -n 10 python -u src/train.py --mode full 2>&1 | tee logs/train-$(date +%Y%m%d_%H%M%S).log'
```

#### 終了判定（`make check` 例）

```make
# 0=全DS完了, 1=失敗あり, 2=進行中/未開始
check:
	@python - <<'PY'
import re, sys, pathlib
log = pathlib.Path("logs/latest.log")
if not log.exists(): print("logs/latest.log not found"); sys.exit(2)
txt = log.read_text(errors="ignore")
starts = list(re.finditer(r"^=== START .+? ===$", txt, flags=re.M))
region = txt[starts[-1].start():] if starts else txt
datasets = ["adult", "credit-g"]
code = 0
for ds in datasets:
    s = re.search(fr"--- DS={ds} start ", region)
    ok = re.search(fr"--- DS={ds} OK ", region)
    fail = re.search(fr"--- DS={ds} FAIL ", region)
    if ok: st="OK"
    elif fail: st="FAIL"; code=1
    elif s: st="RUNNING"; code=max(code,2)
    else: st="PENDING"; code=max(code,2)
    print(f"{ds}: {st}")
sys.exit(code)
PY
```

#### ログからの簡易サマリ生成（README貼り付け用）

```make
report:
	@python - <<'PY'
import re,glob
print("|dataset|mode|AUC|ACC|best|elapsed[s]|")
print("|-|-|-:|-:|-|-:|")
for p in sorted(glob.glob("logs/train-*.log")):
  for line in open(p,errors="ignore"):
    m=re.search(r"\[RESULT\] ds=(\S+) mode=(\S+) AUC=([\d.]+) ACC=([\d.]+) best=(\{.+?\}) elapsed_sec=(\d+)", line)
    if m: print("|"+"|".join(m.groups())+"|")
PY
```

---

### 既知の課題 / 次のアクション

* 初期リソース由来の AUC 未定義

  * 現象
    先頭で OpenML から「複数バージョンあり」警告。続いて
    `UndefinedMetricWarning: Only one class is present in y_true`が大量発生。
    さらに各 `iter` で `One or more of the test scores are non-finite: [nan ...]`。
    最終的な結果は AUC=0.7570（正常に出ている）。

  * 直接原因
    Successive Halving の初期反復で、使用サンプル数が小さすぎる（`min_resources_=29`）。
    その小さなサブセットを 5-fold に割ると、ある fold の 検証セットが片側クラスだけになることがあり、AUC が未定義 → `nan`。
    Halving は `nan` を含んだままでも選抜を進めるため、警告だらけでも最後はちゃんと収束している。

  * 深い原因
    Halving が使う「サンプル縮小」は層化が保証されない。初期リソースが小さいと、全体としては二値でも fold の検証部で片クラス化しやすい。`credit-g` は行数が少なく（≒800前後）、クラス不均衡も効く。

  * 対策
  対策（いずれか、併用可）

    OpenMLのバージョンを固定して再現性確保：

    ```python
    fetch_openml("credit-g", version=1, as_frame=True, cache=True, data_home="data_cache")
    ```

    `min_resources` を引き上げる（初期サンプルをもっと大きく）。
    目安: `min_resources >= n_splits * 10 / min(p, 1-p)`
    例えば 5fold、少数派比率 p≈0.3 とすると最低 ~170 程度。とりあえず 200〜300 から。

    ```python
    cv = StratifiedKFold(n_splits=5, shuffle=True, random_state=42)
    search = HalvingGridSearchCV(
        pipe, param_grid, scoring="roc_auc",
        cv=cv, factor=3, min_resources=250, random_state=42,
        n_jobs=8, error_score=0.0, verbose=1
    )
    ```

    `cv` を明示的に層化（fold内の片クラスを減らす）
    上のコードの `StratifiedKFold` を使う。
    それでも初期サンプルが小さすぎれば片クラスは起こり得るので、結局は 2 とセット。

    `error_score` を `0.0` か `"raise" `に
    未定義スコアを 0 と見なして強制的に足切りするか、例外で気づくかを選べる。今回は `0.0` で静かに進めるのが無難。


* 「複数バージョンあり」警告

    * 現象
    `credit-g` に対して OpenML が「version 1 と 2 がある。今は 1 を返す」と言っている。

    * 原因
    名前だけ指定すると、OpenML 側が“現時点でのデフォルト”を返すため、将来ブレる可能性がある。

    * 対策
    `version` を固定。ついでに `cache=True`, `data_home="data_cache"` でネットワーク依存を減らす。

* `credit-g` の性能向上

  * `clf__class_weight='balanced'` の比較、`max_leaf_nodes` の拡張（例: 127）
  * 特徴量見直し（高cardinalityカテゴリの処理、Target/Hash Encoding検討）
* OpenML 取得のリトライ導入（ネットワーク/一時I/O対策）

  ```python
  import time
  def with_retry(fn, tries=3, wait=10):
      for i in range(tries):
          try: return fn()
          except Exception:
              if i==tries-1: raise
              time.sleep(wait)
  ```
* FastAPI の入力/出力スキーマ厳格化（pydantic）とベンチ（P50/P95）
* GitHub Actions: `build-and-push.yml`（ECR）と `deploy.yml`（ECS）追加
* アーキ図（ECS/ECR/ALB/SSM/Secrets/S3）の最終化、Runbook/撤収手順の明文化

---

### ディレクトリ構成（例）

```
.
├─ api/                  # FastAPI（/health, /predict）
├─ data/ 
├─ src/                  # 学習スクリプト・ユーティリティ
├─ notebooks/
├─ models/               # joblib成果物
├─ artifacts/            # summary.json, cv_results.csv, ほか
├─ logs/                 # 学習ログ（latest.log はシンボリック）
├─ cache/                # OpenMLキャッシュ（自動生成）
├─ tests/                # 最小限のユニットテスト
├─ Makefile
├─ pyproject.toml
└─ README.md
```

---

### 変更履歴

* **2025-09-06**: slowマーカーをpyproject.tomlに記述
* **2025-09-06**: API（FastAPI）実装
  - 追加: `api/app.py` に `/health`, `/predict`, `/schema`, `/reload`
  - 挙動:
    - 学習済みパイプライン（`models/model_openml_adult.joblib`）を起動時ロード
    - `/schema` で学習時の必須列と数値列を公開
    - `/predict` は不足列を `None` 補完、数値列は自動で `to_numeric(errors="coerce")`
      - 前処理の `SimpleImputer` と `OneHotEncoder(handle_unknown="ignore")` により欠損・未知カテゴリを許容
    - `/reload` でモデル再読込（`MODEL_PATH` 変更後の反映にも対応）
  - Makefile:
    - `make api`（ローカル起動）、必要なら `api-bg` で簡易常駐（任意）
  - 結果: `/predict` は最小3列入力でも 200/推論成功（不足列は自動補完）
* **2025-09-02**: `adult`/`credit-g` を full モードで実行、成果物と指標を反映。ログ運用・終了判定・スリープ抑止をREADMEに追記。
* **2025-09-01**: リポ初期化、`breast_cancer` でスモーク。

---

### ライセンス

TBD（サンプルコード主体のため後日整理）