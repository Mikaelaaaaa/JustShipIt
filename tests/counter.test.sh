#!/usr/bin/env bash
# 總覽「等你」格的「全部 N」（specs/board-pages「總覽」：含範圍外的待處理數連結「全部 N」，點了把範圍切回全部）。
# 組字寫在網頁的 inline script 裡，這裡用 node 把 counterHtml 從 index.html 切出來直接執行。
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
command -v node >/dev/null || fail "需要 node 才能跑等你計數測試"

node - "$OPSX_ROOT/herdr-board/web/index.html" <<'JS' || fail "等你計數"
const fs = require('node:fs');
const assert = require('node:assert');
const html = fs.readFileSync(process.argv[2], 'utf8');
const START = 'function counterHtml', END = '/* ---------- 精靈';
const s = html.indexOf(START), e = html.indexOf(END);
if (s < 0) throw new Error(`index.html 找不到標記 ${START}`);
if (e < s) throw new Error(`index.html 找不到 ${START} 之後的標記 ${END}`);
const counterHtml = new Function(html.slice(s, e) + ';return counterHtml;')();

const W = {type: '等待決定', gate_id: 'g1'};
const card = (repo, waiting) => ({repo, slug: repo + '-x', waiting});
const inA = c => c.repo === 'a';
const all = () => true;
const own = c => !!c.waiting;
const cards = [card('a', W), card('b', W), card('b', W), card('a', null)];

// 範圍外也有卡在等：連結寫全部的數字
const scoped = counterHtml(cards, inA, own);
assert.strictEqual(scoped, '<button class="link" data-act="scope-all">全部 <b>3</b></button>', '範圍視圖顯示全部的等你數');
assert.ok(!scoped.includes('範圍外'), `連結文字不含「範圍外」：${scoped}`);
assert.strictEqual(counterHtml([card('b', W)], inA, own), '<button class="link" data-act="scope-all">全部 <b>1</b></button>',
  '範圍內是零時也顯示全部的等你數');

// 範圍內外一樣多、全部範圍、沒有卡：不畫連結（大數字已經是全部）
assert.strictEqual(counterHtml([card('a', W), card('b', null)], inA, own), '', '範圍外沒有在等的卡');
assert.strictEqual(counterHtml(cards, all, own), '', '範圍是全部');
assert.strictEqual(counterHtml([], all, own), '', '沒有卡');

// 收進 session 的主 change 卡照常各算一張（D6：看板不再把主 change 收成一張 session 卡）
const folded = (repo, waiting) => ({...card(repo, waiting), session: repo + '/f'});
assert.strictEqual(counterHtml([folded('b', W), folded('b', W), card('a', null)], inA, own),
  '<button class="link" data-act="scope-all">全部 <b>2</b></button>', '同一個 session 的兩張在等的卡算 2');

// 範圍外的主 change 只有子 change 在等：「等你」的判斷由呼叫端傳入，子 change 等你的卡也算
const subOnly = {...folded('b', null), subWait: true};
assert.strictEqual(counterHtml([subOnly], inA, c => own(c) || !!c.subWait),
  '<button class="link" data-act="scope-all">全部 <b>1</b></button>', '範圍外只有子 change 在等：全部 N 要算到它');

// 切片外的接線：總覽與頂列的等你數都經 waitsOnYou（自己的 gate 或子 change 的 gate）
const ov = html.slice(html.indexOf('function overview('), html.indexOf('\n}', html.indexOf('function overview(')));
assert.ok(ov.includes('counterHtml(liveCards(),inScope,waitsOnYou)'), '總覽要經 counterHtml 畫等你格的全部 N：' + ov);
assert.ok(ov.includes('cards.filter(waitsOnYou)'), '等你格的大數字算子 change 等你的卡');
const top = html.slice(html.indexOf('function renderTop('), html.indexOf('\n}', html.indexOf('function renderTop(')));
assert.ok(top.includes('fCards().filter(waitsOnYou)'), '頂列看板的等你數算子 change 等你的卡');
assert.ok(html.includes('const waitsOnYou=c=>needsYou(c)||subWaiting(c,data.sessions||[]).length>0;'), 'waitsOnYou 的定義');
const act = /data-act="([^"]+)"/.exec(scoped)[1];
assert.ok(html.includes(`if(a==='${act}'){setScope('all');return;}`), `click handler 要處理 data-act="${act}"，並把範圍切回全部`);
JS
