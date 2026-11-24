"""Talk to a running game over its live socket (one JSON request per line).

    python3 -I tools/live.py status [--live]
    python3 -I tools/live.py eval 'length(game.world.creatures)' [--live]
    python3 -I tools/live.py screenshot /abs/path.png [--live]
    python3 -I tools/live.py reload

Use when no Julia MCP session is available. `--live` only to LOOK at the human's game.
"""
import json, socket, sys, random

ROOT = "/sim/Programmieren/SimGame/world"

def live(cmd, game="sandbox", timeout=600, **kw):
    sock = f"{ROOT}/run/game.sock" if game == "live" else f"{ROOT}/sandbox/run/game.sock"
    msg = {"id": random.randint(1, 10**9), "cmd": cmd, **kw}
    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    s.settimeout(timeout)
    s.connect(sock)
    s.sendall((json.dumps(msg) + "\n").encode())
    buf = b""
    while not buf.endswith(b"\n"):
        chunk = s.recv(1 << 20)
        if not chunk:
            break
        buf += chunk
    s.close()
    return json.loads(buf)

if __name__ == "__main__":
    args = [a for a in sys.argv[1:] if a != "--live"]
    game = "live" if "--live" in sys.argv else "sandbox"
    cmd = args[0]
    if cmd == "eval":
        code = args[1] if args[1] != "-" else sys.stdin.read()
        a = live("eval", game, code=code)
    elif cmd == "screenshot":
        a = live("screenshot", game, path=args[1])
    else:
        a = live(cmd, game)
    if a.get("ok") is not True:
        print("ERROR:", a.get("error", a), file=sys.stderr)
        sys.exit(1)
    if cmd == "eval":
        print(a["result"])
    elif cmd == "status":
        print(json.dumps(a["status"], indent=1)[:6000])
    else:
        print(json.dumps(a)[:4000])
