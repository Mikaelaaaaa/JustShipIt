#!/usr/bin/env bash
# README 是公開首頁：首行 tagline、必備段落、看板截圖、不外洩、授權段只連 LICENSE；安裝細節搬到 docs/setup.md 不遺失。
# 驗收：openspec/specs/readme-landing/spec.md
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
README="$OPSX_ROOT/README.md"
SETUP="$OPSX_ROOT/docs/setup.md"
assert_file "$README"

# --- Requirement：README 首行是英文 tagline ---
[ "$(sed -n '1p' "$README")" = '# JustShipIt' ] || fail "README 第一行不是 # JustShipIt"
tagline="$(sed -n '2,$p' "$README" | grep -m1 -v '^[[:space:]]*$')"
[ -n "$tagline" ] || fail "標題後沒有 tagline"
printf '%s' "$tagline" | LC_ALL=C grep -q '[^ -~]' && fail "tagline 含非 ASCII 字元：$tagline"

# --- Requirement：README 含首頁必備段落，依序 ---
want=(為什麼做 快速開始 示範 功能重點 流程 看板 常用指令 安全模型 安裝 文件 狀態 參與開發 授權)
bare="$(grep '^## ' "$README" | grep -vE '^## <a id="[a-z0-9-]+"></a>' | head -1)"
[ -z "$bare" ] || fail "二級標題沒有 anchor：$bare"
got="$(grep '^## ' "$README" | sed -E 's/^## (<a id="[a-z0-9-]+"><\/a>)?//')"
last=0
for h in "${want[@]}"; do
  n="$(printf '%s\n' "$got" | grep -nxF -- "$h" | head -1 | cut -d: -f1)"
  [ -n "$n" ] || fail "README 少二級標題：$h"
  [ "$n" -gt "$last" ] || fail "README 二級標題順序不對：$h"
  last=$n
done
quick="$(awk '/^## .*快速開始$/{f=1;next} /^## /{f=0} f' "$README")"
printf '%s\n' "$quick" | grep -qE '^(bash <plugin root>/bin/)?opsx init --global$' || fail "快速開始沒有 opsx init --global 這一行"
printf '%s\n' "$quick" | grep -qxF 'opsx init' || fail "快速開始沒有單獨一行 opsx init"
printf '%s\n' "$quick" | grep -qF 'docs/setup.md' || fail "快速開始沒連到 docs/setup.md"
printf '%s\n' "$quick" | grep -qF 'openspec' || fail "快速開始前置條件沒提 openspec CLI"
! grep -qF 'ogulcancelik' "$README" || fail "README 含查無佐證的 herdr 外部連結"
grep -qF 'references/work-split.md' "$README" || fail "README 沒連到 references/work-split.md"

# --- Requirement：專案顯示名稱是 JustShipIt ---
BOARD="$OPSX_ROOT/herdr-board/web/index.html"
for f in "$README" "$SETUP"; do
  grep -qF 'Mikaelaaaaa/JustShipIt' "$f" || fail "$f 沒有 Mikaelaaaaa/JustShipIt"
  ! grep -qF 'Mikaelaaaaa/opsx-workflow' "$f" || fail "$f 還有舊 repo 名 Mikaelaaaaa/opsx-workflow"
done
! grep -qF 'opsx 看板' "$README" || fail "README 還把看板叫 opsx 看板"
grep -qF '<title>JustShipIt' "$BOARD" || fail "看板 <title> 沒改成 JustShipIt"
grep -qF '</svg>JustShipIt</div>' "$BOARD" || fail "看板 brand 沒改成 JustShipIt"

# --- Requirement：README 把看板當現況寫 ---
sed -n '1,/^## /p' "$README" | grep -qF 'docs/assets/board-web.png' || fail "開頭圖不是看板截圖 docs/assets/board-web.png"
for w in 舊版 新版 設計預覽 實作中 現有版本; do
  ! grep -qF -- "$w" "$README" || fail "README 含看板版本字眼：$w"
done
demo="$(awk '/^## .*示範$/{f=1;next} /^## /{f=0} f' "$README")"
printf '%s\n' "$demo" | grep -qF '虛構的示範資料' || fail "示範段沒標明示範資料是虛構的"
for img in docs/assets/board-web.png docs/assets/card-detail-web.png docs/assets/changes-web.png docs/assets/opsx-tui-demo.png; do
  [ -f "$OPSX_ROOT/$img" ] || fail "缺 $img"
  printf '%s\n' "$demo" | grep -qF "$img" || fail "示範段沒引用 $img"
done

