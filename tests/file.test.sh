#!/usr/bin/env bash
# opsx file：待分類搬進 repo。驗收：specs/board-actions「分類」「不存在的待分類」（board-inbox 4.1）
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
use_fakes date
export OPSX_TEST_NOW="2026-11-06 14:30"
cd "$FX"   # 從 dispatch 的 worktree 跑時，cwd 不能讓 opsx new 把 fixture 的卡當成 agent 開的
A="$(mk_opsx_repo a)"

# --- 分類：內容原樣、unfiled 的檔不在了 ---
assert_eq "$(opsx new --name try-it -- 試試看)" try-it
U="$OPSX_STATE_DIR/unfiled/try-it.md"; cp "$U" "$FX/orig.md"
out="$(opsx file try-it --repo "$A")"; assert_eq "$?" 0 "file: $out"
assert_eq "$out" try-it
C="$A/openspec/changes/try-it"
assert_eq "$(cat "$C/inbox.md")" "$(cat "$FX/orig.md")"; assert_grep '^schema: opsx$' "$C/.openspec.yaml"
assert_no_file "$U"

# --- repo 裡已有同名：加 -2，原本的不動 ---
assert_eq "$(opsx new --name try-it -- 第二件)" try-it
assert_eq "$(opsx file try-it --repo "$A")" try-it-2
assert_grep '^第二件$' "$A/openspec/changes/try-it-2/inbox.md"; assert_grep '^試試看$' "$C/inbox.md"

# --- 不存在的待分類、沒給 repo、不合格的 slug：退出非零，repo 沒有新資料夾 ---
before="$(find "$A/openspec/changes" | sort)"
assert_rc 2 opsx file nope --repo "$A"
assert_rc 2 opsx file try-it
assert_rc 2 opsx file ../x --repo "$A"
assert_eq "$(find "$A/openspec/changes" | sort)" "$before"

# --- 並行：file 與 new --repo 同時挑到同一個 slug，兩邊內容都完整（specs/board-actions「分類與新增並行撞名」）---
export OPSX_TEST_NOW="2026-11-06 15:30"
assert_eq "$(opsx new --name par-file -- 待分類的那件)" par-file
opsx file par-file --repo "$A" > "$FX/p1.out" 2> "$FX/p1.err" &
opsx new --name par-file --repo "$A" -- 另一件 > "$FX/p2.out" 2> "$FX/p2.err" &
wait
assert_not_grep '失敗' "$FX/p1.err"; assert_not_grep '失敗' "$FX/p2.err"
assert_eq "$(cat "$FX/p1.out" "$FX/p2.out" | sort -u | wc -l | tr -d ' ')" 2 "兩個 slug 要不同"
assert_eq "$(grep -l '^待分類的那件$' "$A"/openspec/changes/par-file*/inbox.md | wc -l | tr -d ' ')" 1
assert_eq "$(grep -l '^另一件$' "$A"/openspec/changes/par-file*/inbox.md | wc -l | tr -d ' ')" 1

# --- 分類帶著附件 ---
printf 'png-bytes' > "$FX/shot.png"
export OPSX_TEST_NOW="2026-11-06 15:00"
assert_eq "$(opsx new --name with-attach --attach "$FX/shot.png" -- 有附件)" with-attach
out="$(opsx file with-attach --repo "$A")"; assert_eq "$?" 0 "file 附件: $out"
assert_eq "$out" with-attach
assert_eq "$(cat "$A/openspec/changes/with-attach/attachments/shot.png")" png-bytes
assert_no_file "$OPSX_STATE_DIR/unfiled/with-attach.md"; assert_no_file "$OPSX_STATE_DIR/unfiled/with-attach"

# --- 分類撞名時附件跟著改名的殼 ---
printf 'other' > "$FX/b.txt"
assert_eq "$(opsx new --name with-attach --attach "$FX/b.txt" -- 撞名的附件)" with-attach
assert_eq "$(opsx file with-attach --repo "$A")" with-attach-2
assert_eq "$(cat "$A/openspec/changes/with-attach-2/attachments/b.txt")" other
assert_no_file "$A/openspec/changes/with-attach/attachments/b.txt"
assert_eq "$(ls "$A/openspec/changes/with-attach/attachments")" shot.png "原本的殼不變"
assert_no_file "$OPSX_STATE_DIR/unfiled/with-attach"

# --- 待分類資料夾裡多了別的檔（Finder 的 .DS_Store）：照樣搬完，不留半張卡 ---
export OPSX_TEST_NOW="2026-11-06 16:00"
assert_eq "$(opsx new --name ds-store --attach "$FX/shot.png" -- 看過截圖)" ds-store
printf 'finder' > "$OPSX_STATE_DIR/unfiled/ds-store/.DS_Store"
out="$(opsx file ds-store --repo "$A")"; assert_eq "$?" 0 "多了 .DS_Store 也要成功：$out"
assert_eq "$out" ds-store
assert_eq "$(cat "$A/openspec/changes/ds-store/attachments/shot.png")" png-bytes
assert_no_file "$OPSX_STATE_DIR/unfiled/ds-store.md"; assert_no_file "$OPSX_STATE_DIR/unfiled/ds-store"
assert_no_file "$A/openspec/changes/ds-store-2"
# 預期外的檔：建殼前就退出，什麼都不動
assert_eq "$(opsx new --name ds-store --attach "$FX/shot.png" -- 有別的檔)" ds-store
printf 'mine' > "$OPSX_STATE_DIR/unfiled/ds-store/notes.txt"
before="$(ls "$A/openspec/changes")"
assert_rc 2 opsx file ds-store --repo "$A"
assert_eq "$(ls "$A/openspec/changes")" "$before" "不能建殼"
assert_file "$OPSX_STATE_DIR/unfiled/ds-store.md"; assert_file "$OPSX_STATE_DIR/unfiled/ds-store/attachments/shot.png"

# --- 分類進有 workplan 的 repo：source me 的卡自成 feature，milestone 是 current_milestone（specs/workplan-attach「opsx file」）---
F="$(mk_opsx_repo f)"
printf 'milestones:\n  - name: "2.0"\n    goal: "g"\ncurrent_milestone: "2.0"\n\nfeatures:\n  - name: fa\n    status: active\n    prs:\n      - name: pa\n        branch: feat/pa/t\n        status: pending\n        changes:\n          - name: pa\n            status: pending\n' > "$F/openspec/workplan.yaml"
export OPSX_TEST_NOW="2026-11-06 18:00"
assert_eq "$(opsx new --name to-workplan --type 功能 -- 分類後掛進 workplan)" to-workplan
out="$(OPSX_USER=mika opsx file to-workplan --repo "$F" 2> "$FX/f.err")"; assert_eq "$?" 0 "$(cat "$FX/f.err")"
assert_not_grep '沒掛進' "$FX/f.err"
python3 -I - "$OPSX_ROOT/bin/lib" "$F/openspec/workplan.yaml" "$out" <<'PY' || fail "分類的卡要自成 feature：$(cat "$F/openspec/workplan.yaml")"
import sys
sys.path.insert(0, sys.argv[1]); import chain
f = chain.load_workplan(sys.argv[2])["features"][-1]
assert (f["name"], f.get("milestone"), f["prs"][0]["name"], f["prs"][0]["branch"]) == (sys.argv[3], "2.0", sys.argv[3], "feat/%s/mika" % sys.argv[3]), f
PY
assert_grep '^priority: P2$' "$F/openspec/changes/$out/inbox.md"
echo ok
