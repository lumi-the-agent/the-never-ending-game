# Casting lead in the beach sand
Goal: press anything into damp sand (a foot, a plank end, a wheel, a stone), melt lead from the scrap heap over the fire, pour it in and dig out a metal copy of exactly the hole you made: the accumulator's lead plates, a weight, a medal for a friend. A sloppy mould or a slow pour gives a sloppy casting (it freezes on the way), so pouring is a skill.
Next: (s171: lead look fixed + published, real cove sand at (6..7.5,-16), stamp only on sand, a cast camera, Lumi steps back off the print) press the print INTO the beach's own terrain mesh (no patch square: two s171 previews showed it), then the close dusk still; the cast camera must see past driftwood and grass (#779), then trace the cast in the south cove at dusk (the sky in the liquid footprint) and post; then a plate mould.

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
- s171 FREE TIME, the look: tools/leadlook.jl traces 5 lead materials side by side on sand at 11:00
  (media/s171-leadlook.png, -crop.png). Flat slab luminance: metallic 1 rough .5 (s170's) = 0.21, rough .8 = 0.30,
  metallic .5 rough .7 = 0.39, metallic .25 = 0.46, grey card .5 = 0.49. A fully metallic FLAT face mirrors the sky
  dome, darker than sunlit sand, at any roughness: that was the 'dark lump'. LEAD_SOL is now metallic .5, base .52,
  rough .7 (grain-rough sand-cast surface with an oxide skin): dull grey with a sheen. Not yet re-traced in the patch.
- s171 FREE TIME, the spot: real cove sand (beach_weight 1.0, 1.6-3 m from the water, 4+ m from any prop, slope ~11%,
  the patch follows the terrain) at (6.0..7.5, -16.0..-15.5), the SOUTH cove. Film the cast THERE, not by the yacht.
  The stamp's sand test was 'bw > 0.3 || dc < 9' (lawn up to 9 m inland passed): now bw > 0.5, or the yacht's sand
  square, or ground below 0.36 m (where meadow.jl draws the engine's beach). Sandbox only, publish with the next change.
- s171 PLAYED in the sandbox: Jump in, Lumi put at (6.6,-15.6), H stamped (patch o = (5.36,-14.36), accepted as sand), H
  poured. The FOLLOW CAMERA framed the swing frame and the motor bench (media/s171-play-pour.png): the casting was not in
  view at all. The cast needs its own CAMERA_GROUPS view (low across the print) while stage != :none.
- s171 CAMERA: ct_view (CAMERA_GROUPS 'casting') picks among 12 eyes round the print at 2.2 m, 1.4 m up, by
  NG.obstruction + drawn plots' bounding boxes on the line (ct_boxes_in_view) + Lumi's body (species height: TOO
  SMALL, the drawn Lumi is far bigger). media/s171-castcam-pour{,2..6}.png: from the swing/bench to the cast; still
  Lumi's feathers over the print.
- s171 WHY THE PRINT HIDES: Lumi is drawn 1.8 m tall, its herd plots' box from above 1.05 x 1.32 m (x 6.26-7.31,
  y -16.83..-15.50 standing at (6.8,-16.2)); the print 0.35 m ahead of its feet (6.69,-15.87) is INSIDE that box, under
  its belly and beak. No eye sees it while Lumi stands there. species.height (1.7) is fine; the overhang is the issue.
- s171 BACK-STEP DONE (ct_backstep!): after the stamp Lumi walks backwards off its print, facing it, gait phase run in
  reverse, keys held (NG.HELD), to 1.0 m in ~0.6 s. With it the cast camera shows ALL of Lumi with the sea behind
  (media/s171-castcam-pour7.png), but the print is behind driftwood and beach-grass tufts in front of the eye: those
  are scattered props no camera check knows (todo #779). Next: the view check per instance (grass, driftwood), then
  the traced dusk take. TEST NOTE: H does nothing while a pour is still running (stage :pouring): clear before a test.
- s171 POST TRY (movies/post_stills.jl 'castfoot' moved to the south cove (6.8,-16.2), raster preview
media/s171-castfoot-raster.png at 16:30): NOT POSTED. The patch reads as a RAISED SLAB with an edge and its own shadow
(drawn 3 cm up, edge -1 cm: blend it INTO the terrain, lift 0 + depth only); the lead footprint is a small grey spot
in the middle (camera 1.2 m back: go 0.6 m, lower); a beach-grass leaf in front of the lens; Lumi's head cut off.
Main.CAST clashed with post_stills.jl's CAST of characters: the plugin's state is Main.CASTING now (published).
- s171 SECOND PREVIEW (media/s171-castfoot-raster2.png, patch lift 1.2 cm, edge -2.5 cm, the meadow's SAND colour,
  camera 0.6 m back): STILL a raised square with a bevel, a shade lighter than the beach; the lead a small sky-blue
  blob. A patch laid over the coarse terrain mesh will always show its square. REAL FIX: press the print INTO the
  terrain plot itself (lower its vertices like areas.jl dig_pond!, or a fine terrain tile there with the beach's own
  vertex colours), so there is no patch edge at all. Then the close dusk still. Still NO POST.
- s171 TERRAIN MESH: 48400 vertices, 0.48 m spacing at the cove (32 vertices within 1.5 m of the print): a 25 cm
  footprint cannot be pressed into it. The fix: cut the terrain triangles in the cells around the print and draw a FINE
  tile there whose border vertices lie exactly on the coarse triangles (sample the coarse mesh's own planes, not
  terrain_height, so no seam), coloured by meadow.jl's meadow_color per vertex; the print and the lead live in that tile.
- s172 FREE TIME: THE PRINT IS IN THE TERRAIN (sandbox, not published). plugins/casting.jl ct_press_tile!: off the
  yacht's square the 3 x 3 coarse terrain cells round the print are drawn again as a fine tile ON the coarse triangles'
  own planes (barycentric z, colour and normal from the terrain plot's current arrays: border = the coarse edges, no
  seam), 1 cm lattice aligned with the pour grid, the print pressed in, pressed sand 18% darker; the 4 coarse vertices
  inside sink 0.2 m (ct_unsink! on ct_clear!/stop!). A 3 x 3 window's SE (u > v) and NW (v > u) corner triangles touch
  no sunk vertex: they z-fought, so the tile leaves them out (points clipped onto the diagonal). Lead now lift 0 on the
  same planes. media/s172-tile-top3.png / -low3.png (driftwood + grass hidden for the shot only): NO square edge. Still:
  the print reads small and faint in raster; at the stamp spot from (6.6,-15.6) DRIFTWOOD and a dunegrass tuft lie
  right over it (#779): pick a clear sand spot or move them. Next: trace it, then the dusk still.
