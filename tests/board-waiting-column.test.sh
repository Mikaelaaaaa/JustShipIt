#!/usr/bin/env bash
# 看板網頁的等待中面板、待指派列的「pane 在 <stage>」、report 待你決定的列。
# 驗收：openspec/changes/me-20261120-1456/specs/board-web/spec.md
# 規則寫在網頁的 inline script 裡，這裡用 node 把函式切出來執行，面板順序看 renderHome 的原始碼。
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
command -v node >/dev/null || fail "需要 node 才能跑等待中面板的網頁測試"

node - "$OPSX_ROOT/herdr-board/web/index.html" <<'JS' || fail "等待中面板網頁規則"
const fs = require('node:fs');
const assert = require('node:assert');
const html = fs.readFileSync(process.argv[2], 'utf8');
const esc = x => String(x == null ? '' : x).replace(/[&<>"]/g, c => ({'&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;'}[c]));
const START = '/* 等待中 start */', END = '/* 等待中 end */';
const s = html.indexOf(START), e = html.indexOf(END);
if (s < 0 || e < s) throw new Error(`index.html 找不到標記 ${START} / ${END}`);
const {holdBadge, paneStage} = new Function('esc', html.slice(s, e) + ';return {holdBadge, paneStage};')(esc);

// 等待中的卡列上有 hold（Examples 每一列）
for (const hold of ['等 CI', '等協調者', '等 other 合併', '等背景工作'])
  assert.ok(holdBadge({hold}).includes(hold), `列上要有 ${hold}`);
assert.strictEqual(holdBadge({hold: null}), '', '沒有 hold 不畫');
assert.ok(!holdBadge({hold: '<b>x</b>'}).includes('<b>'), 'hold 要 escape');

// 待指派列：有 pane 標出 stage，沒派出不標
assert.ok(paneStage({stage: 'grill', dispatch: {pane: 'p1'}}).includes('pane 在 grill'), '有 pane 的 grill 卡');
assert.strictEqual(paneStage({stage: 'apply', dispatch: null}), '', '沒派出的卡沒有 pane 在');

const body = name => { const i = html.indexOf(`function ${name}(`); return html.slice(i, html.indexOf('\nfunction ', i + 1)); };
assert.ok(body('rowRunning').includes('holdBadge(c)'), 'rowRunning 要畫 hold');
assert.ok(body('rowReady').includes('paneStage(c)'), 'rowReady 要畫 pane 在哪一站');

// 面板順序：待處理、進行中、等待中、待指派；沒有等待中的卡時顯示空字
const home = body('renderHome');
const at = t => { const i = home.indexOf(t); assert.ok(i >= 0, `renderHome 要有 ${t}`); return i; };
const order = [at("panel('待處理'"), at("panel('進行中'"), at("panel('等待中'"), at("`待指派 · ")];
assert.deepStrictEqual([...order].sort((a, b) => a - b), order, '面板依序是 待處理、進行中、等待中、待指派');
assert.ok(home.includes("H('等待中')"), '等待中面板取 section 是等待中的卡');
assert.ok(home.includes('沒有在等的工作'), '沒有等待中的卡時顯示 沒有在等的工作');

// report 待你決定的列：標籤、問題、開啟 pane，沒有合併與照建議
assert.ok(/WAIT_BADGE=\{[^}]*'report 待你決定'/.test(html), 'WAIT_BADGE 要有 report 待你決定');
const WAIT_BADGE = new Function(html.slice(html.indexOf('const WAIT_BADGE='), html.indexOf(';', html.indexOf('const WAIT_BADGE=')) + 1) + 'return WAIT_BADGE;')();
const rowAttn = new Function('esc', 'WAIT_BADGE', 'GRANT_OF', 'pendBadge', 'priorityBadge', 'bot', 'since', 'key', 'ui',
  body('rowAttn') + ';return rowAttn;')(esc, WAIT_BADGE, {}, () => '', () => '', () => '', () => '', c => c.slug, {sel: null});
const row = rowAttn({slug: 'm', title: 'm', repo: 'r', mr: {url: 'u', head_sha: 'abc'},
  waiting: {type: 'report 待你決定', question: 'report.md 有留給人決定的項目', options: ['開啟 pane']}});
assert.ok(row.includes('report 待你決定') && row.includes('report.md 有留給人決定的項目'), '列上要有標籤與問題：' + row);
assert.ok(row.includes('data-act="pane"'), '要有開啟 pane：' + row);
assert.ok(!row.includes('data-act="merge"'), '不能有合併按鈕');
assert.ok(!row.includes('data-act="stop"'), '不能有停止按鈕：' + row);
assert.ok(!row.includes('照建議'), '不能有照建議');

// 待指派列：已派出的卡給開啟 pane、不給指派；沒派出的照舊給指派
const rowReady = new Function('esc', 'KIND', 'pendBadge', 'priorityBadge', 'since', 'stoppedLine', 'key', 'ui', 'paneStage',
  body('rowReady') + ';return rowReady;')(esc, {}, () => '', () => '', () => '', () => '', c => c.slug, {sel: null}, paneStage);
const live = rowReady({slug: 'g', title: 'g', repo: 'r', kind: 'dev', stage: 'grill', dispatch: {pane: 'p1'}});
assert.ok(live.includes('pane 在 grill') && live.includes('data-act="pane"'), '已派出的卡有 pane 在 grill 與開啟 pane：' + live);
assert.ok(!live.includes('data-act="dispatch"'), '已派出的卡不給指派：' + live);
const idle = rowReady({slug: 'y', title: 'y', repo: 'r', kind: 'dev', stage: 'apply', dispatch: null});
assert.ok(idle.includes('data-act="dispatch"') && !idle.includes('pane 在'), '沒派出的卡照舊指派：' + idle);
JS
echo ok
