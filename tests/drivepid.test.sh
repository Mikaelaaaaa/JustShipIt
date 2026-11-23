#!/usr/bin/env bash
# bin/lib/drivepid.py：ps 本身跑不起來（沙盒裡 exec 被拒、或找不到 ps）時回 unknown，不丟例外。
# 整輪 coordinate 的 PATH 後面有真的 /bin/ps，沙盒外會被找到，所以這裡直接呼叫模組、PATH 只放指定的目錄。
# 驗收：openspec/changes/agent-20261123-0145/specs/opsx-coordinate/spec.md「讀不到命令列不重派」
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
PY="$(cat "$OPSX_STATE_DIR/python")"
mkdir -p "$FX/noexec" "$FX/empty"; : > "$FX/noexec/ps"; chmod -x "$FX/noexec/ps"
state() { # <PATH> <pid> → 印 狀態<TAB>命令列
  PATH="$1" "$PY" -I -c 'import sys; sys.path.insert(0, sys.argv[1]); import drivepid; print("%s\t%s" % drivepid.state(int(sys.argv[2]), "u"))' "$OPSX_ROOT/bin/lib" "$2"
}
sleep 30 & live=$!

out="$(state "$FX/noexec" "$live" 2>&1)" || fail "ps exec 失敗不該丟例外: $out"
assert_eq "$out" "$(printf 'unknown\t')" "ps 不可執行"

out="$(state "$FX/empty" "$live" 2>&1)" || fail "找不到 ps 不該丟例外: $out"
assert_eq "$out" "$(printf 'unknown\t')" "找不到 ps"

sleep 0 & dead=$!; wait "$dead"
assert_eq "$(state "$FX/empty" "$dead")" "$(printf 'gone\t')" "pid 不在時不用讀命令列"

kill "$live"
