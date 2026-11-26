#!/usr/bin/env bash
# skills/apply/SKILL.md 的子 change 一節：分配規則與 subagent 的 brief。只證明規則寫在對的段落；agent 守不守由 eval 驗。
# 驗收：openspec/changes/apply-fanout/specs/subchange-apply/spec.md「apply skill 寫明分配規則」
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
SK="$OPSX_ROOT/skills/apply/SKILL.md"
assert_file "$SK"
has() { grep -qF -- "$1" "$2" || fail "'$1' not in $(basename "$2")"; }
section() { awk -v h="## $1" '/^```/{fence=!fence} index($0,h)==1{on=1;print;next} !fence && /^## /{on=0} on' "$SK"; }
SUBS="$FX/subs"
section "When the main change has subs/" > "$SUBS"
[ -s "$SUBS" ] || fail "section missing: When the main change has subs/"

# --- Scenario：apply skill 寫明分配規則 ---
for k in '先 propose 沒有 tasks.md 的子殼' 'depends-on' 'subagent' '<主>--<子>' 'DONE <子> <sha>' 'NEEDS-USER <子>' '子殼的 gates.md' '不 push'; do
  has "$k" "$SUBS"
done

# --- Scenario：apply skill 寫明疊回規則（openspec/changes/apply-fanout/specs/subchange-stack/spec.md）---
for k in 'opsx stack' 'workplan 順序' '退出 3' 'session 自己重做' '/opsx-workflow:review' '/opsx-workflow:pr' '不在衝突標記上手解'; do
  has "$k" "$SUBS"
done

# --- stop-gate-waits-on-subagents：收到 DONE 要把子殼 status 寫成 n/n，Stop hook 才不把等疊當成 subagent 在跑 ---
has 'opsx status apply <total>/<total>' "$SUBS"
has '--sub <子> --worker session' "$SUBS"
has 'anything that is not `NEEDS-USER`' "$SUBS"

# --- me-20261111-1326：subagent 不勾子殼 tasks.md（commit 閘門只要求檔案存在），session 疊上 PR branch 時勾 ---
has 'does not check off the sub-shell' "$SUBS"
has 'only requires' "$SUBS"
has 'the session checks off' "$SUBS"
! grep -qF 'the commit gate reads the sub-shell' "$SUBS" || fail "apply 子 change 一節不能再說 commit 閘門讀子殼的勾"

# --- grant-action：授權 gate 要寫 action:，值取自 hook 的 deny 訊息 ---
has 'action: <value>' "$SK"
has "grant hook's deny message" "$SK"

# --- grant-outbound-speech：Two modes 寫明對外發話是第三級、hook 不擋、發話前寫 gate；第二級列有 test-path ---
MODES="$FX/modes"
section "Two modes" > "$MODES"
for k in 'customer or anyone outside the team' 'level three' 'write a `type: approval` gate' 'test file in a directory with no tracked tests'; do
  has "$k" "$MODES"
done

# --- issue-backlink：/pr 5b 回原 issue 留 MR 連結是第二級 mr 的例外，閘門會判；其餘對外發話仍是第三級 ---
has '`/opsx-workflow:pr` step 5b' "$MODES"
has 'level two under `mr`' "$MODES"
GR="$OPSX_ROOT/references/grants.md"
grep -F '**要授權**' "$GR" | grep -qF '回原 issue 留 MR 連結' || fail "grants.md 第二級列要含回原 issue 留 MR 連結"
grep -qF 'hook 看不到 issue 留言' "$GR" && fail "grants.md 不能再說 hook 看不到 issue 留言"
grep -qF '其他 issue 留言' "$GR" || fail "grants.md 要寫明其他 issue 留言仍是第三級"
# 被擋的動作開 gate 是通則；skill 步驟明定記成失敗的 deny 是唯一例外
has 'unless a skill step names that deny as a failure to record' "$SK"

# --- review-fix-in-scope：apply 接 review 退回的 task；pr 在有待修時拒絕 ---
has '## R<N>. review 退回' "$SK"
has '測試先紅再修' "$SK"
has '待修（範圍內）' "$OPSX_ROOT/skills/pr/SKILL.md"
has '/opsx-workflow:apply <slug>' "$OPSX_ROOT/skills/pr/SKILL.md"

# --- 範圍外開卡一律走 opsx new，帶 --type 與 path:line，slug 可能是既有的卡（specs/card-auto-merge「apply 的範圍外開卡」）---
grep -F "A problem outside this card's scope" "$SK" > "$FX/row6"
[ "$(wc -l < "$FX/row6" | tr -d ' ')" = 1 ] || fail "skeleton 第 6 列要剛好一行"
for k in 'opsx new' '--kind-of-work' '--type' 'path:line' 'existing card' 'never dispatch'; do has "$k" "$FX/row6"; done
# 沒帶 --name 的 opsx new 會被拒絕：教的指令要帶卡名（board-actions「卡名由 --name 指定」）
has 'opsx new --name <描述性卡名>' "$FX/row6"
for k in 'openspec new change' '--area' 'areas.txt'; do ! grep -qF -- "$k" "$FX/row6" || fail "第 6 列不能再提 $k"; done
# 開卡前不知道會不會被併：完整證據事前就寫進 --evidence；放不下時 split-out 再寫；priority 只對沒被併的新卡跑
has '併進' "$FX/row6"
has 'before you know whether it merges' "$FX/row6"
has 'opsx split-out' "$FX/row6"
has 'only when it was not merged' "$FX/row6"
! grep -qF "Put longer evidence under \`## 證據\` in that slug's" "$FX/row6" || fail "第 6 列不能叫被併入的 agent 把證據寫進目標卡的 ## 證據"

# --- me-20261111-1326：開卡步驟不教 agent 帶 --source（第 6 列）---
has '不要帶 `--source`' "$FX/row6"

