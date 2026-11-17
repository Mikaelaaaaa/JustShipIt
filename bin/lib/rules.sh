#!/usr/bin/env bash
# 每張卡依模式要遵守的行為規則，一個來源：router hook 每句 prompt 注入（claude），
# dispatch 渲染進 codex worktree 的 AGENTS.md（bin/lib/agents-md.sh）。改這裡兩邊一起變。
# 不含前導 ` · `；段與段用 ` · ` 隔開，AGENTS.md 依它拆成條列。

rule_autopilot() { # <repo 根目錄>：測試那段看它有沒有 tests/run.sh
  [ -n "${1:-}" ] || { echo "rule_autopilot: 缺 repo 根目錄參數" >&2; return 1; }
  printf '%s' 'autopilot：要問人的事寫 gates.md（type: approval | decision；要使用者在終端機跑指令的另加 needs: run；type: approval 的要寫 action:，值照 hook deny 訊息裡的抄；type: decision 的題要等別張卡合進 main 才能做的，另加 waits-on: <卡名>，coordinate 只憑這一行停 pane），不用 AskUserQuestion、不在 pane 問；gate 一律由使用者答，協調者不代答；不是產品取捨、也可逆的題採 Recommended，記「自動採用」；操作類的題（等 subagent、等背景工作、要不要跑全套測試）不開 gate，照建議做、記「自動採用」 · Bash 會被 dontAsk 拒的寫法：for / while（不寫迴圈）、把命令替換的結果賦值給變數再展開、命令替換裡放 pipe、{ } 群組、source 或 .、bash -c 跑多段、印 $?；一個 Bash 呼叫做一件事，讀多個檔用 Read 或 cat a b c，記決定用 opsx log，路徑寫字面絕對路徑 · worktree 裡沒有 `openspec/`（不進 git）：openspec 指令寫成 cd <主 checkout 絕對路徑> && openspec …，下一個指令先 cd <worktree 根> 回來（cd 會留到後面每個 Bash 呼叫，測試、opsx、git、router 都看 cwd），卡的檔案讀寫主 checkout 的 openspec/changes/<slug>/ · '
  if [ -f "$1/tests/run.sh" ]; then rule_tests_runsh; else rule_tests_repo; fi
  if [ -f "$1/package.json" ] && grep -q '"docs:api"' "$1/package.json"; then
    printf '%s' ' · `pnpm docs:api` 要單獨下：先單獨 cd 到 worktree 根（剛跑過 openspec 的話 cwd 還在主 checkout，產生器會在沙箱外寫進主 checkout 的檔案），再單獨下 `pnpm docs:api`，前面不接 `cd … &&`、後面不接 pipe（沙箱排除只比對單獨下的指令，接了就在沙箱裡跑、tsx 開 IPC socket 回 listen EPERM），跑完在 worktree 看 git status；被 dontAsk 拒就開 needs: run gate，不換寫法重試'
  fi
}

# 測試段兩種寫法分開放：router 依 repo 根挑一種，AGENTS.md 兩種都列（派工後分支可能增刪 tests/run.sh）
rule_tests_runsh() {
  printf '%s' '跑測試一律 bash tests/run.sh <檔名過濾>（只認 `tests/run.sh` 這個檔名，不看內容），指令前不加 `VAR=…` 或 `export`（前綴環境變數對不到 dontAsk 的 Bash(bash tests/:*)）'
}

# TEST_DATABASE_URL 例外對應 bin/lib/launch.sh 允許清單裡帶前綴的兩個形狀，清單改了這句跟著改
rule_tests_repo() {
  printf '%s' '跑測試用這個 repo 的指令（先看 CLAUDE.md，再看 package.json / pyproject），寫成 dontAsk 允許清單有的形狀：pnpm test、pnpm vitest、pytest、uv run、go test；指令前不加 `VAR=…` 或 `export`，`TEST_DATABASE_URL=` 接 pnpm test / pnpm vitest 除外；清單外的測試指令被 dontAsk 拒就開 needs: run gate，不換寫法重試'
}

rule_interactive() {
  printf '%s' 'interactive：要授權就直接問，不寫 gate'
}
