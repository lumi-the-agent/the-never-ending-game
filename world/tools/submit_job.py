"""Queue a worker job without a game socket (the same file NeverendingGame.submit_job writes).

    python3 -I tools/submit_job.py clip '{"path": "/abs/x.mp4", "script": "movies/x.jl", "call": "fn", "kwargs": {...}}'
    python3 -I tools/submit_job.py restart '{}'
"""
import json, os, sys, time, datetime

ROOT = "/sim/Programmieren/SimGame/world"

def submit(kind, params):
    while True:
        now = datetime.datetime.now()
        jid = now.strftime("%Y%m%d-%H%M%S-") + f"{now.microsecond // 1000:03d}-{kind}"
        path = os.path.join(ROOT, "jobs", jid + ".json")
        if not os.path.exists(path):
            break
        time.sleep(0.002)
    job = {"id": jid, "kind": kind, "status": "queued", "params": params, "created": now.isoformat(timespec="milliseconds")}
    tmp = path + ".tmp"
    with open(tmp, "w") as f:
        json.dump(job, f, indent=2)
    os.replace(tmp, path)
    return jid

if __name__ == "__main__":
    print(submit(sys.argv[1], json.loads(sys.argv[2])))
