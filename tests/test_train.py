# tests/test_train.py
"""
Smoke tests for src/train.py

- Fast test: runs on builtin dataset (breast_cancer) with mode=fast.
- Optional slow test: runs on adult (OpenML) with mode=full.
  Enable by setting environment variable RUN_SLOW=1.

Usage:
  pytest -q
  RUN_SLOW=1 pytest -q -m slow
"""

from __future__ import annotations

import os
import sys
import json
import time
import importlib
from pathlib import Path
from typing import Tuple

import pytest


REPO_ROOT = Path(__file__).resolve().parents[1]
SRC_DIR = REPO_ROOT / "src"


def _import_train_module():
    """Import src/train.py as a module after ensuring src/ on sys.path."""
    if str(SRC_DIR) not in sys.path:
        sys.path.insert(0, str(SRC_DIR))
    # Avoid stale cache if tests re-run in the same interpreter
    for mod in ["train", "datasets"]:
        if mod in sys.modules:
            del sys.modules[mod]
    return importlib.import_module("train")


def _run_train_in_tmp(tmpdir: Path, dataset: str, mode: str) -> Tuple[Path, Path, dict]:
    """
    Run train.main() in a temporary working directory.
    Returns: (model_path, summary_path, summary_json)
    """
    train = _import_train_module()

    old_cwd = Path.cwd()
    try:
        os.chdir(tmpdir)

        # Simulate CLI args
        old_argv = sys.argv[:]
        sys.argv = ["train.py", "--dataset", dataset, "--mode", mode]
        t0 = time.time()
        train.main()  # prints [RESULT] ... and writes artifacts/models
        elapsed = time.time() - t0
        assert elapsed >= 0

    finally:
        sys.argv = old_argv
        os.chdir(old_cwd)

    # Infer dataset label used in filenames from train.py conventions
    dsname_map = {
        "builtin": "builtin_breast_cancer",
        "adult": "openml_adult",
        "credit-g": "openml_credit_g",
        "local": "local_csv",
    }
    dsname = dsname_map[dataset]

    model_path = tmpdir / f"models/model_{dsname}.joblib"
    summary_path = tmpdir / f"artifacts/summary_{dsname}.json"
    cv_csv_path = tmpdir / f"artifacts/cv_results_{dsname}.csv"

    assert model_path.is_file(), f"missing model: {model_path}"
    assert summary_path.is_file(), f"missing summary: {summary_path}"
    assert cv_csv_path.is_file(), f"missing cv csv: {cv_csv_path}"

    with summary_path.open() as f:
        summary = json.load(f)

    # Basic sanity checks on summary contents
    for k in ["dataset", "mode", "auc", "accuracy", "best_params", "elapsed_sec", "cv_splits"]:
        assert k in summary, f"summary missing key: {k}"
    assert 0.0 <= float(summary["auc"]) <= 1.0
    assert 0.0 <= float(summary["accuracy"]) <= 1.0
    assert int(summary["elapsed_sec"]) >= 0
    assert summary["dataset"] == dsname
    assert summary["mode"] == mode

    return model_path, summary_path, summary


def test_train_builtin_fast(tmp_path: Path, capsys):
    """
    Fast smoke: builtin dataset with mode=fast.
    Should finish quickly and produce artifacts and a model.
    """
    model_path, summary_path, summary = _run_train_in_tmp(tmp_path, dataset="builtin", mode="fast")

    # Ensure [RESULT] line was printed
    out, err = capsys.readouterr()
    assert "[RESULT]" in out, "expected [RESULT] line in stdout"

    # Spot-check performance is reasonable (not strict)
    assert summary["auc"] >= 0.95


@pytest.mark.slow
@pytest.mark.skipif(os.environ.get("RUN_SLOW") != "1", reason="set RUN_SLOW=1 to enable slow test")
def test_train_adult_full(tmp_path: Path):
    """
    Optional slow test: adult dataset full mode.
    Uses OpenML and takes ~20s on a modest CPU.
    """
    _run_train_in_tmp(tmp_path, dataset="adult", mode="full")
