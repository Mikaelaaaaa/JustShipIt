#!/usr/bin/env bash
# 看板的頁面：路由、欄內分組、markdown、卡內檔案 tab、變更頁與已歸檔頁、歸檔按鈕（specs/board-pages、specs/board-actions「歸檔按鈕的顯示」）。
# 函式寫在網頁的 inline script 裡，這裡用 node 把標記之間切出來直接執行；DOM 接線由使用者在瀏覽器實測（D8）。
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
command -v node >/dev/null || fail "需要 node 才能跑看板頁面的網頁測試"

node - "$OPSX_ROOT/herdr-board/web/index.html" <<'JS' || fail "看板頁面"
const fs = require('node:fs');
const assert = require('node:assert');
const html = fs.readFileSync(process.argv[2], 'utf8');
const cut = name => { const s = html.indexOf(`/* ${name} start */`), e = html.indexOf(`/* ${name} end */`);
  if (s < 0 || e < s) throw new Error(`index.html 找不到標記 ${name} start / end`); return html.slice(s, e); };
const fn = name => { const a = html.indexOf(`function ${name}(`); if (a < 0) throw new Error(`index.html 找不到 function ${name}(`); return html.slice(a, html.indexOf('\n}', a)); };
const esc = x => String(x == null ? '' : x).replace(/[&<>"]/g, c => ({'&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;'}[c]));

// ---------- 路由 ----------
const {splitHash, route, cardPath} = new Function(cut('路由') + ';return {splitHash, route, cardPath};')();
const pageOf = h => route(splitHash(h).path);
// Scenario hash 對到頁面（一般場景）
assert.deepStrictEqual(pageOf('#board'), {page: 'board'});
assert.deepStrictEqual(pageOf('#card/a/x'), {page: 'card', repo: 'a', slug: 'x', file: null}, '檔案 tab 停在第一個檔（file 是 null）');
assert.deepStrictEqual(pageOf('#card/a/x/design.md'), {page: 'card', repo: 'a', slug: 'x', file: 'design.md'});
assert.deepStrictEqual(pageOf('#changes'), {page: 'changes'});
assert.deepStrictEqual(pageOf('#archived'), {page: 'archived'});
assert.deepStrictEqual(pageOf('#log'), {page: 'log'});
// 邊界場景
assert.deepStrictEqual(pageOf(''), {page: 'board'}, '沒有 hash');
assert.deepStrictEqual(pageOf('#nope'), {page: 'board'}, '不認得的頁面');
assert.deepStrictEqual(pageOf('#card/a/missing'), {page: 'card', repo: 'a', slug: 'missing', file: null}, '卡不在 collect 裡：路由仍是細節頁');
assert.ok(fn('pageCard').includes('找不到這張卡') && fn('pageCard').includes("href('board')"), '卡不在 collect 裡：顯示「找不到這張卡」與回看板的連結');
// 篩選條件在 ? 之後，不影響頁面
assert.deepStrictEqual(splitHash('#log?repo=a&t=today'), {path: 'log', query: 'repo=a&t=today'});
assert.deepStrictEqual(pageOf('#card/a/x?prio=P0'), {page: 'card', repo: 'a', slug: 'x', file: null});
assert.deepStrictEqual(pageOf('#card/%E0%A4'), {page: 'board'}, '壞掉的編碼回看板頁');
// 子目錄的檔案與特殊字元來回不變
assert.deepStrictEqual(pageOf('#' + cardPath('a b', 'x', 'specs/board-web/spec.md')), {page: 'card', repo: 'a b', slug: 'x', file: 'specs/board-web/spec.md'});

// Scenario 沒有外部資源
assert.ok(!/<script[^>]+src=["']?https?:/i.test(html), '不載入外部 script');
assert.ok(!/<link[^>]+href=["']?https?:/i.test(html), '不載入外部 stylesheet');

// ---------- 欄內分組 ----------
const grp = new Function('esc', cut('分組') + ';return {shouldGroup, groupCards, groupHtml, loadCollapsed, saveCollapsed, COLLAPSE_KEY};')(esc);
// Scenario 哪些欄分組（Examples 五列）
for (const [name, n, want] of [['待處理', 2, true], ['進行中', 3, false], ['已完成', 12, true], ['進行中', 5, false], ['進行中', 6, true]])
  assert.strictEqual(grp.shouldGroup(name, n), want, `${name} ${n} 張：${want ? '分組' : '不分組'}`);
assert.ok(fn('pageBoard').includes('shouldGroup(s.name,list.length)?groupCards(list)'), '看板頁照 shouldGroup 決定分組');
// Scenario 依 session 再依 repo 分組
const card = (slug, more) => ({repo: 'a', slug, waiting: null, ...more});
const done = [1, 2, 3, 4].map(i => card('f' + i, {session: 'a/fb'})).concat([card('b1', {repo: 'b'}), card('b2', {repo: 'b'})]);
const groups = grp.groupCards(done);
assert.deepStrictEqual(groups.map(g => [g.name, g.cards.length]), [['fb', 4], ['b', 2]], '兩組：fb 4 張、b 2 張');
assert.strictEqual(groups.reduce((n, g) => n + g.cards.length, 0), 6, '組的卡數總和等於欄的卡數');
assert.deepStrictEqual(groups[1].cards.map(c => c.slug), ['b1', 'b2'], '組內維持欄的排序');
assert.strictEqual(groups[0].sub, 'a', 'session 組的副標是 repo');
// 在等你的組排前面
assert.deepStrictEqual(grp.groupCards([card('x', {repo: 'z'}), card('y', {repo: 'y', waiting: {type: '等待授權'}})]).map(g => g.name), ['y', 'z']);
// Scenario 收合狀態保留：存進 storage，重整後讀回、組仍是收合的
const mem = {}; const store = () => ({getItem: k => mem[k] ?? null, setItem: (k, v) => { mem[k] = v; }});
const shut = new Set(['已完成|feature:a/fb']);
assert.strictEqual(grp.saveCollapsed(store, shut), true);
const back = grp.loadCollapsed(store);
assert.ok(back.has('已完成|feature:a/fb'), '重整後讀回收合狀態');
const row = c => `<div class="card">${c.slug}</div>`;
assert.ok(grp.groupHtml('已完成', groups[0], row, back).startsWith('<div class="gk shut"'), 'fb 組仍是收合的');
assert.ok(grp.groupHtml('已完成', groups[1], row, back).startsWith('<div class="gk"'), 'b 組是展開的');
assert.ok(grp.groupHtml('已完成', groups[0], row, back).includes('aria-expanded="false"'));
// Scenario localStorage 不能用：讀寫丟例外時全部展開，畫面照常
const broken = () => { throw new Error('SecurityError'); };
assert.strictEqual(grp.loadCollapsed(broken).size, 0, 'localStorage 丟例外：全部展開');
assert.strictEqual(grp.saveCollapsed(broken, shut), false, '寫入丟例外不往外丟');
mem[grp.COLLAPSE_KEY] = '{not json';
assert.strictEqual(grp.loadCollapsed(store).size, 0, '內容壞掉也全部展開');
mem[grp.COLLAPSE_KEY] = '{"a":1}';
assert.strictEqual(grp.loadCollapsed(store).size, 0, '不是陣列也全部展開');
const h = grp.groupHtml('待處理', groups[0], row, grp.loadCollapsed(broken));
assert.strictEqual((h.match(/<div class="card">/g) || []).length, 4, '展開的組畫出它的卡');

// ---------- markdown ----------
const {md} = new Function('esc', cut('markdown') + ';return {md};')(esc);
// Scenario 畫 tasks.md 的勾選框
const tasks = md('- [x] 1.1 做好\n- [ ] 1.2 還沒');
const boxes = [...tasks.matchAll(/<input type="checkbox" disabled( checked)?>/g)];
assert.strictEqual(boxes.length, 2, '兩個勾選框：' + tasks);
assert.ok(boxes[0][1] && !boxes[1][1], '第一個勾起來、第二個沒勾：' + tasks);
// Scenario 檔案內容裡的 HTML 不執行：標題、清單、表格、程式碼、行內都先 escape
for (const src of ['<script>alert(1)</script>', '# <script>alert(1)</script>', '- <script>alert(1)</script>',
  '| a |\n|---|\n| <script>alert(1)</script> |', '```\n<script>alert(1)</script>\n```', '`<script>alert(1)</script>`', '> <script>alert(1)</script>']) {
  const out = md(src);
  assert.ok(!/<script/i.test(out), '不能產生 script 元素：' + out);
  assert.ok(out.includes('&lt;script&gt;alert(1)&lt;/script&gt;'), '以文字顯示：' + out);
}
assert.ok(!md('[x](javascript:alert(1))').includes('href="javascript'), '只有 http(s) 連結變成 <a>');
assert.ok(md('| a | b |\n|---|---|\n| 1 | 2 |').includes('<table>'), '表格');
assert.ok(md('## 標題').includes('<h2>標題</h2>'), '標題');

// ---------- 卡內檔案 tab ----------
const files = new Function('esc', 'md', cut('檔案 tab') + ';return {fileBody, fileTabsHtml, kb};')(esc, md);
// Scenario 檔案太大
const big = files.fileBody({ok: true, p: 'report.md', s: 200000, big: true});
assert.ok(big.includes('檔案太大') && big.includes('report.md'), '顯示「檔案太大」與路徑：' + big);
// Scenario 讀檔失敗
assert.ok(files.fileBody({ok: false, error: '找不到 a/x'}).includes('找不到 a/x'), '顯示 error');
assert.ok(files.fileBody({ok: false, error: '<b>x</b>'}).includes('&lt;b&gt;'), 'error 要 escape');
assert.ok(files.fileBody({ok: true, p: 'tasks.md', s: 20, t: '- [x] 好'}).includes('checked'), '小檔畫成 markdown');
assert.ok(files.fileBody(null).includes('載入中'), '還沒回來');
// tab 與 subs/ N 個檔
const list = {ok: true, files: [{p: 'proposal.md', s: 100}, {p: 'specs/x/spec.md', s: 2048}], subs: 3};
const tabs = files.fileTabsHtml(list, 'specs/x/spec.md', p => '#card/a/x/' + p);
assert.strictEqual((tabs.match(/role="tab"/g) || []).length, 2);
assert.ok(/aria-selected="true" href="#card\/a\/x\/specs\/x\/spec.md"/.test(tabs), '選到的 tab：' + tabs);
assert.ok(tabs.includes('subs/ 3 個檔'), 'subs 大於 0 時寫出數量');
assert.ok(!files.fileTabsHtml({...list, subs: 0}, null, p => p).includes('subs/'), 'subs 是 0 不寫');
assert.ok(files.fileTabsHtml({ok: false, error: '找不到 a/x'}, null, p => p).includes('找不到 a/x'), '列檔失敗顯示 error');
// 接線：細節頁進頁時打 /api/card-files，換 tab 才帶 path
const api = html.slice(html.indexOf('async cardFiles('), html.indexOf('\n', html.indexOf('async cardFiles(')));
assert.ok(api.includes("'/api/card-files?card='+encodeURIComponent(card)+(path?'&path='+encodeURIComponent(path):'')"), 'card-files 的網址：' + api);
assert.ok(api.includes("typeof j.ok==='boolean'?j:{ok:false,error:"), '400、404 的 JSON 照樣交給檔案區');

// ---------- 細節頁的段 ----------
const pc = fn('pageCard');
const at = t => { const i = pc.indexOf(t); assert.ok(i >= 0, 'pageCard 要有 ' + t); return i; };
// Scenario 細節頁有抽屜的段：派工指示、併入項目、邏輯表，邏輯表在合併請求段之後
assert.ok(at('${notesSection(c)}${mergedSection(c)}') < at('${mr}${logicMapSection(c)}${logSec}'), '段的順序');
for (const t of ['${askBox(c)}', '${cardActs(c)}', '${sideFacts(c)}', '${treeSection(c,data.sessions)}', 'fileTabsHtml(']) at(t);
// Scenario 沒派出不打最後輸出：只有 dispatch 有 pane 才打 /api/output、才有最後輸出段
assert.ok(fn('ensureCard').includes('if(c.dispatch&&c.dispatch.pane)loadOutput(c);'), '有 pane 才打 /api/output');
assert.ok(pc.includes("const out=d.pane?`<section><h3>最後輸出"), '沒有 pane 就沒有最後輸出段');
// Scenario 回看板保留篩選：回看板連結與頂列連結都經 href，帶上目前的篩選條件
assert.ok(html.includes("const href=path=>'#'+path+qs(F);"), 'href 帶篩選條件');
assert.ok(pc.includes(`<a href="\${href('board')}">← 回看板</a>`), '細節頁的回看板連結');

// ---------- 變更頁、已歸檔頁 ----------
const flt = new Function('esc', cut('篩選') + ';return {emptyF, matchF, facetOf};')(esc);
const chg = new Function('esc', cut('變更頁') + ';return {changesHtml, archivedHtml, archivedAt};')(esc);
const live = [{repo: 'a', slug: 'board-revamp', title: '看板改版', kind: 'dev'}, {repo: 'b', slug: 'readme', title: 'README 改寫', kind: 'chore'}];
const lrow = c => `<a class="lrow">${c.title}</a>`;
const search = q => live.filter(c => flt.matchF({...flt.emptyF(), q}, flt.facetOf(c), []));
// Scenario 搜尋：比對標題與 slug，不分大小寫
assert.deepStrictEqual(search('看板').map(c => c.slug), ['board-revamp'], '打「看板」只剩看板改版');
assert.deepStrictEqual(search('README').map(c => c.slug), ['readme']);
assert.deepStrictEqual(search('BOARD-rev').map(c => c.slug), ['board-revamp'], 'slug 也比對、不分大小寫');
const page = chg.changesHtml(search('看板'), lrow);
assert.strictEqual((page.match(/class="lrow"/g) || []).length, 1);
assert.ok(page.includes('data-repo="a"') && !page.includes('data-repo="b"'), '依 repo 分組');
// Scenario 沒有符合
const none = chg.changesHtml(search('zzz-沒有'), lrow);
assert.ok(none.includes('沒有符合的卡') && !none.includes('lrow'), '沒有任何卡的行：' + none);
// Scenario 列出已歸檔卡
const arch = [
  {repo: 'a', slug: 'old', title: '舊的', archived: true, path: '/c/a/openspec/changes/archive/2026-11-01-old', mr: null, priority: null, dispatch: null},
  {repo: 'a', slug: 'older', title: '更舊', archived: true, path: '/c/a/openspec/changes/archive/2026-10-01-older', mr: null, priority: null, dispatch: null},
];
const ah = chg.archivedHtml(arch, c => '#card/a/' + c.slug);
assert.ok(ah.includes('title="每個 repo 只列最近 30 張"'), '各 repo 的數字 title 寫明上限');
assert.strictEqual((ah.match(/class="arow"/g) || []).length, 2, '列出這 2 張');
assert.ok(ah.indexOf('2026-11-01') < ah.indexOf('2026-10-01'), '新歸檔的在上');
assert.strictEqual(chg.archivedAt(arch[0]), '2026-11-01', '歸檔時間取自 archive/ 目錄名');
// Scenario 沒有等級與 agent：列表沒有 MR、等級、agent 欄
assert.ok(!/MR|P[012]|claude|codex|badge/.test(ah), '已歸檔列沒有 MR、等級、agent：' + ah);
assert.ok(chg.archivedHtml([], c => '').includes('沒有符合的卡'));

// ---------- 看板欄的卡 ----------
const constOf = name => new Function(html.slice(html.indexOf(`const ${name}=`), html.indexOf(';', html.indexOf(`const ${name}=`)) + 1) + `return ${name};`)();
const joinDot = new Function(fn('joinDot') + '\n};return joinDot;')();
const nw = new Function(html.slice(html.indexOf('const nw='), html.indexOf('\n', html.indexOf('const nw='))) + ';return nw;')();
const rowAttn = new Function('esc', 'WAIT_BADGE', 'GRANT_OF', 'pendBadge', 'priorityBadge', 'bot', 'since', 'key', 'ui', 'joinDot', 'nw', fn('rowAttn') + '\n};return rowAttn;')(
  esc, constOf('WAIT_BADGE'), constOf('GRANT_OF'), () => '', () => '', () => '', () => '', c => c.slug, {sel: null}, joinDot, nw);
// Scenario 授權待處理的按鈕：按「這張卡」送 grant card
const grantRow = rowAttn({slug: 'g', title: 'g', repo: 'r', waiting: {type: '等待授權', gate_id: 'g1', question: 'push?', options: ['這次', '這張卡', '這個 repo 永遠', '拒絕']}});
const grantBtn = label => (new RegExp(`<button[^>]*>${label}</button>`).exec(grantRow) || [''])[0];
assert.ok(grantBtn('這張卡').includes('data-act="answer"') && grantBtn('這張卡').includes('data-grant="card"'), '這張卡 → grant card：' + grantRow);
assert.ok(grantBtn('這次').includes('data-grant="this"') && grantBtn('這個 repo 永遠').includes('data-grant="repo"'), '這次 → this、這個 repo 永遠 → repo');
assert.ok(grantBtn('拒絕').includes('data-text="拒絕"') && !grantBtn('拒絕').includes('data-grant'), '拒絕不帶 grant');
assert.ok(html.includes("api.post('answer',{slug:c.slug,gate:c.waiting.gate_id,grant:grant||'',text,repo:repoTop(c)})"), 'answer 的 body 帶 grant');
// Scenario 可以合併的按鈕：POST /api/merge 帶 slug 與 repo
const mergeRow = rowAttn({slug: 'm', title: 'm', repo: 'r', mr: {url: 'u', head_sha: 'abc'}, waiting: {type: '可以合併'}});
assert.ok(mergeRow.includes('data-act="merge"'), '有合併按鈕：' + mergeRow);
assert.ok(html.includes("function merge(c){act(`opsx merge ${c.slug}`,()=>api.post('merge',{slug:c.slug,repo:repoTop(c)}));}"), 'merge 的 body');
// Scenario type 不明沒有答案按鈕
const unknown = rowAttn({slug: 'u', title: 'u', repo: 'r', waiting: {type: 'type 不明', gate_id: 'g1', question: 'q'}});
assert.ok(!unknown.includes('data-act="answer"'), 'type 不明不能有 answer 按鈕：' + unknown);
assert.ok(!rowAttn({slug: 'n', title: 'n', repo: 'r', waiting: {type: '等待決定', gate_id: 'g1', question: 'q', recommended: 'x', needs: 'run'}}).includes('照建議'), 'needs: run 沒有照建議');
assert.ok(grantRow.startsWith('<div class="card you'), '等你的卡有藍條');
// Scenario 待分類不能指派
const unfiled = fn('rowUnfiled');
assert.ok(!unfiled.includes('data-act="dispatch"') && !unfiled.includes('data-act="explore"'), '待分類列沒有指派與先 explore');
// Scenario 同步進行中不算錯
assert.ok(fn('syncNow').includes("if(r.status===409)toast('同步進行中');"), '409 顯示同步進行中，不是錯誤 toast');
// Scenario 沒有孤兒就沒有那一行（孤兒與沒對到卡的 agent 收在看板底下預設收合的「其他 pane」區塊）
const stray = new Function('esc', 'joinDot', 'ui', 'AGENT_WORD', 'ORPHAN_WHY',
  fn('rowUnmatched') + '\n}\n' + fn('rowOrphan') + '\n}\n' + fn('strayHtml') + '\n};return strayHtml;')(esc, joinDot, {strayOpen: false}, {idle: '閒置'}, {archived: '卡已歸檔'});
assert.strictEqual(stray([], []), '', '都沒有：不畫區塊');
const orphOnly = stray([], [{repo: 'a', slug: 'x', pane: 'w1:p3', agent_status: 'idle', reason: 'archived'}]);
assert.ok(orphOnly.includes('孤兒 pane 1') && orphOnly.includes('data-act="reap"') && orphOnly.includes('data-act="reap-all"'), '孤兒列有關閉與全部關閉：' + orphOnly);
assert.ok(!orphOnly.includes('沒對到卡'), '沒有沒對到卡的 agent 不畫那一段');
assert.ok(orphOnly.startsWith('<details class="stray" id="stray">'), '預設收合：' + orphOnly);
const unOnly = stray([{name: 'scratch', pane: 'p7', agent_status: 'idle'}], []);
assert.ok(unOnly.includes('沒對到卡的 agent 1') && unOnly.includes('data-act="pane-id"') && !unOnly.includes('孤兒 pane'), '沒有孤兒不畫那一段：' + unOnly);
assert.ok(!/color:var\(--danger\)|class="[^"]*err/.test(unOnly + orphOnly), '其他 pane 不用紅字');
assert.ok(fn('strayLists').includes('!a.orphan&&!a.coordinator'), '協調者不進其他 pane 區塊');
assert.ok(fn('pageBoard').includes('${strayHtml(un,orph)}') && !fn('colExtra').includes('unmatched_agents'), '其他 pane 在看板最底下，不在進行中欄');
// Scenario 欄的卡數：欄標題的數字是欄內卡數（收件匣另加待分類）
assert.ok(fn('pageBoard').includes("const n=list.length+(s.name==='收件匣'?(data.unfiled||[]).length:0);"), '欄的卡數');
// 頂列的全域動作
for (const t of ['id="new-open"', 'data-act="sync">立即同步', 'data-act="reap-all"']) assert.ok(html.includes(t), '頂列要有 ' + t);

// ---------- 歸檔按鈕 ----------
const arc = new Function(cut('歸檔') + ';return {archiveState, archiveCtl, archiveBody};')();
const mrMerged = {url: 'u', merged_at: '2026-11-20T10:00:00Z'};
// Scenario 歸檔按鈕的顯示（Examples 三列）
const yes = arc.archiveCtl({slug: 'x', mr: mrMerged, dispatch: null, agent_status: null});
assert.ok(yes.includes('data-act="archive"') && yes.includes('歸檔') && !yes.includes('等協調者收尾'), '已合併、沒有活 pane：歸檔按鈕');
const wait = arc.archiveCtl({slug: 'x', mr: mrMerged, dispatch: {pane: 'p'}, agent_status: 'working'});
assert.ok(wait.includes('等協調者收尾') && !wait.includes('data-act'), '已合併、有活 pane：等協調者收尾，沒有按鈕');
assert.strictEqual(arc.archiveCtl({slug: 'x', mr: {url: 'u', merged_at: null}, dispatch: null}), '', '沒合併：兩個都沒有');
assert.strictEqual(arc.archiveCtl({slug: 'x', mr: null, dispatch: null}), '', '沒有 MR：兩個都沒有');
// 跟 server 同一條件：pane 已經不在（unknown）算沒有活 pane；idle 是 pane 還在
assert.strictEqual(arc.archiveState({mr: mrMerged, dispatch: {pane: 'p'}, agent_status: 'unknown'}), 'ready');
assert.strictEqual(arc.archiveState({mr: mrMerged, dispatch: {pane: 'p'}, agent_status: 'idle'}), 'wait');
assert.deepStrictEqual(arc.archiveBody({repo: 'a', slug: 'x'}, {a: '/code/a'}), {slug: 'x', repo: '/code/a'}, 'POST body 帶 repo 根路徑');
assert.ok(html.includes("function archiveCard(c){act(`openspec archive ${c.slug} -y`,()=>api.post('archive',archiveBody(c,data.repo_paths)));}"), '按鈕走動作接線（失敗 toast stderr）');
assert.ok(html.includes("if(a==='archive'){archiveCard(c);return;}"), '點擊接線');
assert.ok(fn('rowDone').includes('archiveCtl(c)') && fn('cardActs').includes('archiveCtl(c)'), '已完成欄與細節頁都畫歸檔');

// ---------- 子 change 等你 ----------
// collect 在子 change 有 waiting 時只把 session 放進待處理，主 change 卡留在自己的欄；看板的待處理欄要列出它，點進細節頁從樹上回
const sw = new Function('esc', 'cardHref', cut('子 change 等你') + ';return {subWaiting, subWaitingHtml};')(esc, c => '#card/' + c.repo + '/' + c.slug);
const sess = [{repo: 'a', feature: 'fb', mains: [
  {slug: 'bt', subs: [{slug: 'as', waiting: {type: '等待決定'}}, {slug: 'ct', waiting: null}]},
  {slug: 'bu', subs: [{slug: 'cu', waiting: null}]}]}];
const bt = {repo: 'a', slug: 'bt', title: 'BT', session: 'a/fb', section: '進行中'};
assert.deepStrictEqual(sw.subWaiting(bt, sess), ['as'], '主 change 底下等你的子 change');
assert.deepStrictEqual(sw.subWaiting({repo: 'a', slug: 'bu', session: 'a/fb', section: '進行中'}, sess), [], '子 change 都沒在等：不列');
assert.deepStrictEqual(sw.subWaiting({repo: 'a', slug: 'x', section: '進行中'}, sess), [], '沒有 session：不列');
assert.deepStrictEqual(sw.subWaiting({...bt, section: '待處理'}, sess), [], '主 change 自己已在待處理：不重複列');
const swh = sw.subWaitingHtml([bt, {repo: 'a', slug: 'bu', session: 'a/fb', section: '進行中'}], sess);
assert.ok(swh.includes('#card/a/bt') && swh.includes('as') && !swh.includes('#card/a/bu'), '待處理欄的子 change 區塊連到主 change 的細節頁');
assert.strictEqual(sw.subWaitingHtml([{repo: 'a', slug: 'bu', session: 'a/fb', section: '進行中'}], sess), '', '沒有等你的子 change：不畫區塊');
assert.ok(fn('colExtra').includes('subWaitingHtml('), '待處理欄底下畫子 change 等你');

// ---------- 看板抽屜（D9） ----------
const fakeAsk = c => c.waiting ? `<div class="ask">${esc(c.waiting.question)} 建議 ${esc(c.waiting.recommended)}<button data-act="answer" data-text="A">A</button></div>` : '';
const dr = new Function('esc', 'bot', 'priorityBadge', 'askBox', 'sideFacts', cut('抽屜') + ';return {drawerHtml};')(
  esc, () => '<svg class="bot"></svg>', () => '', fakeAsk, () => '<div>進度與 MR 條件</div>');
const waitCard = {repo: 'a', slug: 'x', title: 'X 卡', section: '待處理', waiting: {type: '等待決定', question: '要 A 還是 B', recommended: 'A'}};
// Scenario 點卡片打開抽屜
const open = dr.drawerHtml(waitCard);
assert.ok(open.includes('id="drawer"') && open.includes('data-key="a/x"'), '抽屜帶卡的身分，按鈕找得到是哪張卡');
assert.ok(open.includes('要 A 還是 B') && open.includes('建議 A') && open.includes('data-act="answer"'), '抽屜有問題、建議與回答按鈕（askBox）');
assert.ok(open.includes('進度與 MR 條件'), '抽屜有進度與 MR 條件（sideFacts）');
assert.ok(open.includes('data-act="drawer-detail"') && open.includes('開啟細節'), '抽屜有「開啟細節」');
assert.ok(open.includes('data-act="drawer-close"'), '抽屜有關閉鈕與遮罩');
// Scenario 沒在等的卡
const idle = dr.drawerHtml({...waitCard, waiting: null});
assert.ok(idle.includes('沒有在等你') && !idle.includes('data-act="answer"'), '沒在等：寫「沒有在等你」，沒有回答按鈕');
// 跳脫
assert.ok(!dr.drawerHtml({...waitCard, title: '<b>t</b>'}).includes('<b>t</b>'), '標題經 escape');
// 接線：點卡片與「自己選／看詳情」開抽屜，「開啟細節」跳細節頁，Esc 先關抽屜，看板頁畫抽屜
assert.ok(html.includes('if(rowEl){openDrawer(rowEl.dataset.key);return;}'), '點卡片本體開抽屜，不跳頁');
assert.ok(html.includes("if(a==='open'){openDrawer(k);return;}"), '自己選／看詳情開抽屜');
assert.ok(html.includes("if(a==='drawer-detail'){openCard(k);return;}"), '開啟細節跳 #card');
assert.ok(html.includes("if(a==='drawer-close'){closeDrawer();return;}"), '關閉鈕與遮罩關抽屜');
assert.ok(html.includes("if(e.key==='Enter'&&e.target.matches('.card[data-key]')){openDrawer(e.target.dataset.key);return;}"), '卡片上按 Enter 開抽屜');
assert.ok(/if\(e\.key==='Escape'\)\{if\(!\$\('#dialog'\)\.hidden\)closeDispatch\(\);else if\(panelOpen\)setPanel\(false\);else if\(ui\.drawer\)closeDrawer\(\);/.test(html), 'Esc 先關抽屜，不跳頁');
assert.ok(fn('pageBoard').includes('drawerHtml('), '看板頁畫抽屜');
assert.ok(fn('render').includes("r.page==='board'?ui.drawer:null"), '抽屜開著時回覆框 Enter 與按鈕找得到這張卡');
assert.ok(fn('render').includes("if(r.page!=='board')ui.drawer=null;"), '離開看板頁抽屜關閉');
// 其他頁照舊直接進細節頁
assert.ok(html.includes("openCard(btn.dataset.key);return;}") && fn('overview').includes('cardHref(c)'), '紀錄與總覽連結照舊進細節頁');
// 抽屜的標題列：標題在最上，右側「開啟細節 →」文字連結與 ✕
const head = open.slice(open.indexOf('<header'), open.indexOf('</header>'));
assert.ok(head.includes('X 卡') && head.includes('class="link" data-act="drawer-detail">開啟細節 →') && head.includes('aria-label="關閉抽屜"'), '標題、開啟細節與關閉在同一列：' + head);

// ---------- 版面不靠說明文字 ----------
// 欄頭沒有副標、頁面沒有大標與說明行；更新於只在頂列
assert.ok(constOf('SECTIONS').every(s => !('hint' in s)), '欄沒有副標');
assert.ok(!fn('pageBoard').includes('class="hint"') && !/class="ph"/.test(html) && !/\.ph p/.test(html), '沒有欄副標、頁首說明行');
assert.ok(!fn('pageBoard').includes('更新於') && html.includes('id="stamp"'), '更新於只在頂列');
assert.ok(!fn('inboxBody').includes('上次同步'), '收件匣欄頂沒有上次同步那行');
// 上次同步移到「立即同步」按鈕的 title
const syncTitle = new Function('ago', fn('syncTitle') + '\n};return syncTitle;')(() => '5 分鐘');
assert.strictEqual(syncTitle(null), '上次同步 還沒跑過 · GitLab · GitHub · shortcut');
assert.ok(syncTitle({at: 'x', created: 2, updated: 1, errors: 1, first_error: 'gitlab 401'}).startsWith('上次同步 5 分鐘前 · 新建 2 · 更新 1 · 錯誤 1：gitlab 401'), '同步摘要');
assert.ok(fn('renderTop').includes('sb.title=syncTitle(ls)'), '頂列把摘要放進同步按鈕的 title');
assert.ok(/<button[^>]*id="sync-btn"[^>]*data-act="sync">立即同步<\/button>/.test(html), '同步按鈕在頂列');

// joinDot：分隔點只在兩段非空之間（Examples）
const plain = s => s.replace(/ /g, ' ');
for (const [parts, want] of [[['a', '', 'b'], 'a · b'], [['', 'b'], 'b'], [['a', ''], 'a'], [[], '']])
  assert.strictEqual(plain(joinDot(parts)), want, JSON.stringify(parts));
assert.strictEqual(joinDot(['a', 'b']), 'a' + String.fromCharCode(0xa0) + '· b', '點前是不換行空格、點後是一般空格：只能在點後折行，點不會落在行首');
const mergeNoSha = rowAttn({slug: 'm', title: 'm', repo: 'r', mr: {url: 'u', head_sha: ''}, waiting: {type: '可以合併'}});
assert.ok(!/·\s*<\/div>/.test(mergeNoSha) && !mergeNoSha.includes('class="sep"'), '沒有 sha 時「五個條件都通過」後面沒有落單的點：' + mergeNoSha);
const recRow = rowAttn({slug: 'g', title: 'g', repo: 'r', waiting: {type: '等待授權', gate_id: 'g1', question: 'push?', recommended: '這張卡', options: ['這次', '拒絕']}});
assert.ok(recRow.includes('<div class="q">push?</div><div class="l2">建議：這張卡</div>'), '建議另起一行，不用點接在問題後：' + recRow);

// 短時間：月/日 時:分，用本機時區組 Date 測，跟跑測試的機器時區無關
const {shortTime, timeHtml} = new Function('esc', fn('shortTime') + '\n}\n' + fn('timeHtml') + '\n};return {shortTime, timeHtml};')(esc);
assert.strictEqual(shortTime(new Date(2026, 10, 21, 9, 10)), '11/21 09:10');
assert.strictEqual(shortTime(new Date(2026, 0, 5, 23, 7)), '01/05 23:07');
const th = timeHtml('2026-11-21T09:10:00+08:00');
assert.ok(th.includes('title="2026-11-21T09:10:00+08:00"') && th.includes('>' + shortTime(new Date('2026-11-21T09:10:00+08:00')) + '</time>'), '完整值在 title：' + th);
assert.ok(timeHtml('2026-11-18').includes('>11/18</time>'), '只有日期的不加時間（不被當成 UTC 午夜）');
assert.strictEqual(timeHtml(''), '');
assert.strictEqual(timeHtml('不是時間'), '不是時間', '解析不了照原文');

// 協調者狀態：頂列右側，有 pane 才能點；沒有就灰字「協調者未開」
const coord = new Function('esc', 'COORDINATOR', 'AGENT_WORD', fn('coordHtml') + '\n};return coordHtml;')(esc, constOf('COORDINATOR'), constOf('AGENT_WORD'));
const cOn = coord([{name: 'scratch', pane: 'p7', agent_status: 'idle'}, {name: 'lead', pane: 'w1:p1', agent_status: 'working', coordinator: true}]);
assert.ok(cOn.startsWith('<button class="coord on"') && cOn.includes('data-act="pane-id"') && cOn.includes('data-agent="opsx-coordinator"') && cOn.includes('協調者 執行中'), '協調者在跑：' + cOn);
assert.ok(cOn.includes('aria-label='), '協調者按鈕有 aria-label');
const cUnknown = coord([{name: 'lead', pane: 'w1:p1', agent_status: 'unknown', coordinator: true}]);
assert.ok(!cUnknown.includes('unknown') && cUnknown.includes('協調者 不在 herdr'), 'unknown 換成白話：' + cUnknown);
const cNoPane = coord([{name: 'lead', pane: null, agent_status: 'idle', coordinator: true}]);
assert.ok(!cNoPane.includes('data-act') && cNoPane.includes('協調者 閒置'), '沒有 pane 不能點：' + cNoPane);
const cOff = coord([{name: 'scratch', pane: 'p7', agent_status: 'idle'}]);
assert.ok(cOff.includes('協調者未開') && !cOff.includes('data-act') && !/danger|err/.test(cOff), '沒有協調者：灰字協調者未開：' + cOff);
assert.ok(coord(undefined).includes('協調者未開'), '舊 collect 沒有 unmatched_agents');
assert.ok(fn('renderTop').includes("$('#coord').innerHTML=data.generated_at?coordHtml(data.unmatched_agents):''"), '頂列畫協調者狀態');

// MR 條件 5/5（卡在 pipeline）不用紅色滿格：進度條不染色，卡住的是琥珀小標
const rr = fn('rowRunning');
assert.ok(!rr.includes('danger') && !/<i class="\$\{stuck/.test(rr), '進度條不因 MR 卡住變紅');
assert.ok(rr.includes('<span class="badge warn">MR 卡在'), 'MR 卡住用琥珀小標');
assert.ok(!/\.prog \.bar i\.warn/.test(html), '沒有紅色進度條的 CSS');
// 進度列：階段＋條＋n/m 一行，說明另起一行
assert.ok(rr.includes('<div class="prog">') && rr.includes('</div>${s.label?`<div class="l2">'), '說明不在進度條那一行');

// 收件卡：只露「指派」，其餘收進 ⋯（<details> 鍵盤可開），data-act 照舊
const ri = fn('rowInbox');
assert.ok(ri.includes('<details class="more"') && ri.includes('<summary aria-label="更多動作"'), '⋯ 選單是 details/summary');
for (const t of ['prioCtl(c)', 'data-act="explore"', 'mergeCtl(c,data.cards)', 'dropCtl(k)']) assert.ok(ri.slice(ri.indexOf('<details')).includes(t), '⋯ 裡有 ' + t);
assert.ok(ri.indexOf('data-act="dispatch">指派') < ri.indexOf('${menu}'), '主按鈕指派露在外面');
assert.ok(html.includes("if(e.target.closest('details'))return;"), '點 ⋯ 不開抽屜');

// 細節頁：狀態標籤只有一個；session 用功能圖示，不再寫第二個「功能」
assert.ok(!pc.includes('功能 ${esc(c.session'), 'session 標籤不寫「功能」');
assert.ok(pc.includes('const status=(w?') && (pc.match(/\$\{status\}/g) || []).length === 1, '狀態只放一個');
// 缺資料是灰字一次：列檔失敗不再畫只有錯誤的文件卡；沒有 pane、紀錄讀不到不用紅字
assert.ok(pc.includes("const doc=L&&!L.ok?'':"), '列檔失敗不畫文件卡');
assert.ok(!files.fileTabsHtml({ok: false, error: '卡目錄不在了'}, null, p => p).includes('err'), '文件 tab 的列檔失敗是灰字');
assert.ok(!/<div class="note err">\$\{esc\(o\.error\)\}/.test(pc) && !/<div class="note err">\$\{esc\(tlErr\)\}/.test(pc), '最後輸出與紀錄讀不到是灰字');

// ---------- 第 2 輪瀏覽器檢查（browser-review-2.md） ----------
const css = html.slice(html.indexOf('<style>'), html.indexOf('</style>'));
const rule = sel => { const i = css.indexOf(sel + '{'); if (i < 0) throw new Error('找不到 CSS ' + sel); return css.slice(i, css.indexOf('}', i)); };
// 1 總覽四格等高、內容靠上
assert.ok(rule('.ov').includes('align-items:stretch'), '總覽四格等高：' + rule('.ov'));
// 2 卡片 meta 只留 repo 與天數，天數不被截
assert.ok(!fn('rowRunning').includes('c.dispatch?.agent'), '進行中卡的 meta 不放 agent');
assert.ok(!rule('.c-ttl .m').includes('text-overflow:ellipsis') && !rule('.c-ttl .m').includes('nowrap'), 'meta 可以換行，不截字：' + rule('.c-ttl .m'));
// 3 最後輸出與紀錄讀不到用白話，原始錯誤只放 title
assert.ok(pc.includes('沒有 agent 在跑') && !/>\$\{esc\(o\.error\)\}</.test(pc), '最後輸出讀不到：白話「沒有 agent 在跑」，不露原始錯誤');
assert.ok(pc.includes('紀錄讀不到') && pc.includes('data-act="log-retry"') && !/>\$\{esc\(tlErr\)\}</.test(pc), '紀錄讀不到：白話加重試');
assert.ok(html.includes("if(a==='log-retry'){loadLog();return;}"), '重試接線');
// 5 900 寬頂列一行：新增、立即同步只剩圖示，協調者與更新於收成一個點加 tooltip
const narrow = css.slice(css.indexOf('@media (max-width:900px)'));
assert.ok(narrow.includes('#new-open,#sync-btn{font-size:0') && narrow.includes('#new-open::before') && narrow.includes('#sync-btn::before'), '窄版新增與同步是圖示按鈕');
assert.ok(narrow.includes('#stamp{display:none}') && narrow.includes('.coord{font-size:0'), '窄版協調者與更新於收成一個點');
assert.ok(fn('renderTop').includes("$('#coord').title="), '協調者點的 tooltip 帶狀態與更新時間');

// ---------- 第 3 輪瀏覽器檢查（browser-review-3.md） ----------
// 1 總覽四格同高：2×2 時兩列也一樣高
assert.ok(rule('.ov').includes('grid-auto-rows:1fr'), '總覽每一列同高：' + rule('.ov'));
// 2 卡片 meta 只在「·」處換行：每段包在不換行的 span 裡
assert.ok(rule('.nw').includes('white-space:nowrap'), '.nw 不換行');
for (const r of ['rowAttn', 'rowRunning', 'rowReady', 'rowDone', 'rowInbox'])
  assert.ok(/<div class="m">\$\{joinDot\(\[nw\(/.test(fn(r)), r + ' 的 meta 每段包 nw()');
assert.strictEqual(nw('agent:review'), '<span class="nw">agent:review</span>');
assert.strictEqual(nw(''), '', '空段不包，joinDot 才丟得掉');
// 3 細節頁不露絕對路徑：顯示 repo · openspec/changes/…，完整路徑放 title
const plSrc = html.slice(html.indexOf('function cardPathLabel('), html.indexOf('\n}', html.indexOf('function cardPathLabel(')) + 2);
const cardPathLabel = new Function('esc', plSrc + 'return cardPathLabel;')(esc);
const lbl = cardPathLabel({repo: 'acme-web', path: '/home/someone/code/acme-web/openspec/changes/team-invites-email/'});
assert.ok(lbl.includes('>acme-web · openspec/changes/team-invites-email<'), '顯示 repo 相對路徑：' + lbl);
assert.ok(lbl.includes('title="/home/someone/code/acme-web/openspec/changes/team-invites-email/"'), '完整路徑在 title');
assert.ok(!lbl.includes('>/home/'), '畫面上的字不含絕對路徑');
assert.ok(cardPathLabel({repo: 'a', path: '/x/a/openspec/changes/archive/2026-11-20-old/'}).includes('>a · openspec/changes/archive/2026-11-20-old<'), '已歸檔卡也是相對路徑');
assert.strictEqual(cardPathLabel({repo: 'a', path: null}), '', '沒有 path 不畫');
assert.ok(fn('cardActs').includes('${cardPathLabel(c)}') && !fn('cardActs').includes("esc(c.path||'')"), '操作列用 cardPathLabel，不印絕對路徑');
JS
echo ok
