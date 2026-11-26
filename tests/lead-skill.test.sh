#!/usr/bin/env bash
# skills/lead/SKILL.md：協調者的職責與五塊回報格式。specs/opsx-lead/spec.md「協調者 skill 寫明職責與五塊回報格式」。
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
F="$OPSX_ROOT/skills/lead/SKILL.md"
assert_file "$F"

# babysit 之後 MR 全綠卻沒標可以合併時 Stop hook 推的兩行（me-20261117-1421），協調者要查得到
grep -qF '停住：babysit 做完，邏輯表不是 MR 最新 head' "$F" || fail "skill 缺新推送：邏輯表不是 MR 最新 head"
grep -qF '停住：babysit 做完，report.md 有留給人決定的項目' "$F" || fail "skill 缺新推送：report.md 有留給人決定的項目"
grep -qF '停住：babysit 做完，邏輯表有沒經過決定的項目沒處理' "$F" || fail "skill 缺新推送：邏輯表有沒經過決定的項目沒處理"
grep -qF 'whichever `停住：babysit 做完，…` line the hook sent for that card' "$F" || fail "skill 要把 report 待你決定跟 hook 任一條 babysit 停住行算同一項"
! grep -qF 'only three states stay silent: the MR is ready (coordinate sends 可以合併)' "$F" || fail "MR ready 不再一律靜音"

# 五塊依序出現
line_of() { grep -nF -- "$1" "$F" | head -1 | cut -d: -f1; }
prev=0
for h in '① 要你處理' '② 可合併（依序）' '③ 進度' '④ 我處理掉的' '⑤ 最後一行'; do
  n="$(line_of "$h")"; [ -n "$n" ] || fail "缺區塊標題：$h"
  [ "$n" -gt "$prev" ] || fail "區塊順序錯：$h 在第 $n 行，前一塊在第 $prev 行"
  prev="$n"
done

# 每塊的欄名
for s in \
  '| # | 卡 | 問什麼 | 我的建議 | 詳情 |' \
  '→ 回『1 照建議』即可' \
  '| # | 功能 | PR | 卡 | 測試 | 邏輯表 | PR 連結 |' \
  '進度 HH:MM · <current_milestone>：剩 N 張 · 可合併 a · 測試中 b · 開發中 c · 等你 d · 還沒派 e' \
  '| 功能（session） | 卡 | 優先度 | 階段 | 卡在 |' \
  '| 卡 | 發生什麼 | 我怎麼處理 | 開卡 |' \
  '絕對路徑' 'path:line' '絕不合併' 'me-20261111-1315' 'logic-map.md' 'report.md'; do
  grep -qF -- "$s" "$F" || fail "skill 缺：$s"
done

# 可合併只看 agent 的回報（review 完、相關測試綠、跟 main 無衝突）；多張一起合時只用 git merge-tree 查依序疊起來無衝突，不重跑全套
# 只看職責 4 那一段（從「4. 」到「5. 」），表格註解裡的字不算
D4="$(sed -n '/^4\. /,/^5\. /p' "$F")"
[ -n "$D4" ] || fail "找不到職責 4"
for s in 'reports review done' 'Do not rerun the suite yourself' 'git merge-tree --write-tree' 'git commit-tree'; do
  case "$D4" in *"$s"*) ;; *) fail "職責 4 缺：$s" ;; esac
done
case "$D4" in *"run the full suite"*|*"rerun the suite against"*) fail "職責 4 不能叫協調者自己重跑全套：$D4" ;; esac

# 去重是協調者的職責（specs/card-auto-merge「協調者 skill 寫明去重」）：Duties 裡有一條含 opsx merge-card 與同一件事，不受只併小事限制
DUTIES="$(sed -n '/^## Duties/,/^## Report format/p' "$F")"
DEDUP="$(printf '%s\n' "$DUTIES" | grep -F 'opsx merge-card')"
[ -n "$DEDUP" ] || fail "Duties 缺 opsx merge-card 的去重職責"
for s in '同一件事' '只併小事' 'decisions.tsv' '④' 'kind_of_work' 'impact'; do
  case "$DEDUP" in *"$s"*) ;; *) fail "去重職責缺：$s — $DEDUP" ;; esac
done

