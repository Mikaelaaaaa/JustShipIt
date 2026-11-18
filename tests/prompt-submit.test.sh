#!/usr/bin/env bash
# 送給卡的話送出後讀輸入框：框裡還是剛送的那句才補一次 Enter；補了仍在只警告；送話失敗不讀畫面。
# 驗收：openspec/changes/me-20261118-1102/specs/prompt-submit-check/spec.md「送給卡的話送出後確認離開輸入框」
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
use_fakes herdr
export OPSX_FAKE_LOG="$FX/fake.log"; : > "$OPSX_FAKE_LOG"
R="$(mk_repo r)"; C="$R/openspec/changes/c1"; mk_change "$R" c1
DISP="$OPSX_STATE_DIR/dispatch.json"
SAMPLE="$OPSX_ROOT/tests/fakes/herdr-samples/agent-read.txt"
screen() { # <檔名> <輸入框那一行換成什麼>：從實跑樣本做出畫面，只換輸入框
  sed "s/^❯\$/$2/" "$SAMPLE" > "$FX/$1"; printf '%s' "$FX/$1"
}
reset() {
  : > "$OPSX_FAKE_LOG"; rm -f "$FX/once"; unset OPSX_TEST_AGENT_READ OPSX_TEST_PROMPT_ERR
  printf '## g1\ntype: decision\nstatus: open\n問題: 怎麼做\n選項: 照建議 (Recommended) | 不要\n建議: 照建議\n' > "$C/gates.md"
  printf '{"r/c1":{"mode":"autopilot","agent":"claude","pane":"w5:pAE"}}' > "$DISP"
}
enters() { grep -c '^pane send-keys w5:pAE enter$' "$OPSX_FAKE_LOG" || true; }
reads() { grep -c '^agent read' "$OPSX_FAKE_LOG" || true; }
last_prompt() { jq -r '."r/c1".last_prompt // "（沒有）"' "$DISP"; }
answer() { ( cd "$R" && opsx answer c1 --gate g1 照建議 ) > "$FX/out" 2> "$FX/err"; }
export OPSX_TEST_AGENT_READ_ONCE="$FX/once"
# row <送出後第一次讀到的畫面檔> <send-keys 次數> <說明>：之後的讀都是空輸入框（補了 Enter 就送出去了）
row() {
  reset; cp "$1" "$FX/once"
  answer || fail "$3：answer rc：$(cat "$FX/err")"
  assert_eq "$(enters)" "$2" "$3：$(cat "$OPSX_FAKE_LOG")"
  assert_eq "$(last_prompt)" 照建議 "$3 的 last_prompt"
  assert_grep '^agent read w5:pAE --source visible --format ansi$' "$OPSX_FAKE_LOG"
}

# --- 送出後輸入框的字決定補不補 Enter：一般場景 ---
row "$(screen typed '❯ 照建議')" 1 "框裡是剛送的那句"
assert_eq "$(reads)" 2 "補了 Enter 再讀一次"
assert_eq "$(cat "$FX/err")" "" "補了就送出去，不警告"
row "$SAMPLE" 0 "框是空的"
assert_eq "$(reads)" 1 "沒補 Enter 不再讀"
row "$(screen other '❯ 我自己打的字')" 0 "框裡是別的字"

# --- 邊界場景 ---
printf 'Do you want to proceed?\n  1. Yes\n  2. No\n' > "$FX/dialog"
row "$FX/dialog" 0 "畫面上沒有輸入框（對話框）"
awk '/^❯$/ && !d { print "❯ 照建"; print "  議"; d=1; next } { print }' "$SAMPLE" > "$FX/wrapped"
row "$FX/wrapped" 1 "長句折行，去空白後相同"
printf '────\n\e[38;2;138;144;149m❯ \e[0m\e[2mPress up to edit queued messages\e[22m\n────\n' > "$FX/dim"
row "$FX/dim" 0 "只有 dim 的提示字"
row "$(screen more '❯ 照建議 再加一句')" 0 "前面相同但多了字"

# --- 補了 Enter 仍留在框裡只警告 ---
reset; export OPSX_TEST_AGENT_READ="$(screen typed '❯ 照建議')"
answer; assert_eq "$?" 0 "仍留在框裡，送話本身仍算成功：$(cat "$FX/err")"
assert_eq "$(enters)" 1 "只補一次 Enter：$(cat "$OPSX_FAKE_LOG")"
assert_eq "$(grep -c 'w5:pAE' "$FX/err")" 1 "stderr 一行含 pane id：$(cat "$FX/err")"

# --- 送話失敗不讀畫面 ---
reset; printf 'agent_not_found\n' > "$FX/perr"; export OPSX_TEST_PROMPT_ERR="$FX/perr"
answer
assert_eq "$(reads)" 0 "送話失敗不讀：$(cat "$OPSX_FAKE_LOG")"
assert_eq "$(enters)" 0 "送話失敗不補 Enter"
assert_eq "$(last_prompt)" "（沒有）" "送話失敗不記 last_prompt"

# --- 送給不是卡的 agent（--agent）、沒有 pane 的卡：不讀畫面 ---
reset
source "$OPSX_ROOT/bin/lib/common.sh"
source "$OPSX_ROOT/bin/lib/python.sh"
opsx_python_load || fail "$OPSX_PY_ERR"
runtime_prompt --agent someone hi nowait >/dev/null || fail "--agent 傳話 rc"
runtime_prompt r/fresh hi nowait >/dev/null || fail "沒有條目的卡傳話 rc"
assert_eq "$(reads)" 0 "--agent 與沒有 pane 的卡不讀畫面：$(cat "$OPSX_FAKE_LOG")"

# --- drive 的 agent_prompt_stalled：herdr 收下了但 agent 沒動，同樣檢查 ---
source "$OPSX_ROOT/bin/lib/drive.sh"
reset; printf 'agent_prompt_stalled\n' > "$FX/perr"; export OPSX_TEST_PROMPT_ERR="$FX/perr"
cp "$(screen stalled '❯ \/opsx-workflow:apply c1')" "$FX/once"
herdr_step c1 runtime_prompt r/c1 "/opsx-workflow:apply c1" wait > "$FX/out" 2>&1 || fail "herdr_step rc：$(cat "$FX/out")"
assert_eq "$HERDR_STEP_OK" 1 "stalled 算送過"
assert_eq "$(enters)" 1 "stalled 後框裡是剛送的指令要補 Enter：$(cat "$OPSX_FAKE_LOG")"
assert_eq "$(last_prompt)" "/opsx-workflow:apply c1" "stalled 也記 last_prompt"
# wait 模式送成功不檢查：herdr 等 agent 做完才回
reset; cp "$(screen waited '❯ \/opsx-workflow:apply c1')" "$FX/once"
herdr_step c1 runtime_prompt r/c1 "/opsx-workflow:apply c1" wait > "$FX/out" 2>&1 || fail "herdr_step rc：$(cat "$FX/out")"
assert_eq "$(reads)" 0 "wait 模式送成功不讀畫面：$(cat "$OPSX_FAKE_LOG")"
echo ok
