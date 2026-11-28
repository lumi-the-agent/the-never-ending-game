# Stuck in the sand: dig, plank, push, rock it free
Goal: sail too far into the soft dry sand, or let the friends ride, and the yacht's wheels really sit in the sand and stop; then the player gets it out like a person would: dig a ramp in front of each wheel (the sand slides back if the hole is too steep), wedge a plank under a wheel, get the friends to push, or let a gust rock it out. Every stuck is a different puzzle because the sand stays where you left it (the loop SnowRunner and MudRunner built whole games on). Passed s168 (critic: surprise 7, fun 7, real 7, toward 8).
Next: (s169 PUBLISHED: wheels in the sand field, soil per wheel, settled in their own holes = 136 N; Q a friend pushes; R digs, heap to the side; the sand square moves with the cart) a plank under a wheel (SandField.plank_rest); poses: Lumi's scoop (only :eat now) and the friend leaning; check 'own hole 34 N < fresh 48.5' against s168's holes costing more; ruts beyond the 6 m square (a beach-wide field). Then the traced film at low sun: stuck, Lumi digging, a friend shoving, it rolls out = the post.

## s168: the physics, measured (physics/stuck.jl, check physics/stuck_check.jl, passes in 10 s)
- `Stuck.rim(s, r, b, ground, zc, i; pressed)`: WheelSand.arc on REAL ground: the entry angle where the rim meets
  the profile, Bekker stress for the profile's sinkage at each point (Wong-Reece peak shift, rear mirrored),
  Janosi shear; `settle` finds the axle height carrying W and the towed slip (zero torque). On flat ground = arc
  (194.15 vs 194.15 N for the cart in dry sand). Normal stress alone gave only 70% (shear + peak shift matter).
- LOAD HISTORY: sinkage must count from the surface the sand had BEFORE it was pressed (`pressed` per cell = what
  press! took away). Without it a standing wheel re-pressed each step counted its own rut as fresh sand and dug
  itself down (4.4, 5.2 cm and growing; even firm sand 'stuck' at 25 N > 17 N). With it: stiff reloading (Wong's
  repetitive loading taken as stiff), the standing wheel stays put.
- `run_wheel`: one wheel pushed through the GPU-capable sand field (2 cm cells): dry sand rolls at ~45-48 N per wheel
  (flat model 48.5), firm 12-17 (17.3). Its sand goes SIDEWAYS into berms (no bow wave on a 10 cm rim): a towed
  wheel in uniform sand does not bury itself; stuck = drive < 4 x 48.5 = 194 N.
- THE PUZZLE (95 kg cart, r 0.35, b 0.10, dry sand): rolling fresh 194 N | firm sand 69 N | three friends aboard
  (275 kg) press 6.3 cm holes and need 789 N | they climb off: the light cart still sits 5.4 cm deep, breakout
  297 N (s168 final) | a ramp dug in front of each wheel (hole floor rising to the surface over 40 cm): 42 N.
- WHO CAN PUSH (WheelSand.foot, both feet, full shear + ridge): a 60 kg pony on hooves 7x7 cm ~357 N on dry sand;
  Lumi (8 kg, 6x4 cm feet) ~52 N. So: Lumi alone cannot break it out of the holes (297), CAN after digging (42),
  then stops again in fresh dry sand (194): it needs a friend or planks to the firm wet band. The sail at 8.8 m/s
  gives ~80-150 N trimmed: it can never sail dry sand (the s167 yacht's 69 N everywhere is firm sand where the cove
  is dry: a mislabel to fix together with the ways out, never alone).
- Not yet: plank under a wheel (SandField.plank_rest exists), the gust (needs the time series of the sail force),
  digging as an action, slip sinkage for a DRIVEN wheel (the motor cart will dig itself in, Lyasko), compacted
  sand's own Bekker constants (rocking in its own ruts).
- The hole once the wheel lifts out (200 slump sweeps): 63 -> 43 mm deep, walls at 33.2 deg (repose 33), side berms
  22 mm, 0.2 m long along the track: the field slumps the way dry sand does.
