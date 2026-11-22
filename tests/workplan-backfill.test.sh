#!/usr/bin/env bash
# opsx backfill：不在 workplan 的卡先預覽、--write 才照建卡的掛入規則補進去。
# 驗收：openspec/changes/workplan-backfill/specs/workplan-backfill/spec.md
source "$(dirname "$0")/lib.sh"
LIB="$OPSX_ROOT/bin/lib"
unset OPSX_USER

# card <repo> <slug> [<frontmatter 多的行>…]：有 inbox.md 與 kind dev 的卡
card() {
  local d="$1/openspec/changes/$2" l; mkdir -p "$d"; shift 2
  printf 'schema: opsx\nkind: dev\n' > "$d/.openspec.yaml"
  { printf -- '---\ntype: 功能\nkind_of_work: planned\n'; for l in "$@"; do printf '%s\n' "$l"; done; printf -- '---\n\n## 一句話\n\nx\n'; } > "$d/inbox.md"
}
# 第 3 欄（動作）；那張卡沒有一行就印空
action() { awk -F'\t' -v s="$2" '$2==s{print $3}' "$1"; }
reason() { awk -F'\t' -v s="$2" '$2==s{print $4}' "$1"; }
# 讀回 $WPR 的 workplan：印 python 運算式，f(<名>) 是 feature，pr(<名>) 是 PR，fof(<PR 名>) 是 PR 所在的 feature 名
wp() { set -- "$WPR" "$1"; python3 -I -c 'import sys
sys.path.insert(0, sys.argv[1]); import chain
fs = chain.load_workplan(sys.argv[2])["features"]
f = lambda n: next((x for x in fs if x["name"] == n), None)
prs = [(x["name"], p) for x in fs for p in x.get("prs") or []]
pr = lambda n: next((p for _, p in prs if p["name"] == n), None)
fof = lambda n: next((fn for fn, p in prs if p["name"] == n), None)
print(eval(sys.argv[3]))' "$LIB" "$1/openspec/workplan.yaml" "$2"; }

R="$(mk_repo Rp)"; WPR="$R"
mkdir -p "$R/openspec/changes"
cat > "$R/openspec/workplan.yaml" <<'EOF'
current_milestone: "m1"
milestones:
  - name: "m1"
    goal: "g1"
  - name: "m0"
    goal: "g0"

features:
  - name: F
    status: active
    prs:
      - name: p
        branch: feat/p/x
        status: pending
        changes:
          - name: p
            status: pending
  - name: G
    status: active
    prs:
      - name: q
        branch: feat/q/x
        status: pending
        changes:
          - name: q
            status: pending
  - name: DONE
    status: complete
    milestone: "m0"
    prs:
      - name: d
        branch: feat/d/x
        status: merged
        changes:
          - name: d
            status: done
EOF
card "$R" p
card "$R" o1
card "$R" a1 "source: agent:p"
card "$R" s1
printf '2026-11-01T10:00:00+08:00\t系統\t已決定\t從 q 拆出（id s1-old）\n' > "$R/openspec/changes/s1/decisions.tsv"
card "$R" both "source: agent:p"
printf '2026-11-01T10:00:00+08:00\t系統\t已決定\t從 q 拆出（id b-old）\n' > "$R/openspec/changes/both/decisions.tsv"
card "$R" c1 "source: agent:d"
card "$R" k1 "source: agent:gone"
card "$R" lp
card "$R" lc "source: agent:lp"
card "$R" z0 "source: agent:p" "priority: P0" "priority_reason: 使用者：急"
# 父卡 c1 自成帶 milestone m0 的 feature，P0 子卡也自成 feature、沿用 m0（預覽要跟寫入一樣）
card "$R" cz "source: agent:c1" "priority: P0" "priority_reason: 使用者：急"
# source 的父卡不存在，改看 decisions.tsv 的 split-out 父卡
card "$R" k2 "source: agent:gone2"
printf '2026-11-01T10:00:00+08:00\t系統\t已決定\t從 q 拆出（id k2-old）\n' > "$R/openspec/changes/k2/decisions.tsv"
# 父卡已拆：照 split_into 找第一個在 workplan 的主 change（m9 不在、p 在 F）
card "$R" spar "split_into: m9, p"
card "$R" sc "source: agent:spar"
card "$R" sp "split_into: m1x"
card "$R" si "split_into: []"
mkdir -p "$R/openspec/changes/legacy"; printf -- '- [x] 1.1 x\n' > "$R/openspec/changes/legacy/tasks.md"
card "$R" host
mkdir -p "$R/openspec/changes/host/subs/sub1"; printf -- '---\nparent: host\n---\n' > "$R/openspec/changes/host/subs/sub1/inbox.md"
git -C "$R" config user.name "Mikaela Lin"
RN="$(basename "$R")"

# --- 先預覽，帶 --write 才寫：預覽不寫檔、預覽不寫 P2 覆寫 ---
cp "$R/openspec/workplan.yaml" "$FX/wp.before"; cp "$R/openspec/changes/o1/inbox.md" "$FX/o1.before"
opsx backfill --repo "$R" > "$FX/pre" 2> "$FX/pre.err" || fail "預覽 rc：$(cat "$FX/pre.err")"
cmp -s "$FX/wp.before" "$R/openspec/workplan.yaml" || fail "預覽不能改 workplan"
cmp -s "$FX/o1.before" "$R/openspec/changes/o1/inbox.md" || fail "預覽不能改 inbox"
assert_not_grep '^priority:' "$R/openspec/changes/o1/inbox.md"
grep -q "^$RN	o1	" "$FX/pre" || fail "預覽要有 o1 一行：$(cat "$FX/pre")"

# --- 依父卡掛入（預覽與寫入要同一個動作）---
assert_eq "$(action "$FX/pre" a1)" "掛進 feature F" "source 找到 active 父 feature"
assert_eq "$(action "$FX/pre" s1)" "掛進 feature G" "split-out 的父卡"
assert_eq "$(action "$FX/pre" both)" "掛進 feature F" "source 優先於 split-out"
assert_eq "$(action "$FX/pre" o1)" "自成 feature" "沒有父卡"
assert_eq "$(action "$FX/pre" c1)" "自成 feature（milestone m0）" "父 feature 已完成，沿用它的 milestone"
assert_eq "$(action "$FX/pre" k1)" "自成 feature" "父卡已歸檔"
assert_eq "$(action "$FX/pre" lp)" "自成 feature" "散父卡"
assert_eq "$(action "$FX/pre" lc)" "掛進 feature lp" "父卡也是散卡、先處理父卡"
assert_eq "$(action "$FX/pre" z0)" "自成 feature" "P0 不掛進父 feature"
assert_eq "$(action "$FX/pre" p)" "" "已在 workplan 的卡不出現"
assert_eq "$(action "$FX/pre" cz)" "自成 feature（milestone m0）" "散父卡帶 milestone，P0 子卡沿用"
assert_eq "$(action "$FX/pre" k2)" "掛進 feature G" "source 的父卡不存在時改看 split-out"
assert_eq "$(action "$FX/pre" sc)" "掛進 feature F" "父卡已拆時照 split_into 找"
grep -qx "$RN	spar	略過	已拆" "$FX/pre" || fail "已拆的父卡本身要略過：$(cat "$FX/pre")"

# --- 略過不能掛或不該掛的卡 ---
grep -qx "$RN	sp	略過	已拆" "$FX/pre" || fail "已拆要略過：$(cat "$FX/pre")"
grep -qx "$RN	legacy	略過	沒有 inbox.md" "$FX/pre" || fail "沒有 inbox.md 要略過：$(cat "$FX/pre")"
assert_eq "$(action "$FX/pre" si)" "自成 feature" "split_into: [] 算沒拆"
assert_eq "$(action "$FX/pre" sub1)" "" "子殼不是頂層卡"

# --- 帶 --write 照預覽寫入 ---
opsx backfill --repo "$R" --write > "$FX/w" 2> "$FX/w.err"; rc=$?
assert_eq "$rc" 0 "全部成功 exit 0：$(cat "$FX/w.err")"
assert_eq "$(cat "$FX/w.err")" "" "全部成功 stderr 是空的"
cmp -s "$FX/pre" "$FX/w" || fail "寫入印的要跟預覽一樣：$(diff "$FX/pre" "$FX/w")"
assert_eq "$(wp 'fof("a1")')" F
assert_eq "$(wp 'fof("s1")')" G
assert_eq "$(wp 'fof("both")')" F
assert_eq "$(wp 'fof("lc")')" lp
assert_eq "$(wp '[p["name"] for p in f("o1")["prs"]], [c["name"] for c in pr("o1")["changes"]]')" "(['o1'], ['o1'])"
assert_eq "$(wp 'f("c1").get("milestone")')" m0 "父 feature 已完成時仍沿用它的 milestone"
assert_eq "$(wp '"milestone" in f("o1"), "milestone" in f("k1"), "milestone" in f("lp")')" "(False, False, False)" "沒有父卡的舊卡不填 milestone"
assert_eq "$(wp 'fof("z0")')" z0
assert_eq "$(wp 'f("cz").get("milestone")')" m0 "寫入的 milestone 跟預覽一樣"
assert_eq "$(wp 'fof("k2"), fof("sc")')" "('G', 'F')"
assert_eq "$(wp 'fof("sp"), fof("legacy"), fof("sub1")')" "(None, None, None)" "略過的卡不寫"
assert_eq "$(wp 'pr("p")["branch"]')" "feat/p/x" "已在 workplan 的卡不改 branch"
assert_grep '^priority: P2$' "$R/openspec/changes/o1/inbox.md"
assert_grep '^priority_auto: true$' "$R/openspec/changes/o1/inbox.md"
assert_grep '^priority: P0$' "$R/openspec/changes/z0/inbox.md"
assert_not_grep '^priority_auto' "$R/openspec/changes/z0/inbox.md"
case "$(opsx priority o1 --repo "$R")" in P2*) ;; *) fail "o1 要是 P2：$(opsx priority o1 --repo "$R")" ;; esac

