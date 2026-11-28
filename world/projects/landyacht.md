# Land yacht with a dynamo on its axle
Goal: the player sails the bare cart along the beach with the friends aboard, trimming a patched sail against the wind (too tight: the flow tears off and it stalls; too loose: it luffs; right: it heels onto two wheels and runs faster than the wind), and switches Lumi's motor, run backwards on the axle as a dynamo, in to brake and charge the clay-pot cells, or out to fly; at dusk the sail comes down and the cart drives home on what the sailing stored. Speed now or charge for the evening, every day a different wind. (Strongest idea s162 after 3 rounds: surprise 8, fun 8, real 6, toward 8.)
Next: (s164, todo #763) READ job 20261128-053315-216-run (3D AR 4 chord 48) and settle sail_slices vs the 3D box; the cart is ON THE BEACH now (plugins/landyacht.jl, static): translucent canvas so it glows backlit, then yarns (physics/telltale.jl, 0.1 g, stepping with the slices' flow) tied at 3 heights, the sail's solved force pushing the cart over the sand (wheelsand.jl), sheet keys in Jump in; traced film from leeward for the post.

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
s164 READ job 20261128-045120-189-run (CPU, AR 4, 20 chords avg last 10, spread between 2-chord windows < 0.01):
  chord 24: 0/2.5/5/7.5 deg CL 0.060/0.109/0.190/0.211 (CD .082/.068/.094/.107)  smooth, no knee
  chord 32: 0/2.5/5/7.5 deg CL -0.002/0.061/0.229/0.280 (CD .051/.051/.066/.065)  KNEE between 2.5 and 5:
  0.025/deg below, 0.067/deg across, 0.020/deg above. THE TALL SAIL LUFFS IN 3D at 32 cells per chord (24 smears it,
  as 2D needs ~32 too). Smaller than 2D's jump (0.17 vs ~1.0): downwash + Re 2000, but it is a knee, not a slope.
And job 20261128-040140-400-run (AR 2, 24 chords avg last 10): chord 32 -10/-5/0/5/10: -0.113/0.015/0.004/0.151/0.233;
  chord 48: -0.147/-0.096/-0.030/0.165/0.343. Long averages: 32 vs 48 agree within 0.04 at 0 and 5, not at 10 deg.
SO: the trim window of a tall cambered sail at this Re is ~3-4 deg wide in the flow itself. Box must be >= 32/chord.
s164 TELLTALE PROBE (GPU, AR 4, chord 32, 14 chords, sample last 4; velocity 2.5 cells off each face, mid-span and
half-span alike; code in the s164 eval, to become physics/sailflow.jl `telltales`):
  2.5 deg (CL 0.06, luffing): LEE streams at all stations (ut 1.04-1.16, yarn -4..0 deg); WINDWARD at 5% chord
  ut 0.02, un 0.04: the yarn STANDS OFF the cloth at 60 deg; from 15% back the windward flow is reversed (a slow
  bubble inside the curve, ut -0.06).
  5 deg (CL 0.23, drawing): lee streams; windward 5% ut 0.25, yarn LIES DOWN to 16 deg; 15%+ still reversed (weak).
THE WINDWARD LUFF TELLTALE LIFTS WHEN THE SAIL LUFFS, by itself, as sailors read it (pinching = windward one lifts).
Steady flow at Re 2000 (min ~ mean): threads point, they don't flutter. Put the telltales at <= 5% chord.
  More angles (yarn angle off the cloth at 3% chord, mid-span; + = standing off):
    alpha   0     2.5(5%)  5(5%)   10     20     30     40
    wind   +29    +60      +16     +15    +5     +6     -1
    lee     -7     -5       -3     +1     +14    +28    +40
  At 30 deg the lee flow is REVERSED at 30% chord (a bubble under the lifting yarn); at 40 it is unsteady there
  (27% of samples reversed): the stall, and the first flutter in the whole sweep. Tips (80% half-span) lift less.
  THE TRIM GAME IS IN THE FLOW: too loose = windward yarn stands off, right (5-10) = both lie down, too tight = the
  lee yarn lifts, then flutters. physics/sailflow.jl `telltales` (s164). NEXT: yarns as rods (drag ~ |u|^2 from
  the sampled flow + gravity: limp in the slow bubble, streaming in the fast side), then the sail box on the cart.
s164 PASSED idea 'Wool on the sail: trim the land yacht by its telltales' (critic: surprise 7, fun 7, real 7, toward 8;
risk: the box not keeping up -> threads lag -> canned table). MEASURED the lag the same session:
  TRIM RESPONSE (box 192x96x192 = 3.5M cells, AR 4, chord 32): sheeted 2.5 -> 7.5 deg at 8 chords (body re-measured,
  4.5 ms): windward luff yarn 60 deg -> 31 (0.12 chord) -> 11 (0.23) -> 4 (0.34, overshoot) -> settles ~12 by 0.6 chord.
  The threads answer the sheet within HALF A CHORD of wind: 0.25 s for a 2.5 m chord in 5 m/s. Fast enough to play.
  COST: 39 ms/step, 57 steps per chord = 2.24 s GPU per chord: 4.5x SLOWER than real time (needs ~0.8M cells).
  2D SLICE at chord 32 (256x128 = 33k cells): CPU 1.0 ms/step = 0.053 s per chord (10x FASTER than real time);
  GPU 2.5 ms/step (launch overhead dominates tiny boxes). 2D at 32 already luffs (s163).
  => PLAN: three 2D slices of solved flow (foot / middle / head) on CPU threads, each with its own apparent wind
  (wind grows with height over the sand = real twist; cart speed subtracted), coupled by lifting-line downwash from
  their own solved lift (Prandtl: the slices' CL sets the induced angle each sees). A row of telltales at each
  height, as sailors rig them. Check the coupled slices against the 3D AR-4 numbers (knee 2.5->5, CL 0.23 @ 5).
Lava bug found s164 (todo filed): an sdf closure doing `t < ts ? r1 : r2` on two captured Float32 fields fails to
  compile (byte-offset GEP on a phi of field addresses, emit.jl:3516); `r1 + dr * (t >= ts)` compiles.
s164 BUILT physics/sailflow.jl `sail_slices` (+ arc2d_sim, retrim!, slice_cl!): N 2D slices of solved flow (CPU, chord 32,
  256x128, thick 3) joined by Prandtl's lifting line (Glauert series, all N terms), relaxed 12 rounds x 1.5 chords,
  each slice re-trimmed in its running flow to alpha_geo - alpha_induced. ~6 s for a whole sweep point incl. warm-up.
  alpha 0/2.5/5/7.5/10:  3 slices CL -0.121/0.136/0.380/0.558/0.806 (mid induced -0.8/0.75/1.25/2.2/3.2 deg)
                         5 slices CL -0.124/0.126/0.376/0.560/0.832   -> converged in N
                         3D AR-4 box -0.002/0.061/0.229/0.280/0.325
  DISAGREE by ~2.5x in slope: slices ~0.10/deg, 3D box 0.033/deg, lifting-line theory for AR 4 ~0.073/deg.
  The 3D box has given about HALF of theory before too (flat AR 2: 1.45/rad vs Helmbold 2.6). 2D at chord 32 flat
  10 deg 0.35 vs 0.54 at chord 128 (s163): 2D at 32 is low too, yet the slices come out ABOVE theory (camber).
  OPEN: which is right at Re 2000? Next check: the flat plate through sail_slices vs the 3D flat AR-4 box vs
  Helmbold; the 3D box at chord 48 for AR 4 at 5 deg (one case, :run job); the 3D box's tip gap (32 cells) and
  blockage (y 128 = 4 chords). Don't put either number on the cart until they agree within ~20%.
  FLAT PLATE both ways (s164): slices (3, flat 2D sections, round ends) CL 5/10 deg = 0.266/0.534; 3D flat AR-4 box
  (256x128x192, thick 2, 14 chords avg 6, GPU 2.2 min) 0.200/0.362. Box/slices = 0.75/0.68 flat, 0.60/0.40 cambered.
  The 3D box is lower in both; the gap is bigger with camber (the 3D knee is weaker than the 2D one). Classical AR 4
  with the slices' own 2D slope (~0.06/deg) would give ~0.05/deg: the slices sit near theory, the box below it.
  QUEUED: job 20261128-053315-216-run (CPU, AR 4 arc, chord 48, 2.5/5/10 deg, 20 chords avg 10): if the box CL rises
  towards the slices at 48 cells, the 3D box was under-resolved and the slices are the game's sail; if it stays, the
  missing lift is real 3D low-Re physics and the slices need it (then: why). READ IT FIRST next session.
s164 late: physics/telltale.jl (module Telltale: Yarn, hang, step!, lift_deg): a wool yarn as an 8-segment Verlet
  chain, gravity + cylinder drag across (Cd 1.2) and along (0.06) from a flow function, inextensible. FIRST TEST
  (2D slice snapshot frozen after 10 chords, 2.5 m chord, 5 m/s, yarn 15 cm / 2 mm / 0.3 g tied 4 cm off the cloth
  at 5% chord; lift_deg 0 = hanging, 90 = level):  0 deg lee 99 / wind 5;  2.5 lee 19 / wind 0;  7.5 lee 73 / wind 3.
  NOT YET A RESULT: (1) the 2D slice sheds, a frozen snapshot can catch it mid-cycle: step the yarn WITH the flow;
  (2) at 0.3 g the windward yarn hangs at every trim (its air is 0.05-0.44 U in the curve: drag/weight < 0.4);
  real telltales are lighter (0.05-0.1 g, or cassette tape): try 0.1 g; (3) no collision with the cloth yet.
  In 5 m/s full stream: drag/weight ~1.9 at 0.3 g -> ~62 deg, so the lee yarn streaming 73-99 deg is plausible.
s164 END: plugins/landyacht.jl PUBLISHED: the bare cart parked on the beach edge by the beach hut (first dune grass +
  (-5, 0.4), ~(-1.5, -15.5)): 5 driftwood planks (asset 918) as a 2.4 x 1.25 m deck, 4 oak board wheels (asset 051,
  0.7 m), a plank mast, the 10% arc sail (chord 1.2, 2.8 m tall, sheeted 18 deg) in canvas Diffuse. Static. 0.0 ms/frame.
  Raster: media/s164/yacht-raster-2.png. LOOKS: wheels + deck read well; the SAIL reads as a flat grey slab (no
  seams, curve invisible side-on), ground still grassy there. NOT TRACED YET. Before any post: canvas texture with
  panel seams + a darker luff tape, a 3/4 view from leeward that shows the belly, check on sand, traced still.
s164 LAST: the sail got a canvas texture (plugins/landyacht.jl ly_canvas: 5 crosscut panels with double seams, brown
  tapes on all edges, one patch over a tear), uv on the arc mesh; published. Raster 3/4 from leeward:
  media/s164/yacht-raster-3.png (reads as sailcloth, the belly shows). TRACED (sandbox, 25 s):
  media/s164/yacht-traced.png: the shaded side comes out OLIVE (sky + grass bounce on a Diffuse sheet facing away from
  the sun). Try a thin translucent cloth (diffuse transmission) so a backlit sail glows with its seams dark: goal 7.
