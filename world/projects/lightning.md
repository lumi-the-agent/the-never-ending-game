# Lightning makes a lodestone
Goal: When a storm rolls in, the player races to plant copper rods and iron spikes on the hill; the strike picks its own path through what stands there (a good rod takes it into the ground, a lone iron spike comes out a magnet), and afterwards you dig glass roots out of the sand where it went in. You make magnet stones by catching lightning: a race against the weather with consequences you dig up.
Next: the stepped leader: from the cloud base, step 10-50 m toward the strongest field of physics/estatic.jl (conductors the player placed, the island's ground as the earthed plane), attach by the striking distance r = 10 I^0.65; draw the path as a traced emitter at night. Then the return stroke's Biot-Savart field magnetising the spike (softiron.jl hysteresis), then the fulgurite from Joule heat in the sand.

## s153 (passed as the strongest of three idea rounds; the critic: surprise 8, fun 7, real 6)
- The critic's worry: the cloud's charge layer as a number someone sets, fulgurite as a melt threshold, many systems
  in one go. Answer: the cloud's charge from the weather's updraft later; fulgurite from the energy the current puts
  into the sand, not a temperature switch. One system per session.
- physics/estatic.jl: earthed conductors as boundary-element panels over an image ground in the storm's field.
  Selftest (rod with a hemispherical cap, field 2 radii above the tip over E0): h/r 100 -> 8.7, 200 -> 15.3,
  40 -> 4.4; Forbes' formula for a capped rod (beta = 1.2 (h/r + 2)^0.9, falling ~ 1/9 at 3 r from the cap centre)
  gives 8.6, 15.9, 3.9: within 10%. 0.1 s for 960 panels (dense solve; bigger scenes need the GPU or a fast multipole).
