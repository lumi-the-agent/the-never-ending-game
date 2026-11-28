# Form the plates the way Plante did
Goal: (passed s182, round 2: surprise 7 fun 7 real 7 toward 9) The player hangs two cast lead sheets in a jar of dilute acid, wires them to the pots and forms them: charge until they fizz, reverse the leads, charge again. Every reversal eats deeper into the lead and the jar holds more charge, but a lazy player who just leaves them on gets mostly bubbles. How much the cart can carry tomorrow is how well you formed tonight.
Next: WATCH the film (job 20261128-203732-233-clip -> media/s182-plante-b.mp4, copied to site/films/plante-swaps-the-leads.mp4 by 20261128-203732-631-run; pending post pending/plante-swaps-the-leads.json waits on those two). An OLD take (job 202255-902, thick glass, unreadable) lands first and is copied to the same film path by 202255-930: the new take overwrites it later. Test frames media/s182-plante-frame{,2,3,4}.png: frame 4 (ThinDielectric jar, side view) reads as a jar, but the PbO2 reads as cardboard and B hides behind A. Then make the jar a FAST plugin (projects/plante/plugin-draft.jl was 430 ms/frame), the swap by Lumi's own wing (J in Jump in), then the cart drawing from the formed pair.

## s182: physics/plante.jl (module Plante)
- Each plate: formed depth d, share x of the layer that is PbO2, fresh film on the bare lead under it. Current splits
  between the solid reaction and water splitting by Tafel kinetics at the plate's one potential (bisection), the pots
  as 5.2 V behind 3.8 ohm, acid 0.05 ohm. Constants (orders): PbSO4/PbO2 1.69 V b 0.04 i0 0.1 A/m2; O2 on PbO2 1.229 V
  b 0.12 i0 1e-5; PbSO4/Pb -0.356 V b 0.04 i0 0.1; H2 on Pb 0 V b 0.12 i0 1e-8 (Pavlov 2011; Bockris & Reddy).
  Layer inner surface a_v 2e5 m2/m3, porosity 0.5, passivating film e-folds at 0.15 um.
- Results, 6 h from the pots at ~0.57 A, plates 0.03 m2: left on one way 0 Ah (the negative only makes H2, nothing to
  discharge; 2.2 L of gas); reversed hourly 0.246 Ah (both ~5.6 um deep); every 15 min 0.093 Ah (deeper, but the last
  short charge leaves the positive unfinished). Cell 2.9-3.1 V while forming (high: lead's H2 overpotential).
- After a swap the jar goes quiet for ~20 min (A's oxide reduces, B's spongy lead oxidises) before O2 (~45 min) and H2
  (~53 min) come back: that's the film (movies/plante.jl, rate 600 chemistry s per film s, swap at 3 s).
- What is still lumped: one potential per plate (no current distribution), the acid's strength does not change with
  charge (no Nernst on H2SO4), no self-discharge, the oxide's patchiness is drawn from thresholds (edges first),
  not solved.
