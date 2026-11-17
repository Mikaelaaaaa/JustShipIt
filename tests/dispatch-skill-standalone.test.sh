#!/usr/bin/env bash
# dispatch skill 呼叫 opsx dispatch 必須是單獨一個指令：串接的、或用 bash …/bin/opsx 開頭的指令對不上主控 session 的
# excludedCommands「opsx dispatch *」，會留在沙盒裡、建不了 worktree。對應 specs/opsx-dispatch「dispatch skill 用單獨的 opsx dispatch 呼叫」。
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

f="$OPSX_ROOT/skills/dispatch/SKILL.md"
assert_file "$f"
assert_grep "its own Bash command" "$f"      # 規則本身寫在 skill 裡
assert_grep "opsx dispatch \*" "$f"          # 並說明為什麼（對不上排除規則）
assert_not_grep 'bin/opsx" dispatch' "$f"

# check_skill <file>：以 block 為單位讀 fenced code block（``` 開、``` 關，去掉縮排）。散文裡的反引號片段不算範例。
# 不合格時 stderr 第一個字是原因：
#   NO_EXAMPLE  沒有任何 block 含 opsx dispatch
#   MULTI_LINE  含 opsx dispatch 的 block 不只一行非空行
#   PREFIX      那一行不以 `opsx dispatch ` 開頭（含 cd …&&、VAR=… 前綴、bash …/bin/opsx）
#   CHAIN       那一行含 ; & | 反引號 $( ，或以 \ 結尾
check_skill() {
python3 -I - "$1" <<'PY'
import re, sys
blocks, cur = [], None
for line in open(sys.argv[1], encoding="utf-8").read().splitlines():
    s = line.strip()
    if s.startswith("```"):
        if cur is None:
            cur = []
        else:
            blocks.append(cur)
            cur = None
    elif cur is not None:
        cur.append(s)
if cur is not None:
    blocks.append(cur)  # 沒關的 fence 在 markdown 裡延伸到檔尾
hits = [b for b in blocks if any("opsx dispatch" in l for l in b)]
if not hits:
    sys.exit("NO_EXAMPLE: fenced block 裡沒有 opsx dispatch 範例")
for b in hits:
    body = [l for l in b if l]
    if len(body) != 1:
        sys.exit("MULTI_LINE: %r" % body)
    l = body[0]
    if not l.startswith("opsx dispatch "):
        sys.exit("PREFIX: %r" % l)
    if re.search(r"[;&|`]|\$\(", l) or l.endswith("\\"):
        sys.exit("CHAIN: %r" % l)
PY
}

check_skill "$f" || fail "真的 dispatch skill 沒過檢查"

# 把 fenced 範例改壞的每一種寫法，檢查都要擋下來，而且擋的原因要對
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
expect_blocked() { # expect_blocked <name> <新內容> <預期原因 regex>
  mutate "$1" "$2" || fail "mutation $1 寫不出來"
  assert_file "$FX/$1.md"
  cmp -s "$f" "$FX/$1.md" && fail "mutation $1 沒改到檔案"
  check_skill "$FX/$1.md" >/dev/null 2>"$FX/$1.err" && fail "mutation $1 應該被擋下卻通過了"
  grep -qE "^($3):" "$FX/$1.err" || fail "mutation $1 該因 $3 被擋，實際：$(cat "$FX/$1.err")"
}
expect_blocked a 'cd <repo> && opsx dispatch <slug> --agent <a>' PREFIX
expect_blocked b 'opsx dispatch <slug> --agent <a>; echo x' CHAIN
expect_blocked c 'opsx dispatch <slug> | tee log' CHAIN
expect_blocked d 'opsx dispatch $(echo x) --agent <a>' CHAIN
expect_blocked e 'bash ${CLAUDE_PLUGIN_ROOT}/bin/opsx dispatch <slug>' PREFIX
expect_blocked f '' NO_EXAMPLE
expect_blocked g 'OPSX_USER=x opsx dispatch <slug> --agent <a>' PREFIX
expect_blocked h $'cd <repo>\n   opsx dispatch <slug> --agent <a>' MULTI_LINE
expect_blocked i $'opsx dispatch <slug> --agent <a> \\\n     && echo x' 'MULTI_LINE|CHAIN'
expect_blocked j 'opsx dispatch `cat slug` --agent <a>' CHAIN
expect_blocked k 'opsx dispatch <slug> --agent <a> & sleep 1' CHAIN
true
