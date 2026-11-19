---
name: review
description: |
  Spec-driven code review of an OpenSpec change before it becomes an MR. Refuses to start unless
  every task has its test and the change's tests are green, then runs three reviewers in parallel
  (one merged reviewer on a small chore or bug-fix card, at most two rounds)
  (A: spec conformance against design.md D-ids and tasks; B: code quality using the ponytail six
  categories; C: adversarial, attacks the premise and checks the tests prove the acceptance
  criteria), merges their findings with lead judgment into four buckets, sends every verified Bug and Must-fix
  that this change caused back to `/opsx-workflow:apply`, files the rest as inbox cards, and writes report.md. Use when the user says "review", "code review", "check my changes",
  "審一下", gives a change slug or MR number, or when the opsx router injects `review · <slug>`.
argument-hint: "[change slug | MR number]"
compatibility: Spawns three Agent subagents (A and B on claude-sonnet-5-5, C on claude-opus-5-5).
---

# /review

**Steps in TodoWrite.** First action after loading: put this skill's steps into TodoWrite verbatim; a step you will not do stays in the list as `skip: <reason>`, never deleted.

Three readers who do not share context, one lead who decides. The report they leave is what `/opsx-workflow:pr` and the board build on.

## Step 0: the gate

Read `openspec/changes/<slug>/tasks.md` and `status.json`. For every checked task, the `測試：` file must exist (or the line says `測試：無 · <reason>`), and `status.json.tests` must be `green`. When you have to run the whole suite yourself, 背景跑 it and read the output file: it takes longer than the Bash tool's timeout, and `tests/run.sh` prints `START <name>` before each file, so a slow file is not a hang. If either fails, do not review: say which tasks lack tests or that the suite is red, and that `/opsx-workflow:apply <slug>` has to finish first. A review of untested code is a review of a guess.

No CI: CI runs only on the primary remote (`gitlab` when the repo has that remote, otherwise `origin`), and the forge is the host in `git remote get-url <primary>`: a host with `gitlab` in its name is GitLab, `github.com` is GitHub. A GitLab primary has CI when the repo has a `.gitlab-ci.yml`; a GitHub primary has CI when `.github/workflows/` holds a `.yml` or `.yaml` file (a README or `.gitkeep` alone is no CI). No remote at all, or a primary on any other host, is no CI. Any other CI file (a Jenkinsfile, `.circleci/`) does not count. Look with `git ls-files .github` and `ls -a` at the repo root: the grant hook denies any Bash command whose text names `.gitlab-ci.yml` or `.github/workflows`, even a read. Without CI, nothing else runs the whole suite before merge, so `status.json` is not enough: 背景跑 the whole suite as above, with `bash tests/run.sh` when the repo has `tests/run.sh`, otherwise the test command found the way apply finds it (CLAUDE.md first, then package.json / pyproject, then the usual `pnpm test`, `pytest`, `go test ./...`). When that finds no test command, do not run the suite: write `找不到測試指令，沒跑全套` under `## 測試` in report.md and start review. Any red file means do not review: list each red test name with its first error line, and send it back to `/opsx-workflow:apply <slug>`. Review starts only after the whole suite finishes with no red file. With CI present, the full run is not required.

