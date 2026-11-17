#!/usr/bin/env bash
# 看板網頁的停住原因：沒有 waiting 時顯示「停住：<原因>」與時:分，有 waiting 或 stopped 是 null 時不顯示（specs/board-stop-reason）。
# 規則寫在網頁的 inline script 裡，這裡用 node 把「停住 start」到「停住 end」標記之間切出來直接執行。
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
command -v node >/dev/null || fail "需要 node 才能跑停住原因的網頁測試"

node - "$OPSX_ROOT/herdr-board/web/index.html" <<'JS' || fail "停住原因網頁規則"
const fs = require('node:fs');
const assert = require('node:assert');
const html = fs.readFileSync(process.argv[2], 'utf8');
const START = '/* 停住 start */', END = '/* 停住 end */';
const s = html.indexOf(START), e = html.indexOf(END);
if (s < 0 || e < s) throw new Error(`index.html 找不到標記 ${START} / ${END}`);
const esc = x => String(x == null ? '' : x).replace(/[&<>"]/g, c => ({'&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;'}[c]));
const {stoppedNote} = new Function('esc', html.slice(s, e) + ';return {stoppedNote};')(esc);

const at = '2026-11-16T10:05:00+08:00';
// 沒有 waiting：顯示原因與時:分
const h = stoppedNote({waiting: null, status: {phase: 'review', step: 2, total: 5}, stopped: {reason: '等 reviewer（review 站）', at}});
assert.ok(h.includes('停住：等 reviewer（review 站）'), '要有停住原因：' + h);
assert.ok(h.includes('10:05'), '要有時:分：' + h);
assert.ok(!stoppedNote({waiting: null, stopped: {reason: '<b>x</b>', at}}).includes('<b>'), '原因要 escape');
// 有 waiting：只顯示 waiting
assert.strictEqual(stoppedNote({waiting: {type: '等待決定', question: 'q'}, stopped: {reason: '等人答 gate（apply 站）', at}}), '', '有 waiting 不顯示');
// stopped 是 null 或沒有這個鍵：不顯示
assert.strictEqual(stoppedNote({waiting: null, stopped: null}), '', 'stopped null 不顯示');
assert.strictEqual(stoppedNote({waiting: null}), '', '舊資料沒有 stopped 不顯示');
// agent 在跑：舊的停住原因不顯示；idle 或 herdr 查不到（null）照舊顯示
const stopped = {reason: '等 reviewer（review 站）', at};
assert.strictEqual(stoppedNote({waiting: null, agent_status: 'working', stopped}), '', 'working 不顯示');
assert.ok(stoppedNote({waiting: null, agent_status: 'idle', stopped}).includes('停住：'), 'idle 要顯示');
assert.ok(stoppedNote({waiting: null, agent_status: null, stopped}).includes('停住：'), 'agent_status null 要顯示');

// 進行中那一列接在進度後面
assert.ok(html.includes('${prog}${mrNote}${stoppedNote(c)}'), '進行中列放進停住原因');
JS
echo ok
