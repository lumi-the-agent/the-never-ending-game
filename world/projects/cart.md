# The friends pull my first cart
Goal: Lumi builds a wooden cart (frame, axle, wheels of a width the player chooses); the friends pull it up the dune on a rope, feet slipping in the sand, ruts behind it; then the drum motor goes on the axle and the same friends try to hold it back in a tug of war they lose. Fun because the wheel width and who pulls decide whether it climbs, and the motor's worth shows in friends.
Next: (s158 PASSED as 'one sand law for feet and wheels'; feet done: wheelsand.jl foot/foot_creep/lean) give each friend a mass from its mesh volume (species.jl has none); then one friend on the dune pulling a fixed rope: its feet planted by `foot`, creeping and stepping, the lean from `lean`, footprints written into the terrain; then the cart as PrintSim rigid bodies with wheels on `wheel`.

## s157 (strongest idea, did not pass in 3 rounds: surprise 7, fun 6, real 6, toward 9)
- Critic's risks: poses must come from the rope's force (not a tilt), soil constants must be general (they are: Wong's table, 4 soils).
- physics/wheelsand.jl done (NOTES 'Wheels in sand'): narrow vs wide rim, towed resistance, climb table.
- Motor for it: Motor.drum_film() starts from every angle (NOTES 'The drum rotor').

## s158: passed (round 3): "one sand law for feet and wheels" (surprise 7, fun 7, real 7, toward 8)
- Critic's risk: the bodies. A statics lean + step trigger can look like a stiff puppet sliding; the friends must look
  like characters putting their weight into the rope, or the sand law only shows as scrapes under a pose.
- Done: physics/wheelsand.jl `foot` (Bekker + Janosi-Hanamoto + Rankine ridge), `foot_creep`, `lean`; cart_climb uses
  the feet (NOTES 'Feet on sand'). One 8 kg friend now pulls the 12 kg cart up 10 deg.
