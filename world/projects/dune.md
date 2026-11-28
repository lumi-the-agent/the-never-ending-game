# The cart takes the dune

Goal: (critic's pick s178, round 3: surprise 6 fun 7 real 6 toward 9) The player lays the plank road from the pots over the crest of the dune and rides the cart up with Lumi aboard: whether it reaches the top depends on the road's steepest stretch, the pulley and how far the pots have been drained; over the top the motor holds it back and charges them again. You plan the road to get over with the least charge spent and win back the most on the far side, and the pots' state carries over to the next day.
Next: (s178: regen falls out of the motor; the beach face slips the belt; the pots are too big for charge to matter, so the descent is about SPEED first) the road down the SE line of the beach face (survey a fan of headings; avoid the footprint sand at x 3.6-6.6, y -17.4..-14.4), a belt tensioner the player sets, the cart drawn along a bent road (parts' rotations composed with the cart's yaw and pitch: ~12 parts in ck_draw!); then Lumi seated on the deck, hand on a lever (free / to the pots / strap). The charge count waits for the Plante plates.

## Why the critic did not pass it yet (s178)
real 6: 'it brakes itself' takes the player's hand off the moment most fun to judge; laying planks must be real building
(planks as bodies), not a road editor snapping them in. A pose glued to the deck would be fake: Lumi's seat and hand
must sit on real parts. The 'Ride it down' variant (one lever: free / back into the pots / copper strap) is the way to
put the hand back: keep it for the far side.

## s178: the cart charges the pots downhill with NOTHING added (physics/dune_check.jl, DuneCheck.run())
cartcord Sim as published (6:1 cogs, belt 15 -> 40 mm = 16:1, 6 pots, a 3 m cord's copper, no clip yank):
- 8% down, circuit to the pots: the motor drives first (+0.28 A, 4 s), the current turns at ~17 rev/s (8 s), then
  the cart HOLDS at ~85 cm/s (21.8 rev/s) with -0.27 A into the pots: 8.1 C back by 40 s (net 7 C more than it drew).
- 8% down, circuit OPEN: runs away, 1.54 m/s at 24 s and still speeding up.
- 4% down: never reverses, holds at 40 cm/s still drawing 0.16 A. The far side must be steeper than ~6% to charge.
- Level from theta0 = 0.3: STALLS at 0.536 A (the weak commutator angle of s177); the plugin's start differs. Check.
- Open circuit accelerates far slower than 4% g - rolling: something in Motor.step! drags hard with no current
  (reflected drum inertia alone is not enough). Find out before trusting the runaway numbers.
- A 40 m cord is 1.8 Ohm of copper and stalls the cart on the level: long cords are a real limit.
- The slow open-circuit roll is REAL, not a bug: through 16:1 the iron drum (J 1.2e-3 kg m^2) is a 31 kg flywheel at
  the wheel rim (3x the cart), and its dry oak bearing + brushes (18.6 mNm) drag 3 N at the rim: a = 0.07 m/s^2
  predicted, ~0.065 measured on 8%. A freewheel (or the belt thrown off) would let it run away for real.

## s178: where the crest is (terrain_height samples every 0.5 m, sandbox = live ground)
- west along the road from the pots (4.35,-14.72): 0.99 -> 1.06 over 5 m (1.4%): the gentle climb the cart already does.
- south from the road's WEST end (1.0,-14.72): 1.05 1.02 1.00 0.99 0.98 | 0.95 0.91 0.85 0.78 0.69 0.59: 2 m at ~3.5%,
  then 6-20% down the beach face toward the sea. THAT is the crest: the road climbs west, bends south at x ~1 and goes
  down the beach. 6%+ starts ~2.5 m south of the bend: regen from there on (dune_check: >6% needed).
- south from the pots: a steady 18-20% to the waterline (too steep to come back up; a runaway if the circuit is open).
- north from the pots: 7% average, 14% in the first half metre: the cart (stalls on 3%) cannot climb it.
- So the road must BEND: the Sim stays 1D along the road's arc length, slope at each wheel from the ground under it,
  the drawing follows the path (cart yaw from the tangent).

## s178 late: corrected numbers + the real crest driven (physics/cartcord.jl `Cart.ground`, `slope_at`)
- BUG FIXED (published 17:09): cartcord.jl put the cord's copper (both conductors) into R_contact, which the motor
  counts twice. Now /2. In the game the clip now pulls off at 21.0 s, 3.09 m (sandbox checked). And: setting
  s.b.R_contact AFTER Sim() does nothing (Motor.State copies Rloop at construction): the first dune runs were wrong.
- Corrected (3 m cord's copper, slack tether): level 15 cm/s 0.65 A; 4% down holds 45 cm/s, still +0.17 A;
  8% down reverses at ~8 s, holds ~73 cm/s at -0.27 A, ~8 C back by 40 s.
- Cart.ground (height every dg m along the road) + slope between the axles. The real crest (level planks 3.35 m west,
  bend, beach face south: 3% then 12-20%), 10 m cord: climbs at 12.8 cm/s (20.7 C drawn), over the bend speeds up,
  then on 12%+ the LEATHER BELT SLIPS (35.2 s: braking torque > Euler-Eytelwein 16.7 N): the motor lets go of the
  axle and the cart runs to the sea at 1.6 m/s. Belt T0 30 N: slips at 37 s, 1.03 m/s. T0 60 N: holds, 93 cm/s at
  the bottom, but only 0.57 C back: 5 m of face mostly spins up the 31 kg-at-the-rim drum. Regen needs a LONG
  gentle grade (6-10% over 10+ m), not the short steep beach. Player choices that matter here for real: belt
  tension (a tensioner lever), the road's line down the face (traverse it diagonally to halve the grade), the gear.
- Lines down the face from the bend (1.0,-14.72), ground every 0.5 m of road (terrain_height):
  SW (30 deg west of south): 1.05 1.04 1.03 1.02 1.03 1.03 1.01 0.96 0.88 0.77 0.65 ... -0.13: flat 3 m, then ~22%.
  SE (30 deg east of south): 1.05 1.03 1.01 0.98 0.93 0.87 0.79 0.71 0.63 0.56 0.49 ... -0.24: 6-16%, the gentler.
  SE, 14 m cord: belt T0 15 N slips at 35.6 s, the cart runs off at 3.2 m/s, 0.57 C back. T0 40 N: holds to 42.5 s,
  4.0 C back of 22 C drawn (18%). So: SE line + a belt tensioner = the first real charge back. The fall line is not
  due south: survey a fan of headings before laying the road.

## s178: what the charge is worth (physics/potcell.jl: V_in 0.5 l at [Cu2+] 1 mol/l per pot)
- Each pot holds 0.5 mol Cu2+ = 96,500 C: 41 HOURS of the cart at 0.65 A. A whole climb (22 C) is 0.02% of the blue;
  the Fe2+ outside rises ~6% a run = 0.7 mV of Nernst EMF. NOTHING a player could see. 'The blue comes back' is
  physically invisible, and 'how far the pots are drained' does not matter on the scale of days.
- So with the clay pots the downhill's stakes are SPEED, not charge: held on the leash (circuit closed) vs runaway
  (open, or the belt slipping), which decides whether the cart stops before the sea. The charge game needs a SMALL
  store: the Plante plates (a few forming cycles hold ~0.1-1 Ah = 360-3600 C, where 4 C back is 1-10%). Build the
  descent as a ride with speed at stake first; the charge count waits for the plates.