Every card: also run `opsx check <slug>`. Any line it prints (a sub-change shell that is incomplete, a missing fact field) stops review the same way; name the lines. A line pointing at a `spec.md` is a spec that breaks the Gherkin rules: stop the same way, list those lines, and send it back to `/opsx-workflow:apply <slug>`. The `opsx init` hint line that may follow them goes along with them. A `Must-fix 候選` line is not an incomplete shell: leave it for Step 3. A line starting `explore.md 步驟` goes back to `/opsx-workflow:explore <slug>`, not to `/opsx-workflow:apply`. A line starting `workplan.yaml: mr:` is not code and not yours to settle: write a `type: decision` gate (set that PR's `mr:` to `none` and archive without an MR, or delete the line and open one) and stop; when the answer arrives, edit `openspec/workplan.yaml` accordingly, run the check again, and carry on.

Before reading the round: when the newest `logic-map-undecided-r*` gate is answered and has no `寫回:` line, the answers are not in design.md yet: run only the **Logic map gate answered** step of Step 4, which is not a round, then continue as that step says. When it is still open, the user has not answered: repeat its question and stop.

Read the round from report.md: its title is `# Review · <slug> · 第 <N> 輪 · …`; no report.md means N is 0, and this run is round N+1. When N is already 2 or more, two rounds are done (the confirm pass in Step 4 edits report.md in place, keeps the 第 2 輪 title and is not a round): review does not start a reviewer. If report.md still lists items under `### 待修（範圍內）` and their `R` tasks in tasks.md are not all checked, send them back to `/opsx-workflow:apply <slug>` (Step 4). If those tasks are checked, run the confirm pass in Step 4. Write a gate in `gates.md` (`type: decision`) only for an item that needs a user decision and cannot be fixed; if nothing is open, say the review budget is used up and continue to the next node.

Decide small or not by `../../references/continue.md`, "Light flow" (kind chore or bug-fix, at most 3 tasks, one first path component outside tests). A small card runs one merged reviewer in step 2; any other card runs three.

`opsx status review 1/7 "gate 過了"`.

## Step 1: shared inputs

```bash
git diff main...HEAD > /tmp/review-<slug>-diff.txt
git diff --name-only main...HEAD > /tmp/review-<slug>-files.txt
git log --oneline main...HEAD > /tmp/review-<slug>-commits.txt
```

Paths to hand every agent: project root, branch, `proposal.md`, `design.md` (D-ids), `tasks.md`, `grill.md` if present, `CLAUDE.md`, `ARCHITECTURE.md`, `CONTEXT.md` when they exist. Scope from `$ARGUMENTS`: a slug, an MR number (`glab mr diff <n>`), or auto-detect the one in-progress change; several → **AskUserQuestion**.

## Step 1b: logic map

Every round builds the logic map of the current head before the reviewers start, so the bugs in it reach Agent A and the product decisions in it reach the user before the MR opens. Wait for the map before Step 2. The confirm pass and the base-merge confirm pass in Step 4 do not run this step. `/opsx-workflow:pr` step 5c and babysit run sub-steps 1–4 below when the head has moved since.

1. `git fetch <remote> main`. `<remote>` is the primary remote by pr step 1's rule: `gitlab` in Acmecorp-AI and Acmecorp-Infrastructure, otherwise `origin`. A stale local `main` gives an old merge-base, and the map would include other people's commits. When the fetch exits non-zero, the map would be built on that stale base: take the failure path of sub-step 3 with `產表失敗：fetch 失敗`.
2. `<map path>` is the absolute path of `openspec/changes/<slug>/logic-map.md` in the checkout that holds `openspec/`. In a dispatch worktree that is the main checkout, not the current directory, so every command below uses the absolute `<map path>`, never a relative one. Delete `<map path>` before spawning: `openspec/` is not in git, so the previous run's map is still on disk, and only a file this run wrote can count as success in sub-step 3. Spawn one fresh subagent with the Agent tool (general-purpose). The prompt is exactly these five lines, with absolute paths written in:

   ```
   repo: <absolute path of this checkout>
   range: <remote>/main...HEAD
   output: <map path>
   design: <absolute path of `openspec/changes/<slug>/design.md` in the same checkout as `<map path>`>
   Load <absolute path of ../logic-map/SKILL.md, next to this skill> and follow it.
   ```

   Nothing else goes into the prompt: no spec, proposal, report, tasks, explore, grill, conversation, PR title or description. The map exists to show where the code and the intent differ, and an agent that has read the intent describes the intent. design.md is the one exception, and the logic-map skill reads it only after the condition tables are final, to sort the ⚠ marks.
3. Without the Agent tool (codex, for example), never build the map in this session: it has read the intent. Write `產表失敗：無 Agent 工具`. When the subagent fails, or `<map path>` does not exist afterwards, write `產表失敗：<reason>` with the first line of its report. A failure line replaces the one line under `## 邏輯表` the same way sub-step 4 overwrites it, with the heading added when report.md has none; never write it as a second line. In round 1, when report.md does not exist yet, keep the failure line for Step 5 the same way. Then end this step and go on to the caller's next step. A failed map stops nothing.
4. Write the `## 邏輯表` section of report.md. When report.md does not exist yet (round 1), do not create it here: keep the line and write it under `## 邏輯表` in Step 5. The router reads an existing report.md as "review ran", so a relaunch in the middle of the review would send the card to `/opsx-workflow:pr`. The same holds for a failure line from sub-step 3. The section holds one line, and a later run must overwrite the whole line, not append:

   ```
   ## 邏輯表
   openspec/changes/<slug>/logic-map.md · <head sha 前 7 碼>
   ```

Then read the map's `### ⚠ 要看的地方` lists for Step 2 and Step 4: `bug：違反 design Dn` items go to Agent A; `沒經過決定` items, and every item of a map that says 沒有 design.md，未分類, go to the gate in Step 4; `程式整理` items and the 照 design D line stay on the map for the user to read.

## Step 2: three agents, one message

A small card spawns one merged reviewer (model `claude-sonnet-5-5`) instead: it gets both the Agent A brief and the Agent B brief below and returns one list in the shape below with `AGENT: AB`; Agent C does not run. Any other card spawns all three in a single message so they run concurrently. None of them sees the others' output. Each reads the diff and every changed file in full, plus two or three sibling files per changed file for the local pattern.

**Agent A, spec conformance** (model `claude-sonnet-5-5`). For each D-id in design.md: the file:line that implements it, or a finding. Goals have code; non-goals have none (scope creep is a finding). Each `- [x]` task does what it says, and its `測試：` file tests the `驗收：` scenario it names. Risks in design.md have their stated mitigation. Classification: BUG = task checked and the diff has no code for it (cite task number, plus the D-id it serves); MUST_FIX = the diff has code for the task or goal but it contradicts a decision (cite D-id), even if the task feels unfinished. For a Scenario with an Examples table (a Scenario Outline), every row needs a matching case in the `測試：` file; a missing row is MUST_FIX, since the task's code is there but the tests do not prove every row its `驗收：` points at, and the finding names the missing row. Do not flag trade-offs design.md already acknowledges. Also return `D_TABLE`: one row per D-id in design.md, followed as well as violated; a followed D gets its file:line, a violated D points at its finding. Also confirm every `bug：違反 design Dn` item of the logic map that the lead hands over (Step 1b): read the code at the node's 位置 and the design Dn it names, and return a finding with that `d_id` when the code really contradicts it; say so in SUMMARY when it does not.

**Agent B, code quality** (model `claude-sonnet-5-5`). Knows nothing about the spec. Reviews for the six ponytail categories, each finding with a concrete failure case or it is downgraded: bug (input → wrong output), 安全 (trust boundary crossed without validation), 負載 (what breaks at 10× rows or users), 沒測試的風險 (new branch / loop / parser / money / auth with no test), 慢 (N+1, unbounded scan, sync I/O in a hot path), 多餘 (dead code, unused dep, duplicate helper, abstraction with one caller). Plus the code-quality lens from `../interrogate/references/code-quality-review.md`. MUST_FIX requires quoting the convention line from CLAUDE.md / ARCHITECTURE.md. Read `references/ponytail-review.md` for the category definitions.

**Agent C, adversarial** (model `claude-opus-5-5`). Prompt from `../interrogate/references/reviewer-prompt.md` with `rubric.md`. Its stance is that this change is wrong: attack the premise in design.md, list the alternative it skipped and why that one might be better, name the input, load, or ordering that breaks it. Then the tests: for each task, does the test actually prove the `驗收：` scenario, which edge is missing (empty, limit, bad input, wrong tenant), would the test still pass if the implementation were subtly broken. Every finding needs a concrete failure scenario; without one it is not listed.

All three return the same shape:

```
AGENT: <A|B|C>
D_TABLE:                      # agent A only
- d_id: <D1>
  status: <followed|violated>
  where: <file:line of the implementation, or of the finding it violates>
FINDINGS:
- severity: BUG|MUST_FIX|SUGGESTION
  file: <path>
  line: <n>
  d_id: <related D-id, or none>
  description: <one line>
  evidence: <failure scenario | D-id | convention quote>
  fix: <concrete instruction>
SUMMARY: <one paragraph>
```

## Step 3: lead judgment

Read `../interrogate/references/lead-judgment.md`. Merge: same file:line from two agents → one finding, keep the stronger evidence, mark it high-signal. Then every finding lands in one bucket, with a one-line reason:

- **Act on**: evidence verified by you (read the cited line, confirm the scenario), fix now.
- **Consider**: plausible but not proven, or a design question for the user; goes to the report, not to code.
- **Noted**: style or preference, no action.
- **Dismissed**: evidence does not hold; say why.

Evidence you cannot verify downgrades the finding one level, so an unverifiable finding in scope goes to Consider, not back to apply.

A logic-map bug item that Agent A confirms is an ordinary MUST_FIX against its design Dn and goes through the scope rule below. A logic-map bug item that Agent A does not confirm goes to Dismissed, with Agent A's reason.

Then scope every BUG and MUST_FIX left in Act on. 範圍內 = the failure scenario cannot happen on main (a caller this change broke counts); run the scenario on main when you can. When it cannot be run, 範圍內 = the cited file:line is inside the added or changed lines of `git diff -U0 main...HEAD` (take `main` as the remote default branch, `origin/main` after `git fetch`; a stale local main pulls already-merged code into scope, and the "on main" scenario runs on the same base). 範圍外 = the scenario happens on main too. Only 範圍內 BUG and MUST_FIX are sent back to `/opsx-workflow:apply`.

Run `opsx check <slug>` and read every `Must-fix 候選` line it prints: the card's explore.md wrote 影響範圍 as skip, yet the diff touches a file other files reference. A candidate is a grep hit, not proof: it misses shell variables and config keys, and it flags files only their own tests reference. Read the cited reference yourself; a candidate you confirm is a Must-fix, and review sends it back to explore (the `## R<N>. review 退回` group in tasks.md, so `/opsx-workflow:apply` and explore's 影響範圍 step redo it); one you cannot confirm goes to Consider.

