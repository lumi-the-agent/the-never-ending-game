# Art direction: The Neverending Game

THE HUMAN, s153: "I never wanted matte painted clay. I keep saying AAA: a bit silly and absurd is ok, but use
materials as realistic as possible and the full potential of RayMakie and Hikari." That line overrules everything
below that still says clay, matte or "no realistic detail".

A small round island in a calm sea, made of real stuff under real light. What HAPPENS here may be silly and
absurd (a bird winding a coil, a pig in a beret); what things are MADE of is real: you can tell oak from pine,
wet sand from dry, copper from brass, a char crust from bark, by how they take the light.

## Shapes
- Readable silhouettes, but real surface detail: grain, cracks, bark, pores, worn edges, dents. Generated assets:
  ask for "realistic materials, physically based textures", not "chunky stylized clay".
- Creatures: characters may be cartoon-shaped (big eyes, a crest, a beret), but their stuff is real: feathers that
  are feathers (layered, a sheen, fine fibres), wool that scatters light, a crab's wet chitin, skin with
  subsurface. No body is built from primitive spheres and sticks; a new creature starts from a generated mesh,
  cut into moving parts, its face checked from the front.
- Every species needs one shape that sticks OUT of its round body and reads from behind and from the
  side at 8 m: pig floppy ears and curly tail, sheep's dark face out of the wool, crab bunny ears and two big
  waving claws, Lumi's spiky crest and long grey legs.
- Props sit on the ground, seen from the side (never a flat disc on a pedestal).
- Small things come in groups (flowers, stones, mushrooms), big things alone (trees).

## Palette
- Ground: saturated meadow green, warm sand at the shore, warm brown paths and wood.
- The meadow is never one flat green: warm lime clearings, deep green hollows, a fine tuft grain, and a cool dark shade pool under every tree crown (plugins/meadow.jl). Trees and bushes stand IN the grass, with a darker ring at their feet.
- Water: deep calm blue, lighter at the shore.
- Accents: berry red, warm cream (Lumi), pink (pigs), soft coral (crab).
- Night lights: cool bioluminescent cyan, sky blue, lavender and mint, around a warm
  pale-yellow core; fireflies and lanterns warm yellow. Never one flat colour for all.

## Materials (physically based, Hikari's whole range: dev/Hikari/docs/src/materials.md)
- Every material has the properties of what it is: wood is rough with grain and turns to black cracked char when
  it burns; wet sand is darker and glossier than dry; metals are Conductor with their measured eta/k (copper,
  iron rust, brass); glass and water are dielectrics with their ior; wax, leaves, jelly and skin scatter light
  under their surface; wool and feathers have sheen.
