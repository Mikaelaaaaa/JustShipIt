#!/usr/bin/env bash
# UserPromptSubmit（協調者的 --settings 掛上）：skills/lead/SKILL.md 跟上次記下的內容不同時，注入一行新版的絕對路徑。
# 路徑從腳本位置算，不靠 CLAUDE_PLUGIN_ROOT：--settings 掛的 hook 不是 plugin hook，不一定有這個變數。OPSX_LEAD_SKILL 只給測試換路徑。
# 只注入路徑、寫成事實不寫成命令，模型才不會把它當 prompt injection 擋掉。
# shellcheck source=/dev/null
source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"

skill="${OPSX_LEAD_SKILL:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../skills/lead" && pwd)/SKILL.md}"
rec="$OPSX_STATE_DIR/lead-skill.cksum"

sum="$(cksum < "$skill")"
[ -f "$rec" ] && [ "$(cat "$rec")" = "$sum" ] && exit 0

mkdir -p "$OPSX_STATE_DIR"
tmp="$(mktemp "$rec.XXXXXX")"
printf '%s\n' "$sum" > "$tmp"
mv "$tmp" "$rec"
ctx UserPromptSubmit "skills/lead/SKILL.md 已改過，新版在 $skill"
