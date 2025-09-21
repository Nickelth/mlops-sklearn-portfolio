.ONESHELL:
.RECIPEPREFIX := >
SHELL := /bin/bash
.SHELLFLAGS := -o pipefail -c

.PHONY: init train train-file train-fast train-full train-both api api-bg check envinfo clean \
		report-md docker-build docker-run docker-run-baked docker-stop deps bench model-pull-reload

VENV ?= venv
STAMP := $(VENV)/.ok
PY := $(VENV)/bin/python -u
EXTRAS ?=

# ==== venv stamp ====
$(STAMP):
>	python3 -m venv $(VENV)
>	$(PY) -m pip install -U pip setuptools wheel
>	touch $(STAMP)

init: $(STAMP)
>	$(PY) -m pip install -e .$(EXTRAS)

TS := $(shell date +%Y%m%d_%H%M%S)
BLAS := OMP_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 MKL_NUM_THREADS=1 NUMEXPR_NUM_THREADS=1
DS ?= builtin
MODE ?= fast

# 依存（pandas / sklearn が無ければ入れる）
deps: | $(STAMP)
>	@$(PY) -c "import sklearn, pandas" 2>/dev/null || $(PY) -m pip install -e .[dev]

# ===== 学習（CI向け: 標準出力にも流す） =====
train: deps
>	mkdir -p logs models cache artifacts
>	env $(BLAS) nice -n 10 $(PY) src/train.py --dataset $(DS) --mode $(MODE) 2>&1 | tee logs/train-$(TS).log
>	@echo "=== TRAIN DONE ==="

# ===== 学習（静音: ログファイルのみ） =====
train-file: deps
>	mkdir -p logs models cache artifacts
>	env $(BLAS) nice -n 10 $(PY) src/train.py --dataset $(DS) --mode $(MODE) > logs/train-$(TS).log 2>&1
>	@echo "=== TRAIN DONE ==="

train-fast:
>	$(MAKE) train MODE=fast

train-full:
>	$(MAKE) train MODE=full

train-both:
>	$(MAKE) train DS=adult MODE=$(MODE)
>	$(MAKE) train DS=credit-g MODE=$(MODE)

bench:
>	@mkdir -p artifacts
>	@printf '%s\n' '{"features":{"age":39,"education":"Bachelors","hours-per-week":40}}' > /tmp/payload.json
>	@TS=$$(date +%Y%m%d_%H%M%S); \
>	docker run --rm --net host -v /tmp/payload.json:/payload.json:ro williamyeh/hey \
>		-z 30s -c 16 -m POST -T 'application/json' -D /payload.json http://127.0.0.1:8000/predict \
>		| tee artifacts/bench-$$TS.txt; \
>	grep -E 'Requests/sec|Avg|50%|95%' artifacts/bench-$$TS.txt || true

model-pull-reload:
>	@test -n "$(S3_BUCKET)" || (echo "ERROR: set S3_BUCKET"; exit 1)
>	$(AWSCLI) s3 sync $(S3_BUCKET)/latest/models/ models/ --only-show-errors
>	curl -s -X POST "http://localhost:8000/reload?path=$(MODEL_PATH)" | jq .

api:
>	uvicorn api.app:app --host 0.0.0.0 --port 8000

api-bg:
>	nohup uvicorn api.app:app --host 0.0.0.0 --port 8000 >/dev/null 2>&1 &

# 可視化
envinfo: | $(STAMP)
>	@echo "PYTHON  : $$($(PY) -c 'import sys;print(sys.executable)')"
>	@$(PY) -c 'import sys,sklearn,pandas;print("py",sys.version.split()[0],"sklearn",sklearn.__version__,"pandas",pandas.__version__)'

check:
>	@grep -E "^\[RESULT\]|^=== TRAIN DONE ===|^Traceback|^ERROR" -n logs/train-*.log | tail -n 30 || true
>	@ls -lh models/model_*.joblib artifacts/summary_*.json 2>/dev/null || true

# artifacts ディレクトリを order-only で用意
artifacts:
>	mkdir -p artifacts

report-md:
>	@$(PY) scripts/log_report.py > artifacts/report.md

clean:
>	rm -rf cache __pycache__

IMAGE ?= mlops-sklearn-portfolio:local
PORT  ?= 8000
MODEL_PATH ?= /app/models/model_openml_adult.joblib

