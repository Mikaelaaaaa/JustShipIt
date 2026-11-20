# git 指令的比對樣式，hooks/security-guard.sh 與 hooks/opsx-grant-gate.sh 共用。只定義變數，不讀 stdin、不需要 python。
# git 與子命令之間可以夾全域選項：-C <dir>、-c k=v、--git-dir[=]x、--work-tree[=]x、--no-pager 這類旗標。
GIT_TOK='([^[:space:]\\]|\\.)+'
GIT_GOPT="(-C|-c|--git-dir|--work-tree|--namespace|--super-prefix|--config-env|--exec-path)[[:space:]]+${GIT_TOK}|--[a-z][a-z-]*(=${GIT_TOK})?|-[A-Za-z]"
# 後面直接接子命令名，例如 "${GIT_PRE}commit"
GIT_PRE="git(([[:space:]]+(${GIT_GOPT}))*)[[:space:]]+"
GIT_PUSH="${GIT_PRE}push"
