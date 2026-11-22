#!/usr/bin/env bash
# skills/review/SKILL.md 的結構：修一輪的範圍、未實作 task、D 對照、hook 引用。
# 只證明規則寫在對的段落且沒被反向改寫；agent 守不守由 eval 驗。對應 openspec/changes/review-fix-scope/specs/opsx-review-fix。
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
SK="$OPSX_ROOT/skills/review/SKILL.md"
assert_file "$SK"

assert_fixed() { grep -qF -- "$1" "$2" || fail "'$1' not in $(basename "$2")"; }
assert_not_fixed() { ! grep -qF -- "$1" "$2" || fail "'$1' should not be in $(basename "$2")"; }
line_of() { grep -nF -- "$1" "$2" | head -1 | cut -d: -f1; }

section() { awk -v h="## $1" 'index($0,h)==1{on=1;print;next} /^## (Step|Guardrails)/{on=0} on' "$SK"; }
STEP2="$FX/step2"; STEP3="$FX/step3"; STEP4="$FX/step4"; STEP5="$FX/step5"; GUARD="$FX/guard"
section "Step 2" > "$STEP2"; section "Step 3" > "$STEP3"; section "Step 4" > "$STEP4"; section "Step 5" > "$STEP5"; section "Guardrails" > "$GUARD"
for f in "$STEP2" "$STEP3" "$STEP4" "$STEP5" "$GUARD"; do [ -s "$f" ] || fail "section missing: $f"; done

# --- 1.1 Agent A 被要求回傳 D_TABLE（含照做的），每個 finding 註明 D-id ---
assert_fixed 'Also return `D_TABLE`' "$STEP2"
assert_fixed 'followed as well as violated' "$STEP2"
assert_fixed 'status: <followed|violated>' "$STEP2"
assert_fixed 'd_id: <related D-id, or none>' "$STEP2"
assert_fixed 'Agents B and C write `d_id: none`' "$STEP3"
assert_fixed 'keep every row, followed ones included' "$STEP3"

# --- 1.2 report 的 D 對照表；四個桶都有 D-id 欄位；有修前清單 ---
assert_grep '^## D 對照' "$STEP5"
assert_fixed '照做 / 偏離' "$STEP5"
assert_fixed '修前清單' "$STEP5"
n=$(grep -cF 'D-id <Dn|none>' "$STEP5"); [ "$n" -ge 4 ] || fail "D-id slot in all four buckets: found $n of 4"

# --- 2.1 範圍：因果判準，退回看 diff 行；task 已勾但沒實作屬範圍內 ---
assert_fixed 'cannot happen on main' "$STEP3"
assert_fixed 'a caller this change broke' "$STEP3"
assert_fixed 'git diff -U0 main...HEAD' "$STEP3"
assert_fixed 'happens on main too' "$STEP3"
assert_not_fixed 'always Consider, never Act on' "$STEP3"
assert_fixed 'BUG = task checked and the diff has no code for it' "$STEP2"
assert_fixed 'Review never implements a task' "$GUARD"

# --- review-examples-rows：Agent A 逐列對照 Examples 表，缺列是 MUST_FIX ---
assert_fixed 'Scenario with an Examples table' "$STEP2"
assert_fixed 'every row needs a matching case in the `測試：` file' "$STEP2"
assert_fixed 'a missing row is MUST_FIX' "$STEP2"
assert_fixed 'the finding names the missing row' "$STEP2"

# --- 2.2 step 4：範圍內寫成 task 回 apply，範圍外開卡，驗不了的降 Consider ---
assert_fixed '## R<N>. review 退回' "$STEP4"
assert_fixed '待修（範圍內）' "$STEP4"
assert_fixed '/opsx-workflow:apply <slug>' "$STEP4"
assert_fixed 'opsx new' "$STEP4"
assert_fixed '優先度 P2' "$STEP4"
assert_fixed 'review changes no code' "$STEP4"
assert_not_fixed 'at most 一個 回歸測試 in total' "$STEP4"
assert_fixed '確認: <sha>' "$STEP4"
assert_fixed '待修（範圍內）' "$STEP5"
assert_fixed '確認: <sha>' "$STEP5"

