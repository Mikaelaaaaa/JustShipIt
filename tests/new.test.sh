#!/usr/bin/env bash
# opsx new：＋新增。驗收：specs/board-actions「新增到 repo」「卡名由 --name 指定」「沒給 repo」「空的一句話」（board-inbox 3.1）
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
use_fakes date
export OPSX_TEST_NOW="2026-11-06 14:30"
cd "$FX"   # 從 dispatch 的 worktree 跑測試時，cwd 不能讓 opsx new 把 fixture 的卡當成 agent 開的
A="$(mk_opsx_repo a)"; B="$(mk_opsx_repo b)"
snap() { find "$A/openspec/changes" "$B/openspec/changes" | sort; }

# --- 新增到 repo：卡名就是 --name ---
out="$(opsx new --name chat-keyboard --repo "$A" -- 聊天視窗被鍵盤蓋住)"; assert_eq "$?" 0 "new: $out"
assert_eq "$out" chat-keyboard "stdout 只印 slug"
C="$A/openspec/changes/chat-keyboard"
assert_file "$C/inbox.md"; assert_grep '^schema: opsx$' "$C/.openspec.yaml"
assert_grep '^type: 待定$' "$C/inbox.md"; assert_grep '^source: me$' "$C/inbox.md"; assert_grep '^found: 2026-11-06$' "$C/inbox.md"
assert_eq "$(awk '/^## 一句話/{f=1;next} f&&NF{print;exit}' "$C/inbox.md")" 聊天視窗被鍵盤蓋住

# --- 同名加流水號 ---
out="$(opsx new --name chat-keyboard --repo "$A" -- 另一件事)"; assert_eq "$out" chat-keyboard-2
assert_grep '^另一件事$' "$A/openspec/changes/chat-keyboard-2/inbox.md"
assert_grep '^聊天視窗被鍵盤蓋住$' "$C/inbox.md"

# --- 沒給 repo：只寫 unfiled/ ---
before="$(snap)"
out="$(opsx new --name try-it -- 試試看)"; assert_eq "$?" 0; assert_eq "$out" try-it
U="$OPSX_STATE_DIR/unfiled/try-it.md"
assert_file "$U"; assert_grep '^source: me$' "$U"; assert_grep '^試試看$' "$U"; assert_grep '^type: 待定$' "$U"
assert_eq "$(snap)" "$before" "不帶 --repo 不能動任何 repo"
assert_eq "$(opsx new --name try-it -- 再一個)" try-it-2

# --- 卡名規則（board-actions「卡名由 --name 指定」）：不合就退出非零、stderr 含 --name 與拿到的值、什麼都不寫 ---
before="$(snap)"; ub="$(find "$OPSX_STATE_DIR/unfiled" | sort)"
bad_name() { # bad_name <stderr 要含的值> <opsx new 的參數…>
  local want="$1" e; shift
  e="$(opsx new "$@" 2>&1 >/dev/null)"; assert_eq "$?" 2 "要退出 2：$*"
  case "$e" in *--name*) ;; *) fail "stderr 要含 --name：$e" ;; esac
  case "$e" in *"$want"*) ;; *) fail "stderr 要含「${want}」：$e" ;; esac
}
bad_name "" --repo "$A" -- 聊天視窗被鍵盤蓋住
bad_name "" -- 沒給 repo 也要擋
bad_name Chat-Keyboard --name Chat-Keyboard --repo "$A" -- x
bad_name 聊天 --name 聊天 --repo "$A" -- x
bad_name "chat keyboard" --name "chat keyboard" --repo "$A" -- x
bad_name ../x --name ../x --repo "$A" -- x
bad_name aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa --name aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa --repo "$A" -- x
bad_name 1chat --name 1chat --repo "$A" -- x
bad_name -chat --name -chat --repo "$A" -- x
bad_name main--sub --name main--sub --repo "$A" -- x
bad_name kb_export2 --name kb_export2 --repo "$A" -- x
bad_name kb_export2 --name kb_export2 -- 待分類也擋：之後 opsx file 建不了殼
bad_name chat- --name chat- --repo "$A" -- x
bad_name "" --name "" --repo "$A" -- x
bad_name "" --repo "$A" --name
assert_eq "$(snap)" "$before"; assert_eq "$(find "$OPSX_STATE_DIR/unfiled" | sort)" "$ub" "卡名不合不能寫任何檔"
assert_eq "$(opsx new --name kb-export2 --repo "$A" -- x)" kb-export2
assert_eq "$(opsx new --name a --repo "$A" -- x)" a "最短 1 字"
assert_eq "$(opsx new --name aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa --repo "$A" -- x)" aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa "最長 32 字"
assert_file "$A/openspec/changes/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/inbox.md"
# 32 字的名字在待分類撞名：加號後仍不超過 32 字（跟 new_shell 同一條截法），opsx file 收得下
L32=keyboard-covers-chat-input-box-1
assert_eq "$(opsx new --name "$L32" -- 第一張)" "$L32"
u2="$(opsx new --name "$L32" -- 第二張)"
assert_eq "$u2" keyboard-covers-chat-input-b-1-2 "截中段、保留最後一段再加 -2"
assert_eq "$(opsx file "$u2" --repo "$A")" "$u2"

# --- 空的、多行的一句話：退出非零，什麼都不寫 ---
before="$(snap)"; ub="$(ls "$OPSX_STATE_DIR/unfiled")"
assert_rc 2 opsx new --name x --repo "$A" -- ""
assert_rc 2 opsx new --name x --repo "$A" -- "   "
assert_rc 2 opsx new --name x --repo "$A" -- "$(printf 'a\nb')"
assert_rc 2 opsx new --name x -- ""
assert_rc 2 opsx new --name x --repo "$FX/nope" -- 有字
assert_eq "$(snap)" "$before"; assert_eq "$(ls "$OPSX_STATE_DIR/unfiled")" "$ub"

