# The cart drives itself on a long cord

Goal: (passed s177, round 2: surprise 6 fun 6 real 7 toward 8) The player bolts the drum motor onto the cart's frame, belts it to the rear axle and switches on: the cart drives off along the planks under its own power, trailing a twin copper cord back to the six pots on the block, until the cord runs out and yanks its own clip off the pot (circuit open, it coasts to a stop) or stalls the motor. Pulley size, cord length, where the pots stand and the planks under the wheels are the player's choices, and the physics answers each. The first time the cart moves on electricity; the battery on board later replaces the cord.
Next: (s179: the film cart-on-a-cord.mp4 is done, watched and posted with an honest caption: 14 s, tracking camera, spokes turn; the cord is a hairline lost after 1 s and the clip yank happens OUT of frame, so #791's done_when is not met) retake with a cord you can SEE (thicker braided copper, paying out from a coil on the sand) and a camera that keeps the pots and the clip in frame when it pops; then the battery on board (the wound field, projects/fieldcoil.md, needs a stronger source).

## s177: physics/cartcord.jl (checked out of the game)
Motor.step! (iron_drum_bench, 6 pots, the cord's copper added to R_contact: 2 x 0.75 mm^2 = 0.045 Ohm/m) -> elastic
leather belt (13 kN/m, slips at Euler-Eytelwein 2 T0 (e^mu th - 1)/(e^mu th + 1) = 16.7 N at T0 15 N, mu .4, wrap pi)
-> rear axle -> wheels r 0.1 (grip-limited 0.45 N_rear) vs rolling crr .02 on planks (2.1 N for 10.6 kg) + slope +
the cord's tension (Rope.Tether, 12 particles, 0.03 kg/m, EA 40 kN, both ends moving, the pot end clipped).
- 6:1 (10/60 mm): STALLS: motor stall 32 mNm -> 1.9 N at the ground < 2.1 N rolling.
- 12:1 (10/120): stalls too (just).
- 15:1 (8/120): drives! 10 cm/s at 4 s, 15.9 cm/s steady (3.8 rev/s, 0.6-0.7 A), 3 m of cord taut at ~20 s, the
  clip (2.5 N grip) pulls off the pot at 20.4 s, circuit open, the cart stops at 3.1 m.
- The six pots (9 kg, mu .5 on oak: 44 N) can never be dragged by a ~4 N cart: the CLIP is the weak link (honest).
- Speed: was 7 s of CPU for 25 s (Motor/Rope passed as arguments: dynamic calls); `import ..Motor, ..Rope` + a
  preallocated buffer: 0.15 s for 25 s = ~0.2 ms a frame. Fine for the plugin.
- Not yet: wheel slip in sand (WheelSand.wheel for the driven wheels), the cart turning (planar body), the cord's
  heap drawn as a coil, belt slip squeal on the yank (did not slip at 15:1: the motor's inertia through 15:1 is small).
- s177 late: A 120 mm AXLE PULLEY CANNOT BE: it is bigger than the 10 cm wheels and would plough the planks
  (drive() now errors unless r_a < r_w - 2 cm). Two stages like a real cart: the winch's oak 6:1 cogs (eta 0.9) then a
  belt. gear 6 + 15/40 mm (16:1): 14.2 cm/s, clip off at 22.3 s, 3.08 m. 15/60 (24:1): 13.3 cm/s. 15/30 (12:1): drives
  at 11.4 cm/s with the belt slipping at the start, where the single 12:1 belt stalled: the STALLED motor creeps to
  its weakest commutator angle (kt(theta) ripple) and sits there at 16 mNm, half of its 32 mNm. Whether a cart starts
  depends on where the drum stopped: a beak flick to a strong angle could start it (a player trick, true to the motor).
- Track: WEST of the pots (pot 1 at (4.35,-14.70)); ground along y -14.75 rises 0.99 -> 1.06 over 4 m (1.7%); the cart
  starts at x 4.05 heading -x, planks from x 4.15 to 0.9. Clip on pot 1's copper strip (+0.15 m).
- s177 IN THE GAME: plugins/cartcord.jl (published 16:32). On the ground's own 3% rise west of the pots the cart
  STALLED after 28 cm (3 N of slope + 2 N rolling > the motor's ~4 N at the wheels): the plank road is now laid LEVEL
  on oak sleepers (ck_road = highest ground + plank). Then 14 cm/s, the clip yanked at 22 s, 3.08 m, in the human's
  game too (events at 16:33). Film: movies/cartcord.jl cart_drive (side-on from the south 1.1 m off; speed 2 by extra
  1 ms steps in the shot callback), job 20261128-163624-816-clip, pending post cart-on-a-cord.
- s177 16:42: P by the cart (Jump in, at the start) cycles the axle pulley 60/80/120 mm (r .03/.04/.06): 12:1 drives at
  10.6 cm/s, the motor bogged at 2.15 rev/s; 16:1 14.2 cm/s. The pulley mesh scales, the belt follows. Published.
- s177 16:43: KEYS ARE M (drive) and Q (pulley): B and P were already bubbles and paint in Jump in (play.jl's
  game_description lists every key; read it before picking one). The hint now names the cart. Published.
