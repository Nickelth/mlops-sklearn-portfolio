.ONESHELL:
SHELL := /bin/bash
.SHELLFLAGS := -o pipefail -c

.PHONY: init train train-fast train-full train-both api api-bg check envinfo clean \
		report-md docker-build docker-run docker-run-baked docker-stop

VENV ?= venv
STAMP := $(VENV)/.ok
PY := $(VENV)/bin/python -u
EXTRAS ?=

# ==== venv stamp ====
$(STAMP):
	python3 -m venv $(VENV)
	$(PY) -m pip install -U pip setuptools wheel
	touch $(STAMP)

init: $(STAMP)
	$(PY) -m pip install -e .$(EXTRAS)

TS := $(shell date +%Y%m%d_%H%M%S)
BLAS := OMP_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 MKL_NUM_THREADS=1 NUMEXPR_NUM_THREADS=1
DS ?= builtin
MODE ?= fast

train: | $(STAMP)
	mkdir -p logs models cache artifacts
	env $(BLAS) nice -n 10 $(PY) src/train.py --dataset $(DS) --mode $(MODE) \
		> logs/train-$(TS).log 2>&1

train-fast:
	$(MAKE) train MODE=fast

train-full:
	$(MAKE) train MODE=full

train-both:
	$(MAKE) train DS=adult MODE=$(MODE)
	$(MAKE) train DS=credit-g MODE=$(MODE)

api:
	uvicorn api.app:app --host 0.0.0.x --port 8000

api-bg:
	nohup uvicorn api.app:app --host 0.0.0.x --port 8000 >/dev/null 2>&1 &

# 可視化
envinfo: | $(STAMP)
	@echo "PYTHON  : $$($(PY) -c 'import sys;print(sys.executable)')"
	@$(PY) -c 'import sys,sklearn,pandas;print("py",sys.version.split()[0],"sklearn",sklearn.__version__,"pandas",pandas.__version__)'

check:
	@grep -E "^\[RESULT\]|^=== TRAIN DONE ===|^Traceback|^ERROR" -n logs/train-*.log | tail -n 30 || true
	@ls -lh models/model_*.joblib artifacts/summary_*.json 2>/dev/null || true

# artifacts ディレクトリを order-only で用意
artifacts:
	mkdir -p artifacts

report-md:
	@python scripts/log_report.py > artifacts/report.md

clean:
	rm -rf cache __pycache__

# 末尾あたりに追記
IMAGE ?= mlops-sklearn-portfolio:local
PORT  ?= 8000
MODEL_PATH ?= /app/models/model_openml_adult.joblib

docker-build:
	docker build -t $(IMAGE) .

# ホストの models/ と logs/ をボリュームで渡す運用（推奨）
docker-run:
	docker run --rm -p $(PORT):8000 \
		-e MODEL_PATH=$(MODEL_PATH) \
		-v $(PWD)/models:/app/models \
		-v $(PWD)/logs:/app/logs \
		$(IMAGE)

# モデルをイメージに焼いた場合はこちら（.dockerignore の models/ を外して COPY 済み前提）
docker-run-baked:
	docker run --rm -p $(PORT):8000 $(IMAGE)

docker-stop:
	-@docker ps --filter "ancestor=$(IMAGE)" -q | xargs -r docker stop

# ==== S3 Sync ====
# 必須: 環境変数 S3_BUCKET（例: s3://<BUCKET>/mlops-sklearn-portfolio）
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
	@$(PY) scripts/generate_manifest.py

.PHONY: s3-dryrun
s3-dryrun:
	@test -n "$(S3_BUCKET)" || (echo "ERROR: set S3_BUCKET=s3://…"; exit 1)
	@echo "Would push to: $(S3_SNAPSHOT) and $(S3_LATEST)"

.PHONY: s3-push
s3-push: manifest
	@test -n "$(S3_BUCKET)" || (echo "ERROR: set S3_BUCKET=s3://…"; exit 1)
	@echo ">>> Pushing snapshot to $(S3_SNAPSHOT)"
	$(AWSCLI) s3 sync models     $(S3_SNAPSHOT)/models/     --only-show-errors
	$(AWSCLI) s3 sync artifacts  $(S3_SNAPSHOT)/artifacts/  --only-show-errors
	$(AWSCLI) s3 sync logs       $(S3_SNAPSHOT)/logs/       --only-show-errors || true
	@echo ">>> Updating latest at $(S3_LATEST)"
	$(AWSCLI) s3 sync models     $(S3_LATEST)/models/       --delete --only-show-errors
	$(AWSCLI) s3 sync artifacts  $(S3_LATEST)/artifacts/    --delete --only-show-errors
	$(AWSCLI) s3 sync logs       $(S3_LATEST)/logs/         --delete --only-show-errors || true

.PHONY: s3-pull
s3-pull:
	@test -n "$(S3_BUCKET)" || (echo "ERROR: set S3_BUCKET=s3://…"; exit 1)
	@mkdir -p models artifacts logs
	@echo ">>> Pulling from $(or $(SRC),$(S3_LATEST))"
	$(AWSCLI) s3 sync $(or $(SRC),$(S3_LATEST))/models/    models/    --only-show-errors
	$(AWSCLI) s3 sync $(or $(SRC),$(S3_LATEST))/artifacts/ artifacts/ --only-show-errors
	$(AWSCLI) s3 sync $(or $(SRC),$(S3_LATEST))/logs/      logs/      --only-show-errors || true

# ==== ECR Push ====
AWS_REGION ?= us-west-2
AWS_ACCOUNT_ID ?= $(shell aws sts get-caller-identity --query Account --output text 2>/dev/null)
REPO_NAME ?= mlops-sklearn-portfolio
ECR_URI   ?= $(AWS_ACCOUNT_ID).dkr.ecr.$(AWS_REGION).amazonaws.com/$(REPO_NAME)
TAG ?= v$(shell date +%Y%m%d)-1

.PHONY: ecr-login docker-push
ecr-login:
	aws ecr get-login-password --region $(AWS_REGION) \
	| docker login --username AWS --password-stdin $(AWS_ACCOUNT_ID).dkr.ecr.$(AWS_REGION).amazonaws.com

docker-push: docker-build ecr-login
	docker tag $(IMAGE) $(ECR_URI):$(TAG)
	docker tag $(IMAGE) $(ECR_URI):latest
	docker push $(ECR_URI):$(TAG)
	docker push $(ECR_URI):latest
