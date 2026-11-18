#!/usr/bin/env bash
# hooks/cmd-skeleton.pl：切開指令字的引號與跳脫要還原；引號、註解、跳脫內的 heredoc 記號不吞後續行。
# 驗收：openspec/changes/agent-20261111-2326/specs/command-gate-bypass/spec.md「指令骨架去掉切開指令字的引號與跳脫」
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
SK="$OPSX_ROOT/hooks/cmd-skeleton.pl"
skel() { printf '%s' "$1" | perl "$SK"; }
has_commit() { case "$(skel "$1")" in *"git commit"*) return 0 ;; *) return 1 ;; esac; }

# --- 切開指令字：還原成 git commit ---
has_commit "g''it commit -m x" || fail "g''it：$(skel "g''it commit -m x")"
has_commit "git commi''t -m x" || fail "git commi''t：$(skel "git commi''t -m x")"
has_commit 'git c\ommit -m x' || fail 'git c\ommit：'"$(skel 'git c\ommit -m x')"
has_commit '"git" commit -m x' || fail '"git" commit'
has_commit "g'i't commit -m x" || fail "g'i't：$(skel "g'i't commit -m x")"
has_commit "$(printf 'git \\\ncommit -m x')" || fail "行尾續行的 git commit：$(skel "$(printf 'git \\\ncommit -m x')")"

# --- 反例：不是 git commit 的字不能被湊成 git commit ---
has_commit "echo 'git commit' x" && fail "單引號字串內的 git commit 不是指令：$(skel "echo 'git commit' x")"
has_commit "echo don't commit it's" && fail "撇號不是引號：$(skel "echo don't commit it's")"

# --- 緊貼字的單引號片段、$'…' 的 \'、跳脫反斜線後的真引號：片段裡的 " 不吞後一條指令 ---
has_commit "echo a'b \"'; git commit -m x; echo \"'\"" || fail "緊貼字的單引號片段吞掉了 commit：$(skel "echo a'b \"'; git commit -m x; echo \"'\"")"
has_commit "echo \$'\\' \"'; git commit -m x; echo \"'\"" || fail "\$'…' 的 \\' 吞掉了 commit：$(skel "echo \$'\\' \"'; git commit -m x; echo \"'\"")"
has_commit "echo \\\\'a \"'; git commit -m x; echo \"'\"" || fail "\\\\' 之後的引號吞掉了 commit：$(skel "echo \\\\'a \"'; git commit -m x; echo \"'\"")"
[ "$(skel "echo don't commit it's")" = "echo don't commit it's" ] || fail "撇號文字的骨架要原樣保留：$(skel "echo don't commit it's")"
has_commit "echo \\\\'git commit -m x'" && fail "\\\\' 之後的單引號字串不是指令：$(skel "echo \\\\'git commit -m x'")"

# --- heredoc 記號在引號、註解、跳脫內：後一行的 commit 仍在骨架裡 ---
has_commit "$(printf 'echo "<<EOF"\ngit commit -m x\nEOF')" || fail "雙引號內的 <<EOF 吞掉了 commit"
has_commit "$(printf "echo '<<EOF'\ngit commit -m x\nEOF")" || fail "單引號內的 <<EOF 吞掉了 commit"
has_commit "$(printf 'true # cat <<EOF\ngit commit -m x\nEOF')" || fail "註解內的 <<EOF 吞掉了 commit"
has_commit "$(printf 'echo \\<<EOF\ngit commit -m x\nEOF')" || fail '跳脫的 \<<EOF 吞掉了 commit'

