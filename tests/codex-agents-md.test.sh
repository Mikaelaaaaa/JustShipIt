#!/usr/bin/env bash
# codex-agents-md：規則單一來源（router 與 AGENTS.md 同源）、render_agents_md、dispatch codex 放 AGENTS.md。
# 驗收：specs/codex-agents-md/spec.md
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
export CLAUDE_PLUGIN_ROOT="$OPSX_ROOT"
source "$OPSX_ROOT/bin/lib/rules.sh"

# --- 1.1 router 輸出以 ` · ` 接 rule_autopilot / rule_interactive ---
R="$(mk_repo Acmecorp-AI git@gitlab.example.com:acmecorp/Acmecorp-AI.git)"
mkdir -p "$R/openspec/changes/eval-core" "$OPSX_STATE_DIR"
printf 'schema: opsx\ncreated: 2026-11-05\nkind: dev\n' > "$R/openspec/changes/eval-core/.openspec.yaml"
git -C "$R" checkout -q -b feat/eval-core/mikaela
router() { # <mode> → additionalContext
  printf '{"Acmecorp-AI/eval-core":{"mode":"%s"}}' "$1" > "$OPSX_STATE_DIR/dispatch.json"
  python3 -I -c 'import json,sys;print(json.dumps(dict(cwd=sys.argv[1],tool_name="",tool_input={},prompt="下一步",hook_event_name="UserPromptSubmit")))' "$R" \
    | bash "$OPSX_ROOT/hooks/openspec-router.sh" 2>/dev/null | jq -r '.hookSpecificOutput.additionalContext'
}
ctx_auto="$(router autopilot)"
case "$ctx_auto" in *" · $(rule_autopilot "$R")") ;; *) fail "router autopilot 要以 ' · ' 接 rule_autopilot: $ctx_auto" ;; esac
# R 沒有 tests/run.sh：router 不注入 bash tests/run.sh（agent-20261116-1405）
case "$ctx_auto" in *'bash tests/run.sh'*) fail "沒有 tests/run.sh 的 repo 不該注入 bash tests/run.sh: $ctx_auto" ;; esac
case "$(rule_autopilot "$R")" in *'不用 AskUserQuestion'*'一個 Bash 呼叫做一件事'*) ;; *) fail "rule_autopilot 內容不對: $(rule_autopilot "$R")" ;; esac
ctx_int="$(router interactive)"
case "$ctx_int" in *" · $(rule_interactive)") ;; *) fail "router interactive 要以 ' · ' 接 rule_interactive: $ctx_int" ;; esac

# 測試在 agent 的 worktree 跑，主 checkout 可能在別的分支：router 要看 worktree 有沒有 tests/run.sh
mkdir -p "$R/openspec/changes/eval-wt"
printf 'schema: opsx\ncreated: 2026-11-16\nkind: dev\n' > "$R/openspec/changes/eval-wt/.openspec.yaml"
XW="$R/.claude/worktrees/eval-wt"
git -C "$R" worktree add -q -b feat/eval-wt/mikaela "$XW"
mkdir -p "$XW/tests/sub"; printf '#!/usr/bin/env bash\n' > "$XW/tests/run.sh"
git -C "$XW" add tests/run.sh; git -C "$XW" commit -q -m "add runner"
printf '{"Acmecorp-AI/eval-wt":{"mode":"autopilot"}}' > "$OPSX_STATE_DIR/dispatch.json"
ctx_wt="$(python3 -I -c 'import json,sys;print(json.dumps(dict(cwd=sys.argv[1],tool_name="",tool_input={},prompt="下一步",hook_event_name="UserPromptSubmit")))' "$XW/tests/sub" \
  | bash "$OPSX_ROOT/hooks/openspec-router.sh" 2>/dev/null | jq -r '.hookSpecificOutput.additionalContext')"
case "$ctx_wt" in *'opsx：'*'eval-wt'*) ;; *) fail "router 沒認出 worktree 的卡 eval-wt: $ctx_wt" ;; esac
case "$ctx_wt" in *'bash tests/run.sh'*) ;; *) fail "worktree 有 tests/run.sh、主 checkout 沒有，router 要注入 bash tests/run.sh: $ctx_wt" ;; esac

# test-run-rule-edges Scenario：cwd 在 worktree 的 git 目錄裡時看那棵 worktree（.git/worktrees/<name>/ 沒有 work tree）
XG="$(git -C "$XW" rev-parse --absolute-git-dir)"
case "$XG" in "$(cd "$R/.git" && pwd -P)/worktrees/"*) ;; *) fail "worktree 的 git 目錄應在主 checkout 的 .git/worktrees/ 下: $XG" ;; esac
ctx_xg="$(python3 -I -c 'import json,sys;print(json.dumps(dict(cwd=sys.argv[1],tool_name="",tool_input={},prompt="下一步",hook_event_name="UserPromptSubmit")))' "$XG" \
  | bash "$OPSX_ROOT/hooks/openspec-router.sh" 2>/dev/null | jq -r '.hookSpecificOutput.additionalContext')"
