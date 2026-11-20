#!/usr/bin/env bash
# 分區看全部 open gate：只等別張卡合進 main 的 gate 不算待處理。
# 驗收：openspec/changes/board-waits-on-pending/specs/board-collect/spec.md「只等別張卡的 gate 不算待處理」
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
gcard() { # <slug> <gates.md 內容>
  local d="$ROOT/r/openspec/changes/$1"; mkdir -p "$d"
  printf 'schema: opsx\ncreated: 2026-11-10\nkind: dev\n' > "$d/.openspec.yaml"; printf '## 一句話\n\n%s\n' "$1" > "$d/inbox.md"
  printf '## 1\n\n- [ ] 1.1 a\n' > "$d/tasks.md"
  printf '%b' "$2" > "$d/gates.md"
}
WAIT='## g1\ntype: decision\nstatus: open\nwaits-on: other\nopened_at: 2026-11-10T10:00:00+08:00\n問題: 等 other\n選項: 等 (Recommended) | 不等\n'
ASK='\n## g2\ntype: decision\nstatus: open\nopened_at: 2026-11-10T10:00:00+08:00\n問題: 選\n選項: a (Recommended) | b\n'
gcard only-wait "$WAIT"
gcard wait-then-ask "$WAIT$ASK"
gcard ghost-wait '## g1\ntype: decision\nstatus: open\nwaits-on: ghost\nopened_at: 2026-11-10T10:00:00+08:00\n問題: 等 ghost\n選項: 等 (Recommended) | 不等\n'
gcard plain-ask "$ASK"
gcard other-done '## g1\ntype: decision\nstatus: open\nwaits-on: merged-card\nopened_at: 2026-11-10T10:00:00+08:00\n問題: 等\n選項: 等 (Recommended) | 不等\n'
gcard ready-wait "$WAIT"
printf '# report\n\n## MR\nhttps://gitlab.example.com/acmecorp/r/-/merge_requests/7\n' > "$ROOT/r/openspec/changes/ready-wait/report.md"
export OPSX_TEST_GLAB_JSON="$FX/mr.json" OPSX_TEST_GLAB_JSON_BY_IID="$FX/mr-"
printf '{"state":"opened","draft":false,"has_conflicts":false,"sha":"aaa111","head_pipeline":{"status":"success"},"unresolved_discussions_count":0,"created_at":"2026-11-05T01:10:00.000Z","merged_at":null}' > "$FX/mr-7.json"
cat > "$ROOT/r/openspec/workplan.yaml" <<'EOF'
features:
  - name: fo
    status: active
    depends-on: []
    prs:
      - name: other
        branch: feat/other/u
        status: pending
        depends-on: []
        changes:
          - name: other
            status: pending
  - name: fm
    status: active
    depends-on: []
    prs:
      - name: merged-card
        branch: feat/merged-card/u
        status: merged
        depends-on: []
        changes:
          - name: merged-card
            status: done
EOF
J="$(opsx collect --root "$ROOT")"; assert_eq "$?" 0 "collect rc: $J"

C="$(card "$J" r only-wait)"
assert_eq "$(q "$C" section)" 等待中 "只等未合的卡：等待中"
assert_eq "$(q "$C" hold)" "等 other 合併" "hold 指出等哪張卡"
assert_eq "$(q "$C" waiting.gate_id)" g1 "waiting 照舊指第一個 gate"
assert_eq "$(q "$C" open_gates.0.id)" g1
assert_eq "$(q "$(card "$J" r wait-then-ask)" section)" 待處理 "未合 waits-on 後面還有要人答的題：待處理"
assert_eq "$(q "$(card "$J" r other-done)" section)" 待處理 "等的卡已合進 main：待處理"
assert_eq "$(q "$(card "$J" r ghost-wait)" section)" 等待中 "waits-on 對不到任何卡：照沒合算，不是待處理"
C="$(card "$J" r ready-wait)"
assert_eq "$(q "$C" mr.state)" ready "fixture 的 MR 要是 ready：$C"
assert_eq "$(q "$C" section)" 待處理 "MR 可合併、gate 只等別張卡：仍是待處理"
assert_eq "$(q "$(card "$J" r plain-ask)" section)" 待處理 "沒寫 waits-on 的 gate：待處理"
echo "collect-waits-on-section ok"
