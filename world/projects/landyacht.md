# Land yacht with a dynamo on its axle
Goal: the player sails the bare cart along the beach with the friends aboard, trimming a patched sail against the wind (too tight: the flow tears off and it stalls; too loose: it luffs; right: it heels onto two wheels and runs faster than the wind), and switches Lumi's motor, run backwards on the axle as a dynamo, in to brake and charge the clay-pot cells, or out to fly; at dusk the sail comes down and the cart drives home on what the sailing stored. Speed now or charge for the evening, every day a different wind. (Strongest idea s162 after 3 rounds: surprise 8, fun 8, real 6, toward 8.)
Next: converge the cambered sail with LONG runs (20+ chords, average the last 10, report the spread; a :run job) at chords 32 and 48, against Pelletier & Mueller 2000 cambered-plate data, until zero lift and slope agree; then a cloth sail (VBD) whose shape is the next body in the flow, and the box riding with the cart.

## The critic's risks (s162)
- A frozen lookup for the sail, or a dynamo that is only a drag number with a charge bar: then it is a rig.
- The stack is big (cloth + flow box on a cart + wheels + belt + motor + circuit + cells): build it in steps that each play.

## Parts that exist
- physics/groundwind.jl (WaterLily 3D, GPU on Mantle since s162: 5 ms/step at 262k cells)
- physics/wheelsand.jl, sandfield.jl (wheels and feet in sand), motor.jl (drum rotor; run backwards = dynamo), circuit.jl, potcell.jl
- assets: plank 20261128-021035-918-asset, board wheel 20261128-021036-051-asset

## s162 step 1: a flat plate in the solved flow (physics/sailflow.jl)
Plate 16 x 32 x 2 cells (aspect ratio 2), box 128 x 64 x 64, Re 2000, GPU (Mantle) == CPU (CL 0.31294 vs 0.31293).
Averaged over chords 6-10 of wind; force = MINUS WaterLily.pressure_force (it returns the force on the fluid).
  alpha  0    5    10   15   20   25   30   40   50   60   75   90
  CL   0.00 0.13 0.23 0.30 0.53 0.58 0.68 0.73 0.77 0.78 0.49 0.00
  CD   0.12 0.11 0.17 0.21 0.33 0.42 0.55 0.82 1.11 1.47 1.74 1.77
Lift rises, peaks broadly at ~50-60 deg and falls; drag grows to broadside: the stall comes from the flow, nothing
fitted. Low aspect ratio plates stall gently like this (tip vortices). BUT: lift slope ~1.45/rad, about half of
low-AR theory (Helmbold, A = 2: 2.6/rad), a jump 15 -> 20 deg, CD at 90 deg 1.77 (vs ~1.2): coarse chord (16
cells), blunt 2-cell plate (12% thick), 12% blockage, short average. 12 angles took 33 s on the GPU.

Finer grid (chord 24, span 48, box 192x128x96, 9% blockage): CL 10/20/40 = 0.22/0.50/0.89, CD 0.13/0.28/0.85.
High angles moved towards measured AR-2 plates (CLmax ~0.9-1.0 near 40 deg); the small-angle slope did not
(Re 2000 and the blunt plate, not the grid). 3 angles 41 s.
CAMBERED arc, 10% deep to leeward (+y), chord 16: CL at -10/-5/0/5/10/20/40 = -0.17/-0.12/-0.01/-0.01/0.13/0.40/0.60.
Zero lift at about +5 deg: it acts like a sail bent the OTHER way, and gives less lift than the flat plate.
The sdf is right (checked on the arc, ends, below, past the span), the lift sign is pinned by the flat plate's
drag. Suspects: a 2-cell band is 12% thick and the concave side is under-resolved; the leading edge meets the
flow at -22 deg (10% camber) and separates on the pressure side at Re 2000.
MOSTLY RESOLUTION: the same arc at chord 32 (box 256x128x128, 6% thick): CL at -5/0/5 = 0.011/0.012/0.149,
CD 0.056/0.050/0.060: the curve moved up by 0.13-0.15 and zero lift is now near -5 deg (the right side for a
sail bent to leeward). Not converged: thin-airfoil theory says -11.5 deg for 10% camber, and -5..0 is flat.
3 angles x 8 chords took 62 s. FOR THE GAME: a sail needs >= 32 cells per chord (~4M cells), too heavy per frame:
re-solve the sail force a few times a second in the background (quasi-steady), the cart integrates every frame.
Chord 48 (box 320x160x160, 8.2M cells, 171 s for 3 angles): CL at -5/0/5 = -0.098/-0.022/0.167, CD 0.043/0.036/0.040.
NOT CONVERGING: 16 -> 32 -> 48 cells per chord gives CL(-5) -0.12 -> +0.01 -> -0.10. The averages are only 3-4
chords long and start at 3-7 chords: the starting vortex and the unsteady separated flow are still in them.
The camber result is NOT trustworthy yet; the flat plate's broad stall is. Long runs first (20+ chords, average
the last 10, report the spread), as a :run job on the worker.
QUEUED s162: job 20261128-040140-400-run (tools/sail_converge.jl, CPU, chords 32+48, -10..10 deg, 24 chords, ~2 h): read its result first.
