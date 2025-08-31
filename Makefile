PY := python -u
TS := $(shell date +%Y%m%d_%H%M%S)
BLAS := OMP_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 MKL_NUM_THREADS=1 NUMEXPR_NUM_THREADS=1

train:
	mkdir -p logs models cache artifacts
	env $(BLAS) nice -n 10 $(PY) src/train.py --mode full 2>&1 | tee logs/train-$(TS).log

train-fast:
	env $(BLAS) nice -n 10 $(PY) src/train.py --mode fast 2>&1 | tee logs/train-$(TS).log
