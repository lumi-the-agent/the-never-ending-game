# Land yacht with a dynamo on its axle
Goal: the player sails the bare cart along the beach with the friends aboard, trimming a patched sail against the wind (too tight: the flow tears off and it stalls; too loose: it luffs; right: it heels onto two wheels and runs faster than the wind), and switches Lumi's motor, run backwards on the axle as a dynamo, in to brake and charge the clay-pot cells, or out to fly; at dusk the sail comes down and the cart drives home on what the sailing stored. Speed now or charge for the evening, every day a different wind. (Strongest idea s162 after 3 rounds: surprise 8, fun 8, real 6, toward 8.)
Next: (s168) the course: NO flat 20 m of beach exists (see 'THE ISLAND HAS NO SAILING BEACH'), and the cove above the swash is DRY sand (194 N, more than the sail gives; the published 69 N is firm sand). First projects/stuck.md (todo #773): wheels in the sand field, dig/push/plank, honest soil per wheel. Then the course: the 12 m broad-reach run near (-10,-11.5) yaw 240, a plank track to the wet band, or a tide flat; make tests/landyacht.jl ask for what the island has. Then Lumi seated with the sheet, a traced chase film and a post; then friends aboard.
- s167 IN THE GAME: plugins/landyacht.jl ly_sail!: the server (serve!) starts on boarding in a Distributed worker; channels and the serve call must be made ON the worker (closures of the plugin module Plugin_landyacht cannot be deserialized there; include must return nothing). Parked 2 m on from the old spot (a hollow with a 16% grade held it), bow NW (old bow pointed into the sea 5 m off). Grade over the wheelbase. Run: 8.9 m/s, stalled 61 N stays, alpha 29 drives 133-144 N, 17.1 m, alpha 29->19 as it sped up.

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

## s165: the yacht rolls (offline)
- Free time: moved the cart off the hut (it stood 1.5 m from the hut's middle) to open sand at dunegrass[1] + (-2.6,-1.5),
  tilted to the slope (ly_attitude); canvas is DiffuseTransmission (ly_canvas_through): backlit, the seams and the
  patch go dark, olive gone. Re-rendered the posted still 'my-land-yacht' (job 20261128-061911-575-clip).
- physics/yachtrun.jl `run_yacht`: 1D along the heading. Beam wind 6 m/s, sheet 20 deg = alpha 70 deg (stalled: a
  player must ease out first). Firm sand: it moves off anyway (1 m/s at 1.1 s); dry sand 194 N holds it near still.
  CL from stalled slices swings 1.9-3.7 over 0.5-chord windows (shedding period ~5 chords): a stalled sail pulses.
  Results: media/s165/yachtrun.txt.
- pressure_force is the fluid's side: lift AND drag flip (my first CD came out negative).
- FOUND (s165, media/s165/yachtrun.txt, beam wind 6 m/s, firm sand, 8 s): sheet too tight (alpha 70->35 as it
  speeds up) gives CL 2.3-3.7 and 4.2 m/s; eased to alpha 15 gives CL 1.1 and 1.0 m/s. BACKWARDS from a real sail:
  2D slices keep the stalled vortex street coherent and overstate stalled force ~3x (my 3D AR-2 plate: CL 0.8-0.9 at
  40-60 deg, s162). The game would reward over-sheeting. FIX BEFORE PLAY: spanwise-periodic 3D slabs (span ~1 chord,
  chord 16-24, on the GPU) instead of 2D slices, so the wake breaks up; check stalled CL against the s162 box.
- Speed: 8 s of beach run took ~19 s (2.4x slower than real time, 3 CPU slices, 0.1 s steps).
- WHY (s165, arc 10% camber, alpha 50, chord 16, 2D unless said): domain 4 chords tall (the live slices' size)
  CL 2.48 CD 3.10; 8 chords CL 2.03 CD 2.54; 16 chords CL 1.92 CD 2.37 -> BLOCKAGE adds ~30%: slices need >= 8 chords
  of height. A spanwise-periodic slab (arc_slab_sim, span 1 chord, seeded with w noise, wrms 0.08 alive) gave
  CL 2.53 = the 2D number: the 3D wake is NOT the cause. Left: Re 2000. Laminar, the attached flow at alpha 15 gives
  only CL 1.1 while stalled unconfined still gives 1.9, so trimming right is not rewarded. Next try: the same arc at
  Re 2e4-1e5 (WaterLily implicit LES, finer grid at the sail), alpha 15 vs 50, and the s162 3D box's own blockage.
- Re test (s165, chord 32, 8 chords tall, media/s165/sail-re.txt): alpha 15: CL 1.47/1.67/1.70 at Re 2e3/2e4/1e5;
  alpha 50: CL 2.55/2.58/2.39 (CD ~3). Re barely matters (the grid sets the effective Re), and chord 16 gave 2.03 at 50:
  grid-dependent. Stalled 2D normal force ~4, ~2.7x Fage & Johansen's plate (~1.5): 2D deep stall is the known
  failure (coherent shedding). The 1-chord slab did not break it up in 35 chords at 16 cells/chord. NEXT: a real 3D
  check at 50 deg on the GPU (the s162 AR-2 box said CL 0.8-0.9) with a span of 2-4 chords and long averaging; if 3D
  is needed for stall, the live sail = 3D slabs on the GPU, or the slices only below stall + a 3D box for the
  stalled branch, chosen by the flow (separation at the leech), never by a table.
- 3D check queued s165: job 20261128-062851-640-run (AR 4, chord 24, alpha 15 vs 50).
- 3D ANSWER (s165, GPU on Mantle, AR 4 chord 24 box (192,96,160), 20 chords, 112 s for both, media/s165/sail-3d-gpu.txt):
  alpha 15: CL 0.46 CD 0.14 (L/D 3.3); alpha 50: CL 0.54 CD 0.68 (L/D 0.8). In 3D the stall is DRAG: once moving with
  the apparent wind at 60 off the bow, drive per q*A = CL sin b - CD cos b = 0.33 trimmed vs 0.13 stalled: right trim
  wins, as on a real yacht. The 2D slices gave stalled/trimmed lift 1.5-2.4x and CD 3 at stall: they cannot carry the
  game. DECISION: the live sail is the 3D box on the GPU (2.9M cells did ~20 chords/min; a box hugging the sail at
  chord 16-24 ~ 1M cells should be near real time for a 1.2 m sail in 6 m/s = 5 chords/s -> measure ms/step first).
  Caveat: 3D CL at 15 deg (0.46) is low for a 10% cambered AR-4 sail (~0.9 expected): the camber gain is lost at 24
  cells/chord, 2 cells thick (s163 saw the same). Check chord 32 at 10/15/50 once the box hugs the sail.
- CPU CROSS-CHECK (s166, job 20261128-062851-640-run, same case, 186 s): alpha 15 CL 0.458 CD 0.137, alpha 50 CL 0.533
  CD 0.667. GPU (Mantle) and CPU agree to the 3rd digit: the 3D answer is the flow's, not a GPU fault.
- CAMBER DOES NOTHING IN THE 3D BOX (s166 free time, GPU, chord 24 AR 4 box (192,96,160), alpha 15, Re 2000, mean of
  2-chord bins over chords 10-22, CL spread +-0.02): flat CL 0.40 CD 0.18 | arc 5% 0.28 / 0.115 | arc 10% 0.46 / 0.14
  (s165) | arc 20% 0.41 / 0.195. Arc 10% at Re 2e4 (shorter run): 0.49 / 0.15. Lift sits at ~0.4 whatever the belly:
  the box flies like a LOW-Re plate (vortex lift off the leading edge, camber 1-5 cells deep under 2-cell BDIM
  smoothing), not like a 1.2 m sail at Re 5e5 (~0.9-1.0 at 15 for a 10% AR-4 sail). For 'Sail it yourself' that is
  fine (sheet = angle, the stall is right), but BELLY (sheet tension, the outhaul) is NOT a knob the box can answer
  yet, and the forces are ~half a real sail's at good trim. Don't scale it up (a fudge); test chord 48 with a 1.5-cell
  plate before promising belly as play. Also odd and open: 5% camber lifts LESS than flat (less drag too).
- THE ISLAND HAS NO SAILING BEACH (s168 free time; scan of NG.terrain_height, Island(1, 24, 3), wind toward
  (0.95, 0.31) = from WSW; grade over the 1.6 m wheelbase, beach = h 0.8..1.4, margin 0.8 from the water):
  * No straight 20 m on beach sand anywhere with a beam/close reach: within 8 m of the parking spot every 20 m line
    meets >= 10.6% (the ring is r ~16 m: a 20 m chord sags 3 m, into the sea or up the dune).
  * Longest straight run under 4% on beach sand: 15.5 m at (17, 3.5) yaw 170 (east side, beta 62, 27 m from the cart);
    near the cart 12-13.5 m at (-10, -11.5) yaw 240 (beta 132 = broad reach), 10 m from the cart.
  * Steering along the contour (turn radius 4.4 m) does not save it: the coast wobbles tighter than the cart turns,
    grades 12-28%, and the heading swings the wind from dead ahead (beta 2-12) to dead astern.
  * Flat 20 m stretches exist only ON TOP (r 9-10, h 2.5, e.g. (8.5, 5.5) yaw 170, gmax 0) = grass, not sand.
  So the 20 m-straight test asks for a beach this island does not have. Real land yachts sail wide low-tide flats.
  Choices for the work part: (a) test the 12 m broad-reach run near (-10,-11.5) yaw 240; (b) a sand flat the island
  really has (shape it: tide flat / beach terrace in the terrain, an engine change that touches everything); (c) the
  top plateau on grass with grass rolling resistance. No fudging the wind or mass.
- WHY THE BELLY DOES NOTHING (s167 free time, Re 2000, plate 2 cells, 12+12 chords; ~5 min of runs in all):
  (1) GRID: 2D alpha 5, gain of a 10% arc over flat: chord 16 +0.10 | 24 +0.31 | 32 +0.38 | 64 +0.45 (flat .24/.27/.37/.38).
      The hugging box (chord 16) keeps a fifth of the belly even in 2D. 2D at 10/15 deg: gain +0.35..+0.50.
  (2) NOT 3D NUMERICS: a span-periodic slab (chord 24, span 16, GPU) = 2D to 3 digits (flat .267, arc .573).
  (3) THE TIPS' DOWNWASH + A LOW-Re SWITCH: finite AR 2, chord 32, alpha 5: CL flat .158, arc .147; section cl is
      flat along the span (mid .17 / .16, tip .09 / .08), so the whole span is down, not only the tips. 2D chord 32
      curve 0..4 deg: flat -.01 .12 .18 .23 .29 (5: .37); arc -.11 -.01 .09 .31 .58 (5: .75). At Re 2000 the arc's
      lift is a SWITCH between 2 and 4 deg (below it the arc lifts LESS than flat: convex side separated). ONE downwash
      of ~3 deg puts both mid sections on their 2D curves (flat .17 at ~2, arc .16 at ~2.3): the sail sits below
      the switch, and switching on would raise the downwash and push it back off. Downwash ~17 deg per unit cl, ~2x
      lifting-line's 9 for AR 2. (At 15 deg the 2D curve is shedding lift and is no section model; s165.)
  SO: belly is a knob only at a Re where the convex side stays attached (real sails, 5e5), which needs a far finer
  grid than real time allows. Keep belly OUT of play; sheet angle is the knob. A sail that 'luffs by itself' (s163)
  is this same switch.
- THE HUGGING BOX (s166, sailflow.jl `Sail3D`, `sail3d`, `sail3d_force!`; retrim inside the running flow like the 2D
  slices): chord 16, AR 4, box (96,48,96) = 442k cells, GPU (Mantle): 6.0 ms/step, 5.3 chords/s at 15 deg, 3.4 at 50
  (smaller steps in the stalled wake). A 1.2 m sail in 6 m/s needs 5 chords/s: REAL TIME at good trim, 0.7x stalled,
  alone on the GPU. Forces vs the big chord-24 box: 15 deg CL 0.43 CD 0.17 (0.46/0.14), 50 deg CL 0.71 CD 0.90
  (0.53/0.67): blockage (sail 2/3 of the box span, 48 cells high) puffs up the STALLED case by ~1/3. Drive at beta 60:
  trimmed 0.29, stalled 0.17 (big box 0.33/0.13): right trim still wins, by 1.75x instead of 2.5x. Next widen the box
  in y (64) if the GPU allows, and step it on its own task beside the frame.
- IN THE GAME PROCESS (s166, NOTES '3D sail box INSIDE THE GAME PROCESS'): @async on thread 1 runs the box at 6.4 ms/step;
  a Threads.@spawn task fails on Mantle's single-writer SubmitChannel, and Vulkan KA launches always use dev.default_bq.
  SAIL SERVER WORKS (s166, sailflow.jl `serve!`, test via Distributed addprocs + RemoteChannels): its own process,
  first force 28 s after start (compile + warm: Lumi can rig the sail meanwhile), then 4.8 chords/s at 5.5 ms/step
  (= real time for 1.2 m at 5.8 m/s), trimmed 15: CL .42 CD .16; re-trimmed to 50 mid-run: .69/.88 within ~1 s. The
  'game' side drains the channel each frame: median 0.8 ms, one 107 ms spike (first call compile? check in the plugin).
  IN THE GAME (s166 late, sandbox only, media/s166-sailtest.jl via live_eval Base.include): the game process starts
  the server (addprocs), sends alpha each frame, drains CL/CD, moves the cart's plots with translate!: 8 m/s beam,
  trim 15: 2.7 m/s and 20.5 m at 13 s, 43 m in 20 s, 30 fps held. Missing: wheel spin, ground following, collisions,
  keys, a camera that follows. Live-eval traps: no `using` inside live_eval code (include a file), Makie is
  NeverendingGame.Makie there, wrap in try/finally so rmprocs always runs.
  WAS THE PLAN: the box in its OWN PROCESS (own Vulkan device on the GPU), the game sends the sail angle + apparent wind and
  reads back CL/CD each frame; or a Mantle LavaDevice view on an allocate_batch_queue! channel (engine change).
- FIRST RUNS ON THE 3D SAIL (s166, yachtrun.jl sail = :box3d, area now aspect x chord^2 = 5.76 m2 (was 3.36), 95 kg,
  firm sand rolling resistance 69 N, beam wind): 6 m/s: NOTHING MOVES at any trim (trimmed drive 52 N < 69: the box's
  CL 0.42 is a low-Re sail's, ~half a real one). 8 m/s: trimmed (alpha 15) rolls, 1.4 / 2.3 / 3.2 m/s at 5/10/15 s;
  pinned on the centre line (alpha 85) never moves (18 N); over-sheeted to alpha 45 rolls FASTER at the start
  (2.7 / 3.8 / 4.2 m/s): near the beam the stalled sail's big CL (0.66, puffed by blockage) still pushes, its drag is
  sideways. The apparent wind swings from 90 to 62 deg by 15 s; trimmed should overtake once it is forward of ~55.
  Wall: 22 s for 15 s trimmed (0.7x real time with the CPU loop), 32-37 s stalled. Yesterday's wind decides: a
  6 m/s day does not sail.
- SPEED (s165): 3D arc box chord 16, AR 4, (128,64,96) = 786k cells on the GPU (Mantle): 9.9 ms/step, 0.035 chords
  a step = 3.5 chords/s = 0.7x real time for a 1.2 m sail in 6 m/s (5 chords/s). A box hugging the sail (~400k cells)
  should reach ~1.4x. It shares the GPU with the frame: step it on its own task, the cart reads its latest force.
