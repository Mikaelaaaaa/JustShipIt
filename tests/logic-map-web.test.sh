#!/usr/bin/env bash
# 看板抽屜的邏輯表段：原文不折行、HTML 以文字顯示、沒有邏輯表不顯示（specs/board-web「抽屜的邏輯表段」）。
# 規則寫在網頁的 inline script 裡，這裡用 node 把頁面的 esc 與「邏輯表 start」到「邏輯表 end」標記之間切出來直接執行。
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
command -v node >/dev/null || fail "需要 node 才能跑邏輯表的網頁測試"

node - "$OPSX_ROOT/herdr-board/web/index.html" <<'JS' || fail "邏輯表網頁規則"
const fs = require('node:fs');
const assert = require('node:assert');
const html = fs.readFileSync(process.argv[2], 'utf8');
const START = '/* 邏輯表 start */', END = '/* 邏輯表 end */';
const s = html.indexOf(START), e = html.indexOf(END);
if (s < 0 || e < s) throw new Error(`index.html 找不到標記 ${START} / ${END}`);
const es = html.indexOf('const esc='), ee = html.indexOf('\n', es);
if (es < 0) throw new Error('index.html 找不到 const esc=');
const {logicMapSection, logicMapScroll, restoreLogicMapScroll} =
  new Function(html.slice(es, ee) + html.slice(s, e) + ';return {logicMapSection, logicMapScroll, restoreLogicMapScroll};')();

const unesc = t => t.replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&quot;/g, '"').replace(/&amp;/g, '&');
const preText = h => { const m = h.match(/<pre class="term logic-map"[^>]*>([\s\S]*)<\/pre>/); assert.ok(m, '要有 <pre class="term logic-map">：' + h); return m[1]; };

// 顯示原文
const map = '# 邏輯表：x\n┌─┐\n│a│\n└─┘';
const h = logicMapSection({logic_map: map});
assert.ok(h.includes('<h3>邏輯表'), '有「邏輯表」段：' + h);
assert.strictEqual(unesc(preText(h)), map, 'pre 的文字跟 logic_map 一字不差');
const rule = sel => (html.match(new RegExp('\\n' + sel.replace(/\./g, '\\.') + '\\{[^}]*\\}')) || [''])[0];
assert.ok(rule('.term').includes('overflow-x:auto'), '.term 可橫向捲動：' + rule('.term'));
assert.ok(/white-space:pre[;}]/.test(rule('.term.logic-map')), '.term.logic-map 蓋掉 pre-wrap、不折行：' + rule('.term.logic-map'));

// HTML 以文字顯示
const b = logicMapSection({logic_map: '<b>粗</b> & "q"'});
assert.ok(!b.includes('<b>'), '不能出現真的 <b>：' + b);
assert.strictEqual(unesc(preText(b)), '<b>粗</b> & "q"', '顯示字面上的標籤');

// 沒有邏輯表
assert.strictEqual(logicMapSection({logic_map: null}), '', 'null 不顯示');
assert.strictEqual(logicMapSection({}), '', '沒有 key 不顯示');
assert.strictEqual(logicMapSection({logic_map: ''}), '', '空字串不顯示');

// 重畫後同一張卡留住橫向捲動，換卡從頭開始（抽屜每次 collect 變動都用 innerHTML 重建）
const pre = (k, left = 0) => ({dataset: {key: k}, scrollLeft: left});
const drawer = p => ({querySelector: sel => (sel === 'pre.logic-map' ? p : null)});
assert.ok(logicMapSection({repo: 'r', slug: 'x', logic_map: map}).includes('data-key="r/x"'), 'pre 要帶卡的 key');
const pos = logicMapScroll(drawer(pre('r/x', 240)));
const same = pre('r/x'); restoreLogicMapScroll(drawer(same), pos);
assert.strictEqual(same.scrollLeft, 240, '同一張卡重畫後留在 240');
const other = pre('r/y'); restoreLogicMapScroll(drawer(other), pos);
assert.strictEqual(other.scrollLeft, 0, '換卡從 0 開始');
restoreLogicMapScroll(drawer(null), pos);
const fresh = pre('r/x'); restoreLogicMapScroll(drawer(fresh), logicMapScroll(drawer(null)));
assert.strictEqual(fresh.scrollLeft, 0, '原本沒有邏輯表段時從 0 開始');
// 細節頁畫在 #view：render() 重寫 #view 前記下、之後放回
const r = html.slice(html.indexOf('function render(){'), html.indexOf('\n}', html.indexOf('function render(){')));
assert.ok(/const lmPos=logicMapScroll\(\$\('#view'\)\);[\s\S]*setView\(\$\('#view'\),[\s\S]*restoreLogicMapScroll\(\$\('#view'\),lmPos\)/.test(r),
  'render 要在重寫 #view 前記下、之後放回：' + r);

// 位置：細節頁的合併請求段之後、紀錄段之前
const pc = html.slice(html.indexOf('function pageCard('), html.indexOf('\n}', html.indexOf('function pageCard(')));
assert.ok(pc.includes('${mr}${logicMapSection(c)}${logSec}'), 'pageCard 要把邏輯表段放在 mr 與 logSec 之間');

// 合併請求段的合併鈕跟等待你段一樣看 waiting.type：MR 五條件全綠但邏輯表沒對到、pane 還在跑時沒有合併鈕（board-mergeable-needs-map）
const ms = html.indexOf('  const mr=c.mr&&c.mr.url?'), me = html.indexOf('\n', ms);
if (ms < 0) throw new Error('index.html 找不到細節頁的 const mr=');
const mrSection = c => new Function('c', html.slice(es, ee) + html.slice(ms, me) + ';return mr;')(c);
const MR = {url: 'https://x/-/merge_requests/1', state: 'ready'};
assert.ok(mrSection({mr: MR, waiting: {type: '可以合併'}}).includes('data-act="merge"'), '可以合併：有合併鈕');
const off = mrSection({mr: MR, waiting: null});
assert.ok(!off.includes('data-act="merge"') && off.includes('卡在 ready'), 'MR ready 但不是可以合併：沒有合併鈕，顯示卡在 …：' + off);
const gate = mrSection({mr: MR, waiting: {type: '等待決定'}});
assert.ok(!gate.includes('data-act="merge"'), 'MR ready 但等的是別的 gate：沒有合併鈕：' + gate);

// 看板原型的樣本快照：等待類型是可以合併的卡，合併請求段也有合併鈕
const sample = JSON.parse(fs.readFileSync(require('node:path').join(process.argv[2], '..', '..', 'tests', 'fixtures', 'collect-sample.json'), 'utf8'));
const ready = sample.cards.filter(c => c.waiting && c.waiting.type === '可以合併');
assert.ok(ready.length > 0, '樣本要有可以合併的卡');
for (const c of ready) assert.ok(mrSection(c).includes('data-act="merge"'), `樣本 ${c.slug} 的合併請求段要有合併鈕`);
JS
echo ok
