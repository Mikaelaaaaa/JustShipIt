#!/usr/bin/env bash
# hooks/lead-skill-reload.sh：協調者每句 prompt 比對 skills/lead/SKILL.md，改過才注入一行路徑。
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
H="$OPSX_ROOT/hooks/lead-skill-reload.sh"
REC="$OPSX_STATE_DIR/lead-skill.cksum"
IN='{"hook_event_name":"UserPromptSubmit","prompt":"進度","cwd":"/"}'

run_hook() { printf '%s' "$IN" | bash "$H"; }
context() { printf '%s' "$1" | jq -r '.hookSpecificOutput.additionalContext'; }

mkdir -p "$FX/plugin/skills/lead"
export OPSX_LEAD_SKILL="$FX/plugin/skills/lead/SKILL.md"
printf '# Lead skill v1\n\n協調者的職責。\n' > "$OPSX_LEAD_SKILL"
want="skills/lead/SKILL.md 已改過，新版在 $OPSX_LEAD_SKILL"

# 沒有紀錄：注入一行，記下現在的內容
assert_no_file "$REC"
out="$(run_hook)" || fail "沒有紀錄：hook 失敗"
assert_eq "$(printf '%s' "$out" | jq -r '.hookSpecificOutput.hookEventName')" UserPromptSubmit "沒有紀錄：事件名"
ctx1="$(context "$out")"
assert_eq "$ctx1" "$want" "沒有紀錄：注入的句子"
assert_file "$REC"
assert_eq "$(cat "$REC")" "$(cksum < "$OPSX_LEAD_SKILL")" "沒有紀錄：紀錄是現在內容的 cksum"

# 注入的只有路徑：一行，不含本文的第一個標題行
assert_eq "$(printf '%s\n' "$ctx1" | wc -l | tr -d ' ')" 1 "只注入一行"
case "$ctx1" in *"Lead skill v1"*) fail "注入了 SKILL.md 本文：$ctx1" ;; esac

# 現在的內容（連續第二句，中間沒改）：什麼都不輸出，紀錄不變
out="$(run_hook)" || fail "內容相同：hook 失敗"
assert_eq "$out" "" "內容相同：不輸出"
assert_eq "$(cat "$REC")" "$(cksum < "$OPSX_LEAD_SKILL")" "內容相同：紀錄不變"

# 上一版的內容：注入一行，紀錄更新成新內容
printf '# Lead skill v2\n\n新的規則。\n' > "$OPSX_LEAD_SKILL"
out="$(run_hook)" || fail "上一版：hook 失敗"
assert_eq "$(context "$out")" "$want" "上一版：注入的句子"
assert_eq "$(cat "$REC")" "$(cksum < "$OPSX_LEAD_SKILL")" "上一版：紀錄更新"

# 改過之後連送兩句：只有第一句帶到
printf '# Lead skill v3\n' > "$OPSX_LEAD_SKILL"
first="$(run_hook)"; second="$(run_hook)"
assert_eq "$(context "$first")" "$want" "連續兩句：第一句注入"
assert_eq "$second" "" "連續兩句：第二句不輸出"

# 暫存檔不留在 state 目錄
assert_eq "$(find "$OPSX_STATE_DIR" -name 'lead-skill.cksum.*' | wc -l | tr -d ' ')" 0 "暫存檔留下來了"

# 沒設 OPSX_LEAD_SKILL：路徑是腳本旁的 skills/lead/SKILL.md，轉成絕對路徑
unset OPSX_LEAD_SKILL
rm -f "$REC"
out="$(run_hook)" || fail "預設路徑：hook 失敗"
real="$(cd "$OPSX_ROOT/skills/lead" && pwd)/SKILL.md"
assert_eq "$(context "$out")" "skills/lead/SKILL.md 已改過，新版在 $real" "預設路徑"

echo ok