# --- 範圍外開卡帶 --type 與 path:line，slug 可能是既有的卡（specs/card-auto-merge「review 的範圍外開卡」）---
grep -F -- '- **範圍外.**' "$STEP4" > "$FX/oos"; [ -s "$FX/oos" ] || fail "Step 4 找不到範圍外段"
for k in 'opsx new' '--type' 'path:line' 'existing card'; do assert_fixed "$k" "$FX/oos"; done
assert_not_fixed 'openspec new change' "$FX/oos"; assert_not_fixed '--area' "$FX/oos"; assert_not_fixed 'areas.txt' "$FX/oos"
# me-20261111-1326：開卡步驟不教 agent 帶 --source
assert_fixed '不要帶 `--source`' "$FX/oos"
assert_fixed '併進' "$FX/oos"; assert_fixed '--evidence' "$FX/oos"
assert_fixed 'before you know whether it merges' "$FX/oos"; assert_fixed 'opsx split-out' "$FX/oos"

# --- 2.3 hook 擋下：引用的共用文件要解析得到，不在本文重寫 ---
assert_fixed '../../references/harness-claude-code.md' "$STEP4"
[ -f "$(dirname "$SK")/../../references/harness-claude-code.md" ] || fail "harness-claude-code.md does not resolve from skills/review/"
assert_fixed 'do not reword the command' "$STEP4"

# --- node-steps-gates：opsx check 的 Must-fix 候選由 review 讀並判斷 ---
assert_fixed 'Must-fix 候選' "$STEP3"
assert_fixed 'sends it back to explore' "$STEP3"
assert_fixed 'A `Must-fix 候選` line is not an incomplete shell: leave it for Step 3.' "$SK"
assert_fixed 'A line starting `explore.md 步驟` goes back to `/opsx-workflow:explore <slug>`, not to `/opsx-workflow:apply`.' "$SK"

# --- gherkin-check / check-wiring：前置對每張卡跑 opsx check，spec 的行退回 apply（specs/spec-gherkin-check）---
STEP0="$FX/step0"; section "Step 0" > "$STEP0"; [ -s "$STEP0" ] || fail "section missing: Step 0"
assert_fixed 'Every card: also run `opsx check <slug>`.' "$STEP0"
assert_not_fixed 'A main change with `subs/`: also run `opsx check' "$STEP0"
assert_fixed 'A line pointing at a `spec.md` is a spec that breaks the Gherkin rules: stop the same way, list those lines, and send it back to `/opsx-workflow:apply <slug>`.' "$STEP0"

# --- 沒 CI 的 repo：review 自己背景跑全套，紅就退回 apply；有 CI 不必（specs/review-full-suite-gate）---
grep -F 'No CI:' "$STEP0" > "$FX/noci"; [ -s "$FX/noci" ] || fail "Step 0 找不到 No CI 段"
# 有沒有 CI 照主要 remote 判斷（D8、D9、D10、D12）：Examples 表每一列對到一句條件
for k in 'the primary remote (`gitlab` when the repo has that remote, otherwise `origin`)' \
  'the forge is the host in `git remote get-url <primary>`: a host with `gitlab` in its name is GitLab, `github.com` is GitHub.' \
  'No remote at all, or a primary on any other host, is no CI.' \
  'A GitLab primary has CI when the repo has a `.gitlab-ci.yml`' \
  'a GitHub primary has CI when `.github/workflows/` holds a `.yml` or `.yaml` file' \
  '(a README or `.gitkeep` alone is no CI)' \
  'Any other CI file (a Jenkinsfile, `.circleci/`) does not count' \
  'Without CI, nothing else runs the whole suite before merge' \
  'With CI present, the full run is not required'; do
  assert_fixed "$k" "$FX/noci"
done
for k in 'an empty workflows directory is no CI' 'has no CI when the repo has a `.gitlab-ci.yml`' \
  'With no CI present, the full run is not required' 'Skip this if status.json is green'; do
  assert_not_fixed "$k" "$FX/noci"
