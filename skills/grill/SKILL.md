---
name: grill
description: |
  Grill the user about the whole plan of a change before it gets proposed, until you both understand
  it the same way. Reads inbox.md, explore.md (已知 / 待決 / 不做), CONTEXT.md, the ADRs, the workplan
  and the parent card, lists every branch of the plan, sorts each into "answerable from the code",
  "answerable by running something once", or "only the user can answer", resolves the first two
  itself, asks the third one question at a time with 2–4 concrete options, and writes the result to
  grill.md as numbered decisions (D1, D2…) plus what is still unknown. Runs after explore for every
  card whose kind is not chore or bug-fix, even when 待決 is empty. Use when the user says "grill",
  "grill me", "幫我釘決定", "待決", "還有什麼沒定", or asks you to pressure-test a plan before
  proposing it. Also the stage the opsx router injects between explore and propose. A card whose kind
  is chore or bug-fix skips it and goes straight to /propose.
argument-hint: "[change slug]"
---

# /grill

**Steps in TodoWrite.** First action after loading: put the numbered steps in `## Steps` into TodoWrite verbatim; a step you will not do stays in the list as `skip: <reason>`, never deleted.

## Core

This is Matt Pocock's grill-me (`~/.claude/skills-retired-20261110/grill-me/SKILL.md`), with the opsx flow added around it:

> Interview the user relentlessly about every aspect of their plan until you reach a shared understanding. Walk down each branch of the design tree, resolving dependencies between decisions one-by-one.

The plan is the whole card, not only explore.md's 待決. An empty 待決 means explore found no open question; it does not mean the plan has none. The rest of this file says what to read, which branches reach the user, and what to leave for propose.

## Steps

1. Kind chore or bug-fix: reply「<slug> 是 chore / bug-fix，不經 grill，直接 /opsx-workflow:propose」and stop. Otherwise read every source in `## What to read`, even when 待決 is empty, and list the branches of the plan: each 待決 item, each 已知 entry that hides a choice and each 不做 item (`## Reopen 已知 and 不做`), and whatever the inbox line or 派工指示 leaves open.
2. Walk the branches one at a time with AskUserQuestion, 2 to 4 options, the recommended one first, in the words `CONTEXT.md` uses (`references/CONTEXT-FORMAT.md`). In autopilot do not call AskUserQuestion; follow `## In autopilot`.
3. A branch the code or one run can answer is yours: look it up or run it, write the answer into explore.md's `## 已知`, and when the item was in 待決, remove it from 待決. Only a branch nobody but the user can answer is asked.
4. When every branch is resolved, write D1 to Dn into `grill.md` (decision, reason, rejected alternative) and continue to `/opsx-workflow:propose <slug>`. In autopilot with a gate still open, write the Ds you have and stop.
5. Before the summary goes out, `Read ../technical-writing/SKILL.md` and apply it, then `Read ../unslop/SKILL.md` and apply that.

## Where you are

`openspec/changes/<slug>/explore.md` exists. Grill runs between explore and propose for every card whose kind is not chore or bug-fix, whether 待決 is empty or not. It is not a place to re-explore: what explore already settled with code or a run stays settled; what it settled by choosing, you confirm.

If the card's `.openspec.yaml` says the kind is chore or bug-fix, grill does not run for it (`../../references/continue.md`, "Light flow"): reply「<slug> 是 chore / bug-fix，不經 grill，直接 /opsx-workflow:propose」and stop. Propose turns the open items into assumptions.

## What to read

Read all of these before the first question. A dispatch worktree has no `openspec/` (it is not in git), so read every path under `openspec/` from the main checkout, by its absolute path, the same way propose does. The user will use words from their own head; you need to know when those words collide with what the project already calls things, and which choices were already made somewhere else.

- The card's `inbox.md`: the one line the user wrote, its `## 證據`, and its `## 派工指示` section when there is one. An instruction there that leaves a scope open is a branch.
- explore.md's `## 已知`, `## 待決` and `## 不做`, all three.
- `CONTEXT.md` (or `CONTEXT-MAP.md` and the context it points at), `docs/adr/`, `openspec/workplan.yaml`.
- The parent card, when there is one. A card split out of a bigger one is listed in the parent's `inbox.md` frontmatter as `split_into:`; find it with `grep -l '<slug>' <main checkout>/openspec/changes/*/inbox.md` and keep only the hit where the slug is a whole item of the `split_into:` list (`kb-export` does not match `kb-export-csv`). A sub-change (`openspec/changes/<main>/subs/<sub>/`) names its main change as `parent:` in its own `inbox.md` frontmatter. Read the parent's `explore.md` and `grill.md`. A D the parent card already decided is not asked again; cite it by the parent's slug and D-id where it matters.
- No parent card: do not look further and do not ask about it.
- The card's own `grill.md` and `gates.md`, when grill ran on this card before (a gate answer came back, or the pane was relaunched). The Ds already written stay as they are: continue numbering after the last D, and handle only the branches still open in 待決 or waiting on a gate.