# --- 重跑不重複掛 ---
cp "$R/openspec/workplan.yaml" "$FX/wp.after"
opsx backfill --repo "$R" --write > "$FX/w2" 2>&1 || fail "重跑 rc：$(cat "$FX/w2")"
cmp -s "$FX/wp.after" "$R/openspec/workplan.yaml" || fail "重跑不能改 workplan"
assert_eq "$(action "$FX/w2" a1)" "" "已掛的卡不再出現"
grep -qx "$RN	sp	略過	已拆" "$FX/w2" || fail "略過的卡每次都列"

# --- 沿用卡已在用的 branch ---
B="$(mk_repo Bq)"; BN="$(basename "$B")"; WPR="$B"
mkdir -p "$B/openspec/changes"; printf 'features:\n  - name: F\n    status: active\n    prs:\n      - name: p\n        branch: feat/p/x\n        status: pending\n' > "$B/openspec/workplan.yaml"
git -C "$B" config user.name "Mikaela Lin"
card "$B" b1; card "$B" b2; card "$B" b3; card "$B" b4; card "$B" b5; card "$B" b6
mkdir -p "$OPSX_STATE_DIR"
printf '{"%s/b1": {"branch": "feat/b1/mikaela", "mode": "stopped"}, "%s/b4": {"branch": "feat/b4/mikaela", "mode": "stopped"}}\n' "$BN" "$BN" > "$OPSX_STATE_DIR/dispatch.json"
git -C "$B" branch fix/b2/mikaela; git -C "$B" branch fix/b4/x; git -C "$B" branch feat/b5-2/mikaela
git -C "$B" branch feat/b6/mikaela; git -C "$B" branch feat/b6/mikaela-lin
opsx backfill --repo "$B" --write > "$FX/b" 2> "$FX/b.err" || fail "branch 測試 rc：$(cat "$FX/b.err")"
assert_eq "$(wp 'pr("b1")["branch"]')" "feat/b1/mikaela" "dispatch.json 的紀錄"
assert_eq "$(wp 'pr("b2")["branch"]')" "fix/b2/mikaela" "本地唯一一條"
assert_eq "$(wp 'pr("b3")["branch"]')" "feat/b3/mikaela-lin" "都沒有就照建卡規則算"
assert_eq "$(wp 'pr("b4")["branch"]')" "feat/b4/mikaela" "dispatch 紀錄優先"
assert_eq "$(wp 'pr("b5")["branch"]')" "feat/b5/mikaela-lin" "別張卡的 branch 不算"
assert_eq "$(action "$FX/b" b6)" "略過" "兩條以上要略過"
assert_eq "$(reason "$FX/b" b6)" "branch 有兩條以上：feat/b6/mikaela、feat/b6/mikaela-lin"
assert_eq "$(wp 'pr("b6")')" None
assert_not_grep '^priority:' "$B/openspec/changes/b6/inbox.md"
rm -f "$OPSX_STATE_DIR/dispatch.json"

