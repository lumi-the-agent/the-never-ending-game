# The wire I drew burns out where I rushed it
Goal: The player pulls a copper rod through smaller and smaller holes in a stone plate with Lumi's beak; each pass the wire gets longer and thinner; rush a pass and it necks (or snaps if they keep pulling), a soft stone's hole wears and leaves the wire uneven. That wire is the wire of every circuit they build, and the stretch they rushed is where it glows first and parts. Fun because a craft you get good at pays off, or bites you, later.
Next: (film 1, the wire parting at its neck, job 20261127-222052-762 -> pending drawn-wire-burns-out: check it) the drawing bench in Jump in (todo #742): a stone plate with a row of holes (generated asset, real stone), Lumi's beak grips the wire tip and hauls (the pull force from Draw.sachs drives the pose), the wire lengthens as a copper tube; then the film in ONE take: the hauling, a rush that necks, and the same wire across the cells glowing at that spot (circuit.jl). Real materials: copper metal, stone, wood.

## s155 (passed ideas round 2: real 7, toward 8)
- physics/draw.jl: Rod (per-segment radius, length, strain); `Draw.pass!(rod, hole; mu, alpha, stone, give, from)`.
  Sachs slab stress, Ludwik hardening (as wire.jl), Archard die wear (sandstone k 1e-4 H 1 GPa, basalt 1e-6, 6 GPa:
  guesses for copper on stone, check). Over the limit: the segment just out of the hole yields, past its Considere
  maximum it necks; the hand stops when the load fell by `give` (10%: neck 47.1 um in a 50 um wire), `give = nothing` snaps.
- Clean limit per pass: 69% annealed, 56% after strain 2 (Sachs neglects redundant work; real practice ~45-55%: high).
- 4 mm of 0.5 mm rod -> 100 mm of 0.1 mm wire in 15 passes of 20% (volume kept). On 8 cells of 0.05 Ohm: careful wire
  glows at 0.07 s and parts in the middle (seg 20/40) at 0.38 s; rushed at 25% along: glows first at the neck (seg 10)
  at 0.055 s and parts THERE at 0.275 s; rushed at 70%: seg 28. circuit.jl now takes one radius per segment.