## Reopen 已知 and 不做

Explore writes facts into 已知 and exclusions into 不做, but some of them were choices the user never saw. A plan that drops a role check because 已知 called it unused, or skips a channel because 不做 listed it, has made a product decision without asking. So:

- **Every 不做 item is a branch.** Confirm it with the user, even when it looks obvious. Leaving something out is a choice.
- **Every new behaviour has failure branches.** For each new path the card adds, list what happens when it does not succeed: the tool or call returns an error, a precondition is not met (the account is not connected, the record is gone, the user lost access), whether the failure is logged or audited, and what the user sees (including in another UI language). Each one the code cannot answer is a bucket-3 branch. Asked here, it becomes a D and a negative Scenario; left out, it surfaces only when the logic map reads the finished code, after review and CI.
- **An 已知 entry that hides a choice is a branch.** It hides a choice when the state it describes could be kept or changed, and this card's scope touches it. "role_gate has no reader at runtime" hides a choice: the card has to decide whether to wire a reader or delete it.
- **A pure fact in 已知 is not asked.** It says where code lives or how it works, and the card does not have to decide whether to change it.

| Section | Entry | Ask the user? |
|---|---|---|
| 不做 | LINE 與自動草稿的工具組不動 | yes |
| 已知 | role_gate 沒有任何執行期讀取端 | yes |
| 已知 | getUserAppRoles 回三個模組的角色 slug | yes |
| 已知 | stage.sh 的 stage_of 依 kind 與 grill.md 決定下一站 | no: pure fact |
| 已知 | 母卡 grill.md 已定 D3：不改 role_gate | no: the user answered it on the parent card |
| 不做 | 不改 eval fixture 的 schema 複本 | yes: every 不做 is confirmed |

When the user's answer turns a 不做 into scope, or an 已知 into a change, it becomes a D like any other answer.

## Classify before you ask

Every branch goes into exactly one bucket. Only the third bucket reaches the user. The user's attention is the scarce resource in this flow; spending it on something `grep` or a ten-line script could answer is the failure mode this skill exists to prevent.

1. **The code answers it.** Current behavior, what calls what, which table holds it, whether a helper already exists. Go look. Write the answer into explore.md's `## 已知` with the file path, and remove the item from 待決.
2. **Running it once answers it.** Timing, layout, actual output, how a library behaves on this input, whether approach A or B is faster. Build the smallest throwaway that observes the thing, in a scratch directory outside the source tree, following `skills/explore/references/prototype.md`. The observation is the answer. Record it in 已知 with what you ran and what you saw, and remove the item from 待決. Do not ask the user to guess something you can measure.
3. **Only the user can answer it.** Product choice, preference, risk appetite, priority between two valid designs, anything that depends on what they want rather than what is true. These are the questions you ask.

If you are unsure which bucket a branch belongs to, try bucket 1 for a few minutes before defaulting to bucket 3.

## How to ask

- Use the **AskUserQuestion** tool for every question. Never ask in plain prose. The popup is what lets the user answer in one click or type their own.
- **One question at a time.** Wait for the answer before the next. Each answer can change what the next question should be; a batch of questions throws that away.
- **2–4 concrete options**, each a real alternative with its consequence in a few words. Yes / No is almost never the right pair; the user can always pick "Other". Put your recommended option first and mark it `(Recommended)`, with one line on why.
- **No shorthand tokens for answering.** Do not ask the user to reply "A" or "1". They answer in their own words or by picking the option.
- **Order the questions by dependency.** If question 3's options change depending on question 1's answer, ask 1 first. Walk the decision tree one branch at a time rather than jumping around.
- After an answer, acknowledge it in one sentence, then ask the next question. No summaries mid-stream.

## In autopilot

When the router line carries `autopilot：`, nobody is watching the pane. AskUserQuestion there makes herdr mark the agent blocked, and the drive loop cannot send the next command. So in autopilot you never call it. Buckets 1 and 2 work the same as always. Every 不做 item and every 已知 entry that hides a choice is a product choice, so it is a gate below; the user's answer becomes a D whether it keeps the item as it is or changes it. Each bucket-3 branch goes one of two ways:

