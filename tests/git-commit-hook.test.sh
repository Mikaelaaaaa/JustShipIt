#!/usr/bin/env bash
# git 端 commit 閘門（prepare-commit-msg）：agent 的 commit 在真的發生時照卡判斷，人的 commit 不判斷。
# 驗收：openspec/changes/commit-gate-git-hook/subs/git-commit-hook/specs/commit-gate-git-hook/spec.md
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
HOOK="$OPSX_ROOT/hooks/git-prepare-commit-msg.sh"
install_hook() { git -C "$1" config hook.opsx.event prepare-commit-msg; git -C "$1" config hook.opsx.command "bash '$HOOK'"; }

R="$(mk_repo gitgateR)"; mk_change "$R" card
printf 'prs:\n  - name: card\n    status: in-progress\n' > "$R/openspec/workplan.yaml"
printf 'openspec/\n' >> "$R/.git/info/exclude"
C="$R/openspec/changes/card"
printf '## 1. x\n\n- [ ] 1.1 a\n' > "$C/tasks.md"
install_hook "$R"
N="$(mk_repo gitgateN)"; install_hook "$N"

n=0; stage() { n=$((n + 1)); echo "$n" > "$1/f.txt"; git -C "$1" add f.txt; }
head_of() { git -C "$1" rev-parse HEAD; }
# agent <session 目錄> <指令>：在 bash 裡照原樣執行；R、N 換成 fixture 路徑
agent() { ( cd "$1" && env -u OPSX_CARD CLAUDECODE=1 bash -c "$2" ) >"$FX/out" 2>"$FX/err"; }
human() { ( cd "$1" && env -u OPSX_CARD -u CLAUDECODE bash -c "$2" ) >"$FX/out" 2>"$FX/err"; }

# --- 人的 commit 不判斷 ---
stage "$R"; h="$(head_of "$R")"
human "$R" 'git commit -q -m x'
[ "$(head_of "$R")" != "$h" ] || fail "人在卡未勾的 repo commit 要放行: $(cat "$FX/err")"
stage "$R"; h="$(head_of "$R")"
( cd "$R" && env -u OPSX_CARD CLAUDECODE=0 git commit -q -m x ) 2>"$FX/err"
[ "$(head_of "$R")" != "$h" ] || fail "CLAUDECODE=0 不算 agent: $(cat "$FX/err")"
git -C "$R" checkout -q -b side "$h"; echo side > "$R/s.txt"; git -C "$R" add s.txt; human "$R" 'git commit -q -m side'
git -C "$R" checkout -q feat/card/mikaela; echo main > "$R/g.txt"; git -C "$R" add g.txt; human "$R" 'git commit -q -m main'
h="$(head_of "$R")"
human "$R" 'git merge -q --no-edit side'
assert_eq "$(git -C "$R" rev-list --count --merges "$h"..HEAD)" 1 "人的 merge commit 要放行: $(cat "$FX/err")"

# --- 放行寫法在 git 端都擋下（tasks 全未勾） ---
blocked() { # <session 目錄> <指令>
  stage "$R"; local h; h="$(head_of "$R")"
  agent "$1" "$2"
  assert_eq "$(head_of "$R")" "$h" "要擋下：$2｜$(cat "$FX/err")"
  grep -q 'opsx commit 閘門' "$FX/err" || fail "stderr 要含「opsx commit 閘門」：$2｜$(cat "$FX/err")"
  git -C "$R" reset -q --hard
}
blocked "$N" "(cd $R; git commit -m x)"
blocked "$N" "echo \"use git commit here\"; (cd $R; git \"commit\" -m x)"
blocked "$R" "echo \"use git commit here\"; bash -c \"cd $N\"; git commit -m x"
blocked "$R" "echo 'git commit [no-change]'; git commit -m x"
blocked "$R" "git commit -m \"x\\\"\" ; echo \"[no-change]\""
blocked "$R" "git commit -m it\\'s ; echo '[no-change]'"
blocked "$R" "git commit -m x # [no-change]"
blocked "$R" "git commit>LOG -m x"
blocked "$N" "git -c alias.ci='!git -C $R commit -m x' ci"
blocked "$R" "env -S 'git commit -m x'"
blocked "$R" "printf 'git commit -m x\\n' > f.sh; bash f.sh"
if ( cd / && env -C "$R" true ) 2>/dev/null; then
  blocked "$N" "if env -C $R git commit -m x; then :; fi"
  blocked "$N" "time env -C $R git commit -m x"
  blocked "$N" "command env -C $R git commit -m x"
  blocked "$N" "env -C $R sh -c 'git commit -m x'"
  blocked "$N" "env -C$R git commit -m x"
