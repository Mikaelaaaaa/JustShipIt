#!/usr/bin/env bash
# SessionStart：herdr 的名字跟著 pane，協調者換 pane（resume、換帳號、herdr 還原）名字就掉了。
# 協調者的 Claude session id 由 coordinate 每輪與 opsx lead 寫進 $OPSX_STATE_DIR/coordinator.json，這裡只讀：
# 對得上就把 opsx-coordinator 掛回自己的 pane。名字在另一個還有 agent 在跑的 pane 上時不搶，只說出來。
# 任何失敗都以 0 結束，不擋 session 啟動。specs/opsx-lead/spec.md。
source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"
# shellcheck source=/dev/null
source "$OPSX_ROOT/bin/lib/common.sh"

pane="${HERDR_PANE_ID:-}"
[ -n "$pane" ] || exit 0
f="$OPSX_STATE_DIR/coordinator.json"
[ -f "$f" ] || exit 0
if ! known="$(jq -er '.session_id' "$f" 2>/dev/null)"; then
  ctx SessionStart "opsx：$f 讀不懂（沒有 session_id），協調者的名字不會自動掛回。刪掉它，coordinate 下一輪會重記"
  exit 0
fi
[ "$known" = "$(jqr '.session_id')" ] || exit 0

if got="$(runtime_get --agent "$COORDINATOR_AGENT" 2>&1)"; then
  at="$(printf '%s' "$got" | jq -r '.result.agent.pane_id // empty' 2>/dev/null)" || at=""
  status="$(printf '%s' "$got" | jq -r '.result.agent.agent_status // empty' 2>/dev/null)" || status=""
  [ "$at" = "$pane" ] && exit 0
  if [ -z "$at" ]; then
    ctx SessionStart "opsx：這個 session 是協調者，但查不到 $COORDINATOR_AGENT 掛在哪個 pane（herdr 沒給 pane id），名字沒有掛回這個 pane，卡片的事件可能送不到協調者"
    exit 0
  fi
  # 跟 coordinate 的 LIVE_AGENT 同一組：其他狀態代表那個 pane 已經沒有 agent（例如剛 /exit 只剩 shell）
  case "$status" in
    working|idle|blocked|done)
      ctx SessionStart "opsx：這個 session 是協調者，但 $COORDINATOR_AGENT 這個名字掛在另一個 pane ${at}（agent_status ${status}），沒有搶過來。兩個協調者同時在跑，請使用者決定留哪個：留這個就先關掉 ${at} 再重開這個 session；事件現在送往 ${at}"
      exit 0 ;;
  esac
else
  case "$got" in
    *agent_not_found*) ;;
    *) ctx SessionStart "opsx：查不到 $COORDINATOR_AGENT 在哪（herdr：$(printf '%s' "$got" | head -c 200 | tr '\n' ' ')），名字沒有掛回這個 pane，卡片的事件會送不到協調者"; exit 0 ;;
  esac
fi
if ! out="$(herdr agent rename "$pane" "$COORDINATOR_AGENT" 2>&1)"; then
  ctx SessionStart "opsx：這個 session 是協調者，但把 pane $pane 改名成 $COORDINATOR_AGENT 失敗（herdr：$(printf '%s' "$out" | head -c 200 | tr '\n' ' ')）。卡片的事件會送不到協調者；把這段錯誤告訴使用者，或用 opsx lead 重開協調者"
fi
exit 0
