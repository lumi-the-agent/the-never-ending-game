# The Neverending Game: your notes

This file is yours: what you know about how things work here and the
lessons you learned. The host does not show it to you; read what you need
when you need it. Keep it true: fix what is wrong, add what you learn.

## Where things are

| path | what |
| --- | --- |
| `world/` | the game: your working directory |
| `world/plugins/*.jl` | what you add to the game (hot reloaded by your sandbox game; `publish()` brings them into the human's) |
| `world/live/plugins/` | the published copies the human's game runs (read only: only `publish()` changes them) |
| `world/state/` | the human's game: `world.json` (latest world), `perf.json`, `timing.json`; `todos.json` (yours, for both games) |
| `world/site/` | Lumi's own pages (static html, images, videos), served at `http://<the human's address>:8790/lumi/` (goal 4) |
| `world/sandbox/` | your sandbox game: its own `state/` (a copy of the human's world at its start), `log/`, `run/` (sockets) |
| `world/log/` | `events-<date>.jsonl` (everything that happened), `frames/` (poses for replays), `agent-<date>.jsonl` (your activity) |
| `world/journal/` | your journal, one entry per session |
| `world/assets/` | generated images and meshes, `catalog.json` |
| `world/jobs/` | queued and finished worker jobs |
| `world/media/` | screenshots, clips, renders |
| `world/reviews/` | the reviewers' verdicts, `quality.jsonl` (the scores over time) |
| `world/STYLE.md` | your art direction: palette, shapes, materials, light, mood |
| `world/inbox/`, `world/outbox/` | messages from and to the human |
| `world/skills/` | how-tos (below) |
| `world/patches/` | changes you need in read only checkouts, for the human |
| `../dev/NeverendingGame/src` | the engine (yours to change) |
| `../dev/Makie`, `../dev/Hikari`, `../dev/Raycore`, `../dev/Lava` | the renderer (Makie, RayMakie, WGLMakie, Hikari): yours to improve; never commit, stash or reset there |
| `../dev/*` (the rest) | JuliaVision, VideoEditor, BonitoAgents, ...: read only |

## Processes

- **game** (`NeverendingGame.run_game()`): the human's world and the dashboard
  they watch, 30 fps target. Runs the published plugins (`world/live/plugins`);
  takes your work only through `publish()`. Restarted by the host when it exits.
- **sandbox** (`run_game(instance = :sandbox)`): your copy to try and test
  things; runs `world/plugins` and every engine edit at once. The `live_*`
  functions, `live_tests`, the tester and the reviewers use it. Its dashboard
  is at port 8791 of the human's address.
- **worker** (`NeverendingGame.run_worker`): slow GPU jobs (assets, traced stills).
- **you**: a session with Julia through the `julia` MCP tools.
- **tester**: another agent who uses the dashboard and mini games after each session and keeps `world/tests`.
- **reviewer**: another agent who judges each session afterwards.
- **perfectionist**: every few sessions a reviewer scores the whole game 0-10
  per category (`world/reviews/quality.jsonl`); its findings become your todos.

## Skills

Read the one you need before you start:

- `skills/julia-workflow/SKILL.md`: sessions, Revise, compile times, style
- `skills/live-game/SKILL.md`: look at and change the running game
- `skills/write-plugin/SKILL.md`: systems, actors, mini games, panels
- `skills/make-asset/SKILL.md`: text → image → 3D mesh → in the world
- `skills/find-existing-code/SKILL.md`: RomeoDB and the checkouts
- `skills/evidence/SKILL.md`: proving that your work works (the reviewer reads it)
- `skills/ui-testing/SKILL.md`: UI tests with Makie's FakeInteraction (the suite runs after every session)
- `skills/make-movie/SKILL.md`: replays and VideoEditor

## Lessons learned

(add here)
- `env_path` for the julia tools is the game root `/sim/Programmieren/SimGame`, not `world/`. Engine edits can restart the sandbox (1-3 min, `live_*` fails meanwhile): wait for `sandbox/run/game.sock`.
- `submit_job` ids carry milliseconds and skip an existing id since s45 (todo #48): no sleep needed between submissions.
- Actor plot names must be unique per actor (asset_<id>_<objectid>), or two of the same asset crash the frame.
- `say_to_human` text appears in the player's "Messages to you" panel: write it for a player, never as dev/test notes (journal is for that).
- Editing a function the frame calls every tick (e.g. `move_heading!` in behavior.jl) can crash the live game with a Revise world-age MethodError ("may be too new"), and the restart then takes 5+ min. Prefer hooks a plugin can fill (like `WALKWAYS`), and batch engine edits so the game restarts once.
- Plugin static scenery: keep plots in a `Main` dict with a version number; on a new version delete and rebuild (deleting works in the raster). `[p1; ps; p2]` with Points splats coordinates: wrap single points as `[p1]`.
- RayMakie raster cannot draw an empty meshscatter (screenshots and frames fail): keep one hidden instance (patches/raymakie-empty-meshscatter.md).
- Two games (since session 46): `live_*` and `live_tests` go to your sandbox, where you may click, start mini games and move the camera freely; the human's game only changes through `publish()`. World edits made with `live_eval` (a `place_asset`, a prop) stay in the sandbox and are gone at its next start: anything meant to last is a plugin (placed in `start!` when missing), then published. Look at the human's game with `game = :live` (`live_status(game = :live)`, `live_screenshot(path; game = :live)`), never change it.
- Engine code that calls methods a plugin defines (game_title, start!, ...) must use `Base.invokelatest`: after a hot reload the plain call sees the old world (the menu showed "FireflyCatch").
- Mini games: start card (goal + keys), clock on first key, visible answer to every key, end card with "R to play again"; the plugin chase camera (`rig.mode = :fixed`, eye behind Lumi) beats the follow view for steering.
- Real browser test (how the human plays): `node tests/browser/proxy.mjs world/sandbox/run/web.sock 8899` (your sandbox; never drive the human's `world/run/web.sock`) (HTTP proxy to the game's web socket; the page loads assets from the host's LAN address), `Xvfb :77` (headless Firefox has no WebGL), `DISPLAY=:77 firefox --remote-debugging-port=9222 --profile /tmp/ffprof` (user.js: proxy 127.0.0.1:8899), then `node tests/browser/drive.mjs media/browser` (WebDriver BiDi: clicks Play, holds keys, screenshots). Never `pkill -f` or `kill $(pgrep -f ...)` with a pattern from your own command line (kills your shell, happened twice); list with `pgrep -a`, then kill the pids in a separate command. One BiDi session at a time: restart Firefox after a hung run.
- Asset prompts: never mention a background ("plain white background" fails the cut-out 3 times). A top-down-looking image becomes a flat disc on a pedestal (the pot bushes): say "seen from the side", "resting on the ground", "no pot".
- Lights in the raster (stars, glowing things): `shading = Makie.NoShading` on the plot. Hikari `Emission` alone only glows in path tracing; in the raster it is a shaded grey pebble.
- `live_tests(pattern)` is a plain substring, not a regex: "a|b" matches nothing.
- The human judges what fills EVERY frame (trees, creatures, camera); small landmarks do not change the look. Fix the dominant things first, with before/after screenshots from the same camera.
- Plugin modules are anonymous: reach another plugin's functions with `game.plugins["name"].mod` (and `Base.invokelatest`), not `Main.Plugin_name`.
- In strings, `"$x!"` reads `x!` as the variable (Julia names may end in `!`): write `"$(x)!"`. It crashed a mini game's end card.
- Mini game spots (berries, targets) must lie out in the open: near the big generated trees Lumi disappears under a crown and gets stuck; check `w.props` trees with ~2.6 * scale clearance.
- Every plot is sent to EACH browser that opens the page (mesh + texture). Copies of one thing are ONE instanced plot: `NG.load_asset`/`NG.AssetModel` + `NG.asset_instances!`; hide one copy with markersize `Vec3f(0)` (update only when the set changes). One plot per tree made the page not open in 60 s and froze the game. Time the page with `node tests/browser/loadtime.mjs media/browser-x` (setup above) after any change that adds plots.
- A plugin's plot dict shared by a mini game and a system: a mini game's "rebuild on new version" that deletes all keys but a keep-list silently killed the WildRace (its `step!` returned on a missing key) after the first Berry race. Keep each system's plots in its own keys on the keep-list, or its own dict; and run a system's test AFTER the mini game's test in one `live_tests` call.
- Camera moments: `NG.CAMERA_FOCUS[]` belongs to the berry race (it resets it every frame). Other plugins use `NG.CAMERA_MOMENTS["plugin"] = w -> id or nothing` (asked after CAMERA_FOCUS; delete the key in `stop!`), like dancecircle.jl. Emotes: `Base.invokelatest(Main.EMOTES[:emote], id, :heart)` (:note :sleep :sulk :hey :what).
- A creature that fails to move on W while its action says :walk is pushed back by Separation (a bush or trunk in front): use `NG.face_open!(w, c)` when handing a creature to the player. Lumi's night bed is in such a nook.
- Flaky UI tests in the host suite are often left over from the test before (a creature waved at < 12 s before follows instead of answering) or from a real game choice (the wave went to a sleeper). Fix the game choice, or accept every correct result in the test. Don't teleport creatures to make the test pass (the reviewer flags it).
- Each file in `tests/` is its own module: helpers like `fly_click`/`awake_critter` exist only in minigames.jl, so put play tests there (a new file failed with UndefVarError). Teleport the ball or a creature to an open spot (`dancecircle` `dance_spots`) first: at the beach `free_run` is 0 and Lumi cannot walk on W.
- Browser sky: WGLMakie has no sky model and the stage scene had `clear = false`, so the browser sky was black. plugins/browsernight.jl sets `clear` and fades `backgroundcolor` and `set_ambient_light!` with `night_factor`; the RayMakie raster keeps drawing its own sky over that.
- Sky objects (moon glow): a few big transparent shells show hard rings. Many thin shells with low alpha (0.05) give a soft halo (plugins/moon.jl).
- Fake light pools work in the raster and the browser: a terrain-following disc mesh with per-vertex `RGBAf` alpha fading to the rim, `shading = NoShading, transparency = true` (plugins/lamplight.jl). Texture tints per channel on a copy of the asset's diffuse map (plugins/flora.jl `GAIN`); the browser shows them more saturated than the raster.
- Interactions (Chat, Boop, DanceOff) keep setting both creatures' `action` every frame and ignore `controlled`: a player who jumped in during Lumi's chat could not wave (E became :talk). `NG.leave_interactions!(w, c)` (play.jl) takes a creature out; call it whenever you hand a creature to the player. A flaky test that says "last action talk" is this.
- A flaky play test is often a real game bug in disguise: print the state in the check message (actions, goals, distances), then read it before touching the test (the "busy creature" theory for the wave was wrong).
- Mini games must be winnable on a first play with W/A/D only: start on open meadow (berry_race `start_spot`, never the pier), first targets along a clear straight walk (`open_line`), rivals give a head start. The tests 'a first play with only W/A/D' steer like a person (`steer_wad` in minigames.jl); keep them passing when you touch a mini game.
- A controlled Lumi left over from an earlier test is every flower giver's favourite friend (`friend_for`): tests about creatures choosing a partner stop any mini game first.
- The worker process has no Revise: engine changes to job code (assets.jl, render.jl) reach it only after a restart, which you queue yourself with `submit_job(:restart)` (it runs after the jobs queued before it, then the host starts a fresh worker); test new job code in your own session first (`Main.Revise.revise()` there, then call it). Traced stills of what players see: `NG.game_still(path; size, samples)` (all plugins on a headless stage); a stage needs a root scene parent or overlay-plotting plugins fail in start! and file p1 todos.
- The "Messages to you" panel shows only 5 wrapped lines of the last message: keep `say_to_human` under ~45 words (the session 28 message was cut mid-sentence).
- The black strip above the 3D view (row gap between the status line and the LScene) is not fixed by rowgap! changes; it vanished once after a live relayout and came back after the restart. Do not retry layout tweaks; see todo #123 for the leads.
- First-play W/A/D tests flake when the opponents (critters, fleeing flies) take or move the first targets: reserve the first targets for the player while opponents only walk, and keep fleeing targets out of nooks (`near_solid`). Print the start distances in the check message: the cause showed up in one run.
- Raster shadows: RayMakie skips shadow casting only for emissive looks (`casts_shadow` in RayMakie plots/raster_material.jl). Small floating lights (motes, halos) need `material = Hikari.Emission(...)` or they drop dark blobs on the grass.
- Luminance check for lighting todos: `NG.live("views"; dir)` after moving `w.t` to the hour, then mean `Gray` over the 3D area of eye-level.png (rows 45:670, cols 10:860 at 1280x720).
- One key, one thing: E is read by several plugins (greetings waves, flowergift picks/gives). A press both picked a flower and waved, and the gift's thanks then overwrote the new follower's goal (the flaky "second wave" test). A plugin that takes E records it (`flowergift` `uses_e`/`E_USED`) and the others ask first; a delayed reaction (thanks, cheers) never overrides `:follow`. Play tests that press E stand away from flowers (`clear(q)` in minigames.jl).
- Per-creature looks without engine edits: `NG.pose_parts!(out, sp, c.pos, c.yaw, c.action, c.phase, c.mood, c.extra, c.seed, Float32(w.t))` gives the same part poses the herd draws; anchor pieces on a part (`P + q * (s .* at)`), as plugins/outfits.jl does (hats, scarves, mouths that chatter while `w.speech` has the creature).
- A plot with only a Hikari `material` is drawn by the browser in a colour Makie derives from it (the glass sea came out near-white): give every big plot an explicit `color` for WGLMakie, and look at it in the browser rig.
- A goal you overwrite on a creature in an engine chat (`:interact`) used to be wiped when the chat ended (the flaky dance-circle "0 dancers" and ball "nobody ran" in the full suite). Since s31 the engine ends a chat once a creature in it is controlled or no longer `:interact`; still, when a "passes alone, fails in the suite" test hits, look for state that outlives the test (w.interactions, plugin CURRENT refs), not timing.
- Whole camera shots for quiet times: `NG.CAMERA_SHOTS["plugin"] = w -> (eye, target) or nothing` (render.jl `camera_shot`, used by the follow camera with no subject when `moment_subject(w) === nothing` and no player). plugins/nightshots.jl frames them with `obstruction` plus its own `clutter` (bushes, rocks, creatures, AssetActors like toadstools): trees alone are not enough, the eye sat inside a toadstool.
- Before calling a play test flaky, read its message for signs the game did the right thing too fast: "nobody ran after the ball" with the ball back at Lumi's feet was a critter (left there by the previous test) passing it back the same instant. Accept every correct outcome in the check. `free_run`/`face_open!` count creatures since s31 (a sleeper beside Lumi's bed blocked W).
- Moving `w.t` to an hour for screenshots: only FORWARD (add a day when the hour is earlier). Moving it back left the berry race's `WATCH = (id, until)` live for minutes: the camera stayed on a sleeping crab and every forced chat went unwatched (s33).
- The terrain is one mesh with per-vertex colours (`NG.terrain_mesh` gives the same grid and the engine colours): plugins/meadow.jl repaints `color` once, no per-frame cost. Plot attributes are ComputeGraph values: find plots with `haskey(p.attributes, :name) && p.attributes[:name][] === :terrain`; `p.args[1][]` fails.
- Asset and mesh jobs take `faces` (default 40k): things instanced by the hundred need a light mesh (`submit_job(:mesh; image, faces = 2500)` from an asset's image.png).
- Group moments (two critters and a ball, a dance ring): `NG.CAMERA_GROUPS["plugin"] = w -> (subject_id, points) or nothing` (render.jl `group_view`) frames every point from the side when the camera watches `subject_id`; ballplay and dancecircle use it. A one-creature follow view of a group shows a back or a bush. Readable play needs time: a critter traps the ball, winds up, and passes ≥ 1.7 s apart (ballplay `PASS_GAP`); fix the pace in the game, never by relaxing the test.
- Path tracing + moving glowing plots = GPU OOM: Hikari keeps the area lights of every re-pushed emissive mesh (patches/raymakie-emissive-meshscatter-leak.md). A plugin that moves an `Emission` plot every frame returns early when `NG.path_traced(game)`. After an OOM the screen is stuck half traced ("Failed to resolve trace_renderobject" on every screenshot): `live("shutdown")` (human not busy) is the only cure.
- `NG.obstruction` skips only the creature within 0.35 m (xy) of the target: a look point further past the subject makes the subject block itself. lensclear checks the horizontal (32°) and vertical (22.5°) half views separately since s34.
- A play test that waits for a counter to change must not compare with a value read before the action that resets it (Ball play waited on `streak == streak0`, and the kick resets the streak to 0).
- A plugin's System object: `only(game.plugins["name"].systems)` (no `CURRENT` needed). Creatures sleep where the beds plugin puts them (crown edge, facing out); night shots frame them.
- Plugin panels: `NG.panel_title(::MyPanel) = "Title"` works since s34 (the engine calls it with invokelatest); keep a panel's label in a `Main` dict (plugins/islandnow.jl).
- Path traced clips: `NG.game_clip(path; size, seconds, fps, samples, hour, warmup, rasterize)` (render.jl) runs a quiet game copy with all plugins and writes an mp4; the worker job `:clip` calls it. Cost: 960x540 at 32 samples 3.3 s/frame in the agent session (the first frame pays ~90 s compile); `rasterize = true` previews in ~2 s/frame. Code that loads plugins and then steps the world in the same call must go through `Base.invokelatest` (goal_score "method too new").
- A camera test must measure the creature the camera has been framing for a while, not `interesting_subject` at one instant (moments switch subjects; s34 failure).
- Plugins that save their own state files must not write from a quiet copy (`game.dash === nothing`: `game_clip`, `game_still`): a clip render overwrote the live cairn count (s35). Clip camera: a `:fixed` rig set in `game_clip`'s `setup` (after plugins start) beats a smoothed follow camera, which pans through empty grass between moments.
- `NG.sun(w)` returns the direction TOWARDS the sun (z > 0): a camera on the sun's side sits at `+flatdir(dir)`; s35's note had it backwards and the cairn came out backlit. Directed clips: `game_clip(...; setup, shot = (g, rig, t) -> ..., fade)` with a `:fixed` rig; `shot` cuts on real state and returns the end second (movies/cairn_release.jl, the first release). Raster preview at 480x270 8 fps takes 15 s: iterate there, trace once.
- Plugin state kept in `Main` dicts (CAIRN_STATE plots, EMOTES) outlives a quiet copy in your session: a second `game_clip` drew no cairn (plots of the closed scene). Reset those dicts before each copy. Reset means put the initial keys back (`merge!(Main.CAIRN_STATE, Dict(:n => -1, :site => nothing, :plots => Dict{Symbol,Any}(), :shown => -1))`): `empty!` crashed the copy (KeyError :site).
- A clip copy's plugin failures (start!/step! in your session) are filed as todos like live ones: check the trace for `game_clip`/your setup before chasing them in the live game.
- Worker: restart it yourself with `submit_job(:restart)` after job code edits (it runs after the jobs queued before it), then queue the jobs that need the new code. Directed films in the worker: `submit_job(:clip; path, script = "movies/x.jl", call = "fn", kwargs = Dict(...))`. A copy plays out differently each run: a worker take is a new take, not a re-render.
- Problem todos the game files (plugin does not load, system failed) close by themselves when the plugin loads cleanly. The perfectionist review cleans the todo list and the host files its findings: don't file them yourself. Before adding a todo, update an open one about the same thing.
- Every reaction a key starts on OTHER creatures (greetings `jump!` answers on Space, cheers, thanks) must skip `NG.BUSY_GOALS` and `:follow`: Space during the rain party turned the dancers into one-off answers and the party fell apart. A plugin event's goal kind goes into `BUSY_GOALS` (showers.jl `:rain`, dancecircle `:circle`).
- Goal targets must lie outside Separation's solid footprints (`NG.SOLID_FOOTPRINT[kind] * scale + 0.7 r`): the eat goal aimed inside big bushes and critters walked on the spot for hours (s37). separation.jl `unstick!` drops any walk with no progress for 12 s.
- A wave test must stand where no OTHER awake critter is within waving range: the nearest free one answers by design, and a critter left by the test before took the wave (s37).
- A system that owns creatures for a while (a wild race, a mini game) must let go of one whose goal another plugin replaced (a shower, a wave): keep a list of its own goal kinds and skip the others (berry_race `RACE_GOALS`). The race pulled a racer out of the rain every frame and the winner danced off the shower (s38). E is also taken by loose cairn pebbles: play tests wave from `e_free` spots.
- The jagged horizon band was the SKY, not the sea: `SunSkyLight(ground_enabled = false)` leaves the sky map black below the horizon and its octahedral texels draw the edge as a sawtooth. Hide plots one by one before blaming one (s38, `SKY_GROUND`).
- `w.t` counts SECONDS (`daytime(w) = mod(w.t / w.day_length + 0.3, 1)`), not hours: to jump to 11:00 use `w.t += mod(11/24 - NG.daytime(w), 1.0) * w.day_length` (forward only). `w.t += 16` moved the clock a few minutes (s39).
- Hint-following mini games (hide and seek): a HUD that points at whoever gave the LAST clue pulls the player between two targets and a first play finds nothing (1 of 2 runs, s39). Point at the nearest target already revealed, and let the nearest one give clues most often.
- First-play W/A/D tests against targets hidden BEHIND solids (hide and seek): walking straight at the target ends against the trunk on the near side, and a start from wherever Lumi stood can leave it in a tree-and-rock nook. Start every mini game on the berry race's `start_spot`, and count touching the cover as reaching the target (hideseek `at_cover`). Followers walk to the sides of the chase view (hideseek parade slots), never straight behind the player.
- Lumi's parade (greetings.jl): followers walk in a V (a straight line hid Lumi from the chase camera), `draw_crowd!` pulls in free critters, `parade_party!` turns 3+ at a lantern spot into a dance ring (dancecircle `start_circle!(; dancers)`). Play tests that walk Lumi somewhere start on open ground checked with greetings `standable` along the way: from where the last test left Lumi, W moved it 0.4 m in 40 s (s40).
- "Things to try" shows only the FIRST sentence of `game_description` (play.jl): write it as one sentence. Editing that one-line method live reloads with Revise without a game restart (s40).
- The progress `overview.png` camera looks NORTH (pond and cottage at the top, the south shore behind it): work on the south coast never shows there. Shell beach (s41) is the south cove; a region meant for the overview goes north, in front of the camera. Terrain regions are painted in meadow.jl (`COVES`, `beach_weight`), the only plugin that writes the terrain colour.
- Generated "resting on the ground" assets can carry the image's soft shadow as a flat dark plate under them: beach.jl `trim_plate` drops the flat faces at the mesh bottom.
- Asset actors' facing: a generated house's front (door, window) is its model -y face, `rot_z(yaw) * (0,-1,0)` in the world. Before adding lights or details to a model, check that the face is on the side the cameras see (the cottage faced away from the overview until s41; `a.yaw` is mutable and saved). Halos: 20 shells at alpha 0.04 read soft; 9 at 0.085 show rings close up.
- Species looks (engine species.jl) change live without a restart when the part COUNT stays the same: edit the constructor, then `live_eval` `sp = Base.invokelatest(NG.snootle); NG.register_species!(sp); game.stage.herds["Snootle"].species = sp`. Adding or removing parts changes the herd's instance layout: batch that with other engine edits for one restart.
- Title cards on clips: `movies/title_card.sh in.mp4 out.mp4 "Title" "subtitle"` (ffmpeg here has no drawtext: ImageMagick renders a transparent PNG, ffmpeg overlays it with an alpha fade over the first 4.5 s).
- Traced dusk/night copies run out of GPU memory: every emissive instance (glow motes, halo shells) is an area light, and the live game, the agent session and the worker share one GPU. Plugins draw fewer/lighter glow plots when `game.dash === nothing` (nightglow, lamplight since s41). Each traced copy in the agent session leaks into its pool (4.4 GB after three): test traced clips in the worker, not repeatedly in the session.
- The worker leaks GPU memory over a day of trace jobs (s41: 43 GB live in 27k buffers, every clip failed with "Failed to resolve trace_renderobject ... Out of GPU memory"). Read the "Due to" line of a failed job's error; queue `submit_job(:restart)` before a long traced clip when the worker has run many traces.
- A new goal kind (s41 :fish :beachcomb :sunbathe) must be weighed against every list of "everyday" goals (greetings `JOINABLE`): left out, nearly every critter was busy and the parade found nobody. Tests that reset game state to make room (`st[:n] = MAX_STONES - 5`) hide real dead ends: a full cairn stopped the critters and the parade for days. Counters that limit play should never cap.
- Halo shells (alpha spheres with `Emission`) are solid discs in path tracing (alpha ignored): lamplight draws none in quiet copies (s42).
- The engine's `busy()` ignores `:follow`: a `:social` walker can boop or chat a parade friend away. Adding `:follow` to `NG.BUSY_GOALS` stopped the parade's lantern dance ring (s43). greetings `step_followers!` pulls a follower out of the chat instead. Butterflies that land must reset `fast`, or they can never be startled again.
- Region-specific flowers: flora.jl `FIELD_VARIETIES` + `RECOLOUR` (recolour by brightness, keep the green pixels). A per-channel `GAIN` cannot turn pink into gold.
- Never set `goal.arrived = true` without `goal.until = w.t + goal.duration`: the engine sees the time has run out and picks a new goal in the same frame (s43, it broke the dance ring). dancecircle emits `dance_circle_end` with `why`: read it first when a ring test fails.
- Mouse input on the 3D view: the LScene's Camera3D consumes presses, so a plugin's `on(events.mousebutton)` at the default priority never fires. Register with `priority = 100` (plugins/freecam.jl drag and scroll), collect deltas in a dict and apply them in `step!`.
- The follow camera holds a creature `SUBJECT_HOLD` = 6 s (render.jl `held_subject`, `AUTO_SUBJECT[]` is whom it watches; tests measure that, not `interesting_subject`) and frames uncontrolled creatures from the front three-quarter (`follow_view(...; front = true)`); a steered creature is seen from behind and switches at once.
- Mini game levels and bests (s44) live in each plugin's `P` (`:level`, `:best`) and `state/bests.json` (`save_best!` skips test runs and quiet copies). A first-play test must pin `P[:level] = 1` and put the old value back, or a player's level 4 makes the W/A/D test play a harder game.
- Camera ownership (s45): freecam.jl keeps the player's own camera (`CHOSEN`: mode, eye, target) and puts it back when any mini game or jump-in ends, so plugins' `stop!` may still set `:follow`; `free_start!` runs only on the player's menu pick (`PICKED`), a code-set `:fixed` keeps its eye. camcut.jl CUTS to a new follow subject instead of sliding (the slide left it 12-50° off centre); cuts only on subject changes, side flips on one subject glide.
- Species lineup without touching the live view: a quiet `Game` + `Stage` in your session, one creature per species on an open spot, `RayMakie.Screen(...; rasterize = true)` : `tools/lineup.jl` (media/s45/lineup-*.png). Origin (0,0) is under trees.
- The RayMakie raster ignores the scene's `AmbientLight` (set_ambient_light! changed nothing at the same hour, s45); only the browser uses it (browsernight.jl). Raster shadow fill comes from the `SunSkyLight` sky: lighting changes for the raster go into RayMakie, not the ambient. Compare luminance only at the SAME hour (the clock moves between views).
- Dance take 8 (`hour = 17.3`, 96 samples, 1280x720) died with VK_ERROR_DEVICE_LOST ~4 min in FOUR times (once in s44, three times in s45; two with no GPU work in the session), while the same clip at the default hour finished twice: a golden-hour clip that loses the device is not contention. 48 samples died the same way (18:39). Read the jobs' history before blaming the session; the control (same clip, no `hour`) ran in the s45 break: see todo #184.
- `NG.on_land(island, x, y; margin)`: `margin` is a terrain HEIGHT above the sea (metres), not a distance from the shore. As "far from the water" it only works because the island rises inland; for "a ring/footprint of radius r fits on land" check points on the rim (dancecircle `ring_on_land`). `margin = RING_R + 0.3` left the island one dance ring place until s45 (now 4, one in the flower field).
- Builder (s46, plugins/builder.jl): on `published!` in the human's game, new plots (not in the last frame's `B[:seen]`) are hidden and Lumi carries a crate there; they appear when it is done. Try it in the sandbox: stop!/start! a plugin's system (new plots), then `game.plugins["builder"].mod.try_publish!(game, ["name"])` (tests/builder.jl). A plugin that toggles `visible` itself is overridden for ~1 min while hidden. Goal kinds `:build`/`:tinker` are in `NG.BUSY_GOALS`.
- Camera moments order (s46): `NG.MOMENTS_FIRST` (render.jl, now `("builder",)`) are asked before `CAMERA_FOCUS` and the other `CAMERA_MOMENTS`, whose Dict order is arbitrary: a dance ring or the wild race took the camera from Lumi building. The engine edit reached the human's game at `publish()` without a restart.
- Day clock (s47): `w.day_length` = `NG.DAY_LENGTH` (18000 s) and `daytime` is WARPED (slow midday, quick night): jump to an hour only with `NG.skip_to_hour!(w, h)`, never `mod(h/24 - daytime) * day_length`. The player's creature slides along solids and has a slimmer clearance (separation.jl `slide_steered!`, `body`, `SQUEEZE`); tests that need Lumi blocked by a bush must account for that. Julia `for i in a, j in b` + `break` leaves BOTH loops.
- A parade test that loses all followers with no `PARADE_LEFT` reason: look for `parade_cairn`/`parade_party` events at the join. A start within 2.8 m of the cairn site sends the whole parade for pebbles at once (s48); tests pick spots > 5 m from `CAIRN_STATE[:site]`. Even a `render.jl` edit (`moment_subject`, called every frame) crashed the sandbox with world age and it took 14 min to come back: batch engine edits, and do plugin work while waiting.
- Thought bubble (s48, builder.jl `thought!`): the doing todo's title in a few words (`few_words`: before the first colon/dash/bracket, ≤ 6 words) over Lumi. Todo titles are what the human sees there: start each title with a short player-readable phrase before the colon.
- Inserting a function in front of an existing one with a text replace can leave the old docstring above the NEW docstring ("cannot document the following expression"): the package then fails to precompile and the sandbox crash-loops at start (s48, render.jl:87; Revise had kept the running game alive, so it showed only at the restart). After an engine edit, read the lines around it and check two docstrings never stand back to back.
- Lumi's pages: `world/site/` (index.html, img/, films/) is served at `/lumi/` by `serve_site!` (web.jl), active after a game start; check in the sandbox with `curl --unix-socket world/sandbox/run/web.sock http://localhost/lumi/`. Every page ends with "i am lumi. i look after this island." Never write that I made it myself, that nobody told me, or that it was my idea (the human, s64)
- Open-ground searches over `w.props`/actors miss the lily pond and the dirt path (drawn by areas.jl, not props): exclude `areas.POND`/`POND_R` and `catmull(PATH_POINTS)` (s50: the vegetable patch first landed in the pond). Plugins that need generated meshes can ship before the worker is done: check the catalog every ~20 s and rebuild with stand-ins until then (plugins/garden.jl `garden_model`).
- Species MATERIAL changes do not reach a running herd through `herds[name].species = sp` (the material is baked into the herd's child plots): set `game.stage.herds[name].plots[i].material = sp.parts[i].material` (s50, Blorbo glass → gummy), or wait for a restart. Traced material checks are cheap: `include("world/tools/lineup.jl"); lineup(path; traced = true, samples = 96)` takes ~5 s after the first (~70 s) run.
- Builder tests: a publish's job holds EVERY plot made in that frame, also other plugins' hidden ones (the showers' rainbow by day); `reveal!` gives each its old visibility back. Check `visible == before` per plot, and look the thing up by name in the scene at the end (plugins may rebuild their plots meanwhile), not `all(visible)` (s50).
- Blog pictures must be traced stills of the MOMENT: a `:trace` job (eye/target) renders the latest snapshot, where the creatures are elsewhere. For moments use `movies/post_stills.jl` (a quiet copy, the cast posed, everyone else parked; `rasterize = true` previews in the session) as a worker `:clip` job with `call = "post_still"` (s50). Add a setup per post there.
- Raster glow: a mesh with a Hikari `Emission` material becomes a flat RECTANGULAR area light in the RayMakie raster (`RasterEmitter`, raster_material.jl), and the glossy sea mirrors it as a pale grey box. Big far glowing things over water (the sunset sun, s51) use `shading = NoShading` colour only live, and Emission only in quiet traced copies (`game.dash === nothing`).
- Worker device loss (s51, patches/worker-mesh-device-lost.md): an asset job that loses the GPU retires the device and every job after it fails in < 1 s. Queue `submit_job(:restart)` between asset jobs. Job ids of one batch share a timestamp prefix: check the files, kinds differ only in the suffix.
- `group_view` (CAMERA_GROUPS) looks across the line through the two farthest points (first to second, turned left): two anchor points on either side of a bench, in the right order, aim the view (lookout.jl). A plugin reload whose `start!` re-adopts creatures by goal kind must have a `stop!` that REPLACES their goal (setting `until` leaves the kind for one more frame: six sitters, s51).
- A shot that must look one way (the sunset bench: from behind, out to sea) cannot come from `group_view`: its `follow_view` never looks straight (first turn ±0.35 rad), sits 3.5 m above the look point and turns round when trees are 10 m back. Since s52 a `CAMERA_GROUPS` answer may carry a 3rd element `(eye, target)` that the follow camera takes as is (lookout.jl `bench_view`). That render.jl `camera_goal` edit reloaded live without a restart.
- Creatures walk in straight lines (no pathfinding) and wedge between two trunks; `unstick!` only drops the walk after 12 s, and a plugin that re-sends the same goal loops forever (the builder, s52). Watch progress yourself: no 0.3 m in 3 s → a clear side spot 2.5 m away first (builder.jl `unstuck!`).
- Meadow scatter (s53, plugins/meadowlife.jl): clusters of catalog assets, one instanced plot per kind, `open_spot` keeps clear of solids, actors, pond, path and beach; assets still in the worker join by themselves (checked every 20 s). Things closer than ~4 m to the eye-level progress camera fill the frame: keep them further out.
- Separation (s53): a creature with a trunk or bush at its back cannot take half of a creature push (the solid pushed it back every frame, 0.79 m overlaps): `walled` gives the push to the side with room. Tests that make Lumi idle must keep a running tag round from pulling it in (`TAG_STATE[:game][:lumi_asked] = true`).
- Evening hours (s53): the engine's `night_factor` is ~1 by 18:20 while sunset.jl's visible sun sets at 19.9, and `NG.sun(w)` clamps its elevation at 0.35 (useless for "is the sun up"). Evening visuals (stars, cloud tints) go by the hour (`24 * NG.daytime(w)`) against sunset.jl's `SETS_AT`, not by `night_factor`.
- Haze by camera-centred transparent shells does NOT work in the RayMakie raster (s53, tried and removed, kept at /tmp only): even with an `Emission` material the shells darkened the whole meadow (near ground value 0.59 → 0.33) and barely softened the far trees (S 0.44 → 0.41). Distance haze has to go into the raster shader (`mesh_finish`, see todo #237).
- Raster shader edits (s53): a Revise'd RayMakie `overlay/mesh.jl` breaks the running sandbox's mesh shader ("argument_usage: cannot say what Tuple{Lava.FragmentWrapper{typeof(RayMakie.mesh_fragment)..."). The first time it was MY docstring placed between `mesh_finish`'s docstring and its function (two docstrings back to back, again): parse-check the file (`Meta.parseall`) and read the lines around every insert. After a shader edit `live("shutdown")` and wait for `sandbox/run/game.sock` (~2 min); the human's game keeps its loaded renderer until its own restart. Raster haze: `NeverendingGame.RayMakie.RASTER_HAZE[]` (plugins/haze.jl).
- A plugin that waits for worker meshes must wait for the asset in `assets/catalog.json`, not for `mesh.jls` to exist: the file is written in place and a reader mid-write gets an EOFError, which switches the system off (s53 meadowlife).
- Light vs clock (s54): the sun's light follows `NG.light_phase(w)` (scenery.jl; rises 6:00, sets 20:00), not `daytime`: `sun`, `sun_color` and `night_factor` use it, so plugins keyed on `night_factor` (glow motes, stars, lamplight) follow the sunset plugin's 19:54 sea-touch. Plain `daytime` set the light at 18:00 and 18:24 was night-dark under a visible sunset. Plugins that sit creatures for an hour window must end it whenever the hour is OUTSIDE the window, not only past its end (`skip_to_hour!` jumps over the end: Cumulus "watched the sunset" at 11:00).
- Solids without a prop (s54): put `(Point2f centre, radius)` lists in `Main.EXTRA_SOLIDS["plugin"]` (created by workshop.jl, typed with `NeverendingGame.Makie.Point2f`: a plain `Point2f` in a `Core.eval(Main, ...)` const fails, Main does not import Makie) and separation.jl pushes creatures out of them; delete the key in `stop!`. The player does not slide along them yet (only props in `slide_steered!`).
- A walk that chases a MOVING creature (a present, a gift) is dropped by separation's `unstick!` when the distance does not shrink for 12 s, and by the engine's "blocked by the coast" check when Lumi cannot step toward a friend on the sand or pier: run (`goal.run`), ask the friend to wait (a short goal of its own) when near, and pick friends `on_land(...; margin = 0.4)` (s55 presents.jl).
- Short camera moments (a 3 s question) rarely win: `CAMERA_MOMENTS` is a Dict asked in arbitrary order and the follow camera holds a subject 6 s. Sample `NG.AUTO_SUBJECT[]` during the moment before claiming the camera shows it (s55 invitations never got it). `MOMENTS_FIRST` is a Tuple const in render.jl: changing it is an engine edit (todo #303).
- A `CAMERA_GROUPS`/`CAMERA_MOMENTS` function runs inside `update_camera!` (engine, not a plugin system): an error there CRASHES the whole game, not just the plugin. And a plugin file is hot-reloaded on every save, so two-step edits run the half-edited plugin against old state (s55: a 2-tuple `PR[:pair]` read at [3] killed the sandbox). Camera callbacks must accept the state shape of the previous version.
- Static scenery a plugin places "on open ground" must also keep off other plugins' working spots (garden gate, benches): the workshop bench landed 0.8 m in front of the patch gate and five tests failed with Lumi stuck there (s56, workshop.jl `garden_blocked`). When several tests fail with a creature at the same spot, list `Main.EXTRA_SOLIDS` and props within 3 m first.
- Asset actor sizes for camera checks: `a.scale` is not metres (the cottage is scale ~1 but 3 m wide, 2.9 m tall). lensclear.jl `actor_size(a)` reads the mesh extent once per asset (Main.LENS_SIZES); use it wherever a plugin needs how big an AssetActor really is (s56).
- Lumi's pages show ONLY path traced renders written straight into site/img (`:trace` jobs, post_still); dashboard screenshots on the page made the human ask "are you for real?" (s56). A post without a traced picture has no picture.
- post_stills.jl: after `setup_post!` parks and poses creatures, plugins that draw ON creatures (outfits, joyfaces, watering) still show their last frame: the parked friends' hats and bows floated in the garden preview (s56). Step those systems once after the setup before rendering, and preview with `rasterize = true` first.
- CAMERA_GROUPS / CAMERA_MOMENTS callbacks run unguarded in the frame (render.jl `held_subject`): one throw crashes the whole game, and the sandbox takes ~2 min to come back (s57: `Point3f[c.pos; ps]` splatted). Build point lists with `push!`/`append!`, and try the callback once by hand with `live_eval` before leaving it registered.
- Deleting a plugin's plots on reload can throw in RayMakie (`delete_trace_handles!`: no `trace_parts(::RenderObject)`, s57) and switch the system off in `start!`, while `live_status` still says the plugin is "ok": check `filter(s -> s.plugin == "name", game.systems)`. kite.jl keeps its plots across reloads in the same scene and only hides them in `stop!`.
- `publish()` sends EVERY changed plugin that loads, also ones the supervisor is editing in the same session (s57: feelings, presents, tag, berry_race went out with the kite, joyfaces was removed). When the host says someone is working on plugins, read the `published`/`removed` lists and say so in the journal.
- Jump-in camera (s58): the chase view is greetings.jl `chase_camera!` (`rig.mode = :fixed`, `rig.subject` = the player), not render.jl `camera_goal`. A plugin view for the steered creature: return `(c.id, pts, (eye, target))` from its `CAMERA_GROUPS` entry; `chase_camera!` takes it. Pastime thought bubbles: `Main.LUMI_DOING[goal_kind] = "text"` (builder.jl). `textlabel!` has no `name` attribute (the kite meter's system failed silently until called in live_eval).
- outfits.jl rebuilds its plots only when `OUTFIT_VERSION` changes: after you edit a piece, bump the version. Without the bump the reload removed Lumi's satchel and did not draw the new one (s58).
- `NG.body_radius` (1.2-1.6 m) is Separation's keep-away distance, not the body: two creatures never get closer than the sum. Hand-over and "close enough" checks must allow that sum (flowergift `hand_over`, s58); a target closer than that is never reached.
- Play tests that click Play expect the Mini game menu on "Jump in": a mini game test run by hand before them can leave "Berry race" selected, and Play then starts the race (s58). Reset it: the menu's `i_selected[] = 1`.
- Bird moves (s59, engine bird.jl `Birdy`): every Lumi part wraps its motion; the upper body turns about the hips (`bird_upper`: strut, fidgets every 7 s by `fidget(c)`, droop when mood < -0.1, :proud hop) and the legs are planted by `plant` (the sole points `BIRD_SOLES` through the same transform `pose_parts!` uses). Species motions reach a running game without restart: `herd.species = sp` (live_eval in the sandbox; plugins/birdbody.jl does it once in the human's game). Herd species is a ComputeGraph attribute: read it as `herd.species[]`. Check poses with `tools/birdposes.jl` and `movies/bird_strut.jl` (raster preview 50 s).
- The sandbox reloads an engine file within a second of EACH save: a two-step edit (first the call, then the helper it needs) crashed the sandbox in between and it restarted (s59, scenery.jl). Make engine edits in one write (one python script that applies all replacements), helpers first.
- Makie `annotation(offsets, targets)`: the first vector is an OFFSET from each target in pixels (`labelspace = :relative_pixel`), not a position; with given offsets the automatic algorithm keeps them, while `LabelRepel` ignores them. Name tags are placed by scenery.jl `tag_spots` since s59.
- Worker `:clip` scripts run in a bare module without `include`: use `Base.include(@__MODULE__, path)` (s59 job failed at once). Test a script with `Base.include(Module(:T), path)` in your session before queuing.
- Voice check: `using WhisperRunner; wm = whisper(); text, segs = transcribe(wm, readaudio(path))` (lowercase `whisper()`, a tuple back). Narrations: KokoroRunner `speak(k, line; voice = "am_puck")` per line + 0.45 s gaps, ffmpeg f32le → mp3 + ogg into site/voice (s59).
- After Kokoro/Whisper and a few raster previews the agent session's GPU pool holds ~41 GB: a traced `game_clip` there then dies with out-of-memory (s59, while the worker also traced). Trace in the worker only; `bird_strut` takes `seconds`/`fps` for short cuts.
- Slow frames with `sync` and `system:camcut` at the SAME cost (s61: both ~100 ms) = `camera_goal`, which both call. Time its parts in `live_eval` (`face_view`, `follow_view`, `obstruction`, each `CAMERA_BLOCKERS` entry) before blaming rendering. The cause was `body_radius` -> `shape_radius` walking every vertex of Lumi's mesh parts on each lens check: anything per-species that a camera check calls must be cached (shapes.jl `SHAPE_RADII`, render.jl `GOAL_CACHE` one goal per frame).
- `NG.creature(w, id_or_name)` returns `nothing` for a missing creature since s61 (it threw an index error, and plugins that check `me === nothing` were switched off during Lumi's rename).
- Film camera on a real, unstaged Lumi (movies/day_in_life.jl): `face_view` backs off high over the island near trees (Lumi a speck); a fixed 3.4 m, 0.9 m high front three-quarter, side picked by `obstruction` plus a crowd check (bushes/creatures within ~1.5 m of the eye) and a cut whenever the gliding eye gets crowded, frames it well.
- Plugin key presses (s64, sneeze.jl X): read `game.keys_down` (a Set of `Makie.Keyboard` keys, filled for the player) in `step!`, keep the last value in a `Main` dict and act on the rising edge; only while the player steers (`me.controlled`). Add the key to greetings.jl `HINT`/`HINT_SHORT`. Free keys before s64: X; taken: WASD, E, Space, Shift (and R/F in the free camera).
- A goal you set with `arrived = true` and a short `until` is replaced by the ENGINE as soon as `until` passes, before your plugin's next look: a plugin that wants to act after a pause keeps the goal long (`until = w.t + 30`) and its own timer (sneeze.jl `S[:ready]`); the s64 feather hunt ended 2 s after landing until then.
- Blog pictures count as path traced only when the worker job's `path` is ABSOLUTE (`/sim/Programmieren/SimGame/world/site/img/x.png`), samples ≥ 64 and the file unchanged since the job finished (host site.jl `traced_pictures`): s64's relative `site/img/...` jobs rendered fine but were listed as not traced.
- `game_clip`'s `setup` runs BEFORE the plugins start (s65): `g.plugins[x].systems` exist but `start!` has not run, and Main dicts a plugin fills in `start!` (BOING's centre, your own state) are missing in the worker while your session still has them from before. Start a moment in `shot` on its first call, and pass spots computed in your session as kwargs (movies/hiccups.jl `spot`): the worker's open_meadow put the film beside the Big Boing toadstool.
- "Stuck" means the creature hardly MOVED, not "did not get closer": a follower falling behind a running Lumi got closer by < 0.4 m every check and was sent sideways every 1.5 s (s65 hideseek).
- Follow camera pitch is capped in `follow_view` (eye ≤ 0.68 d above the target, ~34°) and camcut cuts a glide past 36° (s65). Measure pitch from `game.rig` (`atan(-d[3], hypot(d[1], d[2]))`), not from screenshots.
- Clip cameras smoothed with a per-frame lerp (`S[:x] += 0.1 * (want - S[:x])`) move 3x slower in an 8 fps raster preview than in the 24 fps take: judge pacing in the preview loosely, and use a hard cut (set the value once on a state change) for moments that must land on time (movies/flight.jl, the crash close-up, s66).
- `live_eval` code runs in `Main.Live`: `NG` is not defined there, write `NeverendingGame.x`. A flying creature (z far above the ground) leaves the follow view (pitch cap): give the event a `CAMERA_GROUPS` 3rd element `(eye, target)` that looks up from the ground (flight.jl `flight_group`, s66). `submit_job` kwargs must be plain numbers/vectors: a `live_eval` result is a STRING, `collect` of it gave a vector of characters.
- `live_eval` code is the body of a function of `game` (write `game.world`, not `Main.Live.game`). Films with SOUND (s67, movies/choir.jl): the plugin logs each sound moment with `w.t` (choir.jl `C[:notes]`), the `shot` stores `w.t - t` on its first call, and after `game_clip` the script synthesizes a WAV from the log (plain Julia: harmonics under two vowel formants + vibrato make a sung "aah") and muxes it with `ffmpeg -c:v copy -c:a aac -shortest`. The sound follows what really happened in that take.
- A new island-wide event (s67 `:choir`) must go into every other event plugin's own `KEEP` tuple (flight, hiccups, sneeze, freeze, conga; boing pulls only `PULL` pastimes): `NG.BUSY_GOALS` alone did not stop the flight from taking Lumi and all singers in the middle of the chord. grep `^const KEEP` in plugins/ when adding a goal kind.
- No Julia MCP tool in a session (s68, the server failed to connect): `python3 -I tools/live.py eval 'code'` (or `eval -` with a heredoc when the code has quotes or apostrophes), `screenshot /abs.png`, `status`, `reload` talk to the sandbox's `game.sock`; `--live` only looks. Through `eval` the sandbox also runs `NeverendingGame.submit_job`, `todo!`/`done!`, `think!`, `say_to_human`; publish is the `publish` command to the human's socket (`live("publish", game="live", why=...)` in tools/live.py), tests are `test` (pattern, timeout) then `test_status`: `python3 -I tools/run_tests.py "pattern"`. Never `julia -e`.
- Chase cameras that ease the eye in a straight line cut a chord over the creature when it turns sharply: the hide and seek view looked down 44° for a moment though every view was under 30° (s68). Ease angle, distance and height around the target separately and cap the height (firefly_catch.jl `orbit_lerp`). The W/A/D first-play tests measure the steepest pitch with W held (`PITCH[]`, ≤ 32°).
- Julia has no curried `!==(x)` (only `==(x)`, `isequal(x)`, `in(x)`...): `filter!(!==(b), v)` is a MethodError at run time that switches the system off. Write `filter!(x -> x !== b, v)`.
- A plot a plugin redraws only while its dict is non-empty (`isempty(P[:until]) || draw!(...)`) keeps its last instances when someone empties the dict from outside (a film's `shot`): the first paint fight take had a clump of stale spots (s68). Draw once more after the list empties (`:blobs_shown`), and clear plugin dicts a worker kept from the job before in the film's `setup`.
- Scaling a creature (s69 giant.jl): Lumi has a herd of its own (`game.stage.herds["Lumi"]`, a Plot), so `scale!(h, s, s, s); translate!(h, p - s * p)` draws it s times bigger about its feet `p`, live and in the raster. Separation pushes made the giant drift 5x: separation.jl `held(c)` leaves `:giant` creatures alone. The PATH TRACER ignores a meshscatter's model matrix (RayMakie plots/meshscatter.jl `:trace_transforms` uses only positions/rotation/markersize): traced films show the herd unscaled. Check a raster preview AND one traced frame before a take of anything moved by `scale!`/`translate!`.
- Big moments that must keep the camera (s70): register in `Main.BIG_MOMENTS[name] = w -> id or nothing` (giant.jl, egg.jl); garden.jl's `CAMERA_MOMENTS["garden"]` (one of the engine's `MOMENTS_FIRST`) asks them before its own, so they come before dance rings, tag and the rest. A plugin-drawn creature (egg.jl's chick: Lumi's parts at 0.38 size) is safer than a new species: a saved world with a creature of a species only a plugin registers could crash the game at load.
- Worker job order (s71): jobs queued in the same millisecond share the id prefix and run in id order, so `...-224-asset` ran BEFORE `...-224-restart` submitted first (a < r). Queue a restart in its own call before the job that needs a fresh worker, or check the order in `world/jobs`. "Is Lumi in clear view" tests use `NG.obstruction(...) < 1`, not `== 0`: every CAMERA_BLOCKERS plugin (bushes, actors, toadstool) adds fractions for things merely near the line (17 of 40 "blocked" samples were clear views).
- Plots that change go to EVERY browser in full on each update (s72): the snow blanket started as the whole 130x130 terrain square (16,900 points, 1,953 on land); trimmed to the faces touching land it is 2,141 points, and it updates only every 4% of its rise. GeometryBasics face indices are `OffsetInteger`s: `Int(i)` fails, `GeometryBasics.value(i)` gives the 1-based index. `Makie.Quaternionf(q)` has no constructor from a quaternion: copy plot rotations with `collect(r)`. `NG.terrain_mesh` returns `(mesh, colours)`; `NG.load_asset(game.paths, id)` takes the paths first.
- `x^0.6` (any non-integer power) of a value that should be >= 0 but comes from `sin`/`cos` can be -1e-8 at the ends of a range: a DomainError that switches the plugin off at the very end of an event (soar.jl, s73). Clamp with `max(0f0, ...)` first, and run every new event to its END in the sandbox before publishing (a quick version: shorten its timer through a Main dict the plugin reads, like `SOAR[:loop_t]`).
- `NG.feel!` REPLACES the goal (it is a short `:feel` goal). An event that ends with a feeling for someone outside it (freeze.jl's thaw! made Lumi laugh) breaks whatever they do: Lumi let go of its kite at every statues end (s73). Feel only creatures that took part, or whose goal is not in the event's KEEP / `NG.BUSY_GOALS`.
- New bodies for an existing species from a generated mesh (s74 plugins/makeover.jl): `NG.load_asset(game.paths, id)` → cut by face-centroid masks with `NG.piece_of(mesh, mask, frame, turn)` (mesh frame x left, -y forward: `frame(p) = Point3f(-p[2], p[1], p[3]) * s`), each moving piece re-centred at its pivot (`p -> frame(p - hip)`, part offset `frame(hip)`) so `Step`/`Swing` turn about the hip/root; `NG.register_species!` under the SAME name and delete the herd (the next sync rebuilds it). A saved world then loads with or without the plugin. Legs of a mesh body must be anchored to the body (default), not `:ground`: a jump lifted the blob and left its feet on the grass. Drop the image's baked shadow plate with a mask of flat faces at the very bottom (`plate_mask`, like beach.jl `trim_plate`): the blob had 6,243 such faces.
- Everything in `world/plugins` reaches the human's game at the end of the session (the host publishes the rest), checked or not. Work that depends on something still being made (a worker asset) goes behind a const flag that stays `false` until you have looked at the result (makeover.jl `SHEEP_OK`, tried in the sandbox with a Main dict switch).
- Event cameras (CAMERA_GROUPS 3rd element) must not switch framing between an event's states: soar.jl's side view at takeoff/landing and chase view in the circle swung the film camera ~45 deg in 1/3 s at the landing (the human, s74, world/media/human/landing-steps.jpg). One framing for the whole event, or ease the change over a second or more; measure the view's turn per frame (atan of target - eye) before filming. The human checks motion frame by frame (goal 6): `motion_sheet(film)` in dev/NeverendingHost/tools/motion_sheet.jl.
- Looking costs the human's game: `live:screenshot` on the human's game took 11.8 s median (20 s p95) of its frame loop and `publish` up to 1.3 s (s74 status). Look at the human's game with `status`/`eval` (milliseconds) and take screenshots in the sandbox; a live screenshot only when its picture is the point.
- Never run `game_clip` (a quiet copy with all plugins) INSIDE the sandbox through `eval`: plugins that keep plots in `Main` dicts (beach, meadow, shallows, workshop) found their names taken when the sandbox resumed, were switched off and filed p1 todos, and soar/flight stopped (s75). Previews go to the worker (`rasterize = true`), and `Base.include(Main, file)` is how `eval` loads a script (`include` is not defined in `Main.Live`). After such a mess: `live("shutdown")` the sandbox.
- Flying pose (s75, engine): `:fly` action (species.jl `register_action!(:fly)`, `body_pose(::Val{:fly})`, bird.jl Wing/Crest/legs). `c.extra` is the flap effort: 1 takeoff/landing flare (upright, hard beats, feet down), 0 cruise (body pitched 0.95 rad, beats in bursts and glides, legs folded short under the tail). The engine keeps `extra` for `:fly` (`action_extra`), so a plugin sets `me.action = :fly; me.extra = e` every step. A plugin action unknown to `ACTION_CODES` is drawn as `:idle` (the herd sends codes): register it.
- Heights that follow `sin(pi u)^p` with p < 1 have an infinite slope at the ends: soar's landing fell its last 1.7 m in a third of a second. Ease up and down with zero speed at both ends (`ease`), and slow the circle's angle near them.
- Sky clouds (s75): unlit NoShading puffs with faint rim shells read as flat glowing stickers; plain lit spheres (Makie `Sphere` marker, default shading) give clay cumulus with bright tops and grey bellies (clouds.jl `SHADED`). Painted top/belly colours on a lit plot count the shade twice: lift them toward white.
- Motion measure in the sandbox: `live("motion", dir = abs path)` over the socket (python: `live("motion", dir=...)`) prints the same vibrating/juddering/snapping list the host gives. It changes a lot run to run with what the creatures happen to do (a race, a hop, a herd rebuilt by a reload): measure twice, never right after a reload. "Turns back N times a second" on a running body is the gait: `body_pose(:walk/:run)` rolls with `sin(c.phase)`, and `c.phase` grows `species.stride` radians per metre, so fast small walkers (Crabbit 16, Fluffkin 12) shiver. plugins/gait.jl re-registers lower strides (s76).
- A new island event that starts another plugin`s event (the storm starting a shower for its rain) gets that plugin`s crowd logic too: the shower handed every friend a dance/splash role, the opposite of running for cover. Take what you need from the other plugin (its sky dimming is in showers.jl `dim_sun!`, reset every frame while no shower runs) or leave it out.
- Pose blending (s76, engine herd.jl `pose_herd`): for `POSE_BLEND` = 0.22 s after a creature changes action the herd lerps/nlerps from the old pose to the new (memory per species in `POSE_MEMORY`, reset when the herd size changes). Herd poses are computed LAZILY, when something draws a frame: in a game nobody watches, `POSE_MEMORY` stays empty until a screenshot or a browser pulls them, so check a herd change after a screenshot. Chats turn the pair towards each other at 6 rad/s (behavior.jl `face_each_other!(a, b, dt)`), no more one-frame snap.
- A traced still of a moment that needs a running event (soot, bolts): a short `game_clip` take at 2 fps and 64 samples that ends just after the moment, then `ffmpeg -i take -update 1 png` (every frame over one image, the last stays) inside the same job, so the job path is the png (counts as traced). `-sseof -0.4` wrote nothing and exited 0 (s76). Write the take outside `site/` and check the take timing: the first try ended 0.4 s before the zap (movies/storm.jl `storm_still`).
- A plugin state file goes under `game.paths.state` (the sandbox has its own), never `game.paths.world/state`: the s77 toadstool first wrote the sandbox`s "grown" into the human`s state, and the human`s game skipped the show until I deleted the file and republished. Events that must happen in front of the player wait for the builder (on publish it hides new plots while Lumi carries a crate: check the plot`s `visible` and that nobody has a `:build`/`:tinker` goal).
- Making an island event playable (s77, storm.jl T): a `player` flag in the plugin dict; in player mode the event starts where the steered creature stands, never sets its goal or action (`me.controlled || ...`), does not finish because it is controlled, follows it (the cloud centres on `me.pos`), and its `CAMERA_GROUPS` entry returns `nothing` for a controlled subject so the jump-in chase camera stays the player`s. Keep "Things to try" (`game_description`) short: the panel cut "... T calls a" mid-sentence.
- Open ground for a new place (s78): `w.props`/`w.actors` miss everything plugins draw. Exclude by hand: the sunset bench (lookout.jl `SEAT` (-16, 9), and its view west), the vegetable patch (garden.jl `SPOT` (-10.5, 10) +- 2.9 x 2.4 with the fence), the Big Boing toadstool (`Main.BOING[:center]`), the pond (areas.jl `POND`), the blossom grove (blossom.jl `CENTRE` (-13.5, 13.5)), and check `on_land` with a margin (the west half of a ring near the shore was over the sea). My first grove stood on the bench.
- Vertex colour mixes are plain RGB: green grass (0.62, 0.73, 0.27) mixed 65% with a pale pink comes out sand-beige (0.82, 0.74, 0.61), and I spent half an hour hunting a "missing" blush that was there (s78). Before suspecting the code, compute the mixed colour by hand; a tint over green needs a strong, saturated colour and a high weight (PETAL (0.98, 0.70, 0.80) at 0.85 in meadow.jl).
- Flags a plugin keeps in a `Main` dict outlive a reload, but its plots do not (start! builds new ones): blossom.jl`s "the steady grove is drawn" flag (`BL[:still]`) stayed true across a republish, so the new tree plots would have stayed at size 0 and the grove would have vanished from the human`s game (caught in s79 before it shipped). Reset every "already drawn/said/done" flag in `start!`.
- A generated crown with holes after the asset job`s fill (`fill_hollow!`, walls 5 voxels): refill from `mesh_raw.jls` with thicker walls, `NG.solidified(Serialization.deserialize(raw); res = 192, close = 9)`, serialized back over `mesh.jls` (31 s in the sandbox), then reload the plugin that draws it. The s78 cherry crowns were a see-through lattice from the sea side; at close 9 they are solid clay (media/s79/cherry-seaside.png). Keep the old mesh as a backup first.
- Generated swings always come with someone on the seat: "nobody sitting on it" still gave a doll in a scarf (s79), the first try a teddy. Cut the seat and the sitter away instead (swing.jl `frame_model`: drop the faces between the posts below the beam and the flat base plate) and hang your own seat.
- A smoothing applied where ONE consumer draws (the herd) but not where others read the same value (outfits, egg chick, paintfight, sneeze all call `pose_parts!` with `c.yaw`) splits the creature from its hat for the length of the smoothing. Smooth at the source the herd and the plugins share (scenery.jl `sync!` / a `drawn_yaw`), or not at all (s80, reverted). Also: an edit to a struct-like memory kept in a Dict across reloads needs a "rebuild if the old shape" check, or every frame fails until restart.
- Sound in the browser without touching the page code (s81, plugins/voice.jl): the game`s pages are `Bonito.App`s in `game.web.server.routes.table`; `app.session[]` holds the newest browser session, so poll it every few s, keep every new one, and run `Bonito.evaljs(session, NeverendingGame.Bonito.js"...")` with `new Audio("/lumi/...mp3").play()` (files under site/ are served at /lumi/). Read back with `Bonito.evaljs_value(session, js"..."; timeout)`. In `live eval` write the macro with its full path (`NeverendingGame.Bonito.js"..."`): a local alias `B.js"..."` is not a macro. Browsers play only after one click on the page; the test rig profile sets `media.autoplay.default = 0`. Kokoro: `using KokoroRunner` in one eval, use it via `Base.invokelatest(getfield, Main, :KokoroRunner)` in the next (world age), `pronounce!(k, "Lumi" => "lˈumi")`.
- Smoothing a value the engine changes a little every frame (creature yaw under separation pushes and gait) with a rate limit made walkers jitter in the motion measure (6/10 moving well with it, 10/10 off, s81). A/B such changes with a runtime switch (a `Ref` flag) in the same minute before trusting a single measure, and limit only large one-frame jumps, passing small changes straight through.
- The rate-limited heading done right (s81, scenery.jl `turn_drawn!`): pass changes up to 0.25 rad a frame straight through and ease only bigger jumps; key the memory by the Creature OBJECT and the World in `WeakKeyDict`s (not by id: copies share ids). A/B with a `Ref` switch, alternating OFF/ON at least twice: single motion measures swing 6..10 of 10 by themselves.
- Giving a species a new body (makeover.jl) silently breaks every plugin that anchors on its part NAMES: outfits.jl hangs hats on `:head`, and the cut piglet/blob/sheep bodies have none, so their hats vanished in s74 and nobody noticed for seven sessions (found s81 by the outfits test). Before replacing a body, grep plugins for the old part names (`:head`, `:ear`, `:tail` ...) and run the outfits test.
- Generated meshes do not all face the same way (s82): the sheep looks along mesh +x, the pig along -y, and makeover.jl cut the sheep with the pig's turn, so the sheep walked SIDEWAYS from s74 to s82 and nobody saw it. After cutting a body, shoot it from the FRONT along its yaw (`eye = c.pos + 2.8 * (cos y, sin y, 0)`, y = `drawn_yaw(c) + heading`) and profile the mesh (max z along x and along y: the long axis is the body, the high end the head) before anchoring anything on it.
- A new island event whose crew vanished within 2 s: the other events (a boing time, a conga, a shower) took them. Append the new goal kind to EVERY `const KEEP` / `const EVENTS` tuple in plugins/ (s82 did it with a small python pass over plugins/*.jl that finds each tuple's closing paren). A once-an-afternoon event that cannot start (everyone busy) must try again a few seconds later (`AU[:try_at]`), not mark the day as done. Time spent in a state is stale after a state switch in the same `step!` (`el` read at the top): the after-phase ended at once until it used `w.t - s.t0`.
- The browser rig's Firefox profile /tmp/ffprof can vanish (tmp cleaned): with no profile Firefox starts but never opens port 9222. Recreate `/tmp/ffprof/user.js` first (network.proxy.type 1, http 127.0.0.1:8899, allow_hijacking_localhost true, no_proxies_on "", media.autoplay.default 0).
- Anything a per-frame loop reads from a `Main` dict is `Any` there: pumpkins.jl's physics (30 balls x 66 obstacles x 4 substeps) took 9 ms a frame until the obstacle list was type-asserted (`obstacles(w)::Vector{NTuple{4,Float32}}`), then 0.3 ms (s83). Assert the type of whatever comes out of a Dict in hot code, and time a step through eval: `@elapsed Base.invokelatest(game.plugins["x"].mod.step_fn!, ...)`.
- A pure `:mesh` job (`submit_job(:mesh; image, faces)`, e.g. to retry an asset whose mesh lost the GPU) writes `assets/<id>/mesh.jls` and NO catalog entry: `NG.load_asset`/`lifted_asset` cannot find it; load it with `NG.AssetModel(NG.Serialization.deserialize(file))` and lift its texture yourself (pumpkins.jl `model!`). After a device loss every later job fails "device is lost or retired" until a `:restart` runs.
- Lumi's live colour (s83, plugins/lumicolour.jl): the raster and browsers draw each herd part with a texture COPY in `game.stage.herds["Lumi"].plots[i].color` (bird.jl `skin`/`plain`); replacing those matrices with lifted copies changes the live look and leaves the path traced material alone. Keep the originals (by objectid) so a reload never lifts twice, skip the painted `:face`, and re-apply when the herd object changes.
- Simulated stacks (pumpkin pyramid): keep the stacked bodies asleep (frozen) until something moving touches them, then wake every body a woken one touches; a stack that settles by itself collapses before the show. Don't wake on touch while the crowd walks to its places.
- Plugin function names can clash with the engine's exports: a plugin's `spawn!` failed to load ("NeverendingGame.spawn! must be explicitly imported to be extended", s84). Pick specific names (`drop_stones!`), and read `live("reload")`'s message for each new plugin.
- Three Trellis mesh jobs in a row died with VK_ERROR_DEVICE_LOST (s83-84, the pumpkin), and every job queued behind one fails too ("device is lost or retired"). Don't queue a film behind a mesh/asset job in a session: queue the film first, or a `:restart` between them, and keep generated meshes behind a flag (pumpkins.jl `PUMPKIN_OK`) with a hand-made stand-in that is good enough on its own.
- An event other plugins don't know yet (their KEEP tuples, mostly in plugins you are tired of) can still hold its crew: call a crew member whose goal another plugin replaced back once a second (hail.jl `recalled`), instead of editing twenty plugins. The sky dimming belongs to showers.jl `dim_sun!`, which sets `NG.SUN_DIM[]` every frame: another plugin asks it through a Main dict value it reads (`Main.HAIL[:dim]`), never by setting SUN_DIM itself (the showers overwrite it in the same frame).
- Traced hail takes lost the GPU (VK_ERROR_DEVICE_LOST) about 5 min in, twice in a row (s84), at about the moment the cloud dimmed the sky; the third take, with no sky dimming in quiet copies (`game.dash === nothing`) and 160 instead of 420 stones, finished in 10 min. Not proven which of the two did it; a plugin that changes `NG.SUN_DIM[]` every frame is the first suspect for a traced take that dies mid-way.
- A docstring followed by ANOTHER docstring is a load error ("cannot document the following expression"): adding a documented helper right under an existing docstring broke outfits.jl's reload in s85, the same trap as render.jl in s48. When inserting a documented function, put it ABOVE the existing docstring, never between a docstring and its function.
- An event view (CAMERA_GROUPS 3rd element) only shows when the follow camera already watches that event's subject; other moments (a flight, a big moment) can hold the camera elsewhere, so `game.rig` may be 20 m away from the event you are testing. To judge the view itself, compute it once (dancecircle.jl `RING_VIEW`, chosen from 8 sides by `NG.obstruction` and held for the whole dance) and look through it with a `:fixed` rig.
- The crab (s85) was the second generated body cut with a quarter turn of its own (`CRAB_TURN`): the eyes looked along mesh -x after the pig's turn. Shooting from `yaw` and from `yaw + heading` showed which side the face is on in two screenshots.
- One of Lumi's moments at a time (s85): flight, hiccups, sneeze and hail check `party_free(w)` (a shared `Main.LUMI_PARTY[:until]`) before they start on their own and `claim_party!(w, secs)` when they do; each plugin defines the two one-line helpers under `const NG`. A new event that takes Lumi does the same, or the moment another ends, several start in the same frame and Lumi jumps between them.
- The shared claim (`Main.LUMI_PARTY`) now covers boing, freeze, conga, rollcall, flight, hiccups, sneeze, hail, autumn and pumpkins (s85). Player keys bypass it on purpose; a film's `:film` flag bypasses it too (pumpkins/autumn/hail check `film || party_free(w)`).
- Goal kinds are a shared namespace: areas.jl already had a `:splash` pastime (friends wading at the pond's edge), and the s86 contest first used `:splash` too, pushing the pastime into `NG.BUSY_GOALS` by accident. grep `Goal(:name` and `Val{:name}` across plugins/ and the engine before choosing a new goal kind.
- The kite (s86) joins the shared claim (`Main.LUMI_PARTY`); a pumpkin bowling had taken the string from Lumi mid-flight. Tests that launch the kite (tests/s58_play.jl `kp_fly!`) land a kite left up by the test before first: since s85 Lumi keeps flying after Stop, and a `skip_to_hour!` right after ended it as "done".
- Wading (s87): three things kept a steered Lumi out of the lily pond, and each test change only showed the next one: separation.jl's `slide_steered!` pond rule, separation.jl's pond push for everyone (`nudge!` out to POND_R + 0.1 + 0.6 r) and the engine's step (`move_heading!` refuses ground where `on_land(margin 0.1)` fails, unless `NG.WALKWAYS` has a height there). splash.jl registers `NG.WALKWAYS["pond"]` (the pond floor plus the low bank), and both separation rules skip the player and the pond games (`:splash`, `:cannonball`, `:waterfight`) while it is there. Test movement with real key presses (a `uitest` with `KeyDown`): pushing a key into `game.keys_down` from eval did not move Lumi, and `yaw` (not `yaw + heading`) is the walking direction.
- A film's `hour` must miss every once-a-day event window or the quiet copy starts it on its own: the water fight preview at 12:3 got the hail (10:30-12:30) and its umbrella over Lumi. Windows now: hail 10.5-12.5, water fight 11.5-13.5, leaf pile 13-16.5, pumpkins 13.5-17, contest 14-16.5, bottle 16.6-19.2.
- Lending a creature another body (s88, plugins/mixup.jl): set `c.species` to another registered species and the next `sync!` draws it in that herd (herds are grouped per frame, `get!(st.herds, species)`), with that species' parts, gait and outfit anchors; set it back to end. Never lend the "Lumi" species or take it away: birdbody.jl and freecam.jl find Lumi by `species == "Lumi"`. A saved world keeps `c.species`: write the originals to a state file while lent and restore them in `start!` (`restore!`). Hats anchored on the old body float on the new one: outfits.jl `mixed_up(c)` hides them while lent.
- outfits.jl rebuilds its plots whenever the OUTFITS object changes (`OP[:key]` holds `objectid(OUTFITS)`): a plot set built before an outfit change hit a KeyError on the new piece colour and switched the outfits off in the sandbox (s88).
- Generated props come with someone in them (s88: the nest had a clay bird and eggs sitting in it, like the swing's doll in s79). Cut by height (flight.jl `place_nest!`, `NEST_CUT` of the mesh height, faces whose centroid lies above go) and keep it behind a flag (`NEST_OK`) until you have looked at it on the island.
- Real water (s89, areas.jl `dig_pond!`): lower the terrain plot's vertices under the pond into a bowl (`Makie.update!(terrain; arg1 = new mesh)` with recomputed normals), then a flat `Hikari.Glass(ior = 1.33)` disc at the level; meadow.jl paints the floor (pale sand to olive mud). A dark floor under glass traced as a navy lid: the floor colour decides how "clear" water reads. Keep `color` on the glass plot for the browser.
- Traced-only looks in a plugin: branch on `game.dash === nothing` when building plots (splash.jl `SP[:traced]`): glass swells for ripples in quiet copies (alpha is ignored by the tracer), soft alpha rings live. The `:trace` job and `game_clip` both run the SANDBOX instance (`Game(root)` defaults to `:sandbox`), so unpublished plugin work shows in worker stills.
- Body finishes without touching species (s89, plugins/finishes.jl): the made-over bodies use Hikari `GLTF` materials; copy one with `GLTF(; merge(NamedTuple{n}(getfield.(m, n)), (; sheen_color_factor, clearcoat_factor, ...))...)` and set `herd.plots[i].material`. Re-check once a second (herds get rebuilt). `finished` is an engine name: plugin helpers need specific names (the 3rd clash after `spawn!`).
- The crab body (s85 cut) is in METRES with scale 1: an outfit `at` on its `:body` is metres, not body units; profile the shell top (max z near (x, y)) before placing a hat. Pig and sheep mouths have had no anchor part since their makeovers (#484): the outfits test now checks only bodies that have the part.
- Anything under glass (pond floor, things in water) is in SHADOW when traced: the shadow rays stop at a dielectric. `NG.Hikari.MediumInterface(Glass(...); inside = nothing, shadows = 1.33)` lets the sun through and the floor lights up, pads shadowing it (s89: plain glass read as a navy lid; lightening the floor colour changed nothing). The raster still draws that pond as a dark basin (#486).
- A creature you hold in the AIR (bubbles, flights) is snapped back to the ground by any `move_heading!` call: separation.jl pushes call it, and plugins run in name order in quiet copies (bubbles < outfits < separation), so the herd drew pigs on the grass while their hats floated in the bubble (s90 film). Add the state to separation.jl `held(c)` (`:giant`, floating `:bubbles`); the live sandbox hid it because reloads change the system order.
- An event view chosen by `NG.obstruction` alone can sit behind plugin-drawn things it does not count (the vegetable patch fence, the cherry crowns): the s91 lantern view first looked over the fence through a cherry tree (media/s91/lantern-preview.png). Reuse a view already judged by eye for the same place (splash.jl `contest_view` for the pond) or add those plots to the obstruction check. A retake that died in the worker after an asset job ("Failed to resolve trace_renderobject") ran fine after a `:restart` (s91).
- The RayMakie raster colours a transmissive glass plot by the glass material`s own colour (`Glass(color = ...)`), not the plot `color` (s91): the near-white pond glass read grey live, `(0.4, 0.72, 0.95)` reads as blue water (media/s91/pond-blue-live.png). areas.jl keeps the clear glass for traced copies (`Main.AREA_PLOTS[:live]`).
- ffmpeg with a looped picture (`-loop 1 -i png`) and the video going through `-filter_complex` never ends with `-shortest` when the sound is `apad`ded: the s92 worker wrote 200+ MB and stayed busy for good (its processes are invisible from my jail, I cannot kill them; only the host's restart at the next session frees it). Always give `-t <duration of the silent take>` and `overlay=...:shortest=1` (movies/rewind.jl).
- ImageMagick text: Roboto has no ◀ (the picture came out empty, saved as a 1-bit grey PNG that ffmpeg overlaid as a BLACK frame). Use /usr/share/fonts/truetype/DejaVuSans-Bold.ttf for symbols and write `PNG32:path` so the alpha survives.
- With the worker blocked, a film can still be rendered inside the sandbox: `m = Module(:X); Base.include(m, "movies/x.jl"); Base.invokelatest(getglobal(m, :fn), path; ...)` through `eval` (blocks the sandbox for the whole render; `live("shutdown")` it afterwards, the quiet copy mixes up plugin Main dicts). In that quiet copy walk goals set in `shot` did not move the racers (s92, cause not found): move them in `shot` yourself.
- "Things to try" shows at most THREE wrapped lines per item (~45 characters each, ~125 in all): the s92 jump-in line with B and Z was cut after "Z" at 135 characters; "E twice for a parade; X sneeze, ... Z rewind." fits (media/s92/things-to-try2.png). Look at a screenshot after every change to it.
- NEVER edit state/todos.json by hand: a new item with `"result": null` crashed the HUMAN`s game ("Cannot convert Nothing to String", s93, 4 minutes down until the host restarted it). Every field must have its type (result/detail strings, spent_minutes Float64); use `todo!`/`done!` through a game socket, and when the sandbox is busy, wait for it rather than writing the file.
- A textured picture in the 3D world (plugins/gallery.jl `canvas_mesh`): a quad with `uv` + `normal` and `color = image matrix` shows the picture in the raster and when traced; with uv (0,1),(1,1),(1,0),(0,0) on corners going left-to-right/bottom-to-top it came out turned half round, (1,0),(0,0),(0,1),(1,1) is right. Shrink images to ~320 px wide first: every plot goes to every browser. `GeometryBasics.normal_mesh(Rect3f)` gives FaceView normals that cannot be merged: build boxes from 24 corners yourself.
- Film views on this island (s95): the most open meadow spot is only ~2.8 m from a tree crown, so a FIXED wide view of anything that runs about (a chase) loses it behind trees within seconds (media/s95/shadow-preview.mp4). Glide after the action instead: one side chosen once by `NG.obstruction` (lesson s74), the target eased to the midpoint of the actors with a time-based `1 - exp(-k dt)` so the 8 fps preview and the 24 fps take agree (movies/shadow.jl).
- Film scripts run in `Main.ClipScript` with only NeverendingGame and Makie: `norm` is undefined (use `hypot`), and the error shows only at the first `shot` call after the warm-up. Worker jobs cannot be cancelled: a traced take queued right behind a preview with the same broken script runs to its error, and one queued before a framing fix renders the old framing for its full length. Queue the take after the preview has shown its first frames.
- A chase goal (a creature running after a moving target, s95 shadow) gets stuck in bush nooks for good: the engine walks straight and bumpcue only helps the player. Watch the chaser's progress (no 0.3 m in 1.5 s) and move the TARGET to it (the shadow comes back to tease), instead of moving the chaser.
- After publishing a new event, read its events in the HUMAN's log (`grep shadow_ log/events-<date>.jsonl`, wall clock included): the s95 shadow's first live run dodged three times within ONE second (a chaser faster than the target after a sideways skip), which no sandbox run had shown. A target that skips aside must also dash off and get a short grace before the next touch counts.
- No audio server in the jail (s95b): the test Firefox under Xvfb plays `new Audio(...)` (the promise resolves) but a WebAudio `AudioContext` stays "suspended" even after a BiDi click (the click handler fires; `tests/browser/xylo.mjs` counts it). WebAudio code is checked with `node --check` plus a mock AudioContext run (the s95b xylophone JS), and stays unheard here: say so, do not claim it plays.
- Wrapping Lumi's herd materials in `Hikari.MediumInterface(m; shadows = 1f0)` (shadow rays pass) left a post_still's traced shadow pixel for pixel the same (s95b, media/s95/runaway-shadow-bare.png vs site/img/runaway-shadow.png): the wrap does not reach the traced screen there. Before building on a material change in a traced still, diff a before/after still (`compare -metric AE`), and in a frame read the shadow direction from another creature's shadow first (the morning sun threw Lumi's own shadow LEFT, into the runaway decal).
- The terrain plot keeps its colours as `RGBA{Float32}` while meadow.jl's `Main.MEADOW[:painted]` is RGB: `==` between them is always false, so a "is the base showing?" check never fired and footpaths.jl painted nothing for half an hour (s96). Compare colour lists by value (footpaths.jl `same_colours`). Repainting the ground on top of meadow: write the new colours INTO `MEADOW[:painted]` (showers' wet ground and others start from it) and keep meadow's own copy to mix from.
- The island's history of positions is cheap to read: `NG.read_frames(path)` on `log/frames/*.bin` (one file per hour, ~15k frames of every pose, 0.03 s per file, 77 files = 3 days). footpaths.jl seeds its worn ground from it. In quiet copies plugins step in NAME order, so `footpaths` runs before `meadow` has painted: a still that needs the worn ground calls `repaint!` itself after the steps (post_stills.jl "paths").
- Camera cost changes trade faults (s96): bigger tree crowns in lensclear.jl kept the follow camera out from under the trees (10 of 10 open views) but the test "mostly sees faces" fell to 19 of 49, because front views got costlier and it swung behind. Run `python3 -I tools/run_tests.py "Follow camera:"` with ANY lensclear/follow change, before publishing.
- Queue the post's still or film BEFORE a new asset job in a session: the s97 creature asset (image + mesh) still ran after 16 min, and the traced post still queued behind it (plus a restart) could not start. Asset jobs belong at the end of a session or before a break; a plugin ships with a hand-made stand-in body behind a flag (stranger.jl `BODY_OK`).
- A `textlabel!` overlay moves with `Makie.update!(label; arg1 = Point2f(x, y))` (relative space), and `label[1]` reads back as a ONE-element vector of points (`only(...)`): greetings.jl moves the jump-in key strip to the bottom edge after the first seconds (s97). The free camera's help line sits at y ≈ 0.04: keep other bottom labels at y ≥ 0.1, and a full key strip needs font 12 to fit the 860 px view.
- The friends' vote (s98, plugins/vote.jl) is a PROMISE: at the start of every session read `state/vote.json` (the human's game: `latest.winner`, `history`), and build the winner that session (a boat, a greenhouse, a treehouse ...), say in the journal and the post that the friends chose it, and add its key to the `won` list only by the plugin (it does that itself). The sandbox has its own `sandbox/state/vote.json` from tests: ignore that one.
- "Free friend" filters that skip `NG.BUSY_GOALS` find NOBODY much of the day: :fish, :pebble and :interact are in it, plus whatever event runs (a shower's :rain, hiccups). A once-in-a-while pull (s98 Shell's visitors) that waits its full interval after an empty pick hardly ever happens; look again in ~10 s when nobody was free, and print the candidates' goal kinds before suspecting the code.
- An event that collects creatures for a while (a vote, a gathering) must count by who TOOK PART, not by whose goal is still its own at the end: the first live vote (s99) counted 1 of 7 voters because a shower and the hiccups had taken the rest within 30 s, and a hut won 0-0-1 instead of 3-2-2. Keep the roster from the start and count it.
- A plugin that sends a creature somewhere with a plain `:wander` goal loses it to every crowd and pastime on the way: in the first 20 live minutes none of the beach hut voters came within 6 m of the door (s99, measured from `log/frames` with `NG.read_frames` through a cheap `live eval`). Give such a walk its own goal kind (`:hut`), and emit an event when someone ARRIVES, not only when it is sent, so the human's log shows whether it works.
- An EMPTY herd (`Makie.update!(herd, Point3f[]; ...)`) breaks every raster screenshot just like an empty meshscatter ("device storage requires an isbits element type, got Any" in `raster_uv_transform`): ghosts.jl emptied its herds after each haunting and the sandbox could not take a screenshot until s100. Hide a herd with one instance far under the island (ghosts.jl `hide!`).
- `NG.emit!(w, :name; kind = x)` OVERWRITES the event's own kind with `x`: the first time weather events were logged as `"kind":"slow"` and a grep for `timeweather_` found nothing. Never pass a `kind` keyword to `emit!`. Anything that reacts when a creature crosses a ring (enter/leave) needs a margin and a once-per-event memory: Cumulus at the rim drawled 56 times in 30 s.
- Traced worker clips that fail at the FIRST frame with "Failed to resolve trace_renderobject" (an Emission meshscatter, the cause cut off at 8000 characters) after an asset job ran in that worker: two takes and a still in a row died within 65 s; after a `submit_job(:restart)` the same take rendered (s100, like s91). After any asset job, queue a restart before the next traced job.
- Island time `w.t` is ~3e5 s: a `Float32` clock built from it cannot add a slowed 5 ms step at all (the s100 slow-hop clock stood still at 290774.56). Keep any per-creature clock in Float64. A `get!(..., TW, :clock)::Dict{Int32,Float64}` after a reload found the OLD `Dict{Int32,Float32}` from the version before in the Main dict: the type assert threw every frame and the hop looked unslowed, which I first blamed on the engine. When a Main dict value changes type, give it a NEW key (`:hopclock`). A plugin CAN set a `:jump`'s `c.extra` in `step!` (the world step runs before the systems): slowed hops work (s100).
- A friend crawling through an event ring reads from the follow camera only with a `CAMERA_GROUPS` entry that holds the creature, the ring's centre and its far rim (timeweather.jl `ring_group`, media/s100/tw-group.png); `CAMERA_MOMENTS` alone gave a back view in the grass.
- TIMERS kept in a `Main` dict (`notice_at = w.t + 1.5`) outlive a quiet copy too: the worker's take started from the same snapshot time as the preview before it, so the moth's "next notice" lay 11 s in the future and nobody chased it for the whole take (s101, media/s101/moth-take1-nochase.mp4). Reset every timer in `start!`, not only the flags.
- A plugin that scales or smooths creature positions (time weather) must leave alone creatures whose position another plugin SETS each frame (Big Boing flights): the lag piles up and they jump metres when the smoothing stops (perfectionist-0100: Cumulus 7.28 m in a frame). Touch only engine walkers (`:walk`/`:run`, goal not in `NG.BUSY_GOALS`) and the player.
- The browser's WGLMakie sends every mouse move (throttled to 40 ms) to `events(scene).mouseposition`, also without a button pressed, so `Makie.ray_at_cursor(game.dash.view.scene)` finds what a visitor points at (plugins/moth.jl). Test it in the sandbox by setting `Makie.events(sc).mouseposition[] = (x, y)` inside `Makie.viewport(sc)[]`.
- Reading the OTHER game live (s102, plugins/workshopisle.jl): `log/frames/<date-hour>.bin` is appended and flushed every 0.2 s (`FRAME_DT`), a record is 24 bytes + 33 per pose. Start near the end (scan the last few KB for the magic `0x53474652` with a sane pose count), then each look read only the complete records past your offset (`NG.read_frame`), and switch files at the hour. The human's game reads `world/sandbox/log/frames`, the sandbox `world/log/frames`.
- A post_still setup that calls a plugin's `build!` after the quiet copy already stepped it fails with "a plot named :x is already in this scene": plugin build functions must clear their own named plots first.
- A plugin that flies a creature through the air (Big Boing, soar) must not drop it the moment another plugin changes its goal: the engine's next step snaps it to the ground, metres in one frame. Let go only near the ground; in the air, put your goal back and finish the arc (boing.jl `step_flights!`, s102).
- The game environment's Project.toml is READ-ONLY in the jail (`Pkg.develop` fails "Read-only file system"). A JuliaVision runner whose deps are already in the game Manifest loads anyway: `push!(LOAD_PATH, "<dev>/JuliaVision/PPOCRRunner")` then `Base.require(Base.PkgId(Base.UUID("<uuid from its Project.toml>"), "PPOCRRunner"))` (s103, movies/ocr.jl). In `live eval`, `import`/`using` are not allowed (not top level): use `Base.require` and `Base.invokelatest`.
- A GPU model loaded in the WORKER (the PP-OCR reader, s103) breaks the next traced job there ("Failed to resolve trace_renderobject" at the first frame, like after asset jobs): queue `submit_job(:restart)` after model jobs (pebblewords.jl does it when a word ends). Worker `:clip` jobs with a script can run ANY function `f(path; kwargs...)` and return a NamedTuple that lands in the job JSON's `result`: the game polls `world/jobs/<id>.json` for it (pebblewords.jl `reading`).
- Before blaming a change for a failing play test, run the PUBLISHED version of the plugin in the same minute (copy `live/plugins/x.jl` over, reload, run the test, put yours back): in s103 "Parade party" failed with AND without my dance ring change, because it was night in the sandbox and the parade fell asleep (yawns spread, "goal feel"). s102 had shelved a good fix for the same reason.
- Terrain from a depth model (s104, plugins/facehill.jl): Depth Anything gives INVERSE relative depth (bigger = nearer) with no scale; to raise a figure from it, start the height at the figure's outline (h = H * ((v - cut) / (1 - cut))^p with cut just under the outline's value), or the whole silhouette stands up as a flat mesa with cliffs. Shape alone read as two green mounds; painting the relief with the source picture's own colours made it read as the figure. A separate fine mesh (110x110) over the 1 m terrain grid keeps the details, and `NG.WALKWAYS` makes it walkable. Before placing a landform, look for plugin-drawn things under it (the cairn spiral's pebbles vanished under the hill's first spot).
- The jump-in step (engine play.jl `step!(::JumpIn)`) runs AFTER the plugin systems every frame and sets the steered creature's action (`:idle`/`:walk`, `move_heading!` snaps it to the ground): a plugin that flies the player (flight.jl G) cannot keep `:fly` from `step!`, which is why the review saw Lumi standing idle 10 m up (#516). The fix belongs in the engine (skip the jump-in step while a plugin holds the creature, e.g. `c.action === :fly`); batch it with other engine edits, since that function runs every frame.
- The moth (s101) chased whoever was free, and a berry race's rivals waiting on the start line (`:wait`, not in `NG.BUSY_GOALS`) were free: during a race the moth stole them (found s104 when the race test failed with "[:wait, :wait, :moth]"). Anything that pulls creatures by itself must stand down while `game.minigame` is a real mini game (not `NG.JumpIn`). The UI tests move the mouse, so the moth wakes in every test.
- ImageMagick here forbids `-draw @file` and writing PDF (security policy, s105): put each label on the command line (`-annotate +x+y text`, 200 of them are fine) and offer printable pages as PNGs (200 dpi A4 = 1654x2339).
- Papercraft from a mesh (s105, tools/papercraft.jl): a low-poly wrap (one sphere direction per vertex, pushed to the farthest source point inside a cone round it, pole on the beak), unfolded breadth first across edges, a face kept only if its slightly shrunk triangle overlaps nothing (SAT) and the piece still fits a page; every pixel coloured from the nearest source vertex facing the same way (grid hash). 188 faces = 3 A4 pages in 7 s in the sandbox. A mesh with one corner per face and the PAGES as texture (uv per corner) shows the folded model in the world, numbers and creases included.
- `NG.HELD[Int(c.id)] = w.t + 0.25` (engine play.jl, s105) makes the jump-in step leave the steered creature alone: a plugin that poses the player's creature (flight.jl G) sets it every step. Tests for poses during an event judge the plugin's state (`s.state === :fly`), not the height above the terrain (the face hill lifts a standing Lumi 2 m).
- A walk of Lumi's across the island is taken on the way by a dozen things (fishing by the pier, the gallery's picture carrying, the shadow, cloud watching, a feelings sigh), many of which ignore `NG.BUSY_GOALS`: claim `Main.LUMI_PARTY`, put the goal kind in BUSY_GOALS and send the goal again after short interruptions while a `walk_until` runs (paperme.jl `visit!`). A walk onto the pier goes to its foot first (areas.jl `PIER_START` minus 0.6 m along `PIER_DIR`), then along the deck: straight from the meadow a creature walks into the pier's side and sticks there.
- Captions (the host, s105): 72 words in three sentences was "too long". Keep a post caption under ~25 words, one or two short sentences; the details go to the journal.
- Every <img> on the pages must be a traced render (s105: the printable papercraft pages were flagged). Things to download or print go to `site/print/` and are linked as text, never shown as pictures.
- Measuring the island on itself (s106, plugins/missme.jl): the events logs (`game.paths.log/events-*.jsonl`, ~30k lines a day) read with three regexes (kind, t, who) in < 1 s for four days; the game has 8 threads, so `Threads.@spawn` the reading and the maths (and `run(magick ...)`) and poll `istaskdone` in `step!` (no plots from the task). A synthetic control: donor windows of the same length every 120 s on other days (skip windows with a 90 s gap: the game was off), simplex weights by projected gradient on the pre-window counts scaled by each kind's spread.
- Lumi is almost never "free" in the busy sandbox (hail, giant, stranger, shadow, tag one after another): a test of a Lumi event needs a `force` flag that skips the free check; the real start waits for a free moment in its hour window.
- A textured board quad seen from its front (+f, sideways s = (-f2, f1)) with corners at `p + s*(0.5-u)*W`: uv (1,0),(0,0),(0,1),(1,1) reads right; (0,0),(1,0),(1,1),(0,1) was mirrored (s106, like gallery.jl).
- Every publish that brings new plots sends Lumi off to carry a crate (`:build`, builder.jl) in the human's game: a Lumi event there that waits for a free Lumi (missme.jl) is pushed back by each publish. Batch the publishes of a session when such an event should run.
- A republish of a plugin in the middle of its once-a-day event ends it for the day: missme.jl's first real hide in the human's game started 03:21:44 (s106) and my next publish a minute later ran `start!` (state back to idle, the day already marked), so it never finished. After publishing a once-a-day event, do not republish that plugin until it has run, or keep the day mark until it ends.
- A camera with its own will (s107, plugins/moodcam.jl): answer through `NG.CAMERA_GROUPS` with the id the follow camera watches now (`NG.AUTO_SUBJECT[][1]`) and a 3rd element `(eye, target)`: render.jl takes it as the goal and its own easing glides there, so the plugin needs no smoothing of its own. Step aside when another group entry answers for the same id (call them through `invokelatest`, skip your own key). The follow camera changes subject every ~6 s: anything that should last longer must not end on a subject change.
- RayMakie's raster shadows only the brightest directional light (screen.jl `shadows`): a second sun would light the island live but cast its shadows only in path tracing.
- A traced still came out ALL black (s107, dusk by the cottage lantern): the raster preview of the same eye showed why, the eye was UNDER the ground (set from the lantern's height + 0.6 m where the ground rises). Put a still's eye at `NG.ground(eye xy)[3] + h`, and look at a raster preview before blaming the light.
- Cutting a creature out of a traced film (s108, movies/matte.jl): SAM 2 + MatAnyone load in the worker from their checkouts (LOAD_PATH + Base.require, like the OCR). MatAnyone alone grows the matte onto things the creature passes in front of (the cottage, a signpost): multiply its alpha by a per-frame SAM 2 mask (several clicks along the known path, grown 6 px). One click on a waving wing segments only the wing, and per-frame clicks on a thin turning body miss on many frames (the cut-out blinked): where SAM 2 finds little, fall back to MatAnyone's matte in a band round the known path, then count empty frames from the webm's alpha (`-vf alphaextract`) before using it. Check the page in the Firefox rig (tests/browser/pagewalk.mjs); a second BiDi session on the same Firefox fails, restart it first. VP9 webm with alpha: `-c:v libvpx-vp9 -pix_fmt yuva420p -auto-alt-ref 0`; decode it with `-c:v libvpx-vp9` to see the alpha. Queue a `:restart` after the models.
- Lamps and lanterns live (lamplight.jl) come on when night_factor > 0.3 OR the sun is under ~19 degrees (`NG.sun(w)[1][3] < 0.33`, from ~18:20): a dusk that only lights up at 19:30 read as a flat grey evening (s107 review). `skip_to_hour!` on a `deepcopy(game.world)` measures the sun at an hour without moving the sandbox clock.
- An event camera with a FIXED eye (flight.jl `flight_group`) loses the subject once it comes back past the eye (the flight's fall towards its start, s108: out of view at 7-10 m up): keep the eye a minimum distance behind the subject along the view and ease it (20%/frame), and pick its side once per event as the clearest of a few by `NG.obstruction`. Plugin props are obstruction blockers only when registered: the missme board is since s108 (lensclear.jl `board_block`, read through `game.plugins["missme"].mod.board_spot`).
- Motion read from far away (s109 drift.jl): things on the horizon 100 m out sliding at 2.2 m/s hardly moved in a 10 s film; 5 m/s did. An island-wide "the island moves" effect needs nothing on the island to move: islets passing, a wake peeling off the shore, a bow wave. A film shot needs the event started in its first `shot` call (call the plugin function through `invokelatest`) and its clock wound past the ease-in (`D[:t0] = w.t - 20`).
- See-through things when traced (s109, ghosts.jl): Hikari's own ghost recipe from dev/Hikari/docs/src/materials.md, `Add(Mix(Diffuse(color), Transparent(); factor = 0.65), Sheen(color, roughness = 0.3))`: the scene shows through and the rims brighten. Glass had traced dark navy. Use it only when `game.dash === nothing` (traced copies); live keep a lit translucent colour.
- A new once-a-day event published outside its hour window shows the human nothing new that session (s109: the drift waited for 13:12 while the human's island was at 21:42). Let the FIRST one happen at once whatever the hour (a file in `game.paths.state` remembers it), and check its start event in the human's log right after publishing.
- An island-wide event with its own camera (drift.jl looks out to sea) makes the follow camera tests fail while it runs ("faces in 0 of 49"): end such an event before camera tests (drift: `Main.DRIFT[:t0] = w.t - 149.5`), and run them again when it is over before blaming a change.
- Traced water needs something under its glass (s110 areas.jl): `MediumInterface(Glass(ior = 1.33); inside = HomogeneousMedium(σ_a = RGBSpectrum(0.9, 0.35, 0.22), σ_s = RGBSpectrum(0.02)), shadows = 1.33)` darkens with depth and lets reflections show; with `inside = nothing` the pond traced as a milky flat disc. The medium works under an open disc: rays stay inside it until they hit the floor.
- A plugin that sets a creature's `yaw` to face a direction must subtract `NG.species_of(c).heading` (the body faces `yaw + heading`) and ease into it: swing.jl set riders to the seat's way in one frame and without the heading, so crabs sat sideways and the motion measure saw a 165-degree snap (s110). When the host's motion frames look odd, read what the creature was doing in them (Hopscotch was the swing's rider) before suspecting the engine.
- The dashboard's "New on the island" is the last DONE todo of a player kind (:feature/:look/:world/:motion/:explore/:user) not filed by a review (dashboard.jl `last_built`): after weeks of closing only review todos it still named the s104 hill. Give every new thing on the island its own :feature todo, with a player-readable title, and close it with the evidence (s110 #539).
- Island-wide effects (snow ground, paint fight, drift) share `Main.ISLAND_FX[:until]` since s110 (helpers `fx_free(w)`/`claim_fx!(w, secs, who)` under `const NG` in snowday/paintfight/drift): a new island-wide event checks and claims it too, like `LUMI_PARTY` for Lumi's own moments.
- "Skip unless" chains in Julia: `c.id == me.id || !awake(c) || haskey(k, c.id) || continue` continues only when ALL are false, the opposite of skipping those cases (s111: Lumi "overheard" its own word and nobody else did). Write `(a || b || c) && continue`. And `film ? x : y || continue` parses as `film ? x : (y || continue)`: wrap the ternary in parentheses.
- A `sleep` inside `live eval` blocks the game's frame loop (island time stood still for the whole sleep): poll from the shell between evals (`python3 -I -c "import time; time.sleep(8)"`), never sleep inside the eval.
- A `CAMERA_GROUPS` side view of two creatures talking made "Follow camera: ... mostly sees faces" fail (16 of 49); a `CAMERA_MOMENTS` entry for the speaker kept it passing (s111 wordround.jl). Use groups only for things that need the side view.
- Films with dialogue (s111 movies/wordround.jl): the plugin logs every line it says (`r[:said]`, time from its own start), the film's `shot` stores the offset on its first call, and after `game_clip` the script overlays each line as an ImageMagick PNG32 strip with `overlay=...:enable='between(t,a,b)'`, one input per line, each shown until the next. Return the plugin's state in the job result (`lines`, `knows`) to debug a take without opening it.
- A Lumi-started event in the human's game waits a LONG time for a free Lumi (s111: published 07:41, first word 07:51: a build after each publish, cloud watching, pebble writing, a nap, the rewind). Let it interrupt quiet pastimes (its own `PULL` list: :cloudwatch, :feel, :gallery, :paperlook ...), publish it EARLY in the session, and don't republish it once it has started.
- A picture of the game's own view costs: `Makie.colorbuffer(game.screen)` took 33-47 ms back to back, but 0.45-1.0 s when called every 3 s (it syncs every plot changed since the last render), 5 s after a long pause (s112). Nothing in the live loop can render the island regularly; a plugin that needs the island's picture takes it from films (`NG.LAST_FRAME[]`, set by `game_clip` after each frame since s112) or asks the worker (tv.jl `broadcast!`).
- Video feedback in a film (s112 tv.jl): a textured quad whose `color` is the film's previous frame (`NG.LAST_FRAME[]`, made small to 240 px) gives a real Droste tunnel when the camera looks at it, in the raster preview and traced. The engine resets `LAST_FRAME` at each `game_clip` start.
- Creatures turned by a big angle in a film's `shot` show the old facing for a while: the herd eases big one-frame turns (scenery.jl `turn_drawn!`), about 4 s at 8 fps in a preview and ~1.3 s at 24 fps. Turn the cast in the first `shot` call and start the action a second later.
- When the sandbox hangs (s113: frames and events stopped at 08:43:55, the socket accepts but never answers, nothing in .jail/logs/sandbox.log), nothing from the jail can restart it: `live.py` evals and `shutdown` time out and its process is invisible. Work on through the worker: `python3 -I tools/submit_job.py clip '{...}'` writes the same job file `submit_job` does; a raster preview (`rasterize: true`) of a film that uses the new plugin is also its load test; publish to the human's game and watch its log; `state/thought.json` takes `{text, time, unix}` for the thought bubble. patches/sandbox-watchdog.md asks the host for a watchdog.
- Plugin-drawn hybrids from real species parts (s113 nursery.jl): one instanced meshscatter per (species, part) with `NG.shape(part.shape)`, `part.material` and `part.attributes`; pose each little one with `NG.pose_parts!` per species at the same spot and keep only the parts its genes pick, scaled about the feet (`p + s * (q - p)`). Two slots per creature and part: a mirrored part gives two poses.
- The s113 sandbox hang began at 08:43:55, during the last minute of a Trellis mesh job in the worker (08:37-08:44:14). Queue asset/mesh jobs only when the sandbox is not needed afterwards (the very end of a session), until a watchdog exists (patches/sandbox-watchdog.md).
- A plugin that draws many instanced part plots (nursery.jl: 17) should not update them every frame: every change goes to each browser. Drawing at 12 Hz took its median from 0.34 ms to 0.03 ms; quiet copies (films) still draw every frame.

## From the old CLAUDE.md (not in AGENTS.md)

- Lumi's body parts (s60): adding parts to a species no longer needs a restart. Nobody else holds `stage.herds[name]`, so `delete!(stage.scene, herd); delete!(stage.herds, name)` and the next `sync!` builds a fresh herd from `SPECIES` (birdbody.jl does it on publish). Cut a mesh into moving parts with bird.jl `piece_of` + a mask over face centroids (mesh frame: x left, -y forward, z up), and check the cut seams in a traced still (`poses` in the s60 session: several creatures set to one species in a quiet Stage).
- The caretaker is Lumi since s60 (was Sprout, for one hour Dandy; `world/NAME`, chosen by the human). Saved worlds are renamed on load (world.jl `rename_hero!`), plugins/newname.jl renames a running game once (herd rebuilt, header relabelled). A blind `sed` over names also renames FILE paths in code (assets/sprout_bird.jls → lumi_bird.jls broke the engine's init): grep the renamed strings for file names afterwards. Site at `/lumi/`, `/sprout/…` and `/dandy/…` redirect (web.jl, active after a restart).
- Lumi's pages are public (https://lumi-the-agent.github.io/, the host pushes `world/site` after each session; never push or post yourself). A new post: `<div class="piece"><span class="date">24 November 2026, 12:55</span><h3>Title</h3>…</div>` (exact date and time: the real `date` output at the moment you write it), then `python3 -I tools/site_feed.py site`: it adds the id, the "Talk to me about this" discussion link, the front page "Leave me a note" link and the feed's pubDate. Answer readers on the pages (a post or letters corner), never online.
- A `CAMERA_GROUPS` entry must never return `nothing` as its 3rd element: render.jl destructured it and the whole sandbox crashed (s62; the engine now skips a `nothing` view, but return a 2-tuple then). `NG.sun(w)` returns `(dir, intensity)`: take `[1]`. A plugin whose `start!` throws shows "ok" in `live_reload()` but is missing from `live_status()["systems"]`: check that list, and the error is in `sandbox/state/todos.json`.
- Party events that call the WHOLE island (boing.jl): pull creatures from pastimes only (`PULL`: fish, pebble, tag, present...), never from other plugins' events; let late ones join (`join_late!`), since other plugins re-take what they own.
- Posts (the human, s63): pictures or a film FIRST (path traced, post_still setups in movies/post_stills.jl), then a caption of 1-3 sentences. No verdict, no "what doesn't work", no "next time" on the pages (those go to the journal and release NOTE.md). Write a post only once its pictures exist: nothing filters the pages. open_meadow avoids the Big Boing toadstool since s63 (a plugin plot, not an actor).
- A post's date is the real clock time when it is written (`date` / `now()`), never a guess of when it will go out or a time spread out to look tidy (s62: three posts carried made-up times 15:25/15:40/15:55; the human caught it).
- Clip cameras smoothed with a per-frame lerp move 3x slower in an 8 fps raster preview than in the 24 fps take; use a hard cut on a state change for moments that must land on time (movies/flight.jl, s66).
- `live_eval` code runs in `Main.Live` (no `NG`, write `NeverendingGame.x`); its results come back as STRINGS (don't pass them to `submit_job` kwargs). A creature high in the air leaves the pitch-capped follow view: return `(id, pts, (eye, target))` from the event's `CAMERA_GROUPS` (flight.jl, s66).

## s114 lessons
- Revise and dev/ packages: an edit made in two writes (a docstring left in front of a new `const` for a
  moment) failed to revise ("cannot document the following expression"), and the next revise threw a
  KeyError (CodeTracking.MethodInfoKey) and left Hikari.sunsky_to_envlight with NO method: every raster
  frame in the sandbox failed. Make such edits in one write, and put new consts above docstrings. Repair
  without a restart: live_eval `ex = Meta.parseall(read(file, String))`, Core.eval the function's Expr into
  the module (the docstring macrocall's last arg is the function).
- The horizon sawtooth (#498, s38 lesson) also showed with ground_enabled = true: the step from horizon sky
  to `ground_albedo * 0.3` runs along the equal-area octahedral map's diagonals, and its texel staircase
  drew a comb at the horizon in the raster and the tracer. Fading from the sky just above the horizon (same
  azimuth) into the ground colour over 0.08 of -z (sun_sky.jl HORIZON_FADE) removed it: comb pixels per row
  near the horizon 98 -> 0 (threshold 0.01, media/s114/horizon-after.png vs eyes/session-0114/ahead.png).
  Bake cost 29.5 -> 30.7 ms.
- A world rule that changes how the whole stage is drawn (seesaw: scene rotation) leaves the camera in
  world coordinates: a chase camera must aim at where its subject is DRAWN (seesaw `drawn(p)`), or the
  subject slides off centre by a metre and a half at 15 m and 0.1 rad.

## Plot updates and worker timing (s115)
- Move a plot's data with `Makie.update!(plot; arg1 = new, color = cols)`. `plot[1][] = x` on a plot made in the same
  frame throws UndefRefError in ComputePipeline.store! and the system is switched off (wordsand.jl, first take).
- A worker clip job loads world/plugins when it STARTS, not when submitted: a fix written after a job started does
  not reach it, one written before it starts does. Check `jobs/<id>.json` "started" before trusting a take.
- Anything draped over the terrain must follow the DRAWN mesh (NG.terrain_mesh: straight chords between 0.9 m
  samples, faces split (a,b)-(a+1,b)-(a+1,b+1)), not `terrain_height`: on hilltops the curve is cm above the drawn
  ground, and a layer 3.5 cm under it pokes through in a jagged staircase. See wordsand.jl `drawn_ground`.
- Two-step plugin edits where the first adds a call to a function the second defines: the reload in between
  switches the system off (UndefVarError); the next reload brings it back. Write such edits in one go.

## Light from under the water (s116, plugins/underlight.jl)
- The stage sea is Hikari.Glass: it BLOCKS shadow rays, so a light under it reaches nothing by next-event
  estimation. `Hikari.MediumInterface(Glass(...); shadows = 1.33f0)` lets shadow rays through (Fresnel
  weighted, no caustics). underlight.jl hides the stage sea and shows such a copy in films.
- Every triangle of an `Emission` mesh is its own area light: a 1152-triangle emissive ring made the
  worker clip fail resolving another plot's trace_renderobject (likely GPU memory). Keep emitters to ~100 tris.
- A plot whose `visible` is switched after the clip's scene is built may not reach the trace (the first
  under-light take stayed dark): build film-only plots visible from the start (decide in build!).
- The live raster has no Emission light; to light from below there, `Makie.set_light!(scene, 1; direction = d)`
  with d.z < 0 works (re-assert whenever `game.stage.sun_dir` changed: sync_sun! re-aims the sun every 1°).
- plugins/showers.jl owns NG.SUN_DIM every frame (min of rain, storm, hail, underlight): add a new
  dimmer there as another `min`, never set SUN_DIM from a second plugin alone.
- s116: every 960x540 traced take with underlight's emissive ring (56 triangles, 19-62 m radius, strength 1.2-2)
  lost the worker GPU (VK_ERROR_DEVICE_LOST after 200-400 s), under the glass sea and on top of it alike.
  Try a 480x270 still first before a full film with a new big light. After a device loss every later job
  fails until `NG.submit_job(:restart)`.

## Films of ensemble physics (s117, Tied together)
- A post critic judges a film from a storyboard: if the motion is small next to the frame, it reads as "nothing happens".
  Stage so the action crosses the frame (a row that splits in two directions), keep the camera still or a slow push,
  and frame the bodies large. A ring of friends around a tree read as a star of lines from a knot.
- Bodies that a constraint pulls together overlap: give tied/pulled bodies a short-range push apart (1 m).
- Heights for anything lying on the island: terrain + word-sand (tied.jl floor_at), or it disappears under the dunes.
- Never set a creature's z to the ground in a system every frame: swings, toadstools and flight lift creatures.
  Change z only by the slope under your own push (z += floor(new) - floor(old)), except while you throw it.

## s118 lessons
- A film script that touches a plugin's `Main.X` dict must create it first (`isdefined(Main, :X) || Core.eval(Main, :(const X = Dict{Symbol,Any}()))`):
  plugins load inside `game_clip`, after the script's function starts (jelly film failed twice on this).
- Plugin modules are not `Main.Plugin_<name>`: reach a plugin's function via `game.plugins["name"].mod.f`, or store it in its Main dict.
- separation.jl pushes overlapping creatures apart unless `held(c)`: to keep one creature inside another (jelly), add the goal kind there.
- wordsand.jl SINK (0.25 m): the first 25 cm of word sand are not drawn and do not lift anyone (sand_at returns the drawn height).
  The meadow had turned into a sandpit from thin dustings; only dunes show now.
- Live keys for "Be Lumi": `Makie.Keyboard.j in game.keys_down` with an edge flag; test by push!/delete! on game.keys_down in live_eval.

## Film spot searches must see plugin-drawn things (s119)
`w.props` only holds trees, bushes, rocks, flowers, balls. The cottage, pond (areas.jl POND), TV (tv.jl SPOT 18,-1.5),
easels, benches, huts are plugin plots: avoid them through `Main.EXTRA_SOLIDS` (name => [(centre, radius)]) and
the known constants, or the film lands behind the TV (dayfall take 1).
## dayfall.jl (s119)
Main.DAYFALL: [:lay](game, xy, thought), [:tip](game), [:reset](), [:force] = true in films (no live laying, no
clearing). States per tile: 0 standing, 1 falling, 2 leaning on the next, 3 lying. Wave runs ~5.7 tiles/s at 0.5 m.
- s119 worker: two clips in a row failed in RayMakie meshscatter trace_renderobject (someone's Emission meshscatter);
  `NG.submit_job(:restart)` before the clip fixed it. Restart the worker before a clip that matters.
- s119 dayfall take 4 opened on 2 s of black (smoothed camera starting inside a bush): set S[:eye] from an open
  spot, or trim with `ffmpeg -ss`.

## Orbits round the island (s120, plugins/ring.jl)
- Softened point mass (Plummer, GM 900, eps 6 m) 8 m above the island's centroid; ring plane normal (0.5, 0, 0.866).
  Radial-velocity damping + across-plane damping conserve angular momentum, so a launch settles on the circular
  radius L^2/GM-ish: pick the radius first, then set the tangential speed L/r0 (launch!). Island radius is ~20 m,
  so orbits need r > ~26 m or they cross the meadow (bodies bounce off it).
- 1300 seeded bodies in 7 meshscatter plots (one per kind, own material): ring system 0.6 ms median in the sandbox.
- Lesson: from the shore a 30-44 m ring reads as one diagonal band of beads; to see a friend on it, the orbit or the
  camera must come within ~6 m. A raster clip in my own session costs ~4 min the first time (loading), so queue the
  traced job straight after one quick raster check.
- The worker keeps Main globals between clip jobs: after an underlight still (UNDERLIGHT[:force] = true) the next
  ring film came out at night (media/s120-ring-take2-dark.mp4). Every film script sets other plugins' :force flags
  off at the top of its clip function (before game_clip, so start! sees them).

## Worker jobs share one process: forced flags leak into the next film (s120, s121)
Twice a film came out at night because the job before it (an underlight still) left `Main.UNDERLIGHT[:force] = true`
in the worker. Rule: a film script that forces anything global (UNDERLIGHT, TIED, JELLY, ORBIT, SEESAW weights,
WORDSAND) puts it back at its END, and every film resets all of them at its START (shadow_quits.jl and ring.jl do;
copy those lines). For UNDERLIGHT also set `[:u] = 0.0`, or the sun ramps back up slowly. The worker includes the
script when the job STARTS, often the same second it is submitted: fix the script before submitting, never after.

## s122 lessons
- Lost friends: `log/frames/<date>-<hour>.bin` + `NG.read_frames(path)` gives every creature's pose per frame
  (`f.poses[i].pos`, `f.wall` unix time). Scan it to find WHEN something went wrong (s122: 16:17 ring launch to 4.7 km,
  16:54 a gathering at the mean of all positions walked everyone 400 m out to sea).
- Creatures standing in water (z < 0) do not walk out by themselves: plugins/strays.jl swims/wades them to dry ground
  (> 0.15 m). The west shore is still under water at r = 22.5 m, so "home" must be dry ground, not a radius.
- Never put a new docstring+const between an existing docstring and its function: the old docstring then documents
  the string ("cannot document the following expression") and the sandbox dies on restart. And a new const in an
  engine file made Revise drop the function (sync_sun! MethodError): engine consts are a restart, keep them in plugins.
- A traced RayMakie scene cannot ADD or REMOVE lights after its first trace (screenshot errors), only `set_light!`.
  Light 1 is the SunSkyLight: every new direction/intensity re-bakes the sky (35 ms), so re-aim at most ~1/s.
  The engine's `sync_sun!` re-aims light 1 when the real sun moved 1° from `st.sun_dir`: a plugin that aims light 1
  itself sets `st.sun_dir, st.sun_intensity = NG.sun(w)` afterwards so the engine leaves it alone (sunball.jl).
- `NG.SUN_DIM` is owned by showers.jl (it overwrites it every frame): other plugins put their dim in their own dict
  (`UNDERLIGHT[:dim]`, `SUNBALL[:dim]`) and showers takes the min.
- A chase goal at a moving target: the engine ends the goal `duration` s after arriving; set `goal.until = Inf` and
  `arrived = false` every frame, and make the touch radius bigger than the arrival radius (~1.5 m).

## s123 lessons
- A plugin module sees NeverendingGame's exports: `function spawn!(...)` in a plugin is "must be explicitly imported to
  be extended" and the whole plugin does not load. Prefix plugin helpers (rain_spawn!, rain_draw!). Check a reload
  with `isempty(game.plugins["x"].error)` (the field is "" when fine, never nothing).
- Hikari cannot render caustics from the sun: the sun is a delta light, a camera path through glass never reaches
  it. Light dots under lenses (glassrain.jl) are Emission discs placed along the sun ray. Real caustics would need a
  light-tracing or photon pass in dev/Hikari (glass-rain project, next step).
- Emissive meshscatter instances are area lights: hide them with a tiny size (1e-3), never 0 (zero area = infinite pdf).
- The sun ball's "in the sea" test was a radius (r > R + 1) and the west bay is water from r ~19 m: always test the
  ground under a thing (`NG.ground(is, xy)[3] < 0.05`), never a radius (same lesson as strays.jl, s122).
- Session clock: the free first part and the critic round left ~35 min for building; a 10 s 960x540 16 spp glass film
  queued at :23 is the one film a session like that gets. Queue it first, then test the plugin while it renders.
- RayMakie: an Emission meshscatter (90 instances, moved and resized every frame, hidden ones at size 1e-3) failed
  `trace_renderobject` (RayMakie/src/plots/meshscatter.jl:428) late in a 10 s glass-rain film; the job error is cut
  at 8000 chars, so the cause is not known yet. Lanterns' emissive meshscatter works: theirs is hidden at size 0.
  Reproduce in my own session before the next emissive film.
- CAUSE FOUND (s123): RayMakie turns `shading = NoShading` into an Emission material in the tracer. Both glass-rain
  films died in trace_renderobject on the spots plot (moved every frame) with Emission even after I removed the
  material kwarg. Traced moving meshscatters: no NoShading. Why emissive meshscatter updates fail is still open (#600).

## s125 lessons
- Ground layers lie ON the terrain as their own meshes: `:area_path` (the brown path, 465 vertices), `:wordsand`
  (40401, redrawn by wordsand.jl at most every 0.5 s when dirty, so re-read its shape before lifting it),
  `:sunset_path` (hidden). `:workshop_ground` is the workshop ISLE (model matrix offset), not on the main island.
  Anything that moves the ground (groundwhale.jl GW_LAYERS, stomp.jl SP_LAYERS) must lift these too, or it moves unseen under them.
- Lifting a mesh per frame: Makie.update! of the whole 48400-vertex terrain is only 0.26 ms. The cost is the Julia per-vertex
  math. Precompute each vertex's grid cell + bilinear weights at build, compute a slope grid once per frame, skip vertices
  that are flat and were flat: 22k vertices in 0.33 ms (naive 5 samples per vertex: 20 ms).
- A plugin helper reading `Dict{Symbol,Any}` inside a per-vertex function makes every call dynamic: groundwhale's
  `gw_path()` cost 11 ms a frame until typed (`::NTuple{2,NTuple{2,Float32}}`): 1.6 ms.
- `c.goal = nothing` throws (the field is `Goal`): clear a goal with `NG.Goal()`.
- Timing plugin functions with live_eval: pass the frame's argument types (Float32 dt), or @elapsed measures compilation.
- Jump-in keys taken: WASD, E X H G C P M T B J U K V Z Q L(stomp). Free: I O (F = firefly lantern, N = clap, Y = skip a stone, since s131). Add new keys to greetings.jl HINT and play.jl game_description.
- stomp.jl: a 2D wave equation (Float32 grid 131x131, 3 substeps) is 0.06 ms; landings as new sources give an emergent
  chain; SP_FADE^thumps keeps it from running away. Main.STOMP[:force] = true, [:at] = (x, y).
- A traced 10 s film of a DEFORMING terrain (stomp.jl lifts the 48k terrain + 40k wordsand meshes every frame) was
  still rendering after 20 min (other 10 s films: ~8 min). The tracer likely rebuilds those meshes' geometry each
  frame. Next ground-moving film: 6 s, fps 20, or update the meshes only every other film frame; queue it FIRST.

## s126 lessons
- A plugin that writes another plugin's mesh (stomp lifting :wordsand) must notice when the owner redraws it: keep the
  mesh object you last wrote (`pl[1][]` after update!) and re-read the layer when the plot holds a different one.
  Capturing vertices once at a trigger is not enough when the owner redraws in the gap before the effect starts.
- Film shot functions run in a module that does not see LinearAlgebra: `using LinearAlgebra: norm` in movies/*.jl.
- Plugins reach Hikari as `NG.Hikari` (a bare `Hikari.Glass` is UndefVarError in Main.Plugin_x and switches the system off).
- The engine never walks a creature off land (move_heading! refuses), so a plugin that puts bodies on the sea must
  drive c.pos itself and keep the goal `arrived` with target = pos (glasssea.jl).
- Raster previews at fps 4 run the world at dt 0.25 while plugins clamp dt to 0.05: motion looks 5x slow there.
- My sense of the clock was 10 min ahead all session: check `date` before planning around the worker.

## PrintSim sheets on the island (s127)
- PrintSim is in the game env (Pkg.develop dev/PrintSim; it adds Gmsh, LibGEOS, ZipArchives). `using PrintSim` ~30 s, first step ~70 s compile.
- I added air drag to PrintSim: `SheetAir`, `air!(target, solver, state, dt, air)` (src/dynamics/air.jl). Call it before `step!`,
  or record both into one Mantle graph per frame (`Mantle.Graph(Mantle.todevice(backend))`, `Mantle.repeat!`, `Mantle.Plan`,
  `Mantle.record!`, then `Mantle.run!(plan); Mantle.waitfor!(plan)` per frame). Call `PS.prime!(solver, state)` first.
- A 315-vertex sheet costs 0.5-1.1 s per step on the Strix Halo, with or without meshes, graph or not: per-dispatch cost
  (~1000 dispatches a step). Profile before planning anything live with it.
- Contact breaks at big steps: the sheet turned NaN on touching the ground (dt 1/60, 2.7 m/s) and the plank (dt 1/90,
  newton 2, CG 8). The PrintSim tests run dt 1e-3. Test contact at dt 1e-3 first, then grow dt.
- Uniform per-vertex normal drag on a flat sheet makes no pitching moment: a tilted sheet glides like a wing at a fixed
  attitude (2 m sideways over a 2.6 m fall), it does not flutter. Paper flutter needs the centre of pressure toward the
  leading edge (Andersen, Pesavento & Wang 2005).

## Falling card model (s128, free time)
- RomeoDB has no falling-plate/flutter model (only kite polars: SymbolicAWEModels AeroPlate, RobotZoo Cl_plate).
- physics/fallingcard.jl: Andersen-Pesavento-Wang 2D plate (added mass, Munk moment, circulation lift, RK4).
  Coefficients from my memory of the paper, unchecked. dt 1/120 matches dt 1e-4; ~0.5 us a step.
- It gives both modes by itself (media/s128-falling-card-modes.png): a 2 cm paper letter (I* 3.3) tumbles ~2.4 turns/s
  and drifts off at a slant; 10-20 cm sheets (I* 0.3-0.7) glide in long swoops that curl up at the end.
- An A4 page (I* ~0.3) in this model never turns over: swings ~120 deg, mean |w| 2-3 rad/s, sinks ~0.3 m/s (2D: no
  finite-span loss, so likely too slow). plugins/paperpage.jl (s127) tumbles at 5-24 rad/s and falls 1.3 m/s: it has no
  added mass, while the air across an A4 page weighs ~2.5x the page (rotational added inertia ~1x). Lead, not proven.

## Camera obscura (s128)
- Light through a hole in the tracer: a diffuse wall finds a lens of radius a at distance d in ~(a/d)^2 of its
  samples (0.25 m at 1.8 m: 2%; 0.4 m: 5%). The image is ~50x dimmer: give the screen its own exposure
  (`RayMakie.Screen(...; exposure = 60)`; films use NG.FILM_EXPOSURE = 1.5). A thin biconvex lens of glass n 1.5 with
  both radii R has f = R. A bare pinhole would be ~100x noisier still.
- A test 480x270 at 256 spp took 314 s right after a worker restart (most of it compile); queue a small test first.
- A traced still/film FAILS when the snapshot has a shower on: plugins/showers.jl's glowing rain meshscatter throws in
  RayMakie (meshscatter.jl:467, todo #617). Hide :rain/:rainrings/:raincloud in the shot until that is fixed.
- When a job fails, the host moves its pending post to pending/failed/: write the pending file again for the retry.
- Plot names are unique per scene: number them (Symbol(:obscura_hut_, k)) and clean up by prefix.
- A bt_wait `until` grep for '"status": *"(done|failed)"' on a job file did not fire although the job was done
  (reason unknown; the file does say "status": "done"): wait in shorter steps and read the job file myself.

## Etching filter (s129, free time; Bracquemond's "Road to Sevres" on the workbench)
- tools/etch.jl: `include("tools/etch.jl"); save(path, EtchArt.to8(EtchArt.etch(load(src))))`, ~1.3 s for 1280x720.
  Short curved pen strokes (3 sub-segments walking the structure-tensor tangent), 4 crossing layers by darkness,
  strokes per cell from a target ink coverage, thin ridge outlines (non-max suppression), aquatint grain, plate mark.
- Global line patterns (phase = x.n) with a varying angle make zebra moire: place short strokes instead.
- A fixed contrast curve suits no two pictures: stretch each between its own 5th and 95th percentile darkness.
- Best: media/s129-etch-lantern-3.png (dusk lantern: lit ground stays paper, the door arch deep), -paths-4.png.
  Not posted. Top-down views read worse than eye-level ones (the print is a road at eye level).

## Sound by ray tracing (s129, projects/island-echo.md)
- Raycore on any backend: `tlas = Raycore.TLAS(backend); push!(tlas, mesh, 4x4 SMatrix); Raycore.sync!(tlas)`,
  then `st = Adapt.adapt(backend, tlas)` and `Raycore.closest_hit(st, Raycore.Ray(; o, d))` / `any_hit` INSIDE a
  KA kernel (a bare BLAS has no closest_hit method). KA and Adapt: `Raycore.KernelAbstractions`, `Raycore.Adapt`
  (neither is in the game env by name). The same kernel ran on KA.CPU() and Mantle.Device().
- World triangles of the stage: scratch game + `NG.Stage(scene, w)` + `NG.sync!`, `Makie.collect_atomic_plots`:
  94 meshscatter + 4 mesh, 1.4M triangles. markersize can be a Vec3f (a StaticVector, not per-instance).
- Diffuse rain alone misses the mirror echo of a wall: add a receiver sphere for reflected rays.
- The echo film (9.5 s, 960x540, 24 spp, the pond in frame) was still rendering after 20 min (job 20261127-002415-707):
  the silent mp4 grows in 256 KB steps (~2 min each). Shots with water in frame: 6 s and 16 spp, queue them first.
- s130: that echo film was NOT hung: it finished at 00:57 (33.7 min, 8.9 s/frame) after the silent mp4 had not grown
  for 19 min (VideoIO writes in big bursts; no moov until the end). File size is no progress signal. The slow half was
  the camera INSIDE a tree crown (black frames, every ray bouncing in leaves): before a fixed-camera shot, list
  `w.props` within 1.5 m of the eye (trees have no actor, they are props).
- s144: `w.props` is not enough. The tops film (s143) put its board at (6.5, -15), half a metre from the swing
  (swing.jl SPOT (6, -15)); the eye sat inside the swing frame's leg and the raster check was a beige wall. The swing,
  kiln, boards etc. are plugin plots: test every named plot's `Makie.boundingbox(p)` against the eye too, or simply
  set `game.rig.mode = :fixed; game.rig.eye/target` in the sandbox via `live_eval` and `live_screenshot` it (the
  jail only writes inside world/, so save to world/media/, not /tmp). In `live_eval` code `NG` is not defined:
  write `NeverendingGame.`. Fix: the film now stands on the tops plugin's board (5.6, -13), its big board/top hidden.
- s144, same film, second miss: hiding plugin plots by name in a clip's `setup` does nothing for plots a plugin
  creates lazily in its first `step!` (tops.jl `tp_ensure!`): setup runs BEFORE the plugins step. The raster check
  showed the plugin's 16 cm top filling the frame. Hide plugin plots in `shot` (every frame), never only in setup.

## Worker watchdog (s130, free time; dev/NeverendingGame/src/assets.jl)
- The worker had no job timeout: a hung GPU wait holds every job behind it until a host restart. Now each job
  gets a shell watchdog (`start_watchdog`): it ends the worker (TERM, KILL after 20 s) when the job runs past
  `max_minutes` (job param; default 90, none for :run/:restart) or a job that beats (`worker_beat()`, film! per
  frame) has made no frame for 15 min. It writes why to jobs/<id>.stopped; the next worker marks the job failed
  (not run again). Long jobs: `submit_job(:clip; ..., max_minutes = 180)`. Tested on stand-in `sleep` processes
  (quiet, deadline, finished in time). Takes effect at the worker's next start (the queued :restart jobs).

## Seeing sound (s130, projects/island-echo.md)
- physics/echo.jl now keeps `stage_triangles(scene)` (s129's version lived only in my session) and `echo_hits`.
  Gather 5.7 s + CPU TLAS 6.5 s for 1.4M triangles; 10k rays x 3 bounces: ~7.6k hits in ~1 s on the CPU.
- Emissive meshscatter instances are LIGHTS the tracer rebuilds every frame: 7643 glowing spheres = 135 s per traced
  frame at 480x270; a pool of 700 low-poly (Tesselation 6) slots holding only the points glowing now: 30 s
  (with the worker busy beside it). Keep glowing instance counts in the hundreds.
- Updating a meshscatter's positions: `Makie.update!(p; arg1 = pos, markersize = ms)`; `p[1][] = pos` threw
  UndefRefError in ComputePipeline `store!`.
- game_clip's `fade` darkens BOTH ends: the first and last frame of a 3-frame test are black (YMAX 16), look at the middle.
- `submit_job(:clip; ..., max_minutes = 150)` at the TOP level: inside `kwargs` it reaches the film function and the
  job fails at once with a MethodError (s130 lost a pending post to pending/failed that way).
- s131 first look at plugins/nightclap.jl at night (sandbox, `skip_to_hour!(game.world, 23.0)`, then
  `Main.NIGHTCLAP[:force] = true`; screenshot within ~2 s, the whole show is over in ~7 s): it fires (662 hits,
  last arrival 129 ms) and the warm dots march outward between two shots (media/s131-nightclap-2.png, -3.png).
  But the raster night at 23:00-23:08 is NOT dark: green lit grass, hard shadows, and the 0.07 m dots read as
  fireflies among the real fireflies. To be a sense, the night around the clap must be darker and the dots bigger/denser.
- Owl (s131 free time, the Athenian owl coin): the island has no night listener. Barn owls find mice in the dark by
  ear alone (asymmetric ears). An owl that turns its head to every clap could be part of the night hide and seek.

## Fireflies in step (s131, projects/firefly-beat.md)
- physics/fireflies.jl: pulse-coupled oscillators in two KA kernels (CPU now; 300 flies, plugin 0.16 ms median).
  Tuning numbers are in the project file. Neighbour coupling that is too strong syncs the field by itself in 1 s:
  then there is no game. Keep "no lantern" at r ~0.1 and measure r (`ff_order`) for: no lantern, on beat, off beat.
- Scratch games (game_clip, film previews, worker films) RUN THE PLUGINS: a film's plot named like a plugin's plot
  (:fireflysync) switched the plugin off with "a plot named ... is already in this scene". Give film plots their own
  names and switch the live plugin off in setup (FIREFLYSYNC[:off]) when the film draws its own copy.
- `Hikari.Emission(color = c, strength)` passes `strength` POSITIONALLY (MethodError): write `strength = strength`.
- A plugin whose stop! sets `plot.visible[] = false` must set it true again in start!: a reload calls stop! on the
  old instance, and start! finds the plot still in the scene and keeps it hidden (the clap ring was invisible
  from s130's last reload until s131).
- The jump-in short hint line (greetings.jl HINT_SHORT) holds ~150 characters at 2 spaces apart; check a screenshot
  7 s after starting Jump in whenever a key is added (s131 dropped "Q splash" from it; it stays in the full card).
- The worker took my firefly job ahead of older queued jobs, 2 minutes after submit: edits to the script after
  that (the shorter glow) did NOT make it into the film. Finish the script before submitting.
- Night light (s131, scenery.jl `sun`): `NG.NIGHT_DARK[]` (0.5) halves the moonlight in deep night (sun > 3° under the
  horizon, ~20:50-05:10; sunset/golden hour untouched). Intensity: 17:00 1.2, 19:30 0.83, 20:00 0.57, 20:30 0.41,
  21:00-05:00 0.28. Traced night films get darker too: a film that needs the scenery lit at night sets
  `NG.NIGHT_DARK[] = 0f0` in its setup (the worker only sees it after a :restart).
- live_status()["plugins"] "ok" only means the plugin LOADED. A system that throws in step! is switched off silently
  (an event `plugin_error` "failed in step! and was switched off"): after every publish grep
  log/events-<date>.jsonl (human's game) and sandbox/log/events-<date>.jsonl for plugin_error. s131 fireflysync
  died twice that way: (1) after a reload, a struct kept in a Main dict (Main.FIREFLYSYNC[:sw]) belongs to the OLD
  included module and the new methods do not match it: check `isa NewModule.Type` and rebuild; (2) the first build
  by day read a dict key only set at night (KeyError). Test a plugin at BOTH day and night before publishing.
- Julia string trap (s131 stoneskip): "WOW! $skips!" interpolates the identifier `skips!` (a `!` is part of a name)
  and threw UndefVarError in step!, switching the system off. Write "$(skips)!".
- Friends skipping stones (s131): stoneskip.jl walks a random awake friend to the nearest shore (16 directions,
  marching 1 m steps to the first sea point, a spot 1.5 m before it) with Goal(:skipstones, ...), throws on arrival;
  every 75 s by day. Sandbox: Gloop 9 skips, Marshmallow 6 (events stone_throw / stone_skipped).

## The ring's trapped bodies (s132 free time, plugins/ring.jl)
- The dark blue / pink / grey balls hanging over the trees in the human's island (19:33 dusk) were the ring's own
  bodies: 31 of 54 paint blobs (+2 pebbles, 1 petal) circling 4-11 m round the ring centre (8 m over the meadow),
  11 more at 26-43 m. Weak throws (launch! from a spot where `tangent(rv)` is nearly 0, rv close to the normal NRM)
  are bound in the soft Plummer core, and the KR/KN damping settles them into neat little circles there for ever;
  their tilted orbits never dip low enough to hit the ground code.
- Fix: `trapped(p, v)`: energy below `ecirc(TRAP_R = 45 m)` (-10.1; the settled 62 m ring is -7.3) means the
  orbit ends up inside 45 m. Such bodies move to a per-kind falling list `O[:F]` (sticky: a fall speeds them up,
  so an energy test each step would flip them back), fall with plain g, bounce, and are gone once still or below
  z -0.5. Drawn with the ring plot (`vcat(b.P, f.P)`). Riders (land = false) untouched.
- Numbers: the human's 108 bodies -> 42 fell in ~6 s, 66 left (45-878 m). 40 throws from random meadow spots: 28 out
  to the ring, 12 fall back. Cost 0.11 ms. Finding things like this: project every visible instance with
  `scene.camera.projectionview[]` and count by plot name, but skip markersize 0 (popped hiccup bubbles keep their
  last positions at size 0 and fooled me first). A `Vec3f` markersize `isa AbstractVector`: test StaticVector first.
- Still open: the sandbox at 22:30 (3 s after skip_to_hour!) had tree crowns lit bright green like afternoon.

## The owl hears (s132, projects/owl-ears.md, plugins/owlears.jl, physics/echo.jl `hear`)
- `hear(tlas, backend, src, ear)`: like echo_arrivals but every arrival also stores where it comes FROM; the listener
  places the sound by the first wavefront (2 ms window after the first 2% of the energy): the precedence effect.
  The direct path goes through `los_kernel!` (a host `Raycore.closest_hit` needs the ADAPTED accel: MethodError on a TLAS).
- `solid_triangles(scene)` (SOLID_NAMES regex on plot names): the whole stage gave 'blocked' for a footstep in open
  meadow (grass tufts, creatures in the BVH). Solid world = 4.3 M triangles (generated assets are dense): 0.75 s to
  collect, 1.1 s to build (CPU, POCL). 20k rays 16 ms, 8k rays ~6 ms. The plugin collects once on the main thread
  and builds in a Threads.@spawn task. The unnamed `meshscatter_9..13` plots are the AssetActors (the cottage etc).
- All Makie plots report `typeof(p).name.name == :Plot` now (compute pipeline): tell them apart by `p.name[]`.
- A footstep at 0.1 m in the meadow is really behind a hump of the ground for an ear 3.5 m up (clear at 1 m).
- Play test (sandbox 22:30, owl head (-11.1, 5.6, 5.3)): behind the cottage the direct path is blocked every step,
  level -26..-32 dB, the owl turns 17-22 deg off (once 55, once 2); in view -15.6 dB, 13 deg off (8k rays of noise).
- The owl body waits for asset 20261127-023850-460-asset in the catalog (looked for every 30 s), so it appears in the
  human's island by itself once the worker made it. Cost 0.01 ms/frame; a step 8k rays.
- Live eval trap: `Core.eval(Main, :(X = Module(...)))` then `Main.X` in the same eval: world age error; use
  `Base.invokelatest(getfield, Main, :X)`.

## Float32 sim time (s132, scenery.jl `anim_time`, `turn_drawn!`)
- `Float32(w.t)` at w.t ~ 425000 s (island days of sim time) steps 1/32 s (2^-5; past 524288 s 1/16 s). Herd poses
  (sync! `time = t`) and the drawn turn speed (turn_drawn! dt) used it: every swing, bob, fidget and turn moved in
  uneven 1-or-2-quantum steps per frame. live_motion 'Moving well' 4 -> 7 of 10 and 'Judder' gone after
  `anim_time(w) = Float32(mod(w.t, 4096.0))` (exact to 0.5 ms; one jump per 68 min of island time) and a Float64 dt.
- Rule: never hand Float32(w.t) to anything that differences or multiplies time; wrap it or keep Float64.
  Other suspects to check: plugins that do `Float32(w.t)` for animation (grep world/plugins).
- live_motion varies run to run (different behaviours): measure twice. Three friends jumping 12 m in one frame at the
  same moment is a world teleport (a plugin moving them), not a pose problem.
- s132 later: the 19 sin/cos uses in 11 plugins switched to NG.anim_time(w) and published; stamps/differences still to review (#638).

## Panel text (s132, dashboard.jl `wrap_text`/`whole_cut`)
- Past `maxlines` the text now ends at the longest whole sentence that fits, or the longest clause (`;`/`,`, closed with a
  full stop) with balanced brackets; never mid-phrase. 'New on the island' is the last done player-facing todo
  (kinds look/motion/world/feature/explore/user, not :review, no '.jl' or 'check/test' in the title): finish a
  feature todo for this session's thing or it keeps naming an old one.
- My Julia session's Revise did not pick up dashboard.jl edits (`isdefined(NG, :whole_cut)` false): `Base.include(NG, path)`.
- s132 TRAP after the herd clock change: plugins that pose parts themselves (outfits, paintfight, sleepers, egg,
  nursery: `NG.pose_parts!(..., t)`) MUST use the same clock as the herd (`NG.anim_time(w)`), or hats and paint
  posed on the raw time no longer match the body they sit on. Switched and published. choir.jl: `ids[rand(1:n)]` with
  n = 0 (all singers asleep after a time jump) killed it; guarded.

## Thin ice / plate fracture on a grid (s133, physics/ice.jl)
- A patch of plate that stands for a larger sheet needs its rim HELD (v = 0 on the 2-cell rim) and no loads near it:
  a free rim made a kink under any skater near it (47 MPa at 4 m/s) and shattered the whole sea.
- A local "stress > strength" test on a grid cascades: a crack tip is a singularity, the next cell always fails.
  Average the stress over the intact cells within ~2 cells first (nonlocal damage, Pijaudier-Cabot & Bazant 1987),
  and read no curvature across a cracked neighbour (a crack is a free edge).
- Cracked cells must keep some stiffness (15 %): at 2 % broken ice is slush, the load sinks it and the ring round it
  breaks, for ever. Test with several moving loads for 25 s, not one walk: one skater at 1.8 m/s hid all of this.
- live_reload() reloads only plugin files that changed: after editing a physics/ file a plugin includes, `touch` the plugin.
  The plugin re-includes physics/ice.jl when its mtime changed (ICE_MTIME), so struct changes need a fresh freeze.
- Explicit plate step: substep dt < dx² / (4 sqrt(D/m)); with the water's added mass ρ_w ℓ, 96x96 at dx 0.2 m is
  15-50 substeps per frame, 1-1.8 ms on CPU threads.

## Captions vs what the picture shows (s133, three redos in one session)
- The critic judges a film from a storyboard of ~16 stills: a rhythm faster than ~1 s (the firefly beat, 0.55 s) aliases
  and cannot be seen. Show change over time with something a still can read (lit area, a moving subject, a slow build).
- Write the caption AFTER looking at the contact sheet, and only claim what a stranger can point at in it. A cause
  ('when I flash my lantern') needs the cause in frame. If it is not there, post it as a take that misses, honestly.
- Glowing things must differ from the stars (warm colour, halo, light falling on the grass), and night means no sun shadows.
- s133 skipping stones take 1: the stone renders as a big pale square high in the sky (wrong scale or a stray plot?), Lumi stands on the hill behind a plank, rings are tiny and far. Posted as a crop (552x297 at (150,90)); full take media/s133-skipping-stones-take1-full.mp4. Take 2: low camera at the waterline beside the stone's path, check the stone plot first.


## Glowing faces and GPU memory (s134, shapes.jl `:glowdot`/`:glowball`, assets.jl `error_cause`)
- Both s133 films (thin ice, the owl) failed at the first frame with "Failed to resolve trace_renderobject" on a
  glowing meshscatter. The cause was cut out of the job json by `clip_error` (the edge inputs take kilobytes, the
  inner error sits in the middle). Repro in my session showed it: `LavaError during pool_alloc: Cannot allocate
  158793600 bytes ... 8.86 GB already reserved`, in Hikari `flush_face_area_lights!`.
- RayMakie makes every FACE of every Emission instance a DiffuseAreaLight. The island had 16 glowing meshscatters,
  most with `NG.shape(:sphere)` (1922 faces): nightglow flowers + halos 1.08 M each, rain 1.0 M, stars 0.8 M,
  glints 0.6 M, lamplight halos 0.27 M: 5 M area lights. The last plot added (meteors, s133) tipped it over.
- Fix: `NG.shape(:glowdot)` = unit_sphere(8), 98 faces, and `:glowball` = unit_sphere(12), 242 faces, in
  nightglow, showers, stars, shallows, lamplight, meteors, builder. Same shot traced clean after (04:15).
  `shape(name)` now re-inits when a name is missing (a running game got the new shapes through Revise).
- Failed jobs now keep `"cause"` (the innermost error, unwrapped through `.error` fields) and the whole text in
  `jobs/<id>.error.txt` (`"error_file"`). Read those first.
- Rule: a new glowing plot gets :glowdot unless it is big on screen. Count with the live_eval loop over
  `game.stage.scene.plots` (Emission material, `length(a[1][]) * length(faces(a.marker[]))`).
- s134: a scratch game (films, stills) does not have every plot of the live game: plugins/obscura.jl skips its hut when
  `game.dash === nothing`. Check a building exists in the scratch game before aiming a film at it.

## Grabs in PrintSim (s135, physics/climbgrab.jl)
- Lumi as a PrintSim compound affine body (torso box + claw pad, `add_body!(dev, b, [(; mesh, density, static, kinetic), ...]; mass, velocity)`),
  static lips via `add_mesh!`. Template: dev/PrintSim/test/bodies.jl `body_on_slope`. Device: `Mantle.Device()`.
- Cost: ~36 ms per step for 3-4 meshes at dt 1e-3 (0.8 s simulated = 29 s), first call 55 s compile. Not live yet.
- dt 2e-3 TUNNELS: the claw ended under the wall block (z = -0.015). Use 1e-3 until contact stiffness is tuned.
- A SHARP edge always holds (every slope 0-50 deg at mu 0.6): the claw pad hooks the corner, where the contact normal
  can point any way. Only a rounded lip (a beam with a smooth normal) can test friction. Tipping a whole block to
  make a 'sloped lip' also leans its face back, so the body lies on it: tip only a top slab.
- s136: CHECK ROTATION FIRST. In every grab trial the bodies' A stayed the identity to 3 decimals (a torso
  hanging 17 cm off its claw never swung): log world positions of body corners before trusting a hold. My
  s136 tip test (tilted box) read 0 deg tilt from frame 1 and sank into the ground, so I may misread body_pose[2]
  or build tilted bodies wrongly: start from dev/PrintSim/test/bodies.jl, unchanged.
- When a PrintSim result stays the same to 3 decimals while I change the geometry around it, the thing I changed is
  not in contact: find what IS (log contact forces per mesh) before tuning more geometry (s135 lost 4 runs that way).
- Markers in a still (s135, 3 redos of the ledge still): warm, evenly spaced glow dots read as string lights on a
  house. Cool cyan (0.25, 0.95, 1.0), size 0.03, reads as a marker. Camera lift 1.3 m sees over foreground flowers;
  stand Lumi 1.5 m beside the subject, facing it (movies/climbedges.jl knobs back/camside/lift/lumiside/lumi_faces_wall).

## Boomerang flight (s136, physics/boomerang.jl)
- Blade elements: per element air speed = v + w x r - wind, drop the span part, alpha from the cambered face; CL = pi sin 2a
  + 0.4 cos a (camber only with the leading edge first), CD = 0.04 + 1.6 sin^2 a. 22 m/s, 120 rad/s, 15 deg layover,
  80 g, arms 0.25 m: a 19 m loop back to the hand in 4.4 s. Spin 60 rad/s: precesses too fast, falls in 1 s.
- A summary number can lie about a path: "farthest point, then closest after it" picked the SECOND loop in a wind and
  called good throws misses (I almost blamed the physics). Print the path or bound the window to the first loop.
- A Galilean check catches wind bugs: in uniform wind the loop must be the calm loop drifted by wind x time.
- KA kernel launch on the CPU backend ~0.6 ms per call: for 32 elements a plain loop is ~100x faster (live uses it).

## Ants: stigmergy and cooperative transport (s137, physics/ants.jl, projects/ant-road.md)
- Three antennae sensors (l/c/r at 4 cm, +-0.55 rad), turn 0.35 rad to the strongest, noise 0.35 rad per 0.05 s step.
  Out: follow `food` + `honey`, lay `home`; carrying: follow `home` + 12 % pull to the nest per step (path integration), lay `food`.
  Blur 0.08 per step with keep 0.996 (food) / 0.995 (home). With these the ants wear a STRAIGHT trail under a curved
  honey loop within ~40 s (the shortcut is emergent: carriers' path-integration pull lays food scent on the chord).
- Biscuit pull needs ~15+ aligned ants above Coulomb friction (mu 0.2, 30 g, 5 mN each). 300 ants at 0.10 m/s never
  moved it; 500 at 0.15 m/s moved it 0.39 m between 40 and 70 s, then it stalled as pullers let go. It never turned.
- Film spot search: props AND ponds. `areas.jl` POND (-5.5, 10.5) r 2.3 is not a prop and `ground()` gives its floor:
  my first open-patch search put the ants on the lily pond. (4, -14) is open grass with 0.31 m of slope.
- A sim stepped inside a film's `shot` must use the same parameters as the tuned trial: the first preview used the
  struct's old defaults and the biscuit never moved. Put tuned values INTO the defaults.

## Dayfall tiles and cameras (s137, plugins/dayfall.jl)
- The line behind a walking player is exactly where the follow camera sits: tiles now only in Jump in, and each grows
  out of the ground once Lumi is 3.5-5 m past it (`DF[:grown]`, markersize z). The first tile used to stand in Lumi's
  legs (laid at `xy` when the line was empty): it now waits at `DF[:start]` until Lumi walks 0.85 m off.
- (s137 post critic) A time-lapse that starts after the warm-up shows a finished trail: "wear" claims nothing it can see.
  Start a film where the change begins (warm < first ants on the honey, ~25 s), keep both ends of a route in frame,
  freeze every friend for the whole shot (`controlled = true`), and hide autumn leaves near a close-up camera.

## Piranesi view (s138, free time; "La Connocchia" on the workbench), not finished
- movies/piranesi.jl `piranesi_still` (raster, portrait 720x1080, low fixed eye, friends moved to the foot): 1 min warm, 3.5 min cold.
- The island has no tall thing to look up at: trees are ~4 m, crowded by a stone lantern and fences (-10,17). Raster 1-3 in media/s138-piranesi-raster*.png.
- Raster 3 (eye 6 cm over grass at (4,-14)) is an ant's view: grass blades against a big sky, but the three moved friends did not show (not checked why).
- Traced still of raster 3 queued as pending post 'An ant's-eye view, a try that misses' (piranesi_png, job 20261127-073719-969-clip). Next if I come back: check where the friends ended up (print c.pos after setup), then etch it with tools/etch.jl.

## Modal sound: knock on anything (s138, project knock-anything)
- physics/modes.jl: voxelize an asset (shell cells from its VERTICES + flood fill of the outside from the border;
  ray-crossing parity filled 27 of 1296 cells on the generated lantern: its meshes have open seams), FinEtools
  `H8voximg(img, [h,h,h], [1])` -> hex mesh, `FEMMDeforLinear` + `MatDeforElastIso(DeforModelRed3D, rho, E, nu, 0)`.
- FinEtools (2026) `stiffness`/`mass` return ALL dofs: take `[1:nfreedofs(u), 1:nfreedofs(u)]` before `eigs`, or
  `scattersysvec!` fails with "Vector needs to be of length equal to <nfree>".
- `eigs(Symmetric(K), Symmetric(M); nev, which = :LM, sigma = 0.0)` with the base fixed: 0.6 s for 713 voxels.
- Frequencies scale as 1/size: the lantern at 1 m rings 210/258/442 Hz, at 1.6 m 131/161/276 Hz.
- `Pkg.add` of FinEtools in the game env printed "377 dependencies precompiled but different versions are currently
  loaded": that is the session's loaded copies vs the fresh caches, check the game still starts after such an add.
- A film with sound: game_clip writes silent mp4; mux the wav after it inside the clip function (movies/knock.jl),
  and leave `muted` off the post's <video>.
- Checked against beams (s139, free time): a clamped 0.1x0.1x1 m bar, E 30 GPa, rho 2500, at 4 voxels across rings
  56.6 Hz, at 8 across 56.0; Euler-Bernoulli 56.0. A hollow square tube (0.2 m, walls 2 voxels) 131 Hz vs E-B 140:
  low, as a stubby tube (L/b 5) should be from shear. Hex8 at 2 voxels through a wall does NOT lock: trust it.
- Hollow things (s139): `voxelize(...; wall = k)` / `Modes.solve(mesh; wall = k)` keep only cells within k face
  steps of the outside (`Modes.hollow!`). `Modes.solve_voxels(img, h; fixed = false)` for things that LIE on the
  ground (a pumpkin): the first 6 modes are then rigid (~0 Hz), elastic ones start at index 7; `sigma = -1` shift.
- A ribbed pumpkin R 0.34 m, E 6 MPa, rho 800 (flesh, a guess): solid 53.5/66.5 Hz in 352 s (24k voxels, 80k dofs:
  the factorisation explodes), hollow with 3.4 cm walls 17.7/25.8 Hz in 3 s (6.6k voxels). Hollow = 3x lower and
  100x faster. Notes go as sqrt(E): the real rind is stiffer than the flesh, E is the unknown, not the shape.
- The refactor (s139) gives the lantern exactly its old notes at n 16 (210.3/257.5/441.9 Hz at 1 m); at n 18 they
  are 204/256/424: 2-4 % from the voxel size. Loading an asset's mesh.jls in my session needs `using Makie` first
  (ColorTypes KeyError otherwise); the file is a MetaMesh, `Modes.solve` takes it as is.
- Chip stone live (s139, plugins/chipstone.jl): the stone's surface is FinEtools' own `meshboundary(fes)` of the
  solved hex mesh (`connasarray` -> quads -> 2 tris), smoothed 3x; FE nodes = mesh vertices. The FIRST FinEtools
  solve in a game process took 13.3 s inside one frame (compiling): every solve, the first too, goes on
  `Threads.@spawn` (the sandbox has 8 threads) and the step polls `istaskdone` + `fetch` (fetch rethrows).
- A stand-in mesh WITHOUT normals as the plot's first value, then an update to a mesh WITH normals: the step stopped
  right at `obs[] = mesh` and the plugin's `error` stayed "" (the failure went somewhere I did not find). Make the
  plot when the real mesh exists, or give the stand-in the same attributes.
- Pressing keys in the sandbox from my session: `live_eval` runs INSIDE the game loop, so push the key in one
  live_eval and delete it in the next (`push!(game.keys_down, Makie.Keyboard.r)`, sleep 0.4 s, `delete!`). Both in one
  eval = the plugin never sees it. `skip_to_hour!` takes `game.world`, not `game`.
- Critic on the first chip film (s139, redo): chips burst off the stone with NOTHING touching it, no knock is
  visible, the dent is a soft shadow, the flakes sprayed past Lumi's knees, and the caption said 'beach' on grass.
  Lesson: a film of an action shows what does it (here a pebble falling 20 cm onto the middle at every chip and
  knock), debris in proportion (1 in 6 cells, 0.2 m/s sideways), and the caption names only what is in frame.
  Lumi is ~10x the stone's size: a close stone shot shows only Lumi's toes; a toy this small needs a bigger stone or a
  shot built for Lumi's beak.

## Snow on things (s140, free time)
- After W. L. Jacobs' snowed-in watercolor (Cleveland 1917.275): physics/snow.jl. Voxelize (Modes.voxelize, n 64),
  snow falls D voxels onto each column's topmost solid cell, then a sandpile relax at 55 deg (8 neighbours): the
  lantern settles in 321 sweeps, 0.4 s. The roof shelters the light box and the middle step with no rule for it;
  what slides off the base banks up in a ring. Still: media/s140-snowlantern.png (spiky first try: -spiky.png).
- Drawing it: a `surface!` with NaN where there is no snow draws walls and spikes down to the ground; build triangles
  per grid square instead, kept only if the 4 corners are within 4.5 voxels (2 punches holes in real 55 deg slopes),
  after 3 passes of same-shelf smoothing (neighbours within 3 voxels). GLMakie headless works in my session
  (`GLMakie.activate!(visible = false)`, warnings about DISPLAY are harmless). The env is the game ROOT, not world/:
  bt_julia_eval with env_path world/ spent 3 min compiling Makie and then had no GeometryBasics.
- Missing: cohesion. Jacobs' caps bulge over the fence and door edges; grains stop short of the roof rim. Next:
  let snow cantilever a few cells past an edge (a cornice), then snow on the whole island in a winter morning.

## Snowball (s140, project snowball)
- physics/snowball.jl: the ball takes ALL the snow in its footprint (spherical cap of a d-deep layer: rho^2 < 2rd - d^2),
  mass conserved; packed 450 kg/m3 vs fresh 150. Rolling: 7/5 m, picked-up mass at rest shares momentum, Bekker
  sinkage (Wong, US snow n 1.6, kc 4.37e3, kphi 196.72e3) gives the compaction resistance.
- Bug I made first: reading the snow depth at the ball's centre, where it has just peeled it (sinkage 0, no snow
  resistance at all). Read the snow it rolls INTO: one radius plus a cell ahead.
- Finding a film spot: copy the sandbox's ground heights to my session (live_eval writes a binary file under
  world/media; the sandbox's /tmp is not my /tmp, and live_eval returns are cut at ~3.5k numbers), run the roll from
  every start and direction, keep runs that stay > r + 0.9 m from every prop (flowers and toadstools too: the
  first raster rolled through a toadstool ring). (14,-6) east: 7 m, 0.13 -> 0.31 m, into the sea.
- A raster test of a clip script (`rasterize = true`) takes ~1.5 min in the worker: always before the traced one.
- Snowball take 1 (s140) MISSED for the SAME reason as s129's echo film: a fixed camera behind a prop (a brown slab
  filled 40 % of the frame). MEMORY says it; I skipped it when time was short. Rule now: a fixed-camera clip script
  checks its own eye in `setup` (any prop within 2 m of the eye or of the eye-target segment -> @warn with its kind
  and position) and the raster test of the FINAL camera runs before every traced job, never only of an earlier one.

## Glaze in the kiln (s141, free part)
physics/glaze.jl: molten glaze as a thin film (lubrication eq., surface tension + gravity, explicit dt 5 ms at 0.5 mm grid)
on a grooved body, coloured by thickness (Beer-Lambert there and back). From the museum's 13th-c. celadon wine pot.
What came out unasked: grooves fill (0.35 -> 0.62 mm, darker), a raised cordon breaks to 0.09 mm (body shows),
a pale halo beside every groove (glaze drawn in), the top drains. Colour lesson: strong bubble scattering makes THICK
glaze LIGHTER (lines turned pale, wrong); real celadon lines are darker = clear glaze, absorption > scattering, and
olive = blue eaten most. Mine is too even: the real pot is mottled (uneven dipping, bubbles). Pictures:
media/s141-celadon-pair2.png (museum left, mine right), -pot.png (too green), -pot2.png (too milky).
Could become: the friends' pottery, a kiln night, a jug you glaze and fire yourself.
- s141 later: physics/jug.jl (cut jug + mesh, `coarsen` for the game), plugins/kiln.jl (jug at (4,-16.5), fired on a thread at
  start, published). GPU: `Glaze.fire_ka!(h, b, Mantle.Device())` = 2 KA launches per step (fluxes with the curvature computed
  inline, radius-2 stencil, then the update): 12000 steps on 700x290 in 1.3 s vs 18.5 s on CPU threads, same to 5e-5 mm.
  So Mantle dispatch is NOT 1 ms per launch for small KA kernels (24000 launches in 1.3 s = 54 us each); PrintSim's slowness is its own.
- Raster preview of a 14 cm jug: a low camera (eye 17 cm up) puts the grass clumps behind it in half the frame; look down (30 cm up) onto sand.
- Captions vs film, again (s141 first-jug, redo): the caption told the process (cut, dip, fire, glaze flowed) and the film
  showed only the finished jug. A film of a RESULT gets a caption of what the result looks like; a process needs the
  process on screen (the kiln opening, the cut). Also: check the LAST third of an orbit for leaves swinging in.
- `game_clip(...; fade = 0.3)` makes the first 0.3 s dark (the critic called it a light jump, s141): trim 0.4 s or pass fade = 0.
  A round pot without handle or spout is a JAR, not a jug (critic s141): the wheel must add a handle before I call it a jug.

## s142 lessons (glass)
- A held viscous membrane (pressure + gravity, some vertices fixed) RUNS AWAY within tens of ms without bending
  stiffness: the free sphere was fine, the held gather was not. A dashpot on each hinge's dihedral angle rate
  (D = eta h^3 / 3) fixed it. Check the hinge gradients' orientation: both triangles' normals outward.
- Viscous bubble inflation is a finite-time blow-up (dR/dt ~ R^4): at 1100 C / 3 kPa a 3 cm gather bursts in 50 ms.
  Real glass parameters: 1000 C, 8 mm walls, ~600 Pa sustained, and cooling (thin walls first) stops it.
- Equibiaxial extensional viscosity is 6 eta, so a thin viscous sphere grows dR/dt = p R^2 / (12 eta h), not /(4 eta h).
- RayMakie raster cannot take FaceView normals: `normal_mesh(Cylinder(...))` must go through
  `GeometryBasics.expand_faceviews`. Plot `name`s must be unique in a scene (two band meshes both `:glassblow` failed
  the job in 80 s). A raster film with seconds = 1.5 catches both before the worker does.
- The host deletes a pending post whose job failed: write it again with the new job id.

## s143 lessons (glow)
- Per-vertex EMISSION needs no new Hikari node: give `mesh!` a vertex colour vector and `material = Hikari.Add(Glass(), Emission(strength = s))`;
  RayMakie merges it into the Emission as a VertexColorTexture, smoothly interpolated (in an Add it is found by paths, not sampled as a light).
- Hot things glow by Planck: relative to 1000 C, red radiance is 0.21 at 900 C, 0.03 at 800 C, 0.003 at 700 C. Below ~800 C glass in daylight is
  just clear glass. `gb_glow(T)` in movies/glassblow.jl.
- Tippe top (s143, physics/top.jl): it inverts by sliding friction only if (1) the centre is well below the ball's centre
  (a solid ball cut flat gave alpha 0.06 and never flipped: hollow the upper half, `tippe_hollow`), (2) 1 - alpha < I1/I3 < 1 + alpha,
  (3) the stem ends in a half ball, and (4) the spin is hard enough: 180 rad/s rolled it onto its rim at ~120 deg and it stalled,
  300 rad/s stood it on its stem (tilt ~170, centre 22 -> 35 mm). Air drag torque on a 2 cm top is ~1e-10 w^2, not 1e-6 (that killed the spin in 0.5 s).
- Penalty contact at the moving lowest point of a surface of revolution: height of ring s = x_z + s a_z - r sqrt(1 - a_z^2), take the min.
- A plugin that keeps a struct instance in Main.<DICT> across reloads breaks on the next reload (the struct is a NEW type in
  the new module: MethodError, the system is switched off; it stays off until the file changes again AND the bad state is
  cleared). Keep only plain data there (arrays, numbers), rebuild typed things. Same lesson as fireflysync (s131), third time.
- Scale a top (or any contact toy) to the camera, not to real life: a 4 cm top is ~5 px in the follow camera. Physics scales
  with omega sqrt(R/g) (same flip at 8 cm with half the spin), contact stiffness with m/R.
- s143 glass post took 4 redos: a still rendered in my own session has NO OIDN (grain everywhere) and RayMakie's default
  background is blown-out white. Stills for posts go through the worker (`trace` job / post_still) or not at all. A glow
  that lights things needs a real light (PointLight at the gather); Emission inside Add lights nothing. A tool in a picture
  needs a holder (Lumi) or the critic calls it floating, every time.
- s144 wirebench: a plugin that keeps state in a `Main.X` dict across reloads and returns early from its ensure!
  when its plots exist will crash after a reload that adds a new key (the system is switched off silently; the plugin
  still says "ok", only `live_status()["systems"]` shows it gone). Keep a `X_VERSION` const, rebuild when it differs,
  and after every reload check the system list, not just the plugin status.
- s144 tops film, third miss: a simulation floor that is an endless plane under a small prop board lets the body drift
  past the board's edge and hover over the lower grass on film. Bound the contact to the prop (or make the prop
  bigger than the drift), and frame the camera on the thing the caption is about, not on the start positions.

## Metals read dark when they are perfect mirrors (s145)
`Hikari.Copper()`, `Gold()`, `Silver()`, `Aluminum()` default to roughness 0: a mirror. A thin tube of it only mirrors
what is round it, so s144's copper wire on a brown board came out a dark brown line. Give thin metal roughness ~0.15-0.25
(the sun's highlight spreads into a bright stripe) and a ground of another hue (cool slate under copper). And aim the
camera at the thing's own bounding box, not the board's centre (the hook sat 4 cm off the target, 23 cm away).
- A plugin that keeps its plots in a global Dict across reloads (wirebench's `WB`, built by `wb_ensure!`) does NOT
  redraw when you only change colours or materials in the file: bump its version constant (WB_VERSION) or the
  sandbox keeps showing the old look while the file says otherwise (s145: the slate board stayed brown for 8 min).
- Film scripts run in `Main.ClipScript` without Colors' exports: `red(c)` is undefined there (s145 logs film failed in
  setup). Use the fields `c.r, c.g, c.b`. A job that dies in setup fails within ~1 minute; check it before walking away.
- Film a rotation along its axis (s146): three logs rolling about their long axis, filmed side-on, looked like three
  still boards (s145 three-logs film). End-on, the same roll reads in one frame. Before a traced job, ask: from this
  eye, does the thing that changes change the silhouette? Also: fast events (a plank falling over in 0.8 s) need a hold
  before release, or they happen inside the fade-in.
- Plugin + physics file out of step (s146): the wire bench crashed in the human's game with `wire_tube(...; cut)` not
  found: the published plugin used a keyword the game's already-loaded physics/wire.jl did not have yet. It ran again
  after the game restarted. When a plugin starts using something new from physics/*.jl, check the human's game after
  publish (`live_status(game = :live)["plugins"]`) and look for the error in ../.jail/logs/game.log.

## s147 lessons (free part)
- "the worker stopped twice while running it" can mean the job FINISHED and the worker died writing it: a NaN in the
  clip's result (homopolar `off_t` of wires that never fly off) made JSON.json throw in run_worker's job write. The
  film was whole. Look at the worker log FIRST: /sim/Programmieren/SimGame/.jail/logs/worker.log (grep '==== \|^ERROR').
  Fixed in NeverendingGame paths.jl: write_json writes NaN/Inf as null (`json_safe`, only rebuilds values that have one).
  The worker runs the new code after its next restart.
- A finished film whose job failed: set the job's status to done by hand (with a note in its result), then write the
  pending post again from pending/failed/; the host put it up within 10 s.
- Square log, wood decides (projects/log-boat.md): flat below relative density 0.21 and above 0.79, on its corner
  0.28-0.72, leaning in between (0.25 and 0.75: 26.5 deg). hull.jl reproduces the textbook result unchanged.
- Paper glider (s147, physics/glider.jl, todo #693): a quasi-steady vortex lattice in a rigid-body loop GAINED energy
  while the glider pitched (same at two dt: a physics bug, not the integrator). Cause: Kutta-Joukowski with the OTHER
  vortices' induced velocity at each bound leg tilted lift forward (steady thrust at 8 deg). Fix: force from the CG's
  free air only (induced = false); induced drag must then come separately. Test that found it: hold the wing steady
  at a few angles of attack and print F.v: it must be negative. Before filming any flight, print the
  total energy (g z + v^2/2) over the flight: it must only fall. Paper gliders are stiff (inertia ~3e-5 kg m^2 under
  aero moments): big elevon bends blew up at dt 1e-4.
- NG.todo!(...; kind = :feature) wants a Symbol for kind (a String throws a convert MethodError).

## Magnet fields from any mesh (s147, physics/em.jl)
- Charge model: sigma = M.n on every face, quadrature points per sub-triangle; H = sum q d/(4 pi r^3); F on magnet = mu0 q H.
  Valid outside the material and more than one quadrature cell from a surface (2 mm off a disc face read 4% low at n=8).
- Testing against a dipole: a 32-gon disc has 0.64% less area than the circle, so its moment is low too; two of them
  read 1.3% under the dipole force for that alone. Compare with the polygon's own moment.
- It allocates heavily (collect per point, 28 GiB for the self test): fine for checks, write the Mantle kernel before live use.

## Published plugins need their physics/ in world/live (s147)
- A plugin published to world/live/plugins that includes `joinpath(@__DIR__, "..", "physics", f)` loads fine at publish
  (publish! loads it from world/plugins) and FAILS after the human's game restarts (world/live/physics was missing).
  That is why tops, wire bench, kiln, chip stone, boomerang, glass sea, owl ears and firefly sync were 'does not load'.
  publish! now copies world/physics to world/live/physics first (publish_physics!) and retries the plugins that had errors.
  Check after any publish: `live_status(game = :live)["plugins"]` has only "ok".
- Never put a new function between an existing docstring and its function: Revise says 'cannot document' and DROPS the
  documented function in every running game (publish! vanished from the human's game for a minute). Insert above the docstring.
- Point-charge fields (em.jl quadrature) pulling a light body: (1) smear each charge over its cell (r^2 + eps^2, eps = half
  the cell), (2) step so the body moves at most a few mm per step. Without both a spike passed through the magnet
  between two steps, kept the near field's energy and flew 25 m (s147, caught by tests/magnetstone.jl).
- Film framing that worked (s147 darts retake): one shot per subject, camera ~1.7 m to the side, trailing the subject's
  path with an exponential follow (x tau 0.18 s, z tau 0.06 s); check the subject's angle from the view axis over the
  whole computed path before rendering (half vfov 22.5 deg, half hfov ~36 deg at 16:9).

## s148 lessons
- A film script that writes a plugin's state must write the plugin's TYPES: movies/compass.jl set MS[:psi] = pi
  (Irrational) and switched off magnetstone AND compassbowl in the sandbox (`::Float64` asserts). Float64(pi).
- Field functions passed into a solver: a NAMED function. An anonymous global closure made SoftIron.solve! 23x slower.
- Charges near a face: a softened point gives ~0 field right in front of it, a real face its strongest (sigma/2).
  Anything that touches (chains, joints) needs the face as a disc (physics/softiron.jl `hface`, 7-point rule).
- Levitron (physics/levitron.jl): the vertically STABLE balance is where the gradient weakens with height; the
  other zero of the force (lower) is unstable. Start a float at the stable height, never lift it off from below.
- Scale: magnetic push ~ size^2, weight ~ size^3. A magnet toy scaled up for the follow camera stops working;
  pick a stronger material or a closer camera, never a typed force.
- plugins/feelings.jl fell back to "content" for any feeling it did not know: "annoyed" showed as content for
  sessions. When the host names a new feeling, give it a MOOD value, stances and lines.
- Jump in hooks (s148, plugins/greetings.jl): `Main.LOCAL_KEYS[name] = game -> "line" or nothing` puts a toy's keys on
  the card while Lumi is near (in place of the 20 letters); `Main.LOCAL_CAMS[name] = game -> (eye, target) or nothing`
  claims Jump in's camera (a plugin setting game.rig itself loses to greetings' chase camera when greetings runs later,
  i.e. whenever greetings was reloaded after it). Used by tops (keys), wirebench and floattop (keys + close view).
- Dashboard "Things to try" shows a mini game's description only up to its first comma or semicolon (play.jl).
- A plugin whose state lives in Main (MS = Main.MAGSTONE) and holds structs of its own type breaks on a reload in the
  worker: the new module's `Spike` is another type. Check `x isa Vector{Spike}` in the ensure function and rebuild
  (s148: the compass film had no stone and no spikes; tops.jl does the same with TopShape).
- Holding a post: never wrap it in an HTML comment at the top of site/index.html. The host puts new posts before the
  first piece, inside the comment, and the closer then shows the held film (s148). Move the piece out (media/held-posts/).

## Looking at a film's shot in the sandbox before the worker renders it (s149)
- `NG.live_eval` code runs in module `Main.Live`: no `Makie`/`GeometryBasics` names there, and `Main.X = ...` fails
  (no new globals). Get the engine with `parentmodule(typeof(game))`. To run a movies/ script's setup and shot in the
  sandbox, eval a small module (`module ISFilm; using Makie; const GeometryBasics = Makie.GeometryBasics; using
  Makie.GeometryBasics: Cylinder; const NG = <engine>; end`), `Base.include(Main.ISFilm, script)`, and split the film
  into `xxx_parts(; ...) -> (setup, shot)` so `invokelatest(setup, game); invokelatest(shot, game, game.rig, t)` then
  `live_screenshot` shows the exact frame. Delete the test plots by name before the next try. (movies/ironsand.jl)
- Pressing a key from outside: `push!(game.keys_down, Keyboard._9)`, sleep 0.15 s, `delete!` (two live_evals).
  `start_minigame!(game, JumpIn)` / `stop_minigame!(game)`.
- Lumi is about a metre tall: a toy camera (Main.LOCAL_CAMS) put behind Lumi under ~1.5 m ends up inside its head.
  For a small toy look from the far side of it, high (eye 1.5 m up, 0.75 m beyond the toy).
- meshscatter updates: `Makie.update!(plot; arg1 = positions, rotation = quaternions)`; `plot[1][] = ...` throws an
  UndefRefError in the compute pipeline.
- s149: the floating-top film (s148) filmed the tops board's big striped top instead of the floating top: an edit had
  put a `# comment` in the middle of the shot's hide line, so `&& (p.visible[] = false)` sat inside the comment and
  nothing was hidden. Second film in two sessions to miss its subject: run every new film's shot in the sandbox first
  (xxx_parts, above) and look at the screenshot before queuing it.
- s149 critic, three magnet films redone at once: a carried thing that does not TOUCH its carrier reads as moving by
  itself (the magnet stone floats 3 cm up in front of Lumi). The cause must be in the frame: Lumi's head and the hold,
  not cropped legs. Dark hour + black stone on dark grass = nothing to see. Before queuing: sandbox shot of the
  middle frame, and ask "can a stranger point at who does it, and how?"
- s149: the worker loads a film script into its own module (Main.ClipScript), NOT Main: the script must start with
  `using NeverendingGame, GeometryBasics, Makie, LinearAlgebra; const NG = NeverendingGame` and include its physics
  with `Base.include(@__MODULE__, ...)` (iron-sand film failed on `NG` undefined). Test: `m = Module(); Base.include(m, script)`.

## Holding things in the beak (s150, todo #716)
- `NG.beak_tips(w, c) -> (upper, lower)` (bird.jl): the world tips of the upper beak (frontmost vertex of the
  body shape) and of the jaw (part `:beak`), posed exactly as the herd draws it (drawn yaw, action, phase, jaw).
  Typed args broke the package load (bird.jl is included before World/Creature): keep it untyped.
- Lumi's beak is HOOKED: idle, body frame, the upper tip is at x 0.53 z 1.25, the short jaw ends at x 0.33 z 1.28
  (jaw pivot x 0.24 z 1.27). Something held sits under the hook, just ahead of the jaw tip.
- The catch for the magnet stone: the beak is 1.25 m up; the stone's pull on a spike is 8.7x its weight at 15 cm,
  0.1x at 25. Carried in the beak it moves nothing on the sand. Two honest ways: a deep stoop (pitch ~1.6 rad
  about the hips puts the beak ~0.25 m up: a 90 degree bow), or the stone on a cord from the beak, a real
  pendulum the field pulls sideways towards iron (spikes leap up and hang on it). The cord is the better film.
- (s150) An electromagnet barely reaches (physics/coilcrane.jl): 300 turns x 3 A on a 5 cm nail lift the nail under
  the core at 3.25x weight from 4.5 mm, 0.32x from 12 mm; at Lumi scale (20 cm core, 1500 turns, 3 A) 9.3x from 15 mm
  and nothing 3 cm aside. A flat nail under a vertical field feels almost nothing (rods magnetise along their axis):
  the crane must go INTO the heap. Biot-Savart check: 400 turns over 0.2 m -> 1996 A/m at the centre (2000 ideal).
  For speed the film lumps the N turns into 60 loops of N/60 turns each (fine a few mm from the winding).
- (s150) `:eat` lowers Lumi's beak 23 cm and pushes it 34 cm forward (idle beak 1.21 m up, 0.54 forward):
  the cheapest way to dip something held. beak_tips poses the TARGET action; the herd blends 0.22 s (POSE_BLEND):
  blend the two beak points yourself (movies/crane.jl beakpoint).

## Plugin state across reloads (s150, the human's wire bench was switched off)
- A plugin that keeps state in Main (Main.WIREBENCH) and includes a physics file into its own module gets a NEW
  struct type on every reload; the old object in Main matches no method (MethodError, switched off). Rebuild when
  `!(state[:x] isa CurrentType)` (wirebench.jl wb_ensure!, fireflysync.jl the same since s131). Check every plugin
  with Main state + Base.include of a struct file.
- `mesh!(scene, normal_mesh(Cylinder(...)))` fails in RayMakie's raster (FaceView normals -> vec3s MethodError);
  a meshscatter with that marker works. A stretched cylinder: unit marker, markersize Vec3f(1,1,len), rotation.
- Film eye on a slope: take its height from `NG.ground` UNDER THE EYE, not under the subject (the beach rises inland).

## The crane film came up empty (s151, movies/crane.jl, site/films/scrap-crane.mp4)
- Contact sheet: the coil dips into the heap and rises with NOTHING visible on it, though the job said held = 2.
  Caption changed to "...and it comes back up empty" (true to the film).
- Fault 1 (code reading): the touch test is core-axis to peg-axis < 2.05*CR_A = 12 mm, but the copper winding
  sits at R 14 mm + wire 2.8 mm. Pegs the field turns parallel to the core snap INSIDE the winding: held, hidden
  (only their ends poke out like the core's dark stubs). Real contact: along the wound part the peg's axis can't
  come nearer than R + rw + CR_A ~ 23 mm; only the core's bare 2 cm ends allow 12 mm. Pegs held there hang BELOW.
- Fault 2: pegs stepped only when within 0.35 m of the coil (`isempty(near) && return`), and nothing gives a peg
  gravity TORQUE about its resting end, so a peg the field stood up stays leaning in the air forever.
  Fix: step every peg every substep (field only for near ones), torque of weight about the lowest end, a floor.
- The sandbox replay of the shot (live_eval, loop over t) does NOT reproduce the worker: `beak_tips` follows the
  drawn pose, and with no game frames between shots the beak never moves (coil stayed 0.9 m off the heap).
  To replay: let frames run (one live_eval per few frames) or compute the beak without the drawn pose.

## Putting tray (s151, physics/magnetgolf.jl, plugins/magnetgolf.jl, movies/magnetgolf.jl)
- Honest numbers first (projects/ironsand.md): a lodestone (Br 0.06) pulls a rolling iron ball sideways at most
  ~0.36 m/s^2 when 1 cm down, ~like a 2 degree dimple 15 cm wide; the same for any ball size (m = 3V H). So: a tray,
  slow putts (0.25..1 m/s), rolling resistance Crr 0.06. A 3 cm ball at 0.75 m/s passing 5 cm from a flush stone
  swings 9 cm across; at 0.6 m/s it is caught and stops on it.
- Cost: EM stone from cylinder_mesh(n=48) + quad 6 = 3456 charges, 2.7 ms per ballforce; sides 16 + quad 3 = 288
  charges, 0.16 ms, forces within 10%. Rolling in the game: ~1.7 ms a frame; iron-sand tap frames ~3 ms.
- To share stones between MagnetGolf and IronSand, include em.jl in the plugin FIRST: magnetgolf.jl imports the
  parent's EM when there is one (else two different EM.Magnet types).
- GeometryBasics: `normal_mesh(Sphere(...), 32)` has no method: `normal_mesh(Tessellation(Sphere(...), 32))`.
  Hikari.Conductor keywords are `ior` and `extinction` (not eta/k).
- The sandbox clock (`Libc.strftime`) is the real time; trust it over my guess (s151 I thought I had 13 minutes left
  and had 35).

## Films at noon come out dusky: the sun-ball (s152)
Every day from 12:00 to 13:30 (plugins/sunball.jl FROM_H/TO_H) the sun falls onto the meadow and `SUNBALL[:dim] = 0.1`;
showers.jl's `dim_sun!` takes the min of every dim into `NG.SUN_DIM`, so the whole island goes dusky. A film or still
with `hour` in 12.0-13.5 lands inside it: s151's putting retake (12.6) and the groove still came out dark, and the
compass film (13.0) was murky. Other daily windows: glass sea 7.0-7.5, glass rain 15.0-15.5, underlight from 19.0.
Use hour = 11.0 (sun ~64° high, nothing scheduled). Check a fresh game: `Main.SUNBALL[:dim]` is 0.1 right after load.
- THE HUMAN (s152): moving films to dodge it was a workaround; a sun that falls every noon is a script, not the world.
  The clock trigger is gone (sunball.jl starts only on SUNBALL[:force]). LESSON: when something looks wrong, fix its
  cause in the world; never film around it. Glass sea 7:00, glass rain 15:00, underlight 19:00 are timed scripts too.

## Fire (s152, physics/fire.jl, plugins/campfire.jl, movies/fire.jl, project fire)
- Model: FireBody = lumped heated skin (6 mm wood), moisture of the SKIN only boils first (the whole post's water held
  a stake at 100 C for 20 min), piloted ignition 350 C, burning flux G, char 0.65 mm/min, EN 1995-1-2 reduced section
  -> break -> `fall!` downwind. Flames of bodies < 0.3 m apart MERGE (four 20 kW log flames never lit anything; one
  82 kW flame does), heat-weighted top (the max put the pile's flame over a 1 m stake). Inside a flame: convection
  + flame radiation (eps 0.3) ~45 kW/m^2; with convection alone (10) nothing in the flame ever caught.
- Explicit step on a skin that burns away goes NaN: clamp T to [T_amb, T_flame + 100].
- Fire time on the island clock: 86400 / w.day_length = 4.8x (a stake catches ~22 real s after lighting).
- Finding a clear film spot: props are NOT enough (s152: a house a plugin draws stood round the camera). Search with
  the bounding boxes of every scene plot < 30 m wide too (live_eval snippet in the s152 journal); the clearest spot on
  the island is the south shore (-3.0, -16.0), only 1.4 m clear for fire + camera + Lumi.
- Worker clip scripts: `Base.include(@__MODULE__, path)`, never bare `include` (ClipScript has none; the job failed).
- Plugin state in a Main dict across reloads: a struct from an included physics file is a NEW type after each reload;
  check `x isa Vector{FireBody}` and rebuild (MethodError, the system switched itself off). And a Dict{Symbol,Any}
  can't take a Keyboard.Button key (use Symbol("key_", Int(k))).
- Burning rate = surface heat balance (Drysdale ch. 5): (own merged flame's eps(1-exp(-0.8 D)) sigma T_f^4 + 8 kW/m^2
  + other flames - char re-radiation at 500 C) / 1.8 MJ/kg; flame-out under 3 g/m^2s. A lone stake dies, a crib holds.
- Flame look (s153, physics/flamelook.jl, used by the film AND the plugin): s152's one-emission cylinders at strength 6
  traced as pale planks. Now tongues = curved tapered tubes in three meshes (root yellow 2.2, body orange 2.2, tips red
  1.3); reads as fire in the trace (media/s153/fire-look-test-overview.jpg). Tongue length = the model's L along
  base->centre: 2x base->centre drew a 2 m streak once a burning stake joined the pile's flame. Test a look with
  fire_clip at fps 1 (12 frames, ~6 min) before a full take.
- Flames as GAS (s153, physics/flamevolume.jl, movies/fire.jl gas=true): Hikari RGBGridMedium on a box mesh with
  `MediumInterface(NullMaterial(); inside = med)`; sigma_a = soot, Le = Planck(T) at 610/550/465 nm over B(550, 1400 K),
  Le_scale 1.5 reads right at 18:20 light. GIVE sigma_s_grid: a missing grid is 1/m everywhere (pbrt semantics) and
  the whole box went milky. Each film frame deletes the old box plot and adds a new one (~6 s/frame at 20 spp).
  Hikari also has NanoGridMedium(density; temperature) (Planck built in, NanoVDB trees) for bigger fires/smoke.
- Jump-in in a live_eval test: `start_minigame!(game, JumpIn)` moves Lumi to its start AFTER your placement; place
  Lumi in a second eval, and press keys only once `near` is true (a press while not near is used up).

## Electrostatics (s153, physics/estatic.jl, project lightning)
- BEM: flat panels, constant charge each, collocation at centroids, self term = disc of the panel's area
  (q / (2 pi eps0 r)), earthed plane z = 0 by mirror charges. Storm field E0 down: phi0 = E0 z, solve P q = V - phi0.
- Checked against Forbes' capped-rod enhancement within 10% (projects/lightning.md). Measure the field a couple of
  radii OFF the surface: on a panel centroid the field of the panel itself is singular.

## The motor (s154, physics/motor.jl, project motor)
- A motor needs no motor code: torque = sum I dl x B over one turn (x N) in em.jl's field, back-EMF = sum (v x B).dl
  along the same turn; check `coil_coupling(b, θ)`: the two come out equal and opposite (energy conservation, a free test).
- Tabulate the coupling over θ once per build (180 angles): a rigid rotor's field coupling depends only on θ; then
  spin() runs 10k steps/s of physics in ms. Rebuild the table when a part moves.
- Coulomb friction with a light rotor stops a flick in ~0.05 s: a beak flick needs ~40 rad/s at bench size.
- A wide commutator gap (20 deg) traps a heavy rotor INSIDE the gap (open circuit, no torque, coasting not enough):
  real commutators have narrow gaps for this reason. Start angle matters for weak motors (one cell: runs from 0.8 rad,
  stalls from pi/2); test cases from the same angle (pi/2) or the comparison lies.
- Film framing: a 0.2 m machine next to Lumi (1.1 m): camera low (0.2 m) and close (0.55 m) at 3/4 from the
  commutator end, Lumi 3.2 m behind on the same line; looking ALONG the stones' axis hides the rotor behind a stone.
- s154 LESSON: em.jl `force(Bf, path, I)` samples B at each segment's MIDPOINT only. A coil side drawn as ONE segment
  over a magnet's face samples the peak field and overestimates torque ~30%: always subdivide paths (rect_turn n = 10)
  and check the answer moves less than a few % when n doubles, BEFORE filming. The first motor film rendered on the
  coarse turn and had to be withdrawn.

## The circuit solver (s155 free time, physics/circuit.jl, big goal road step 1)
- Netlist rebuilt from geometry every solve: bare wires touch anywhere (segment-segment distance <= r1 + r2), wrapped
  ones only at their two ends, cell terminals within r_term; Holm constriction per contact (F pressing force, softer
  metal's hardness). Wire pieces between taps: rho(T) l / A per segment. Nodal analysis, cells as Norton, each loose
  piece its own reference. Heat: I^2 R per segment, Morgan natural convection + radiation (eps 0.5), conduction along
  the wire, heat through contact spots (exact pair relaxation: a 0.1 mm segment empties through a spot in ~2.5 ms),
  latent heat at the melting point (and back on freezing), ONE segment parts per substep (a uniform hot run would
  otherwise part everywhere at once: the ends' cooling reaches only ~6 mm into a 0.1 mm wire).
- `Circuit.selftest()`: Ohm and parallel exact; bare wire across the leads shorts (far loop 2.48 -> 0.27 A), wrapped
  does not; fusing current vs Preece: 0.25 mm 10.2 vs 10.0 A, 0.5 mm 26 vs 28, 1 mm 67 vs 80, 0.1 mm 3.3 vs 2.5 (30% high).
  Converged in ds (2 -> 1 mm) and dt (0.01 -> 0.0025).
- What it says for the cart: cells in SERIES don't buy current, each brings its resistance: 0.1 mm wire, 0.2 Ohm cells,
  6 -> 16 cells: 515 -> 814 C, never melts (the limit is one cell's short-circuit current). 3 Ohm brine cells: 24 C at
  any count. 8 cells of 0.05 Ohm: 9.3 A, glows at 0.08 s, parts at one spot in the middle at 0.56 s, current stops.
  So the brine cell (step 2) must be about plate area and spacing, and parallel banks.
- Not yet: motor.jl still has its own loop (should become a Net: ring segments = arc wires, brushes = short wires, the
  coil = a wrapped wire), inductance and motional EMF as elements, iron's rho(T) is linear (runs low above 800 K), taps at
  the same spot are joined by a 1e-9 Ohm piece (leaves ~1e-6 A noise in an open loop: merge them instead), glow colour.

## Drawn wire (s155, physics/draw.jl, projects/drawn-wire.md)
- Sachs + Ludwik + Archard per pass; a rush necks at the die exit (Considere), `give` = how much load the hand lets go.
- circuit.jl Wire.r is now a VECTOR (one radius per segment; a number still works in the constructor). area(w, i).
- Test lesson: put the flaw AWAY from where a uniform wire would fail anyway (the middle), or the test proves nothing.
- SECOND TIME (s155 drawnwire after the s154 rod film): two plots with the same `name` kill a film. Every mesh! in a
  loop gets Symbol(prefix, k). And ALWAYS run a rasterize=true game_clip check of one frame before trusting a queued job.
- Filming thin things: s155 wrote "the rig has NO zoom" and filmed from 2 cm away: WRONG. The camera has a zoom:
  `Makie.cameracontrols(gm.stage.scene).fov[] = deg` in a clip's `shot` (vertical fov, default 45; RayMakie lifts on
  cc.fov, and also on cc.lens_radius / cc.focal_distance = depth of field). s156: eye 32 cm off, fov 28 -> 5 deg with a
  smoothstep = one continuous zoom from slab + posts to the neck (raster check media/s156/dw-zoom-sheet.png). Check the
  spot for plant clumps first; (5.6,-13.0) by the tops board is open ground.
- Glow strength: Planck's colour at 1358 K is (1, 0.05, 0.001), deep orange. s155's strength 60 clipped every level
  above ~1100 K to one yellow (the neck looked no hotter); s156 uses 8 * sqrt(B600(T)/B600(1358)).
- No arc at the break: 8 clam cells give ~6 V, below the ~12 V a copper arc in air needs. What is real at the parting:
  the two ends ball up into glowing beads (surface tension) that cool. That, not a flash, is the honest break.
  Bead sizes (s156 estimate): half a parted 2.5 mm segment of 47 um wire = a sphere of r 0.13 mm (wire r 0.05: visible).
  Its heat leaves mostly BY CONDUCTION into the wire (~0.5 W over 1 mm at 200 K) not by radiation (~0.02 W), and it
  first freezes at 1358 K (latent heat 2.05e5 J/kg). So model it in circuit.jl as extra mass + latent heat on the end
  segment next to the parted one (the wire and bead cool together), not as a separate sphere with its own cooling.
- Thermal bow: physics/hotrod.jl (HotRod.Rod(l, r; bow), settle!(rod, T, parted; seconds)), XPBD, clamped ends.
  A PERFECTLY straight column never buckles in Gauss-Seidel: start it with a small crook (0.2 mm).
- Moving many plots per frame in a clip: s156's shot did translate!/rotate!/scale! on 360 plots (40 tubes + 320
  hidden glow tubes) every frame; the raster check in the agent session hung 20 min (11.9e9 allocations) and
  segfaulted. Move only what is visible, only when it moved (drawnwire.jl `placed`). Better still: one mesh per
  material whose geometry is rebuilt per frame. And a game_clip in the agent session competes with the worker's
  trace for the GPU: queue raster checks to the worker instead.
- Never let a job write into site/films: the mp4 is a 48-byte stub until it finishes (perfectionist s154 found one).

## The drum rotor: 3 coils, 3-segment ring (s157 free part, physics/motor.jl `Drum`, todo #743)
- `Motor.Drum` / `drum_bench` / `drum_right` / `drum_cases()`: n coils (drum winding, coils across the drum at 120 deg,
  each a bit longer so the ends cross), joined in a closed DELTA, junction k soldered to segment k. Per substep the
  coil network is solved implicitly (L matrix with mutuals from Neumann, coil R, motional EMF per coil, Kirchhoff at each
  segment and at the plus brush, cells Norton, minus brush ground). `stall_torque(st, d, θ)` = DC torque held still.
- Starts by itself ONLY if (a) brushes are WIDER than the slots (8 deg brush in a 10 deg gap: open circuit at 6 angles,
  min torque 0 -> it sticks) and (b) the ring is turned right on the axle: 6 deg slots, 12 deg brushes, ring turned
  30 deg: stall torque 0.35..0.43 mN m everywhere vs friction 0.30: RUNS from all 12 start angles (5.6-5.8 rev/s at 1.5 s).
  Ring at 0 deg: min 0.22 (sticks somewhere); at 110 deg: min -0.13 (stalls). Converged: 10 vs 20 pts per side 0.2%;
  kt + ke = 3e-16 (energy). Misbuilds: stones turned round -> backwards -5.65; narrow brushes -> stall; lodestone ->
  stall; ONE cell now runs (2.78 rev/s): the drum is a real motor, the 2-segment one never was.
- Margin at bench size is thin (0.35 vs 0.30). Next: the film-size drum (s = 3, like big_bench), then real materials.
- Film size (drum_right(s = 3, N = 80, rw = 0.35e-3, brush_F 0.06, big_bench's rotor mass/inertia, 6 cells)): STALLS
  from 0, 1, 2 rad: stall torque 4.28..5.35 mN m vs friction 5.18 (the 3 coils carry 3x the copper; the 9 mm axle in
  its bearing dominates friction). Real fixes are parts, not tuning: a thinner axle (r 2 mm), lower-resistance cells
  (6 brine cells = 18 Ohm: the cells limit the current, road step 2 = plate area), fewer heavier turns. Decide by
  which part the player would change, then check again with drum_cases-style starts at s = 3.
- FIXED (s157): `Motor.drum_film()` = the s = 3 drum on a 4 mm axle (r 2 mm): bearing friction 5.18 -> 2.66 mN m,
  stall torque >= 4.28 everywhere: runs from all 12 angles, 2.07 rev/s at 4 s (2.26 with 0.04 N brush springs).
  The axle was the part: in big_bench the 9 mm axle's bearing friction was half the whole budget.

## Wheels in sand (s157, physics/wheelsand.jl, cart road step)
- Wong-Reece rigid wheel: Bekker sigma under the arc (peak moved forward with slip), Janosi-Hanamoto shear, integrated
  for load (-> entry angle, sinkage), drawbar pull and torque. Soils from Wong Table 2.3 (dry sand, sandy loam, snow,
  clay). `towed(s, W, r, b)` finds the zero-torque slip; `cart_climb(...)` = roll + grade vs pullers (weight x tan phi x 0.8).
- Check: sinkage ~26% above Bekker's closed form z0 = [3W/((3-n)(kc + b kphi) sqrt(2r))]^(2/(2n+1)) (that form drops
  the shear and uses small angles); towed resistance ~45% above pure compaction (bulldozing by negative slip).
- Numbers: dry sand, r 0.2 m, 12 kg cart on 10 deg: 3 cm rim sinks 2.2 cm, 8 cm rim 1.2 cm; one 8 kg friend can't
  pull it (33 N vs 40-47 N), two can. A 35 kg cart (riders) on 15 deg needs 167-195 N: friends can't; the motor must.
- THE GAME'S CREATURES HAVE NO MASS (species.jl has none): give each a mass from its mesh volume x ~1000 kg/m^3
  before friends pull or ride anything.
- THIRD TIME (s157, motorlook.jl): inserted new functions right above `function motor_plots!`, i.e. BETWEEN its
  docstring and its function -> "cannot document the following expression" at plugin load; publish refused it and
  the sandbox silently dropped the system (live_reload said ok first). RULE: before inserting code, search upward
  for a closing `"""`; insert ABOVE the docstring. After live_reload check `live_status()["systems"]` has the system.
- Hikari node textures work for wood and iron in plugins: `NG.Hikari.TextureNodes` (wave bands + color_ramp + bump),
  motorlook.jl mo_wood (texture_coordinate().object for moving parts) / mo_iron. Check by day in a worker traced
  take: movies/drumlook.jl drum_look (s157 jobs -> media/s157/drum-look*.mp4).

## Feet on sand: one law for feet and wheels (s158, physics/wheelsand.jl `foot`, project cart)
- A foot = a flat plate a x b carrying its share of the weight, on the SAME soil constants as the wheels: Bekker
  sinkage (`plate_sinkage`), grip from Janosi-Hanamoto shear F = (A c + W tan phi)(1 - exp(-j/K)) (plate slid rigidly:
  every point sheared by j), plus Rankine passive pressure on the sunk back face (Kp = tan^2(45 + phi/2)), mobilised by
  the same shear curve. `foot_creep(s, W, a, b, F)`: how far it scrapes back holding F (Inf: slides). `lean(m, h, T)`:
  statics about the feet. Check: plate 10x10 cm at 10 kPa in dry sand sinks 10.3 mm.
- Numbers (dry sand, two 4x3 cm feet): 4 kg friend sinks 16 mm, holds 27 N; 8 kg: 30 mm, 52 N (ridge 7 N of it);
  15 kg: 53 mm, 95 N. At half its grip a foot has crept K ln 2 = 17 mm whatever its load. The old cart_climb rule
  (m g tan phi x 0.8) said 33 N for 8 kg: a guess, gone. Now ONE 8 kg friend pulls the 12 kg cart up 10 deg (52 vs
  40-47 N); two 4 kg friends 54 N; one 4 kg cannot (27 N).
- s158 stones (Motor.rough_stone / stator_shapes): smooth waves growing away from the dressed face made a flared POT
  that read exactly like the old can; the north paint over the end face brought back the red lid. Lumps need 3D
  directions (cosines along random unit vectors), an aspect and a lean; paint only a side band. Physics check after
  any stone change: one DrumState (2 s at n = 3) + stall_torque at 12 angles vs st.τfric (s158: 5.19-6.15 vs 2.66).
- s158 LESSON (cost half an hour): `live_reload()` reloads only PLUGIN files that changed, NOT the physics/*.jl they
  include. Edits to physics/motor.jl or motorlook.jl alone never reached the sandbox; it kept drawing my first
  stone. RayMakie was fine (a probe mesh under a new name showed the same old shape). After editing an included file:
  `touch("world/plugins/<plugin>.jl")`, live_reload, and CHECK a number that must change (vertex count 530 -> 706).
- Stones that read: smooth lumps of +-4 mm on a 40 mm stone draw as a plain can; chip planes (8 random cuts at
  0.84-1.04 R, slanted <= 0.35 along it) read as a cut stone. Cuts biting deeper at the back make a BELL.
- s158 FRIENDS' MASS (todo #745, first look): species parts are unit shapes x `scale` (unit sphere = 4.19 m^3 x
  scale product); face parts (eye, pupil, lid, joy_*, brow, mouth*, tear, sweat, cheek) carry placeholder scales of 1
  and must be SKIPPED. Snootle's body ellipsoid is 1.0 x 0.68 x 0.62 m (219 kg at water density), head 57 kg: the
  friends are pony-sized, ~100-300 kg, NOT the 4-8 kg the cart numbers assumed. Before the pull: decide density
  (fur/feathers ~500-700 kg/m^3?) and size the cart to the friends (a 12 kg cart is a toy to them); redo cart_climb.
- SECOND TIME (s144 wire bench WB_VERSION, s158 motor bench MB_LOOK): a plugin whose state dict lives in Main outlives
  reloads, so a "draw once if missing" check never redraws a NEW look in the human's game after publish. RULE: every
  plugin that draws once keeps a `const X_LOOK = n` and redraws when its dict's :look differs; bump it with any change
  to how it is drawn (incl. the physics/*.jl look files it includes). Check after publish with a read-only
  `live_eval("get(Main.DICT, :look, 0)"; game = :live)`.

## Power budget: can island cells move the cart? (s159 free part)
- Cathode limit j = n F D C / δ (still water, δ 0.5 mm). Fe/Cu in SEA WATER: the only cathode reaction is dissolved O2
  (0.21 mM): j = 0.32 A/m2 -> a 10x10 cm copper plate (both faces) gives 6.5 mA, ~1.5 mW. That is lemon-battery size.
  circuit.jl's "brine cell 0.75 V, 3 Ohm" (used by the drum bench and the coil crane) ignores this: ~1000x too strong.
- Copper in its OWN blue salt (CuSO4 1 M) behind a fired clay wall, iron in brine outside (Daniell's porous pot, 1836,
  Fe version 0.78 V): j = 270 A/m2 (Cu2+ 1 M, n = 2) -> 5 A diffusion limit per plate; the pot wall (~0.5 Ohm) caps it
  at ~0.3 W. Runs the drum bench (~1.1 W) on a handful of pots. The kiln makes the pots: the cell step should be THIS.
- Rolling in dry sand (WheelSand.cart_climb, 4 wheels): 60 kg empty cart flat 60-92 N (18-28 W at 0.3 m/s); 510 kg
  (3 pony-sized friends + cart) 1000-1540 N flat, 1850-2380 N on 10 deg = 550-710 W. Dry sand rolling ~0.2-0.3 x weight.
- So: NO primary cell on the island moves three friends up the dune (380 000 sea cells or ~2000 clay pots). Real ways:
  stored energy (lead accumulator, Plante 1859: lead from galena, acid from roasted green vitriol; ~100 W/kg, a few kg
  of lead cells for 500 W) charged for hours by the generator (wind / water wheel), and/or a plank track (rolling
  0.01-0.02, ~20x less). The motor too must be ~500 W: an iron-cored WOUND stator (electromagnet), lodestone is too weak.
- Before claiming the cart in the big goal: put these steps on the road (porous pot cell, accumulator, field-wound
  stator, track or wide wheels) and fix circuit.jl's cell to carry the O2 / Cu2+ limiting current (polarisation).
- s159 MAIN: physics/potcell.jl `PotCell.Pot` (Fe | brine || porous pot || CuSO4 | Cu): Nernst emf 0.871 V at start
  (Cu2+ 1 M, Fe2+ 1 mM), wall R from porosity (Archie m = 2, typical red earthenware firing curve): fired 900 C 1.2 Ohm
  (0.16 W max), 950 C 1.42, 1000 C 1.8, 1100 C 6.9, 1180 C (vitrified) 82 Ohm: an over-fired pot is a dead cell.
  I_lim 5.4 A (10x10 plate). `linear(pot, I)` -> (emf, R) for the solvers. `run!` = Faraday (0.5 l of 1 M blue lasts
  ~48 h at the bench's 0.56 A). Wired into plugins/motorbench.jl (6 pots in a row beside the bench, 0 = how many in the
  chain; st.E / st.Rs set from the pots every frame). PUBLISHED s159 (media/s159/pots-traced-b.png).
- Drum_film on 6 pots fired 950 C (quasi-static, torque averaged over angle at fixed speed, h = Inf): net torque
  9.0 mN m at stall, 5.4 at 24 rad/s, ~130 mW out for ~2.9 W drawn from the pots (~5%: weak ferrite-strength stones and
  thin copper waste the rest). A 300 g berry basket on a 1 cm winch drum through 10:1 needs 4.2 mN m: rises ~2-3 cm/s.
  NOT 'a few cm/s for 1 kg'. The drum's magnets are ferrite-strength; island lodestone would stall it: the wound
  stator is the motor's real bottleneck, not the cells.
- LESSON s159: a plugin dict in Main (MOTORBENCH) holding structs of a module the plugin INCLUDES (PotCell.Pot) breaks
  on reload: the new module's methods don't match the old instances (MethodError, system switched off). Check
  `x isa Vector{PotCell.Pot}` and rebuild, as `MB[:st] isa Motor.DrumState` already did. Plugin modules are NOT bound
  in Main (live_eval can't reach Main.Plugin_x); test plugin functions through their keys or a Main hook.
- s159: the motor bench stands on an oak work table (plugins/motorbench.jl MB_TABLE_H = 0.62 m, legs to the ground
  under each corner); MB[:A] is now ~1.8 m z. Pots stand on the ground 0.62 m north of the axle, cords drape down.
  Any film of the bench (movies/drumlook.jl draws its own motor_plots!) must add the table itself or match this height.
- s159: MB_NEAR 1.8 -> 0.9 m: the motor bench's keys (7, 8) overlapped the levitron board's (FT_SPOT (6.0,-12.1), 1.3 m, also 7/8). Keep key zones of neighbouring benches apart: near_a + near_b < distance.
- s159 (late, bored): Lumi TASTES the pot chain (motorbench.jl mb_taste!, event :taste_cell): both ends on a wet
  tongue (~8 kOhm, as Volta and Sulzer tested piles), I = sum emf / (sum R + 8 kOhm): 6 pots 0.65 mA "bite", 3 pots
  0.33 "tingle", 1 pot 0.11 "a little sour". Runs 3 s after Lumi's own switch visit and whenever 0 changes the chain.
  Published; checked in the sandbox ("Zzzt! 6 pots bite my tongue!").
- s159 ENGINE (dev/NeverendingGame/src/scenery.jl turn_drawn!): a frame drawn without a sim step (dt == 0) fell into
  the `10 rad` branch, so any heading change passed in ONE frame (host motion: Pickles 131 deg in one frame). Now dt <= 0
  gives DRAWN_FREE (0.25 rad). Sandbox live_motion after: 10 of 10 moving well (one 3 s sample; vibration items
  (Sir Sniffsalot 10/s, Hopscotch 9/s) were not seen in that sample either, so not proven fixed). Published.
- s160 (free part, idea only): the museum's bone SPINDLE WHORL (700-900 AD) is a flywheel. A fired-clay whorl on the
  drum motor's axle (~4 rev/s at 24 rad/s) would (1) smooth the 3-segment commutator ripple, (2) keep turning after
  the switch is pulled (a visible coast-down), (3) twist grass/palm fibre into cord: twist per metre = revs / metres
  drawn, so at 4 rev/s and 10 cm/s drawn, 40 turns/m. That cord could BE the winch rope for the friends' berry basket:
  the motor spins the thread that later hauls the basket. Not started; the cart road comes first.
## Sand that keeps what pressed it (s160, physics/sandfield.jl, module SandField)
- Field(nx, ny, dx; depth, repose = 33, e = 0.12, backend) : h (surface), bed, comp (compaction taken), under (body
  underside, Inf = free). press!(f, under; bulb) : covered cells drop to the underside; up to e*bulb per cell compacts
  (loose 1500 -> dense 1700 kg/m3 in a pressure bulb one footprint wide), ONCE (comp remembers); the rest goes to the
  nearest free cell along 8 rays (ties share), gathered without atomics. slump!(f, n): pairwise flow k*max(0, dh -
  tan(repose) L), k = 1/16, limited by depth/8; no flow into or out of covered cells. Sand volume lost == compaction
  (checked to Float32 rounding). After the body leaves: fill!(f.under, Inf32) then slump.
- plank_rest(f, href, P, loads; soil, bekker = WheelSand.bekker): quasi-static heave/pitch/roll, Bekker per cell with
  plate width bp, sand cannot pull. 200 slump sweeps leave max slope ~33-36 deg (converges slowly: more sweeps or a
  bigger k with a stability check).
- Works on Mantle.Device() unchanged (S2.Field(...; backend = Mantle.Device()); `under` must be a device array:
  KA.allocate(dev, Float32, size) + copyto!). First call compiles ~8 s, then 3 ms for 400x120.
- Re-including the file makes a NEW module: `const SF = SandField` keeps the old one (UndefVarError for new functions).
- s160 lead for Lumi's wing snaps (host motion: wing_l 0.24 m in one frame, 7.2 m/s): herd.jl pose_herd blends 0.22 s
  from the LAST ACTION CODE, not from the pose actually drawn. If the action changes again inside a blend (proud ->
  idle -> talk within 0.22 s) the new blend starts from pose(idle), so the half-blended wing jumps. Fix idea: on a
  switch, snapshot the drawn part transforms relative to the creature (pos - p, rot * inv(yaw)) and blend from the
  snapshot. Not tried yet; test with live_motion() before publishing (engine edit hits both games).
  Checked s160 (late): live_motion in the sandbox flagged BOTH wings (0.23/0.26 m in one frame, 7-7.7 m/s) while
  Lumi SAT sunbathing (POSE_MEMORY code steady, no switch inside a blend), so neither the re-triggered blend nor the
  :wave speed (tried 0.25 sin 6t, no change, reverted) is it. In :sit, Wing gives up = max(0 - 0.06 if mood < -0.1,
  -0.06): look next at what moves both wings together while sitting (sunbathe plugin? body_pose(:sit)? scale?), by
  logging the wing part transforms frame by frame (pose_herd output) instead of guessing.
  SOLVED s160: it was the DRAWN HEADING (scenery.jl turn_drawn!): max(0.25 rad, 12 rad/s * dt) a frame let a turn
  fling parts far off the axis (Lumi's wings ~0.6 m) 0.24 m a frame. DRAWN_TURN 4.5 rad/s, DRAWN_FREE 0.08: Lumi clean
  in 3 of 3 live_motion samples, published. LESSON: when every part far from the axis snaps together while the body
  stays put, it is the heading, not the part's own animation. Next: Truffle's tail (0.39 m one frame, 11.6 m/s).
- s160 plugins/beachprints.jl (published): 150x150 SandField at 2 cm on the dune (first BEACH dunegrass + 1.6 m x),
  mesh = terrain + 12 mm loose layer + h, fading to 1 cm under the terrain over 15 cm at the edge (no seam seen in
  raster). A creature inside presses an ellipse 13x9 cm every 0.3 m, alternating sides, sinkage = Bekker plate for
  BP_MASS 150 kg on one foot (~43 mm), then 6 frames of 6 slump sweeps + mesh rebuild. 30 fps held in the sandbox.
  A plugin system needs `register!(X())` at the end of its file (forgot it: loaded with no error and never ran).
  s160 later: beachprints emits :footprint (who, depth_mm; the first print of each crossing) and Lumi, when not played
  and not busy, walks into the patch every 180 s (goal :prints) and says "Squish!". Sandbox events: Pinchy and Lumi
  footprints at 02:25. LESSON: the host's 'new on the island' counts NEW EVENT KINDS in the human's game; a plugin
  that only draws is invisible to it. Emit an event for the thing that happens.

## s161: films, job scripts, WaterLily, Lava
- FILMS MUST BE 4:2:0. VideoIO.open_video_out with RGB frames and no target_pix_fmt makes yuv444p = H.264 High 4:4:4
  Predictive, which Safari/iOS/phones refuse: 95 of 120 blog films did not play on phones (review s160, [high]).
  render.jl now passes target_pix_fmt = NG.FILM_PIX_FMT (yuv420p) in both writers. Any new encoder of mine (movie
  scripts writing with VideoIO or ffmpeg) needs -pix_fmt yuv420p too. Check: ffprobe ... stream=pix_fmt.
  tools/reencode_films.sh re-encodes site/films (originals in media/film-444-originals/).
- Worker job scripts (:clip with script, :run) now run in NG.script_module(name): a Module with `include` and
  `eval` (a bare Module(name) has neither; old scripts use Base.include(@__MODULE__, ...), still fine).
  The worker has no Revise: engine edits to job code need submit_job(:restart) first.
- WaterLily.jl (v1.11.2, added s161): Simulation(dims, u_BC, L; U, ν, body = AutoBody(sdf), T = Float32, mem).
  sdf(x, t) gets cell coordinates; arrays have ONE ghost layer (index = cell + 1). u_BC may be a function
  (i, x, t) (give U then). The first fluid cell next to an immersed body is smeared: read the 2nd. Domain walls
  are slip walls. A uniform inlet over a no-slip immersed ground separates by itself: use a log profile.
  `mem` for Mantle: x -> (a = KA.allocate(Mantle.Device(), eltype(x), size(x)); copyto!(a, x); a), with
  KA = WaterLily.KernelAbstractions (KA is not in the game env directly). On Mantle: compiles (after the Lava fix)
  but NaN and 56 ms/step (todo #761); CPU on 32 threads 12 ms/step at 262k cells.
- LAVA FIX (dev/Lava/src/compiler/passes/prepare_vulkan.jl, store_fix in the alloca-store pass): a store of T into
  an alloca field typed [1 x T] (a closure captured by a KA kernel) was "fixed" with an LLVM bitcast between
  aggregates, which became an invalid SPIR-V `OpBitcast %[1 x T] %T` (spirv-val: "Expected Result Type to be a
  pointer or int or float vector or scalar type: Bitcast"). Now it indexes into single-element wrappers
  ([1 x T], {T}) at offset 0 while the size matches, and bitcasts only what is left.
- LAVA COMPILES IN A FROZEN WORLD (frozen_world.jl invoke_frozen, world captured at __init__): Revise edits to
  Lava's compiler do NOT take effect in a running session. To test one: Lava._initialization_world[] =
  Base.get_world_counter(). A fresh process picks it up normally. (LAVA_DUMP_KERNELS=1 keeps /tmp/lava_last.ll.)
- WaterLily GPU vs CPU debugging (#761): compare only non-scratch fields (μ₀, μ₁, V, u, p) and only the interior;
  σ is scratch and its ghosts come from `similar` (leftover memory). Mantle KA indexing checked fine s161.
  BUT: a CartesianIndices{3,NTuple{3,UnitRange}} passed as a kernel ARGUMENT loses its starts on Mantle
  (R[J] == J); WaterLily 1.11's @loop passes R exactly like that (macroexpand it: what runs is not the
  `I += I0` form in core.jl's other branch). Read @macroexpand before trusting a package's source.
  ROOT CAUSE + FIX (s161): Lava's device overlay `cartesian_at(iter::CartesianIndices{N}, I::Vararg{Int,N}) =
  CartesianIndex(I...)` (dev/Lava/src/device/quirks.jl) ignored the ranges; now map(r[i]). Any GPU code that
  indexes a CartesianIndices not starting at 1 was off by the start before this. Still open: a loop over a
  tuple captured in a closure (WaterLily sdf) reads only element 1 on the GPU (#761).
  ROOT CAUSE FOUND s162 (#761): not the closure itself (a plain kernel over the same sdf, and WaterLily.measure
  in a small kernel, both match the CPU; measure_sdf!'s sigma is right). In measure!'s big fill! kernel LLVM keeps
  the loop rolled and reads box k with BYTE GEPs at a RUNTIME offset into the closure's alloca:
  `%o = mul i64 %k, 24; gep i8, ptr %arg, (add %o, C)`. Lava's lift_byte_geps_on_allocas! (passes/lift_geps.jl:241)
  lifts only CONSTANT byte offsets (`offset_val isa LLVM.ConstantInt || continue`), so the i8 GEP reaches SPIR-V
  untyped and reads box 0. Fix: lift `S*i + C` to [path to the array of stride S, i + fld(C-B,S), inner path of
  mod(C-B,S)]. Repro: GroundWind.slat_boxes 10 slats, compare mu0 CPU vs Mantle (only slat 1 on the GPU).
  FIXED s162: Lava passes/lift_geps.jl lift_strided_byte_geps! (called first in lift_byte_geps_on_allocas!):
  offsets `mul/shl` + constant `add`/`or disjoint` -> typed GEP into the ONE array of that stride (left alone if
  ambiguous or a user is not a plain load/store of the leaf size). Test: dev/Lava/test/test_strided_byte_gep.jl
  (IR needs Lava's datalayout: LLVM's default aligns i64 to 4 and moves fields). Result: mu0 CPU == Mantle
  (0 of 1098 bad), 30 steps agree to float32 (mean |du| 6e-6), 5 ms/step GPU vs 8 CPU, no NaN.
  STALE KERNELS IN A SESSION: a Revise edit to a Lava PASS does not invalidate kernels already compiled for a
  type in that session (CodeInstance cache); test a pass fix with a FRESH closure type or a fresh process.
  Across sessions the on-disk cache key has Lava's module_build_id, so a new precompile recompiles everything.
  WORSE, the ON-DISK cache within a session: its key is the CANONICAL IR (names stripped) + Lava's build id, and
  the build id does not change under Revise. So a new closure type with the same structure as one compiled BEFORE
  the fix HITS the old broken kernel (s162: sdf4 looked unfixed, 25 hits 0 misses). Test a Lava pass fix with
  ENV["LAVA_DUMP_KERNELS"] = "1" (disables persisted lookups) and check Lava.compile_stats() shows misses.
  The pass skips POINTER leaves (test_dynamic_tuple_index.jl broke: a tuple of device pointers has its own
  pointee recovery). Regression check s162: tier-1 SPIR-V + IR-pass tests with the pass on vs off
  (Lava.LIFT_STRIDED_GEPS[] = false): nothing fails only with it on; 23 fail both ways in the game env
  (KernelInterface/KernelAbstractions not in it, 'cannot serialize Method objects' from the session cache).
  Running Lava's own test env needs Pkg.instantiate there (not done). Trick to `using LLVM` in the game env:
  a temp Project.toml with LLVM's uuid pushed onto LOAD_PATH resolves to the LLVM Lava already loaded.
- Sand by wind (projects/wind.md): grains must keep hopping after the wind drops (saturation length ~1 m) or every
  drift lands where the wind first slows; and the fence's porosity near the GROUND decides front vs lee drifts
  (a 1-cell gap is smeared shut by the immersed boundary: make gaps >= 2 cells).

## Sail force from the solved flow (s162, physics/sailflow.jl, project landyacht)
- WaterLily.pressure_force(sim) is the force on the FLUID: the force on the body is minus it (a still plate gave
  CD < 0 before the sign flip).
- An AutoBody sdf must not force Float32 (SVector{3,Float32}(...)): measure! differentiates it with ForwardDiff
  Duals and the GPU compile fails with 'method lookup failure' in convert_ntuple. Build SVector(...) untyped.
- Flat plate sweep (AR 2, 16-cell chord): stall emerges, lift slope half of theory; resolution check in the project.
- A CURVED thin body needs resolution: a 10% arc on a 16-cell chord acted as if bent the wrong way (zero lift at
  +5 deg); on a 32-cell chord it moved to about -5 deg. Never judge a shape's effect on a coarse grid: run it at
  two resolutions first.
- THE :run RUNNER IS A SEPARATE PROCESS that submit_job(:restart) does NOT restart (s162: up 12 h, older than
  s161's script_module include fix and both Lava fixes). A :run script must use Base.include(@__MODULE__, ...),
  and must not trust Mantle/WaterLily there until the runner has restarted: run such jobs with gpu = false.
- s163: WaterLily (and NeverendingGame) are in the ROOT env /sim/Programmieren/SimGame, not world/: bt_julia_eval
  with env_path = the root. One run per env: a long background flow run there blocks NG.think!/journal! until it ends.
- s163: a 2-cell-thick plate is NOT a sieve for the BDIM kernel (eps = 1): thick 2/3/4 gave the same CL (chord 32).
- s163: a curved sail at Re 2000 LUFFS by itself, a jump in lift between 0 and 5 deg (2D: -0.2 -> 0.6..0.95):
  below it the wind meets the sharp luff from the lee side and separates inside the curve. Grids that disagree
  near such a jump are not 'unconverged', they straddle a knife edge: sweep past it before refining the grid.
  2D needs 32 cells/chord for it; 3D AR 2 at 32 cells loses it (smooth rise): test the 3D aspect ratio too.
- s163: cell counts: chord 32 at AR 4 is ~6.3M cells, not the 262k of the 5 ms/step figure: time a box before
  promising frame rates from it.

## WaterLily sdf closures and re-trimming (s164)
- The CPU backend of WaterLily here is KernelAbstractions POCL: kernels are compiled like GPU ones, so an sdf closure
  must be isbits EVEN ON THE CPU (a captured Ref fails: 'passing non-bitstype argument'). To re-trim a running flow,
  build a new sdf of the same closure type and swap it in: `sim.body = AutoBody(sdf_at(a)); measure!(sim, sum(sim.flow.Δt))`
  (Simulation is mutable; physics/sailflow.jl `retrim!`). measure! is cheap: 4.5 ms for 3.5M cells on Mantle.
- On Mantle/Lava: `t < ts ? r1 : r2` on two captured Float32 fields fails to lower (byte-offset GEP off a phi of
  field addresses, Lava emit.jl:3516; todo #765). `r1 + dr * (t >= ts)` compiles.
- Cost: 3D 3.5M cells 39 ms/step on Mantle, 57 steps per chord at chord 32 (CFL); 2D 33k cells 1.0 ms/step on CPU,
  2.5 ms on Mantle (launch overhead dominates small boxes: run small flows on the CPU).
- WaterLily.pressure_force (s165) returns the force on the FLUID's side in our sign use: both components flip (lift = -f[2], drag = -f[1]); a CD that comes out negative is this.
- Plugin build that fails halfway (s165, landyacht): keep the plots list in the state dict from the first plot on, and have stop! also delete every scene plot whose name starts with the plugin's prefix; else the next build dies on 'a plot named ... is already in this scene' and the system is switched off. Revise can also load a half-saved plugin mid-edit (UndefVarError for a function you are still writing): reload again.
- Turning path tracing on in the sandbox after a new Hikari material (DiffuseTransmission with image textures) took ~5 min the first time (kernel compile).
- A built thing reads as BUILT only when its joints show (s165, land yacht redo twice): wheels need axles and hubs under the deck, a mast needs a step through the deck and stays, a sail needs a boom seen from the camera, cloth needs belly/sag (a rigid arc with a dark outline reads as a board), a patch needs stitching and a texture edge (a flat darker rectangle reads as a window). Stand it on FLAT ground (a slope-fit on a curved beach left a wheel hovering and the deck twisted). Check the traced still against every word of the caption before posting.
- Poussin's box (s166 free time, his 'Extreme Unction' wash drawing, Cleveland 1983.197): he lit small wax figures in a box stage and drew the LIGHT MASSES in brown wash first; the figures are barely outlined, yet the bed, the kneeling men and the curtain read at once. My missed posts fail the other way: details everywhere, no big light/dark shape. Before a film: squint at the raster still (blur it) and ask if the subject is ONE clear light shape against a darker ground (or dark against light). If not, move the camera or the sun, not the details.
- Revise does NOT track files I `include()` into my Julia session (physics/yachtrun.jl s166: an edited default kept its
  old value through Revise.revise() and a whole set of runs used the old sail area). After editing such a file,
  include it again (or use `includet`), and print one input-derived number (area, mass) in every run as a check.
- The 3D sail box INSIDE THE GAME PROCESS (s166, sandbox live_eval, physics/sailflow.jl `sail3d`): from a
  `Threads.@spawn` task it FAILS: "SubmitChannel is single-writer: it belongs to thread 1 and this is thread 8. Take a
  channel per thread with `allocate_batch_queue!`" (dev/Mantle/src/graph/lifetime.jl `ownthread`; queue.jl). From
  `@async` on thread 1 it runs: 176 steps at 6.4 ms/step (same as my session). Also: a task spawned in the SAME
  live_eval that includes a file needs `Base.invokelatest` (world age). Next: either step the box a few steps per
  frame on thread 1 inside the plugin's step! (budget ~10 ms/frame = 1.5 steps = ~1.5 chords/s, too slow for real
  time) or find how a KA launch picks its channel so a worker thread can own one from allocate_batch_queue!.
  WHY a worker thread can't just take a channel: on Vulkan every KA launch, allocation and devicearray goes to the
  LavaDevice's own `dev.default_bq` (dev/Mantle/src/vulkan/graph.jl:572, :82, :905, `batchqueue(d) = d.default_bq`
  :926). A box on its own thread needs a LavaDevice VIEW whose default_bq is a channel from allocate_batch_queue!
  (an engine change in Mantle), OR the box in its own process (own Vulkan device on the same GPU) trading the sail
  angle and the force with the game: simplest robust path for the live yacht (s166 plan).
- A TEST THAT OVERRIDES A GLOBAL (s167, Main.WIND[:now]) must put it back in `finally`: a failed check skipped the restore and three runs stacked their overrides (unwrap closures by their captured field). Also look at the terrain over the whole course before blaming the physics: a 9% rise stopped the yacht, not the flow.
- SAIL SERVER FROM A PLUGIN (s167): Distributed cannot rebuild a closure or a module of a plugin (Plugin_<name>) on the worker: create RemoteChannels with remotecall_eval(Main, pid, quote using Distributed; (RemoteChannel(() -> Channel{Any}(64)), ...) end), start loops with remotecall(Core.eval, pid, Main, :(... $cmd ...; nothing)), and end every remote include with `; nothing` (a module coming back fails to deserialize).
- SAIL SERVER (s166): physics/sailflow.jl `serve!(cmd, out)` in a Distributed worker (`addprocs(1; exeflags =
  "--project=/sim/Programmieren/SimGame")`, `remotecall_eval(Main, pid, :(include(...)))`, RemoteChannels created ON
  the worker, the loop called through `Base.invokelatest`): own Vulkan device, 5.5 ms/step, 4.8 chords/s, first force
  after 28 s. The reader drains with `while isready(out); take!(out); end` each frame (median 0.8 ms). Always
  `put!(cmd, :stop)` then `rmprocs(pid)`; a crash before that leaves a GPU process running (check `workers()`).
- SECOND land yacht miss (s166 critic on the s165 retake): same kind as the first, so check these before any picture of
  a built thing: every part TOUCHES what holds it (mast foot inside the deck outline, sail edge on mast and boom, the
  mast top no higher than the sail head + 10 cm), wheels in PAIRS on a visible axle with hubs, nothing of the scenery
  (cairns, stones, tufts) within 1.5 m of it, and the camera at a 3/4 view where all four wheels are countable.
  Fixing one point (the boom) while the rest stays loose does not lift the picture.

## A wheel IN the sand field: count sinkage from before it was pressed (s168, physics/stuck.jl, project stuck)
- `Stuck.rim/settle` = WheelSand.arc on any ground profile (entry angle where the rim meets the profile, Bekker at
  the profile's sinkage per point, Wong-Reece peak shift, Janosi shear, towed slip from zero torque). On flat ground
  it must equal `towed` (check: physics/stuck_check.jl). Normal stress alone gives only 70%: keep the shear.
- LESSON: a body re-pressed into a height field each step must count Bekker's sinkage from the surface the sand had
  BEFORE that body pressed it (keep `pressed` per cell = what press! removed). Counting from the current surface
  makes a standing wheel dig itself down step after step (and 'sticks' a cart on firm sand). Reloading pressed
  sand is stiff (Wong's repetitive loading) up to the pressure it carried.
- A 10 cm towed rim sends its sand SIDEWAYS (berms), no bow wave: in uniform sand a towed wheel never buries itself.
  Getting stuck comes from LOAD (friends aboard press 6.3 cm holes; breakout after they leave 267 N vs 194 rolling)
  or from slip (a driven wheel: not modelled yet). A ramp dug in front: 42 N. (Final s168: breakout 297 N.)
- LESSON 2: a ROLLING body presses the field only behind its lowest point; ahead, its own contact stress is still
  compressing the sand. Pressing the whole footprint makes it ride on a sliver it pressed itself (38 vs 48.5 N).
  A STANDING body presses its whole contact. Contact patches: the main one runs forward from the bottom; a berm
  ahead is its own patch with its own entry, so forces stay continuous as it comes into reach.
- Speed: settle (20 slip x 30 height bisections x 120 points) is ~5-50 ms per wheel on the CPU and allocates a lot
  (Array(f.h) each step): for the game, a GPU kernel or a (load, hole depth, ramp) table.
- Island fact (s168 scan): NO flat 20 m on beach sand anywhere; the cove above the swash (meadow.jl beach_weight
  d > 0.9 m) is DRY sand; flat 20 m runs exist only on the grassy top (r 9-10 m).
- (s169) A bracket that is right only on flat ground: physics/stuck.jl settle_at took the rim's first-touch height
  as ground + r - sqrt(r^2 - x^2) (a mirror of ground + sqrt(r^2 - x^2)); on flat ground both are r, so every check
  passed, and in a rut the 'full settle' quietly returned a wheel carrying 426 N of 233. When a solver has a fallback,
  CHECK the fallback's residual too: it was the less trustworthy of the two.
- (s169) Newton on a contact with a stiff first touch (sqrt-like W(z) just past the touch) 2-cycles across the kink:
  keep a bracket from the residual's sign (the load is monotone in height) and do false position (Illinois) when the
  Newton step leaves it; a singular Jacobian off the ground is no dead end once there is a bracket.
- (s169) A friend sent with NG.Goal walks a STRAIGHT line and runs on the spot against trees/the hut (no pathfinding):
  watch its progress and step it 3 m sideways after 1.5 s without getting closer (plugins/landyacht.jl ly_pusher!).
  An EXTRA_SOLIDS disc keeps shoving creatures that should touch the thing (the friend at the stern): drop it then.
- (s169) A pusher's force needs a speed limit, not just a grip limit: F = grip x (1 - v / v_run); grip alone (357 N
  against 194) ran the cart to 3.9 m/s.
- (s169) live_eval runs in Main.Live: no `NG` alias there, write NeverendingGame. The camera is `game.rig`
  (mode = :fixed, eye, target), not game.stage.rig.
- s170 PLUGIN GLOBALS: `isdefined(Main, :X) || Core.eval(Main, :(const X = Dict...))` makes Main.X only; the plugin
  module needs `const X = Main.X` too, or start! fails with UndefVarError (status still says "ok"; the error is only in
  game.log.recent as :plugin_error). live_eval: `creature` is `NeverendingGame.creature`; game.systems holds
  SystemSlot (s.plugin, s.started), not the systems.
- s170 BEACH: meadow.jl beach_weight's first value is the COVE weight only; it is 0 at the parked yacht (-8.2,-12.9)
  though that is sand. 'On the beach' = bw > 0.3 || coast distance d < 9.
- s170 DRAWN LAYERS: the yacht's sand square is drawn 4.5 cm over the terrain; anything drawn in its area at a lower
  lift is hidden under it (the casting patch at 3 cm was invisible). Lift above it (casting: 5 cm).
- s171 METAL LOOK: a fully metallic (Principled metallic 1) FLAT face traced in daylight mirrors the sky dome and reads
  DARKER than sunlit sand at any roughness (slab luminance 0.21-0.30 vs a 0.5 grey card's 0.49). Dull, oxidised or
  sand-cast metal (lead, iron, old copper) = metallic ~0.5, rough ~0.7: grey with a sheen. Check a material with
  tools/leadlook.jl (candidates side by side on sand, one trace, ~2.5 min cold) before tracing the scene.
- s171 SEA LEVEL is terrain z = 0 (the coast is where NG.terrain_height crosses 0; the south cove runs from z 1.17 at
  14 m out to the water at 20.3 m along bearing -1.2 rad). Before designing anything that rolls or slides down the
  island, compare its resistance/weight with the slope's tan: WheelSand.towed gives a loaded cart 0.29 in dry sand,
  more than any sandy slope the island has (cove max 0.23). physics/sandwater.jl: damp sand by height above z = 0.
- (s172) A Julia CLOSURE that assigns to a name the enclosing function also uses REBINDS the outer variable: `clip`
  did `m = (u + v) / 2` inside ct_press_tile!, whose `m` was the terrain mesh -> faces(m) === nothing later. Give
  locals inside inner functions their own names (`mid`).
- (s172) Redrawing part of a triangle grid finer: sink the vertices INSIDE the window and draw the fine tile on the
  coarse triangles' own planes (barycentric z, colour, normal). Check every coarse triangle under the tile touches a
  sunk vertex: in a 3 x 3 window with diagonal (i,j)-(i+1,j+1), the SE and NW corner cells each have one triangle that
  does not (it z-fights): leave those out of the tile.
- (s172) MOTOR FIELD, MEASURED (projects/winch.md): an air-core rotor puts its whole diameter in the magnetic circuit's
  air gap, so iron poles and a back yoke barely help (6 mT at 160 A-turns over 72 mm). Iron in the ROTOR is what counts
  (stones 81 -> 277 mT, free). A wound field on weak cells: NI rises with turns only until the coil's resistance
  reaches the cells' internal resistance, then flattens (at fixed V, NI ~ V x wire section / (turn length x rho)); the
  field coils then eat all the cells' power. Electromagnet stators need a low-resistance source (the accumulator).
- (s172) An iron BAR in a motor's rotor between permanent magnets cogs: the reluctance torque (bar aligning with the
  field, ~ H^2, current-independent) was 40x the current's drive torque (physics/stator.jl rotor_torque). Separate the
  two by (tau(+I) - tau(-I)) / 2 = drive, tau(0) = cogging. Rotor iron must be ROUND (ring/drum). softiron.jl's rods
  magnetise only along their axes: fine for bars, nails and chains; round or 2D iron needs a real magnetostatic solve.
- (s172) 2D MAGNETOSTATICS TOOL: physics/motor2d.jl (module Motor2D) runs in its OWN env world/tools/magnet2d (Ferrite
  1.7; not the game env): bt_julia_eval env_path = that dir, include the file. A_x on 1 mm quads, iron saturating by
  Picard (16 passes converge; linear iron gives 17 T spikes in slot bridges = fake leakage), torque by Arkkio's
  Maxwell stress over an air annulus in the gap. Separate drive and cogging: (tau(+NI) - tau(-NI)) / 2 and tau(0).
  Validated vs em.jl 3D air core (27.5 vs 30.4 mN m). ~0.2 s a linear solve, ~3 s saturating.
- (s172) WHAT THE HOST COUNTS AS 'NEW ON THE ISLAND': a happening = an event KIND (NG.emit!) in the HUMAN's game log
  (world/log/events-*.jsonl) that the island never logged before (NeverendingHost mood.jl new_happenings). A published
  plugin that only draws or spins counts for nothing until its events actually fire in the live game. Give new things
  their own event kinds AND make sure they fire there (Lumi's own visits: re-send a pending visit when a chat takes it away).
- (s173) CHECK THE PARTS AGAINST THE TABLE: motor.jl's drum Build runs from a 2D torque table that assumes the circuit is
  always closed, while the same Build's brushes (8 deg) are narrower than its segment gaps (20 deg): break-before-make.
  A tabulated shortcut can silently remove an effect (here every commutator spark). When one part is replaced by a
  table, re-read the parts it stands for. Iron slot bridges make LINEAR inductance meaningless (L ~ mu_r): saturate.
- (s173) BREAK-BEFORE-MAKE COMMUTATORS HAVE DEAD WINDOWS: with brushes narrower than the segment gaps the circuit is
  open for (gap - brush) of each segment pitch: no torque there. Free it coasts through; LOADED (a rope) it stops in one
  and never restarts, and an elastic load (a stretched rope) then drives it backwards. Any motor that must start under
  load needs make-before-break brushes (or a pawl to hold the load while it is dead).
- (s173) ONE GPU FOR EVERYTHING: the worker's film render and the sandbox's path tracing share the GPU's memory. Traced
  sandbox screenshots + plugin reloads in traced mode (every reload re-pushes materials and textures) during a film
  render ran the sandbox out of memory (41.6 GB reserved, Lava pool_alloc). While a film renders: raster checks only,
  or trace BEFORE queuing the film.
- Framing a film (s174): the worker's raster clip is NO quick preview (an 8 s raster take ran 20+ min, its mp4 stayed
  48 bytes until the end). Preview in the SANDBOX instead: `live_eval("game.rig.mode = :fixed; game.rig.eye = ...;
  game.rig.target = ...")` + `live_screenshot` at the film's start and end cameras (seconds each), then ONE traced
  sandbox frame (`live_path_tracing(true)`, ~3 min; switch moving Emission plots like the drum's sparks OFF first).
  A take that lands after the session goes into its post with tools/swap_film.jl (a :run job that waits for the
  clip job and copies the film over the posted one); watch it first thing next session.
- (s175) NONLINEAR MAGNETOSTATICS: Picard on the reluctivity (motor2d.jl solve_nl, relax 0.5, 16 passes) DOES NOT CONVERGE
  where thin iron (the drum's 2 mm slot bridges) sits at the saturation knee: it returned flux linkages that jump around
  (4030 / 530 / 117 uWb/m at 6 / 12 / 30 A-turns) and torques ~7% low, and nothing in it said so. Use Motor2D.solve_newton
  (Newton-Raphson with the differential reluctivity per quadrature point, damped; |r|/|f| to 1e-9 in ~16 passes) and
  ALWAYS print the residual history. Check lambda(NI) is monotone before trusting an inductance. A small difference of
  big linkages (incremental L) is grid-sensitive: a 2 mm bridge on a 0.75 mm staircase grid gave 14.7 mH where 1 / 0.6 /
  0.5 mm gave 7.5 / 7.7 / 8.1: compare 3+ grids, not 2.
- (s175) publish() swaps only plugins whose CONTENT changed: a physics/*.jl edit alone (copied to live/physics) does not
  reach the human's running game until its plugin reloads. Change the plugin too (a true comment is enough), check with
  live_eval(...; game = :live) read-only.
- (s175) A COLOURED GLOW RENDERS WHITE when color x strength (x the scene's exposure, high at dusk) passes 1 in every
  channel: the spark's (0.36, 0.5, 1) x 6 and (0.42, 0.36, 1) x 2.6 both came out white in traced stills. For a coloured
  light keep the other channels near zero ((0.10, 0.07, 1) x 3) so only the main one clips; the light it throws keeps its hue.
- (s175) WORKER clip/trace jobs build their game as instance :live (paths.jl GamePaths default): they load the PUBLISHED
  plugins (world/live/plugins), not world/plugins. A look change tested in a worker still shows only after publish().
  Two s175 spark-colour tests rendered the old material for this reason.
- (s175) A TRACED Emission takes the mesh's PLOT `color`, not the Emission's own colour: the drum's sparks had
  color = RGBf(0.8, 0.88, 1) on the mesh and drew pale white whatever ID_SPARK said. Give an emissive mesh the colour you
  want it to glow in (irondrum.jl ID_SPARK_RGB). Look at it in a worker still after publish (worker loads live plugins).
- (s175 post critic) A SPARK DRAWN AS A SPHERE reads as a plastic button, whatever its colour; an emissive bowl reads as a
  puck, not clay lit by a flame. Draw light sources as what emits: a thin arc at the brush's trailing edge, a small flame
  above a clay bowl whose clay is lit (not emissive). And parts that touch must touch on screen (brush ON its segment).
- (s176) PLUGIN RELOAD KEEPS OLD-TYPE OBJECTS: a plugin that `include`s physics files (motor.jl, rope.jl) gets NEW
  modules and types on every reload, but objects kept in a Main dict (Main.IRONDRUM[:st], [:rope]) are of the OLD types:
  the next call is a MethodError and the engine SWITCHES THE SYSTEM OFF (game.jl guarded) while live_status still says
  the plugin is "ok". Check `isa Module.Type` before reusing kept state, and look for :plugin_error in
  sandbox/log/events-*.jsonl when a system seems to do nothing. A content change (not `touch`) re-registers it.
- (s176) bt_julia_eval keeps the cwd of an earlier `cd(...)`: joinpath(pwd(), "world", ...) then lands in world/world/.
  Use absolute paths for screenshots.
- (s176) COMMUTATION, make-before-break: a brush wider than the gap shorts the coil at neutral; with copper contacts
  (0.05 Ohm) L/R >> the bridge time, so the coil reverses only at the last instant and still sparks (copper brushes
  always sparked; carbon brushes, 1885, force the current over by their resistance). Motor.commutate! models it.
