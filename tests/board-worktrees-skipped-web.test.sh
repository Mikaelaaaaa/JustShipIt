#!/usr/bin/env bash
# 看板頂端的錯誤紅條不列 collect 跳過的 worktree（specs/board-web「錯誤紅條不顯示 collect 跳過的 worktree」）。
# 從 index.html 切出 renderTop，用假的 $ 與 stub 直接執行。
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
command -v node >/dev/null || fail "需要 node 才能跑紅條測試"

node - "$OPSX_ROOT/herdr-board/web/index.html" <<'JS' || fail "紅條列了跳過的 worktree"
const fs = require('node:fs');
const assert = require('node:assert');
const html = fs.readFileSync(process.argv[2], 'utf8');
const START = 'function renderTop', END = '/* 篩選列只在內容變了才重寫';
const s = html.indexOf(START), e = html.indexOf(END);
if (s < 0) throw new Error(`index.html 找不到標記 ${START}`);
if (e < s) throw new Error(`index.html 找不到 ${START} 之後的標記 ${END}`);

const top = (data) => {
  const els = {};
  const $ = (sel) => els[sel] || (els[sel] = {innerHTML: '', textContent: '', title: '', hidden: false, classList: {toggle() {}}});
  const renderTop = new Function('$', 'data', 'fCards', 'waitsOnYou', 'fArchived', 'NAV', 'href', 'stampText', 'coordHtml', 'syncTitle', 'esc',
    html.slice(s, e) + ';return renderTop;')($, data, () => [], () => false, () => [], [], () => '#', () => '', () => '', () => '', String);
  return {render: () => renderTop({page: 'board'}), errors: $('#errors')};
};

const onlySkipped = top({generated_at: 'x', errors: [], worktrees_skipped: ['acme-api-wt', 'a-wt']});
onlySkipped.render();
assert.strictEqual(onlySkipped.errors.hidden, true, '只有跳過的 worktree 時紅條要隱藏');
assert.ok(!onlySkipped.errors.innerHTML.includes('跳過 worktree 目錄'), '紅條不能有跳過 worktree 目錄');

const withErr = top({generated_at: 'x', errors: [{source: 'herdr', message: 'herdr agent list 失敗'}], worktrees_skipped: ['a-wt']});
withErr.render();
withErr.render();
assert.strictEqual(withErr.errors.hidden, false, '真的錯誤要顯示');
assert.strictEqual(withErr.errors.innerHTML, '<span>herdr：herdr agent list 失敗</span>', '只有那條 herdr 錯誤，畫兩次不重複');
JS
