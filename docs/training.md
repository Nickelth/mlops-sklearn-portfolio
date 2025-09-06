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