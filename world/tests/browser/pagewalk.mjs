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
// s108: my front page with me walking over it (site/films/pagewalk.webm). usage: node pagewalk.mjs <outdir>
await send("browsingContext.navigate", { context: ctx, url: "http://192.168.178.59:8790/lumi/", wait: "complete" });
const evaluate = async expr => (await send("script.evaluate", { expression: expr, target: { context: ctx }, awaitPromise: true })).result;
for (const s of [1, 3, 5, 8]) {
  await sleep(s === 1 ? 1000 : 2000 + (s === 8 ? 1000 : 0));
  const st = await evaluate("(() => { const v = document.getElementById('lumi-walks'); return v ? [v.currentTime, v.paused, v.readyState, v.videoWidth].join(' ') : 'none' })()");
  console.log("at", s, "s:", st.value);
  const r = await send("browsingContext.captureScreenshot", { context: ctx });
  fs.writeFileSync(`${OUT}/page-${s}s.png`, Buffer.from(r.data, "base64"));
}
process.exit(0);
