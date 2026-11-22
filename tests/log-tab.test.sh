#!/usr/bin/env bash
# 看板紀錄 tab：只畫最新 200 列、載入更多、換篩選回到 200、內容沒變不重寫 #view（specs/board-log「紀錄 tab」）。
# 從 herdr-board/web/index.html 切出「紀錄 tab」那段 inline script，用 node 執行。
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
command -v node >/dev/null || fail "需要 node 才能跑紀錄 tab 測試"

node - "$OPSX_ROOT/herdr-board/web/index.html" <<'JS' || fail "紀錄 tab 案例失敗"
const fs = require('node:fs');
const assert = require('node:assert');

const src = fs.readFileSync(process.argv[2], 'utf8');
const START = '/* ---------- 紀錄 tab', END = '/* ---------- 離開期間 banner';
const a = src.indexOf(START), b = src.indexOf(END);
if (a < 0 || b < 0) throw new Error('index.html 找不到切片標記：' + [a < 0 ? START : '', b < 0 ? END : ''].filter(Boolean).join('、'));
const slice = src.slice(a, b);
const esc = s => String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');

function load(tl, evPass) {
  // 跟 index.html 的 ui 字面值一樣沒有 logLimit：初始值要由切片自己設；事件類別篩選是篩選條件的 ev
  const ui = {};
  const F = { ev: 'all' };
  const f = new Function('ui', 'F', 'tl', 'tlErr', 'esc', 'evPass',
    slice + ';return {renderLog, setView, logMore, setLogFilter, syncLogLimit, LOG_PAGE};');
  return { ui, F, ...f(ui, F, tl, '', esc, evPass || (() => true)) };
}
// 切片外的接線：#view 只經 setView 寫；render() 與 renderContent() 都用 setView，並先把 hash 的篩選條件交給 syncLogLimit
{
  assert.ok(!/\$\('#view'\)\.innerHTML\s*=/.test(src), "index.html 不該直接寫 $('#view').innerHTML");
  for (const name of ['function render(){', 'function renderContent(){']) {
    const r = src.indexOf(name);
    assert.ok(r >= 0, 'index.html 找不到 ' + name);
    const body = src.slice(r, src.indexOf('\n}', r));
    assert.ok(body.includes("setView($('#view'),"), name + ' 要經 setView 寫 #view');
    assert.ok(body.indexOf('syncLogLimit(query)') >= 0 && body.indexOf('syncLogLimit(query)') < body.indexOf("setView($('#view'),"), name + ' 要在畫之前 syncLogLimit');
  }
  // 範圍、repo、時間等條件都在紀錄頁的篩選裡：renderLog 每一列都過 evPass
  assert.ok(src.includes('const evPass=e=>inTime(F,e.ts,Date.now())&&matchF(F,facetOfEvent(e),data.scopes);'), 'evPass 套時間與篩選條件');
}
// n 列，由新到舊，每天 10 列；偶數列是「你」回的
function events(n) {
  const t0 = Date.parse('2026-11-06T23:00:00+08:00');
  return Array.from({ length: n }, (_, i) => ({
    ts: new Date(t0 - i * 2.4 * 3600e3).toISOString(), repo: 'a', slug: 'x', archived: false,
    who: i % 2 ? 'agent' : '你', tag: '已決定', text: 'row-' + i + '-end', evidence: '', source: 'decisions',
  }));
}
const rows = h => (h.match(/<div class="ev">/g) || []).length;

