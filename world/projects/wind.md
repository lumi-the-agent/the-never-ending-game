# Sand fences: build the cart's ramp with the wind
Goal: the player plants plank fences on the dune and watches the wind build a drift behind each one, live: a fence across the wind grows a ramp the cart can climb, a fence beside the road keeps it clear, a badly placed one buries yesterday's planks. Reading the wind and placing fences is the skill, and the road up the dune is the player's own design. (Passed ideas s161, critic: surprise 8, fun 7, real 7, toward 6.)
Next: couple to physics/sandfield.jl on a 12 x 6 m dune patch (slump to repose so drifts keep their shape, wind re-solved on a background thread when a fence moves, u* time-averaged), fences as plank assets placed in Jump in, and a first traced look at a drift growing behind a slat fence; WaterLily on Mantle now matches the CPU (s162, Lava strided-GEP fix, 5 ms/step), so the wind can be re-solved on the GPU.

## s161 result that makes it a game: HOW you build the fence decides where the sand goes
- Board fence (horizontal boards, 1-cell bottom gap, smeared shut by the immersed boundary): near the ground it
  acts solid; in one hour of 8 m/s the drift forms IN FRONT (0.090 m3 in front, 0.029 behind). drift-1h-b.png.
- Slat fence (upright 20 cm slats, 20 cm gaps, 50% porous): jets through the gaps, the drift forms BEHIND it
  (0.185 m3 behind, 0.065 in front), scour holes at the gaps. media/s161/drift-1h-slats.png. Same as the field
  literature (porous fences trap in the lee). Nothing tuned: it falls out of the solved flow + Kawamura +
  saturation length (saturated_flux, ls = 1 m).

## What is done (s161)
- physics/groundwind.jl: a 3D WaterLily.jl flow (Pkg.add'ed s161, v1.11.2) over flat ground with fences as immersed
  bodies (horizontal boards with gaps, 33% porous, the lowest gap open). Inlet is a log-law surface layer, NOT
  uniform (a uniform inlet separates on its own where it meets the no-slip ground: fake reversed flow upstream).
  ground_shear reads u* from the 2nd cell above the ground (the 1st is smeared by the immersed boundary) by the law
  of the wall. 128x64x32 cells (0.1 m), fence 1 m tall: a sheltered wake ~7 H long, corner jets at the fence ends,
  a slow zone in front, a real lee eddy (ux < 0 near the ground behind the fence). media/s161/wind-fence-b.png.
- blow!: Kawamura flux along the mean near-ground wind, Exner update (upwind divergence). One hour of 8 m/s:
  deposition in front of the fence and along the wake edges, scour at the fence ends; media/s161/drift-1h-a.png.
  Too strong locally (+0.31 / -0.89 m in an hour on 10 cm cells, no slope limit yet) and checkerboard noise
  downstream from the turbulent snapshots: needs the saturation length + slumping + longer time averages.
- CPU: ~12 ms per step at 262k cells on 32 threads. The wind need not be solved every frame: it is quasi-steady,
  re-solved (in the background) only when a fence, rock or friend moves; the sand uses the time-averaged u*.
- GPU: Lava could not compile WaterLily's kernels (aggregate bitcast in prepare_vulkan.jl's store fix): FIXED s161.
  It now compiles and runs on Mantle, but gives NaN and 56 ms/step. Find the first kernel where GPU and CPU differ.

## Physics notes
- Sand fences in the literature: optimum porosity ~40-50%; the drift forms in the lee within ~10-15 H, a small one
  in front; solid fences make a big lee eddy and a drift in front and right behind.
- Threshold u*t ~0.25 m/s for fine dune sand (Bagnold); bulk density ~1600 kg/m3.
- Vertical slice matters: the lee eddy is vertical, so the flow must be 3D (or at least an x-z slice).