# 怎麼問 gate（specs/opsx-lead「協調者用跳卡問 gate」「跳卡不代答」「有 sketch 外掛時先畫 cards」）：
# 只讀「## 怎麼問 gate」到下一個 ## 標題，別段的字不算；標題要夾在 ## Duties 與 ## Report format 之間
ASK="$(awk '/^## 怎麼問 gate/{f=1;next} f&&/^## /{exit} f' "$F")"
[ -n "$ASK" ] || fail "找不到「## 怎麼問 gate」段"
heading_of() { grep -n "^$1\$" "$F" | head -1 | cut -d: -f1; }
n_duties="$(heading_of '## Duties')"; n_ask="$(heading_of '## 怎麼問 gate')"; n_report="$(heading_of '## Report format')"
[ -n "$n_ask" ] && [ "$n_ask" -gt "$n_duties" ] && [ "$n_ask" -lt "$n_report" ] \
  || fail "「## 怎麼問 gate」要在 ## Duties（${n_duties}）與 ## Report format（${n_report}）之間，現在在 ${n_ask:-沒有}"
for s in 'AskUserQuestion' 'recommended option first' '(Recommended)' '最多 4 題' '卡名' '例子' \
  'opsx answer' '原文' 'Other' '重講' '不代答' \
  'without the `(Recommended)`' 'at most 12 characters' \
  '--grant' 'test-path' 'mode: stopped' 'approve option' '不准' 'Before each `opsx answer`' 'stderr' \
  'desktop' \
  'sketch' 'cards' '沒裝' 'enabledPlugins' 'opsx init --global' 'user settings' 'card pane'; do
  case "$ASK" in *"$s"*) ;; *) fail "怎麼問 gate 段缺：$s" ;; esac
done
# init 合併 coordinator-settings.json，手加的 enabledPlugins 會留著（specs/opsx-lead「不再叫人重加 enabledPlugins」）
case "$ASK" in *'add it again'*|*'drops'*) fail "怎麼問 gate 段不能再叫人重加 enabledPlugins" ;; esac
# needs: run 的 gate 不進跳卡、給指令
NR="$(printf '%s\n' "$ASK" | grep -F 'needs: run')"
case "$NR" in *'stays out of the pop-up'*指令*) ;; *) fail "needs: run 那行要寫 stays out of the pop-up 並給指令：$NR" ;; esac
case "$NR" in *'goes in the pop-up'*) fail "needs: run 的 gate 不能進跳卡：$NR" ;; esac
# by: coordinator 的 needs: run 題歸協調者代跑、照實貼回；沒標 by 的仍給使用者指令（coordinator-run-owned）
RUN="$(printf '%s\n' "$DUTIES" | grep -F 'by: coordinator' | grep -F 'opsx answer')"
for s in 'worktree' 'exit code' 'block ①'; do
  case "$RUN" in *"$s"*) ;; *) fail "代跑段缺：$s — $RUN" ;; esac
done
case "$NR" in *'no `by: coordinator`'*'stays out of the pop-up'*) ;; *) fail "給使用者指令的只限沒標 by 的 needs: run：$NR" ;; esac
# 跑之前重讀 status；失敗、被拒或不是單次指令都不 answer，刪掉 by 那行交給使用者（design D12、D13）
case "$RUN" in *'re-read'*'status:'*'still `open`'*) ;; *) fail "代跑前要重讀 status、還 open 才跑：$RUN" ;; esac
case "$RUN" in *'exits non-zero, do not run `opsx answer`'*"delete the gate's \`by: coordinator\` line"*) ;; *) fail "失敗不 answer、刪 by：$RUN" ;; esac
case "$RUN" in *'not one command'*'delete its `by: coordinator` line'*) ;; *) fail "不是單次指令也刪 by：$RUN" ;; esac
# force、+ refspec、推別人的 branch、刪除、合併不跑；回結果開頭寫「協調者代跑：」（design D16、D17）
for s in 'force' '`+` refspec' "another card's branch" 'delete' 'merge'; do
  case "$RUN" in *"never run"*"$s"*) ;; *) fail "代跑段不跑的清單缺：$s — $RUN" ;; esac
