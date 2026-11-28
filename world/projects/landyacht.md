# Land yacht with a dynamo on its axle
Goal: the player sails the bare cart along the beach with the friends aboard, trimming a patched sail against the wind (too tight: the flow tears off and it stalls; too loose: it luffs; right: it heels onto two wheels and runs faster than the wind), and switches Lumi's motor, run backwards on the axle as a dynamo, in to brake and charge the clay-pot cells, or out to fly; at dusk the sail comes down and the cart drives home on what the sailing stored. Speed now or charge for the evening, every day a different wind. (Strongest idea s162 after 3 rounds: surprise 8, fun 8, real 6, toward 8.)
Next: (s163 PASSED idea 'Telltales: trim a tall sail whose flow is solved in 3D every frame') read media/s163/tall-sail-3d.txt (AR 4, chord 32, 0/5/10/15 deg): if the luff shows in 3D, put the sail box on the cart and step it EVERY frame (2.5 m chord, 4-6 m/s breeze, 2-3 steps of 5 ms a frame, time it with the friends on screen), apparent wind as the inflow, sheet angle turns the body; wool threads advected in the 3D field at the luff; sheet in/out in Jump in. If AR 4 also loses the luff, find why (Taira & Colonius 2009 AR-2 flat plate as the 3D check) before building on it.

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
s163 free time, NOT LEAKAGE: WaterLily's kernel is 1 cell wide (eps = 1) and its own test plate is 4 cells thick, so
a 2-cell plate might be a sieve. Tested at chord 32 (GPU, game env /sim/Programmieren/SimGame, 10 chords, avg last 4):
  thick 2 / 3 / 4: flat 10 deg CL 0.29 / 0.32 / 0.26 (CD 0.11/0.16/0.17); arc 0 deg CL 0.009 / -0.031 / 0.025.
Thickness does not move it: the arc at 0 deg gives NO lift at any thickness. (Theory for AR 2 inviscid: ~0.5.)
So the s162 job (thick 2) still answers the grid question. Next check: 2D at chord 128 (below).
2D, chord 128, box 1024x512, thick 3, Re 2000, 20 chords avg last 10 (GPU, 4.5 min for 7 cases):
  flat 0/10: CL 0.00/0.54 (CD 0.008/0.113).  10% arc -10/-5/0/5/10: CL -0.53/-0.38/-0.09/0.96/1.38 (CD .18/.11/.06/.07/.16)
THE SAIL LUFFS BY ITSELF: between 0 and 5 deg the arc JUMPS from no lift to 0.96 (1.8x the flat plate). At <= 0 the
wind meets the sharp luff from the lee side and the flow tears off INSIDE the curve (a luffing, backwinded sail);
a few degrees more and it attaches. That is the trim game ("too loose: it luffs") from the flow, nothing fitted.
WHY 3D DID NOT CONVERGE: the AR-2 sail's downwash takes a few degrees off (alpha_i ~ CL/(pi A)), so in 3D the jump
sits higher, and the -10..10 sweeps straddled the knife edge; tiny grid changes flip luffing/drawing.
2D resolution: chord 32 already luffs (arc 0/5/10: -0.21/0.60/1.27; flat 10: 0.35), chord 64 (-0.19/0.95/1.32; flat
0.50). So 32 cells per chord resolves the luff in 2D.
3D, chord 32, AR 2 (span 2 chords), thick 2, 14 chords avg last 6 (5 min on the GPU): arc 5/10/15/20/25/30:
CL 0.14/0.23/0.38/0.45/0.48/0.52 (CD .06/.07/.11/.19/.25/.29). NO JUMP, and at 10 deg less than the flat plate (0.29).
The short AR-2 sail loses the camber's gain: its tip vortices' downwash differs along the span, so sections attach
at different angles and the jump smears out. Physics or numerics: not known yet (Taira & Colonius 2009 for flat AR 2).
NEXT: a TALL sail (AR 4, like a real land yacht's; span 128 at chord 32, box z 256) at 0/5/10/15: does the luff come
back in 3D? Then the sail stepping EVERY frame in a box riding with the cart (no background refresh, the critic's lag
worry): at 5 ms/step for 262k cells, a 2.5 m chord in a 4-6 m/s breeze keeps real time at 2-3 steps a frame.
TALL SAIL AR 4 in 3D (chord 32, span 128, box 256x128x192 = 6.3M cells, 14 chords avg last 6, 4.5 min for 4 angles
= ~4.8 s of GPU per chord of wind): arc 0/5/10/15: CL -0.002/0.225/0.325/0.472 (CD .051/.066/.084/.135).
Better than AR 2 (0.14/0.23/0.38) and a HINT of the luff (0->5 rises 0.045/deg, 5->10 only 0.020/deg), but far from
2D's jump to 0.6-0.95. Still open: physics (3D, Re 2000) or numerics. Try next: longer average + 2 resolutions of the
AR-4 sail at 0/2.5/5/7.5; span-wise CL (does the middle luff and attach like 2D while the tips smear it?).
REAL TIME IS NOT THERE YET: 6.3M cells cost ~4.8 s of GPU per chord of wind; a 2.5 m chord in 5 m/s wind passes in
0.5 s, so this box runs ~10x slower than real time. Options: 2D at 16/24 cells (does it still luff?), a box hugging
the sail, coarser away from it. Measure before promising a frame rate (NOTES s163).
QUEUED s163 end: job 20261128-045120-189-run (CPU, AR 4, chords 24+32, 0/2.5/5/7.5 deg, 20 chords avg last 10):
reads whether the tall sail's weak 3D luff holds at two grids. converge() has aspect = 4 now.
OLD NEXT: 3D sweep 5..30 deg at chord 32 (done above); hysteresis (ramp alpha up vs down: does a drawing
sail stay drawing below the jump?); TELLTALES: threads at the luff from the solved flow, streaming on both sides
when trimmed right, the lee one lifting when it luffs: how the player reads the trim without a gauge.
