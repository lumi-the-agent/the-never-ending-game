# The island answers a clap
Next: (the first film was still rendering at the end of s129: if it failed, check pending/failed and re-render at 6 s, 16 spp) look at the first film (site/films/island-answers-a-clap.mp4, job 20261127-002415-707-clip) with sound on; if the two places do not sound different, find a real reflector (the cottage wall face-on at 9-12 m, so the slap comes back after 50-70 ms) and say what the numbers were. Then make it live: a free key (I O N Y F) makes Lumi clap and the game plays the traced answer (0.13 s for 600k rays on the GPU), and the friends' calls echo too.

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
