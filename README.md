# mlops-sklearn-portfolio

```bash

export OMP_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 MKL_NUM_THREADS=1 NUMEXPR_NUM_THREADS=1


# 学習中はスリープ禁止
systemd-inhibit --what=sleep --why="ml-train" bash -lc 'make train'

# 学習起動（邪魔しない礼儀込み）
nice -n 10 python -u src/train.py --mode full 2>&1 | tee logs/train-$(date +%Y%m%d_%H%M%S).log


```