Seed the report's D 對照 table from Agent A's `D_TABLE` (followed → 照做, violated → 偏離) and keep every row, followed ones included. After bucketing, a row whose finding you dismissed becomes 照做, and a row that a B or C finding in Act on or Consider contradicts becomes 偏離. Cite file:line, not a finding number. Agents B and C write `d_id: none`.

A BUG of the kind 「task 已勾但沒實作」 is 範圍內: the task is this change's own. Before routing it, read the diff yourself and confirm the task has no code at all; if it has code that contradicts a D, it is a MUST_FIX against that D. Both take the Step 4 path: the report line says 回 `/opsx-workflow:apply <slug>` 做完, and review itself never writes the missing code.

## Step 4: hand back, do not fix

In this step review changes no code: it touches only `tasks.md`, `report.md`, `gates.md`, `design.md` (for an answered logic-map gate) and the inbox.

- **範圍內, verified.** Append a group `## R<N>. review 退回` to tasks.md, one task per finding, each with the same `驗收：` and `測試：` sub-lines as any task (the `測試：` is the finding's regression test). List each under `### 待修（範圍內）` in report.md with its file:line. Then invoke `/opsx-workflow:apply <slug>` in this turn: apply writes the test first, fixes, checks the task off.
- **範圍外.** Do not fix it in this PR. Run `opsx new --type <bug|技術債|功能|想法|待定> --kind-of-work planned --repo <top> -- "<finding, failure scenario, path:line, 優先度 P2>"` (a security or data-loss incident takes the priority workplan-priority gives it instead of P2: `--kind-of-work incident --impact <值,…> --evidence "<一行>"`). `opsx new` refuses a card from a worker without `--kind-of-work`, and marks its source `agent:<this card>` by itself, so 不要帶 `--source` (`--source me` is refused for a dispatch agent, wherever its cwd is). `--type` defaults to `bug`; only a P2 `bug` or `技術債` that names a file another unstarted card also names is merged, so write the file as `path:line` in the one line or in `--evidence`. Put everything about the finding into the one-line text and `--evidence` before you know whether it merges, because nothing can amend them afterwards. The printed slug may be an existing card that this finding was merged into (stderr says `併進 <target>（id <id>）`); never edit that card's `## 證據`, and when the evidence did not fit, give the finding its own card with `opsx split-out <target> <id>` and write the rest there. Append ` · 開卡 <slug>` at the end of the finding's line in Consider; nothing follows it.
- **Unverifiable or a design question.** Consider, as before.
- **Logic map, undecided.** Every `沒經過決定` item of the map, and every item of a map that says 沒有 design.md，未分類, goes into one gate in `gates.md` with id `logic-map-undecided-r<N>`, where N is this review round, and `type: decision`. Each round gets its own gate: an earlier round's gate keeps its `answer:` and `寫回:` lines, and reusing its id would make a new answer look written back. The items are not verified by you or the reviewers: they are product decisions, not defects. Number the items, quote each one with its node, and give each 2 to 4 options with the first marked Recommended, so the user can answer them all at once (`1A 2B`). `程式整理` items and 照 design D items never go into the gate. With no such item, write no gate.
- **Logic map gate answered.** When the answer to the newest `logic-map-undecided-r*` gate arrives, write each item's answer into design.md as a new D, numbered after its largest D, with the 理由 line `使用者 <日期> 回邏輯表 ⚠ 選 <選項>`. An answer that changes the code becomes a task in a new `review 退回` group, numbered after the largest `## R<k>.` group already in tasks.md, not after the round, so it never shares a number with a group Step 4 wrote in the same round. Give the task `驗收：` and `測試：` like any task, and list it under `### 待修（範圍內）` in report.md with its task id: that line is what holds `/opsx-workflow:pr` and the Stop hook until a review confirms the fix. Then add one line under the gate in gates.md, `寫回: <日期> · <新的 D>`, so Step 0 and `/opsx-workflow:pr` know the answers are in design.md. Delete the whole `## 邏輯表` section from report.md: the map still labels these items 沒經過決定, and with an unmoved head pr step 5c would keep it; with no section, 5c builds a new map. Then continue by Step 5's rule: `/opsx-workflow:apply <slug>` while `待修（範圍內）` has items or an `R` task is unchecked, otherwise `/opsx-workflow:pr <slug>`. This is not a round: the round count in report.md does not change.
- **Confirm pass** (round 2 is done and its R tasks are checked): re-read only the diff of the fixed items, not the whole change. Move each confirmed item from `待修（範圍內）` to Act on with the fixing commit, and write one line `確認: <sha>` (the current HEAD) in report.md. An item that is still wrong is not sent back to `/opsx-workflow:apply` (every R task is already checked, so apply would have nothing to do and the card would loop): it gets a `type: decision` gate, and the flow waits for the user. No third full review.
- **Base-merge confirm pass** (the branch merged the base branch, `origin/main` or the forge's main, after the last review round, and the merge commit is the only thing new): this does not count as a round, so it never uses up round 2. Re-read only the merge commit's conflict resolutions and the diff of the files the change touches, run the change's tests, then write one line `確認: <sha>` (the current HEAD) in report.md. The Stop hook treats `確認: <sha>` as covering HEAD when no ordinary commit of the branch itself (first-parent, merge commits excluded) lies between `<sha>` and HEAD, so the merge does not send the card back to review. The merged side must already be on a remote-tracking branch (`git branch -r --contains <second parent>`); a local side branch merged in carries unreviewed work and needs a real review round, like any commit the branch adds after the merge.

If a hook or safety check blocks any action here, follow `../../references/harness-claude-code.md`; do not reword the command to get past it. The suite is the test agent's job inside apply; review does not run a fix cycle.

## Step 5: report.md

```markdown
# Review · <slug> · 第 <N> 輪 · <date> · <commit>

## D 對照
| D | 狀態 | 位置 |
|---|---|---|
| D1 | 照做 / 偏離 | <file:line，或指向的 finding> |

## 四桶
### 待修（範圍內）
- <file:line> <description> · D-id <Dn|none> · 來源 <A|B|C> · task R<N>.<k>
### Act on（已修）
- <file:line> <description> · D-id <Dn|none> · 來源 <A|B|C> · 修前清單 <file:line> · commit <sha>
### Consider
- <file:line> <description> · D-id <Dn|none> · 來源 <A|B|C>（未實作的 task 寫：回 `/opsx-workflow:apply <slug>` 做完）
### Noted
- <file:line> <description> · D-id <Dn|none> · 來源 <A|B|C>
### Dismissed
- <file:line> <description> · D-id <Dn|none> · 來源 <A|B|C> · 因為 …

確認: <sha>   <!-- 只在第 2 輪後的確認 pass 寫 -->

## 邏輯表
<Step 1b 寫的那一行；確認 pass 照抄上一輪的>

## 測試
<test agent 最後一次的摘要：N passed，lint 狀態>

## Ledger
<commit sha> · <what was verified and how> · verdict: <green|red>
```

A later round rewrites the file from this template but keeps an existing `## MR` section verbatim: `/opsx-workflow:pr` appends it, and the router and merge read the URL from it. It also keeps the `· 接受` or `· 開卡 <slug>` mark at the end of every Consider item that is still listed. The user accepts a Consider item by adding `· 接受` at the end of its line; while a Consider item has neither mark, the board does not list the card as mergeable.

`opsx status review 7/7 "report.md 寫好"`. Reply with the bucket counts, what was sent back to apply, which inbox cards were opened, what the user should look at in Consider, and the two closing lines. Then continue per `../../references/continue.md`: `/opsx-workflow:apply <slug>` while `待修（範圍內）` has items, otherwise `/opsx-workflow:pr <slug>`, in this turn, unless a gate is open. Consider never opens a gate and never sends the card back to apply. Only an item that needs a user decision and cannot be fixed opens a gate. A `沒經過決定` ⚠ in the logic map is not Consider: its gate holds the card before `/opsx-workflow:pr`. While the newest `logic-map-undecided-r*` gate is open, reply with its question and stop.

## Guardrails

- Never skip step 0. The gate is the whole point of test-first.
- Three agents every time except a small card (one merged reviewer); on any other card C is not optional and not only for contested designs.
- Findings without evidence are not findings.
- Two rounds at most. Anything in scope is fixed by `/opsx-workflow:apply` in this session; anything out of scope is an inbox card; the rest is in the report for the human reviewer.
- Review never implements a task or fixes code. 已勾但沒實作 and every in-scope finding go back to `/opsx-workflow:apply`.