# --- me-20261111-1326：worktree 沒有 openspec/，openspec 指令走主 checkout；測試一律 bash tests/run.sh，不帶前綴環境變數 ---
has '主 checkout' "$SK"
has 'bash tests/run.sh' "$SK"
has 'cd <worktree root>' "$SK"
! grep -qE '^[[:space:]]*(`)?OPSX_ROOT=' "$SK" || fail "apply SKILL.md 不能有 OPSX_ROOT= 開頭的測試指令範例"
# agent-20261116-1405 Scenario：skill 的測試步驟依 repo
has 'When the repo has `tests/run.sh` (only the file name counts, not its content), the command is `bash tests/run.sh' "$SK"
! grep -qF 'In this repo the command is `bash tests/run.sh' "$SK" || fail "apply SKILL.md 不能無條件寫 bash tests/run.sh"
! grep -qF '(`bash tests/run.sh <name>` filters by file name)' "$SK" || fail "apply SKILL.md 的檔名過濾說明要限於有 tests/run.sh 的 repo"
! grep -qF 'and read its output file: `tests/run.sh` prints' "$SK" || fail "apply SKILL.md 的 START 進度說明要限於有 tests/run.sh 的 repo"
# 開 gate 那一步寫明每個 repo 有建議的 decision 由協調者照建議答（specs/opsx-autonomy「agent 規則寫明誰答 gate」）
grep -E '^\| 5 \|' "$SK" > "$FX/apply5"
grep -qF 'in every repo' "$FX/apply5" || fail "apply 第 5 步要寫 in every repo"
grep -qF 'not one that needs your hands, a merge, has no recommendation, is a stuck gate or carries `needs: run`' "$FX/apply5" || fail "apply 第 5 步要寫哪些 decision 仍留給人"
grep -qF 'deploys, changes CI, touches secrets, spends money or speaks outside the team' "$FX/apply5" || fail "apply 第 5 步要寫第三級、花錢、對外的題仍留給人（D2）"
grep -qF '協調者代決' "$FX/apply5" || fail "apply 第 5 步要寫代答註「協調者代決」（D3）"
! grep -qF 'every gate in other repos' "$FX/apply5" || fail "apply 第 5 步不該再把其他 repo 的 gate 都交人"
! grep -qF 'In the opsx-workflow repo the coordinator answers' "$FX/apply5" || fail "apply 第 5 步不該再把代答限定在 opsx-workflow"
! grep -qF '協調者判定' "$FX/apply5" || fail "apply 第 5 步不該再有範圍判斷的答案文字（D5）"
! grep -qF 'The coordinator never answers any gate' "$SK" || fail "apply SKILL.md 不該再寫協調者不答任何 gate"

# agent-20261126-1119-2：第 4 步不手改產生檔（specs/apply-generated-files）
grep -E '^\| 4 \|' "$SK" > "$FX/apply4"
# 每句連條件一起比：刪掉條件、對調分支或把 or 改成 and 都要紅
# 改檔之前就找守門測試，找法只指到 Test agent 段落
has 'Before you edit a file, decide whether a generator owns it, and look for its guard test as the Test agent section says before the edit, not after it.' "$FX/apply4"
! grep -qF 'git grep -l -F' "$FX/apply4" || fail "第 4 步不該自己列守門測試的找法"
# 認定產生檔的訊號（Examples 每一列）
has 'A generator owns the file when the repo CLAUDE.md says so, when a guard test asserts it equals the generator output, or when its header says generated or do not edit.' "$FX/apply4"
has 'A file with none of these signals is edited directly.' "$FX/apply4"
has 'A file the repo CLAUDE.md tells you to hand-edit after generating follows CLAUDE.md, for example drizzle migration SQL.' "$FX/apply4"
# 兩類產生器；從其他輸入產生的檔只在產生器跑不了時才改
has 'When the generator builds the file from another input, edit that input and run the generator again, and do not edit the generated file unless the generator cannot run, as below.' "$FX/apply4"
! grep -qF 'never edit the generated file' "$FX/apply4" || fail "第 4 步不能同時寫 never edit 與被擋時照格式改"
has 'When the generator reads the file back and rewrites it in canonical form, such as `pnpm i18n:split` or a formatter, edit the file directly and run the generator, its `--check` mode or the guard test before the commit.' "$FX/apply4"
# 產生器跑不了，有守門測試：輸入與產生檔都改
has 'When a hook, dontAsk or the sandbox stops the generator from running, and a guard test asserts the file equals the generator output, edit the input if there is one, edit the generated file in the exact generator output format, run that test before the commit and commit only when it is green.' "$FX/apply4"
# 產生器、--check 或守門測試紅，兩類都一樣處理
has 'When the generator, its `--check` mode or the guard test stays red, do not commit, and after two failed rounds of fixes follow the Test agent On FAIL rule.' "$FX/apply4"
# 產生器跑不了，沒有守門測試：兩類各自怎麼改
has 'When the generator cannot run and no such guard test exists, write the step 5 gate with `type: decision`, `needs: run` and `by: coordinator` and the full generator command as its recommendation.' "$FX/apply4"
has 'A file built from another input stays unedited until that run, and you edit only the input.' "$FX/apply4"
has 'A file the generator reads back you edit directly, and you commit only after the run leaves it unchanged or you have taken in its rewrite.' "$FX/apply4"
# 怎麼認出沙盒擋下；其他非 0 結束是產生器自己的錯
has 'The sandbox stopped the generator when its output shows EPERM, `Operation not permitted` or a sandbox violations block.' "$FX/apply4"
has 'Any other non-zero exit is the generator reporting its own error, which is a failure to fix, not a generator that cannot run.' "$FX/apply4"
echo ok
