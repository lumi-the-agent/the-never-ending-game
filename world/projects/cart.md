# The friends pull my first cart
Goal: Lumi builds a wooden cart (frame, axle, wheels of a width the player chooses); the friends pull it up the dune on a rope, feet slipping in the sand, ruts behind it; then the drum motor goes on the axle and the same friends try to hold it back in a tug of war they lose. Fun because the wheel width and who pulls decide whether it climbs, and the motor's worth shows in friends.
Next: friends get a mass from their mesh volume (none in the game yet); then the cart as PrintSim rigid bodies (frame, revolute wheels) on the island's terrain heightfield with physics/wheelsand.jl giving each wheel's sinkage, resistance and drive; ruts written into the terrain; the rope (XPBD) acting on each puller as a force limited by its foot traction.

## s157 (strongest idea, did not pass in 3 rounds: surprise 7, fun 6, real 6, toward 9)
- Critic's risks: poses must come from the rope's force (not a tilt), soil constants must be general (they are: Wong's table, 4 soils).
- physics/wheelsand.jl done (NOTES 'Wheels in sand'): narrow vs wide rim, towed resistance, climb table.
- Motor for it: Motor.drum_film() starts from every angle (NOTES 'The drum rotor').
