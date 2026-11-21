#!/usr/bin/env bash
# 看板的篩選：條件寫進 hash 再讀回、chip 移除、不認得的值、換頁保留、範圍作用在紀錄、時間篩選（specs/board-pages「篩選 popover 與 chips」、specs/board-log「紀錄 tab」）。
# 規則寫在網頁的 inline script 裡，這裡用 node 把「篩選」標記之間切出來直接執行。時間以 TZ=Asia/Taipei（lib.sh）的本機日曆算。
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
command -v node >/dev/null || fail "需要 node 才能跑篩選的網頁測試"

node - "$OPSX_ROOT/herdr-board/web/index.html" <<'JS' || fail "篩選"
const fs = require('node:fs');
const assert = require('node:assert');
const html = fs.readFileSync(process.argv[2], 'utf8');
const s = html.indexOf('/* 篩選 start */'), e = html.indexOf('/* 篩選 end */');
if (s < 0 || e < s) throw new Error('index.html 找不到標記 篩選 start / end');
const esc = x => String(x == null ? '' : x).replace(/[&<>"]/g, c => ({'&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;'}[c]));
const {emptyF, parseF, qs, matchF, facetOf, inTime, chipItems, chipsHtml, removeChip, FGROUPS, forPage, scopeHas} =
  new Function('esc', html.slice(s, e) + ';return {emptyF, parseF, qs, matchF, facetOf, inTime, chipItems, chipsHtml, removeChip, FGROUPS, forPage, scopeHas};')(esc);

const known = {repos: ['a', 'b', 'c'], wss: ['develop', ''], kinds: ['dev', 'chore'], pcs: ['mergeable', 'testing']};
const LAB = {kind: {dev: '功能', chore: '雜務'}, pc: {mergeable: '可合併', testing: '測試中'}};
const scopes = [{workspace: 'develop', repos: ['a', 'b']}, {workspace: null, repos: ['c']}];
const card = (repo, slug, more) => ({repo, slug, title: slug, kind: 'dev', priority: null, dispatch: null, waiting: null, progress_class: null, ...more});
const cards = [card('a', 'x', {priority: {level: 'P0'}}), card('a', 'y', {priority: {level: 'P1'}}), card('b', 'z', {priority: {level: 'P0'}}), card('c', 'w')];
const pick = f => cards.filter(c => matchF(f, facetOf(c), scopes)).map(c => c.repo + '/' + c.slug);
const roundTrip = f => parseF(qs(f).replace(/^\?/, ''), known);

// Scenario 篩選寫進 hash 再讀回：repo a、等級 P0
let f = {...emptyF(), repo: ['a'], prio: ['P0']};
const hash = qs(f);
assert.deepStrictEqual(roundTrip(f), f, '同一個 hash 讀回同樣的條件：' + hash);
assert.deepStrictEqual(chipItems(roundTrip(f), 'board', LAB).map(x => x[2]), ['a', 'P0'], 'chips 是 repo a 與等級 P0');
assert.deepStrictEqual(pick(roundTrip(f)), ['a/x'], '看板只剩符合兩個條件的卡');
// 每一種條件都來回不變
const full = {...emptyF(), scope: 'ws', ws: 'develop', repo: ['a', 'b'], prio: ['P0', 'P2'], kind: ['chore'], agent: ['none', 'codex'], you: true, pc: 'testing', q: '看板 x', t: 'custom', from: '2026-11-01', to: '2026-11-21', ev: 'agent'};
assert.deepStrictEqual(roundTrip(full), full, '全部條件來回不變');
assert.deepStrictEqual(roundTrip({...emptyF(), scope: 'ws', ws: null}), {...emptyF(), scope: 'ws', ws: null}, '沒掛 workspace 的範圍來回不變');
assert.deepStrictEqual(roundTrip({...emptyF(), scope: 'repo', srepo: 'c'}), {...emptyF(), scope: 'repo', srepo: 'c'}, '單一 repo 範圍來回不變');
assert.strictEqual(qs(emptyF()), '', '沒有條件時 hash 沒有 ?');

// Scenario 移除 chip：按 P0 的移除，只剩 repo a，hash 不再含等級
f = removeChip(f, 'prio', 'P0');
assert.deepStrictEqual(chipItems(f, 'board', LAB).map(x => x[2]), ['a'], '只剩 repo a 一個條件');
assert.ok(!qs(f).includes('prio'), 'hash 不再含等級：' + qs(f));
assert.deepStrictEqual(removeChip({...emptyF(), scope: 'repo', srepo: 'a'}, 'sc', ''), emptyF(), '範圍 chip 移除回到全部');
assert.deepStrictEqual(removeChip({...emptyF(), t: 'custom', from: '2026-11-01'}, 't', ''), emptyF(), '時間 chip 移除回到全部');
assert.throws(() => removeChip(emptyF(), 'zz', ''), /不認得的篩選 chip/);
const ch = chipsHtml({...emptyF(), repo: ['a'], prio: ['P0']}, 'board', LAB);
assert.ok(ch.includes('data-frm="prio" data-fv="P0"') && ch.includes('data-fclear'), '每個 chip 可單獨移除，另有清除：' + ch);

// Scenario 不認得的條件值：#board?prio=P9 忽略，不顯示 chip，看板畫全部的卡
const p9 = parseF('prio=P9', known);
assert.deepStrictEqual(p9, emptyF(), '等級條件被忽略');
assert.deepStrictEqual(chipItems(p9, 'board', LAB), [], '不顯示 chip');
assert.strictEqual(pick(p9).length, cards.length, '看板畫全部的卡');
assert.deepStrictEqual(parseF('repo=zz,a&kind=nope&agent=x&t=week&ev=?&sc=repo:zz&pc=zz&from=bad', known), {...emptyF(), repo: ['a']}, '每一種不認得的值都丟掉');
assert.deepStrictEqual(parseF('t=custom', known).t, 'all', '自訂起訖沒有日期就是全部');

// Scenario 換頁保留條件：頂列連結與卡片連結都經 href，帶上 qs(F)
assert.ok(html.includes("const href=path=>'#'+path+qs(F);"), 'href 帶篩選條件');
assert.ok(html.includes('<a href="${href(k)}"'), '頂列的頁面連結經 href');
assert.ok(html.includes('const fCards=()=>liveCards().filter(c=>matchF(F,facetOf(c),data.scopes));'), '變更頁與看板頁同一組篩選');

// 範圍：全部、workspace、單一 repo
assert.deepStrictEqual(pick({...emptyF(), scope: 'ws', ws: 'develop'}), ['a/x', 'a/y', 'b/z'], 'workspace develop 底下的 repo');
assert.deepStrictEqual(pick({...emptyF(), scope: 'ws', ws: null}), ['c/w'], '沒掛 workspace 的 repo');
assert.deepStrictEqual(pick({...emptyF(), scope: 'repo', srepo: 'b'}), ['b/z'], '單一 repo');
assert.deepStrictEqual(pick({...emptyF(), you: true}), [], '等我：沒有卡在等');
assert.deepStrictEqual(pick({...emptyF(), agent: ['none'], kind: ['dev']}), cards.map(c => c.repo + '/' + c.slug), '沒派的卡 agent 是 none');

// Scenario 範圍作用在紀錄：選 workspace develop，只剩 develop 底下 repo 的卡的事件，同步事件不顯示
const ev = [{repo: 'a', slug: 'x', text: 't', tag: '已決定'}, {repo: 'c', slug: 'w', text: 't', tag: '已決定'}, {repo: '', slug: '', text: 'sync', tag: '同步', source: 'sync'}];
const evFacet = x => ({repo: x.repo || '', prio: '', kind: '', agent: '', you: false, pc: null, text: x.text});
const pickEv = f => ev.filter(x => matchF(f, evFacet(x), scopes)).map(x => x.repo || 'sync');
assert.deepStrictEqual(pickEv({...emptyF(), scope: 'ws', ws: 'develop'}), ['a'], '只剩 develop 的事件，同步事件不顯示');
assert.deepStrictEqual(pickEv(emptyF()), ['a', 'c', 'sync'], '沒有範圍條件時同步事件出現');
assert.deepStrictEqual(pickEv({...emptyF(), repo: ['a']}), ['a'], '有 repo 條件時同步事件不顯示');
assert.strictEqual(scopeHas({...emptyF(), scope: 'ws', ws: null}, scopes, ''), false, '沒有 repo 的列不算在沒掛 workspace 的範圍裡');

// Scenario 時間篩選（Examples 六列）：瀏覽器當下時間 2026-11-21T12:00:00+08:00
const NOW = Date.parse('2026-11-21T12:00:00+08:00');
const T = {'今天': 'today', '24 小時': '24h', '7 天': '7d'};
for (const [preset, ts, want] of [
  ['今天', '2026-11-21T09:00:00+08:00', true],
  ['今天', '2026-11-20T23:00:00+08:00', false],
  ['7 天', '2026-11-16T12:00:00+08:00', true],
  ['今天', '2026-11-21T00:00:00+08:00', true],
  ['24 小時', '2026-11-20T12:00:00+08:00', true],
  ['24 小時', '2026-11-20T11:59:59+08:00', false],
]) assert.strictEqual(inTime({...emptyF(), t: T[preset]}, ts, NOW), want, `${preset} · ${ts}：${want ? '出現' : '不出現'}`);
// 自訂起訖照本機日曆日，含兩端；全部不篩；時間讀不懂的列在有時間條件時不出現
const custom = {...emptyF(), t: 'custom', from: '2026-11-20', to: '2026-11-21'};
assert.strictEqual(inTime(custom, '2026-11-20T00:00:00+08:00', NOW), true, '起日當天');
assert.strictEqual(inTime(custom, '2026-11-21T23:59:59+08:00', NOW), true, '迄日當天');
assert.strictEqual(inTime(custom, '2026-11-19T23:59:59+08:00', NOW), false, '起日前一秒');
assert.strictEqual(inTime({...custom, to: ''}, '2026-12-01T00:00:00+08:00', NOW), true, '只有起日');
assert.strictEqual(inTime(emptyF(), 'not-a-date', NOW), true, '全部不篩');
assert.strictEqual(inTime({...emptyF(), t: 'today'}, 'not-a-date', NOW), false);
// 現在用瀏覽器當下時間，不是 collect 的 generated_at
assert.ok(html.includes('inTime(F,e.ts,Date.now())'), '紀錄頁以 Date.now() 算時間篩選');

// Scenario 時間篩選只在紀錄頁；已歸檔頁沒有等級與 agent
assert.ok(!FGROUPS('board').includes('time') && !FGROUPS('changes').includes('time'), '看板頁、變更頁沒有時間篩選');
assert.ok(FGROUPS('log').includes('time'), '紀錄頁有時間篩選');
assert.ok(!FGROUPS('archived').includes('prio') && !FGROUPS('archived').includes('agent'), '已歸檔頁沒有等級與 agent');
assert.deepStrictEqual(chipItems({...emptyF(), t: 'today', prio: ['P0']}, 'board', LAB).map(x => x[0]), ['prio'], '看板頁不畫時間 chip');
assert.deepStrictEqual(chipItems({...emptyF(), t: 'today', prio: ['P0']}, 'archived', LAB), [], '已歸檔頁不畫等級 chip');
assert.deepStrictEqual(forPage({...emptyF(), prio: ['P0'], agent: ['claude']}, 'archived'), emptyF(), '已歸檔頁不套等級與 agent');
const fb = html.slice(html.indexOf('function fbarHtml('), html.indexOf('\n}', html.indexOf('function fbarHtml(')));
assert.ok(fb.includes("if(g.includes('time'))") && fb.includes("if(g.includes('prio'))") && fb.includes("if(g.includes('agent'))"), 'popover 依 FGROUPS 決定要畫的條件');

// 搜尋只重畫內容區：input 事件走 applyF(false) → renderContent，不重寫篩選列
assert.ok(html.includes("if(e.target.id==='fq'){F.q=e.target.value;applyF(false);return;}"), '打字走 applyF(false)');
const rc = html.slice(html.indexOf('function renderContent(){'), html.indexOf('\n}', html.indexOf('function renderContent(){')));
assert.ok(!rc.includes('renderFbar') && !rc.includes('#fslot'), 'renderContent 不動篩選列：' + rc);
JS
echo ok