case "$ctx_xg" in *'opsx：'*'eval-wt'*' · autopilot：'*) ;; *) fail "cwd 在 worktree 的 git 目錄裡 router 要認出卡 eval-wt 並注入 autopilot 規則: $ctx_xg" ;; esac
case "$ctx_xg" in *'bash tests/run.sh'*) ;; *) fail "cwd 在 worktree 的 git 目錄裡，router 要看那棵 worktree 的 tests/run.sh: $ctx_xg" ;; esac
# 反例：cwd 在主 checkout 的 .git 裡時看主 checkout（此時主 checkout 沒有 tests/run.sh）；主 checkout 的分支對到卡 eval-core
printf '{"Acmecorp-AI/eval-core":{"mode":"autopilot"}}' > "$OPSX_STATE_DIR/dispatch.json"
ctx_mg="$(python3 -I -c 'import json,sys;print(json.dumps(dict(cwd=sys.argv[1],tool_name="",tool_input={},prompt="下一步",hook_event_name="UserPromptSubmit")))' "$R/.git" \
  | bash "$OPSX_ROOT/hooks/openspec-router.sh" 2>/dev/null | jq -r '.hookSpecificOutput.additionalContext')"
case "$ctx_mg" in *' · autopilot：'*) ;; *) fail "cwd 在主 checkout 的 .git 裡 router 仍要注入 autopilot 規則: $ctx_mg" ;; esac
case "$ctx_mg" in *'bash tests/run.sh'*) fail "cwd 在主 checkout 的 .git 裡要看主 checkout，主 checkout 沒有 tests/run.sh: $ctx_mg" ;; esac

# 反方向：主 checkout 有 tests/run.sh、worktree 的分支沒有，router 不能注入 bash tests/run.sh
mkdir -p "$R/openspec/changes/eval-nr"
printf 'schema: opsx\ncreated: 2026-11-16\nkind: dev\n' > "$R/openspec/changes/eval-nr/.openspec.yaml"
YW="$R/.claude/worktrees/eval-nr"
git -C "$R" worktree add -q -b feat/eval-nr/mikaela "$YW"
mkdir -p "$R/tests"; printf '#!/usr/bin/env bash\n' > "$R/tests/run.sh"
git -C "$R" add tests/run.sh; git -C "$R" commit -q -m "add runner on main checkout"
printf '{"Acmecorp-AI/eval-nr":{"mode":"autopilot"}}' > "$OPSX_STATE_DIR/dispatch.json"
ctx_nr="$(python3 -I -c 'import json,sys;print(json.dumps(dict(cwd=sys.argv[1],tool_name="",tool_input={},prompt="下一步",hook_event_name="UserPromptSubmit")))' "$YW" \
  | bash "$OPSX_ROOT/hooks/openspec-router.sh" 2>/dev/null | jq -r '.hookSpecificOutput.additionalContext')"
case "$ctx_nr" in *'opsx：'*'eval-nr'*) ;; *) fail "router 沒認出 worktree 的卡 eval-nr: $ctx_nr" ;; esac
case "$ctx_nr" in *'bash tests/run.sh'*) fail "worktree 沒有 tests/run.sh、主 checkout 有，router 不該注入 bash tests/run.sh: $ctx_nr" ;; esac
case "$ctx_nr" in *'package.json / pyproject'*) ;; *) fail "worktree 沒有 tests/run.sh，router 要注入 repo 自己測試指令那段: $ctx_nr" ;; esac

# cwd 在 git 目錄裡（沒有 work tree）：卡照樣找得到，router 不能整個死掉
printf '{"Acmecorp-AI/eval-core":{"mode":"autopilot"}}' > "$OPSX_STATE_DIR/dispatch.json"
rc_git=0
out_git="$(python3 -I -c 'import json,sys;print(json.dumps(dict(cwd=sys.argv[1],tool_name="",tool_input={},prompt="下一步",hook_event_name="UserPromptSubmit")))' "$R/.git" \
  | bash "$OPSX_ROOT/hooks/openspec-router.sh" 2>/dev/null)" || rc_git=$?
assert_eq "$rc_git" 0 "cwd 在 .git 裡 router 要 rc 0"
case "$(printf '%s' "$out_git" | jq -r '.hookSpecificOutput.additionalContext')" in *'opsx：'*'eval-core'*' · autopilot：'*) ;; *) fail "cwd 在 .git 裡 router 仍要注入卡與 autopilot 規則: $out_git" ;; esac

