#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
git からコミット差分を日付ごとにまとめて CHANGELOG を生成するやつ。
使い方:
  python scripts/gen_changelog.py --from <old> --to <new> --out docs/CHANGELOG.md
  python scripts/gen_changelog.py --since 2025-09-14 --until 2025-09-27 --out docs/evidence/CHANGELOG-%Y%M%D.md
"""
import argparse, subprocess, sys, os, json
from datetime import datetime, timezone
from collections import defaultdict

SECTIONS = [
    ("Infra",    lambda p: p.startswith("infra/") or p in {"infra.tf","ecs.tf"}),
    ("API",      lambda p: p.startswith("api/")),
    ("Makefile", lambda p: os.path.basename(p) == "Makefile"),
    ("Config",   lambda p: os.path.basename(p) in {"pyproject.toml", "requirements.txt"}),
    ("Tests",    lambda p: p.startswith("tests/")),
    ("Docs",     lambda p: p.startswith("docs/")),
    ("Scripts",  lambda p: p.startswith("scripts/")),
    ("Other",    lambda p: True),
]

HINT_WORDS = [
    ("MODEL_S3_URI", "Fetch model from S3"),
    ("deployment_circuit_breaker", "ECS: deployment circuit breaker"),
    ("health_check_grace_period_seconds", "ECS: health check grace"),
    ("boto3", "Add boto3 runtime dep"),
    ("uvicorn", "ASGI server wiring"),
    ("scikit-learn", "sklearn version pin/upgrade"),
    ("/health", "Health endpoint"),
    ("/metrics", "Metrics endpoint"),
    ("MODEL_PATH", "Model path handling"),
]

def sh(cmd):
    return subprocess.check_output(cmd, shell=True, text=True, stderr=subprocess.DEVNULL).strip()

def git_log_list(args):
    base = ["git", "log", "--no-merges", "--pretty=format:%H%x1f%ad%x1f%an%x1f%s%x1f%b", "--date=iso-local"]
    if args.commit_from and args.commit_to:
        base.append(f"{args.commit_from}..{args.commit_to}")
    elif args.since or args.until:
        if args.since: base += ["--since", args.since]
        if args.until: base += ["--until", args.until]
    else:
        print("範囲指定がない。--from/--to か --since/--until を渡せ。", file=sys.stderr); sys.exit(1)
    out = subprocess.check_output(base, text=True)
    logs = []
    for line in out.splitlines():
        parts = line.split("\x1f")
        if len(parts) < 4: 
            continue
        commit, ad, author, subject = parts[:4]
        body = parts[4] if len(parts) > 4 else ""
        logs.append((commit, ad, author, subject.strip(), body.strip()))
    return logs

def files_changed(commit):
    out = sh(f"git show --name-only --pretty=format: {commit}")
    files = [p for p in (x.strip() for x in out.splitlines()) if p]
    return files

def sectionize(files):
    buckets = defaultdict(list)
    for f in files:
        for name, pred in SECTIONS:
            if pred(f):
                buckets[name].append(f); break
    # 唯一性確保
    for k in list(buckets.keys()):
        buckets[k] = sorted(sorted(set(buckets[k])), key=lambda x: (x.count("/"), x))
    return buckets

def find_hints(diff_text):
    hits = []
    for key, label in HINT_WORDS:
        if key in diff_text:
            hits.append(label)
    return hits

def summarize_commit(commit):
    files = files_changed(commit)
    diffsnips = sh(f"git show --pretty=format: --unified=0 {commit}")[:100000]
    hints = find_hints(diffsnips)
    return files, hints

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--from", dest="commit_from", help="older commit/tag")
    ap.add_argument("--to", dest="commit_to", help="newer commit/tag")
    ap.add_argument("--since", help="YYYY-MM-DD")
    ap.add_argument("--until", help="YYYY-MM-DD")
    ap.add_argument("--out", default="docs/evidence/CHANGELOG_%Y-%m-%d.md")
    ap.add_argument("--append", action="store_true", help="append instead of overwrite")
    args = ap.parse_args()

    logs = git_log_list(args)
    if not logs:
        print("該当コミットなし", file=sys.stderr); sys.exit(1)

    # 日付ごとにまとめる（ローカル日付）
    by_date = defaultdict(list)
    for commit, ad, author, subject, body in logs:
        dt = datetime.fromisoformat(ad.replace("Z","+00:00")).astimezone().strftime("%Y-%m-%d")
        by_date[dt].append((commit, author, subject, body))

    # 新しい日付が上
    days = sorted(by_date.keys(), reverse=True)

    lines = []
    # ヘッダ
    head = sh("git rev-parse --short HEAD") if not (args.commit_from and args.commit_to) else f"{args.commit_from[:7]}..{args.commit_to[:7]}"
    now = datetime.now().astimezone().strftime("%Y-%m-%d %H:%M %Z")
    lines.append(f"# Changelog ({head})  \nGenerated at {now}\n")

    for d in days:
        lines.append(f"\n## {d}\n")
        for (commit, author, subject, body) in by_date[d]:
            files, hints = summarize_commit(commit)
            buckets = sectionize(files)
            lines.append(f"- {subject}  \n  `{commit[:7]}` by {author}")
            # ヒント（重要変更のにおい）
            if hints:
                lines.append(f"  - hints: " + ", ".join(sorted(set(hints))))
            # 主要セクション優先
            for sec in ["Infra","API","Makefile","Config","Tests","Docs","Scripts","Other"]:
                if sec in buckets:
                    fl = ", ".join(buckets[sec][:6]) + (" …" if len(buckets[sec]) > 6 else "")
                    lines.append(f"  - {sec}: {fl}")

    os.makedirs(os.path.dirname(args.out), exist_ok=True)
    mode = "a" if args.append else "w"
    with open(args.out, mode, encoding="utf-8") as f:
        f.write("\n".join(lines).rstrip() + "\n")

    print(f"Wrote {args.out}")

if __name__ == "__main__":
    main()
