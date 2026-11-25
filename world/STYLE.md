# Art direction: The Neverending Game

A small round island in a calm sea, seen like a toy diorama. Cozy, soft, readable
at a glance. Everything looks like it could be picked up and squeezed.

## Shapes
- Chunky and rounded: domes, blobs, thick stems, soft bevels. No thin spikes, no hard
  corners, no realistic detail (generated assets: say "chunky, stylized, soft rounded shapes").
- Creatures are simple round bodies with big eyes and stubby limbs; read the species
  from the silhouette (Lumi: cream egg with a leaf lumi).
- Every species needs one shape that sticks OUT of its round body and reads from behind and from the
  side at 8 m: pig pointy ear tips, sheep curled ram horns (outside the wool), crab claws raised in a V,
  Lumi's leaf and tan satchel. Back pieces stay flat and light: a dark round bag read as a face.
- Props sit on the ground, seen from the side (never a flat disc on a pedestal).
- Small things come in groups (flowers, stones, mushrooms), big things alone (trees).

## Palette
- Ground: saturated meadow green, warm sand at the shore, warm brown paths and wood.
- The meadow is never one flat green: warm lime clearings, deep green hollows, a fine tuft grain, and a cool dark shade pool under every tree crown (plugins/meadow.jl). Trees and bushes stand IN the grass, with a darker ring at their feet.
- Water: deep calm blue, lighter at the shore.
- Accents: berry red, warm cream (Lumi), pink (pigs), soft coral (crab).
- Night lights: cool bioluminescent cyan, sky blue, lavender and mint, around a warm
  pale-yellow core; fireflies and lanterns warm yellow. Never one flat colour for all.

## Materials
- Matte and soft (painted clay / vinyl toy), little gloss. Wood warm and slightly rough.
- Things that glow: `shading = NoShading` in the raster plus a Hikari `Emission` for
  path tracing (Emission alone is a grey pebble in the raster).

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
- Clouds are clay too: plain lit spheres in clusters (bright tops, grey-blue bellies), never unlit glowing discs or
  rim shells. Many small lumps beat a few big ones; beaded strings of equal balls read as pearls, not cloud.
- A storm cloud is the same clay in slate (RGB ~0.30-0.50, a lighter lump every third), low enough (~8 m) that it
  fills the top of an eye-level frame. Cameras for weather tilt up a little so the sky event is in the picture.
- Lightning is a thin jagged white-blue line (0.86, 0.91, 1.0) that flickers on-off-on for a third of a second; in
  path tracing it is an emitter and lights the cloud's belly and the ground. Strikes leave small dark scorch marks.
- Comedy over danger: what the weather does to us is a cartoon (a puff of small grey soot, a crest on end, a
  gasp face), and the friends' answer to it is a huddle and then laughter.
