#!/usr/bin/env bash
# 看板的等級徽章、總覽各 repo 的 milestone 小字與進度分類篩選（workplan-priority/priority-board「卡顯示等級」，specs/board-pages「總覽」「篩選 popover 與 chips」）。
# 顯示邏輯寫在網頁的 inline script 裡，這裡用 node 把 priorityBadge 與進度相關的函式從 index.html 切出來直接執行。
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
command -v node >/dev/null || fail "需要 node 才能跑等級徽章測試"

TZ=Asia/Taipei node - "$OPSX_ROOT/herdr-board/web/index.html" <<'JS' || fail "等級徽章與進度列"
const fs = require('node:fs');
const assert = require('node:assert');
const html = fs.readFileSync(process.argv[2], 'utf8');
const START = 'const PRIO_BADGE=', END = '/* ---------- 範圍';
const s = html.indexOf(START), e = html.indexOf(END);
if (s < 0) throw new Error(`index.html 找不到標記 ${START}`);
if (e < s) throw new Error(`index.html 找不到 ${START} 之後的標記 ${END}`);
const esc = s => String(s == null ? '' : s).replace(/[&<>"]/g, c => ({'&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;'}[c]));
// 進度行的時間用紀錄 tab 那段的 hhmm，一起切進來
const h0 = html.indexOf('const hhmm=');
if (h0 < 0) throw new Error('index.html 找不到 const hhmm=');
const hhmmSrc = html.slice(h0, html.indexOf('\n', h0));
const {priorityBadge, toggleProgressClass, notDispatchedNames, PROGRESS_LABEL, PRIO_HINT} = new Function('esc', hhmmSrc + html.slice(s, e) + ';return {priorityBadge, toggleProgressClass, notDispatchedNames, PROGRESS_LABEL, PRIO_HINT};')(esc);
// 進度分類的篩選是篩選條件的 pc（specs/board-pages「篩選 popover 與 chips」）：篩選段一起切進來
const F0 = html.indexOf('/* 篩選 start */'), F1 = html.indexOf('/* 篩選 end */');
if (F0 < 0 || F1 < F0) throw new Error('index.html 找不到標記 篩選 start / end');
const {emptyF, matchF, facetOf, chipsHtml, parseF, qs} = new Function('esc', html.slice(F0, F1) + ';return {emptyF, matchF, facetOf, chipsHtml, parseF, qs};')(esc);

// 改等級的提示：等級只排還沒派出去的卡，在跑的卡不受影響
assert.ok(PRIO_HINT.includes('還沒派出去') && PRIO_HINT.includes('不會') && PRIO_HINT.includes('被停'), `提示文字：${PRIO_HINT}`);
const ctl = html.slice(html.indexOf('function prioCtl'), html.indexOf('function prioCtl') + 1200);
assert.ok((ctl.match(/PRIO_HINT/g) || []).length >= 2, `改等級按鈕與編輯列都要帶提示：${ctl}`);

// 徽章與理由
const p0 = {repo: 'r', slug: 'a', priority: {level: 'P0', reason: 'P0：security（附證據）', overridden: false}};
const row = priorityBadge(p0);
assert.match(row, /class="badge[^"]*"[^>]*>P0</, `卡片要有 P0 徽章：${row}`);
assert.ok(!row.includes('改'), `沒覆寫不標「改」：${row}`);
assert.ok(priorityBadge(p0, true).includes('P0：security（附證據）'), `展開區要有理由：${priorityBadge(p0, true)}`);
assert.ok(!row.includes('prio-why'), `列上理由只在 title，展開才顯示：${row}`);

// 覆寫標記
const over = {repo: 'r', slug: 'b', priority: {level: 'P1', reason: 'P1：使用者：等客戶', overridden: true}};
assert.match(priorityBadge(over), />P1<.*>改</, `覆寫的徽章旁有「改」：${priorityBadge(over)}`);

// 沒有等級
assert.strictEqual(priorityBadge({repo: 'r', slug: 'c', priority: null}), '');
assert.strictEqual(priorityBadge({repo: 'r', slug: 'c', priority: null}, true), '');

// 理由跳脫
assert.ok(!priorityBadge({priority: {level: 'P2', reason: '<b>x</b>', overridden: false}}, true).includes('<b>x'), '理由要跳脫');

const text = h => h.replace(/<[^>]*>/g, '');
const p = {milestone: '1.0', goal: '能開單出貨', remaining: 5, mergeable: 1, testing: 1, developing: 1, waiting_on_you: 1, not_dispatched: 1, not_dispatched_planned: ['web-x'], at: '2026-11-11T14:30:00+08:00'};
// 舊的 milestoneLine 與首頁進度列（progressLine、可點的進度數字）已移除，進度分類改用篩選 popover 的「進度」
assert.ok(!html.includes('milestoneLine') && !html.includes('還差'), 'index.html 不再畫還差幾張');
assert.ok(!html.includes('function progressLine(') && !html.includes('data-act="progress-filter"'), '首頁進度列已移除');
// 總覽各 repo 格：repo 名右側小字寫 milestone 剩幾張，不再列整串進度連結（點進度分類改用篩選 popover 的「進度」）
const msSrc = html.slice(html.indexOf('function milestoneHint('), html.indexOf('\n}', html.indexOf('function milestoneHint(')) + 2);
const milestoneHint = new Function('esc', msSrc + 'return milestoneHint;')(esc);
assert.strictEqual(milestoneHint({...p, milestone: '團隊邀請', remaining: 4}), `<small class="ms" title="${esc(p.goal)}">團隊邀請 剩 4</small>`);
assert.strictEqual(milestoneHint({...p, milestone: null}), '', '沒有 milestone 不寫');
assert.strictEqual(milestoneHint(undefined), '', '舊 collect 沒有 progress');
assert.ok(html.includes('${esc(r)}${milestoneHint((data.progress||{})[r])}</span>'), '總覽各 repo 格在 repo 名右側呼叫 milestoneHint');
assert.ok(!html.includes('<div class="milestones">'), '各 repo 格不再列進度連結串');


// 進度分類篩選（specs/board-pages「篩選 popover 與 chips」）：篩選條件的 pc，chip 可點掉
const mk = (slug, progress_class, more) => ({repo: 'r', slug, title: slug, kind: 'dev', priority: null, dispatch: null, waiting: null, progress_class, ...more});
const cards = [mk('a', 'mergeable'), mk('b', 'testing'), mk('c', null)];
const pick = f => cards.filter(c => matchF(f, facetOf(c), [])).map(c => c.slug);
const LAB = {kind: {}, pc: PROGRESS_LABEL};
let cls = toggleProgressClass(null, 'mergeable');
assert.strictEqual(cls, 'mergeable');
assert.deepStrictEqual(pick({...emptyF(), pc: cls}), ['a'], '只剩 mergeable');
const chip = chipsHtml({...emptyF(), pc: cls}, 'board', LAB);
assert.ok(text(chip).includes('進度：可合併') && chip.includes('data-frm="pc"'), `篩選 chip 可點掉：${chip}`);
// 寫進 hash 再讀回；不認得的分類被忽略
const known = {repos: ['r'], wss: [], kinds: ['dev'], pcs: Object.keys(PROGRESS_LABEL)};
assert.strictEqual(parseF(qs({...emptyF(), pc: cls}).slice(1), known).pc, 'mergeable', 'pc 寫進 hash 再讀回');
assert.strictEqual(parseF('pc=nope', known).pc, null, '不認得的分類忽略');
// 換一類直接切過去
assert.strictEqual(toggleProgressClass('mergeable', 'testing'), 'testing');
// 再點一次取消
cls = toggleProgressClass(cls, 'mergeable');
assert.strictEqual(cls, null);
assert.deepStrictEqual(pick({...emptyF(), pc: cls}), ['a', 'b', 'c'], '取消後三張都回來');
assert.ok(chipsHtml({...emptyF(), pc: cls}, 'board', LAB).includes('hidden'), '取消後沒有篩選 chip');

// 篩還沒派：列出範圍內各 repo 還沒建殼的項目名
assert.deepStrictEqual(notDispatchedNames({r: p, s: {...p, not_dispatched_planned: ['s-y']}}, ['r']), ['web-x']);
assert.deepStrictEqual(notDispatchedNames({r: p, s: {...p, not_dispatched_planned: ['s-y']}}, ['r', 's', 't']), ['web-x', 's-y']);
assert.deepStrictEqual(notDispatchedNames(undefined, ['r']), []);
assert.ok(html.includes("F.pc==='not_dispatched'?notDispatchedNames(data.progress,scopeRepos())"), '篩還沒派時待指派欄畫還沒建殼的項目');

// 篩選中各欄的卡：帶 session 的主 change 卡照常出現，收件匣裡符合的卡也在；範圍條件同時套用
const home = [
  mk('run', 'developing', {section: '進行中'}),
  mk('in-session', 'developing', {section: '進行中', session: 'r/feat'}),
  mk('other', 'testing', {section: '進行中'}),
  mk('ready', 'not_dispatched', {section: '待指派'}),
  mk('fresh', 'not_dispatched', {section: '收件匣'}),
  mk('elsewhere', 'developing', {section: '進行中', repo: 's'}),
];
const inSec = (f, name) => home.filter(c => c.section === name && matchF(f, facetOf(c), [])).map(c => c.slug);
assert.deepStrictEqual(inSec({...emptyF(), pc: 'developing'}, '進行中'), ['run', 'in-session', 'elsewhere'], '帶 session 的卡篩選中要出現');
assert.deepStrictEqual(inSec({...emptyF(), pc: 'not_dispatched'}, '待指派'), ['ready']);
assert.deepStrictEqual(inSec({...emptyF(), pc: 'not_dispatched'}, '收件匣'), ['fresh'], '收件匣裡還沒派的卡要畫');
assert.deepStrictEqual(inSec({...emptyF(), pc: 'developing', scope: 'repo', srepo: 'r'}, '進行中'), ['run', 'in-session'], '篩選中範圍篩選同時套用');
assert.ok(html.includes('const fCards=()=>liveCards().filter(c=>matchF(F,facetOf(c),data.scopes));'), '看板的卡都經 matchF（含範圍與進度分類）');
JS
