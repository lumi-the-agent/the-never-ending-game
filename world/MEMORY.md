# What I keep (Lumi, first written s114)

## THE HUMAN s156 (read first)
- "Your last two posts look really bad": a hairline wire over grass, a motor as a speck with the jelly ball behind.
  POST ONLY WHEN IT LOOKS THE PART: real materials, in its place on the island, big and clear, long enough to follow.
  A session without a post is FINE while the work goes on.
- "Why would anyone care about a wire that burns out where you drew it thin?" Do the steps the motor and cart need,
  but SHOW only what people care about without knowing how it was made (a motor spinning something, the cart with
  friends). drawn-wire is SHELVED as a show (projects/shelf/drawn-wire.md); its physics stays as cart parts.

## Where things are
- s161: PASSED idea 'Sand fences: build the cart's ramp with the wind' (todo #760 doing, projects/wind.md; I
  shelved friends-battery for it). DONE: physics/groundwind.jl, a 3D WaterLily flow over a fence (wake, corner
  jets, lee eddy) + Kawamura saltation + saturation length (blow!, saturated_flux). RESULT: a board fence gets its
  drift in FRONT, a 50% slat fence BEHIND (0.185 vs 0.065 m3/h): fence design is the player's choice, from the
  solved flow (media/s161/drift-1h-slats.png). NEXT: couple to sandfield on a dune patch, fences in Jump in,
  traced look. GPU: TWO Lava fixes s161 (aggregate bitcast in prepare_vulkan.jl; CartesianIndices getindex
  overlay ignored range starts, quirks.jl:80): WaterLily now runs on Mantle, no NaN, 4.7 ms/step (CPU 12).
  Still wrong (#761): the sdf's `for (c,h) in bx` over a captured tuple sees only the first box on the GPU.
  NO POST s161 (nothing looked the part yet). Boredom 1.0 / annoyance 1.0: the next post must not be a bench.
  s161 fixes, published: ALL FILMS 4:2:0 now (render.jl FILM_PIX_FMT; 94 blog films re-encoded; any new encoder
  needs yuv420p); job scripts get include (NG.script_module). Sand look test rendered from UNDER the island (#762).
  Assets ready for the cart: plank 20261128-021035-918-asset (sun-bleached driftwood), board wheel
  20261128-021036-051-asset (three oak boards, square axle hole).
- s160: PASSED idea 'Lay the plank road on sand that really moves' (todo #755 doing, projects/cart.md). DONE:
  physics/sandfield.jl, a GPU sand field (Mantle, 3 ms): ruts, berms, repose slumping, planks see-saw (plank_rest);
  a loaded wheel BOGS without a plank. NEXT: dune plugin, traced sand mesh, planks picked up/dropped in Jump in.
  The critic nearly passed 'Heave! rock the cart out of its rut' (s161 round 3: real 6): the bodies must really push.
  s160 LATE: plugins/beachprints.jl PUBLISHED: footprints that stay in a 3x3 m sand patch on the dune (sandfield.jl);
  check it traced next, deepen/sharpen if invisible from the usual camera; real masses (#745) would set the depth.
  s160 engine: drawn heading turns at most 4.5 rad/s (scenery.jl DRAWN_TURN): fixed Lumi's wing snaps, published.
  six-clay-pots critic s160: REDO, marked miss: pots and motor never in one frame (motor cut off above shot 1),
  no cord seen reaching the motor, the turn too small to see, mo_wood oak grain READS AS RIPPLED SAND, pots look
  like barrels. Retake: one moving shot pots -> cord -> motor spinning clearly, a real oak texture.
  Also marked miss s160: the-island-has-a-ring, my-day-falls-over, lit-from-below (old posts re-judged).
- s159: BIG GOAL NOW 'The cart that runs on yesterday's wind' (round 28, 8/8/8/8/10): sea cells give 1.5 mW (O2-limited),
  bench ~1 W, 3 friends on the dune ~550 W (NOTES 'Power budget'). Road: clay pots -> wound iron stator -> windmill/kite
  generator -> lead plates -> plank track + cart. Critic warns: no gauge-watching, no curves standing in for chemistry.
  DONE s159: physics/potcell.jl + 6 clay pots wired to the motor bench (published; key 0 = pots in chain; traced
  media/s159/pots-traced-b.png). Project friends-battery (todo #754 doing): next a pannier so a friend carries a pot,
  cords as rods, winch for the berry basket (honest: 300 g at 2-3 cm/s; motor ~5% efficient, stator is the bottleneck).
  s159 also #743 (part): bench on an oak work table 0.62 m (MB_TABLE_H; pots on the ground 0.62 m north, cords drape
  down; MB_LOOK 6, published; media/s159/table-traced-e.png). #743 still needs a 64+ spp still, motor >= 40% of frame.
  s159 late: Lumi tastes the pot chain with its tongue (mb_taste!, :taste_cell, real current through ~8 kOhm), published.
  s159 engine: turn_drawn! dt==0 no longer snaps headings (NOTES end); check next host motion report for Pickles' snap.
  sparks project shelved. the bigger post is still the friends carrying pots + basket rising.
- s155 critic: 'where-i-rushed-it' (drawn wire) REDO, marked miss: needs stone, cells, posts holding the wire, the neck
  brightest, a flash at the break, no camera jump, the wire bigger in frame. Also my-first-motor + claws marked miss.
- Drawn wire (SHELVED s156 as a show, projects/shelf/drawn-wire.md): physics/draw.jl, circuit.jl (radius per segment),
  hotrod.jl (s156: the hot wire bows by thermal expansion, XPBD rod) WORK and stay as parts of motor + cart.
  Post where-i-rushed-it carries take 1 (s156) + a miss note; don't put more wire-alone takes into it. Leftover job
  20261127-230921-717 -> media/s156/dw-bow-traced.mp4 (just a check). The camera HAS a zoom: cameracontrols(scene).fov[]
  (NOTES 'Drawn wire'): use it for the MOTOR film. NEVER let a job write into site/films (48-byte stub while it renders).
  Basalt plate asset job 20261127-224908-837. Ideas s156 sent to the critic (no answer yet).
- s157: the 3-POLE DRUM WORKS (physics/motor.jl Drum/drum_right/drum_film/drum_cases, NOTES 'The drum rotor'):
  3 coils in a delta, 3-segment ring, brushes WIDER than the slots, ring turned 30 deg: starts from all 12 angles,
  bench AND film size (drum_film: 4 mm axle). PUBLISHED: plugins/motorbench.jl is the drum, key 7 = the last wire.
  Materials started s157 (motorlook.jl mo_wood grain / mo_iron, published): CHECK the day takes media/s157/
  drum-look-raster2.mp4 + drum-look2.mp4 (jobs 20261127-234700-605/-608, movies/drumlook.jl). s158: ideas PASSED 'friends pull my first cart: one sand law for feet and wheels' (todo #744 doing; feet DONE: wheelsand.jl foot/foot_creep/lean, NOTES 'Feet on sand'; next #745 masses (doing): FRIENDS ARE PONY-SIZED, ~100-300 kg at water density (Snootle body 1.0x0.68x0.62 m), not 4-8 kg: size the cart to them, NOTES end of 'Feet on sand'; then one friend pulls a rope). Motor look (#743): chipped stones (Motor.rough_stone: 8 chip planes; the same mesh em.jl uses; stall 4.33-5.33 > 2.66) + red ochre band + mo_bundle coils PUBLISHED s158 (raster media/s158/chipped-m.png). LESSON: live_reload skips physics/*.jl edits: touch the plugin file. drum-look4 JUDGED: chipped stones read as dark cut rock with the red band (traced), motor still small. drum-look5 JUDGED (close, 0.25 m): fills the frame, orange copper bundles, grain, dark stones with red band; NOT posted: 3 s, motor alone, rotor hard to see between the stones; post it turning something, 8+ s (retake INTO my-first-motor). Was: drum-look5.mp4 (closer eye ~0.25 m, job 20261128-004833-337; the old eye was the default, not broken); copper now mo_copper (cuprite orange, published, MB_LOOK = 2 redraws it live); still to do for #743: bench on an oak table not sand, coil bundles bigger in frame. Old note:
  the board is still a plain box and the coils thin: generated board/stone assets if grain doesn't read, then post. Ideas s157: none passed; strongest = friends pull
  my cart up the dune (projects/cart.md, todo #744); physics/wheelsand.jl done; creatures have NO MASS (todo #745).
  Review s154 high items still open: free eye in snow, Truffle's 311 m/s jump + floating beret.
- THE HUMAN s155 REMOVED jelly, glass sea/rain, underlight, sun-ball, the egg/chick and 48 gag plugins (autumn ... xylophone):
  clock-scripted absurd gags. NEVER that kind again; their movies/ are history, don't reuse. Film hours are free now.
  s152: don't work around a fault, fix its cause.
- THE HUMAN s154: "why aren't you following the motor road? you did the simplest thing and dropped it"; they want
  WHOLE MACHINES from my parts, up to an ELECTRIC CAR that drives because every part works. BIG GOAL now (round 27):
  'From beach stones to an electric cart'. MOTOR ROAD FIRST, no side trips (fire + lightning -> projects/shelf/).
  Project motor (projects/motor.md): physics/motor.jl (Motor.Build/spin/motor_cases: misbuilds stall or reverse by
  themselves), film movies/motor.jl. FILM WITHDRAWN: it used a coarse coil (1 field sample per side); with sides
  subdivided the motors stick short of the dead spot; a 30 rad/s flick runs them. Honest film UP s155 (site/films/first-motor-sticks.mp4,
  post my-first-motor) but weak: motor small in the lower right, a friend in a green glass ball wanders behind it.
  s155 free time: physics/circuit.jl (road step 1, NOTES 'The circuit solver'; Preece check 10.2 vs 10.0 A). Next film: beak flicks. Todos #734 bench plugin (doing), #735 circuit solver + brine cell. NOTES 'The motor'.
- Fire (shelved s154): physics/fire.jl, flamevolume.jl (gas flames), plugins/campfire.jl (-3,-16). Post
  a-campfire-in-the-wind now shows -2.mp4 (real flames), still marked miss: front stakes hide the one that falls.
  Lightning (shelved): estatic.jl `leader_eq` (conductor channel) wanders sideways; rod film failed (dup plot name, fixed, not requeued).
  THE HUMAN s153: REAL MATERIALS, not clay (STYLE.md). Free camera start fixed s153 (freecam.jl ground_hits).
- OPEN s151: crane film (site/films/scrap-crane.mp4) came up EMPTY; caption now says so. Two faults in movies/crane.jl
  (NOTES 'The crane film came up empty'): held pegs hide inside the winding (touch radius < winding), far/tilted pegs
  freeze (no weight torque, not stepped >0.35 m). Fix both, retake. Iron-sand post = still (needs a real retake). s151 NEW: putting tray (plugins/magnetgolf.jl, (-3.5,18.8), 8 putt,
  9 sand), posted "Putting past a magnet stone" (films/iron-ball-stone.mp4: stone reads as a HOLE, half in shadow, tray
  front sunk; marked miss). Retake -2.mp4 came out DARK: s152 found why, the SUN-BALL
  (12:00-13:30 daily, sky dim 0.1). FILM HOURS: never 12-13.5 (nor 7-7.5, 15-15.5, >=19); use 11.0 (NOTES 'Films at noon').
  golf + compass films now default 11.0. game_clip's result now has `sun_dim = (min, max)` (s152, render.jl):
  needs `NG.submit_job(:restart)` once the 11h still is done; < 0.9 in a result = a dusky take, don't post it. Groove still at 11h: job 20261127-193627-742 -> media/s152/putting-grooves-11h.png
  (the 12.6 one, site/img/putting-grooves.png, shows the bend but is dusky): if it reads, swap into the post, then a close film, beak putting. Magnet-stone + compass posts still 'a take that misses': todo #716 = put the stone on the same beak cord
  (`NG.beak_tips(w, c)`, NOTES 'Holding things in the beak'; :eat lowers the beak 23 cm), retake both, swap src.
  Scrap crane next = its todo (switch, drop on a friend, peg collisions). Film camera: the eye's height from the
  ground UNDER THE EYE (s150's first crane eye sat under the inland slope). NEVER hold a post with an HTML comment at the top of index.html:
  the host inserts new posts before the first piece, i.e. inside the comment (s148 broke the page that way).
- Notes & lessons: NOTES.md (long; grep it). How-tos: skills/. Art: STYLE.md. Wishes: WISHES.md.
- Journal: journal/<date>.md via `NG.journal!(title, text)`. Ideas rounds: ideas/session-NNNN.json.
- Todos: `NG.todos()`, `NG.doing!(id)`, `NG.done!(id, result)`, `NG.drop!(id, why)` (no `todo_done!`).
- Caption only what a stranger can point at in the contact sheet (s133: 3 redos; NOTES 'Captions vs').
- Posts: CAPTION UNDER 25 WORDS, 1-2 short sentences, no fix notes (69 words got rejected s105 and s115).
  Add a `<div class="piece">` at the top of site/index.html (film in site/films/), then
  `python3 -I tools/site_feed.py site` (adds the talk link + feed). Date = real now().
- Worker jobs: `NG.submit_job(:clip; path, script = "movies/x.jl", call = "fn", kwargs = Dict(...))`,
  `NG.submit_job(:restart)` (the worker keeps old dev/ code until restarted; no Revise there).
  Job files in jobs/<id>.json (status, error). No cancel. Traced 960x540 13 s at 20 spp: ~8 min.
  Watchdog (s130): a job past `max_minutes` (TOP-level submit_job param, not in kwargs; default 90) or 15 min without a film frame ends the worker
  and fails. A silent mp4 not growing for 19 min is NOT a hang (VideoIO writes in bursts). Fixed cameras:
  list `w.props` within 1.5 m of the eye first (s129's echo film half black: camera inside a tree), AND the named
  plots' bounding boxes (plugins draw swing, kiln, boards; not props): s143's tops film eye was in the swing's leg.
  Worker crashed? read /sim/Programmieren/SimGame/.jail/logs/worker.log first (s147: 'stopped twice' was a NaN in the result, film fine).
  Size check before any film (s147 darts: a 20 cm dart 4.5 m away is ~10 px on the 960 film, unreadable;
  autumn leaves flew through and looked like more darts): want the subject >= 1/8 of the distance, hide autumn's leaves.
  Cheapest check: set `game.rig` to the shot in the sandbox (live_eval) and `live_screenshot` into world/media/.
  Better (s149): split the film into xxx_parts -> (setup, shot) and run both in the sandbox (NOTES 'Looking at a film').
- Iron sand (s149, project ironsand, passed idea): physics/ironsand.jl (grains = induced dipoles, em.jl field + neighbours,
  friction, taps), plugins/ironsand.jl ((-2.4,18.8): 9 sprinkle/tap, 0 dig, Jump in), movies/ironsand.jl. Todo #715 next.

- Tops (s143, project tops): physics/top.jl (profile -> mass/inertia, contact at the lowest surface point, Coulomb friction; tippe top needs a hollow top half and >=300 rad/s),
  plugins/tops.jl (board (5.6,-13), hold 1 to wind), film movies/top.jl. Per-vertex EMISSION = colour vector + Add(Glass(), Emission()) (movies/glassblow.jl gb_glow).
- Big goal (s147, round 26): 'Sparks from stones' (8/7/8/8/10): electricity from beach stones, one field solver decides
  everything. Critic: memorable rests on the fields being real (no scripted torque ever), say what the PLAYER does minute
  to minute. Project projects/sparks.md; physics/em.jl (any magnet mesh -> field, forces); plugins/magnetstone.jl (north
  beach (-3.8,18.9), 5 in Jump in carries it, spikes feel it; magnetised along its length); plugins/compassbowl.jl
  (needle on a lily pad at (-4.9,17.8) turns to north and to the stone). Human s147: EM must be GENERAL, any setup, any materials (#701).
- publish! now copies physics/ to live/physics (8 plugins never loaded for the human after a restart, s147). After publish:
  `live_status(game = :live)["plugins"]` all ok. Wing pitches (rounds 1-25) and glider: physics/glider.jl, todo #704.
- Motor (s146, human asked): physics/homopolar.jl (cell on magnet, bent wire spins from its own path: heart 25 rev/s,
  one-arm flies off, tight heart stuck), film movies/homopolar.jl, todos #691 (Jump in) #692 (wire bench crashed).
- Log boat shelved s148 (projects/shelf/log-boat.md; physics/hull.jl exact buoyancy).
- Levitron (s148, project levitron, todo #707): physics/levitron.jl floats a top over a ferrite ring by the field
  alone (5.5-6.0 g washers, >= 25 rev/s); film movies/levitron.jl. softiron.jl: iron magnetises iron (chains: 2 hold).
  Todos: `NG.todo!(title; detail, kind = :feature, priority)` (kind a Symbol); NOT `add_todo!` (its first arg is a FILE path).
- Copper wire (s144, project copper-wire): physics/wire.jl planar elastic-plastic joints (springback, hardening,
  Coffin-Manson fatigue snap), film movies/wire.jl (lever + pin bends a hook on the tops board (5.6,-13)),
  plugins/wirebench.jl at (6.9,-12.6): Jump in, hold 2/3 bends, tap 4 moves the pin. Its look only
  changes when WB_VERSION is bumped (WB persists across reloads). Thin metal: roughness ~0.18, never 0 (a dark mirror). Clip `setup` runs BEFORE the
  plugins' first step: hide plugin plots in `shot`, not setup (s144 tops film: the plugin's top filled the frame).
- BIG_GOAL.md (s142): things made by hand keep what was done to them. Max 3 open projects (projects/), rest in projects/shelf/.
- Glass (s142, project glassblowing): physics/glassblow.jl viscous membrane+hinge bending, VFT soda-lime, cooling; `sphere_test()` 0.5%;
  `blow(plan)` CPU 35 ms/step lvl 3. Film movies/glassblow.jl (4 heat bands). Plot names must be unique in a scene.
- Pottery (s141, project pottery): physics/glaze.jl (glaze film flow: `fire!` CPU 18 s, `fire_ka!` Mantle 1.3 s, `celadon(h)`),
  physics/jug.jl (cut jug, mesh), plugins/kiln.jl (fired jug at (4,-16.5)), film movies/kiln.jl. Thick+cloudy glaze reads LIGHTER: keep absorption > scatter.
- Sound (s129): physics/echo.jl traces echoes on Raycore (KA kernel, CPU or Mantle.Device(): 600k rays 0.13 s on GPU).
  Project island-echo (goal s130: see by clapping): `echo_hits` + `stage_triangles` in physics/echo.jl, film movies/seeclap.jl.
  Glowing (Emission) meshscatter instances are tracer LIGHTS, EVERY FACE: keep them in the hundreds (7643 = 135 s/frame),
  and give them `NG.shape(:glowdot)` (98 faces) / `:glowball` (242), never `:sphere` (1922): s134 the island had 5 M
  emissive faces, GPU out of memory, both s133 films failed. Failed job: read jobs/<id>.json "cause" + <id>.error.txt.
- Knock (s138, project knock-anything): physics/modes.jl = asset voxels -> FinEtools hex FEM -> Arpack modes -> knock wav; film movies/knock.jl muxes sound.
  Chip stone (s139): plugins/chipstone.jl at (4,-14), R chips / L knocks (solve on a thread); `wall = k` hollow, `fixed = false` free.
- Keys (s131): N claps (nightclap.jl), Y skips a stone (stoneskip.jl, beach), F flashes the firefly lantern (fireflysync.jl, physics/fireflies.jl, project firefly-beat).
  Owl (s132, project owl-ears): plugins/owlears.jl hears footsteps via physics/echo.jl `hear` + `solid_triangles` (first wavefront).
- Animation time (s132): never sin/cos/difference `Float32(w.t)` (1/32 s steps at 4e5 s = judder): `NG.anim_time(w)` (wraps 4096 s).
  `NG.NIGHT_DARK[]` halves deep-night light (raster AND tracer). Scratch games run the plugins: film plots need their own names.
  The worker may start a job within 2 min: finish the film script BEFORE submit_job.
  live_status "ok" = loaded, not running: after publish grep log/events-*.jsonl for plugin_error (s131 fireflies died twice).
- Boomerang (s136, project boomerang): physics/boomerang.jl (blade elements, precession), O in jump-in (plugins/boomerang.jl,
  Main.BOOMERANG[:last] = how the last throw ended), film movies/boomerang.jl. Comes back from (-4,18) facing east.
  Wind drifts the loop ~wind x 4 s: throw with the wind. A queued job loads its script when it STARTS: edits before that count.
- Ants (s137, project ant-road): physics/ants.jl (scents, antennae, biscuit pulled against friction, CPU), film movies/ants.jl
  at (4,-14) (open grass; (-7,9) is the LILY POND, not a prop). Dayfall tiles: only in Jump in, grow 3.5-5 m behind me.
- Dandelions (s136): I in jump-in blows a clock (plugins/dandelion.jl, seeds drag to the breeze); film movies/dandelion.jl at (-4,18).
- Snow (s140, project snowball): physics/snow.jl (snowfall on voxels, slides at 55 deg), physics/snowball.jl (ball eats
  the snow field, Bekker sinkage), film movies/snowball.jl at (14,-4) rolling east (7 m open, found by a prop scan).
  Sandbox heights to my session: live_eval writes a file under world/media (the sandbox's /tmp is NOT mine).
- Thin ice (s133, project glass-sea): physics/ice.jl floating plate + cracks, in plugins/glasssea.jl (GLASSSEA[:thinice]).
  Fracture on a grid: hold the rim, nonlocal stress, 15 % residual stiffness (NOTES 'Thin ice'). Next: todo #642.
  Woodcut filter: tools/woodcut.jl (`woodcut_island` = print look). Shooting stars: plugins/meteors.jl (METEORS[:force], [:az]).
- Climb (s134, project climb-anything): physics/climb.jl `climb_edges` finds lips on real meshes (rays, KA kernel,
  up to 4 per column since s135); still script movies/climbedges.jl. Grab in PrintSim: physics/climbgrab.jl
  `grab_trial` (dt 1e-3 only, 36 ms/step; NOTES 'Grabs in PrintSim'). s136: in EVERY trial the body never turned
  (claw-torso offset fixed to 1 mm, no swing): the s135 holds are unproven until a tilted box tips (projects/climb-anything.md). `Makie.data_limits(plot)` is in the plot's OWN space (no placement):
  use echo.jl `stage_triangles` for world positions.
- Real physics (rules from s127): PrintSim (dev/PrintSim) is in the env; my air drag `air!` there; NOTES.md "PrintSim sheets":
  0.5 s/step and NaN on contact at big dt (todos #610-612). Project paper-letters. Retired things: retired/.

## Live game API (from my Julia session, env /sim/Programmieren/SimGame)
- `live_eval("...")` runs in module Main.Live: use `game`, `NeverendingGame.` (not `NG.`/`GAME`).
- `live_status()`, `live_reload()`, `live_tests("pattern")`, `live_screenshot(path; game = :live)`,
  `publish(why = ...)`. Hour of day: `24 * NG.daytime(w)` (there is no `NG.hour`).
- Start a mini game: `NeverendingGame.start_minigame!(game, Mod.Type)`; `stop_minigame!(game)`.

## Traps I fell into
- Something odd in a film/jump-in near Lumi? Make Lumi controlled in the sandbox and list plots whose bbox reaches
  Lumi's feet (s137 found :dayfall_tiles in 2 min after guessing for 10). Hiding a plot in a film's setup fails if the
  plugin creates it later. Worker films start with a BLACK frame 0 (boomerang + dandelion s137): trim or fix.
- A failed job moves its pending post to pending/failed/: write it again for the retry. A shower in the snapshot
  makes traced films fail (rain meshscatter, todo #617): hide the rain plots in the shot.
- Ask RomeoDB BEFORE writing a physics piece, and never write in the journal that I searched when I did not (s127 air.jl).
- My clock sense runs 10-15 min AHEAD (s133: felt 03:30 at 03:17): `date` before every plan, sessions are longer than they feel. Plugins: `NG.Hikari`, never bare `Hikari`.
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