# --- 單張失敗不擋其他卡 ---
X="$(mk_repo Xr)"; WPR="$X"
mkdir -p "$X/openspec/changes"; printf 'features:\n  - name: x1\n    status: active\n    prs:\n      - name: other\n        branch: feat/other/x\n        status: pending\n' > "$X/openspec/workplan.yaml"
git -C "$X" config user.name "Mikaela Lin"
card "$X" x1; card "$X" x2
# 等級算不出來（impact 有值、evidence 空）也算失敗
mkdir -p "$X/openspec/changes/x3"; printf -- '---\ntype: bug\nkind_of_work: incident\nimpact: security\n---\n' > "$X/openspec/changes/x3/inbox.md"
# 父卡 x1 失敗，子卡 x4 也列為失敗，不自成 feature
card "$X" x4 "source: agent:x1"
cp "$X/openspec/workplan.yaml" "$FX/x.before"; cp "$X/openspec/changes/x1/inbox.md" "$FX/x1.before"
# 預覽就要報出 --write 才會撞到的失敗
opsx backfill --repo "$X" > "$FX/xp" 2> "$FX/xp.err"; rc=$?
[ "$rc" -ne 0 ] || fail "預覽遇到會失敗的卡也要 exit 非零"
grep -q "x1" "$FX/xp.err" || fail "預覽的 stderr 要列出撞名的 x1：$(cat "$FX/xp.err")"
assert_eq "$(action "$FX/xp" x1)" "" "會失敗的卡不印成可掛"
opsx backfill --repo "$X" --write > "$FX/x" 2> "$FX/x.err"; rc=$?
[ "$rc" -ne 0 ] || fail "有卡失敗要 exit 非零"
grep -q "x1" "$FX/x.err" || fail "stderr 要列出 x1：$(cat "$FX/x.err")"
grep -q "x3" "$FX/x.err" || fail "stderr 要列出等級算不出來的 x3：$(cat "$FX/x.err")"
grep -q "x4.*父卡 x1 寫入失敗" "$FX/x.err" || fail "父卡失敗時子卡也列為失敗：$(cat "$FX/x.err")"
assert_eq "$(wp 'pr("x3")')" None "x3 不寫"
assert_eq "$(wp 'pr("x4")')" None "父卡失敗的子卡不寫"
assert_eq "$(wp 'fof("x2")')" x2 "x2 照樣掛"
assert_eq "$(wp 'pr("x1")')" None "x1 不留半套"
cmp -s "$FX/x1.before" "$X/openspec/changes/x1/inbox.md" || fail "失敗的 x1 inbox 不能留 P2 覆寫：$(cat "$X/openspec/changes/x1/inbox.md")"
# attach 本身（建卡也走這裡）撞名時也不改 inbox
python3 -I "$LIB/workplanwrite.py" attach "$X" x1 "" mika "" 2> /dev/null && fail "attach 撞名要失敗"
cmp -s "$FX/x1.before" "$X/openspec/changes/x1/inbox.md" || fail "attach 撞名不能改 inbox"