# --- 2.1 render_agents_md ---
source "$OPSX_ROOT/bin/lib/agents-md.sh"
has() { case "$1" in *"$2"*) ;; *) fail "${3:-內容}缺 [$2]" ;; esac; }
gone() { case "$1" in *"$2"*) fail "${3:-內容}不該有 [$2]" ;; esac; }
a="$(render_agents_md autopilot "$OPSX_ROOT")"
# 規則的每一段（以 ' · ' 切開）都在檔裡：同源
while IFS= read -r seg; do has "$a" "$seg" "autopilot 規則段"; done < <(rule_autopilot "$OPSX_ROOT" | awk -F' · ' '{ for (i = 1; i <= NF; i++) print $i }')
for s in '主 checkout' 'bash tests/run.sh' 'gates.md' '一個 Bash 呼叫做一件事' 'waiting for merge' '直接做' '要授權' '永遠要人' 'merge' "$OPSX_ROOT/skills" '`/opsx-workflow:<stage> <slug>`'; do has "$a" "$s" autopilot; done
i="$(render_agents_md interactive "$OPSX_ROOT")"
has "$i" "$(rule_interactive)" interactive
gone "$i" '要問人的事寫 gates.md' interactive
gone "$i" '不用 AskUserQuestion' interactive
gone "$a" 'interactive：要授權就直接問' autopilot
rc=0; render_agents_md yolo "$OPSX_ROOT" >/dev/null 2>&1 || rc=$?; assert_eq "$rc" 1 "不認得的模式要失敗"
render_agents_md yolo "$OPSX_ROOT" 2>&1 | grep -q 'yolo' || fail "錯誤訊息要點名模式 yolo"
for s in '直接做' '要授權' '永遠要人'; do has "$(cat "$OPSX_ROOT/references/grants.md")" "$s" grants.md; done
# 把 main 合進自己的分支是直接做；合 MR 才是永遠要人
has "$a" '不自己合 MR' autopilot
gone "$a" '不自己 merge，' autopilot
has "$(grep '^| \*\*直接做\*\*' "$OPSX_ROOT/references/grants.md")" 'git merge' "grants.md 直接做列"
has "$(grep '^| \*\*永遠要人\*\*' "$OPSX_ROOT/references/grants.md")" 'MR' "grants.md 永遠要人列"
# grant-outbound-speech：授權段寫明對外發話閘門不判，要自己先寫 gate
for s in '對客戶或外部人發話' '閘門不判' '沒被擋不代表可以做' '發話前自己寫 `type: approval` 的 gate'; do has "$a" "$s" "autopilot 的授權段"; done

# --- 3.1 / 3.2 / 4.1 dispatch codex ---
FAKES="$OPSX_ROOT/tests/fakes"; mkdir -p "$FX/fakebin"
printf '#!/usr/bin/env bash\nexec bash "%s/herdr" "$@"\n' "$FAKES" > "$FX/fakebin/herdr"; chmod +x "$FX/fakebin/herdr"
export PATH="$FX/fakebin:$PATH"
export OPSX_FAKE_LOG="$FX/herdr.log"; : > "$OPSX_FAKE_LOG"
export OPSX_USER=mikaela
export OPSX_DRIVE_MAX=0
wait_drive() { # <repo> <slug>
  local f="$OPSX_STATE_DIR/drive-$1-$2.log" n=0
  until grep -q '跑滿 [01] 輪' "$f" 2>/dev/null; do n=$((n+1)); [ $n -lt 50 ] || fail "drive 沒在背景起來：$f"; sleep 0.1; done
}
D="$(mk_repo Acmecorp-CS git@gitlab.example.com:acmecorp/Acmecorp-CS.git)"
for c in cx cl; do
  mkdir -p "$D/openspec/changes/$c"; printf 'schema: opsx\ncreated: 2026-11-10\nkind: chore\n' > "$D/openspec/changes/$c/.openspec.yaml"
done
printf '[repos]\n"Acmecorp-CS" = "acmecorp-ai"\n' > "$OPSX_STATE_DIR/workspaces.toml"
EXCL="$(git -C "$D" rev-parse --path-format=absolute --git-path info/exclude)"
cd "$D"

out="$(opsx dispatch cx --agent codex --mode autopilot --kind chore 2>&1)" || fail "dispatch codex autopilot: $out"
wait_drive Acmecorp-CS cx
WT="$D/.claude/worktrees/cx"
assert_file "$WT/AGENTS.md"
has "$(cat "$WT/AGENTS.md")" "$(rule_autopilot "$WT" | awk -F' · ' '{ print $1 }')" "worktree 的 AGENTS.md"
# D 沒有 tests/run.sh：AGENTS.md 拿到 repo 自己測試指令那段，與 router 同源（agent-20261116-1405）
gone "$(cat "$WT/AGENTS.md")" 'bash tests/run.sh' "沒有 tests/run.sh 的 worktree 的 AGENTS.md"
has "$(cat "$WT/AGENTS.md")" 'package.json / pyproject' "沒有 tests/run.sh 的 worktree 的 AGENTS.md"
assert_eq "$(git -C "$WT" status --porcelain)" "" "AGENTS.md 不進 git"
assert_grep "^agent start cx --kind codex --pane w1:pE -- -a never -s workspace-write --add-dir $D/openspec --add-dir $OPSX_STATE_DIR\$" "$OPSX_FAKE_LOG"

