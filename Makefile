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

