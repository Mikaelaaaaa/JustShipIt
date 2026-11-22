#!/usr/bin/env bash
# 精靈的狀態外觀不受其他元件樣式影響（specs/board-web）。
# 瀏覽器的 cascade 在 node 裡跑不了，這裡守的是它的前提：精靈的狀態 class 不能被 .bot 以外的規則選到。
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
command -v node >/dev/null || fail "需要 node 才能跑精靈測試"

node - "$OPSX_ROOT/herdr-board/web/index.html" <<'JS' || fail "精靈"
const fs = require('node:fs');
const assert = require('node:assert');
const html = fs.readFileSync(process.argv[2], 'utf8');
const escLine = html.match(/^const esc=.*$/m);
if (!escLine) throw new Error('index.html 找不到 const esc=');
const s = html.indexOf('function bot('), e = html.indexOf('\n}\n', s);
if (s < 0 || e < 0) throw new Error('index.html 找不到 function bot(');
const bot = new Function(escLine[0] + '\n' + html.slice(s, e + 2) + ';return bot;')();

const css = html.slice(html.indexOf('<style>') + 7, html.indexOf('</style>'));
const selectors = [...css.matchAll(/([^{}]+)\{/g)]
  .flatMap(m => m[1].split(','))
  .map(x => x.trim())
  .filter(x => x && !x.startsWith('@'));

const cards = {
  ask: {waiting: {type: '等待決定'}},
  wait: {waiting: {type: '可以合併'}},
  work: {waiting: null, agent_status: 'working'},
  sleep: {waiting: null, agent_status: 'idle'},
};
for (const [st, c] of Object.entries(cards)) {
  const svg = bot(c, 30);
  const cls = svg.match(/^<svg class="([^"]+)"/)[1].split(/\s+/);
  assert.strictEqual(cls[0], 'bot', `${st}：第一個 class 是 bot`);
  for (const tok of cls.slice(1)) {
    const re = new RegExp(`\\.${tok}(?![\\w-])`);
    const stray = selectors.filter(sel => re.test(sel) && !sel.startsWith('.bot'));
    assert.deepStrictEqual(stray, [], `${st}：class ${tok} 被 .bot 以外的規則選到`);
  }
}

// Scenario 沒有接腳：任一狀態都沒有接腳的 rect，機身沒有外框線（specs/board-pages「精靈外觀」）
for (const [st, c] of Object.entries({...cards, unsure: {waiting: null, agent_status: null, dispatch: {agent: 'claude'}}})) {
  const svg = bot(c, 30);
  assert.strictEqual((svg.match(/<rect x="\d+" y="(4|54)" width="4" height="6"/g) || []).length, 0, `${st}：沒有接腳`);
  assert.ok(/<rect x="8" y="10" width="48" height="44" rx="6" fill="var\(--pet-(claude|codex)-body\)"\/>/.test(svg), `${st}：機身淺藍填色、沒有 stroke：${svg}`);
}
// Scenario ask 有 ring
const ask = bot(cards.ask, 30);
assert.strictEqual((ask.match(/<rect x="(17|35)" y="21" width="12" height="20"/g) || []).length, 2, 'ask 有兩個 ask 眼睛');
assert.ok(ask.includes('class="ring"'), 'ask 有外圈');
assert.ok(/^<svg class="bot bot-ask /.test(ask), 'ask 的第一個 class 是 bot，有 bot-ask');
// claude 與 codex 用不同的填色 class
assert.ok(bot({waiting: null, dispatch: {agent: 'codex'}, agent_status: 'working'}, 30).includes('bot-codex'), 'codex 有 bot-codex');
assert.ok(bot(cards.work, 30).includes('bot-claude'), '預設 claude 有 bot-claude');
// Scenario 不等人的卡不畫 ask
for (const st of ['working', 'idle', null, 'unknown'])
  assert.ok(!/bot-(ask|wait)\b/.test(bot({waiting: null, agent_status: st, dispatch: {agent: 'claude'}}, 30)), `waiting null（${st}）不是 ask 也不是 wait`);
JS