done
# 全套指令照 apply 的找法（D11），不寫死 tests/run.sh；找不到指令照常開審（D13）
for k in '`bash tests/run.sh` when the repo has `tests/run.sh`' \
  'otherwise the test command found the way apply finds it (CLAUDE.md first, then package.json / pyproject, then the usual `pnpm test`, `pytest`, `go test ./...`).' \
  'When that finds no test command, do not run the suite: write `找不到測試指令，沒跑全套` under `## 測試` in report.md and start review.'; do
  assert_fixed "$k" "$FX/noci"
done
assert_not_fixed '背景跑 the whole suite `bash tests/run.sh`' "$FX/noci"
# 全綠才開審、有紅退回
for k in 'Any red file means do not review' 'each red test name with its first error line' \
  'send it back to `/opsx-workflow:apply <slug>`' 'Review starts only after the whole suite finishes with no red file'; do
  assert_fixed "$k" "$FX/noci"
done
[ "$(line_of 'No CI:' "$SK")" -gt "$(line_of 'A review of untested code is a review of a guess.' "$SK")" ] || fail "No CI 段要接在 status.json 段之後"
[ "$(line_of 'No CI:' "$SK")" -lt "$(line_of 'Every card: also run `opsx check <slug>`.' "$SK")" ] || fail "No CI 段要在 opsx check 段之前"

# --- 產表步：Step 1 之後、Step 2 之前；每輪都產，確認 pass 不產；prompt 四行加 design:（specs/review-logic-map、pr-logic-map）---
MAP="$FX/map"; section "Step 1b" > "$MAP"; [ -s "$MAP" ] || fail "section missing: Step 1b"
[ "$(line_of '## Step 1b' "$SK")" -gt "$(line_of '## Step 1: shared inputs' "$SK")" ] || fail "Step 1b 要在 Step 1 之後"
[ "$(line_of '## Step 2' "$SK")" -gt "$(line_of '## Step 1b' "$SK")" ] || fail "Step 1b 要在 Step 2 之前"
assert_fixed 'Wait for the map before Step 2' "$MAP"
assert_fixed 'The confirm pass and the base-merge confirm pass in Step 4 do not run this step' "$MAP"
assert_fixed 'git fetch <remote> main' "$MAP"
assert_fixed '產表失敗：fetch 失敗' "$MAP"
assert_fixed '`<map path>` is the absolute path of `openspec/changes/<slug>/logic-map.md` in the checkout that holds `openspec/`' "$MAP"
assert_fixed 'Delete `<map path>` before spawning' "$MAP"
python3 -I - "$MAP" <<'PY' || fail "產表步的 prompt 區塊不是那五行，或刪檔不在派之前"
import re, sys
text = open(sys.argv[1], encoding="utf-8").read()
if not text.index("Delete `<map path>`") < text.index("Spawn one fresh subagent"):
    sys.exit("刪檔在派之後")
blocks = [b for b in re.findall(r"```\n(.*?)```", text, re.S) if b.lstrip().startswith("repo: ")]
if len(blocks) != 1:
    sys.exit("找不到以 repo: 開頭的 prompt 區塊")
lines = [l.strip() for l in blocks[0].strip().splitlines()]
want = ["repo: ", "range: <remote>/main...HEAD", "output: <map path>", "design: <absolute path of", "Load "]
if len(lines) != 5 or not all(l.startswith(w) for l, w in zip(lines, want)) or "../logic-map/SKILL.md" not in lines[4]:
    sys.exit("prompt：%r" % lines)
PY
grep -F 'Nothing else goes into the prompt' "$MAP" > "$FX/map-deny"
for k in 'spec' 'proposal' 'report' 'tasks' 'explore' 'grill' 'conversation' 'PR title or description'; do
  grep -qF -- "$k" "$FX/map-deny" || fail "產表步禁止清單缺 $k"