# --- 並行：同名 8 個呼叫，slug 互不相同、每張卡內容完整（specs/board-actions「並行新增到…」）---
par_new() { # par_new <輸出目錄> <opsx new 的前置參數…>：同時起 8 個，各帶「並行<i>」
  local out="$1" i; shift
  mkdir -p "$out"
  for i in 1 2 3 4 5 6 7 8; do opsx new "$@" -- "並行$i" > "$out/$i.out" 2> "$out/$i.err" & done
  wait
}
count() { wc -l | tr -d ' '; }
assert_par() { # assert_par <輸出目錄> <slug 前綴> <各卡內容檔的 glob>
  local out="$1" i
  for i in 1 2 3 4 5 6 7 8; do assert_not_grep '失敗' "$out/$i.err"; assert_eq "$(count < "$out/$i.out")" 1 "並行$i 要印一個 slug"; done
  assert_eq "$(cat "$out"/*.out | sort -u | count)" 8 "8 個 slug 要互不相同"
  assert_eq "$(ls -d $2* | count)" 8 "落地的卡要剛好 8 張"
  for i in 1 2 3 4 5 6 7 8; do assert_eq "$(grep -l "^並行$i\$" $3 | count)" 1 "並行$i 的內容要在剛好一張卡裡"; done
}
export OPSX_TEST_NOW="2026-11-06 17:00"
par_new "$FX/par-unfiled" --name par-unfiled
assert_par "$FX/par-unfiled" "$OPSX_STATE_DIR/unfiled/par-unfiled" "$OPSX_STATE_DIR/unfiled/par-unfiled*.md"

export OPSX_TEST_NOW="2026-11-06 15:10"
spec_before="$(ls -A "$A/openspec")"
par_new "$FX/par-repo" --name par-repo --repo "$A"
assert_par "$FX/par-repo" "$A/openspec/changes/par-repo" "$A/openspec/changes/par-repo*/inbox.md"
assert_eq "$(ls -A "$A/openspec")" "$spec_before" "保留用的東西不能留在 openspec/ 下"

# --- 建殼失敗：退出非零、印原因、只呼叫一次、不留殘渣 ---
export OPSX_TEST_NOW="2026-11-06 15:20"
mkdir -p "$FX/failspec"
printf '#!/usr/bin/env bash\necho "fake openspec: boom" >&2\necho x >> "%s/spec.calls"\nexit 1\n' "$FX" > "$FX/failspec/openspec"; chmod +x "$FX/failspec/openspec"
before="$(snap)"; spec_before="$(ls -A "$A/openspec")"
PATH="$FX/failspec:$PATH" opsx new --name boom --repo "$A" -- 有字 > /dev/null 2> "$FX/fail.err"; rc=$?
[ "$rc" -ne 0 ] || fail "openspec 失敗時 opsx new 要退出非零"
assert_grep 'boom' "$FX/fail.err"
assert_eq "$(count < "$FX/spec.calls")" 1 "openspec 失敗不能換 slug 重試"
assert_eq "$(snap)" "$before"; assert_eq "$(ls -A "$A/openspec")" "$spec_before" "失敗後不能留保留殘渣"

# --- 保留剛被別人放掉：mkdir 失敗但保留目錄已不在，不能誤判成建不了，要換下一號（review R1.1）---
export OPSX_TEST_NOW="2026-11-06 15:40"
mkdir -p "$FX/failmkdir"
printf '#!/usr/bin/env bash\ncase "$*" in *.reserve-*) [ -e "%s/mkdir.once" ] || { : > "%s/mkdir.once"; exit 1; };; esac\nexec /bin/mkdir "$@"\n' "$FX" "$FX" > "$FX/failmkdir/mkdir"; chmod +x "$FX/failmkdir/mkdir"
spec_before="$(ls -A "$A/openspec")"
out="$(PATH="$FX/failmkdir:$PATH" opsx new --name reserve-race --repo "$A" -- 保留剛被放掉 2>/dev/null)"; assert_eq "$?" 0 "new: $out"
assert_eq "$out" reserve-race-2
assert_grep '^保留剛被放掉$' "$A/openspec/changes/reserve-race-2/inbox.md"
assert_eq "$(ls -A "$A/openspec")" "$spec_before" "保留用的東西不能留在 openspec/ 下"

# --- openspec/ 不可寫：退出非零、說原因，不無限換號 ---
export OPSX_TEST_NOW="2026-11-06 15:50"
chmod a-w "$A/openspec"; before="$(snap)"
opsx new --name read-only --repo "$A" -- 唯讀 > /dev/null 2> "$FX/ro.err"; rc=$?
chmod u+w "$A/openspec"
[ "$rc" -ne 0 ] || fail "openspec/ 不可寫時 opsx new 要退出非零"
assert_grep '保留' "$FX/ro.err"
assert_eq "$(snap)" "$before"

# --- 待分類寫入失敗：退出非零、不換號、不留 0 byte 的檔（review R1.2）---
export OPSX_TEST_NOW="2026-11-06 16:00"
mkdir -p "$FX/failcat"
printf '#!/usr/bin/env bash\ncase "$1" in *opsx-new.*) echo x >> "%s/cat.calls"; [ "$(wc -l < "%s/cat.calls")" -gt 3 ] || exit 1;; esac\nexec /bin/cat "$@"\n' "$FX" "$FX" > "$FX/failcat/cat"; chmod +x "$FX/failcat/cat"
PATH="$FX/failcat:$PATH" opsx new --name cat-fail -- 寫不進去 > /dev/null 2> "$FX/cat.err"; rc=$?
[ "$rc" -ne 0 ] || fail "待分類寫入失敗時 opsx new 要退出非零"
assert_eq "$(ls "$OPSX_STATE_DIR/unfiled" | grep -c 'cat-fail')" 0 "寫入失敗不能留檔（含 0 byte）"
assert_eq "$(count < "$FX/cat.calls")" 1 "寫入失敗不能換號重試"