done
case "$RUN" in *'"協調者代跑：<指令> → exit 0'*) ;; *) fail "回結果開頭要寫「協調者代跑：」：$RUN" ;; esac
# 合併類唯一例外：同時帶 merge_when_pipeline_succeeds=true 與 sha= 的 auto-merge 重設照跑，少一個就當合併（specs/opsx-lead「代跑帶 sha 的 auto-merge 重設」）
case "$RUN" in *'auto-merge reset'*'carrying both `merge_when_pipeline_succeeds=true` and `sha=<full head sha>`'*) ;; *) fail "代跑段要放行帶兩參數的 auto-merge 重設：$RUN" ;; esac
case "$RUN" in *"\`<iid>\` is the MR in that card's report.md \`## MR\` URL"*) ;; *) fail "iid 要是這張卡的 MR：$RUN" ;; esac
case "$RUN" in *'either parameter is missing, the sha is not a full 40-character sha, or the iid is another MR, it counts as a merge'*) ;; *) fail "少參數、sha 不完整、別張 MR 都當合併類：$RUN" ;; esac
# 跑之前讀一次 pipeline，只有還在跑才跑（放行清單）；null、已綠、失敗都不跑、刪 by、列進 ①（D12、R3.1）
case "$RUN" in *'Before running it, read `glab mr view <iid> -F json` once'*'Run it only when `head_pipeline` is not null, its sha equals the `sha=` of the 建議, and its status is `created`, `pending`, `running`, `waiting_for_resource`, `preparing` or `scheduled`'*) ;; *) fail "重設前要讀 pipeline、只在還在跑時跑：$RUN" ;; esac
case "$RUN" in *'In every other case the PUT would merge at once'*"delete its \`by: coordinator\` line and list it in block ①"*) ;; *) fail "其餘狀態不跑、刪 by、列進 ①：$RUN" ;; esac
case "$RUN" in *'when `head_pipeline.status` is `success`, the PUT would merge at once, so do not run it'*) fail "防線不能只擋 success：$RUN" ;; esac
# 讀取到 PUT 之間變綠的窗口寫明接受（D18）
case "$RUN" in *'The window between that read and the PUT is accepted'*'merges at once'*) ;; *) fail "要寫明讀取到 PUT 之間的窗口：$RUN" ;; esac
# 轉給使用者時提醒已綠會直接合併（D26）
case "$RUN" in *'When you list a reset gate in block ①, add that the PUT merges at once if the pipeline has turned `success`'*) ;; *) fail "轉給使用者時要提醒已綠會直接合併：$RUN" ;; esac
# 讀 CI log 的兩步 gate 是單一指令規則唯一的多步例外（babysit-ci-log-gate，specs/opsx-lead「代跑兩步讀 CI log 的 gate」）
for s in \
  'The one multi-step 建議 you do run is a CI log read' \
  'both steps are `curl` GETs carrying `PRIVATE-TOKEN: $(cat ~/.local/state/opsx/gitlab-read-token)`' \
  'the first to `pipelines/<pipeline-id>/jobs`, the second to `jobs/<job-id>/trace`' \
  'with the GitLab host in `allowed_domains`' \
  'paste back each failed job'"'"'s name, the failing test'"'"'s name and its assertion block, or the first error block for a job with no test assertion, not the tail of the output' \
  'When either step carries `-X`, `--request`, `-d` or `--data`, or calls any other endpoint, it is not one command' \
  'Never echo the token, never use curl'"'"'s `-v` or `--trace`, and never write the token'"'"'s value into an answer, a gate or a file'; do
  case "$RUN" in *"$s"*) ;; *) fail "代跑段缺讀 CI log 的例外：$s" ;; esac
done
MR17="$(printf '%s\n' "$DUTIES" | grep -F '17. **Mergeable report.**')"
case "$MR17" in *'Never set auto-merge on your own'*) ;; *) fail "職責 17 要寫協調者不自己發起設 auto-merge：$MR17" ;; esac
FG="$(printf '%s\n' "$DUTIES" | grep -F '2. **Forward gates')"
case "$FG" in *'`by: coordinator`'*) ;; *) fail "duty 2 開頭要寫明代跑結果是例外：$FG" ;; esac
# 跳卡回來後重讀 open gate：只問能進跳卡的（不是 needs: run、不是 waits-on），子 change 的 gate 也讀、用 --sub 回
RR="$(printf '%s\n' "$ASK" | grep -F 'status: open')"
for s in 'needs: run' 'waits-on' 'subs/' '--sub'; do
  case "$RR" in *"$s"*) ;; *) fail "重讀 open gate 那行缺：$s — $RR" ;; esac
