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

# 驗收：openspec/changes/apply-static-guards/specs/apply-static-guards/spec.md
TA="$FX/test-agent"
section "Test agent" > "$TA"
[ -s "$TA" ] || fail "section missing: Test agent"
# Scenario：Test agent 段落寫明靜態守門算相關測試
has 'a static guard whose scan covers a file you changed' "$TA"
has 'needs no database, network or other service' "$TA"
# R1.1、D15：brief 帶被改檔案，清單用本地的 main，不 fetch
has 'the files this change touches (`git diff --name-only <primary remote>/main...HEAD` against the local ref, no fetch, plus the uncommitted ones, untracked new files included, from `git status --porcelain`;' "$TA"
# Scenario：不跑全套的原句保留
has 'Do not run the whole suite; CI does that.' "$TA"
! grep -qiE 'exception to|except for static' "$TA" || fail "靜態守門不能寫成不跑全套的例外（D2）"
# Scenario：Test agent 段落寫明找守門的兩種方法（D12、D20：宣告的目標只用來列守門檔）
has 'pnpm test:ring0' "$TA"
has 'use it only to list the guard files, and run only the ones whose scan covers a file you changed' "$TA"
has 'skip the search below; a script name alone (`test:unit`) does not count. Otherwise, first check' "$TA"
# D13：不管改了哪類檔都讀索引
has 'check whether the repo'"'"'s CLAUDE.md lists a document to read before changing files, whatever kind of file you changed' "$TA"
has 'read the guard index it points to in full, never through `grep | head`' "$TA"
has 'run every guard the index lists whose scan covers a file you changed, whether or not the grep below finds it' "$TA"
has 'the helpers they import' "$TA"
# D14：清單不含 find
has '(`readdirSync`, `readdir`, `glob`, `os.walk`, `os.listdir`, `os.scandir`, `iterdir`, `WalkDir`, `ReadDir`, `git ls-files`)' "$TA"
# D39：宣告的指令帶環境變數時用它本身跑
has 'when that command sets environment variables in front, run the guards through the command itself with the guard paths appended, `pnpm test:ring0 <guard paths>`, not through vitest directly' "$TA"
# D41：「失敗」只指 git 步驟
has 'A failure here means a git step (checkout, apply); the guard exiting non-zero on the base is what you compare, not a failure.' "$TA"
! grep -qF '`find`' "$TA" || fail "grep 清單不能有 find（D14）"
# Scenario：只 grep 被改路徑不夠
has 'A grep for the changed path alone misses a guard that builds its root from segments' "$TA"
! grep -qF 'grep the test files for the changed path' "$TA" || fail "不能叫 agent 只 grep 被改路徑（D3）"
# Scenario：守門在 base 也紅時不擋卡（Examples 三列）
has 'compare it with the base before fixing anything' "$TA"
has 'run the same guard on the base commit' "$TA"
has 'git merge-base HEAD <primary remote>/main' "$TA"
has 'when the fetch fails, the red is this change'"'"'s failure' "$TA"
# D19、D25：只在這張卡自己的 worktree 比 base
has 'anywhere else other sessions'"'"' edits may share the tree, so the base is not run' "$TA"
# D16、R3.1：stash 安全步驟，順序一整串
has 'git branch --show-current' "$TA"
has 'set the work aside with `git stash push -u -m <unique tag>` and note the entry'"'"'s SHA by matching that tag in `git stash list --format='"'"'%H %gs'"'"'`, never from the top of the list' "$TA"
has 'no matching entry means nothing was stashed, so do not run the base' "$TA"
has 'When the tree is clean, skip the stash.' "$TA"
has 'Check out the base, run the guard in the foreground until it exits, then check the branch out again and, when you stashed, `git stash apply <sha>`, whether the guard passed or failed.' "$TA"
has 'Drop the entry found by its tag only after the apply exits 0 and `git status --porcelain` shows the changes back' "$TA"
has 'keep the entry, leave the tree as it is, and write a gate that names the SHA' "$TA"
has 'never a bare `git stash`' "$TA"
has 'When any of that cannot be done, do not run the base' "$TA"
# D11、R3.3：逐筆比，去掉行號欄號
has 'Compare failure by failure (file and message, with line and column numbers and any other standalone numbers in the message removed), not red against green, and count them' "$TA"
# D35：識別字裡的數字保留
has 'A number inside an identifier (`msg_404`) is part of the message and stays.' "$TA"
# D36：base 列不出失敗時不用 base 結果
has 'When the guard on the base times out, or is red but lists no failure, do not use the base result: the red is this change'"'"'s failure, and the reply says the base comparison was not run.' "$TA"
# D22：比筆數
has 'count them: more failures with the same file and message on this change than on the base is this change'"'"'s failure' "$TA"
# D23：base 跑完切不回或 apply 失敗
has 'When the branch cannot be checked out again, or the apply fails or does not bring the changes back after the base ran, do not use the base result: the red is this change'"'"'s failure; stop and write a gate that names the commit you are on and the stash SHA' "$TA"
# D21：被改檔案含 untracked
has 'plus the uncommitted ones, untracked new files included' "$TA"
has 'Every failure on this change also on the base: not this change'"'"'s failure; say so in the reply, open a card by skeleton row 6, and count that guard as green' "$TA"
has 'the run'"'"'s other tests keep their own result' "$TA"
has 'Any failure the base does not have: it is this change'"'"'s failure, and the two fix cycles below apply' "$TA"
has 'still red after two cycles is recorded `--tests red` like any other test' "$TA"
# R1.2、R3.2、D17：只有往下掉或刪檔才改基線，往上是這張卡的紅
has 'A ratchet guard red because this change lowered a count or removed a file is fixed in this task: the baseline file the guard names is in scope.' "$TA"
has 'A count that went up is this change'"'"'s failure; never raise a baseline number.' "$TA"
# D18：needs: run gate 之後記紅、往下做
has 'write a `needs: run` gate for that command instead of aborting the change, record that guard `--tests red`, and go on to the next change' "$TA"
# D24：宣告的目標要 CLAUDE.md 寫明只跑不需服務的測試，script 名字不算
has 'When the repo'"'"'s CLAUDE.md says a command runs only tests that need no service (such as `pnpm test:ring0`)' "$TA"
has 'a script name alone (`test:unit`) does not count' "$TA"
# D25：只在目錄名等於卡名的 worktree 跑 base
has 'Run the base only in the worktree whose directory name is this card'"'"'s name' "$TA"
! grep -qF 'one under `.claude/worktrees/` that no other session uses' "$TA"
# D26：改到守門檔本身不做 base 比對
has 'When this change edits the guard file itself, do not run the base: the red is this change'"'"'s failure.' "$TA"
# D27：免服務指令那條路也讀組掃描根的那幾行
has 'read the lines in each guard that build the root it scans, as for the grep below, to decide whether it covers a file you changed' "$TA"
# D28：必讀表多份文件時都讀
has 'When it lists several documents, read every one that has a table of test files or guards; each counts as an index.' "$TA"
# D29：數字也去掉，數字比 base 大才算紅
has 'with line and column numbers and any other standalone numbers in the message removed' "$TA"
has 'a matched failure whose number is higher on this change than on the base is this change'"'"'s failure' "$TA"
# D30：import 被改檔也算蓋到
has 'A guard that imports a file you changed directly also covers it; an indirect import is left to CI.' "$TA"
# D37：本地沒有 main ref 時先 fetch
has 'when the local `<primary remote>/main` ref does not exist, `git fetch <primary remote> main` first' "$TA"
# D38：detached HEAD 不跑 base
has 'When it prints nothing (a detached HEAD), do not run the base: the red is this change'"'"'s failure.' "$TA"
# D42：base 通過就是比過了
has 'A guard that passes on the base was compared: the red is this change'"'"'s failure, and the reply does not say the comparison was skipped.' "$TA"
# D43：修正後仍紅，拿第一次的 base 清單再比
has 'When the guard is still red after a fix cycle, compare again against the base failures from the first run; do not run the base again.' "$TA"
# D44：apply 成功但改動沒回來也要寫 gate
has 'when the apply fails, or exits 0 but `git status --porcelain` does not show the changes back, keep the entry' "$TA"
# D34：列不出可比失敗時不比 base
has 'When a red guard lists no failure to compare (it timed out, or only exited non-zero), do not run the base: the red is this change'"'"'s failure.' "$TA"
# D31：比同一位置的數字，對不上照筆數
has 'The number compared is the one in the same place in the message once line and column numbers are removed; when the places do not line up, compare by count.' "$TA"
# D32：stash 之後任何一步失敗都先切回並 apply
has 'When any step after the stash fails, check the branch out again and apply the stash first' "$TA"
# --- agent-20261126-1119 specs/apply-related-checks：Test agent 的型別檢查與守門測試 ---
# 觸發條件與指令找法（D3、D5、D8）
for k in 'exported symbol' 'imported by a file outside the diff' '`.tsx`' '`.py`' 'mypy' 'Otherwise run no typecheck' 'no typecheck command' 'say so in the reply'; do
  has "$k" "$TA"
