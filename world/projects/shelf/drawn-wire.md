# The wire I drew burns out where I rushed it
Goal: The player pulls a copper rod through smaller and smaller holes in a stone plate with Lumi's beak; each pass the wire gets longer and thinner; rush a pass and it necks (or snaps if they keep pulling), a soft stone's hole wears and leaves the wire uneven. That wire is the wire of every circuit they build, and the stretch they rushed is where it glows first and parts. Fun because a craft you get good at pays off, or bites you, later.
Next: the drawing bench in Jump in (todo #742): the generated basalt draw plate (asset job 20261127-224908-837, s156), Lumi's beak grips the rod tip and hauls (Draw.sachs load drives the lean), the wire comes out as a copper tube; clam cells beside the posts in the picture; then the ONE-take film: haul, rush, neck, the wire on the cells bowing, glowing deepest at the neck, parting, the halves dropping. Beads at the ends: NOTES 'Drawn wire' (conduction-coupled, in circuit.jl).

## s155 (passed ideas round 2: real 7, toward 8)
- physics/draw.jl: Rod (per-segment radius, length, strain); `Draw.pass!(rod, hole; mu, alpha, stone, give, from)`.
  Sachs slab stress, Ludwik hardening (as wire.jl), Archard die wear (sandstone k 1e-4 H 1 GPa, basalt 1e-6, 6 GPa:
  guesses for copper on stone, check). Over the limit: the segment just out of the hole yields, past its Considere
  maximum it necks; the hand stops when the load fell by `give` (10%: neck 47.1 um in a 50 um wire), `give = nothing` snaps.
- Clean limit per pass: 69% annealed, 56% after strain 2 (Sachs neglects redundant work; real practice ~45-55%: high).
- 4 mm of 0.5 mm rod -> 100 mm of 0.1 mm wire in 15 passes of 20% (volume kept). On 8 cells of 0.05 Ohm: careful wire
  glows at 0.07 s and parts in the middle (seg 20/40) at 0.38 s; rushed at 25% along: glows first at the neck (seg 10)
  at 0.055 s and parts THERE at 0.275 s; rushed at 70%: seg 28. circuit.jl now takes one radius per segment.

## s156
- Camera: the clip camera HAS a zoom (`Makie.cameracontrols(scene).fov[]`); the take now zooms 28 -> 5 deg in one move.
- Glow strength 60 -> 8 (60 clipped every level to one yellow).
- physics/hotrod.jl: the wire as an XPBD elastic rod between clamped posts, rest length from thermal strain (~2% at
  melting), E(T) from 130 to ~65 GPa, own weight. 10 cm of 0.1 mm wire at 1300 K bows 8.3 mm (inextensible sine
  estimate 8.7); after parting the long half droops 8.8 mm (cantilever formula 8.2). In the film: 0.4 -> 7.4 mm in
  0.5 s after switch-on, parts at 2.5 s at segment 12, the halves swing and hang ~4 mm low.
