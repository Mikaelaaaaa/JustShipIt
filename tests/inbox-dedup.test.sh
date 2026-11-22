#!/usr/bin/env bash
# 判重複的記號：opsx dedup 蓋記號與列候選、opsx collect 帶出 dedup_checked。
# 驗收：openspec/changes/inbox-autofill/subs/autofill-coordinate/specs/inbox-dedup-stamp/spec.md
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
use_fakes date
export OPSX_TEST_NOW="2026-11-22 10:00"
ROOT="$FX/code"; mkdir -p "$ROOT"
cd "$ROOT"
A="$(mk_opsx_repo a)"; mv "$A" "$ROOT/a"; A="$(cd "$ROOT/a" && pwd -P)"
CH="$A/openspec/changes"
STAMP='dedup_checked: 2026-11-22T10:00:[0-9][0-9]+08:00'   # 假 date 只固定到分鐘

# card <slug> <frontmatter 多行，每行結尾 \n> [一句話]：收件匣卡，只有 inbox.md
card() {
  rm -rf "${CH:?}/$1"; mkdir -p "$CH/$1"
  printf -- "---\n$2---\n\n## 一句話\n\n%s\n" "${3:-$1}" > "$CH/$1/inbox.md"
}
P1='type: bug\nsource: me\nfound: 2026-11-20\npriority: P1\npriority_reason: 測試\n'

# ========== 1.1 collect 帶出 dedup_checked ==========
card c-stamped "${P1}dedup_checked: 2026-11-22T10:00:00+08:00\n"
card c-none "$P1"
card c-empty "${P1}dedup_checked:\n"
J="$(opsx collect --root "$ROOT")"; assert_eq "$?" 0 "collect rc: $J"
val() { printf '%s' "$J" | jq -r --arg s "$1" '.cards[] | select(.slug == $s) | .dedup_checked'; }
assert_eq "$(val c-stamped)" "2026-11-22T10:00:00+08:00" "有記號的卡帶原字串"
assert_eq "$(val c-none)" "null" "沒有 dedup_checked 是 null"
assert_eq "$(val c-empty)" "null" "dedup_checked 空值是 null"
rm -rf "${CH:?}/c-stamped" "$CH/c-none" "$CH/c-empty"

# ========== 1.2 opsx dedup 蓋記號 ==========
# --- 沒有記號的卡：加一行，其餘行不變 ---
card me-20261122-0900 "$P1"
before="$(cat "$CH/me-20261122-0900/inbox.md")"
out="$(opsx dedup me-20261122-0900 --repo "$A" 2>&1)"; assert_eq "$?" 0 "dedup: $out"
assert_eq "$(grep -c '^dedup_checked:' "$CH/me-20261122-0900/inbox.md")" 1 "只有一行記號"
assert_grep "^$STAMP\$" "$CH/me-20261122-0900/inbox.md"
assert_eq "$(grep -v '^dedup_checked:' "$CH/me-20261122-0900/inbox.md")" "$before" "其餘行不變"

# --- 已有記號：換成新時間，不留兩行 ---
card me-20261122-0901 "${P1}dedup_checked: 2026-11-20T10:00:00+08:00\n"
out="$(opsx dedup me-20261122-0901 --repo "$A" 2>&1)"; assert_eq "$?" 0 "re-dedup: $out"
assert_eq "$(grep -c '^dedup_checked:' "$CH/me-20261122-0901/inbox.md")" 1 "重蓋不留兩行"
assert_grep "^$STAMP\$" "$CH/me-20261122-0901/inbox.md"

# --- 一次蓋多張 ---
card m1 "$P1"; card m2 "$P1"
out="$(opsx dedup m1 m2 --repo "$A" 2>&1)"; assert_eq "$?" 0 "多張: $out"
assert_grep "^$STAMP\$" "$CH/m1/inbox.md"; assert_grep "^$STAMP\$" "$CH/m2/inbox.md"

# --- 不合法的卡：退出非 0、點名、一張都不寫 ---
card started "$P1"; printf -- '- [ ] 1.1 x\n' > "$CH/started/tasks.md"
mkdir -p "$CH/bare"; printf '## 一句話\n\n沒有 frontmatter\n' > "$CH/bare/inbox.md"
for bad in ghost started bare; do
  card a "$P1"
  out="$(opsx dedup a "$bad" --repo "$A" 2>&1)"; rc=$?
  [ "$rc" -ne 0 ] || fail "$bad 要退出非 0：$out"
  printf '%s' "$out" | grep -q -- "$bad" || fail "stderr 要點名 ${bad}：$out"
  assert_not_grep '^dedup_checked:' "$CH/a/inbox.md"
done
assert_not_grep '^dedup_checked:' "$CH/started/inbox.md"
rm -rf "${CH:?}/started" "$CH/bare" "$CH/a" "$CH/m1" "$CH/m2" "$CH/me-20261122-0900" "$CH/me-20261122-0901"

# --- 沒給卡或沒給 --repo：用法錯誤 ---
assert_rc 2 opsx dedup --repo "$A"
assert_rc 2 opsx dedup x

# ========== 1.3 opsx dedup --candidates ==========
mkdir -p "$A/bin/lib"; : > "$A/bin/lib/x.py"; : > "$A/bin/lib/y.py"
card a "$P1" "改 bin/lib/x.py:10 的判斷"
card b "$P1" "bin/lib/x.py 也有同樣問題"
card c "$P1" "bin/lib/y.py 要拆"
out="$(opsx dedup --candidates --repo "$A" 2>"$FX/cand.err")"; assert_eq "$?" 0 "candidates: $(cat "$FX/cand.err")"
assert_eq "$out" "$(printf 'a\tb\nb\ta\nc\t')" "三行候選"

# --- 有記號與 P2 的卡不列 ---
card a "${P1}dedup_checked: 2026-11-22T10:00:00+08:00\n" "改 bin/lib/x.py"
card b 'type: bug\nsource: me\nfound: 2026-11-20\npriority: P2\npriority_reason: 測試\n' "bin/lib/x.py"
rm -rf "${CH:?}/c"
out="$(opsx dedup --candidates --repo "$A" 2>"$FX/cand.err")"; assert_eq "$?" 0 "candidates: $(cat "$FX/cand.err")"
assert_eq "$out" "" "有記號與 P2 的卡不列"

# --- 不在收件匣的卡（有 tasks.md）不列 ---
card d "$P1" "bin/lib/y.py"; printf -- '- [ ] 1.1 x\n' > "$CH/d/tasks.md"
out="$(opsx dedup --candidates --repo "$A" 2>"$FX/cand.err")"; assert_eq "$?" 0 "candidates: $(cat "$FX/cand.err")"
assert_eq "$out" "" "不在收件匣的卡不列"

# --- 等級算不出來的卡不列，stderr 一行點名卡與原因，退出 0 ---
card bad 'type: bug\nsource: me\nfound: 2026-11-20\npriority: P9\npriority_reason: 測試\n' "bin/lib/y.py"
out="$(opsx dedup --candidates --repo "$A" 2>"$FX/cand.err")"; assert_eq "$?" 0 "candidates: $(cat "$FX/cand.err")"
assert_eq "$out" "" "等級算不出來的卡不列"
assert_eq "$(grep -c 'bad.*P9' "$FX/cand.err" || true)" 1 "stderr 一行含卡名與原因：$(cat "$FX/cand.err")"
echo "inbox-dedup ok"
