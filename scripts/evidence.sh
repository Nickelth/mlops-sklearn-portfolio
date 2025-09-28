# scripts/evidence.sh
set -euo pipefail

evo() { # Evidence Output: evo "tag" cmd...
  local tag="$1"; shift
  local ts; ts="$(date +%Y%m%d_%H%M%S)"
  local out="docs/evidence/${ts}_${tag}.log"
  mkdir -p docs/evidence
  local rev; rev="$(git rev-parse --short HEAD 2>/dev/null || echo "n/a")"
  # 1行目はメタ情報(JSON Lines)
  printf '%s\n' \
    "$(jq -n --arg ts "$ts" --arg tag "$tag" --arg rev "$rev" \
      --arg cmd "$*" '{ts:$ts, tag:$tag, git:$rev, cmd:$cmd}')" \
    > "$out"
  # 本体出力（stdout+stderr）を追記、かつ画面にも出す
  { "$@" 2>&1; echo "__EXIT_CODE:$?"; } | tee -a "$out"
  echo "[evidence] wrote $out"
}
