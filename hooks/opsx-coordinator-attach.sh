#!/usr/bin/env bash
# SessionStart：herdr 的名字跟著 pane，協調者換 pane（resume、換帳號、herdr 還原）名字就掉了。
# 用 Claude session id 認協調者（$OPSX_STATE_DIR/coordinator.json），每次啟動把 opsx-coordinator 掛回自己的 pane。
# 名字被別的活 pane 佔著時不搶，只說出來。任何失敗都以 0 結束，不擋 session 啟動。specs/opsx-lead/spec.md。
source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"
# shellcheck source=/dev/null
source "$OPSX_ROOT/bin/lib/common.sh"

pane="${HERDR_PANE_ID:-}"
[ -n "$pane" ] || exit 0
sid="$(jqr '.session_id')"
[ -n "$sid" ] || exit 0
src="$(jqr '.source')"
f="$OPSX_STATE_DIR/coordinator.json"

record() { # 寫不下來只少一次自動掛名，不能讓 hook 以非 0 結束
  jq -n --arg s "$sid" --arg p "$pane" --arg at "$(now_iso)" '{session_id:$s, pane:$p, at:$at}' | opsx_replace "$f" || true
}

known=""
if [ -f "$f" ]; then
  if ! known="$(jq -er '.session_id' "$f" 2>/dev/null)"; then
    ctx SessionStart "opsx：$f 讀不懂（沒有 session_id），協調者的名字不會自動掛回。刪掉它後用 opsx lead 重開協調者"
    exit 0
  fi
fi

if [ "$known" != "$sid" ]; then
  # 只有 opsx lead 剛起的協調者會是 startup 且名字已在自己的 pane；其他 session 不必多查一次 herdr
  [ "$src" = startup ] || exit 0
  got="$(runtime_get --agent "$COORDINATOR_AGENT" 2>/dev/null)" || exit 0
  [ "$(printf '%s' "$got" | jq -r '.result.agent.pane_id // empty' 2>/dev/null)" = "$pane" ] || exit 0
  record
  exit 0
fi

if got="$(runtime_get --agent "$COORDINATOR_AGENT" 2>&1)"; then
  at="$(printf '%s' "$got" | jq -r '.result.agent.pane_id // empty' 2>/dev/null)"
  [ "$at" = "$pane" ] && exit 0
  ctx SessionStart "opsx：這個 session 是協調者，但 $COORDINATOR_AGENT 這個名字掛在另一個 pane ${at:-（herdr 沒給 pane id）}，沒有搶過來。兩個協調者同時在跑，請使用者決定留哪個：留這個就先關掉 ${at:-那個} 再重開這個 session；事件現在送往 ${at:-那個 pane}"
  exit 0
fi
case "$got" in
  *agent_not_found*) ;;
  *) ctx SessionStart "opsx：查不到 $COORDINATOR_AGENT 在哪（herdr：$(printf '%s' "$got" | head -c 200 | tr '\n' ' ')），名字沒有掛回這個 pane，卡片的事件會送不到協調者"; exit 0 ;;
esac
if out="$(herdr agent rename "$pane" "$COORDINATOR_AGENT" 2>&1)"; then
  record
  exit 0
fi
ctx SessionStart "opsx：這個 session 是協調者，但把 pane $pane 改名成 $COORDINATOR_AGENT 失敗（herdr：$(printf '%s' "$out" | head -c 200 | tr '\n' ' ')）。卡片的事件會送不到協調者；把這段錯誤告訴使用者，或用 opsx lead 重開協調者"
exit 0
