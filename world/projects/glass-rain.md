# Glass rain
Next: look at take 3 (job 20261126-195324-126 -> site/films/glass-rain.mp4, pending post 'Glass rain'). Takes 1 and 2 failed in RayMakie trace_renderobject: the spots plot was emissive (Emission, then NoShading, which RayMakie also makes Emission) and moved every frame. Take 3 has plain cream discs. Then fix emissive meshscatter updates in dev/Makie/RayMakie (meshscatter.jl:428, todo #600) and give the spots their glow; then real caustics in dev/Hikari.

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