- PLANK, first estimate (rigid-step formula F = W sqrt(2 r s - s^2) / (r - s), not yet SandField.plank_rest): a
  plank (3 cm) laid FLAT in front of a wheel sitting 5.4 cm down is a step of 8.4 cm: ~199 N per wheel (~800 N for
  four), worse than the hole. Wedged as a RAMP from the hole's floor (1 m long): ~W sin(3 deg) = 13 N per wheel,
  ~50 N for four. So how you lay the plank is the skill: flat it is a wall, wedged it is the way out. Confirm with
  rim() over a rigid plank profile + plank_rest (the plank sinks into the sand under the wheel's load).
- SPEED (s168 late): `Stuck.settle_from(..., guess)` = warm-started damped 2D Newton on (axle height, slip):
  0.7-1.9 ms against 7-9 ms for `settle`, converged on every frame of a berm creeping closer (40/40).
- CONTACT PATCHES + REAR-ONLY PRESS (s168 late; these numbers replace the earlier ones above): rim()'s MAIN patch is
  the first contact going forward from the bottom (Wong-Reece on it); PATCHES AHEAD (a berm) get Bekker at their own
  sinkage and shear from their own entry, no mirror, so a berm's force grows from zero as it comes into reach. A
  ROLLING wheel presses the field only BEHIND its bottom (ahead, the arc is still compressing the sand; pressing the
  whole footprint left it riding on a sliver it had pressed itself: 38 N instead of 48.5, not fixed by smoothing or
  dt 5 ms); a STANDING wheel presses its whole contact. Now (stuck_check, passes): flat 194.15 = towed 194.15 N,
  rolling in the field 193.1 N, the friends' hole breakout 297 N (was 267), dug ramp 42 N, hole 6.3 cm. settle and
  settle_from agree to 0.013 N as a repose-flanked berm comes into reach (40/40 frames, zero torque left).
- WHOLE CART (s168 last, `Stuck.CartSand` + `wheel_step!`: an 8 x 8 m field at 4 cm under the cart, 4 wheels at any
  heading, rotated footprints, warm-started settle per wheel, load history): 95 kg pushed with 250 N at 30 deg through
  dry sand: R 169 N (flat model 194; check whether the 4 cm cells or the rotated sampling take the 13%), ruts 3.0 cm,
  BUT 107 ms per frame. For the game: ONE footprint map and ONE press! for all four wheels, press only a window
  around the cart (not the whole 200x200 field, no full Array copies per wheel), settle_from only (~2 ms a wheel),
  the wheels' solve at 10 Hz or on a task; or a KA kernel that evaluates the rim for all wheels at once.
- FAST (s168 end, `Stuck.cart_step!`: one field read, warm-started settle per wheel, ONE footprint map + ONE press!
  with berm radius 4 cells, CartSand concretely typed): the whole cart (4 wheels + press + 2 slump sweeps, 8x8 m at
  4 cm, CPU) = median 0.9 ms a frame, p95 ~20 ms from 45 fallbacks to the full settle in 360 wheel-steps (not an
  iteration limit: 6 or 12 the same; probably the frame the wheel starts rolling and the press turns rear-only).
  Full settle with sample() = ~20-200 ms: fix the fallbacks (find which frames; seed slip from the last value and
  bracket locally) before the game uses it. The `Any`-typed struct had cost 0.3 ms per rim (107 ms a frame).
- WHERE THE FALLBACKS ARE (s168 end): (1) frames 2-6, the wheel starting to roll out of its standing contact (slip
  -0.051 -> -0.012 in a frame); (2) the REAR wheels running in the front wheels' ruts (same track): sitting on
  stiffly-reloading pressed sand, the axle height jumps 3-6 mm frame to frame. TRIED Wong's continuous reloading
  (sigma = A_u p z, A_u ~ 503 MN/m^4 from memory of Wong, UNCHECKED): fallbacks the same (44-45) and a standing
  wheel crept 3.3 -> 5.0 cm (press! counts the elastic reload as compaction): reverted. Next: press! must count
  only plastic sinkage; and/or the fallback = a short local bracket around last frame's slip and height (cheap)
  instead of the full settle; offset the rear wheels' track (a real yacht has a wider rear axle) is NOT the fix.
- WHY NEWTON FAILS THERE (s168, last minutes): after frame 65 the rear wheels fail EVERY frame: on the front wheels'
  stiffly pressed ruts the load W(axle height) is a STEP (touching pressed sand jumps the stress to what it carried),
  so the rest state is a contact constraint (sitting on the floor), not a smooth root; no Newton seed finds it (a
  second seed at the soil's towed slip: still 44). Fix: when settle_from fails, a LOCAL bracket (axle height within
  +-1 cm of last frame by bisection, slip within +-0.05) instead of the full settle; or a complementarity solve.
  TRIED the local bracket (height +-1 cm, slip +-0.05): still 44, median 0.8 -> 3.4 ms (no sign change there):
  removed. On the stiff rut floor the zero-torque state likely does not exist as a smooth root at all: a MODEL
  question (how a towed wheel on a stiff floor slips; maybe slip = 0 rolling with only the floor's contact, R from
  the rim's front patch in fresh sand), not a solver one. Look at T(i) on one of those frames first.
- THE REAL CAUSE (s168, probe of the rear-left wheel at frame 65): T(slip) is smooth and monotone (root near
  -0.006): slip was never the problem. The LOAD has no root: at every slip the axle height pins at 320.42 mm with
  W 5-7 N over the target (a step at first touch). And the load history is WRONG: `pressed` reads 28-72 mm where the
  ground is only 23-31 mm down: sand that slumps (or is bermed) back into a pressed cell is pressed out again next
  frame and COUNTED AGAIN, so the rut looks as if it carried far more than it did. FIX FIRST next session: sand that
  lands on a cell (slump or berm) is loose: P -= what landed (floor 0), so P never exceeds the depth below the virgin
  surface; then accept a bracket narrower than 0.01 mm as converged in settle_from (a resting contact is a step).
- PARTLY FIXED (s168 last): `Stuck.loosen!` (sand that lands on a cell takes that much off its pressed depth) in
  cart_step! and `Stuck.slump!(cs, n)`: fallbacks 44 -> 32 of 360, median 0.9 ms, R 173 N, ruts 3.3 cm. But the
  largest pressed depth is still 10.7 cm under a 3.3 cm rut: something else over-counts (look where: the start
  where the wheels stood, compaction counted twice?, the rear wheel re-pressing the front's rut). run_wheel (the
  check) has its own P logic without loosen!: make it call loosen! too once the over-count is found.
- s168 VERY LAST: loosen! had counted sand SLIDING AWAY (a berm slumping into the rut) as pressed; fixed (only a body
  presses). Over-counted cells (P > 2x depth) 505 -> 192 of 597, max P 10.7 -> 8.8 cm (rut 2.3 cm there, at the
  rear wheel's track 0.08 m ahead of the cart's start), fallbacks 32. The bookkeeping press(P += d, h -= d) /
  land(P -= d, h += d) keeps P + h <= 0 on paper, so something breaks it: log P + h per cell through one frame of
  press, berm and slump to find which step. stuck_check passes throughout (run_wheel keeps its own P logic).
- CORRECTION (s168, 09:09): logging per stage, the 'over-count' appears ONLY in the press step (never in slump),
  from frame 16 when the rear wheels reach the front wheels' tracks, and it is mostly RIGHT: P counts from each
  cell's own top before it was pressed, so loose berm/slumped sand above the old surface pressed down counts in
  full (P > depth below the ORIGINAL surface is not an error). My 'P > 2x depth' metric was wrong. What stays
  suspicious is P up to 8.8 cm: a rolling wheel's rear half re-presses covered cells by mm each frame while its
  axle height jitters (the fallback frames). Next: log one cell's P and the wheel's zc frame by frame.
- s169 FREE TIME, THE FALLBACKS (bench: 4 wheels +-0.8 m, +-0.6 m, 1 m/s, 90 frames, dt 1/30, slump 2):
  heading ALONG the grid (yaw 0) = 0 fallbacks; DIAGONAL (yaw 240 / 17) = 33-40, all from frame ~52 when the REAR
  wheels reach the front wheels' ruts (a diagonal rut is a staircase on the 4 cm grid: floor bumps -19..-31 mm,
  P up to 66 mm). Three things found and fixed in physics/stuck.jl (stuck_check still passes, same numbers):
  (1) BUG in settle_at: top = ground + r - sqrt(r^2-x^2) was right only on flat ground; in a rut the bracket's top
      already had the rim 4 mm deep and the 'full settle' returned W 426 N of 233. Now ground + sqrt(r^2-x^2) + 2 mm.
  (2) settle_from 2-cycled across the kink where the rim first touches pressed sand (230 N/mm below, 22 above):
      now keeps a height bracket (W monotone in zc) and uses false position (Illinois) when Newton leaves it.
  (3) Newton overshooting off a bump into the air (d = 0) returned nothing: now cuts the bracket instead.
  Result: yaw 17: 40 -> 18, yaw 240: 40 -> 23, yaw 0: 0. The REST ARE TRUE STEPS: half of the old fallbacks had NO
  root (the full settle ended up to 18 N = 8% off W anyway, spending 20 ms for it). A step accepts now if the bracket
  closed to 0.01 mm, torque zero, W within 3%. NEXT: either accept the closed-bracket answer at any W error (the full
  settle is no better there) or make the reload continuous (Wong's finite reload stiffness) WITH press! counting
  only plastic sinkage (the s168 creep). Rear wheels jump 2-5 mm a frame on these floors: a visible judder to check.

- s169 IN THE GAME (plugins/landyacht.jl, published): CartSand 6x6 m at 4 cm around the cart, cart_step! each frame
  while it rolls (standing: the holes' R once), soil from meadow.jl beach_weight at the cart's centre (d < 0.9 m wet =
  firm). Parked in the cove: dry sand, wheels 32.5 mm down, R 194 N: the sail (~92 N at 8 m/s) cannot move it any more
  (the old 69 N was firm sand everywhere). Q by the cart (also aboard) calls the nearest friend: it runs over (goal),
  steps round what blocks it (1.5 s without progress -> 3 m sideways, 3 tries, then 'I can't get round to it!'),
  leans on the stern and pushes 2 x WheelSand.foot(soil, 60 kg g/2, 7 cm hooves).Fmax = 357 N dry, tapered by
  (1 - v/2.5 m/s) (grip alone ran it to 3.9 m/s). Measured: Gloop ran 13 m, pushed 8.2 m in 9 s at ~1 m/s (shove
  170-270 N vs roll 120-194), the cart stopped within a second when it let go. Yacht system 2.1 ms median, 2.7 p95;
  frame 7.4/12.2 ms. Drawn sand lifted 4.5 cm over the terrain (at 1.2 cm the 3 cm ruts showed green terrain).
  Screenshots media/s169-yacht-ruts.png (ruts + berms behind the wheels), s169-yacht-ruts2.png (friend at the stern).
- s169 DIGGING (published): R by the yacht in Jump in = one beak scoop (13 cm radius, <= 4 cm deep, never below the
  bed) 0.35 m in front of Lumi; the same volume heaped 0.45 m behind it (loose: no load history; dug cells lose their
  P and comp), slump 6 sweeps, then the wheels re-settle standing. Nothing knows about wheels. Measured: three scoops
  ahead of each wheel took the standing hold 194 -> 134 (first wheel) -> 127 -> 126 -> 118 N. ASYMMETRIC: the first
  wheel's ramp gave -60 N (its R went negative: it wants to roll into its hole), the others 0.4-8 N: look why (heap
  landing under another wheel? the press of the standing re-settle? the scoop line vs the contact patch) before the
  film. The holes barely read in the night raster (media/s169-yacht-dug.png): the film needs low sun across them.
- s169 (09:42) WHY DIGGING WAS UNEVEN: not the dig. The first standing settle meets FRESH sand (48.5 N a wheel = 194)
  and presses the holes; every later settle finds the wheel IN its own hole (~34 N a wheel = 136). Each dig re-settled
  all four, so any dig anywhere cut the hold 30%. Fixed (published): a fresh square settles twice; parked hold = 136 N
  (strong gusts' ~155 N sail can now just break it out). Is 34 < 48.5 right (a wheel in its own pressed hole easier
  than fresh sand)? Under the stiff-reload model the front wall is pressed sand; CHECK against s168's 'friends' holes
  cost MORE (297)' before trusting it. With the fix, digging is a SKILL: 3 scoops 0.25-0.6 m ahead of a wheel: -2 N;
  close in (0.10-0.20 m ahead of the centre): -8 to -26 N a wheel, but 6 close scoops sent one wheel to 143 N (it drops
  into the scoop and meets the far wall: a hole is not a ramp). The heap lands 0.45 m behind Lumi: for the rear wheels
  that is under the cart. Next: throw to the side, and a dig pose; then the film.
- s169 (09:44, published): each wheel has its own soil (cart_step! takes `soils`; landyacht.jl reads beach_weight at
  each wheel), the scoop's heap goes 0.5 m to Lumi's right (not under the cart). End to end in the sandbox: six close
  scoops at the front wheels 136 -> 110 N, Gloop came 12 m (10 s, stepping round), pushed it out at ~1 m/s
  (shove 200-275 N vs roll 152-218 N). stuck_check passes unchanged.
- s169 (09:46, published): the sand square MOVES with the cart: past 1.6 m from its edge a new one snaps to the old
  grid and takes every shared cell (h, bed, comp, P) and the wheels' last settles. Sandbox: pushed 8.5 m, square
  re-centred, the rut behind the right wheels still -19..-27 mm from 1.0 to 2.75 m behind the centre. Gloop got up
  from sleep to push. Older ruts beyond the square (> ~4.6 m behind) are still lost: a beach-wide field is next.
- s169 PATH TRACED LOOK (media/s169-yacht-traced.png, night): the rut on a diagonal heading reads as a row of separate
  DASHES (stitching), not a groove: the 4 cm cells' staircase, the same one that trips the solver. Before the film:
  draw the sand mesh from a smoothed / finer resampling of h (or 2 cm cells near the wheels), and film at low sun from
  the side so the grooves and the dug holes cast shadows. NO POST s169 (the human's rule: only when it looks the part).
- s169 (last, published): the drawn sand goes through a 3x3 binomial blur (physics untouched): the dashed diagonal
  rut is gone in the raster (media/s169-yacht-smooth.png, Gloop at the stern saying 'Phew!'); grooves now soft and
  faint at night. Still check it path traced at low sun before the film.
- s170 FREE TIME, 'is 34 < 48.5 right?' ANSWERED: NO, it is a contact artifact, not physics. One wheel (dry, 233 N)
  standing in a CartSand, settled 4 times: fresh 48.5 N, then 37.5-39.3 (dx 4 cm), 38.4 (2 cm), 38.5 (1 cm): it does
  NOT go away with a finer grid. The hole is a perfect cast (rim = surface = pressed depth to 0.1 mm along the whole
  line, no berm ahead) and the wheel sits 0.02 mm above it at the same height as fresh. But bilinear chords of the cast
  sit 0.02-0.04 mm above the rim between nodes, so zat > 0 comes and goes: the rim meets its own hole in 15 SEPARATE
  patches; the main patch ends at θ = 0.009 rad and the other 14 are 'patches ahead' (no Wong-Reece mirror, shear
  building from each patch's own entry). The same stresses, summed under the other model: R 38.5, slip -0.027 vs
  -0.051. The physics says a towed wheel re-sat in its exact rolling cast meets the same stresses (stiff reload =
  what it carried) and restarts at the rolling R, ~48.5, not lower. So the published 136 N parked hold should be ~194,
  and the s169 'digging is a skill' numbers (-2 / -8..-26 / +100) were measured against the artifact.
  FIX (not made, the solver is touchy): in rim's main-patch scan, bridge gaps shallower than ~0.2 mm (sand grain;
  every gap inside the hole is < 0.1 mm, only the edge's last cell opens 0.76 mm). Then CHECK: stuck_check, the berm
  jump s168 fixed (a berm ahead must still not jump θ1: bridge only gaps INSIDE the run from the bottom, never into a
  patch ahead), the fallback count, and redo the dig numbers. 194 N > the sail's 155 N gust: the parked yacht would
  again need a friend or a dig, which is what the story wants anyway.