# --- Requirement：README 引用 TUI 截圖 ---
TUI_PNG="docs/assets/opsx-tui-demo.png"
[ -f "$OPSX_ROOT/$TUI_PNG" ] || fail "缺 $TUI_PNG"
awk '/^## .*示範$/{f=1;next} /^## /{f=0} f' "$README" | grep -qF "$TUI_PNG" || fail "示範段沒引用 TUI 截圖 $TUI_PNG"

# --- Requirement：流程段寫出自動開發的角色 ---
# 只看說明文字：流程圖裡的節點名不算寫出角色
flow="$(awk '/^## .*流程$/{f=1;next} /^## /{f=0} f&&/^```/{c=!c;next} f&&!c' "$README")"
for cmd in 'opsx drive' 'opsx coordinate' 'opsx lead'; do
  printf '%s\n' "$flow" | grep -qF -- "$cmd" || fail "流程段沒提 $cmd"
done
# 角色說明裡本來就有 gate、合併 字樣，所以認人要做的那兩條的字樣
printf '%s\n' "$flow" | grep -qF '回 gate' || fail "流程段沒寫人要回 gate"
printf '%s\n' "$flow" | grep -qF '合併永遠留給人' || fail "流程段沒寫人要合併"

# --- Requirement：不外洩且授權段只連到 LICENSE ---
# 禁用字樣拼接寫：這個檔自己不能被下面的追蹤檔掃描命中
leak='ts''g-navigator|agen''tory|10\.65\.|172\.21\.|59\.120\.|mikaela''_lin|/Users/mikae''la|spar''k[12]|gmt''c|agn''etory|192\.168\.|10\.66\.|newre''tail|srv19[0-9]|a60''00|台''鋼'
! grep -qiE -- "$leak|/Users/|~/code" "$README" || fail "README 含禁用字樣：$(grep -oiE -- "$leak|/Users/|~/code" "$README" | head -1)"
for s in 'MIT License' 'Apache License' 'licensed under' 'GPL' 'SPDX-License-Identifier'; do
  ! grep -qiF -- "$s" "$README" || fail "README 宣稱授權：$s"
done
! awk '/^## .*狀態$/{f=1;next} /^## /{f=0} f' "$README" | grep -qF '補 LICENSE' || fail "LICENSE 已存在，狀態段不該再列補 LICENSE"
awk '/^## .*授權$/{f=1;next} /^## /{f=0} f' "$README" | grep -qF '[MIT](LICENSE)' || fail "授權段沒連到 LICENSE"

# --- Requirement：LICENSE 檔與 plugin.json 一致 ---
assert_file "$OPSX_ROOT/LICENSE"
[ "$(sed -n '1p' "$OPSX_ROOT/LICENSE")" = 'MIT License' ] || fail "LICENSE 第一行不是 MIT License"
meta="$(python3 -I -c 'import json,sys; m=json.load(open(sys.argv[1])); print(m["license"]); print(m["author"]["name"])' "$OPSX_ROOT/.claude-plugin/plugin.json")"
[ "$(printf '%s\n' "$meta" | sed -n '1p')" = MIT ] || fail "plugin.json 的 license 不是 MIT"
grep -qF "Copyright (c)" "$OPSX_ROOT/LICENSE" || fail "LICENSE 沒有 Copyright (c)"
grep -qF -- "$(printf '%s\n' "$meta" | sed -n '2p')" "$OPSX_ROOT/LICENSE" || fail "LICENSE 的著作權人不是 plugin.json 的 author.name"

# --- Requirement：repo 追蹤檔不含公司名、內網主機與個人路徑 ---
hits="$(git -C "$OPSX_ROOT" grep -niE -- "$leak" -- . ':!docs/assets' | head -20)"
[ -z "$hits" ] || fail "追蹤檔含禁用字樣：
$hits"
# /Users/ 底下只准中性名字（dev、me、you）
hits="$(git -C "$OPSX_ROOT" grep -noE '/Users/[A-Za-z0-9_.-]+' -- . ':!docs/assets' ':!tests/readme-landing.test.sh' | grep -vE ':/Users/(dev|me|you)$' | head -20)"
[ -z "$hits" ] || fail "追蹤檔含非中性的 /Users/ 路徑：
$hits"

# --- Requirement：安裝細節搬到 docs/setup.md 不遺失 ---
assert_file "$SETUP"
for k in 'templates/settings.opsx.json' 'grants.toml' 'opsx-protected' 'coordinator-settings.json' 'opsx init --check' 'com.opsx.sync' 'opsx drop' 'security-guard.sh' 'claude plugin update' 'openspec'; do
  grep -qF -- "$k" "$SETUP" || fail "docs/setup.md 少了 $k"
done
echo ok
