#!/usr/bin/env bash
# opsx release <slug> [--repo <top>]：協調者補的卡 propose 完放掉 pane。dispatch.json 條目記 released_at，不改 mode、不關 pane；
# pane 由 reap 在 agent idle 時收，收掉後 coordinate 照一般待指派規則重派。specs/dispatch-release。

opsx_release() {
  local slug="" top=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --repo) [ $# -ge 2 ] || die "release: --repo 要接路徑"; top="$2"; shift 2 ;;
      -*) die "release: 不認得的選項 $1" ;;
      *) [ -z "$slug" ] && slug="$1" || die "release: 多餘的參數 $1"; shift ;;
    esac
  done
  [ -n "$slug" ] || die "release: 用法 opsx release <slug> [--repo <path>]"
  [ -n "$top" ] || top="$(git_toplevel)"
  [ -n "$top" ] || die "release: 不在 git repo 裡，或給 --repo"
  local repo; repo="$(basename "$(cd "$top" && pwd -P)")"
  OPSX_KEY="$repo/$slug" OPSX_AT="$(now_iso)" OPSX_LIB="$OPSX_ROOT/bin/lib" "$OPSX_PY" -I - "$OPSX_STATE_DIR/dispatch.json" <<'PY' || exit 2
import os, sys
sys.path.insert(0, os.environ["OPSX_LIB"]); import jsonfile
key = os.environ["OPSX_KEY"]
class Refused(Exception):
    pass
def put(d):
    e = d.get(key)
    if e is None:
        raise Refused("release: %s 沒派過（dispatch.json 沒有這個條目）" % key)
    if e.get("mode") == "stopped":
        raise Refused("release: %s 已經 stopped，不用放掉" % key)
    # 重複放掉時保留第一次的時間
    e.setdefault("released_at", os.environ["OPSX_AT"])
try:
    jsonfile.update(sys.argv[1], put)
except Refused as err:
    sys.exit("opsx: %s" % err)
PY
  say "release: $repo/$slug 放掉了，等 reap 在 agent idle 時收 pane"
}
