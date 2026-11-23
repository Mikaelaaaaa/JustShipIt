#!/usr/bin/env bash
# opsx lead：在目前的 herdr workspace 開協調者 session（herdr 名 opsx-coordinator），第一句載入 /opsx-workflow:lead。
# specs/opsx-lead/spec.md。權限模式不帶，用使用者平常的模式：這個 session 能連 herdr socket，不再放寬。

# 印出協調者的啟動指紋兩行：args <參數的 cksum>、settings <設定檔的 cksum>。已在跑時拿它比對協調者是不是用現在這組起的
lead_fingerprint() { # <settings> <claude 參數...>
  local settings="$1" a s
  shift
  a="$(printf '%s' "$*" | cksum)" && s="$(cksum < "$settings")" && printf 'args %s\nsettings %s\n' "$a" "$s"
}

opsx_lead() {
  [ "$#" -le 1 ] || die "lead 只接受一個 repo 路徑，收到：$*"
  [ -n "${HERDR_ENV:-}" ] || die "lead: 不在 herdr pane 裡。先開 herdr，在 herdr pane 裡跑 opsx lead"
  [ -n "${HERDR_WORKSPACE_ID:-}" ] || die "lead: HERDR_ENV 有值但沒有 HERDR_WORKSPACE_ID，不知道要開在哪個 workspace"
  local dir="${1:-$PWD}" top settings="$OPSX_STATE_DIR/coordinator-settings.json" got where pane tab
  local fp="$OPSX_STATE_DIR/coordinator-launch.cksum" now changed
  [ -d "$dir" ] || die "lead: 不是目錄：$dir"
  top="$(cd "$dir" && pwd -P)"
  [ -f "$settings" ] || die "lead: 沒有 ${settings}。先在沙盒外（你的終端機）跑 opsx init --global"
  local -a args=(--settings "$settings" --add-dir "$OPSX_STATE_DIR")

  # agent get 的真輸出與錯誤碼沒有樣本，所以它只用來提早說「已在跑」：查不到、或讀不出位置就照常開，
  # 第二個協調者由 herdr 的名字唯一性擋（agent start 回 agent_name_taken）
  if got="$(runtime_get --agent "$COORDINATOR_AGENT" 2>/dev/null)" \
    && where="$(printf '%s' "$got" | jq -er 'first(.. | objects | select(has("pane_id") and has("tab_id") and has("workspace_id"))) | "workspace \(.workspace_id) · tab \(.tab_id) · pane \(.pane_id)"' 2>/dev/null)"; then
    say "lead: 協調者已在跑（${where}），不開第二個。herdr agent focus $COORDINATOR_AGENT 切過去"
    pane="${where##* pane }"
    if [ ! -f "$fp" ]; then
      say "lead: 沒有這個協調者的啟動記錄，不知道它用哪組參數和設定起的；關掉 pane ${pane} 再跑 opsx lead 才會用現在的參數和設定"
    elif now="$(lead_fingerprint "$settings" "${args[@]}")"; then
      changed=""
      grep -qxF "${now%%$'\n'*}" "$fp" || changed="啟動參數"
      grep -qxF "${now#*$'\n'}" "$fp" || changed="${changed:+$changed 和 }coordinator-settings.json"
      [ -z "$changed" ] || say "lead: 協調者可能是舊的：它起來之後${changed}改過；關掉 pane ${pane} 再跑 opsx lead 才會套用"
    fi
    return 0
  fi

  if ! runtime_open --agent "$COORDINATOR_AGENT" --kind claude --workspace-id "$HERDR_WORKSPACE_ID" --cwd "$top" --label "$COORDINATOR_AGENT" \
    -- "${args[@]}"; then
    say "lead: 協調者已在跑（${HERDR_TAKEN_AT}），剛開的 tab 已收掉，不開第二個。herdr agent focus $COORDINATOR_AGENT 切過去"
    return 0
  fi
  pane="$RUNTIME_PANE"; tab="$RUNTIME_TAB"
  # 協調者一起來就照這次的參數記指紋，下面送第一句失敗 die 也不會留著上一次的；記不下就刪掉，下次說沒有啟動記錄
  now="$(lead_fingerprint "$settings" "${args[@]}" 2>/dev/null)" && printf '%s\n' "$now" 2>/dev/null > "$fp" \
    || { rm -f "$fp" 2>/dev/null || :; warn "協調者的啟動指紋沒記下（${fp}），下次 opsx lead 會說沒有它的啟動記錄"; }
  runtime_prompt --agent "$COORDINATOR_AGENT" "/opsx-workflow:lead" nowait >/dev/null || die "lead: 協調者起來了但第一句送不進去。到 pane ${pane} 自己打 /opsx-workflow:lead（重跑 opsx lead 會說已在跑，不會補送）"
  # 記下協調者的 session id，SessionStart hook 憑它在換 pane 後把名字掛回；這裡記不到時 coordinate 下一輪會記
  got="$(runtime_get --agent "$COORDINATOR_AGENT")" && printf '%s' "$got" | "$OPSX_PY" -I "$OPSX_ROOT/bin/lib/coordq.py" remember "$OPSX_STATE_DIR" \
    || warn "協調者的 session id 這次沒記下，coordinate 下一輪會補記"
  runtime_focus --agent "$COORDINATOR_AGENT" >/dev/null || warn "焦點切不過去，協調者在 tab ${tab}（pane ${pane}）"
  say "lead: 協調者開在 tab ${tab}（pane ${pane}），cwd ${top}"
}
