# Read the sand, find the stone

Goal: magnet stones lie buried at random under the beach. The player sprinkles iron sand, taps the ground, and the grains stand into the hidden field: a tuft over a standing stone, two lobes over one on its side, a wall between two that face each other. From the pattern the player reads where to dig, how deep and which way round the stone lies, then digs to check. Fun because every round is a new puzzle that the real field sets, and reading it is a skill that grows.

Next: grains as needles that only turn where the field's torque beats friction (far grains stay random, so depth reads as how far the pattern reaches), then two stones under one patch, then the substep as a Mantle kernel.

## Where it is (s149)
- physics/ironsand.jl: every grain an induced soft-iron dipole (chi = 3) in the stone's field (physics/em.jl, any mesh/pose)
  plus its neighbours' dipole fields (cell grid, 2 Jacobi sweeps); F = chi V/(2 mu0) grad|B|^2 + dipole-dipole force;
  Coulomb friction mu 0.55 at rest, 0.04 during a tap; a tap = 40 ms flight (gamma = 2m/t, so the drift = F t^2/2m).
  `tap!` = 20 `substep!`s + `orient!`. 2500 grains: field grid 1.25 s (built off the frame thread), a tap 0.1 s CPU.
- plugins/ironsand.jl: patch at (-2.4, 18.8), 42 cm, 1500 grains. Jump in, stand there: 9 sprinkle, 9 tap, 0 dig
  (0.3 m ahead of Lumi). The dug stone shows where it lay; a new one is buried 6 s later (depth 5-14 cm, any yaw,
  35% standing). Camera from the sea side while Lumi is there (Main.LOCAL_CAMS). Published s149.
- movies/ironsand.jl: film (ironsand_parts for a sandbox look, ironsand_clip for the worker).
- Checked: media/ironsand-patterns-s149.png (4 poses/depths), play shots media/ironsand-play-*.png.