# --- mkdir 因撞名以外的原因一直失敗（磁碟滿之類）而 openspec/ 可寫：換號有上限，要 die，不能無限換（review R2.1）---
export OPSX_TEST_NOW="2026-11-06 16:10"
mkdir -p "$FX/enospc"
printf '#!/usr/bin/env bash\ncase "$*" in *.reserve-*) echo x >> "%s/mkdir.calls"; echo "mkdir: No space left on device" >&2; exit 1;; esac\nexec /bin/mkdir "$@"\n' "$FX" > "$FX/enospc/mkdir"; chmod +x "$FX/enospc/mkdir"
before="$(snap)"
PATH="$FX/enospc:$PATH" opsx new --name no-space --repo "$A" -- 磁碟滿 > /dev/null 2> "$FX/enospc.err" &
pid=$!
( sleep 60; kill "$pid" 2>/dev/null ) &
killer=$!
wait "$pid"; rc=$?
kill "$killer" 2>/dev/null
[ "$rc" -ne 0 ] && [ "$rc" -ne 143 ] || fail "mkdir 一直失敗時 opsx new 要自己退出非零（rc=${rc}；143 是被測試的逾時保護殺掉）"
assert_grep 'No space left' "$FX/enospc.err"
[ "$(count < "$FX/mkdir.calls")" -le 1100 ] || fail "換號沒有上限：mkdir 被呼叫 $(count < "$FX/mkdir.calls") 次"
assert_eq "$(snap)" "$before"

# --- 附檔（新增時附檔）---
export OPSX_TEST_NOW="2026-11-06 15:00"
T="$FX/att"; mkdir -p "$T/x" "$T/y"
printf 'png-bytes' > "$T/shot.png"; printf 'log line\n' > "$T/log.txt"
printf 'first' > "$T/x/a.png"; printf 'second' > "$T/y/a.png"

# 附檔建在 repo
out="$(opsx new --name with-attach --repo "$A" --attach "$T/shot.png" --attach "$T/log.txt" -- 聊天視窗被鍵盤蓋住)"; assert_eq "$?" 0 "new --attach: $out"
assert_eq "$out" with-attach
C="$A/openspec/changes/with-attach"
assert_eq "$(cat "$C/attachments/shot.png")" png-bytes; assert_eq "$(cat "$C/attachments/log.txt")" "log line"
assert_grep '^source: paste$' "$C/inbox.md"
assert_eq "$(awk '/^## 附件/{f=1;next} /^## /{f=0} f&&NF' "$C/inbox.md")" "$(printf -- '- attachments/shot.png\n- attachments/log.txt')"
assert_eq "$(grep -n '^## ' "$C/inbox.md" | cut -d: -f2-)" "$(printf '## 一句話\n## 附件\n## 證據')" "## 附件 在 ## 證據 之前"

# 沒附檔照舊
out="$(opsx new --name with-attach --repo "$A" -- 試試看)"; assert_eq "$out" with-attach-2
assert_grep '^source: me$' "$A/openspec/changes/$out/inbox.md"
assert_not_grep '^## 附件' "$A/openspec/changes/$out/inbox.md"
assert_no_file "$A/openspec/changes/$out/attachments"

# 同名附件
out="$(opsx new --name same-attach --repo "$A" --attach "$T/x/a.png" --attach "$T/y/a.png" --attach "$T/x/a.png" -- 同名)"; assert_eq "$?" 0 "new 同名: $out"
D="$A/openspec/changes/$out/attachments"
assert_eq "$(cat "$D/a.png")" first; assert_eq "$(cat "$D/a-2.png")" second; assert_eq "$(cat "$D/a-3.png")" first
assert_grep '^- attachments/a.png$' "$A/openspec/changes/$out/inbox.md"; assert_grep '^- attachments/a-2.png$' "$A/openspec/changes/$out/inbox.md"
assert_grep '^- attachments/a-3.png$' "$A/openspec/changes/$out/inbox.md"
printf 'm' > "$T/Makefile"; printf 'n' > "$T/y/Makefile"
out="$(opsx new --name no-ext --repo "$A" --attach "$T/Makefile" --attach "$T/y/Makefile" -- 沒副檔名)"
assert_eq "$(cat "$A/openspec/changes/$out/attachments/Makefile-2")" n "沒副檔名的同名加 -2"
# 只差大小寫也算同名：macOS 的檔案系統不分大小寫，不改名第二個會蓋掉第一個
printf 'upper' > "$T/x/A.png"
out="$(opsx new --name case-attach --repo "$A" --attach "$T/x/A.png" --attach "$T/y/a.png" -- 大小寫)"
D="$A/openspec/changes/$out/attachments"
assert_eq "$(ls "$D" | wc -l | tr -d ' ')" 2 "兩個檔都要在：$(ls "$D")"
assert_eq "$(cat "$D/A.png")" upper; assert_eq "$(cat "$D/a-2.png")" second

# 附檔進待分類
before="$(snap)"
out="$(opsx new --name with-attach --attach "$T/shot.png" -- 試試看)"; assert_eq "$?" 0 "new unfiled --attach: $out"
assert_eq "$out" with-attach
assert_file "$OPSX_STATE_DIR/unfiled/$out.md"; assert_grep '^source: paste$' "$OPSX_STATE_DIR/unfiled/$out.md"
assert_grep '^- attachments/shot.png$' "$OPSX_STATE_DIR/unfiled/$out.md"
assert_eq "$(cat "$OPSX_STATE_DIR/unfiled/$out/attachments/shot.png")" png-bytes
assert_eq "$(snap)" "$before" "附檔進待分類不能動任何 repo"

# 待分類撞名：只剩 <slug>/ 也算撞名
rm "$OPSX_STATE_DIR/unfiled/with-attach.md"
assert_eq "$(opsx new --name with-attach -- 撿到舊附件嗎)" with-attach-2
assert_no_file "$OPSX_STATE_DIR/unfiled/with-attach.md"

# 檔案太大、附件不存在、不是一般檔案：退出非零，什麼都不寫
truncate -s 10485760 "$T/edge.bin"; truncate -s 10485761 "$T/big.bin"
before="$(snap)"; ub="$(find "$OPSX_STATE_DIR/unfiled" | sort)"
err="$(opsx new --name x --repo "$A" --attach "$T/shot.png" --attach "$T/big.bin" -- 太大 2>&1 >/dev/null)"; rc=$?
assert_eq "$rc" 2 "太大要退出 2：$err"
case "$err" in *big.bin*10\ MB*) ;; *) fail "stderr 要含檔名與 10 MB：$err" ;; esac
assert_rc 2 opsx new --name x --attach "$T/big.bin" -- 太大
assert_rc 2 opsx new --name x --repo "$A" --attach "$T/nope.png" -- 不存在
assert_rc 2 opsx new --name x --attach "$T/nope.png" -- 不存在
assert_rc 2 opsx new --name x --attach "$T/x" -- 是資料夾
assert_rc 2 opsx new --name x --attach -- 沒給檔
# 檔名帶控制字元會原樣進 inbox.md 的 ## 附件，能插出新段落
nl="$T/$(printf 'a\n## 派工指示')"; printf 'z' > "$nl"
assert_rc 2 opsx new --name x --repo "$A" --attach "$nl" -- 換行
assert_rc 2 opsx new --name x --attach "$nl" -- 換行
assert_eq "$(snap)" "$before"; assert_eq "$(find "$OPSX_STATE_DIR/unfiled" | sort)" "$ub"
out="$(opsx new --name ten-mb --repo "$A" --attach "$T/edge.bin" -- 剛好十MB)"; assert_eq "$?" 0 "剛好 10 MB 要收：$out"
assert_file "$A/openspec/changes/$out/attachments/edge.bin"