done
# 不替使用者選
case "$ASK" in *自動採用*) fail "怎麼問 gate 段不能有「自動採用」" ;; esac
# compare 在段裡只出現一次，就是「不用 compare 選」那一處
assert_eq "$(printf '%s\n' "$ASK" | grep -o 'compare' | wc -l | tr -d ' ')" 1 "怎麼問 gate 段 compare 只能出現一次"
case "$ASK" in *'不用 `compare` to choose'*) ;; *) fail "怎麼問 gate 段要寫「不用 \`compare\` to choose」" ;; esac
# 職責 2 指向這段
printf '%s\n' "$DUTIES" | grep '^2\. ' | grep -qF '怎麼問 gate' || fail "職責 2 要指向「怎麼問 gate」段"

# 職責 8–11（specs/opsx-lead「① 一直追要使用者做的事」「可授權的 approval gate 給一次性授權指令」「閒時派待指派」
# 「收件匣派去 explore」「寫 skill 的卡派工時要求 skill-creator」）：用編號切出那一條，別條的字不算。
# 比對整句，反例的那句也要在，單字會被別處的字滿足（working 在 max-working 裡）
duty() { printf '%s\n' "$DUTIES" | grep "^$1\. "; }
D1="$(duty 1)"; D8="$(duty 8)"; D9="$(duty 9)"; D10="$(duty 10)"; D11="$(duty 11)"
# 協調者的 report 待你決定通知跟 Stop hook 的那行是同一件事；處理完的判準；職責 9 只派沒有條目的卡
for s in '[<card>] report 待你決定' 'the same item as the hook'; do
  case "$D1" in *"$s"*) ;; *) fail "職責 1 缺：$s — $D1" ;; esac
done
case "$D8" in *'`waiting.type` is no longer `report 待你決定`'*) ;; *) fail "職責 8 缺 report 待你決定何時算處理完 — $D8" ;; esac
case "$D9" in *'Take only a card that has no dispatch.json entry'*) ;; *) fail "職責 9 要是一句「只派沒有條目的卡」 — $D9" ;; esac
case "$D9" in *'whose dispatch.json entry is not `mode: stopped`'*) fail "職責 9 不能留舊的那句，會跟新規則矛盾 — $D9" ;; esac
for s in 'leave ① out only when nothing is pending' 'starting with `!`' '下一輪' 'until it is gone' \
  'what it unblocked has moved' '`action:` is push, mr, install or delete' '--grant repo'; do
  case "$D8" in *"$s"*) ;; *) fail "職責 8 缺：$s — $D8" ;; esac
done
for s in 'no pane is working and ① has no open gate' 'priority level, then workplan order' 'P2 included' \
  'only a card whose workplan dependencies are all merged' 'mode: stopped' 'max-working' \
  'While any pane is working, dispatch nothing extra' 'Keep the number of working panes below max-working'; do
  case "$D9" in *"$s"*) ;; *) fail "職責 9 缺：$s — $D9" ;; esac
done
# 放掉且 pane 已收的補卡可以派（inbox-autofill D14）：新句子整句在，原本只派沒有條目的那句也整句還在
for s in 'Also take a card whose entry has `released_at` and whose pane is closed (`pane_closed_at` or `reaped_at`): coordinate filled it from the inbox, released its pane after propose, and dispatches it again only at P0/P1, so a filled card that came out of propose at P2 waits for you.' \
  'Take only a card that has no dispatch.json entry, or whose entry is `mode: stopped` and which the user has since asked to restart; any other entry means the card is already dispatched (待指派 also lists cards still in explore, grill or propose whose pane is alive), and `opsx dispatch` refuses it.' \
  'A card with unmerged dependencies, or one the user stopped, waits, and coordinate holds them back for the same reason.'; do
  case "$D9" in *"$s"*) ;; *) fail "職責 9 缺整句：$s — $D9" ;; esac
