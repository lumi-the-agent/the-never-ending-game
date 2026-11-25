// Opens the game page in Firefox (WebDriver BiDi, --remote-debugging-port=9222), waits for the 3D view, then
// reports for `secs` seconds how many voice clips the page was asked to play (plugins/voice.jl) and whether the
// clip files load. usage: node voice.mjs <outdir> [secs]
import fs from "node:fs";
const OUT = process.argv[2], SECS = Number(process.argv[3] || 20);
const ws = new WebSocket("ws://127.0.0.1:9222/session");
let n = 0; const waiting = new Map();
ws.onmessage = ev => { const m = JSON.parse(ev.data); if (m.id && waiting.has(m.id)) { waiting.get(m.id)(m); waiting.delete(m.id); } };
const send = (method, params = {}) => new Promise((ok, fail) => { const id = ++n;
  setTimeout(() => fail(new Error(method + " timed out")), 20000);
  waiting.set(id, m => m.type === "error" ? fail(new Error(method + ": " + m.error + " " + m.message)) : ok(m.result));
  ws.send(JSON.stringify({ id, method, params })); });
const sleep = ms => new Promise(r => setTimeout(r, ms));
await new Promise(r => ws.onopen = r);
await send("session.new", { capabilities: {} });
const ctx = (await send("browsingContext.getTree", {})).contexts[0].context;
await send("browsingContext.navigate", { context: ctx, url: "http://192.168.178.59:8790/", wait: "none" });
const evaluate = async expr => (await send("script.evaluate", { expression: expr, target: { context: ctx }, awaitPromise: true })).result;
for (let i = 0; i < 90; i++) { const r = await evaluate("document.querySelectorAll('canvas').length"); if (r.value > 0) break; await sleep(500); }
console.log("page open");
const file = await evaluate("fetch('/lumi/voice/game/hoo.mp3').then(r => r.status + ' ' + r.headers.get('content-type'))");
console.log("clip file:", file.value); await send("input.performActions", { context: ctx, actions: [{ type: "pointer", id: "m", actions: [{ type: "pointerMove", x: 300, y: 300 }, { type: "pointerDown", button: 0 }, { type: "pointerUp", button: 0 }] }] });
const played = await evaluate("new Audio('/lumi/voice/game/yay.mp3').play().then(() => 'played').catch(e => 'refused: ' + e.name)");
console.log("a test clip:", played.value);
for (let t = 0; t < SECS; t += 2) { await sleep(2000); if (t == 4) await send("input.performActions", { context: ctx, actions: [{ type: "pointer", id: "m", actions: [{ type: "pointerMove", x: 320, y: 320 }, { type: "pointerDown", button: 0 }, { type: "pointerUp", button: 0 }] }] });
  console.log(t + 2, "s: clips asked for", (await evaluate("JSON.stringify({notes: window.lumiXylo ? window.lumiXylo.n : null, state: window.lumiXylo ? window.lumiXylo.ctx.state : null, clicks: window.lumiXylo ? window.lumiXylo.clicks : null})")).value); }
const r = await send("browsingContext.captureScreenshot", { context: ctx });
fs.writeFileSync(`${OUT}/xylo-page.png`, Buffer.from(r.data, "base64"));
process.exit(0);
