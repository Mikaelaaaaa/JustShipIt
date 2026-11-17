#!/usr/bin/env bash
# dispatch skill 呼叫 opsx dispatch 必須是單獨一個指令：串接的、或用 bash …/bin/opsx 開頭的指令對不上主控 session 的
# excludedCommands「opsx dispatch *」，會留在沙盒裡、建不了 worktree。對應 specs/opsx-dispatch「dispatch skill 用單獨的 opsx dispatch 呼叫」。
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

f="$OPSX_ROOT/skills/dispatch/SKILL.md"
assert_file "$f"
assert_grep "its own Bash command" "$f"      # 規則本身寫在 skill 裡
assert_grep "opsx dispatch \*" "$f"          # 並說明為什麼（對不上排除規則）
assert_not_grep 'bin/opsx" dispatch' "$f"
# skill 範例裡的 `opsx dispatch …` 反引號片段與 fenced 範例不帶串接符號，且真的掃到至少一個
python3 -I - "$f" <<'PY' || fail "dispatch skill 的 opsx dispatch 範例有串接或一個都沒有"
import re, sys
text = open(sys.argv[1], encoding="utf-8").read()
snippets = re.findall(r"`(opsx dispatch [^`]*)`", text)
snippets += re.findall(r"^\s*(opsx dispatch .*)$", text, re.M)
if not snippets:
    sys.exit("沒有 opsx dispatch 範例")
bad = [s for s in snippets if re.search(r"[;|]|&&|\$\(", s)]
if bad:
    sys.exit("串接的 opsx dispatch 範例：%r" % bad)
PY