done
# 名額只算工作中的 pane（specs/dispatch-concurrency）：idle、blocked、done 不佔名額，留著 live pane 的說法會跟協調者數得不一樣
case "$D9" in *'live pane count'*) fail "職責 9 要說工作中的 pane 數，不是 live pane count — $D9" ;; esac
# 收件匣交給 coordinate 補卡，協調者只判重複、蓋記號（specs/opsx-lead「收件匣那條職責寫明交給 coordinate、只判重複」
# 「協調者不自己派收件匣卡」「P2 收件匣卡不派」）
D6="$(duty 6)"
for s in 'Every round, start from `opsx dedup --candidates --repo <top>`' \
  'fold the cards you judge 同一件事 with `opsx merge-card` as above' \
  'stamp every remaining P0/P1 card you inspected with `opsx dedup <slug>… --repo <top>`' \
  '`opsx coordinate` fills only stamped cards' \
  'Leave P2 cards unstamped'; do
  case "$D6" in *"$s"*) ;; *) fail "職責 6 缺：$s — $D6" ;; esac
done
for s in 'Inbox cards are filled by `opsx coordinate`' \
  'Do not dispatch inbox cards with `opsx dispatch` yourself' \
  'your part is duty 6: judge duplicates and stamp the rest with `opsx dedup`' \
  'Leave P2 收件匣 cards undispatched and list them in block ③' \
  'A `dispatch-<main>` gate left by a split stays the user'"'"'s' \
  'do not dispatch that main change yourself'; do
  case "$D10" in *"$s"*) ;; *) fail "職責 10 缺：$s — $D10" ;; esac
done
for s in 'dispatch each remaining P0/P1 收件匣 card' 'slots left after 待指派' 'a P0 card ignores max-working' 'P2 included'; do
  case "$D10" in *"$s"*) fail "職責 10 不能有：$s — $D10" ;; esac
done
for s in 'skill-creator' '--note' '依 skill-creator 撰寫' 'design.md' 'decisions.tsv' 'agents/*.md' \
  'evaluation loop' 'only changes code gets no such note'; do
  case "$D11" in *"$s"*) ;; *) fail "職責 11 缺：$s — $D11" ;; esac
done
# 授權指令由使用者自己答：職責 2 的不代答不變，Duties 裡沒有自動採用
duty 2 | grep -qF 'answer none yourself' || fail "職責 2 要保留 answer none yourself"
case "$DUTIES" in *自動採用*) fail "Duties 不能有「自動採用」" ;; esac

# 流量控管（specs/opsx-lead「每輪依序看四欄」「coordinate 放棄的卡列進 ①」「有 open gate 時，跳窗不擋住同一輪的其他欄」
# 「載入後開 10 分鐘一輪」「這個 session 已有流量控管的 loop 時不開第二個」「跳窗開著時不搶著跑」
# 「context 壓縮後不把舊的 ?? 行列進 ①」「同一個 gate 的 ?? 行在兩輪都出現時不輸出」「用量上限暫停時，等待中的卡不列進 ①」
# 「沒事不輸出」「① 少了一項時輸出目前的 ①」「有處理掉的事就回報」「這一輪不列 forge 上的 open MR」）：只切職責 19 那一條
D19="$(duty 19)"
[ -n "$D19" ] || fail "找不到職責 19（流量控管）"
for s in 'Flow control' '`opsx collect`' '待處理, then 等待中, then 待指派, then 收件匣' \
  'list the scheduled tasks of this session with CronList; when none has the prompt `職責 19 流量控管：跑一輪`, start `/loop 10m 職責 19 流量控管：跑一輪`' \
  'pop-up is open' 'waits until the pop-up returns' 'never open a second pop-up' \
  'open the pop-up only after the 等待中, 待指派 and 收件匣 columns are done' \
  'never push a pane yourself' 'lost its --settings' 'redispatches a dead one' \
  'read only the latest coordinate run in `$OPSX_STATE_DIR/coordinator.log`, from the last `== coordinator 開始` line to its `== 結束` line' \
  'list each `??` line from it in block ①' 'unless its gate is already there from 待處理' \
  'Compare block ① by card and reason, never by the timestamps' \
  'outputs nothing' 'not even a line saying so' \
  'handled nothing and block ① is the same as in your last output' 'what coordinate already pushed does not count as handled' \
  'When block ① differs from your last output, by an item added or gone, output the current block ①' \
  'fully handled that the user does not need to know about gets no reply' 'report it in block ④ together with the current block ①' \
  'duty 14 does not run in it' \
  '待處理 by duties 2 and 8' '待指派 by duty 9' '收件匣 by duty 10'; do
  case "$D19" in *"$s"*) ;; *) fail "職責 19 缺：$s — $D19" ;; esac
