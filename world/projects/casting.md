# Casting lead in the beach sand
Goal: press anything into damp sand (a foot, a plank end, a wheel, a stone), melt lead from the scrap heap over the fire, pour it in and dig out a metal copy of exactly the hole you made: the accumulator's lead plates, a weight, a medal for a friend. A sloppy mould or a slow pour gives a sloppy casting (it freezes on the way), so pouring is a skill.
Next: (s170 in the game, published: Jump in on the beach, H stamps Lumi's foot, H pours, it freezes ~4 min, H lifts a 942 g lead foot laid toes-up beside the hole; the patch sits on the yacht's sand at its height and colour) the LOOK for a post: path trace the lifted foot again (it was a dark lump before the toes-up fix: check the conductor's brightness), a ladle in Lumi's beak instead of a bare silver stream, Lumi's stamp/pour/lift poses, the liquid's mirror shine filmed at dusk; then a plate mould (a plank end pressed twice) for the accumulator, and the casting as a real body (PrintSim affine body, mass from its cells).

## Physics (physics/casting.jl, check physics/casting_check.jl passes)
- Virtual-pipe flow on the mould's height field (cross-section = upwind depth: shallow-water speed), lead's surface
  tension front (no advance thinner than 2 capillary lengths = 4.1 mm), column temperature (Biot ~1e-3), contact
  conduction into sand e (T - T0)/sqrt(pi t), air convection + radiation, superheat then latent heat, choke at half
  frozen (critical solid fraction). Lead: rho 10660 liquid / 11340 solid (6% shrinkage), c 142, L 23 kJ/kg, Tm 327.5.
- Measured: 12x6x1 cm plate pit, 72 cm3 at 400 C: fills 9.2-9.6 mm (shrinkage), 67.7 cm3 = 0.77 kg, frozen in 73 s.
  Puddle on flat sand: 3.7 mm thick. Fluidity, 4 mm x 1 cm channel: 25 cm at 400 C, 27 at 450, 24 at 360, 31 when
  8 mm deep, 37 on dry sand (lower effusivity): every direction right, order of real spiral tests (tens of cm).
- Lumi's foot (2.2 cm stamp, 70 cm patch at 1 cm cells): 94.7 cm3 poured -> 83.1 cm3 = 942 g lead foot, frozen in
  261 s. Plugin cost 1.4 ms/frame while pouring (33 x 1 ms steps), nothing after.
- Molten lead at 400 C does NOT glow (Draper point 525 C): it is a mirror-bright silver liquid that skins dull grey.
  The look is the mirror, not orange.

## Open
- The stamp depth is fixed (2.2 cm): take it from Lumi's weight and the soil (WheelSand.bekker) and a stamp's impulse.
- The print is carved, not pressed: no berm/compaction (SandField.press! does that; use it with the foot as `under`).
- Damp sand holds steep walls; dry sand should slump the print (SandField.slump! with the soil's repose).
- The step allocates (~4 arrays/step): fine at 70x70 on the CPU; to KA kernels when moulds get bigger.
- s170 traced (media/s170-cast-traced2.png, a foot lifted mid-pour): the seam to the yacht's sand is gone; the liquid
  in the print is a real mirror (the blue sky in a footprint: THE shot); the frozen piece (Conductor ior 1.9 / k 3.5,
  roughness 0.45) traces nearly black on bright sand: check Hikari's materials.md for a measured lead/rough metal
  before the film (real lead is dull mid-grey, reflectance ~0.6).
- s170 (last): lead is now Hikari.Principled metallic (liquid base 0.86 rough 0.02, frozen 0.58 rough 0.5). Traced
  (media/s170-cast-traced3.png) the lifted piece is still dark with one highlight on sunlit sand: a rough metal shows
  the sky dome, not the sun, so it IS darker than the sand; frame it against the low sun / sky for the film.
- s170 POST TRY (movies/post_stills.jl post "castfoot", job 20261128-105153-701-clip): NOT POSTED, deleted. In the
  quiet game (-6.8,-12.2) is GRASS: my sand square sat on a lawn, Lumi stood ON the patch with its toes over the
  print, and the lead was a thumbnail between its feet. The sandbox spot only looked like beach because the yacht's
  drawn sand square covers it (beach_weight 0 there too). Next try: a real beach spot (bw > 0.5 or coast d < 3),
  Lumi 0.6 m back and to the side, the camera low across the print toward the sea, the print filling a third of the
  frame, liquid still in it (tmax 40 s).
- s170 SECOND TAKE (job 20261128-105546-715-clip, at (-10.1,-15.9)): also NOT posted, deleted. Still grass there (the
  sand strip starts ~1 m further seaward), the patch reads as a brown slab on the lawn, a flower fills the left, Lumi
  is only feet. The lead in the print DOES mirror the sky blue (good). Next take: find the spot by sampling
  NG.terrain colour / beach band in the quiet game first (look at a raster preview, rasterize = true, before the
  trace), draw the patch in the beach's own sand colour, camera 0.4 m from the print.
