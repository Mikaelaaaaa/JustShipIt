#!/usr/bin/env bash
# 看板：沒有 MR、還沒歸檔的 archive 站卡不放「已完成」，照等人規則分區；workplan 已 merged 的照舊放已完成。
# 驗收：openspec/changes/agent-20261116-1405-2/specs/no-mr-archive/spec.md「看板不把無 MR 的卡當已完成」
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
use_fakes herdr glab gh
export OPSX_FAKE_LOG="$FX/fake.log"; : > "$OPSX_FAKE_LOG"
export OPSX_MR_CACHE_TTL=0

card() { printf '%s' "$1" | python3 -I -c 'import json,sys;d=json.load(sys.stdin)
c=[c for c in d["cards"] if c["slug"]==sys.argv[1]]
print(c[0][sys.argv[2]] if c else "null")' "$2" "$3"; }

ROOT="$FX/code-nomr"; mkdir -p "$ROOT"
R="$(mk_repo code-nomr/o git@gitlab.example.com:g/o.git)"
git -C "$R" update-ref refs/remotes/origin/main HEAD
git -C "$R" branch -q feat/docs/mikaela HEAD
C="$R/openspec/changes/docs"; mkdir -p "$C"
printf 'schema: opsx\ncreated: 2026-11-16\nkind: chore\n' > "$C/.openspec.yaml"
printf -- '---\ntype: 功能\nsource: me\nfound: 2026-11-16\n---\n\n## 一句話\n\n只改 openspec\n' > "$C/inbox.md"
printf '## 1\n\n- [x] 1.1 a\n' > "$C/tasks.md"
printf '{"tests":"green"}' > "$C/status.json"
printf '# report\n' > "$C/report.md"
printf '## 卡在接 /archive #1\ntype: decision\nstatus: open\nopened_at: 2026-11-16T15:00:00+08:00\n問題: 卡在哪？\n' > "$C/gates.md"
workplan() { # <status> <mr 欄位行，空字串就不寫>
  { printf 'features:\n  - name: f\n    prs:\n      - name: docs\n        branch: feat/docs/mikaela\n        status: %s\n' "$1"
    [ -z "$2" ] || printf '        %s\n' "$2"
    printf '        changes:\n          - name: docs\n            status: pending\n'
  } > "$R/openspec/workplan.yaml"
}

# 正例：無 MR 的卡有 open gate，在待處理，不在已完成
workplan pending "mr: none"
J="$(opsx collect --root "$ROOT")"; assert_eq "$?" 0 "collect 無 MR: $J"
assert_eq "$(card "$J" docs stage)" archive "stage 照 stage_of"
assert_eq "$(card "$J" docs section)" 待處理 "有 open gate 的無 MR 卡要在待處理"

# 反例：workplan 已 merged 的卡在已完成
workplan merged ""
J="$(opsx collect --root "$ROOT")"; assert_eq "$?" 0 "collect merged: $J"
assert_eq "$(card "$J" docs section)" 已完成 "merged 的卡照舊在已完成"

# 進度分類：驗收 openspec/changes/agent-20261116-1640/specs/no-mr-archive/spec.md「無 MR 的卡在進度算測試中」「開發中的卡照舊依派工分類」
rm -f "$C/gates.md"
workplan pending "mr: none"
J="$(opsx collect --root "$ROOT")"
assert_eq "$(card "$J" docs progress_class)" testing "沒派工的無 MR 卡算測試中"
printf '{"o/docs":{"pane":"w1:p1","mode":"autopilot"}}' > "$OPSX_STATE_DIR/dispatch.json"
J="$(opsx collect --root "$ROOT")"
assert_eq "$(card "$J" docs progress_class)" testing "有派工的無 MR 卡算測試中"
rm -f "$OPSX_STATE_DIR/dispatch.json"
printf '## 1\n\n- [ ] 1.1 a\n' > "$C/tasks.md"
J="$(opsx collect --root "$ROOT")"
assert_eq "$(card "$J" docs progress_class)" not_dispatched "還有沒勾 task、沒派工的卡照舊算還沒派"

echo "collect-no-mr ok"
