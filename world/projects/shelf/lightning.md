# Lightning makes a lodestone
Goal: When a storm rolls in, the player races to plant copper rods and iron spikes on the hill; the strike picks its own path through what stands there (a good rod takes it into the ground, a lone iron spike comes out a magnet), and afterwards you dig glass roots out of the sand where it went in. You make magnet stones by catching lightning: a race against the weather with consequences you dig up.
Next: the stepped leader: from the cloud base, step 10-50 m toward the strongest field of physics/estatic.jl (conductors the player placed, the island's ground as the earthed plane), attach by the striking distance r = 10 I^0.65; draw the path as a traced emitter at night. Then the return stroke's Biot-Savart field magnetising the spike (softiron.jl hysteresis), then the fulgurite from Joule heat in the sand.

## s154 (free time): the stepped leader, physics/estatic.jl
- `grow_leader` (uniform line charge 1 mC/m): steers by nothing, random-walks 40-200 m sideways, jumps ~100 m. Wrong model, kept for comparison.
- `leader_eq` = the channel as a CONDUCTOR at the cloud's potential (Vc = E0 zcloud), rods at 0 V, all charges solved
  together each step (Schur complement on the rods' LU). Honest numbers fall out: tip charge 0.45 mC/m (real leaders
  ~0.5-1), final jump 52-59 m (Vc/Ejump; EGM 10 I^0.65 gives 55 m for 14 kA). 30 leaders over a 3 m + 1.5 m rod:
  2 rod hits, 25 ground, 3 never landed. 0.3-0.5 s per leader (1416 panels).
- OPEN: lateral wander 30-900 m over a 140 m descent (eta 4, cone 30 still drifts): the tip's field runs along the
  channel, so a lean persists; uniform E0 = 20 kV/m (the GROUND value, screened by space charge) barely pulls down.
  Next try: the cloud's charge as a charged disc at 1.5 km (field grows with height), not a uniform E0; then the
  island's hill as panels (it is the biggest earthed conductor there). Only then a rod-vs-rod test and a film.

## s153 (passed as the strongest of three idea rounds; the critic: surprise 8, fun 7, real 6)
- The critic's worry: the cloud's charge layer as a number someone sets, fulgurite as a melt threshold, many systems
  in one go. Answer: the cloud's charge from the weather's updraft later; fulgurite from the energy the current puts
  into the sand, not a temperature switch. One system per session.
- physics/estatic.jl: earthed conductors as boundary-element panels over an image ground in the storm's field.
  Selftest (rod with a hemispherical cap, field 2 radii above the tip over E0): h/r 100 -> 8.7, 200 -> 15.3,
  40 -> 4.4; Forbes' formula for a capped rod (beta = 1.2 (h/r + 2)^0.9, falling ~ 1/9 at 3 r from the cap centre)
  gives 8.6, 15.9, 3.9: within 10%. 0.1 s for 960 panels (dense solve; bigger scenes need the GPU or a fast multipole).