// 只畫最新 200 列
{
  const t = load({ events: events(450), errors: [] });
  assert.strictEqual(t.LOG_PAGE, 200);
  assert.strictEqual(t.ui.logLimit, 200, '切片要把 ui.logLimit 設成 200');
  const h = t.renderLog();
  assert.strictEqual(rows(h), 200);
  assert.ok(h.includes('row-0-end') && h.includes('row-199-end') && !h.includes('row-200-end'), '應是最新的 200 列');
  assert.ok(h.includes('data-act="log-more"'), '要有載入更多');
  assert.ok(h.includes('還有 250 列'), '要寫還剩幾列');
}
// 載入更多
{
  const t = load({ events: events(450), errors: [] });
  t.logMore(); assert.strictEqual(rows(t.renderLog()), 400);
  t.logMore(); const h = t.renderLog();
  assert.strictEqual(rows(h), 450);
  assert.ok(!h.includes('data-act="log-more"'), '全畫完不該有載入更多');
}
// 不到 200 列沒有載入更多；剛好 200 列也沒有
for (const n of [150, 200]) {
  const t = load({ events: events(n), errors: [] });
  const h = t.renderLog();
  assert.strictEqual(rows(h), n);
  assert.ok(!h.includes('data-act="log-more"'), n + ' 列不該有載入更多');
}
// 篩選後才算 200：450 列裡「你」回的有 225 列
{
  const t = load({ events: events(450), errors: [] });
  t.setLogFilter('you');
  const h = t.renderLog();
  assert.strictEqual(rows(h), 200);
  assert.ok(h.includes('還有 25 列'));
}
// 換篩選回到 200
{
  const t = load({ events: events(450), errors: [] });
  t.logMore(); assert.strictEqual(rows(t.renderLog()), 400);
  t.setLogFilter('you'); t.setLogFilter('all');
  assert.strictEqual(t.ui.logLimit, 200);
  assert.strictEqual(rows(t.renderLog()), 200);
}
// 換範圍（或任何篩選條件，hash 的 ? 之後變了）回到 200；條件沒變時不重設
{
  const t = load({ events: events(450), errors: [] });
  t.syncLogLimit('');
  t.logMore(); t.syncLogLimit('');
  assert.strictEqual(t.ui.logLimit, 400, '條件沒變不重設');
  t.syncLogLimit('sc=ws%3Adevelop');
  assert.strictEqual(t.ui.logLimit, 200, '換範圍回到 200');
  t.logMore(); t.syncLogLimit('sc=ws%3Adevelop&t=today');
  assert.strictEqual(t.ui.logLimit, 200, '換時間回到 200');
}
// 篩選條件（evPass）套用之後才算 200 列：同步事件被範圍條件擋掉
{
  const ev = [...events(3), { ts: '2026-11-06T23:30:00+08:00', source: 'sync', who: '系統', tag: '同步', text: 'sync-row', evidence: 'gitlab' }];
  const all = load({ events: ev, errors: [] }).renderLog();
  assert.ok(all.includes('sync-row'), '沒有範圍條件時同步事件出現');
  const scoped = load({ events: ev, errors: [] }, e => !!e.repo).renderLog();
  assert.strictEqual(rows(scoped), 3);
  assert.ok(!scoped.includes('sync-row'), '範圍條件擋掉沒有 repo 的同步事件');
}
// Scenario 篩替你做的決定、舊列
{
  const ev = [
    { ts: '2026-11-06T15:00:00+08:00', repo: 'a', slug: 'x', who: 'claude', tag: '替你決定', text: 'pick-b', evidence: '', source: 'decisions' },
    { ts: '2026-11-06T14:00:00+08:00', repo: 'a', slug: 'x', who: '', tag: '其他', text: 'legacy-row', evidence: '', source: 'decisions' },
  ];
  const t = load({ events: ev, errors: [] });
  t.setLogFilter('agent');
  assert.strictEqual(t.F.ev, 'agent');
  const h = t.renderLog();
  assert.ok(h.includes('pick-b') && !h.includes('legacy-row'), '只剩替你決定');
  t.setLogFilter('all');
  const old = t.renderLog().split('<div class="ev">').find(x => x.includes('legacy-row'));
  assert.ok(old.includes('>—<') && old.includes('>其他<') && old.includes('舊格式的列'), '舊列：誰是 —、標籤其他、照原文：' + old);
  assert.ok(h.includes('data-act="ev-open" data-key="a/x"'), '卡可點，開細節頁');
}
// 按日分組（既有 Scenario）：11/06 三筆在前，11/05 兩筆在後
{
  const ev = ['2026-11-06T15:00:00+08:00', '2026-11-06T12:00:00+08:00', '2026-11-06T09:00:00+08:00',
    '2026-11-05T15:00:00+08:00', '2026-11-05T09:00:00+08:00']
    .map(ts => ({ ts, repo: 'a', slug: 'x', who: '你', tag: '已決定', text: 't', evidence: '', source: 'decisions' }));
  const h = load({ events: ev, errors: [] }).renderLog();
  const days = [...h.matchAll(/<div class="day">([^<]*)<\/div>/g)].map(m => m[1]);
  assert.deepStrictEqual(days, ['2026-11-06 · 3', '2026-11-05 · 2']);
}
// collect 變動不重寫；切到首頁再切回紀錄會重寫
{
  const t = load({ events: events(10), errors: [] });
  let writes = 0, html = '';
  const el = { get innerHTML() { return html; }, set innerHTML(v) { writes++; html = v; } };
  const log = t.renderLog();
  t.setView(el, log, true); assert.strictEqual(writes, 1);
  t.setView(el, t.renderLog(), true); assert.strictEqual(writes, 1, 'HTML 沒變不該重寫');
  t.setView(el, '<home>', false); assert.strictEqual(writes, 2);
  t.setView(el, '<home>', false); assert.strictEqual(writes, 3, '首頁照舊每次寫');
  t.setView(el, log, true); assert.strictEqual(writes, 4, '切回紀錄要重寫');
  assert.strictEqual(html, log);
  t.logMore(); t.setView(el, t.renderLog(), true); assert.strictEqual(writes, 4, '10 列時載入更多不改畫面');
  t.setLogFilter('you'); t.setView(el, t.renderLog(), true); assert.strictEqual(writes, 5, '換篩選要重寫');
}
console.log('ok');
JS
