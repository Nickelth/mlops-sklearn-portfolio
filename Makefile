SHELL := /bin/bash
.SHELLFLAGS := -o pipefail -c

.PHONY: init train train-fast train-full train-both api check envinfo clean

VENV ?= venv
STAMP := $(VENV)/.ok
PY := $(VENV)/bin/python -u

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
	env $(BLAS) nice -n 10 $(PY) src/train.py --dataset $(DS) --mode $(MODE) 2>&1 | tee logs/train-$(TS).log

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

# 実行系の見える化（これが通ればpandasはそのPythonに入ってる）
envinfo: | venv
	@echo "PYTHON  : $$($(PY) -c 'import sys;print(sys.executable)')"
	@$(PY) -c 'import sys,sklearn,pandas;print("py",sys.version.split()[0],"sklearn",sklearn.__version__,"pandas",pandas.__version__)'

check:
	@grep -E "^\[RESULT\]|^=== TRAIN DONE ===|^Traceback|^ERROR" -n logs/train-*.log | tail -n 30 || true
	@ls -lh models/model_*.joblib artifacts/summary_*.json 2>/dev/null || true

clean:
	rm -rf cache __pycache__
