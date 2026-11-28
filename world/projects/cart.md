# The friends pull my first cart
Goal: Lumi builds a wooden cart (frame, axle, wheels of a width the player chooses); the friends pull it up the dune on a rope, feet slipping in the sand, ruts behind it; then the drum motor goes on the axle and the same friends try to hold it back in a tug of war they lose. Fun because the wheel width and who pulls decide whether it climbs, and the motor's worth shows in friends.
Next: (s160 PASSED 'Lay the plank road on sand that really moves'; physics/sandfield.jl done: GPU sand field that keeps ruts, berms, slumps to repose, planks resting by Bekker and see-sawing) a dune plugin: the field as a traced sand mesh on the real dune, planks the player picks up and drops in Jump in (rigid bodies whose pose comes from plank_rest each frame), Lumi's and the friends' feet pressing prints; then the empty cart pushed across by three friends.

## s157 (strongest idea, did not pass in 3 rounds: surprise 7, fun 6, real 6, toward 9)
- Critic's risks: poses must come from the rope's force (not a tilt), soil constants must be general (they are: Wong's table, 4 soils).
- physics/wheelsand.jl done (NOTES 'Wheels in sand'): narrow vs wide rim, towed resistance, climb table.
- Motor for it: Motor.drum_film() starts from every angle (NOTES 'The drum rotor').

## s158: passed (round 3): "one sand law for feet and wheels" (surprise 7, fun 7, real 7, toward 8)
- Critic's risk: the bodies. A statics lean + step trigger can look like a stiff puppet sliding; the friends must look
  like characters putting their weight into the rope, or the sand law only shows as scrapes under a pose.
- Done: physics/wheelsand.jl `foot` (Bekker + Janosi-Hanamoto + Rankine ridge), `foot_creep`, `lean`; cart_climb uses
  the feet (NOTES 'Feet on sand'). One 8 kg friend now pulls the 12 kg cart up 10 deg.

## s160: passed (round 2): "Lay the plank road on sand that really moves" (alike 2, surprise 7, fun 7, real 7, toward 8)
- Goal: 12 planks and a dune; lay them where the sand is softest, three friends push the empty cart up; ruts where you
  left gaps, plank ends sink and see-saw as a wheel crosses; fewest planks wins, the dune changes with tide and wetness.
- Critic's risk: the planks. If they only sit on the field instead of rocking as rigid bodies it is Bekker numbers
  drawn as a dent; the 'fewest planks' puzzle needs the dune to change from day to day.
- Done s160: physics/sandfield.jl (NOTES 'Sand that keeps what pressed it'): compaction (once per cell) + displacement
  to the nearest free cells (Sumner 1999) + mass-exact repose slumping; plank_rest (heave/pitch/roll from Bekker
  pressure per cell, no pull). Numbers: a cart wheel (35 kg cart, 4 wheels) leaves a 22 mm rut with 11 mm berms; a
  wheel carrying 3 friends' share (1470 N) BOGS alone on a 5 cm rim but on a 1 m plank sinks it 8 mm; at the plank's
  quarter it tips 1.7 deg (near end -20 mm, far end lifts +9 mm); 5 cm from the end the plank kicks up 26 deg.
  GPU (Mantle, Radeon 8060S): press + 8 slump sweeps on 400x120 cells at 5 mm: 3 ms. Pictures: media/s160/
  rut-hillshade-a.png, plank-bed-hillshade-b.png (hillshades, not posts).
- Missing: plank dynamics (it is quasi-static, no inertia: the kick-up should be a real rotation with the PrintSim
  rigid body), plate width in Bekker for a small tipped contact, wet sand (repose, kc/kphi with moisture), the dune.
