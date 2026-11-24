---
name: live-game
description: Look at and change the running games - your sandbox and the human's - status, frame times, evaluate code inside, screenshots of the dashboard, plugin reload, publishing to the human. Use whenever you need to see or check the world.
---

# The running games

Two game processes run, each in its own jail: the human's game (the dashboard
they watch and play) and your sandbox, a copy of it. The sandbox runs the
plugins you edit (`world/plugins`) and every engine edit within a second; the
human's game runs the published copies (`world/live/plugins`) and takes engine
edits only when you publish. The sandbox starts as a copy of the human's world
each time it starts; world edits made there with `live_eval` (a placed asset,
a moved prop) never reach the human: anything meant to last belongs in a
plugin, then `publish()`.

From your Julia session (after `using NeverendingGame`), everything goes to
your sandbox unless you pass `game = :live`:

```julia
live_status()                      # frame times per part, plugins (ok/error), systems, mini games
live_eval("length(game.world.creatures)")        # runs between two frames, `game` is the Game
live_eval("game.rig.mode = :orbit")              # change things live
live_screenshot(joinpath(pwd(), "media", "now.png"))  # the sandbox's dashboard, as png; open it and look
live_screenshot(path; game = :live)   # what the human sees right now (look, never change the human's game)
live_reload()                      # load changed plugins now, returns each plugin's state
live_path_tracing(true)            # the RayMakie screen path traces (progressive); false: raster again
publish(why = "golden flower field")   # into the human's game: engine edits + every changed plugin that loads
```

`publish()` answers which plugins were `published`, `removed`, `waiting` (the
human plays that plugin's mini game: it is swapped in when the game ends) and
`refused` (does not load: the published version keeps running). Publish each
piece of work as soon as it is verified in the sandbox; the host publishes
whatever is left after every session. Every system hears about a publish in
the human's game through `published!(system, game, plugins)`.

- `live_eval` code runs inside the frame: keep it short (it costs frame time,
  which shows up in `live_status()["frame_ms"]`). Errors come back as text.
- Frame budget: 33 ms at 30 fps. `frame_ms` has median and p95 for `frame`,
  `sim`, `actors`, `sync`, `panels`, `render`, every `system:<plugin>.<Type>`
  and every `live:<cmd>`. Three slow minutes in a row become a perf todo.
- Each game has one dashboard figure: RayMakie draws it on the game's machine
  (window, or offscreen for screenshots and tests), browsers draw the same
  figure with WGLMakie. Plots must work in both: RayMakie reads `material`
  (Hikari), WGLMakie uses `color`. Lights too (`stage_lights`): RayMakie
  lights with the `SunSkyLight` (sun and sky) and its film (`FILM_EXPOSURE`,
  ACES); WGLMakie sees the sun as a plain directional light plus the
  `AmbientLight`, which RayMakie ignores under a sky. Judge the browser look
  in a browser, not from a RayMakie screenshot.
- The `Game` fields worth knowing: `world` (creatures, props, actors, island,
  t), `plugins`, `systems`, `rig` (camera: mode `:follow`/`:orbit`/`:fixed`,
  `subject`), `minigame`, `stage` (the RayMakie scene: `game.stage.scene`),
  `dash` (the dashboard figure: `game.dash.fig`).
- Engine edits (`dev/NeverendingGame/src`) apply to the sandbox within a
  second (the human's game: at `publish()`): both run with Revise and call
  each frame in the latest world. Check
  `live_status()` afterwards. A syntax error leaves the old code running (the
  error is in the game's log). When a change needs a fresh process (a changed
  struct the game holds), `live("shutdown")`: the host restarts the
  sandbox, which takes about two minutes of compilation. The human's game
  takes struct changes at `publish()` (Revise); restart it only if that fails.
- When a game crashes, the host restarts it and your next session prompt
  shows the log (`.jail/logs/game.log` for the human's, `sandbox.log` for
  yours). Each saves its world every 5 minutes (`world/state/world.json`, the
  sandbox's in `world/sandbox/state/`).