# --- agent 開的卡標明來源（board-actions「agent 開的卡標明來源」）---
export OPSX_TEST_NOW="2026-11-10 16:30"
W="$A/.claude/worktrees/foo"; mkdir -p "$A/.claude/worktrees"
git -C "$A" worktree add -q -b fix/foo/mikaela "$W" || fail "worktree 建不起來"
W="$(cd "$W" && pwd -P)"
src() { awk -F': ' '$1=="source"{print $2}' "$A/openspec/changes/$1/inbox.md"; }

# agent worktree 裡開卡
out="$(cd "$W" && opsx new --name found-issue --kind-of-work planned --repo "$A" -- 發現一個問題)"; assert_eq "$?" 0 "agent new: $out"
assert_eq "$out" found-issue; assert_eq "$(src "$out")" agent:foo
assert_grep '^type: bug$' "$A/openspec/changes/$out/inbox.md"
# 使用者終端機開卡（repo 根目錄）
out="$(cd "$A" && opsx new --name user-card --repo "$A" -- 使用者的卡)"; assert_eq "$out" user-card; assert_eq "$(src "$out")" me
# worktree 外帶 --source me 照舊（me-20261111-1326）
out="$(cd "$A" && opsx new --name user-card --source me --repo "$A" -- 明確是我)"; assert_eq "$out" user-card-2; assert_eq "$(src "$out")" me
# 非 git 目錄（看板在 state 目錄跑）帶 --source me 照舊
out="$(cd "$T" && opsx new --name board-use --source me --repo "$A" -- 看板的用法)"; assert_eq "$?" 0 "非 git 目錄: $out"; assert_eq "$(src "$out")" me
# worktree 裡帶 --source me 被拒：退出 2、訊息點名 --source、什麼都不寫（me-20261111-1326）
before="$(snap)"; ub="$(find "$OPSX_STATE_DIR/unfiled" | sort)"
err="$(cd "$W" && opsx new --name x --source me --kind-of-work planned --repo "$A" -- 想蓋掉來源 2>&1 >/dev/null)"; assert_eq "$?" 2 "worktree 裡 --source me: $err"
case "$err" in *--source*) ;; *) fail "stderr 要點名 --source：$err" ;; esac
(cd "$W" && opsx new --name x --source me --kind-of-work planned -- 沒給 repo) >/dev/null 2>&1; assert_eq "$?" 2 "worktree 裡沒給 repo 也要拒"
assert_eq "$(snap)" "$before"; assert_eq "$(find "$OPSX_STATE_DIR/unfiled" | sort)" "$ub" "被拒時不能寫任何檔"
# 明確 --source agent:<slug> 在 repo 根目錄也成立
out="$(cd "$A" && opsx new --name explicit-agent --source agent:bar --kind-of-work planned --repo "$A" -- 明確是 agent)"; assert_eq "$out" explicit-agent; assert_eq "$(src "$out")" agent:bar
# agent 帶附件：來源取 agent，附件照常
out="$(cd "$W" && opsx new --name with-shot --kind-of-work planned --repo "$A" --attach "$T/shot.png" -- 有截圖)"; assert_eq "$(src "$out")" agent:foo
assert_eq "$(cat "$A/openspec/changes/$out/attachments/shot.png")" png-bytes
assert_grep '^- attachments/shot.png$' "$A/openspec/changes/$out/inbox.md"
# agent 沒給 repo：進待分類，來源一樣
out="$(cd "$W" && opsx new --name no-repo --kind-of-work planned -- 沒指定 repo)"; assert_grep '^source: agent:foo$' "$OPSX_STATE_DIR/unfiled/$out.md"
# 不合格的 --source：退出非零、stderr 含該值、什麼都不寫
before="$(snap)"; ub="$(find "$OPSX_STATE_DIR/unfiled" | sort)"
err="$(opsx new --name x --source robot --repo "$A" -- x 2>&1 >/dev/null)"; assert_eq "$?" 2 "robot: $err"
case "$err" in *robot*) ;; *) fail "stderr 要含 robot：$err" ;; esac
assert_rc 2 opsx new --name x --source agent: --repo "$A" -- x
assert_rc 2 opsx new --name x --source --repo "$A" -- x
assert_eq "$(snap)" "$before"; assert_eq "$(find "$OPSX_STATE_DIR/unfiled" | sort)" "$ub"
# agent 已離開 worktree：OPSX_CARD 在，cwd 是 repo 根目錄，仍是 agent 開的卡
out="$(cd "$A" && export OPSX_CARD=foo && opsx new --name after-leave --kind-of-work planned --repo "$A" -- 離開後開的卡)"; assert_eq "$?" 0 "OPSX_CARD: $out"
assert_eq "$out" after-leave "agent 開的卡不加前綴"
assert_eq "$(src "$out")" agent:foo
# 離開 worktree 後帶 --source me 被拒：退出 2、訊息點名 --source、什麼都不寫
before="$(snap)"; ub="$(find "$OPSX_STATE_DIR/unfiled" | sort)"
err="$(cd "$A" && export OPSX_CARD=foo && opsx new --name x --source me --kind-of-work planned --repo "$A" -- 想蓋掉來源 2>&1 >/dev/null)"; assert_eq "$?" 2 "OPSX_CARD 下 --source me: $err"
case "$err" in *--source*) ;; *) fail "stderr 要點名 --source：$err" ;; esac
# 變數值不合格：退出非零、stderr 含該值、什麼都不寫
err="$(cd "$A" && export OPSX_CARD="a b" && opsx new --name x --kind-of-work planned --repo "$A" -- x 2>&1 >/dev/null)"; assert_eq "$?" 2 "OPSX_CARD=a b: $err"
case "$err" in *"a b"*) ;; *) fail "stderr 要含 a b：$err" ;; esac
# agent 沒帶 --name：一樣拒絕，不退回 agent-<日期>
err="$(cd "$W" && opsx new --kind-of-work planned --repo "$A" -- x 2>&1 >/dev/null)"; assert_eq "$?" 2 "agent 沒帶 --name: $err"
case "$err" in *--name*) ;; *) fail "stderr 要含 --name：$err" ;; esac
assert_eq "$(snap)" "$before"; assert_eq "$(find "$OPSX_STATE_DIR/unfiled" | sort)" "$ub" "被拒時不能寫任何檔"

