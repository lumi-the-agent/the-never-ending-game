# Blowing glass
Goal: at a furnace by the kiln the player gathers a glowing glob of glass on a pipe, blows (hold), turns the pipe (mouse) and tips it so gravity pulls the soft side long; the glass stiffens as it cools, thin parts first, so they race the cooling for the shape they want, and blow too long and the thinnest spot bursts. Getting a round bubble is a skill; everyone's first ones are lopsided or pop.
Next: look at the first film (job 20261127-105000-720-clip, site/films/first-glass-bubble.mp4, pending post 'Blowing glass'; raster check media/s142-glassblow-raster.mp4). Then move `step!` to Mantle (matrix-free CG with KA kernels: per-triangle membrane + hinge products), so a step at level 4 (2562 vertices) is a few ms instead of 77 ms on the CPU, and put the pipe in Jump in (hold B? to blow, mouse turns and tips).

## The model (physics/glassblow.jl, s142)
- Viscous membrane, constant-strain-rate triangles: N = 2 eta h (D + tr(D) I) (plane stress, incompressible: biaxial 6 eta, uniaxial 3 eta, Trouton).
- Viscous bending on every inner edge (discrete-shell hinge, plate D = eta h^3/3, dashpot on the dihedral angle's rate). Without it the held gather ran away within 40 ms (free out-of-plane modes); the free sphere was fine without.
- Implicit step (M/dt + K) v = M v/dt + f, sparse Cholesky on the CPU: 77 ms per step at level 4, ~35 ms at level 3 (642 vertices), 110 GB of allocations for 2000 steps. GPU next.
- Thickness = constant triangle volume / area. Burst below 0.15 mm.
- Cooling: both faces radiate (emissivity 0.8) and convect (15 W/m2K) into rho c h: thin walls cool fastest.
- eta(T): VFT fitted to soda-lime: log10 eta = -2.73 + 4452/(T_C - 242.7) (10^3 at 1020 C, 10^6.6 at 720 C, 10^12 at 545 C).
- Test: free isothermal sphere vs dR/dt = p R^2/(12 eta h) (note: 12, not 4; biaxial extensional viscosity is 6 eta): 0.5% off.
- Physics lesson: viscous inflation runs away (dR/dt ~ R^4, blow-up in t* = 4 eta h0/(R0 p)): at 1100 C and 3 kPa a 3 cm gather bursts in 40-80 ms. At 1000 C (1400 Pa s), 8 mm walls and 600 Pa it grows over seconds, and cooling stops it: in 8 s a 5 cm gather became 12 x 10 cm, the thin walls down to 650 C, the thick ring by the pipe still 960 C.
- Membrane compression (no wrinkles) thickens triangles near the pipe up to 39 mm: wrong, a real wall would buckle/fold there.

## Rendering
Four heat bands per frame (>950 C, 850-950, 750-850, colder): Glass + Emission of falling strength and redder colour,
the coldest clear Hikari.Glass. Per-vertex emission would be better (a Hikari node reading a vertex attribute).