# --- 沒有分支尾巴名字：預覽與 --write 都列為失敗 ---
U="$(mk_repo Uy)"; WPR="$U"
mkdir -p "$U/openspec/changes"; printf 'features: []\n' > "$U/openspec/workplan.yaml"
git -C "$U" config user.name "Your Name"
card "$U" u1
opsx backfill --repo "$U" > "$FX/u" 2> "$FX/u.err" && fail "沒有尾巴名字時預覽要 exit 非零"
grep -q "u1" "$FX/u.err" || fail "預覽要列出 u1：$(cat "$FX/u.err")"
opsx backfill --repo "$U" --write > "$FX/uw" 2> "$FX/uw.err" && fail "沒有尾巴名字時 --write 要 exit 非零"
cmp -s "$FX/u" "$FX/uw" || fail "預覽與 --write 印的要一樣"
assert_eq "$(wp 'pr("u1")')" None "u1 不寫"

# --- 不帶 --repo 掃全部 repo；沒有 workplan 的 repo 印略過 ---
W="$(mk_repo code/Wa)"; N="$(mk_repo code/Nb)"
mkdir -p "$W/openspec/changes" "$N/openspec/changes"; printf 'features: []\n' > "$W/openspec/workplan.yaml"
git -C "$W" config user.name "Mikaela Lin"
card "$W" w1; card "$N" n1
# workplan 不是 UTF-8 的 repo：記一筆失敗，其他 repo 照常
Z="$(mk_repo code/Zc)"; mkdir -p "$Z/openspec/changes"; printf 'features:\n  - name: \377\n' > "$Z/openspec/workplan.yaml"; card "$Z" z1
opsx backfill > "$FX/all" 2> "$FX/all.err" && fail "有 repo 讀不了 workplan 要 exit 非零"
grep -q "Zc" "$FX/all.err" || fail "stderr 要列出讀不了的 repo：$(cat "$FX/all.err")"
assert_eq "$(action "$FX/all" z1)" "" "讀不了的 repo 不列卡"
grep -qx "Nb	-	略過	repo 沒有 workplan" "$FX/all" || fail "沒有 workplan 的 repo 要印略過：$(cat "$FX/all")"
assert_eq "$(action "$FX/all" w1)" "自成 feature" "有 workplan 的 repo 照常"
assert_eq "$(action "$FX/all" n1)" "" "沒有 workplan 的 repo 不列卡"
assert_no_file "$N/openspec/workplan.yaml"

echo ok