# --- 開卡的事實欄位（board-actions「agent 開的卡要帶事實欄位」）---
before="$(snap)"; ub="$(find "$OPSX_STATE_DIR/unfiled" | sort)"
fact_err() { local e; e="$(cd "$W" && opsx new --name x "$@" 2>&1 >/dev/null)"; assert_eq "$?" 2 "要退出 2：$*"; printf '%s' "$e"; }
case "$(fact_err --repo "$A" -- 沒帶 kind)" in *kind-of-work*) ;; *) fail "agent 沒帶 --kind-of-work 的訊息要含 kind-of-work" ;; esac
case "$(fact_err --kind-of-work incident --evidence e --repo "$A" -- 缺 impact)" in *impact*) ;; *) fail "incident 缺 impact 的訊息要含 impact" ;; esac
case "$(fact_err --kind-of-work incident --impact data --repo "$A" -- 缺 evidence)" in *evidence*) ;; *) fail "incident 缺 evidence 的訊息要含 evidence" ;; esac
case "$(fact_err --kind-of-work urgent --repo "$A" -- 錯值)" in *urgent*) ;; *) fail "不認得的 kind 要在訊息裡" ;; esac
case "$(fact_err --kind-of-work incident --impact slow --evidence e --repo "$A" -- 錯 impact)" in *slow*) ;; *) fail "不認得的 impact 要在訊息裡" ;; esac
case "$(fact_err --kind-of-work planned --impact data --repo "$A" -- planned 帶 impact)" in *impact*) ;; *) fail "planned 帶 impact 要拒絕並提到 impact" ;; esac
assert_eq "$(snap)" "$before"; assert_eq "$(find "$OPSX_STATE_DIR/unfiled" | sort)" "$ub" "缺欄位不能寫任何檔"
# incident 全帶：三個欄位各一行
out="$(cd "$W" && opsx new --name incident-all --kind-of-work incident --impact "data, prod_or_main" --evidence "tests/x.test.sh 第 2 案紅" --repo "$A" -- 出事)"
assert_grep '^kind_of_work: incident$' "$A/openspec/changes/$out/inbox.md"
assert_grep '^impact: data, prod_or_main$' "$A/openspec/changes/$out/inbox.md"
assert_grep '^evidence: tests/x.test.sh 第 2 案紅$' "$A/openspec/changes/$out/inbox.md"
assert_eq "$(opsx priority "$out" --repo "$A" | cut -f1)" P0 "寫進去的事實算得出等級"
# planned 不需要 evidence
out="$(cd "$W" && opsx new --name planned-one --kind-of-work planned --repo "$A" -- 想做的)"; assert_grep '^kind_of_work: planned$' "$A/openspec/changes/$out/inbox.md"
# 使用者開的卡不強制：沒帶就是 planned（既有行為）
out="$(cd "$A" && opsx new --name user-planned --repo "$A" -- 使用者的卡二)"; assert_grep '^kind_of_work: planned$' "$A/openspec/changes/$out/inbox.md"

# --- review 退回的邊界 ---
# 明確 --source me（worktree 外）帶附件仍是 paste
out="$(cd "$A" && opsx new --name me-attach --source me --repo "$A" --attach "$T/shot.png" -- 明確我加附件)"; assert_eq "$(src "$out")" paste
# worktree 子目錄
mkdir -p "$W/sub"; out="$(cd "$W/sub" && opsx new --name sub-dir --kind-of-work planned --repo "$A" -- 子目錄)"; assert_eq "$(src "$out")" agent:foo
# worktree 資料夾名與卡名不同：branch 對得到卡就用卡名，對不到才用資料夾名
mkdir -p "$A/openspec/changes/real-card"; printf 'schema: opsx\n' > "$A/openspec/changes/real-card/.openspec.yaml"
git -C "$A" worktree add -q -b feat/real-card/mikaela "$A/.claude/worktrees/agent-a1b2c3" || fail "第二棵 worktree 建不起來"
out="$(cd "$A/.claude/worktrees/agent-a1b2c3" && opsx new --name branch-card --kind-of-work planned --repo "$A" -- 卡名在 branch)"; assert_eq "$(src "$out")" agent:real-card
# worktree 裡兩個訊號都在：卡名走 branch，不用 OPSX_CARD（feature session 的值是 session 名）
out="$(cd "$A/.claude/worktrees/agent-a1b2c3" && export OPSX_CARD=sess && opsx new --name two-signals --kind-of-work planned --repo "$A" -- 兩個訊號)"; assert_eq "$(src "$out")" agent:real-card
git -C "$A" worktree add -q -b scratch/nothing/mikaela "$A/.claude/worktrees/agent-d4e5f6" || fail "第三棵 worktree 建不起來"
out="$(cd "$A/.claude/worktrees/agent-d4e5f6" && opsx new --name no-branch-card --kind-of-work planned --repo "$A" -- branch 對不到卡)"; assert_eq "$(src "$out")" agent:agent-d4e5f6
# 子殼 subagent 的 worktree：branch 是 <主>--<子>，卡在 changes/<主>/subs/<子>/
mkdir -p "$A/openspec/changes/m/subs/s"; printf 'schema: opsx\n' > "$A/openspec/changes/m/.openspec.yaml"
git -C "$A" worktree add -q -b feat/m--s/mikaela "$A/.claude/worktrees/agent-7a8b9c" || fail "第四棵 worktree 建不起來"
out="$(cd "$A/.claude/worktrees/agent-7a8b9c" && opsx new --name sub-shell --kind-of-work planned --repo "$A" -- 子殼 subagent 發現的)"; assert_eq "$(src "$out")" agent:m--s
# worktree 裡又開一棵 worktree（toplevel 是 .../worktrees/x/.claude/worktrees/y）：路徑不算 dispatch 的 worktree，只有 OPSX_CARD 能讓它成為 agent
N="$W/.claude/worktrees/y"; mkdir -p "$W/.claude/worktrees"
git -C "$A" worktree add -q -b scratch/nested/mikaela "$N" || fail "巢狀 worktree 建不起來"
out="$(cd "$N" && opsx new --name nested-me --repo "$A" -- 巢狀沒有變數)"; assert_eq "$(src "$out")" me
out="$(cd "$N" && export OPSX_CARD=foo && opsx new --name nested-agent --kind-of-work planned --repo "$A" -- 巢狀有變數)"; assert_eq "$(src "$out")" agent:foo

