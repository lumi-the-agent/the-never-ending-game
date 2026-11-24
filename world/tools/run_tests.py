"""Run sandbox UI tests whose names contain a substring and print the results (no Julia MCP needed).

    python3 -I tools/run_tests.py "a first play with only W/A/D"
"""
import sys, time
sys.path.insert(0, "/sim/Programmieren/SimGame/world/tools")
from live import live

pat = sys.argv[1]
st = live("test", pattern=pat, timeout=150)
while not st.get("started"):
    time.sleep(2)
    st = live("test", pattern=pat, timeout=150)
print("tests:", st.get("tests"))
while True:
    time.sleep(2)
    s = live("test_status")
    if not s["running"]:
        for r in s["results"]:
            print(r.get("passed"), round(r.get("seconds") or 0, 1), r.get("name"), "\n   ", str(r.get("error"))[:700])
        break