else
  echo "skip: 這台的 env 不支援 -C，env -C 的五列不跑" >&2
fi

# --- [no-change] 只看訊息 ---
blocked "$R" "git commit -m x; echo '[no-change]'"
stage "$R"; h="$(head_of "$R")"
agent "$R" "git commit -q -m 'wip: 停在 1.2 [no-change]'"
[ "$(head_of "$R")" != "$h" ] || fail "訊息帶 [no-change] 要放行: $(cat "$FX/err")"
assert_grep gitgateR "$OPSX_STATE_DIR/bypass.log"

# --- branch 對不到卡 ---
git -C "$R" checkout -q -b feat/nocard/u
blocked "$R" 'git commit -m x'
grep -q 'feat/nocard/u' "$FX/err" || fail "stderr 要含 branch 名: $(cat "$FX/err")"

# --- 子殼有 tasks.md 就放行 ---
mkdir -p "$C/subs/sub"; printf '## 1. x\n\n- [ ] 1.1 a\n' > "$C/subs/sub/tasks.md"
git -C "$R" checkout -q -b feat/card--sub/mikaela
stage "$R"; h="$(head_of "$R")"
( cd "$R" && env -u CLAUDECODE OPSX_CARD=m git commit -q -m x ) 2>"$FX/err"
[ "$(head_of "$R")" != "$h" ] || fail "子殼有 tasks.md 要放行: $(cat "$FX/err")"
rm "$C/subs/sub/tasks.md"
blocked "$R" 'git commit -m x'
grep -q 'tasks.md' "$FX/err" || fail "子殼沒有 tasks.md 要說原因: $(cat "$FX/err")"

# --- 沒有 workplan 的 repo 放行 ---
stage "$N"; h="$(head_of "$N")"
agent "$N" 'git commit -q -m x'
[ "$(head_of "$N")" != "$h" ] || fail "沒有 workplan 的 repo 要放行: $(cat "$FX/err")"

# --- 主殼有勾就放行，量一次耗時 ---
git -C "$R" checkout -q feat/card/mikaela
printf '## 1. x\n\n- [x] 1.1 a\n' > "$C/tasks.md"
stage "$R"; h="$(head_of "$R")"
t0="$EPOCHREALTIME"; agent "$R" 'git commit -q -m x'; t1="$EPOCHREALTIME"
[ "$(head_of "$R")" != "$h" ] || fail "主殼有勾要放行: $(cat "$FX/err")"
echo "agent commit 耗時 $(( (${t1/./} - ${t0/./}) / 1000 )) ms" >&2

# --- 讀不到主 checkout 就擋 ---
REAL_GIT="$(command -v git)"
mkdir -p "$FX/fakegit"
printf '#!/usr/bin/env bash\ncase " $* " in *" --git-common-dir "*) exit 1 ;; esac\nexec "%s" "$@"\n' "$REAL_GIT" > "$FX/fakegit/git"
chmod +x "$FX/fakegit/git"
printf 'x\n' > "$FX/msg"
( cd "$R" && env -u OPSX_CARD CLAUDECODE=1 PATH="$FX/fakegit:$PATH" bash "$HOOK" "$FX/msg" ) 2>"$FX/err"; rc=$?
[ $rc -ne 0 ] || fail "git-common-dir 讀不到要擋"
grep -q '主 checkout' "$FX/err" || fail "stderr 要含「主 checkout」: $(cat "$FX/err")"
( cd "$R" && env -u OPSX_CARD CLAUDECODE=1 bash "$HOOK" "$FX/msg" ) 2>"$FX/err"; rc=$?
assert_eq "$rc" 0 "讀得到時照常判斷: $(cat "$FX/err")"
echo ok
