// Opens the game page in Firefox (WebDriver BiDi, --remote-debugging-port=9222) and checks the "Click once on the
// island to hear Lumi" note (plugins/voice.jl hint!): shown on a new page, gone after the first click.
// usage: node hint.mjs <outdir>
import fs from "node:fs";
const OUT = process.argv[2];
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
for (let i = 0; i < 120; i++) { const r = await evaluate("document.querySelectorAll('canvas').length"); if (r.value > 0) break; await sleep(500); }
console.log("page open");
const note = "String([...document.querySelectorAll('div')].filter(d => d.textContent === 'Click once on the island to hear Lumi').length)";
let shown = "0";
for (let i = 0; i < 20 && shown === "0"; i++) { await sleep(1000); shown = (await evaluate(note)).value; }
console.log("note shown:", shown);
const r = await send("browsingContext.captureScreenshot", { context: ctx });
fs.writeFileSync(`${OUT}/hint-page.png`, Buffer.from(r.data, "base64"));
await send("input.performActions", { context: ctx, actions: [{ type: "pointer", id: "mouse", actions: [
  { type: "pointerMove", x: 400, y: 400 }, { type: "pointerDown", button: 0 }, { type: "pointerUp", button: 0 }] }] });
await sleep(500);
console.log("note after a click:", (await evaluate(note)).value);
process.exit(0);