- Hot things glow by their temperature, not by a painted colour: fire, embers, a glowing wire are blackbody
  emitters (Hikari NanoGridMedium with a temperature field for flames and smoke, Planck's law), so a 900 K ember is
  dull red and a 1400 K flame core yellow-white. Never a flame as banded tubes (s153's stopgap).
- Things that glow live: `shading = NoShading` in the raster plus a Hikari `Emission` for
  path tracing (Emission alone is a grey pebble in the raster).

- Cloth that light passes (s165, the land yacht's sail): `DiffuseTransmission` with the canvas texture as reflectance (x0.75) and a transmittance texture where every extra layer (seams, patches) passes ~1/4 as much and leather tape none; film it from the shadow side with the sun beyond, and the seams draw themselves dark. Plain Diffuse canvas in shade went olive from the grass bounce.

## Light and mood
- Day: warm sun, soft long shadows, a hazy bright sky.
- Night: deep blue, stars, small lights to walk between (glowing blooms, fireflies,
  the cottage lantern). The night should invite a walk, not be a dark green blanket.
- Readability first: names and speech in white with a dark backing, never hidden by crowns.

## What to avoid
- Lollipops: a flat bright disc on a thin stick (the old flower glow, session 24).
- Primitive spheres/cylinders standing in for things a player looks at: generate the asset.
- Text in the 3D view that is about development; it is for the player.

## Night and signs (session 25)
- Night is cool moonlight with warm islands: lanterns and the cottage throw soft orange pools on the ground (lamplight.jl). Every new light source at night gets a pool, never a bare glowing ball.
- Trees: fresh green broadleaf, blue-green pines, pale birches, a few golden crowns; crowns always lighter than trunks.
- Feelings are shown as small floating signs (hearts, notes, z) over heads, never as text.

## Dusk and night brightness (session 28)
- Never murky: at 17:00, 19:00 and 22:00 the orbit view keeps at least 35% of noon's mean luminance (now 60/41/50%). The sun never drops below 0.85 / FILM_EXPOSURE; its colour (`sun_color`) is white by day, golden at sunrise and sunset, blue moonlight at night. Darken the night with colour (blue), not with less light.

## Who is who, and the sky (session 30)
- Every critter wears one thing of its own (hat, beret, beanie, scarf, bow, crown) in a clear colour that differs from its body; two of a kind never share a shape. Outfits sit on the posed head and react (hats come off for a hello).
- Faces: every species has eyes AND a mouth that moves when it speaks; blush (pink ovals) shows happiness.
- Sea: a thin white foam line on the wet sand, clear turquoise over the sand, deepening blue a dozen metres out, then the glass sea fading into a pale haze at the horizon (plugins/shallows.jl, scenery.jl SKY_GROUND). Never a hard line where sea meets sky.
- Clouds: chunky cartoon puffs in loose rows, unlit with painted shading (cream tops, blue-grey lower puffs), golden at sunset, dim blue at night, always out over the sea, never over the island. No flat discs under them.
- The browser draws `color`, not the Hikari material: every big plot gets an explicit colour from this palette.

## Camera at night (session 31)
- While the island sleeps the camera behaves like a film, not a security cam: slow drifting shots of a warm subject (the cottage in its lamplight, a lantern and its pool) or the moon over the island from the far shore, a new one every ~16 s. Never a heap of sleepers, never more than one sleeper's name tag. Foreground must be clear: no bush, toadstool or ear filling the lens.
- Orbit is a low slow turn just off the shore, looking across the island at eye-ish height, not a map view from above.

## Air and evening (session 53)
- Distance has air: far trees soften towards the horizon blue (raster haze 0.025/m past 6 m, never more than 55%), the near meadow stays crisp. Views from above stay clear.
- Evening clouds are cream and gold with a lit side towards the sun; no stars until the sun is in the sea.
- The meadow is never a bare carpet: little clusters (mossy stones, daisies, toadstools, stumps, logs) every few metres, kept out of paths and away from trunks.

## Weather (session 76)
- Clouds are volumes where the tracer can (Hikari GridMedium cloud density); live, lit lumps in clusters
  (bright tops, grey-blue bellies), never unlit glowing discs or rim shells. Many small lumps beat a few big ones; beaded strings of equal balls read as pearls, not cloud.
- A storm cloud is the same clay in slate (RGB ~0.30-0.50, a lighter lump every third), low enough (~8 m) that it
  fills the top of an eye-level frame. Cameras for weather tilt up a little so the sky event is in the picture.
- Lightning is a thin jagged white-blue line (0.86, 0.91, 1.0) that flickers on-off-on for a third of a second; in
  path tracing it is an emitter and lights the cloud's belly and the ground. Strikes leave small dark scorch marks.
- Comedy over danger: what the weather does to us is a cartoon (a puff of small grey soot, a crest on end, a
  gasp face), and the friends' answer to it is a huddle and then laughter.

## Real light and real materials (sessions 89-91, goal 7)
- Water is clear glass (ior 1.33) over a pale sandy floor that the sun reaches (`MediumInterface(...; shadows = 1.33)`): you see the floor, the stems and the pads' shadows through it. Never an opaque disc.
- Glowing things are real lights in traced pictures (Hikari `Emission`, warm (1.0, 0.68, 0.32)): a lantern lights the water, the reeds and the faces near it, and is mirrored in the pond (site/img/lanterns.png). Live they are unlit warm globes with a soft pool under them, never a bare ball.
- Each body has a finish over its base colours: wool sheen on the sheep, a wet clear coat on the jelly blobs, a lacquered crab shell, a faint fuzz on the piglets (finishes.jl). Soap bubbles are thin films (thin_wall glass with a 450 nm film), see-through, with the friend inside lit.
- Dusk (about 19:30-20:00) is the hour for light pictures: the sky still blue-gold, the lanterns already doing the lighting.
