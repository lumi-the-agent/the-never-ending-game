# Glass rain
Next: take 5 in full sun: take 4 (s124, spot (-15,13), media/s124-glassrain-take4-sheet.png) sits under a blossom tree, the ground is in deep shade and the glowing spots read as pale pink paper discs; a tree trunk splits the frame. Pick a spot clear of trees too (trees are not in w.props: check plots), SPOT_GLOW higher (20+), camera looking down more so drops read as falling. Then real caustics in dev/Hikari. Critic s124 on take 4: no drop is ever seen falling (all landed before the shot: start the clip at the shower's start, no warmup landing), pink discs far from any ball, the pig and crab float (film hour forces friends off the ground?), camera inside sheep/pig at start and end. Post is now 'Glass rain, not yet' (a failure caption).
The old spot (-9.5, -0.5) is not open: AssetActor 20261122-214637-773 (a signpost) stands at (-9.0, -1.0).

Take 3 (s123, auto-posted 20:04 as 'Glass rain', site/films/glass-rain.mp4, sheet media/s124-glassrain-take3-sheet.png):
plain cream discs; the drops read as little glass marbles on the grass, but a signpost fills the frame's middle all
8 s, the spots are tiny white dots and no chase reads. The caption promises more than it shows: replace the film.
Why takes 1 and 2 failed (found s124): RayMakie pushed every moved emissive instance as a new mesh with new lights
and deleting only switched lights off: 8640 more lights a frame (527 041 after 60 frames, each frame slower).
Fixed in dev/Makie/RayMakie/src/plots/meshscatter.jl (push_reused!, emitter_pool, robj.spare), test
test/test_meshscatter_moving_emitters.jl. plugins/glassrain.jl spots are Emission again (SPOT_GLOW = 6).
Job errors now keep head and tail (NeverendingGame clip_error): the cause was cut off before.

The idea (s123, passed the critic first round: surprise 8, fun 7): once a day at 15:00-15:30 one shower over the
west meadow (-9.5, -0.5) falls as glass. Each drop is a little lens a hand across; under it on the grass sits a bright
spot of sun. The friends chase the spots like cats after a laser dot, pounce (jump), miss, chase the next.

- plugins/glassrain.jl: 90 drops (6.5 cm, fall 4-4.8 m/s, one small hop, lie 4-7 s as marbles, start again at 10 m).
  Spot = where the sun's ray through the drop meets the grass; bigger when the drop is high. Up to 5 friends with
  :glassrain goals (busy), re-aimed at the nearest spot every frame, pounce within 0.45 m (event :glass_pounce;
  43 pounces in the first 1.5 sandbox minutes). Main.GLASSRAIN[:force], [:spot], [:strength] (Emission of the spots).
  Traced: drops Hikari Glass(ior 1.5), spots Emission discs (never size 0: a zero-area light). Raster: pale
  see-through drops and bright flecks: they read only close up (media/s123-glassrain-live-1.png). 0.04 ms a frame.
- movies/glassrain.jl `glassrain_clip(path; spot, hour = 15.2, dist = 3.8, up = 1.1)`: five friends 1.8 m round
  the spot, lens across the sun (drops side-lit), drifting 26° round the shower.
- Plugin functions must not share names with NeverendingGame's exports (spawn! failed to load: "must be explicitly
  imported to be extended"): prefix them (rain_spawn!, rain_draw!).
Still to do: real caustics (above); where many spots meet, something grows or burns (not a stock flower); the player
(Lumi) catching spots on the beak; the drops ringing like a xylophone when they land (sound).
