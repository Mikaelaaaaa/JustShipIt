#!/usr/bin/env bash
# 看板 /api/collect 回 401 時分兩種訊息：網址沒帶 token、server 拒絕 token（specs/board-web「401 的兩種訊息」）。
# 取 collect 的函式寫在網頁的 inline script 裡，這裡用 node 把「collect 錯誤訊息」兩個標記之間切出來，配假的 fetch 執行。
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
command -v node >/dev/null || fail "需要 node 才能跑 401 訊息的網頁測試"

node - "$OPSX_ROOT/herdr-board/web/index.html" <<'JS' || fail "401 的兩種訊息"
const fs = require('node:fs');
const assert = require('node:assert');
const html = fs.readFileSync(process.argv[2], 'utf8');
const START = '/* collect 錯誤訊息 start */', END = '/* collect 錯誤訊息 end */';
const s = html.indexOf(START), e = html.indexOf(END);
if (s < 0) throw new Error(`index.html 找不到標記 ${START}`);
if (e < s) throw new Error(`index.html 找不到 ${START} 之後的標記 ${END}`);
const {fetchCollect} = new Function(html.slice(s, e) + ';return {fetchCollect};')();

const fakeFetch = (status, body) => {
  const seen = [];
  const fn = async (url, opts) => {
    seen.push({url, token: opts.headers['X-Opsx-Token']});
    return {ok: status >= 200 && status < 300, status, text: async () => body, json: async () => JSON.parse(body)};
  };
  fn.seen = seen;
  return fn;
};
const errorOf = async (tok, status, body) => {
  try { await fetchCollect(fakeFetch(status, body), tok); return null; } catch (err) { return err.message; }
};

(async () => {
  // Examples 一般場景
  assert.strictEqual(await errorOf('', 401, '{"error":"token"}'), '網址沒帶 token：從 herdr 的 open-board 重開一次');
  assert.strictEqual(await errorOf('abc', 401, '{"error":"token"}'), 'token 被 server 拒絕：從 herdr 的 open-board 重開一次');
  // Examples 邊界場景
  const f = fakeFetch(200, '{"cards":[]}');
  assert.deepStrictEqual(await fetchCollect(f, 'abc'), {cards: []}, '200 回 collect 的內容，沒有錯誤');
  assert.deepStrictEqual(f.seen, [{url: '/api/collect', token: 'abc'}], 'token 放在 X-Opsx-Token');
  const long = 'x'.repeat(300);
  assert.strictEqual(await errorOf('', 502, long), 'collect 502：' + 'x'.repeat(200), '不是 401 照原本的錯誤訊息');
})().catch(err => { console.error(err); process.exit(1); });
JS
echo ok