# --- 正例：真的 heredoc，本體仍被去掉 ---
has_commit "$(printf 'cat <<EOF\ngit commit -m x\nEOF')" && fail "真 heredoc 的本體要去掉：$(skel "$(printf 'cat <<EOF\ngit commit -m x\nEOF')")"
has_commit "$(printf 'cat <<-EOF\n\tgit commit -m x\n\tEOF')" && fail "<<- 的 heredoc 本體要去掉"
# 餵給直譯器的 heredoc 本體會被執行，整段保留
has_commit "$(printf 'bash <<EOF\ngit commit -m x\nEOF')" || fail "餵給 bash 的 heredoc 本體要保留"
# 算術裡的 << 是位移，不是 heredoc 開頭；同一行算術已閉合之後的真 heredoc 照樣去掉本體
has_commit "$(printf 'echo $((1<<2))\ngit commit -m x\n2')" || fail "\$(( )) 裡的 << 吞掉了 commit：$(skel "$(printf 'echo $((1<<2))\ngit commit -m x\n2')")"
has_commit "$(printf '(( y = 1<<2 ))\ngit commit -m x\n2')" || fail "(( )) 裡的 << 吞掉了 commit：$(skel "$(printf '(( y = 1<<2 ))\ngit commit -m x\n2')")"
has_commit "$(printf 'x=$((1)); cat <<EOF\ngit commit -m x\nEOF')" && fail "算術之後的真 heredoc 本體要去掉：$(skel "$(printf 'x=$((1)); cat <<EOF\ngit commit -m x\nEOF')")"
# 同一行有真 heredoc、前面還有被引號包住的 <<
has_commit "$(printf 'echo "a <<b" ; cat <<EOF\ngit commit -m x\nEOF')" && fail "引號內的 << 之後的真 heredoc 本體要去掉"
# --- R1.1：$'…\'…' 裡的 \' 是字面引號，<<EOF 還在字串裡，後一行的 commit 仍在骨架 ---
has_commit $'echo $\'\\\'<<EOF\'\ngit commit -m x\nEOF' || fail "ANSI-C 引號內的 <<EOF 吞掉了 commit：$(skel $'echo $\'\\\'<<EOF\'\ngit commit -m x\nEOF')"
# --- R1.1：一串沒有結尾的 <<a 不能讓骨架變慢（hook 逾時等於放行）---
big="$(perl -e 'print "git commit -m x; :\n", "<<a\n" x 8000')"   # 換行讓每個開頭都走到 code_mask 查表
t0=$SECONDS; skel "$big" >/dev/null; elapsed=$((SECONDS - t0))
[ "$elapsed" -le 3 ] || fail "32KB 的一串 <<a 骨架花了 ${elapsed} 秒（要線性）"
has_commit "$big" || fail "那串 <<a 之前的 git commit 不能不見"
# 一串沒結尾的 "$( 也要線性；有結尾的雙引號字串照舊換成空字串
big="$(perl -e 'print "git commit -m x; ", q{"$(} x 10900')"
t0=$SECONDS; skel "$big" >/dev/null 2>&1; elapsed=$((SECONDS - t0))
[ "$elapsed" -le 3 ] || fail "32KB 的一串沒結尾 \"\$( 骨架花了 ${elapsed} 秒（要線性）"
has_commit "$big" 2>/dev/null || fail "那串 \"\$( 之前的 git commit 不能不見"
has_commit 'echo "git commit -m x"' && fail "有結尾的雙引號字串要換成空字串：$(skel 'echo "git commit -m x"')"

# --- R1.2：指令位置的 \<字母> 還原，含 ; && 之後與絕對路徑的 git；參數位置的路徑字保留跳脫 ---
has_commit 'cd /tmp;g\it commit -m x' || fail '; 之後的 g\it：'"$(skel 'cd /tmp;g\it commit -m x')"
has_commit 'cd /tmp&&g\it commit -m x' || fail '&& 之後的 g\it：'"$(skel 'cd /tmp&&g\it commit -m x')"
has_commit '/usr/bin/g\it commit -m x' || fail '絕對路徑的 g\it：'"$(skel '/usr/bin/g\it commit -m x')"
has_commit '{ /usr/bin/g\it commit -m x; }' || fail '{ 之後的 g\it：'"$(skel '{ /usr/bin/g\it commit -m x; }')"
has_commit 'if /usr/bin/g\it commit -m x; then :; fi' || fail 'if 之後的 g\it：'"$(skel 'if /usr/bin/g\it commit -m x; then :; fi')"
has_commit '! /usr/bin/g\it commit -m x' || fail '! 之後的 g\it：'"$(skel '! /usr/bin/g\it commit -m x')"
has_commit 'time /usr/bin/g\it commit -m x' || fail 'time 之後的 g\it：'"$(skel 'time /usr/bin/g\it commit -m x')"
has_commit 'env /usr/bin/g\it commit -m x' || fail 'env 之後的 g\it：'"$(skel 'env /usr/bin/g\it commit -m x')"
has_commit 'command /usr/bin/g\it commit -m x' || fail 'command 之後的 g\it：'"$(skel 'command /usr/bin/g\it commit -m x')"
case "$(skel 'git -C /tmp/env\b commit -m x')" in *'/tmp/env\b'*) ;; *) fail "路徑裡的 env 不算前綴，跳脫要保留：$(skel 'git -C /tmp/env\b commit -m x')" ;; esac
case "$(skel 'git -C /tmp/a\b commit -m x')" in *'/tmp/a\b'*) ;; *) fail "參數位置的路徑字要保留跳脫：$(skel 'git -C /tmp/a\b commit -m x')" ;; esac

