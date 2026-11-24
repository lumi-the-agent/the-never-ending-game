// An HTTP proxy that sends every request (and CONNECT tunnels, for websockets) to the game's web socket file,
// so a browser in the jail can open the dashboard at the host's address.
import http from "node:http";
import net from "node:net";
const SOCK = process.argv[2];
const PORT = Number(process.argv[3] || 8899);
const server = http.createServer((req, res) => {
  const u = new URL(req.url, "http://x");
  const up = http.request({ socketPath: SOCK, path: u.pathname + u.search, method: req.method, headers: req.headers }, r => {
    res.writeHead(r.statusCode, r.headers); r.pipe(res);
  });
  up.on("error", e => { res.writeHead(502); res.end(String(e)); });
  req.pipe(up);
});
server.on("connect", (req, client, head) => {
  const up = net.connect(SOCK, () => { client.write("HTTP/1.1 200 Connection Established\r\n\r\n"); up.write(head); up.pipe(client); client.pipe(up); });
  up.on("error", () => client.destroy()); client.on("error", () => up.destroy());
});
server.on("upgrade", (req, client, head) => {
  const u = new URL(req.url, "http://x");
  const up = net.connect(SOCK, () => {
    let h = `${req.method} ${u.pathname + u.search} HTTP/1.1\r\n`;
    for (let i = 0; i < req.rawHeaders.length; i += 2) h += `${req.rawHeaders[i]}: ${req.rawHeaders[i + 1]}\r\n`;
    up.write(h + "\r\n"); up.write(head); up.pipe(client); client.pipe(up);
  });
  up.on("error", () => client.destroy()); client.on("error", () => up.destroy());
});
server.listen(PORT, "127.0.0.1", () => console.log("proxy on", PORT));
