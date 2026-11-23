#!/usr/bin/env bash
# opsx dedup <slug>… --repo <path>：在 lead 判過重複的收件匣卡上蓋 dedup_checked 記號；coordinate 只補有記號的卡。
# opsx dedup --candidates --repo <path>：列出還沒判的 P0/P1 收件匣卡，與跟它提到同一個檔案的其他收件匣卡。
# specs/inbox-dedup-stamp。寫入與比對在 dedup.py。

# shellcheck source=/dev/null
source "$OPSX_ROOT/bin/lib/collect.sh"

opsx_dedup() {
  local top="" cand=0 slugs=() s
  local usage="dedup: 用法 opsx dedup <slug>… --repo <path> | opsx dedup --candidates --repo <path>"
  while [ $# -gt 0 ]; do
    case "$1" in
      --repo) [ $# -ge 2 ] || die "$usage"; top="$2"; shift 2 ;;
      --candidates) cand=1; shift ;;
      -*) die "dedup: 不認得的選項 $1" ;;
      *) slugs+=("$1"); shift ;;
    esac
  done
  [ -n "$top" ] || die "$usage"
  top="$(opsx_repo_top "$top")"
  if [ "$cand" = 1 ]; then
    [ "${#slugs[@]}" -eq 0 ] || die "$usage"
    opsx_collect --root "$(dirname "$top")" | "$OPSX_PY" -I "$OPSX_ROOT/bin/lib/dedup.py" candidates "$top"
    return
  fi
  [ "${#slugs[@]}" -gt 0 ] || die "$usage"
  for s in "${slugs[@]}"; do
    [[ "$s" =~ ^[a-z][a-z0-9_-]{0,31}$ ]] || die "dedup: slug 不合格：$s"
  done
  "$OPSX_PY" -I "$OPSX_ROOT/bin/lib/dedup.py" stamp "$top" "$(now_iso)" "${slugs[@]}"
}
