# Sled the cart down the dune
Goal: push the empty cart to the dune top, three friends pile in, let go: it runs downhill by gravity; the player brakes by driving a stick into the sand (deeper = more drag, it can snag and slew the cart round) and steers by calling the friends to lean (one side's wheels sink deeper, the cart turns towards them); on a side slope too much lean rolls it over and spills them. Reaching the water without stopping or tipping is the run; ruts and berms stay and change the next run, and after rain or near the water the same dune runs differently. Fun because you steer it live, it can go wrong in funny ways, and the friends react.
Next: (s171: stick force in sand + damp sand from the water table, both checked; the cove is TOO GENTLE for a loaded cart) a real dune behind the south cove (slip face at sand's repose ~32 deg, marram grass), then the cart as a PrintSim affine body (find how to put per-wheel soil forces on it: climbgrab.jl uses affine bodies) on 4 Bekker-Wong wheels, the stick as a SoilTool blade.

## Passed the critic s171 (round 3: surprise 8, fun 8, real 7, toward 7)
Risks it named: the friends' poses must come from the cart's acceleration (not a canned lurch), and the soil cells must
really differ (moisture, compaction), not all dry-sand values. Rollover from the rigid body's own reactions, never a
fitted threshold. R digging moves onto the same blade model.

## Road
- [ ] Blade force in sand (soiltool.jl) + check against classical results
- [ ] Soil per SandField cell: moisture (distance to water, rain) and compaction (passes) -> c, phi, gamma, Bekker k's
- [ ] Cart as a rigid body on 4 Bekker-Wong wheels, friends as masses at seats, load transfer and rollover
- [ ] Stick brake: Lumi drives it in (depth by key hold), it ploughs a furrow in the SandField
- [ ] Friends lean on call (their mass moves), hold-on poses from the cart's acceleration
- [ ] Jump in ride from the dune top + traced 10 s short from the dune's foot

## s171 (first session)
- physics/soiltool.jl: a blade/stick in soil. Upward wedge + side crescents (McKyes-Ali, minimised over the rupture
  angle) above a critical depth, sideways flow (Broms 3 Kp sigma_v) below, dc where the total is least. Check
  physics/soiltool_check.jl PASSES: a wide smooth blade = Rankine passive to 1e-9 (c = 0 and c > 0); a 3 cm stick in dry
  sand 20/50/90/140 N at 5/10/15/20 cm (firm sand 27/66/117/180), above a wide blade's slice, within Broms.
  DOUBT: dc comes out ~0.5 cm (the sideways flow wins almost from the surface); Godwin-Spoor's measured critical depths
  are several tine widths (my memory). The crescents with rho = pi/2 are probably too strong: McKyes-Ali's own rho.
- physics/sandwater.jl: the beach's water from the sea's water table (hydrostatic: suction head = height above the
  sea, sea level is z = 0), van Genuchten retention (Lu & Likos fine sand: alpha 4/m, n 4), suction stress -> apparent
  cohesion (Lu-Likos/Vanapalli), buoyed weight at and below the table. Apparent c: 0 at the waterline, 0.8 kPa at
  20 cm up, ~0 at 2 m. Stick 15 cm: 75 N in the swash, 136 N in the damp band, 94 N on top. Rain/drying not in yet.
  The Bekker k's do NOT change with moisture yet (kc is cohesive: should).
- THE RUN: south cove profile along bearing -1.2 rad: grass to 14 m from the centre (z 1.17), sand 14-20 m, water at
  20.3 m. Gentle (3-6%) to 16 m, then 13 deg (tan 0.23) over the last 3.5 m, right through the damp band.
- ROLLING RESISTANCE / WEIGHT (WheelSand.towed, r 0.35): empty 95 kg dry 0.21 (b 10 cm) / 0.15 (30 cm), firm 0.05-0.07;
  three friends 275 kg dry 0.29 / 0.24 / 0.21 (b 10/20/30 cm), firm 0.08-0.11. A loaded cart on 10 cm wheels does NOT
  roll down the cove's steepest part (0.29 > 0.23). Real choices from this: wheel width, running in your own packed
  ruts. A real dune's slip face (repose ~32 deg, tan 0.62) is needed for a ride.
