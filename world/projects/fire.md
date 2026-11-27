# Fire that spreads through whatever it touches
Goal: The player lights fires on purpose (a campfire to cook fish, coals for the kiln, a hot wire in dry grass) and has to keep them from spreading: dig sand into a firebreak, wet the grass from the pond, drag the stool away. Wind shifts, a spark jumps, a wooden fence catches and sags. Every fire is a small fight you can win or lose, and the island remembers it (char, ash, a burnt stump).
Next: (s153: flames are hot gas with Planck emission in the tracer, physics/flamevolume.jl; film retake site/films/campfire-in-the-wind-2.mp4 -> swap into the post) the live campfire plugin draws the gas flame when path traced, and real wood (grain, char crust) for the logs; then Lumi fights it with its beak for real: carries sea water to it, kicks sand on embers (todo #726); then the island's wood props burn by what they are, and the grass bed (todo #727); then a hot wire as the igniter.

## Where it is (s152, passed idea round 2)
- physics/fire.jl: FireBody (lumped heated skin, moisture boils first, piloted ignition, burning flux G, char rate
  0.65 mm/min, EN 1995-1-2 reduced section -> capacity -> break -> `fall!` downwind), merged flames (Heskestad height,
  Thomas lean, point-source radiation chi_r = 0.3, immersed-flame flux ~45 kW/m^2), `water!`.
- Measured (4 logs 82 kW, stakes 7x7 cm x 1 m, 2 m/s wind): the stake 0.45 m downwind catches 1.8 min, breaks 8.9,
  out 15; stakes beside it (0.35 m off-axis) and upwind stay; calm air: nothing catches (the nearest stakes dry at 100 C).
- movies/fire.jl: film at (-3.0, -16.0) south shore (the clearest spot on the island, NOTES), 20 min in 12 s, hour 18.3.
  Job 20261127-194905-909 -> site/films/campfire-in-the-wind.mp4 (pending post `campfire-in-the-wind`).

## Known gaps (to be honest about)
- (solved s152) Burning rate from the surface heat balance (own flame emissivity 1-exp(-0.8 D) of the merged fire
  + other flames - char surface re-radiation) / L_g 1.8 MJ/kg; out below 3 g/m^2s: a lone stake dies in a second,
  the crib holds at 7.7 g/m^2s (56 kW). The film job (909) was queued before this: its crib burns at the old 82 kW.
- Contact zone = a cylinder round the leaning flame axis, not the flame's real shape.
- Flames in the film are emissive cylinders (tongues), no smoke yet; no embers, no ash.
- CPU loop over pairs: fine for tens of bodies; hundreds (grass) need the Mantle kernel and Raycore queries.

## s153: flames as hot gas
- The human (s153): real materials, not painted clay. The flame is now a temperature field round the merged flame's
  leaning axis (1400 K core, cooling with height), soot absorption 7/m, emission sigma_a * B(T) at 610/550/465 nm
  (Hikari RGBGridMedium). Looks like a real campfire (media/s153/gas-frame4.png). The banded tubes
  (flamelook.jl) stay only for the live raster.
