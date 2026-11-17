#!/usr/bin/env bash
# opsx collect 的 stopped 欄位：讀 Stop hook 寫的停住紀錄 <state>/stop-said/<repo>-<slug>（第一行原因、第二行 ISO 時間）。
# 驗收：specs/board-stop-reason/spec.md「collect 帶出每張卡最後停住的原因與時間」
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
use_fakes herdr glab gh
export OPSX_FAKE_LOG="$FX/fake.log"; : > "$OPSX_FAKE_LOG"
export OPSX_MR_CACHE_TTL=0

st() { printf '%s' "$1" | python3 -I -c 'import json,sys;d=json.load(sys.stdin)
c=[c for c in d["cards"] if c["repo"]=="rs" and c["slug"]=="eval-core"][0]
print(json.dumps(c["stopped"],ensure_ascii=False,sort_keys=True) if "stopped" in c else "MISSING")'; }

RS="$FX/code-stop"; mkdir -p "$RS/rs/.git"
D="$RS/rs/openspec/changes/eval-core"; mkdir -p "$D"
printf 'schema: opsx\ncreated: 2026-11-05\nkind: dev\n' > "$D/.openspec.yaml"; printf '## 一句話\n\neval-core\n' > "$D/inbox.md"
REC="$OPSX_STATE_DIR/stop-said/rs-eval-core"; mkdir -p "$OPSX_STATE_DIR/stop-said"

# 反例：沒有停住紀錄，key 在、值 null
J="$(opsx collect --root "$RS")"; assert_eq "$?" 0 "collect rc（沒有紀錄）: $J"
assert_eq "$(st "$J")" 'null' "沒有停住紀錄是 null"

# 正例：兩行都有，帶出原因與時間；推送去重的 .sent 檔不影響
printf '等 reviewer（review 站）\n2026-11-16T10:05:00+08:00\n' > "$REC"
printf '[eval-core] 停住：連續 3 次沒接 apply，已開「卡在接」gate' > "$REC.sent"
J="$(opsx collect --root "$RS")"; assert_eq "$?" 0 "collect rc（有紀錄）: $J"
assert_eq "$(st "$J")" '{"at": "2026-11-16T10:05:00+08:00", "reason": "等 reviewer（review 站）"}' "有停住紀錄帶出原因與時間"

# 反例：只有原因、沒有時間（舊格式）
printf '等 reviewer（review 站）' > "$REC"
J="$(opsx collect --root "$RS")"; assert_eq "$?" 0 "collect rc（只有一行）: $J"
assert_eq "$(st "$J")" 'null' "紀錄只有一行是 null"

# 反例：第二行不是 ISO 時間（看板拿它做 fromisoformat，壞紀錄不能讓 TUI 掛掉）
printf '等 reviewer（review 站）\nnot-a-time\n' > "$REC"
J="$(opsx collect --root "$RS")"; assert_eq "$?" 0 "collect rc（時間壞掉）: $J"
assert_eq "$(st "$J")" 'null' "第二行不是時間是 null"

# 反例：讀不了（路徑是目錄）
rm -f "$REC"; mkdir -p "$REC"
J="$(opsx collect --root "$RS")"; assert_eq "$?" 0 "collect rc（讀不了）: $J"
assert_eq "$(st "$J")" 'null' "紀錄讀不了是 null"

echo "collect-stopped ok"