- **It is a product choice, or the decision is hard to undo** (a data shape that gets migrated, a public interface, anything the user would have to unpick after merge). Write it as a gate in `gates.md` and leave the item in explore.md's 待決 (add it there when it came from 已知 or 不做):
  ```
  ## <short-id>
  type: decision
  status: open
  問題: <the question, one line>
  已確認: <what is already settled on this point>
  選項: <option> (Recommended) | <option> | <option>
  建議: <why the recommended one>
  證據: <files, what you ran>
  風險: <what goes wrong with the recommendation>
  預設: <what happens if nobody answers>
  ```
  The options follow the same rules as an AskUserQuestion: 2–4 real alternatives, recommended first. `type` is `approval` (a permission) or `decision` (a choice) and nothing else; when 建議 is a command the user must run themselves, add a `needs: run` line; when a `decision` can only be answered after another card merges into main, add `waits-on: <that card's name>`.
- **Anything else.** Take the option you would have marked Recommended. Write it as a D like any other, add a `  - 自動採用：autopilot，沒問使用者` line under it, and log one line in decisions.tsv. The user can overturn it at review or on the MR.

Open every bucket-3 gate that does not depend on another at once, each as its own gate, so one round of answers clears most of them. A question whose options depend on another question's answer is not opened yet: leave it in explore.md's 待決 with this line under it, and open it when that answer comes back:
```
  - waits on gate: <gate id>
```
The router reads that line: while a 待決 item carries it, the card goes back to grill instead of propose. Remove the line when you open the gate.

While any gate is open, do not continue to /opsx-workflow:propose. Write grill.md with the Ds you have, say which branches wait on which gate, and stop. Each answer comes back as a prompt: turn it into its D, remove the item from 待決, open any gate that was waiting on it, and carry on. When every branch is resolved and no gate is open, propose comes next.

## Challenge the language as you go

When the user uses a word that `CONTEXT.md` or the code uses differently, say so right there:「你說的 cancellation 是整張 Order 取消，還是 CONTEXT.md 寫的部分取消？」When a term is vague ("account", "user"), ask which concrete concept they mean before building a decision on it. When the user states how something works and the code disagrees, show the file and ask which one is right. A decision written on a fuzzy word turns into a bug in apply.

If a term gets resolved, update `CONTEXT.md` inline using `references/CONTEXT-FORMAT.md`. Create the file only when there is something to write.

## Output

When every branch is either resolved into 已知 or answered, write `openspec/changes/<slug>/grill.md`. Always write grill.md, even when no branch reached the user: then `## 決策` holds the one line `- 無：所有分支由 已知 解決`. The router treats a missing grill.md as grill not done, so skipping the file sends the card back to grill.

```markdown
## 決策
- D1 <one-sentence decision>
  - 理由：<why this, in the user's terms>
  - 否決：<the alternative> 因為 <reason>
- D2 …

## 未決
- <something only running the real thing will show> · 驗證：<how it will be checked, and in which step of apply>
```

Rules that keep this file useful downstream:

- **D-ids are permanent.** Propose copies D1…Dn into design.md's Decisions section as-is, and review checks each D against the code by id. Never renumber, never reuse a number for a different decision.
- **A D is something the user chose.** It comes from an answer to a question you asked, or from a 已知 fact the user confirmed when it changed the picture. Parameters that merely follow from a D (which helper to reuse, the retry count that falls out of a stated time limit) are not new Ds; they go into that D's 理由 line or are left for apply to work out. A grill.md full of Ds the user never saw is a design doc wearing a disguise.
- **One decision per D.** If an answer settles two things, write two Ds.
- **Questions that surface mid-grill are asked the same way.** If answering one branch reveals another real choice (a scope the user's words left open, a term that collides with CONTEXT.md), ask it, one at a time. If you cannot get an answer in this run, it goes back into explore.md's 待決 with the options you would offer, so the next /grill picks it up. It does not become a note at the bottom of grill.md, and it does not become a D by default.
- **未決 is not a parking lot.** Only things that genuinely need a run to settle, each with its verification plan. If you can settle it now with bucket 1 or 2, do that instead.
- **Write an ADR too** when a decision meets all three of: hard to reverse, surprising without context, the result of a real trade-off. Use `references/ADR-FORMAT.md`; most decisions will not qualify, and that is fine.

Do step 5 of `## Steps` on the summary. Then tell the user in a few lines what got decided and what is still open. When every branch is resolved and no gate is open, continue to `/opsx-workflow:propose <slug>` per `../../references/continue.md` in this turn; if anything went back into 待決, stop there. Call `opsx status grill <n>/<total> <label>` as you move through the branches so the board shows progress.

## What this skill does not do

- It does not write code, proposals, specs, or tasks. Propose does that, from grill.md.
- It does not re-ask what code or a run already settled in 已知, or a D the parent card already decided.
- It does not ask about implementation detail that apply can decide on its own (naming, file layout, which helper to use).
