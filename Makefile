PY := python -u
TS := $(shell date +%Y%m%d_%H%M%S)
BLAS := OMP_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 MKL_NUM_THREADS=1 NUMEXPR_NUM_THREADS=1
DS ?= builtin
MODE ?= fast

train:
	mkdir -p logs models cache artifacts
	env $(BLAS) nice -n 10 $(PY) src/train.py --dataset $(DS) --mode $(MODE) 2>&1 | tee logs/train-$(TS).log

train-fast:
	$(MAKE) train MODE=fast

train-full:
	$(MAKE) train MODE=full

check:
	@grep -E "^\[RESULT\]|^=== TRAIN DONE ===|^Traceback|^ERROR" -n logs/train-*.log | tail -n 30 || true
	@ls -lh models/model_*.joblib artifacts/summary_*.json 2>/dev/null || true