docker-build:
>	docker build -t $(IMAGE) .

# ホストの models/ と logs/ をボリュームで渡す運用（推奨）
docker-run:
>	docker run --rm -p $(PORT):8000 \
>		-e MODEL_PATH=$(MODEL_PATH) \
>		-v $(PWD)/models:/app/models \
>		-v $(PWD)/logs:/app/logs \
>		$(IMAGE)

# モデルをイメージに焼いた場合はこちら（.dockerignore の models/ を外して COPY 済み前提）
docker-run-baked:
>	docker run --rm -p $(PORT):8000 $(IMAGE)

docker-stop:
>	-@docker ps --filter "ancestor=$(IMAGE)" -q | xargs -r docker stop

# ==== S3 Sync ====
# 必須: 環境変数 S3_BUCKET（例: s3://my-bucket/mlops-sklearn-portfolio）
AWS_PROFILE ?=
AWS_REGION  ?=
AWSCLI := aws $(if $(AWS_PROFILE),--profile $(AWS_PROFILE),) $(if $(AWS_REGION),--region $(AWS_REGION),)

# 同期先
SNAP_TS   := $(shell date -u +%Y%m%dT%H%M%SZ)
S3_SNAPSHOT ?= $(S3_BUCKET)/snapshots/$(SNAP_TS)
S3_LATEST   ?= $(S3_BUCKET)/latest

# マニフェスト（ハッシュ）を作る
.PHONY: manifest
manifest:
>	@$(PY) scripts/generate_manifest.py

.PHONY: s3-dryrun
s3-dryrun:
>	@test -n "$(S3_BUCKET)" || (echo "ERROR: set S3_BUCKET=s3://…"; exit 1)
>	@echo "Would push to: $(S3_SNAPSHOT) and $(S3_LATEST)"

.PHONY: s3-push
s3-push: manifest
>	@test -n "$(S3_BUCKET)" || (echo "ERROR: set S3_BUCKET=s3://…"; exit 1)
>	@echo ">>> Pushing snapshot to $(S3_SNAPSHOT)"
>	$(AWSCLI) s3 sync models     $(S3_SNAPSHOT)/models/     --only-show-errors
>	$(AWSCLI) s3 sync artifacts  $(S3_SNAPSHOT)/artifacts/  --only-show-errors
>	$(AWSCLI) s3 sync logs       $(S3_SNAPSHOT)/logs/       --only-show-errors || true
>	@echo ">>> Updating latest at $(S3_LATEST)"
>	$(AWSCLI) s3 sync models     $(S3_LATEST)/models/       --delete --only-show-errors
>	$(AWSCLI) s3 sync artifacts  $(S3_LATEST)/artifacts/    --delete --only-show-errors
>	$(AWSCLI) s3 sync logs       $(S3_LATEST)/logs/         --delete --only-show-errors || true

.PHONY: s3-pull
s3-pull:
>	@test -n "$(S3_BUCKET)" || (echo "ERROR: set S3_BUCKET=s3://…"; exit 1)
>	@mkdir -p models artifacts logs
>	@echo ">>> Pulling from $(or $(SRC),$(S3_LATEST))"
>	$(AWSCLI) s3 sync $(or $(SRC),$(S3_LATEST))/models/    models/    --only-show-errors
>	$(AWSCLI) s3 sync $(or $(SRC),$(S3_LATEST))/artifacts/ artifacts/ --only-show-errors
>	$(AWSCLI) s3 sync $(or $(SRC),$(S3_LATEST))/logs/      logs/      --only-show-errors || true

# ==== ECR Push ====
AWS_REGION ?= us-west-2
AWS_ACCOUNT_ID ?= $(shell aws sts get-caller-identity --query Account --output text 2>/dev/null)
REPO_NAME ?= mlops-sklearn-portfolio
ECR_URI   ?= $(AWS_ACCOUNT_ID).dkr.ecr.$(AWS_REGION).amazonaws.com/$(REPO_NAME)
TAG ?= v$(shell date +%Y%m%d)-1

.PHONY: ecr-login docker-push docker-push-local
# ===== CI前提: デフォは案内だけ =====
docker-push:
>	@echo "[info] Docker push は GitHub Actions (release-ecr.yml) で実施します。"
>	@echo "       手元から ECR へ push したい場合は: make docker-push-local LOCAL_PUSH=1"
>	@echo "       例: IMAGE=mlops-sklearn-portfolio:local TAG=vYYYYMMDD-1"
>	@exit 0

