// Opens the game page in Firefox (WebDriver BiDi, --remote-debugging-port=9222), waits for the 3D view, then moves
// the mouse pointer slowly over it for `secs` seconds (plugins/moth.jl: the pointer is a moth) and saves screenshots.
// usage: node moth.mjs <outdir> [secs]
import fs from "node:fs";
const OUT = process.argv[2], SECS = Number(process.argv[3] || 10);
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
await send("browsingContext.navigate", { context: ctx, url: "http://192.168.178.59:8790/", wait: "none" });
const evaluate = async expr => (await send("script.evaluate", { expression: expr, target: { context: ctx }, awaitPromise: true })).result;
for (let i = 0; i < 120; i++) { const r = await evaluate("document.querySelectorAll('canvas').length"); if (r.value > 0) break; await sleep(500); }
console.log("page open");
await sleep(4000);
const rect = JSON.parse((await evaluate("JSON.stringify(document.querySelector('canvas').getBoundingClientRect())")).value);
console.log("canvas", rect.width, rect.height);
const t0 = Date.now(); let k = 0;
while ((Date.now() - t0) / 1000 < SECS) {
  const u = (Date.now() - t0) / 1000;
  const x = Math.round(rect.left + rect.width * (0.3 + 0.15 * Math.sin(u * 0.9)));
  const y = Math.round(rect.top + rect.height * (0.55 + 0.1 * Math.sin(u * 1.7)));
  await send("input.performActions", { context: ctx, actions: [{ type: "pointer", id: "m", actions: [{ type: "pointerMove", x, y, duration: 150 }] }] });
  if (++k % 20 == 0) { const r = await send("browsingContext.captureScreenshot", { context: ctx });
    fs.writeFileSync(`${OUT}/moth-page-${k}.png`, Buffer.from(r.data, "base64")); console.log("shot", k, x, y); }
}
await send("session.end").catch(() => {});
process.exit(0);