done
for k in 'never build the map in this session' '產表失敗：無 Agent 工具' '`產表失敗：<reason>`' \
  'replaces the one line under `## 邏輯表`' 'openspec/changes/<slug>/logic-map.md · <head sha 前 7 碼>' 'overwrite the whole line'; do
  assert_fixed "$k" "$MAP"
done

# --- 產表失敗停在 gate，不回呼叫端（specs/review-logic-map「產表失敗停在 gate」）---
assert_not_fixed 'A failed map stops nothing' "$MAP"
assert_not_fixed 'Then end this step and go on to the caller' "$MAP"
assert_fixed 'Then write a gate in gates.md and stop' "$MAP"
assert_fixed 'the caller'"'"'s next step does not run' "$MAP"
assert_fixed 'Never fall back to the `<remote>/main` already on disk' "$MAP"
assert_fixed '`logic-map-failed-<n>`' "$MAP"
# R1.3 最大號加 1，跟 hooks/openspec-stop-gate.sh write_auto_gate 一樣；較早的 gate 被刪時不重名
assert_not_fixed 'one more than the number of' "$MAP"
assert_fixed 'one more than the largest number among the `## logic-map-failed-<n>` gates already in gates.md, so the first gate is `logic-map-failed-1`' "$MAP"
assert_not_fixed '0 when there are none' "$MAP"
# R1.4 失敗 Outline「subagent 回報成功，但輸出檔不存在」列；FETCH_HEAD 比對釘整句方向
assert_fixed 'or `<map path>` does not exist afterwards' "$MAP"
assert_fixed 'When the file is newer, the user fetched into this worktree: skip the fetch of sub-step 1' "$MAP"
# R1.1 pane 重開後只收到答案的 prompt：先看最新的 logic-map-failed gate，不從子步 1 重來
grep -F 'look at the newest `## logic-map-failed-<n>` gate in gates.md' "$MAP" > "$FX/failed-entry"
[ -s "$FX/failed-entry" ] || fail "1b 缺入口讀 logic-map-failed gate"
for k in 'When it is open, repeat its question and stop; open no new gate' \
  'When it is answered and the line under `## 邏輯表` is a `產表失敗：` line, or there is no such line yet' \
  'continue by that answer as the list under sub-step 3 says, instead of starting at sub-step 1'; do
  grep -qF -- "$k" "$FX/failed-entry" || fail "入口讀 gate 缺 $k"
done
python3 -I - "$MAP" <<'PY' || fail "讀 logic-map-failed gate 要在 mr: none 預檢與子步 1 之前"
import sys
t = open(sys.argv[1], encoding="utf-8").read()
if not t.index("look at the newest `## logic-map-failed-<n>`") < t.index("skip：mr: none") < t.index("1. `git fetch <remote> main`"):
    sys.exit("順序")
PY
# R1.2 ref 不存在時 git log 只有 stderr，不能當成空 diff
assert_fixed '`git rev-parse --verify <remote>/main` succeeds, and `git log --oneline <remote>/main..HEAD` exits 0 and prints nothing' "$MAP"
# Examples 表每列：失敗行 → type、選項
grep -F -- '- `產表失敗：fetch 失敗`:' "$MAP" > "$FX/gate-fetch"
for k in '`type: decision`' '`needs: run`' 'git -C <absolute path of this checkout> fetch <remote> main'; do
  grep -qF -- "$k" "$FX/gate-fetch" || fail "fetch gate 缺 $k"
done
grep -F -- '- `產表失敗：無 Agent 工具`:' "$MAP" > "$FX/gate-noagent"
for k in '`type: decision`' '派一個 claude pane 重產 (Recommended)' '這張不要表，直接放行'; do
  grep -qF -- "$k" "$FX/gate-noagent" || fail "無 Agent 工具 gate 缺 $k"
done
grep -F -- '- any other `產表失敗：<reason>`' "$MAP" > "$FX/gate-other"
for k in '`type: decision`' '重跑產表 (Recommended)' '這張不要表，直接放行'; do
  grep -qF -- "$k" "$FX/gate-other" || fail "subagent 失敗 gate 缺 $k"