# ===== 手元から push したい強者向け（明示フラグ必須） =====
ecr-login:
>	@[ "$(LOCAL_PUSH)" = "1" ] || (echo "[guard] LOCAL_PUSH=1 を指定してください。"; exit 2)
>	aws ecr get-login-password --region $(AWS_REGION) \
>	| docker login --username AWS --password-stdin $(AWS_ACCOUNT_ID).dkr.ecr.$(AWS_REGION).amazonaws.com

docker-push-local: docker-build ecr-login
>	@[ "$(LOCAL_PUSH)" = "1" ] || (echo "[guard] LOCAL_PUSH=1 を指定してください。"; exit 2)
>	docker tag $(IMAGE) $(ECR_URI):$(TAG)
>	docker tag $(IMAGE) $(ECR_URI):latest
>	docker push $(ECR_URI):$(TAG)
>	docker push $(ECR_URI):latest

# ==== F1 最大点と閾値を算出 ====
.PHONY: threshold
threshold: | $(STAMP)
>	# 既存モデルを使って PR 曲線から F1 最大閾値を算出し artifacts/threshold.json を更新
>	env $(BLAS) $(PY) src/opt_threshold.py --dataset $(DS)

# ==== Permutation 重要度スクリプト ====
# ==== Permutation Importance をPNG/CSV/JSONで artifacts/ に出力 ====
REPEATS ?= 10
MAXS    ?= 5000

.PHONY: perm
perm: | $(STAMP)
>	env $(BLAS) $(PY) src/perm_importance.py --dataset $(DS) --n-repeats $(REPEATS) --max-samples $(MAXS)
perm-adult:
>	$(MAKE) perm DS=adult  REPEATS=$(REPEATS) MAXS=$(MAXS)
perm-credit:
>	$(MAKE) perm DS=credit-g REPEATS=$(REPEATS) MAXS=$(MAXS)

# =========
# Settings
# =========
TFDIR ?= infra
WORKDIR ?= /tmp/infra
AWS_REGION ?= us-west-2
AWS_ACCOUNT_ID ?= $(shell aws sts get-caller-identity --query Account --output text 2>/dev/null)
REPO_NAME ?= mlops-sklearn-portfolio
ECR_URI   ?= $(AWS_ACCOUNT_ID).dkr.ecr.$(AWS_REGION).amazonaws.com/$(REPO_NAME)
TF_VARS = -var="aws_region=$(AWS_REGION)" -var="ecr_repository_url=$(ECR_URI)"
RSYNC       ?= rsync
RSYNC_FLAGS ?= -a --delete

.PHONY: prep tf-init tf-apply tf-destroy tf-output evidence clean-tmp

define SYNC_CMD
if command -v $(RSYNC) >/dev/null 2>&1; then
  $(RSYNC) $(RSYNC_FLAGS) "$(TFDIR)/" "$(WORKDIR)/"
else
  mkdir -p "$(WORKDIR)"
  (cd "$(TFDIR)" && tar -cf - .) | (cd "$(WORKDIR)" && rm -rf ./* && tar -xf -)
fi
endef

prep:
>	mkdir -p $(WORKDIR)
>	@$(SYNC_CMD)

# CloudShell の容量回避で -chdir を使用
tf-init: prep
>	terraform -chdir=$(WORKDIR) init

tf-apply:
>	terraform -chdir=$(WORKDIR) apply -auto-approve $(TF_VARS)

tf-destroy:
>	terraform -chdir=$(WORKDIR) destroy -auto-approve $(TF_VARS)

# ALB DNS を拾って evidence に保存
tf-output:
>	@DNS=$$(terraform -chdir=$(WORKDIR) output -raw alb_dns_name); \
>	echo $$DNS | tee docs/evidence/2025-09-14_alb_dns.txt; \
>	echo "http://$$DNS";

# /health を叩いて保存（ALB の安定化を少し待つ）
evidence:
>	@sleep 10; \
>	DNS=$$(terraform -chdir=$(WORKDIR) output -raw alb_dns_name); \
>	curl -s -i "http://$$DNS/health" | tee docs/evidence/2025-09-14_health.txt

clean-tmp:
>	rm -rf $(WORKDIR)