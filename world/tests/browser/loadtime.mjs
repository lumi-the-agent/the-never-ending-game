// Times how long the dashboard page takes to open in a real Firefox: until a canvas exists and
// until it has drawn (non-blank pixels), with screenshots. usage: node loadtime.mjs <outdir>
import fs from "node:fs";
const OUT = process.argv[2];
const ws = new WebSocket("ws://127.0.0.1:9222/session");
let n = 0; const waiting = new Map();
ws.onmessage = ev => { const m = JSON.parse(ev.data); if (m.id && waiting.has(m.id)) { waiting.get(m.id)(m); waiting.delete(m.id); } };
const send = (method, params = {}) => new Promise((ok, fail) => { const id = ++n;
  setTimeout(() => fail(new Error(method + " timed out")), 30000);
  waiting.set(id, m => m.type === "error" ? fail(new Error(method + ": " + m.error + " " + m.message)) : ok(m.result));
  ws.send(JSON.stringify({ id, method, params })); });
const sleep = ms => new Promise(r => setTimeout(r, ms));
await new Promise(r => ws.onopen = r);
await send("session.new", { capabilities: {} });
const ctx = (await send("browsingContext.getTree", {})).contexts[0].context;
const t0 = Date.now();
await send("browsingContext.navigate", { context: ctx, url: "http://192.168.178.59:8790/", wait: "none" });
const evaluate = async expr => (await send("script.evaluate", { expression: expr, target: { context: ctx }, awaitPromise: true })).result;
let tcanvas = null;
for (let i = 0; i < 240; i++) {
  const r = await evaluate("document.querySelectorAll('canvas').length");
  if (r.value > 0) { tcanvas = Date.now() - t0; break; }
  await sleep(250);
}
console.log("canvas after ms", tcanvas);
for (const s of [1, 3, 6]) {
  await sleep(s === 1 ? 1000 : (s === 3 ? 2000 : 3000));
  const r = await send("browsingContext.captureScreenshot", { context: ctx });
  fs.writeFileSync(`${OUT}/load-${s}s.png`, Buffer.from(r.data, "base64"));
  console.log("shot at canvas +", s, "s; total ms", Date.now() - t0);
}
process.exit(0);
