# The owl that hunts by ear
Goal: at night the player, as a small friend, sneaks from the hedge to the berry bush past an owl in a tree. Every step makes a sound (loud on gravel, path and dry leaves, soft on moss and grass, louder when running); the owl hears what really reaches its head through the island (acoustic ray tracing), turns to where the FIRST wavefront comes from, and glides down when it is sure. Freeze and it loses you; a step behind the cottage reaches it over the roof or off a wall, so it looks the wrong way. Fun: a stealth game where your feet and the island's shape decide, with real risk and a real escape.
Next: look at the traced film (job 20261127-024933-893-clip, site/films/the-owl-listens.mp4, pending post 'The owl listens'; the owl asset 20261127-023850-460-asset renders first). If the owl reads and turns, make it a game: Owl walk, a mini game where a small friend sneaks from the hedge to the berry bush; ground loudness (path, pebbles, leaves loud; grass, moss soft), the owl glides down when two steps in a row are loud and close to where it looks, and freezing makes it lose you. The plugin (plugins/owlears.jl) is live: at night it hears the jumped-in player's footsteps and shows its gaze as a moonlit spot.

## What exists (s132)
- physics/echo.jl `hear(tlas, backend, src, ear; rays, window = 2 ms)`: every arrival at the head with its delay, energy and the direction it comes from (`hear_kernel!`), the direct path through `los_kernel!`; returns `direct`, `t0` (first wavefront), `from` (energy-weighted direction of what arrives within 2 ms of t0: the precedence effect), `level` (dB re a unit source at 1 m, first 80 ms), `n`.
- `solid_triangles(scene)`: terrain, trees, bushes, rocks, logs, stones, gallery, pier, buildings, asset actors (meshscatter_N); no grass, flowers, creatures, particles (`SOLID_NAMES`).
- First numbers (sandbox, owl head at (-16.6, 4.7, 4.5), 9 m west of the cottage at (-7.6, 4.7)):
  footstep right behind the cottage: direct blocked, first wavefront 46.1 ms vs 39.9 ms straight, the owl's head points 28 deg off (the sound comes over the roof and off the north side), -38.3 dB;
  footstep in the meadow 9 m away: direct blocked by a hump of the ground at 0.1 m (clear at 1 m), first wavefront 26.5 ms vs 26.4 ms, 1 deg off, -25.4 dB. 20k rays: 16 ms on CPU (POCL).
- No diffraction in the tracer: a sound behind a wall arrives only by reflection and ground scatter. Real owls hear diffraction round edges at low frequencies; leave that until the game needs it.

## Ideas for later
- Barn owls have asymmetric ears (right one higher): time difference gives left-right, level difference gives up-down. With `from` the head turn is exact; noise in the estimate (fewer rays, a wind) is what makes it fallible.
- The owl's hearing could show the player: its facial disc glows faintly toward what it heard.
