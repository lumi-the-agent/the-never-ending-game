---
name: julia-workflow
description: How to run Julia in the Neverending Game - persistent MCP sessions with Revise, compile times, background runs, code style rules. Read before writing or running any Julia code.
---

# Julia here

- Run Julia only through the `julia` MCP tools (`bt_julia_eval`), always with
  `env_path` = the game root (`$NEVERENDING_ROOT`, the folder above `world/`).
  A session keeps its loaded packages, variables and compiled code; `julia -e`
  in a shell starts from zero every time (RayMakie alone takes minutes).
- Revise is loaded: edit a file in `dev/NeverendingGame/src` and call the
  function again. Struct changes work too. If an edit seems ignored,
  `Revise.revise()` shows the error (it never is the file cache).
- Long work: `bt_julia_eval(...; background = true)` returns a run id, then
  `bt_julia_wait(runs = [...], seconds = ...)`. Never sleep-poll.
- `bt_julia_restart` only when a session is broken; it costs the compile time.
- First `using NeverendingGame` in a fresh session: a few minutes (RayMakie,
  Hikari). Load it once and keep the session.

## Testing without a running game

```julia
using NeverendingGame; const NG = NeverendingGame
w = NG.new_world()                     # or NG.load_snapshot("world/state/world.json")
for _ in 1:300; NG.step!(w, 1/30); end
g = NG.Game(; fps = 30)                # like your sandbox (world/plugins), but here: plugins load, no sockets
NG.frame!(g, 1/30)
```

Offscreen pictures: `NG.screenshot(path, w; samples = 64)` (path traced, slow),
or build a `Stage` in your own scene and use a raster `RayMakie.Screen`.

## Style the human insists on

- Never `try ... catch end` that hides an error. Catch only a specific,
  expected exception, and report it.
- No globals for state: put it in a struct (a "context") and pass it.
- Use multiple dispatch, not `if x isa ...` chains.
- Know the types you work with instead of guarding with `hasproperty`.
- Short, precise names and comments; no essays in code.