done
has '`git diff --name-only <pre-merge sha> HEAD`' "$TA"
has 'the pre-merge sha (`ORIG_HEAD` read right after the merge)' "$TA"
has 'with no pre-merge sha given, no merge happened' "$TA"
! grep -qF 'HEAD^1' "$TA" || fail "Test agent 不該再用 HEAD^1 判斷 merge 帶進的檔（D8）"
# 被拒開 gate，不交 CI（D5）；回報帶型別檢查結果，由 session 開 gate（R1.2）
for k in 'When a hook or dontAsk denies the typecheck, never hand it to CI' '`type: decision`' '`needs: run`' '`by: coordinator`' 'does not continue to review' '`TYPECHECK: PASS|FAIL|DENIED <command and deny message>|SKIPPED <reason>|NOT-TRIGGERED`' 'the session that spawned the Test agent (apply, or babysit after its merge) writes the gate, not the Test agent' 'whose recommendation is the full command' 'apply does not continue to review and babysit does not push' 'A `TYPECHECK: FAIL` from an error this change or this merge brought makes `STATUS` FAIL'; do
  has "$k" "$TA"
done
! grep -qF 'the apply session writes the gate' "$TA" || fail "寫 gate 的不只 apply session（R3.2）"
# 紅時先在 main 跑（D6）
has 'An error that main also has is listed in the reply and not fixed here' "$TA"
has 'only the errors this change or this merge brought are fixed' "$TA"
has '`git worktree add --detach <scratch dir> <remote>/main`, never by switching or stashing this tree' "$TA"
has 'remove it with `git worktree remove` afterwards' "$TA"
has 'when that is denied or cannot run' "$TA"
has 'same file and the same message, whatever the line' "$TA"
# 守門測試三個來源，逐檔判斷（D4、D10、D11）
for k in "the guard tests the repo's CLAUDE.md names" '`git grep -l -F' "the changed file's directory and the directory above it" 'do not guess' '`.yml`' 'whether or not the change also touches source'; do
  has "$k" "$TA"
done
echo ok
