#!/usr/bin/env bash
# README 是公開首頁：置中 logo 與英文 tagline、必備段落、看板截圖、不外洩、授權段只連 LICENSE；安裝細節搬到 docs/setup.md 不遺失。
# 驗收：openspec/specs/readme-landing/spec.md
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
README="$OPSX_ROOT/README.md"
SETUP="$OPSX_ROOT/docs/setup.md"
assert_file "$README"
top="$(sed -n '1,/^## /p' "$README")"

# --- Requirement：README 開頭是置中 logo 與英文 tagline ---
for svg in docs/assets/brand/justshipit-logo-light.svg docs/assets/brand/justshipit-logo-dark.svg; do
  [ -f "$OPSX_ROOT/$svg" ] || fail "缺 $svg"
  printf '%s\n' "$top" | grep -qF "$svg" || fail "開頭沒引用 $svg"
done
printf '%s\n' "$top" | grep -qF '<picture>' || fail "開頭 logo 沒用 <picture>"
printf '%s\n' "$top" | grep -qF 'prefers-color-scheme: dark' || fail "開頭 logo 沒依 prefers-color-scheme 切換"
printf '%s\n' "$top" | grep -qF 'alt="JustShipIt"' || fail "開頭 logo 的 alt 不是 JustShipIt"
tagline="$(printf '%s\n' "$top" | grep -m1 -F '<p align="center"><b>' | sed -E 's#.*<b>(.*)</b>.*#\1#')"
[ -n "$tagline" ] || fail "logo 下沒有置中的 tagline"
printf '%s' "$tagline" | LC_ALL=C grep -q '[^ -~]' && fail "tagline 含非 ASCII 字元：$tagline"
badges="$(grep -o 'img\.shields\.io/[^"]*' "$README")"
[ "$(printf '%s' "$badges" | grep -c .)" -le 1 ] || fail "README 只能放一個 license badge：$badges"
[ -z "$badges" ] || printf '%s\n' "$badges" | grep -qF 'img.shields.io/badge/license-MIT' || fail "README 的 badge 不是 license：$badges"
printf '%s\n' "$top" | grep -qF 'Early preview' || fail "開頭沒有 Early preview 狀態標示"
! grep -qiE 'production[- ]ready' "$README" || fail "README 不該宣稱 production-ready"
n="$(printf '%s\n' "$top" | grep -c '^- ')"
[ "$n" -ge 3 ] && [ "$n" -le 4 ] || fail "開頭的差異清單要 3～4 點，現在 $n 點"
n="$(awk '/^## .*解決什麼問題$/{f=1;next} /^## /{f=0} f' "$README" | grep -o '。' | wc -l)"
[ "$n" -le 3 ] || fail "解決什麼問題段要兩三句，現在 $n 句"
# 參考專案名只存 sha256，名字本身不進公開 repo
python3 -I -c 'import hashlib,re,sys; bad="db0ee43ab2f9353ebd68b373591d62bc827688c6e56f95e89fcbedc2de7b1133"; sys.exit(any(hashlib.sha256(w.encode()).hexdigest()==bad for w in set(re.findall(r"[a-z0-9]+", open(sys.argv[1], encoding="utf-8").read().lower()))))' "$README" || fail "README 提到參考專案名"

# --- Requirement：README 含首頁必備段落，依序 ---
want=(解決什麼問題 怎麼運作 功能 安裝 常用指令 安全模型 文件 狀態 參與開發 授權)
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
quick="$(awk '/^## .*安裝$/{f=1;next} /^## /{f=0} f' "$README")"
printf '%s\n' "$quick" | grep -qE '^(bash <plugin root>/bin/)?opsx init --global$' || fail "安裝段沒有 opsx init --global 這一行"
printf '%s\n' "$quick" | grep -qxF 'opsx init' || fail "安裝段沒有單獨一行 opsx init"
printf '%s\n' "$quick" | grep -qF 'docs/setup.md' || fail "安裝段沒連到 docs/setup.md"
printf '%s\n' "$quick" | grep -qF 'openspec' || fail "安裝段前置條件沒提 openspec CLI"
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
printf '%s\n' "$top" | grep -qF 'docs/assets/board-web-framed.png' || fail "開頭主圖不是 docs/assets/board-web-framed.png"
for w in 舊版 新版 設計預覽 實作中 現有版本; do
  ! grep -qF -- "$w" "$README" || fail "README 含看板版本字眼：$w"
done
feat="$(awk '/^## .*功能$/{f=1;next} /^## /{f=0} f' "$README")"
printf '%s\n' "$feat" | grep -qF '虛構的示範資料' || fail "功能段沒標明截圖是虛構的示範資料"
for img in docs/assets/board-web-framed.png docs/assets/drawer-web-framed.png docs/assets/card-detail-web-framed.png docs/assets/changes-web-framed.png docs/assets/opsx-tui-demo-framed.png; do
  [ -f "$OPSX_ROOT/$img" ] || fail "缺 $img"
  printf '%s\n' "$feat" | grep -qF "$img" || fail "功能段沒引用 $img"
done

# --- Requirement：流程段寫出自動開發的角色 ---
# 只看說明文字：流程圖裡的節點名不算寫出角色
flow="$(awk '/^## .*怎麼運作$/{f=1;next} /^## /{f=0} f&&/^```/{c=!c;next} f&&!c' "$README")"
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