opsx stop cx >/dev/null 2>&1 || fail "stop cx"
: > "$OPSX_FAKE_LOG"
out="$(opsx dispatch cx --agent codex --mode interactive 2>&1)" || fail "redispatch codex interactive: $out"
has "$(cat "$WT/AGENTS.md")" "$(rule_interactive)" "重派後的 AGENTS.md"
gone "$(cat "$WT/AGENTS.md")" '要問人的事寫 gates.md' "重派後的 AGENTS.md"
assert_eq "$(grep -cx '/AGENTS.md' "$EXCL")" 1 "info/exclude 的 /AGENTS.md 只該有一行"
assert_grep "^agent start cx --kind codex --pane w1:pE -- -a on-request -s workspace-write --add-dir $D/openspec --add-dir $OPSX_STATE_DIR\$" "$OPSX_FAKE_LOG"

out="$(opsx dispatch cl --agent claude --mode interactive 2>&1)" || fail "dispatch claude: $out"
assert_no_file "$D/.claude/worktrees/cl/AGENTS.md"

# repo 已有 tracked 的 AGENTS.md：原檔不動，寫 AGENTS.override.md
E="$(mk_repo Acmecorp-AI git@gitlab.example.com:acmecorp/Acmecorp-AI.git)"
printf 'repo-rule-xyz\n' > "$E/AGENTS.md"; git -C "$E" add AGENTS.md; git -C "$E" commit -q -m "add AGENTS.md"
mkdir -p "$E/openspec/changes/tr"; printf 'schema: opsx\ncreated: 2026-11-10\nkind: chore\n' > "$E/openspec/changes/tr/.openspec.yaml"
printf '[repos]\n"Acmecorp-CS" = "acmecorp-ai"\n"Acmecorp-AI" = "acmecorp-ai"\n' > "$OPSX_STATE_DIR/workspaces.toml"
cd "$E"
out="$(opsx dispatch tr --agent codex --mode interactive --kind chore 2>&1)" || fail "dispatch codex tracked AGENTS.md: $out"
TW="$E/.claude/worktrees/tr"
assert_eq "$(cat "$TW/AGENTS.md")" "repo-rule-xyz" "tracked 的 AGENTS.md 不能動"
has "$(cat "$TW/AGENTS.override.md")" 'repo-rule-xyz' override
has "$(cat "$TW/AGENTS.override.md")" "$(rule_interactive)" override
assert_eq "$(git -C "$TW" status --porcelain)" "" "override 不進 git"

# repo 有 tests/run.sh：dispatch 出的 AGENTS.md 拿到 bash tests/run.sh 那段，place_agents_md 傳錯根就紅
P="$(mk_repo Acmecorp-Runner git@gitlab.example.com:acmecorp/Acmecorp-Runner.git)"
mkdir -p "$P/tests"; printf '#!/usr/bin/env bash\n' > "$P/tests/run.sh"
git -C "$P" add tests/run.sh; git -C "$P" commit -q -m "add runner"
mkdir -p "$P/openspec/changes/rn"; printf 'schema: opsx\ncreated: 2026-11-16\nkind: chore\n' > "$P/openspec/changes/rn/.openspec.yaml"
printf '[repos]\n"Acmecorp-CS" = "acmecorp-ai"\n"Acmecorp-AI" = "acmecorp-ai"\n"Acmecorp-Runner" = "acmecorp-ai"\n' > "$OPSX_STATE_DIR/workspaces.toml"
cd "$P"
out="$(opsx dispatch rn --agent codex --mode autopilot --kind chore 2>&1)" || fail "dispatch codex 有 tests/run.sh 的 repo: $out"
wait_drive Acmecorp-Runner rn
has "$(cat "$P/.claude/worktrees/rn/AGENTS.md")" 'bash tests/run.sh' "有 tests/run.sh 的 worktree 的 AGENTS.md"
opsx stop rn >/dev/null 2>&1 || fail "stop rn"

# git dir 沒有 info/（自訂 template 的 repo）：exclude 要建得起來，AGENTS.md 不能留成會進 git 的檔
G="$(mk_repo NoInfo)"
rm -rf "$G/.git/info"
assert_rc 0 place_agents_md "$G" autopilot
assert_eq "$(git -C "$G" status --porcelain)" "" "沒有 info/ 時 AGENTS.md 也不進 git"
echo ok
