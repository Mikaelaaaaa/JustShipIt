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
  OPSX_KEY="$repo/$slug" OPSX_AT="$(now_iso)" OPSX_LIB="$OPSX_ROOT/bin/lib" "$OPSX_PY" -I - "$OPSX_STATE_DIR/dispatch.json" "$top/openspec/changes/$slug" <<'PY' || exit 2
import os, re, sys
sys.path.insert(0, os.environ["OPSX_LIB"]); import jsonfile
key, card = os.environ["OPSX_KEY"], sys.argv[2]
AUTOFILL_MARK = "協調者補卡"   # coordinate.py 的 AUTOFILL_MARK
class Refused(Exception):
    pass
# 段落範圍跟 note.sh 的 note_append、collect 的 notes_of 一樣：## 派工指示 到下一個 ## 為止
def dispatch_notes(path):
    try:
        with open(path, encoding="utf-8") as f:
            lines = f.read().splitlines()
    except FileNotFoundError:
        return []
    head = next((i for i, l in enumerate(lines) if re.fullmatch(r"## 派工指示\s*", l)), None)
    if head is None:
        return []
    body = []
    for l in lines[head + 1:]:
        if l.startswith("## "):
            break
        body.append(l)
    return body
# 只有 propose 完的協調者補卡能放掉：沒有 tasks.md 放掉會把沒 propose 的卡丟回待指派，沒有記號的不是補卡
def check_card():
    if not os.path.isfile(os.path.join(card, "tasks.md")):
        raise Refused("release: %s 還沒有 tasks.md（%s），propose 完才放掉" % (key, card))
    if not any(AUTOFILL_MARK in l for l in dispatch_notes(os.path.join(card, "inbox.md"))):
        raise Refused("release: %s 的派工指示沒有「%s」，不是協調者補的卡，不放掉" % (key, AUTOFILL_MARK))
def put(d):
    e = d.get(key)
    if e is None:
        raise Refused("release: %s 沒派過（dispatch.json 沒有這個條目）" % key)
    if e.get("mode") == "stopped":
        raise Refused("release: %s 已經 stopped，不用放掉" % key)
    # 重複放掉時保留第一次的時間
    e.setdefault("released_at", os.environ["OPSX_AT"])
try:
    check_card()
    jsonfile.update(sys.argv[1], put)
except Refused as err:
    sys.exit("opsx: %s" % err)
PY
  say "release: $repo/$slug 放掉了，等 reap 在 agent idle 時收 pane"
}
