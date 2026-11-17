#!/usr/bin/env bash
# shell-var-braces：bash 3.2 在 UTF-8 locale 下會把緊接在 $name 後面的中文或全形標點的首位元組吃進變數名，
# set -u 下就變成 unbound variable，蓋掉原本要印的訊息。這類寫法要加大括號：${name}（。
# 驗收：specs/shell-var-braces/spec.md
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

# 略過整行註解與行尾註解（空白 # 空白 之後）；C locale 讓 grep 逐位元組比，[^[:print:][:cntrl:]] 就是 0x80 以上的位元組
code_hits() { # <file>
  LC_ALL=C sed -E -e 's/^[[:space:]]*#.*$//' -e 's/[[:space:]]+#[[:space:]].*$//' "$1" \
    | LC_ALL=C grep -nE '\$[A-Za-z_][A-Za-z0-9_]*[^[:print:][:cntrl:]]' || true
}

T="$FX/scan"; mkdir -p "$T"
n=0
# 每一列是 spec Examples 表的一列
for line in \
  'die "drop: 沒有捨棄 $repo/$slug（上面是原因）"' \
  'fail "缺 $k：$relay_step"' \
  'fail "split_into「$v」算沒拆"' \
  'fail "現在在 $n_duties）"' \
  'x="$v（" # 行尾註解'; do
  n=$((n + 1)); printf '%s\n' "$line" > "$T/bad$n.sh"
  [ -n "$(code_hits "$T/bad$n.sh")" ] || fail "掃描器抓不到：$line"
done
for line in \
  'die "drop: 沒有捨棄 $repo/${slug}（上面是原因）"' \
  'die "drop: $repo/$slug 還有併入的項目"' \
  'fail "rc $rc)"' \
  'echo "$1（"'; do
  n=$((n + 1)); printf '%s\n' "$line" > "$T/ok$n.sh"
  [ -z "$(code_hits "$T/ok$n.sh")" ] || fail "掃描器誤報：$line"
done
printf '%s\n' '# 看 $OPSX_FAKE_LOG（預設空）' 'x=1 # $HOME、上層' > "$T/comment.sh"
[ -z "$(code_hits "$T/comment.sh")" ] || fail "掃描器誤報註解：$(code_hits "$T/comment.sh")"

# 真實檔案；這支自己的 fixture 字串就是違規範例，不掃
bad=""
for f in "$OPSX_ROOT"/bin/opsx "$OPSX_ROOT"/bin/lib/*.sh "$OPSX_ROOT"/hooks/*.sh "$OPSX_ROOT"/tests/*.sh "$OPSX_ROOT"/tests/fakes/*; do
  [ -f "$f" ] || continue
  [ "$f" = "$OPSX_ROOT/tests/shell-var-braces.test.sh" ] && continue
  h="$(code_hits "$f")"; [ -z "$h" ] || bad+="${f#"$OPSX_ROOT"/}:
$h
"
done
[ -z "$bad" ] || fail "緊接非 ASCII 字元的變數要加大括號（\${name}）：
$bad"
