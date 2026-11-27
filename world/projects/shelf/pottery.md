# Throw a pot, glaze it, open the kiln
Goal: the player throws a jug on a kick wheel, cuts lines into it with a stick, dips it in glaze and fires it in the kiln by the cottage; when the kiln opens the jug looks the way they made it (cuts fill with darker glaze, a ring they pinched up breaks to bare clay at its top, a thick dip runs at the foot). Every jug is different and you get better at it: how deep to cut, how long to dip.
Next: todo #678, the potter's wheel in Jump in (shape the profile with the mouse, cut lines where the beak points) and a kiln that fires it with `Glaze.fire_ka!` on Mantle (1.3 s); its film shows the jug pale celadon (the posted first-jug film is dark olive: colours were linear, fixed with jug.jl `glaze_rgb`). Then #679 (lip curvature, drips).

## What exists (s141)
- physics/glaze.jl: molten glaze as a thin film (lubrication equation: h^3/(3μ) times surface-tension pressure gradient
  and gravity), explicit, dt 5 ms at a 0.5 mm grid, μ 300 Pa s, σ 0.3 N/m; Beer-Lambert colour `Glaze.celadon(h)`
  (olive: blue absorbed most, little bubble scatter). Started from the Cleveland Museum's 13th-c. celadon wine pot
  (workbench s141): its incised lines are darker and its rims pale, and my solve gives the same unasked.
- movies/kiln.jl: `fire_jug` (cuts: 6 double vertical lines, a double ring, a pinched ring; foot wiped bare),
  `jug_mesh` (outside + inside + lip + floor, vertex colours), `kiln_clip` (half orbit at (4,-16.5), 4 pm),
  material Hikari CoatedDiffuse (clear coat ior 1.52 over the colour seen through the glaze).
- Numbers (s141 full jug): between lines 0.34 mm, in a cut 0.61 mm, on the pinched ring 0.10 mm, top drains.
- Not modelled yet: the profile's own curvature (the solver sees only the cuts, so the lip does not break),
  bubbles and mottling, crazing on cooling, glaze dripping off the foot.
- Pictures: media/s141-celadon-pair2.png (museum pot left, my patch on a pot right).

## s141, in the game
- plugins/kiln.jl: the jug stands at (4,-16.5) by the chip stone, fired on a thread at start (CPU, ~10-20 s), mesh coarsened 3x2
  (233 x 145 points; 1.6 mm cuts still show). Published 10:07; jug_fired event in the human's game. Screenshot media/s141-kiln-live.png.
- GPU: `Glaze.fire_ka!(h, b, Mantle.Device())`, two KA launches per step (fluxes with inline curvature, then update):
  12000 steps on 700x290 in 1.3 s, matches the CPU to 5e-5 mm. Not yet used in the game (the thread firing is fine for one jug).
- The raster shows the jug darker olive than the tracer preview colours (vertex colours under CoatedDiffuse); check the traced film.
- Colour: Glaze.celadon is LINEAR reflectance; plots take sRGB. physics/jug.jl `glaze_rgb` encodes it (s141 first film was muddy olive before that).
- Post (s141): 'My first glazed jar', site/films/first-jug.mp4 cut to 0.4-5.4 s of media/s141-firstjug-full.mp4 and cropped
  (critic: fade-in frame, a leaf and a red thing at the edge, no handle = a jar). The wheel needs a pulled handle to make a jug.
- Critic on the jar film (ready, minor): the glaze reads matte except where the sun glints (frames 13-16): try a lower coat
  roughness (0.03 -> 0.01) and a camera that catches the sun's reflection; the belly lines read RAISED and pale (the pale halo
  beside each groove wins over the dark groove at this size): deeper or wider cuts, or the sRGB-fixed colours (the film used
  the old dark linear ones), should make the groove itself the dark line.
