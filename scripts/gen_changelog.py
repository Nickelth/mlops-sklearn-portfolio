#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
ソースコードのdiffをそのままMarkdownに出力するやつ。
- コミット範囲(--from .. --to) か 日付範囲(--since/--until) 指定
- 出力は1枚(--out) か 日毎分割(--daily-outdir)
- パスフィルタ(--paths 'api/* infra/*.tf Makefile pyproject.toml' など) で対象を絞れる
"""

import argparse
import os
import shlex
import subprocess
from datetime import datetime, timedelta, date
from pathlib import Path

def run(cmd: str) -> str:
    return subprocess.check_output(cmd, shell=True, text=True, stderr=subprocess.DEVNULL).strip()

def git_commits_by_range(commit_from: str, commit_to: str) -> list[tuple[str,str,str]]:
    fmt = "%H%x1f%ad%x1f%s"
    out = run(f'git log --no-merges --date=iso-local --pretty=format:"{fmt}" {commit_from}..{commit_to}')
    rows = []
    for line in out.splitlines():
        h, ad, sub = line.split("\x1f", 2)
        rows.append((h, ad, sub))
    # 古い→新しい順で並べ替え
    rows.sort(key=lambda x: x[1])
    return rows

def git_commits_by_date(since: str, until: str) -> list[tuple[str,str,str]]:
    fmt = "%H%x1f%ad%x1f%s"
    out = run(f'git log --no-merges --date=iso-local --pretty=format:"{fmt}" --since "{since}" --until "{until}"')
    rows = []
    for line in out.splitlines():
        h, ad, sub = line.split("\x1f", 2)
        rows.append((h, ad, sub))
    rows.sort(key=lambda x: x[1])
    return rows

def commit_parent(c: str) -> str:
    # 初回コミットの場合は空になりがちなので /dev/null との比較に落とす
    try:
        return run(f"git rev-list --parents -n 1 {c}").split()[1]
    except Exception:
        return ""

def git_diff(parent: str, child: str, paths: list[str]) -> str:
    path_args = " ".join(shlex.quote(p) for p in paths) if paths else ""
    if parent:
        cmd = f"git diff --unified=3 --no-color {parent} {child} -- {path_args}".strip()
    else:
        # ルート比較（初回コミット）
        cmd = f"git show --pretty=format: --patch --unified=3 {child} -- {path_args}".strip()
    try:
        diff = run(cmd)
    except subprocess.CalledProcessError:
        diff = ""
    return diff

def ensure_dir(p: str):
    Path(p).parent.mkdir(parents=True, exist_ok=True)

def write_md(path: str, content: str):
    ensure_dir(path)
    with open(path, "w", encoding="utf-8") as f:
        f.write(content)

def md_escape_title(s: str) -> str:
    return s.replace("<","&lt;").replace(">","&gt;")

def group_by_date(commits: list[tuple[str,str,str]]) -> dict[str, list[tuple[str,str,str]]]:
    by = {}
    for h, ad, sub in commits:
        d = datetime.fromisoformat(ad.replace("Z","+00:00")).astimezone().strftime("%Y-%m-%d")
        by.setdefault(d, []).append((h, ad, sub))
    return by

def daily_loop(since: str, until: str):
    d0 = date.fromisoformat(since)
    d1 = date.fromisoformat(until)
    d = d0
    while d <= d1:
        yield d.strftime("%Y-%m-%d"), (d + timedelta(days=1)).strftime("%Y-%m-%d")
        d += timedelta(days=1)

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--from", dest="cfrom", help="older commit/tag")
    ap.add_argument("--to", dest="cto", help="newer commit/tag")
    ap.add_argument("--since", help="YYYY-MM-DD")
    ap.add_argument("--until", help="YYYY-MM-DD")
    ap.add_argument("--paths", nargs="*", default=[], help="globパターンで対象ファイルを絞る")
    ap.add_argument("--out", help="単一Markdownの出力先（例: docs/CHANGELOG.md）")
    ap.add_argument("--daily-outdir", help="日毎に出力するディレクトリ（例: docs/evidence/daily）")
    ap.add_argument("--namefmt", default="CHANGELOG_%Y-%m-%d.md", help="日毎ファイル名フォーマット")
    args = ap.parse_args()

    if args.cfrom and args.cto:
        commits = git_commits_by_range(args.cfrom, args.cto)
        mode = "range"
    elif args.since and args.until:
        mode = "date"
        commits = git_commits_by_date(args.since, args.until)
    else:
        print("範囲指定がない。--from/--to か --since/--until を渡せ。"); exit(1)

    if not commits:
        print("該当コミットなし。"); exit(0)

    if args.daily_outdir:
        # 日毎にファイルを分ける
        if mode == "range":
            # コミット範囲を日付に再グループ
            by = group_by_date(commits)
            days = sorted(by.keys())
            for d in days:
                title = f"# Changelog (diff) {d}\n"
                body = []
                for h, ad, sub in by[d]:
                    p = commit_parent(h)
                    diff = git_diff(p, h, args.paths)
                    if not diff.strip():
                        continue
                    body.append(f"## {md_escape_title(sub)}  \n`{h[:7]}` {ad}\n\n```diff\n{diff}\n```\n")
                if not body:
                    continue
                fname = datetime.strptime(d, "%Y-%m-%d").strftime(args.namefmt)
                outpath = os.path.join(args.daily_outdir, fname)
                write_md(outpath, title + "\n".join(body))
                print(f"Wrote {outpath}")
        else:
            # since/untilで完全日次に
            Path(args.daily_outdir).mkdir(parents=True, exist_ok=True)
            for d, n in daily_loop(args.since, args.until):
                sub_commits = git_commits_by_date(d, n)
                if not sub_commits:
                    continue
                title = f"# Changelog (diff) {d}\n"
                body = []
                for h, ad, sub in sub_commits:
                    p = commit_parent(h)
                    diff = git_diff(p, h, args.paths)
                    if not diff.strip():
                        continue
                    body.append(f"## {md_escape_title(sub)}  \n`{h[:7]}` {ad}\n\n```diff\n{diff}\n```\n")
                if not body:
                    continue
                fname = datetime.strptime(d, "%Y-%m-%d").strftime(args.namefmt)
                outpath = os.path.join(args.daily_outdir, fname)
                write_md(outpath, title + "\n".join(body))
                print(f"Wrote {outpath}")
    else:
        # 単一ファイルへまとめる
        title = "# Changelog (diff)\n"
        meta = []
        if mode == "range":
            meta.append(f"- Range: `{args.cfrom}` .. `{args.cto}`")
        else:
            meta.append(f"- Since: {args.since}, Until: {args.until}")
        if args.paths:
            meta.append(f"- Paths: {' '.join(args.paths)}")
        head = title + "\n" + "\n".join(meta) + "\n"
        body = []
        for h, ad, sub in commits:
            p = commit_parent(h)
            diff = git_diff(p, h, args.paths)
            if not diff.strip():
                continue
            body.append(f"## {md_escape_title(sub)}  \n`{h[:7]}` {ad}\n\n```diff\n{diff}\n```\n")
        out = head + "\n".join(body) if body else head + "\n(差分なし)\n"
        outpath = args.out or "docs/CHANGELOG.md"
        write_md(outpath, out)
        print(f"Wrote {outpath}")

if __name__ == "__main__":
    main()