done
# 三欄照職責 2、9、10：職責 19 不另訂派工上限、不代答；推 pane 是 coordinate 的事；等協調者是 collect 給任何閒著 pane 的預設標籤，不是 coordinate 放棄
for s in 'opsx merge' 'glab mr merge' 'gh pr merge' 'CronCreate' 'max-working' 'P2' 'Recommended' 'opsx answer' 'opsx dispatch' \
  'herdr pane send-keys' 'herdr pane read' 'herdr agent prompt' 'send-text' 'opsx relaunch' '「繼續」' \
  'since your last round' '等協調者' 'confirmation screen' 'with this duty as its prompt' 'pop-up first' 'heartbeat'; do
  case "$D19" in *"$s"*) fail "職責 19 不能有：$s — $D19" ;; esac
done

# frontmatter 的 name 是 lead（/opsx-workflow:lead）
assert_eq "$(sed -n 2p "$F")" "name: lead" "frontmatter name"
# 職責 2：每個 repo 有建議的 decision 由 opsx coordinate 照建議答、註「協調者代決」並列在 ④，其餘 gate 轉給使用者
# （specs/opsx-lead「職責 2 寫明所有 repo 照建議答」「職責 2 不再限定 repo、不再有範圍判斷例外」）
D2="$(grep -E '^2\. ' "$F")"; [ -n "$D2" ] || fail "缺職責 2"
for k in 'every repo' '協調者代決' 'decision' '照建議' 'ponytail' '④' 'approval' 'Every other gate is the user'"'"'s' \
  'not one that needs your hands, a merge, has no recommendation, is a stuck gate or carries `needs: run`' '①' \
  'deploys, changes CI, touches secrets, spends money or speaks outside the team'; do
  case "$D2" in *"$k"*) ;; *) fail "職責 2 缺 [$k]" ;; esac
done
case "$D2" in *"Every gate is the user's"*) fail "職責 2 不該再寫每個 gate 都是使用者的" ;; esac
for k in 'In other repos, a gate that asks whether to open another card' 'every gate in other repos' '協調者判定：範圍內' 'In the opsx-workflow repo'; do
  case "$D2" in *"$k"*) fail "職責 2 不該再有 [$k]" ;; esac
done
# ④ 的資料來源是 decisions.tsv
for k in 'decisions.tsv' 'whose who column is 協調者' 'sends you no event'; do
  case "$D2" in *"$k"*) ;; *) fail "職責 2 缺 [$k]" ;; esac
done
case "$D2" in *"lists what it answered in block ④"*) fail "職責 2 不能寫成 opsx coordinate 自己列 ④" ;; esac

# 職責 17 與報告 ②：每支可合併 MR 附邏輯表連結與代決清單，不分 repo；其他 repo 照舊貼邏輯圖
# （specs/opsx-lead「報告 ② 有連結與代決清單」「opsx-workflow 的 MR 不再只有一行」）
D17="$(duty 17)"; [ -n "$D17" ] || fail "缺職責 17"
R2="$(awk '/^### ② /{f=1;next} f&&/^### /{exit} f' "$F")"; [ -n "$R2" ] || fail "找不到報告 ②"
for k in 'file:///' '代決' 'opsx-workflow'; do
  case "$D17" in *"$k"*) ;; *) fail "職責 17 缺 [$k]" ;; esac
done
case "$D17" in *'logic graph pasted inline'*) ;; *) fail "職責 17 要保留 logic graph pasted inline" ;; esac
case "$D17" in *'one line saying it is ready is enough'*) fail "職責 17 不該再說 opsx-workflow 一行即可" ;; esac
for k in 'file:///' '代決：' '代決：無'; do
  case "$R2" in *"$k"*) ;; *) fail "報告 ② 缺 [$k]" ;; esac
done
echo ok