done
! grep -qF 'needs: run' "$FX/gate-noagent" "$FX/gate-other" || fail "只有 fetch gate 帶 needs: run"

# --- gate 答完的接續（「使用者跑過 fetch」「使用者沒跑或跑錯目錄」「選放行」「選重跑不寫 skip」）---
grep -F -- '- fetch gate:' "$MAP" > "$FX/ans-fetch"
for k in 'git rev-parse --git-path FETCH_HEAD' '`opened_at`' 'skip the fetch of sub-step 1' 'write another fetch gate' 'FETCH_HEAD 不存在'; do
  grep -qF -- "$k" "$FX/ans-fetch" || fail "fetch gate 答完的接續缺 $k"
done
# R3.1 重跑與改派的 claude pane 都從 mr: none 預檢重來，不跳過 D4；只有沒有 Agent 工具的 session 記 log 後停
grep -F -- '- 重跑產表:' "$MAP" | grep -qF 'start again from the `mr: none` check before sub-step 1' || fail "重跑產表要從 mr: none 預檢重來"
grep -F -- '- 派一個 claude pane 重產:' "$MAP" > "$FX/ans-claude"
for k in 'A session that has the Agent tool starts again from the `mr: none` check before sub-step 1' \
  'Only a session without the Agent tool runs `opsx log'; do
  grep -qF -- "$k" "$FX/ans-claude" || fail "派 claude pane 缺 $k"
done
grep -F -- '- 這張不要表，直接放行:' "$MAP" > "$FX/ans-skip"
for k in 'skip：使用者放行（logic-map-failed-<n>）' "go on to the caller's next step"; do
  grep -qF -- "$k" "$FX/ans-skip" || fail "放行缺 $k"
done

# --- mr: none 空 diff 卡不產表（「只動 openspec 的卡」「mr: none 但有 commit」）---
grep -F 'skip：mr: none' "$MAP" > "$FX/mrnone"; [ -s "$FX/mrnone" ] || fail "缺 mr: none 不產表"
for k in '`mr: none`' 'git log --oneline <remote>/main..HEAD' 'prints nothing' 'spawn nothing and open no gate'; do
  grep -qF -- "$k" "$FX/mrnone" || fail "mr: none 段缺 $k"
done
python3 -I - "$MAP" <<'PY' || fail "mr: none 判斷要在子步 1 之前"
import sys
t = open(sys.argv[1], encoding="utf-8").read()
if not t.index("skip：mr: none") < t.index("1. `git fetch <remote> main`"):
    sys.exit("順序")
PY
for k in 'comment' '留言' 'gh pr' 'glab api'; do assert_not_fixed "$k" "$MAP"; done
assert_fixed '## 邏輯表' "$STEP5"

# --- bug 類 ⚠ 交 Agent A 確認；沒確認的進 Dismissed ---
assert_fixed 'Also confirm every `bug：違反 design Dn` item of the logic map' "$STEP2"
assert_fixed 'A logic-map bug item that Agent A does not confirm goes to Dismissed' "$STEP3"

# --- 沒經過決定與未分類的 ⚠ 進同一個 gate；程式整理與照 design D 不進；答案寫回 design ---
grep -F -- '- **Logic map, undecided.**' "$STEP4" > "$FX/undecided"; [ -s "$FX/undecided" ] || fail "Step 4 找不到 Logic map, undecided 段"
for k in '`logic-map-undecided-r<N>`' '`type: decision`' '2 to 4 options' 'Recommended' '沒有 design.md，未分類' \
  '`程式整理` items and 照 design D items never go into the gate' 'not verified'; do
  assert_fixed "$k" "$FX/undecided"
done
grep -F -- '- **Logic map gate answered.**' "$STEP4" > "$FX/answered"; [ -s "$FX/answered" ] || fail "Step 4 找不到 Logic map gate answered 段"
for k in 'design.md' '使用者 <日期> 回邏輯表 ⚠ 選 <選項>' 'review 退回' '/opsx-workflow:apply <slug>' '/opsx-workflow:pr <slug>' 'not a round'; do
  assert_fixed "$k" "$FX/answered"