# --- 原樣保留的片段不能讓裡面的指令字逃過還原 ---
# 沒結尾的雙引號之後，指令位置的 g\it 照樣還原
has_commit $'# say "hi\ng\\it commit -m x' || fail "註解裡沒結尾的 \" 之後的 g\\it：$(skel $'# say "hi\ng\\it commit -m x')"
has_commit $'echo "$(echo a # it\'s\n)"; g\\it commit -m x' || fail "\$( 裡註解的撇號之後的 g\\it：$(skel $'echo "$(echo a # it\'s\n)"; g\\it commit -m x')"
# 緊貼字、含空白的單引號片段保留引號，片段裡的指令字照樣還原
has_commit $'bash -c true\'; g\\it commit -m x\'' || fail "緊貼字的片段裡的 g\\it：$(skel $'bash -c true\'; g\\it commit -m x\'')"
# 引號裡的 (( 不是算術，同一行的真 heredoc 照樣剝掉，本體裡的 <<X 不吞後面的 commit
has_commit $'echo "((" ; cat <<EOF\ncat <<X\nEOF\ngit commit -m x\nX' || fail "引號裡的 (( 取消了真 heredoc：$(skel $'echo "((" ; cat <<EOF\ncat <<X\nEOF\ngit commit -m x\nX')"
# 被跳脫的 \$ 後面的 ' 是一般單引號，不是 $'…'
has_commit $'echo \\$\'\\\'\ng\\it commit -m x\necho \'y\'' || fail "\\\$' 被當成 \$'…'：$(skel $'echo \\$\'\\\'\ng\\it commit -m x\necho \'y\'')"
# 沒結尾的雙引號之後，後面的 " 不再配對，夾在中間的指令留在骨架
has_commit $'echo "$(echo a # it\'s\n)" ; git commit -m x ; echo $(echo "a")' || fail "沒結尾的 \" 之後，\$(echo \"a\") 的引號吞掉了 commit：$(skel $'echo "$(echo a # it\'s\n)" ; git commit -m x ; echo $(echo "a")')"
has_commit $'echo "$(echo a # it\'s\n)" ; git commit -m x ; echo \\"' || fail "沒結尾的 \" 之後，\\\\\" 吞掉了 commit：$(skel $'echo "$(echo a # it\'s\n)" ; git commit -m x ; echo \\"')"
case "$(skel $'echo "$(echo a # (\n)" ; git push ; echo "x"')" in *"git push"*) ;; *) fail "沒結尾的 \" 之後的 git push 不見：$(skel $'echo "$(echo a # (\n)" ; git push ; echo "x"')" ;; esac
# 註解裡的撇號不是單引號開頭
has_commit $'# it\'s\necho \'x \' ; git commit -m x ; echo \' y\'' || fail "註解撇號讓引號錯位：$(skel $'# it\'s\necho \'x \' ; git commit -m x ; echo \' y\'')"
# 第 3 層的緊貼字片段照樣還原
has_commit $'echo "$(echo "$(echo "$(bash -c x\'; g\\it commit -m x\')")")"' || fail "第 3 層緊貼字片段的 g\\it：$(skel $'echo "$(echo "$(echo "$(bash -c x\'; g\\it commit -m x\')")")"')"
# $$ 後面的 ' 是一般單引號
has_commit $'echo $$\'\\\' ; g\\it commit -m x ; echo \'y\'' || fail "\$\$' 被當成 \$'…'：$(skel $'echo $$\'\\\' ; g\\it commit -m x ; echo \'y\'')"
# (( 之後一行很多 << 也要線性
big="$(perl -e 'print "git commit -m x; (( ", "<<a" x 10900, "\n"')"
t0=$SECONDS; skel "$big" >/dev/null; elapsed=$((SECONDS - t0))
[ "$elapsed" -le 3 ] || fail "(( 之後 10900 個 <<a 骨架花了 ${elapsed} 秒（要線性）"
has_commit "$big" || fail "(( 之後那串 <<a 之前的 git commit 不能不見"
echo "cmd-skeleton ok"
