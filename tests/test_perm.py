import json, os, subprocess, sys, pathlib

ROOT = pathlib.Path(__file__).resolve().parents[1]

def run(cmd):
    print("+", " ".join(cmd))
    subprocess.check_call(cmd, cwd=ROOT)

def test_perm_builtin_generates_artifacts(tmp_path):
    # 生成
    run([sys.executable, "-u", "src/perm_importance.py",
         "--dataset", "builtin", "--n-repeats", "3", "--max-samples", "2000"])

    # ファイル確認
    stem = "perm_importance_builtin_breast_cancer"
    png  = ROOT / "artifacts" / f"{stem}.png"
    csvf = ROOT / "artifacts" / f"{stem}.csv"
    jsf  = ROOT / "artifacts" / f"{stem}.json"
    assert png.exists() and png.stat().st_size > 10_000  # だいたい数十KB以上
    assert csvf.exists()
    assert jsf.exists()

    # JSONスキーマ軽チェック
    meta = json.loads(jsf.read_text())
    assert "baseline_score" in meta and 0 <= meta["baseline_score"] <= 1
    assert "top3" in meta and len(meta["top3"]) >= 1