done
assert_fixed 'A `沒經過決定` ⚠ in the logic map is not Consider: its gate holds the card before `/opsx-workflow:pr`.' "$STEP5"

# --- R1.1 第 1 輪產表不建出 report.md：router 看到 report.md 會判成 pr（bin/lib/stage.sh） ---
assert_fixed 'When report.md does not exist yet (round 1), do not create it here: keep the line and write it under `## 邏輯表` in Step 5.' "$MAP"
# --- R1.2 design: 行跟 <map path> 同一個 checkout：dispatch worktree 沒有 openspec/ ---
assert_fixed 'design: <absolute path of `openspec/changes/<slug>/design.md` in the same checkout as `<map path>`>' "$MAP"
# --- R1.3 gate 答完的處理：review 重進不算一輪；寫回後記 寫回: 行、清掉邏輯表行、照 Step 5 規則接下一步 ---
for k in '`寫回: <日期> · <新的 D>`' 'continue by Step 5'"'"'s rule'; do
  assert_fixed "$k" "$FX/answered"
done
assert_not_fixed 'when no answer changes the code, continue to `/opsx-workflow:pr <slug>`' "$FX/answered"

# --- R2.4 Step 0 先認 gate、再算輪數；寫回後照那步的接續，不停 ---
GATE0='Before reading the round: when the newest `logic-map-undecided-r*` gate is answered and has no `寫回:` line, the answers are not in design.md yet: run only the **Logic map gate answered** step of Step 4, which is not a round, then continue as that step says.'
assert_fixed "$GATE0" "$STEP0"
[ "$(line_of "$GATE0" "$SK")" -lt "$(line_of 'Read the round from report.md' "$SK")" ] || fail "Step 0 認 gate 的段落要在算輪數之前"
assert_not_fixed 'and stop there' "$STEP0"
# --- R2.2 每輪自己的 gate id，認最新一個 ---
assert_fixed 'with id `logic-map-undecided-r<N>`, where N is this review round' "$FX/undecided"
# --- R2.1 改程式的答案也進待修，pr 與 Stop hook 才擋得到；R2.3 群組編號接現有最大的 R ---
assert_fixed 'list it under `### 待修（範圍內）` in report.md with its task id' "$FX/answered"
assert_fixed 'numbered after the largest `## R<k>.` group already in tasks.md, not after the round' "$FX/answered"
assert_not_fixed '## R<N>. review 退回' "$FX/answered"
# --- R2.5 失敗行第 1 輪也不建 report.md；寫回時整段刪掉 ## 邏輯表，對上 pr 5c 的「沒有這一段」 ---
assert_not_fixed '(add the heading when it is missing)' "$MAP"
assert_fixed 'In round 1, when report.md does not exist yet, keep the failure line for Step 5 the same way.' "$MAP"
assert_fixed 'Delete the whole `## 邏輯表` section from report.md' "$FX/answered"
assert_not_fixed 'Clear the line under `## 邏輯表`' "$FX/answered"

# --- No CI 的探查指令要過得了 grant hook（D8、D9）：點名 CI 路徑的 Bash 連唯讀都判第三級 ---
PROBE='Look with `git ls-files .github` and `ls -a` at the repo root: the grant hook denies any Bash command whose text names `.gitlab-ci.yml` or `.github/workflows`, even a read.'
grep -qF -- "$PROBE" "$FX/noci" || fail "No CI 段要寫明探查指令與 hook 的限制"
# grant-gate-fixture 會再 source lib.sh 開新的 $FX，先清掉這支用完的
rm -rf "$FX"
source "$(dirname "${BASH_SOURCE[0]}")/grant-gate-fixture.sh"
for c in 'git ls-files .github' 'ls -a'; do
  out="$(gg "$c")"; assert_eq "$(decision "$out")" allow "探查指令要放行（${c}）: $(reason "$out")"
done
out="$(gg 'ls .github/workflows')"; assert_eq "$(decision "$out")" deny "點名 .github/workflows 的唯讀指令被擋，SKILL.md 才要繞開: $(reason "$out")"
