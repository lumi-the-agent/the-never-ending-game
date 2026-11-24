---
name: evidence
description: How to prove your work works before marking a todo done - screenshots of the dashboard, frame times, path traced stills, and an honest self check against what the reviewer will judge.
---

# Evidence

A separate reviewer judges every session without seeing your conversation.
They read the todo's result and look at the sandbox game (with the
session's work). Give them something to look at:

1. `live_screenshot("media/<date>/<what>.png")` while your change is visible
   (move the camera with `live_eval("game.rig.mode = :orbit")` or set
   `game.rig.subject`). Open the png and look at it yourself first.
2. `live_status()["frame_ms"]`: the frame median/p95 and your system's cost.
3. For beauty shots: `submit_job(:trace; path = ..., samples = 128)`.
4. `publish(why = "...")` so the human's game has it too.
5. `done!(id, "what changed; screenshot: media/...; frame p95 21 ms (was 20); how to see it: Play menu → …")`

Check yourself the way the reviewer will (their rubric: works in the
game, readable and visible at 1280×720, fun, fast, code that does not
duplicate or hide errors). If something is weak, say so in the result and add
a todo, rather than letting the reviewer find it.
