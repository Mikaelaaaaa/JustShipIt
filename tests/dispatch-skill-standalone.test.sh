#!/usr/bin/env bash
# dispatch skill 呼叫 opsx dispatch 必須是單獨一個指令：串接的、或用 bash …/bin/opsx 開頭的指令對不上主控 session 的
# excludedCommands「opsx dispatch *」，會留在沙盒裡、建不了 worktree。對應 specs/opsx-dispatch「dispatch skill 用單獨的 opsx dispatch 呼叫」。
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

f="$OPSX_ROOT/skills/dispatch/SKILL.md"
assert_file "$f"
assert_grep "its own Bash command" "$f"      # 規則本身寫在 skill 裡
assert_grep "opsx dispatch \*" "$f"          # 並說明為什麼（對不上排除規則）
assert_not_grep 'bin/opsx" dispatch' "$f"

# check_skill <file>：fenced code block 裡每一行提到 dispatch 的都以 `opsx dispatch ` 開頭、不帶串接符號，
# 不經 bin/opsx，且至少有一行 opsx dispatch（散文裡的反引號片段不算範例）
check_skill() {
python3 -I - "$1" <<'PY'
import re, sys
lines = open(sys.argv[1], encoding="utf-8").read().splitlines()
fenced, inside = [], False
for line in lines:
    if line.strip().startswith("```"):
        inside = not inside
    elif inside and line.strip():
        fenced.append(line.strip())
hits = [l for l in fenced if "dispatch" in l]
if not any("opsx dispatch" in l for l in hits):
    sys.exit("fenced block 裡沒有 opsx dispatch 範例")
bad = [l for l in hits
       if not l.startswith("opsx dispatch ")
       or re.search(r";|&&|\||\$\(", l)
       or "bin/opsx dispatch" in l or 'bin/opsx" dispatch' in l]
if bad:
    sys.exit("不是單獨一個 opsx dispatch 指令的 fenced 範例：%r" % bad)
PY
}

check_skill "$f" || fail "真的 dispatch skill 沒過檢查"

# 把 fenced 範例改壞的每一種寫法，檢查都要擋下來
fenced='opsx dispatch <slug> --agent <a> --model <m> --mode <mode> --kind <kind>'
grep -qF -- "$fenced" "$f" || fail "skill 的 fenced 範例變了，更新這個測試的 fenced 字串"
mutate() { # mutate <name> <取代 fenced 那行的新內容>；空字串 = 整個 fenced block 刪掉
  python3 -I - "$f" "$FX/$1.md" "$fenced" "$2" <<'PY'
import re, sys
src, dst, old, new = sys.argv[1:5]
text = open(src, encoding="utf-8").read()
if new:
    text = text.replace(old, new)
else:
    text = re.sub(r"[ \t]*```bash\n.*?```\n", "", text, flags=re.S)
open(dst, "w", encoding="utf-8").write(text)
PY
}
mutate a 'cd <repo> && opsx dispatch <slug> --agent <a>'
mutate b 'opsx dispatch <slug> --agent <a>; echo x'
mutate c 'opsx dispatch <slug> | tee log'
mutate d 'opsx dispatch $(echo x) --agent <a>'
mutate e 'bash ${CLAUDE_PLUGIN_ROOT}/bin/opsx dispatch <slug>'
mutate f ''
for m in a b c d e f; do
  cmp -s "$f" "$FX/$m.md" && fail "mutation $m 沒改到檔案"
  check_skill "$FX/$m.md" >/dev/null 2>&1 && fail "mutation $m 應該被擋下卻通過了"
done
true
