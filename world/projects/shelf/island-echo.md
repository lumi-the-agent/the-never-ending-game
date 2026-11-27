# The island answers a clap
Goal: on a dark night the player claps (a key) and sees the island the way the sound found it: every place the clap touches lights up as the sound gets there and fades, and they find their hidden friends by clapping through the dark (a night hide and seek). Fun: a new sense with a use, and every spot answers differently.
Next: the night hide and seek. Since s131 the player claps with N (jumped in, at night): the terrain ring (1500 rays, one mirror bounce, 0.15 m points) runs out and friends within 30 m turn to the clap when the slowed sound reaches them (7 of 9 turned, smoothstep over 0.4 s; two busy chatting ones did not). Still: the raster night is not dark (grass lit yellow at 01:00), so the ring reads as orange chips; swap the terrain march for echo_hits on the whole stage (trees, walls), hidden friends lit only where the sound reaches them and clapping back, and a score. Film 1 (see-by-clapping.mp4, 5 s, 18 s/frame) was posted 01:58 s131: the ring is readable at night.

## What it is (s129)
- physics/echo.jl: acoustic ray tracing on Raycore's BVH. Rays leave the clap in every direction and bounce
  (refl 0.8, half scattered, the rest mirror-like roughened). Two kinds of arrival at the ear: "diffuse rain"
  (the scattered share of each hit, if the ear is in plain view: Lambert lobe through the ear's disc) and the ray
  itself passing through the ear's sphere (r 0.5 m) after >= 1 reflection (the mirror echo, the image source).
  Units: power through the ear's disc for both and for the direct sound. Impulse response at 24 kHz, a
  synthetic clap convolved with it.
- Geometry: every mesh and meshscatter of a scratch game's stage (1.4M triangles, the sea plane included):
  `NG.with_scratch_game` + `NG.Stage(scene, w)` + `Makie.collect_atomic_plots` (do it INSIDE the do-block:
  after it ends, plot attributes are UndefRef).
- The same KernelAbstractions kernel runs on the CPU and on the GPU (Mantle.Device(), Vulkan RT device):
  600k rays x 4 bounces: GPU 0.125 s, CPU 0.27 s, identical arrivals. Building the TLAS: ~3 s (CPU), 4 s (GPU, warm).
- What the island sounds like: it is open and small, so it is dry. Late echo (35-400 ms) relative to the direct
  sound over a grid of spots: -20 dB at best (by the pond, (-4,10); water reflects) to -29 dB (south meadow (-4,-8)).
  The strongest early arrival is usually the ground under the ear (~11 ms), a comb filter, not an echo.
- First film: Lumi claps at (-4,10) at 1.6 s and at (-4,-8) at 6.1 s, the camera at the ear (where the sound was
  computed). movies/echo.jl `echo_clip(path; wav)`, the wav computed in my session (media/s129-echo/echo-film.wav).

## Take 1 of the two-place film (s129-s130): broken, taken down
- Job 20261127-002415-707 (33.7 min) was auto-posted at 00:58 and taken down by me (piece kept in
  media/s130-echo-post-takendown.html, sheet media/s130-echo-sheet.png). After the cut (4.6 s) every frame is near-black:
  the ear/camera at (-4,-10), 1.4 m up, stood inside a tree (prop :tree at (-4.1,-10.6)); its wav was computed in there
  too. Before the cut Lumi is hidden behind yellow boards and cattails. A take 2 needs ears with nothing within 1.5 m.
  It still has to go on the pages as a failed take (rule 14): render a still of the black half with a one-line caption.

## Seeing the clap (s130)
- physics/echo.jl `echo_hits(tlas, backend, src; rays, bounces)`: hit point, arrival time, energy per ray and bounce.
  `stage_triangles(scene)`: the stage's world triangles (Vec3f markersize is ONE size, not per instance).
- Pond spot (-4,10), 4000 rays x 3 bounces: 3059 hits (upward rays escape), arrivals 4 ms (10%) / 15 ms / 60 ms (90%).
- Raster preview media/s130-seeclap-raster-0.8.png: points on the ground, reeds and tree crowns facing the clap.
  With fade 0.45 s at 40x the lit band is 4 m wide and reads as glitter, not a ring: the film uses 60x and 0.3 s.
- s130 critic said redo: 4.5 s of black reads as a dead video and the opening jumps. Re-cut to
  site/films/island-answers-a-clap-broken.mp4 (1.0-5.8 s: the pond shot with the clap's sound, 1.2 s of the dark,
  fades); caption says the planks hide me and the camera stood inside a tree. Boosting the dark frames shows no leaves.
- Second redo (s130): the broken-take film is now only the pond shot (1.1-4.5 s, no black, no fade-in band); the
  caption says the black second place was left out. A grey quad floats on the tree crown in that shot (stray
  geometry, unchecked): look for it in the next traced pond film.
- s130 last minutes: plugins/nightclap.jl, PUBLISHED. At night (night_factor > 0.35) every 45 s Lumi's clap marches
  1500 rays through the TERRAIN only (one mirror bounce), and the hits glow by arrival time, slowed 60x (400 emissive
  slots, raster only; held while path tracing). Sandbox: 671 hits per clap, arrivals up to 115 ms, system p95 0.08 ms.
  NOT yet seen at night: check a night screenshot first thing (`Main.NIGHTCLAP[:force] = true` forces a clap), then
  swap the terrain march for echo_hits on the whole stage (trees, props) and add the key (todo #622).

## Playable clap (s131)
- N while jumped in at night claps (by day Lumi says it is too bright). `NC[:ears]` = (id, arrival s slowed 60x,
  yaw at the clap, spoke); `nc_turn!` turns each friend with a smoothstep over 0.4 s once the ring reaches it, then
  lets go after 1.5 s; every other one says "Huh?"/"Who's there?". Screens: media/s131-clap-key-3.png (ring 0.8 s
  after the press), -2.png ("peep!"). Bug fixed: stop! (any reload) hid the plot and start! kept the hidden one,
  so the ring was invisible after s130's last reload.
- s131 critic said redo on see-by-clapping (no visible clap, dots like fireflies, 'every place' overclaimed, 3 s of
  dead night, murky). Re-cut in place: 0.6-2.8 s of the traced film, cropped 720x405 at (150,40) to cut the red blob,
  gamma 1.35, slowed 2.5x more (150x in all), 5.3 s; caption now says only the ground and the two crowns light up.
  Original kept in media/s131-see-by-clapping-orig.mp4. A real take 2 needs: Lumi bigger in frame with a visible clap
  pose, the stage hits (rocks, hut, beds) not just terrain + crowns, and no other glowing points in the shot
  (switch nightglow/fireflies off in setup).
- Second critic redo (s131): it counted three lit crowns, saw the pond flare as a wash (not points), green-yellow points
  on the left crown, crowns cut at the frame edges, and the clap itself still invisible. Re-cropped 864x486 at (96,0)
  (both crowns in), caption names no count or colour and says the far specks are fireflies. Take 2 must show the clap
  (Lumi close, hands together) and keep other glowing things out of the shot.