# --- agent 開的卡進待分類的原子保留（main #92）---
# 同名兩張：第二張加 -2、兩張內容各自完整
export OPSX_TEST_NOW="2026-11-10 17:00"
u1="$(cd "$W" && opsx new --name unfiled-pair --kind-of-work planned -- 待分類甲)"; u2="$(cd "$W" && opsx new --name unfiled-pair --kind-of-work planned -- 待分類乙)"
assert_eq "$u1" unfiled-pair; assert_eq "$u2" unfiled-pair-2
assert_grep '^待分類甲$' "$OPSX_STATE_DIR/unfiled/$u1.md"; assert_grep '^待分類乙$' "$OPSX_STATE_DIR/unfiled/$u2.md"
# 並行：同時挑同一個 slug，兩邊都拿到自己的、不互蓋
export OPSX_TEST_NOW="2026-11-10 17:01"
(cd "$W" && opsx new --name par-agent --kind-of-work planned -- 並行甲 > "$FX/q1.out" 2> "$FX/q1.err") &
(cd "$W" && opsx new --name par-agent --kind-of-work planned -- 並行乙 > "$FX/q2.out" 2> "$FX/q2.err") &
wait
assert_eq "$(cat "$FX/q1.out" "$FX/q2.out" | sort -u | wc -l | tr -d ' ')" 2 "並行兩張的 slug 要不同：$(cat "$FX/q1.err" "$FX/q2.err")"
assert_eq "$(grep -l '^並行甲$' "$OPSX_STATE_DIR"/unfiled/par-agent*.md | wc -l | tr -d ' ')" 1
assert_eq "$(grep -l '^並行乙$' "$OPSX_STATE_DIR"/unfiled/par-agent*.md | wc -l | tr -d ' ')" 1

# --- type 欄位（board-actions「新增到收件匣」：帶 type、agent 卡預設 bug、type 不在值域）---
export OPSX_TEST_NOW="2026-11-11 10:00"
type_of() { awk -F': ' '$1=="type"{print $2; exit}' "$1"; }
out="$(opsx new --name with-type --type 技術債 --repo "$A" -- 帶 type)"; assert_eq "$?" 0 "--type 技術債: $out"
assert_eq "$(type_of "$A/openspec/changes/$out/inbox.md")" 技術債
assert_eq "$(grep -c '^type:' "$A/openspec/changes/$out/inbox.md")" 1 "type 只寫一行"
out="$(cd "$W" && opsx new --name agent-incident --kind-of-work incident --impact data --evidence e --repo "$A" -- agent incident)"
assert_eq "$(type_of "$A/openspec/changes/$out/inbox.md")" bug "agent 的 incident 卡預設 bug"
out="$(cd "$W" && opsx new --name agent-type --type 想法 --kind-of-work planned --repo "$A" -- agent 帶 type)"
assert_eq "$(type_of "$A/openspec/changes/$out/inbox.md")" 想法 "agent 帶 --type 照收"
out="$(cd "$W" && opsx new --name agent-unfiled --kind-of-work planned -- agent 待分類)"
assert_eq "$(type_of "$OPSX_STATE_DIR/unfiled/$out.md")" bug "agent 的待分類卡也是 bug"
out="$(opsx new --name user-unfiled-type --type 功能 -- 使用者待分類帶 type)"
assert_eq "$(type_of "$OPSX_STATE_DIR/unfiled/$out.md")" 功能
# type 不在值域、--area、--dup-of：退出 2，什麼都不寫
before="$(snap)"; ub="$(find "$OPSX_STATE_DIR/unfiled" | sort)"
err="$(opsx new --name x --type 改善 --repo "$A" -- x 2>&1 >/dev/null)"; assert_eq "$?" 2 "--type 改善: $err"
case "$err" in *改善*) ;; *) fail "stderr 要含拿到的值：$err" ;; esac
assert_rc 2 opsx new --name x --type "" --repo "$A" -- x
assert_rc 2 opsx new --name x --type Bug --repo "$A" -- x
assert_rc 2 opsx new --name x --type --repo "$A" -- x
assert_rc 2 opsx new --name x --type 改善 -- x
assert_rc 2 opsx new --name x --area hooks --repo "$A" -- x
assert_rc 2 opsx new --name x --dup-of x --repo "$A" -- y
assert_eq "$(snap)" "$before"; assert_eq "$(find "$OPSX_STATE_DIR/unfiled" | sort)" "$ub" "被拒時不能寫任何檔"

