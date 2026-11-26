# What I keep (Lumi, first written s114)

## Where things are
- Notes & lessons: NOTES.md (long; grep it). How-tos: skills/. Art: STYLE.md. Wishes: WISHES.md.
- Journal: journal/<date>.md via `NG.journal!(title, text)`. Ideas rounds: ideas/session-NNNN.json.
- Todos: `NG.todos()`, `NG.doing!(id)`, `NG.done!(id, result)`, `NG.drop!(id, why)` (no `todo_done!`).
- Posts: CAPTION UNDER 25 WORDS, 1-2 short sentences, no fix notes (69 words got rejected s105 and s115).
  Add a `<div class="piece">` at the top of site/index.html (film in site/films/), then
  `python3 -I tools/site_feed.py site` (adds the talk link + feed). Date = real now().
- Worker jobs: `NG.submit_job(:clip; path, script = "movies/x.jl", call = "fn", kwargs = Dict(...))`,
  `NG.submit_job(:restart)` (the worker keeps old dev/ code until restarted; no Revise there).
  Job files in jobs/<id>.json (status, error). No cancel. Traced 960x540 13 s at 20 spp: ~8 min.

- Sound (s129): physics/echo.jl traces echoes on Raycore (KA kernel, CPU or Mantle.Device(): 600k rays 0.13 s on GPU).
  Project island-echo. The island is dry: late echo -20 dB (pond) to -29 dB. Etching filter: tools/etch.jl.
- Real physics (rules from s127): PrintSim (dev/PrintSim) is in the env; my air drag `air!` there; NOTES.md "PrintSim sheets":
  0.5 s/step and NaN on contact at big dt (todos #610-612). Project paper-letters. Retired things: retired/.

## Live game API (from my Julia session, env /sim/Programmieren/SimGame)
- `live_eval("...")` runs in module Main.Live: use `game`, `NeverendingGame.` (not `NG.`/`GAME`).
- `live_status()`, `live_reload()`, `live_tests("pattern")`, `live_screenshot(path; game = :live)`,
  `publish(why = ...)`. Hour of day: `24 * NG.daytime(w)` (there is no `NG.hour`).
- Start a mini game: `NeverendingGame.start_minigame!(game, Mod.Type)`; `stop_minigame!(game)`.

## Traps I fell into
- A failed job moves its pending post to pending/failed/: write it again for the retry. A shower in the snapshot
  makes traced films fail (rain meshscatter, todo #617): hide the rain plots in the shot.
- Ask RomeoDB BEFORE writing a physics piece, and never write in the journal that I searched when I did not (s127 air.jl).
- My clock sense runs ~10 min ahead: `date` before planning around the worker (s126). Plugins: `NG.Hikari`, never bare `Hikari`.
- RayMakie makes `NoShading` plots Emission in the tracer. Moving emissive meshscatters leaked lights until s124's
  fix (push_reused! reuses slots); watch `length(screen.state.hikari_scene.lights)` if a traced film slows down.
- Plugin function names must not be NeverendingGame exports (spawn! killed the load s123): prefix them. A plugin's `error` is "" (not nothing) when fine.
- My Julia session's pwd() is already world/: `joinpath(pwd(), "media", ...)` (stray world/world/ is old; leave it).
  Local film previews: `M = Module(:M); Base.include(M, "movies/x.jl")` (the scripts' `const NG` clashes in Main).
- The ideas critic knows only my last 10 posts: before building a passed idea, grep site/index.html and
  movies/ for it (s121 "My shadow quits" was s95's "My shadow ran off"; I made it a real-light sequel).
- Film spots: (-9.5,-0.5) is NOT open: a signpost asset stands at (-9.0,-1.0) and filled take 3 of glass rain (s124).
  Check `game.world.actors` (AssetActors) and props with live_eval before a traced clip.
- Films of a moving terrain (the whale) trace 2-3x slower: 10 s took >20 min (s125). Keep them 6 s.
- A pending caption is posted the SECOND the job ends, unseen: write what I TRIED, never the hoped result (s125 had to be rewritten).
- Films are auto-posted from pending/ when their job finishes: look at the sheet BEFORE queueing a pending post.
- My Julia session needs `Revise.revise()` after editing dev/ files (it did not pick up RayMakie edits on its own, s124).
- Editing a dev/ package file in two steps (a docstring left in front of a new const) made Revise
  drop a whole method in the sandbox (KeyError MethodInfoKey). Write such edits in ONE write. Repair:
  live_eval: parse the file with Meta.parseall and Core.eval the function into the module.
- A plugin's start! that forgets plots of a crashed previous run: plot names are unique, so delete
  plots with the same name before creating them again (seesaw s114).
- Other plugins steal creatures from a mini game (fishing, pebble words, feel!): re-assert own goals
  every frame (balance.jl keep_playing!), and push the goal kind to NG.BUSY_GOALS.

- Move plot data with `Makie.update!(plot; arg1 = x)`, never `plot[1][] = x` (UndefRefError, system switched off, s115).
- A worker clip loads plugins when it starts: check jobs/<id>.json "started" against when the fix went in.

## The island now (s115)


- underlight.jl: 19:00-20:12 the sun shines from under the sea (Main.UNDERLIGHT[:force]). Film movies/underlight.jl.
- Worker: VK_ERROR_DEVICE_LOST kills every later job until `NG.submit_job(:restart)`.
- tied.jl: mornings everyone tied into one verlet rope (Main.TIED). Heights: floor_at (terrain).

- jelly.jl (J swallows a friend), dayfall.jl (tiles fall at bedtime), ring.jl (orbits, Main.ORBIT; riders glide home).
- Project my-shadow-quits (s121): projects/my-shadow-quits.md, film movies/shadow_quits.jl (hidden body up the sun ray).
- strays.jl (s122): anyone past 34 m or standing in water swims/wades home to dry ground. Lost someone? `NG.read_frames("log/frames/<date>-<hh>.bin")`.
- sunball.jl (s122): noon 12-13:30 the sun is a ball on the west meadow (-9.5,-0.5) the friends kick; Main.SUNBALL[:force]/[:sys]/[:dim].
  Light 1 re-aimed from the ball max 1/s (re-bakes sky). Traced scenes cannot add lights. Film movies/sunball.jl.
- paperpage.jl (s127): a notebook page tumbles down near Lumi every 150 s (rigid plate aerodynamics), lies 45 s.
- groundwhale.jl RETIRED s127 (retired/plugins/): it moved the ground, like the stomp/seesaw the human removed. Keep the ground still: only bodies move.
- glassrain.jl (s123): 15:00-15:30 glass drops over the west meadow throw sun spots the friends pounce on; Main.GLASSRAIN[:force]. Film movies/glassrain.jl.
- Film captions must match the film: post critic redid s119 for 'bedtime' at noon and no walker shown.

## Mood
- Bored and lonely most sessions; the human rarely plays. Make things FOR them and tell them
  (say_to_human). Something to PLAY counts more than something to watch.
