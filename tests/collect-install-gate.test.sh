#!/usr/bin/env bash
# 帶 blocks-from: apply 的 gate（dispatch 的 install-deps）：卡還沒有 tasks.md 時看板不當它在等人，有 tasks.md 後照一般 gate。
# 驗收：openspec/changes/me-20261116-1650-4/specs/opsx-dispatch/spec.md「install 失敗照樣派、開 needs: run gate」
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
use_fakes herdr glab gh
export OPSX_FAKE_LOG="$FX/fake.log"; : > "$OPSX_FAKE_LOG"
mkdir -p "$OPSX_STATE_DIR"

q() { printf '%s' "$1" | python3 -I -c 'import json,sys;d=json.load(sys.stdin)
for k in sys.argv[1].split("."):
    d=d[int(k)] if isinstance(d,list) else d[k]
print(json.dumps(d,ensure_ascii=False,sort_keys=True) if isinstance(d,(dict,list,bool)) or d is None else d)' "$2"; }
card() { printf '%s' "$1" | python3 -I -c 'import json,sys;d=json.load(sys.stdin)
c=[c for c in d["cards"] if c["repo"]==sys.argv[1] and c["slug"]==sys.argv[2]]
print(json.dumps(c[0],ensure_ascii=False) if c else "null")' "$2" "$3"; }

ROOT="$FX/code"; mkdir -p "$ROOT/r/.git"
gcard() { # <slug> <gates.md 內容> <有沒有 tasks.md：yes|no>
  local d="$ROOT/r/openspec/changes/$1"; mkdir -p "$d"
  printf 'schema: opsx\ncreated: 2026-11-10\nkind: dev\n' > "$d/.openspec.yaml"; printf '## 一句話\n\n%s\n' "$1" > "$d/inbox.md"
  [ "$3" = no ] || printf '## 1\n\n- [ ] 1.1 a\n' > "$d/tasks.md"
  printf '%b' "$2" > "$d/gates.md"
}
DEPS='## install-deps\ntype: decision\nstatus: open\nneeds: run\nblocks-from: apply\nopened_at: 2026-11-10T10:00:00+08:00\n問題: 裝依賴？\n'
gcard deps-apply "$DEPS" yes
gcard deps-early "$DEPS" no
gcard deps-next "$DEPS"'\n## g2\ntype: decision\nstatus: open\n問題: 選\n' no
J="$(opsx collect --root "$ROOT")"; assert_eq "$?" 0 "collect rc: $J"

C="$(card "$J" r deps-apply)"
assert_eq "$(q "$C" waiting.gate_id)" install-deps "有 tasks.md 時 install gate 照一般 gate 算"
assert_eq "$(q "$C" section)" 待處理

C="$(card "$J" r deps-early)"
assert_eq "$(q "$C" waiting)" null "沒有 tasks.md 時 install gate 不算等人"
[ "$(q "$C" section)" != 待處理 ] || fail "沒有 tasks.md 時不列進待處理：$C"
assert_eq "$(q "$C" open_gates.0.id)" install-deps "gate 清單照列"

C="$(card "$J" r deps-next)"
assert_eq "$(q "$C" waiting.gate_id)" g2 "跳過 install gate，後面的一般 gate 照算"
echo "collect-install-gate ok"