# --- 掛進 workplan：specs/workplan-attach「新卡掛進 workplan」「新 PR 帶 branch」「掛進去不改等級」「沒有 workplan 的 repo 不建檔」---
export OPSX_USER=mika OPSX_TEST_NOW="2026-11-12 09:00"
wp_fixture() { # wp_fixture <repo> <current_milestone 那一行，空字串是沒設>
  cat > "$1/openspec/workplan.yaml" <<EOF
created: 2026-11-05

milestones:
  - name: "1.0"
    goal: "g1"
  - name: "2.0"
    goal: "g2"
$2

features:
  - name: fa
    milestone: "1.0"
    status: active
    prs:
      - name: pa
        branch: feat/pa/t
        status: pending
        depends-on: []
        changes:
          - name: pa
            status: pending
  - name: fc
    milestone: "1.0"
    status: complete
    prs:
      - name: pc
        branch: feat/pc/t
        status: merged
        depends-on: []
        changes:
          - name: pc
            status: done
  - name: fp
    milestone: "1.0"
    status: pending
    prs:
      - name: pp
        branch: feat/pp/t
        status: pending
        changes:
          - name: pp
            status: pending
  - name: fn
    prs:
      - name: pn
        branch: feat/pn/t
        status: pending
        changes:
          - name: pn
            status: pending
EOF
}
where() { # where <repo> <slug>：印「<feature>\t<milestone，沒有是 ->\t<branch>」；workplan 沒有以 slug 命名、底下一個同名 change 的 PR 印 none
  python3 -I - "$OPSX_ROOT/bin/lib" "$1/openspec/workplan.yaml" "$2" <<'PY'
import sys
sys.path.insert(0, sys.argv[1]); import chain
for f in chain.load_workplan(sys.argv[2]).get("features") or []:
    for pr in f.get("prs") or []:
        if pr.get("name") == sys.argv[3] and [(c.get("name"), c.get("status")) for c in pr.get("changes") or []] == [(sys.argv[3], "pending")]:
            print("%s\t%s\t%s" % (f["name"], f.get("milestone") or "-", pr.get("branch")))
            sys.exit(0)
print("none")
PY
}
WP="$(mk_opsx_repo wp)"; wp_fixture "$WP" 'current_milestone: "2.0"'
wnew() { opsx new --repo "$WP" "$@" 2> "$FX/wp.err"; }
s="$(wnew --name chat-keyboard --type 功能 -- 使用者的卡)"; assert_eq "$?" 0 "$(cat "$FX/wp.err")"
assert_eq "$s" chat-keyboard "卡名也是 workplan 的 PR 名和 branch 第二段"
assert_eq "$(where "$WP" "$s")" "$s	2.0	feat/$s/mika" "source me 自成 feature，milestone 是 current_milestone"
assert_not_grep '沒掛進' "$FX/wp.err"
assert_grep '^priority: P2$' "$WP/openspec/changes/$s/inbox.md"
assert_grep '^priority_reason: 自動掛進 workplan，維持 P2$' "$WP/openspec/changes/$s/inbox.md"
assert_grep '^priority_auto: true$' "$WP/openspec/changes/$s/inbox.md"
assert_eq "$(opsx priority "$s" --repo "$WP" | cut -f1)" P2 "掛進目前 milestone 仍是 P2"
opsx priority "$s" --repo "$WP" | cut -f2 | grep -q '系統：自動掛進 workplan' || fail "理由要顯示系統：$(opsx priority "$s" --repo "$WP")"
python3 -I - "$OPSX_ROOT/bin/lib" "$WP/openspec/workplan.yaml" "$s" <<'PY' || fail "新 feature 要是 active、depends-on 空、PR pending"
import sys
sys.path.insert(0, sys.argv[1]); import chain
f = [x for x in chain.load_workplan(sys.argv[2])["features"] if x["name"] == sys.argv[3]][0]
assert (f["status"], f["depends-on"], f["prs"][0]["status"], f["prs"][0]["depends-on"]) == ("active", [], "pending", []), f
PY
s="$(wnew --name user-bug --type bug -- 使用者的 bug)"; assert_eq "$(where "$WP" "$s" | cut -f3)" "fix/$s/mika" "type bug 的 branch 前綴是 fix"
assert_eq "$(where "$WP" "$s" | cut -f1)" "$s" "沒有併入目標的 bug 卡建殼並自成 feature"
s="$(wnew --name parent-active --type 功能 --source agent:pa --kind-of-work planned -- 父 feature active)"
assert_eq "$(where "$WP" "$s")" "fa	1.0	feat/$s/mika" "父卡 feature active 時加 PR"
s="$(wnew --name parent-complete --type 功能 --source agent:pc --kind-of-work planned -- 父 feature complete)"
assert_eq "$(where "$WP" "$s")" "$s	1.0	feat/$s/mika" "父 feature complete 時自成 feature、沿用它的 milestone"
s="$(wnew --name parent-pending --type 功能 --source agent:pp --kind-of-work planned -- 父 feature pending)"
assert_eq "$(where "$WP" "$s" | cut -f1)" fp "只有 complete 才自成 feature，pending 掛進父 feature"
s="$(wnew --name parent-no-status --type 功能 --source agent:pn --kind-of-work planned -- 父 feature 沒寫 status)"
assert_eq "$(where "$WP" "$s" | cut -f1)" fn "沒寫 status 的父 feature 也掛進去"
s="$(wnew --name sub-shell-card --type 功能 --source agent:pa--sub1 --kind-of-work planned -- 子殼開的)"
assert_eq "$(where "$WP" "$s" | cut -f1)" fa "子殼 agent 取主殼"
s="$(wnew --name parent-missing --type 功能 --source agent:zz --kind-of-work planned -- 父卡不在 workplan)"
assert_eq "$(where "$WP" "$s")" "$s	2.0	feat/$s/mika" "父卡沒掛等於沒有父卡"
s="$(wnew --name security-incident --kind-of-work incident --impact security --evidence 'bin/x.sh:1 洩漏' --type bug -- 安全事件)"
assert_eq "$(where "$WP" "$s" | cut -f1)" "$s"
assert_not_grep '^priority:' "$WP/openspec/changes/$s/inbox.md"
assert_eq "$(opsx priority "$s" --repo "$WP" | cut -f1)" P0 "incident P0 卡不寫覆寫"
# 掛入前是 P0／P1 的卡不掛進父 feature，自成 feature、沿用父 feature 的 milestone（workplan-attach D16）
fa_prs="$(grep -c '^      - name:' "$WP/openspec/workplan.yaml")"
s="$(wnew --name parent-incident --kind-of-work incident --impact security --evidence 'bin/x.sh:2 洩漏' --type bug --source agent:pa -- 有父卡的安全事件)"
assert_eq "$(where "$WP" "$s")" "$s	1.0	fix/$s/mika" "有父卡的 incident 卡自成 feature、milestone 沿用 fa"
assert_eq "$(grep -c '^      - name:' "$WP/openspec/workplan.yaml")" "$((fa_prs + 1))" "只多了新 feature 自己的 PR，fa 的 prs 不變"
# 父卡名是 feature 名（feature session 的 agent 開的卡）：找不到 PR 就當 feature 名找（workplan-attach D18）
s="$(wnew --name session-agent --type 功能 --source agent:fa --kind-of-work planned -- session agent 開的)"
assert_eq "$(where "$WP" "$s")" "fa	1.0	feat/$s/mika" "source 是 feature 名時掛進那個 feature"
s="$(wnew --name session-complete --type 功能 --source agent:fc --kind-of-work planned -- complete feature 的 session)"
assert_eq "$(where "$WP" "$s")" "$s	1.0	feat/$s/mika" "feature 名指到 complete 的 feature 時自成 feature、沿用它的 milestone"
# 卡名已被 workplan 的 PR、歸檔的卡或 */<名>/* 分支用掉：照撞名加 -2，PR 名和 branch 名才會跟卡名相同
s="$(wnew --name pc --type 功能 -- 跟已合併的 PR 同名)"; assert_eq "$s" pc-2 "$(cat "$FX/wp.err")"
assert_eq "$(where "$WP" pc-2 | cut -f3)" "feat/pc-2/mika" "workplan 多一個 pending 的 PR pc-2"
mkdir -p "$WP/openspec/changes/archive/2026-11-01-old-card"
assert_eq "$(wnew --name old-card --type 功能 -- 跟歸檔的卡同名)" old-card-2
git -C "$WP" branch -q feat/old-branch/mika
assert_eq "$(wnew --name old-branch --type 功能 -- 跟分支同名)" old-branch-2
git -C "$WP" branch -q feat/old-two
assert_eq "$(wnew --name old-two --type 功能 -- 跟兩段的分支同名)" old-two-2 "有 feat/old-two 時建不出 feat/old-two/<user>"
s="$(wnew --name fa --type 功能 -- 跟 feature 同名)"; assert_eq "$s" fa-2 "$(cat "$FX/wp.err")"
assert_eq "$(where "$WP" fa-2 | cut -f3)" "feat/fa-2/mika" "workplan 多一個 PR fa-2"
assert_not_grep '沒掛進' "$FX/wp.err"
WX="$(mk_opsx_repo wx)"
printf 'features:\n  - name: fx\n    status: active\n    prs:\n      - name: px\n        branch: feat/px/t\n        status: pending\n        changes:\n          - name: cx\n            status: pending\n' > "$WX/openspec/workplan.yaml"
assert_eq "$(opsx new --name cx --type 功能 --repo "$WX" -- 跟 change 同名 2> "$FX/wx.err")" cx-2 "只有 change 叫 cx 也算占用：$(cat "$FX/wx.err")"
# workplan 讀不了（PR 的 changes 寫成 flow list）：照樣建殼、退出 0，stderr 說 workplan 讀不了，不印 Traceback
WF="$(mk_opsx_repo wf)"
printf 'features:\n  - name: ff\n    status: active\n    prs:\n      - name: pf\n        branch: feat/pf/t\n        status: pending\n        changes: [p, q]\n' > "$WF/openspec/workplan.yaml"
s="$(opsx new --name x --type 功能 --repo "$WF" -- workplan 壞了 2> "$FX/wf.err")"; assert_eq "$?" 0 "$(cat "$FX/wf.err")"
assert_eq "$s" x; assert_file "$WF/openspec/changes/x/inbox.md"
assert_grep 'workplan' "$FX/wf.err"; assert_not_grep 'Traceback' "$FX/wf.err"
# 頂層寫成清單、檔案沒有讀取權限：一樣只警告、照樣建殼（D14）
WL="$(mk_opsx_repo wl)"
printf -- '- a\n' > "$WL/openspec/workplan.yaml"
s="$(opsx new --name list-top --type 功能 --repo "$WL" -- 頂層是清單 2> "$FX/wl.err")"; assert_eq "$?" 0 "$(cat "$FX/wl.err")"
assert_eq "$s" list-top; assert_grep 'workplan' "$FX/wl.err"; assert_not_grep 'Traceback' "$FX/wl.err"
WR="$(mk_opsx_repo wr)"; wp_fixture "$WR" ""; chmod 000 "$WR/openspec/workplan.yaml"
s="$(opsx new --name no-read --type 功能 --repo "$WR" -- 讀不到 workplan 2> "$FX/wr.err")"; assert_eq "$?" 0 "$(cat "$FX/wr.err")"
chmod 644 "$WR/openspec/workplan.yaml"
assert_eq "$s" no-read; assert_grep 'workplan' "$FX/wr.err"; assert_not_grep 'Traceback' "$FX/wr.err"
WN="$(mk_opsx_repo wn)"; wp_fixture "$WN" ""
s="$(opsx new --name no-milestone --type 功能 --repo "$WN" -- 沒設目前階段)"
assert_eq "$(where "$WN" "$s")" "$s	-	feat/$s/mika" "沒有 current_milestone 就不寫 milestone"
s="$(opsx new --name no-workplan --type 功能 --repo "$A" -- 沒有 workplan 的 repo)"; assert_file "$A/openspec/changes/$s/inbox.md"
assert_no_file "$A/openspec/workplan.yaml"; assert_no_file "$A/openspec/workplan.lock"
# 掛不進去（workplan 沒有 features:）：卡照建、退出 0，stderr 說卡已建、沒掛進 workplan，workplan 不動
WB="$(mk_opsx_repo wb)"; printf 'created: 2026-11-05\n' > "$WB/openspec/workplan.yaml"
s="$(opsx new --name bad-workplan --type 功能 --repo "$WB" -- 壞的 workplan 2> "$FX/wb.err")"; assert_eq "$?" 0 "$(cat "$FX/wb.err")"
assert_file "$WB/openspec/changes/$s/inbox.md"
assert_grep "已建 ${s}，但沒掛進 workplan" "$FX/wb.err"; assert_grep 'features' "$FX/wb.err"
assert_eq "$(cat "$WB/openspec/workplan.yaml")" "created: 2026-11-05"
echo ok
