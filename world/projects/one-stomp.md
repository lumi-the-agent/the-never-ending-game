# One stomp bounces the whole island
Next: take 2 that READS. Take 1 (site/films/one-stomp.mp4, posted as a first take; sheet media/s125-stomp-sheet.png, frames media/s125-stomp-f26.png, -f42.png): from 10 m up the rings are invisible, nobody is seen in the air, and the word sand flickers (wordsand.jl redraws its flat sand every 0.5 s over my lift: leave :wordsand out of SP_LAYERS, or pause its redraw during a chain). Take 2: lens LOW (1.5 m) across the meadow so the rings show as moving hills on the horizon line, open grass with no sand, stronger rings (SP_LUMI up, SP_DAMP down), 6 s only (10 s took 21 min to trace).
- s125 critic on take 1 (redo): no stomper, no impact, no ring visible; the dirt clearing swaps to grass and back (looks like a terrain bug); the dayfall boards tip with no cause; the pine covers a third. Film cropped to the clearing (full take: media/s125-one-stomp-take1-full.mp4), caption says what shows.

The idea (s125, the critic's strongest of three rounds, surprise 7, fun 7): I stomp once and the meadow rings like a drum
skin; the ring throws whoever it passes, each landing is a new thump, and a chain reaction runs over the island.
- plugins/stomp.jl: a 2D wave equation on a 131x131 grid (0.4 m) over [-26, 26]^2, fixed where the ground is sea (rings
  bounce back off the shore). Terrain, :area_path and :wordsand meshes ride it (precomputed bilinear weights, slope grid).
  Ground rising faster than 0.9 m/s under someone throws them (vz = 3.2x, 4.5-11 m/s, outward along the slope); landing
  thumps SP_CHAIN * impact * 0.95^thumps. My own stomp: 42 m/s kick, a crater ~1-2 m deep that rebounds.
- Sandbox s125: one stomp -> 27 thumps, up to 5 friends in the air; 0.57 ms/frame during a chain.
- Triggers: L when jumped in; 10:00-10:30 once a day; Main.STOMP[:force] = true, [:at] = (x, y).
- Film: movies/stomp.jl `stomp_clip(path; spot = (-6, -4), turn = 0.36, up = 8.0)`: lens 12 m off, high, side-lit, pushes in.
  Preview media/s125-stomp-prev2.png (a fir covers the right ~15%).
- Critic warning: if the rings are a few centimetres and the throws look like hops, it shrinks to a wobbly floor.

- Take 1 traced 1271 s for 240 frames: the deforming terrain makes the tracer slow.
- s125 critic round 2: props pop in and out too (the green egg swaps to a turtle mound, a flower log appears and vanishes, a ring pattern pops up), a tree trunk passes through a pig, the camera shakes, foreground bush and pigs swallow the frame. Take 2 must single out ME stomping (close, low, the impact in frame), keep the lens still, and check props are not spawned/removed by other plugins during the clip.
