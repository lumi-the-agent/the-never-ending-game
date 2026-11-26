# The sea freezes into glass
Next: bumps the lens SEES: in the film shot, push pairs of friends at each other at 2-3 m/s in front of the lens, and a soft wall round the skating ground so nobody slides out of frame or into the lens; then frost marks (skate tracks that stay), and me on the ice jumped in (todo #608). Posted take 2 (site/films/glass-sea-2.mp4): the freeze reads; no bump shows.

The idea (s126, the critic's strongest of three rounds: surprise 6, fun 7, "too expected" but no likeness penalty):
one cold morning the sea round the island is clear hard glass, fish hang frozen mid-swim under it, and the friends
slide out, slip, bump and spin. Critic: it only counts if the sliding is simulated, not friends drifting, and if
caustics really converge (they cannot yet: see Next).

- plugins/glasssea.jl: 7:00-7:30 once a day for 90 s; Main.GLASSSEA[:force] = true, [:at] = (x, y).
  A clear slab (Hikari Glass ior 1.31, 5 cm) over the glass sea, 14 orange fish (meshscatter) frozen under it.
  The 5 friends nearest the shore trot down, then glide: friction 0.12/s, a skating push every 1.6-3.8 s (back to the
  middle when > 7 m out), the shore bounces a slide back, equal-mass elastic bumps (restitution 0.85) that spin both
  bodies; a hard bump says a line and emits :glasssea_bump. Forced freezes wake sleepers.
- Film: movies/glasssea.jl `glasssea_clip(path; center = (25.6, 6.9), dist = 6.5, up = 0.9)`: five friends placed
  on the ice in a ring, pushed inward so they meet in the middle; the lens low on the ice, out at sea, island behind.
- Sandbox s126: friends at (27, 1)..(31, 7) still sliding 1-2.6 m/s after 8 s. Hopscotch stayed on land at (7, 7.9)
  trotting in place (something else holds it): check which plugin.
- Take 1 traced (s126, site/films/glass-sea.mp4, 7.8 s, 4 min on the worker; posted 22:03 'The sea froze'; sheet
  media/s126-glasssea-take1-sheet.png): the sea is a perfect mirror and the friends stand on their own reflections,
  slide apart, Gloop glides up to the lens. Beautiful, but it reads as walking on still water, not on ice; the fish are
  invisible (the reflection wins at that angle). Sandbox raster: the ice does not show at all (clear glass over glass).
- s126 critic on take 1 (redo): no freezing is seen (the sea is a mirror from frame 1), warm noon light, nobody visibly
  bumps or spins, friends slide INTO the lens, a blue friend sinks through the ice at the end, brown egg shapes hover.
  Retakes: ice frosted (roughness 0.22), the film starts on water with the friends on the beach and freezes at 1.2 s,
  hour 7.5. Take 2 (glass-sea-2.mp4, center (25.6, 6.9)): friends far and small. Take 3 (glass-sea-3.mp4, center
  (22.7, 6.12), dist 6, side 3.5, up 1.4): closer; the crabs and blobs still slide out to the left, the sheep at the lens.
  Bumps need aiming: push pairs at each other in the shot, and keep sliders inside a box the lens sees (a soft wall).
- Take 3 traced (site/films/glass-sea-3.mp4, not posted; sheet media/s126-glasssea-take3-sheet.png): closer and the freeze
  reads, but the blue blob slides into the lens at 6 s and the last 3 s are empty ice. Take 2 stays the post.
- s126 critic on take 2 (redo): the frosted ice reads as calm water at DUSK (dark glossy mirror, no white, no frost, no
  cracks); friends walk at walking pace, nobody glides; they bunch at the frame edges; a grey blob clips the top-left
  corner in every frame (something at the lens: check before the next take); brown double oval floats beside the blob.
  Post trimmed to 7 s, caption now "I tried to freeze the sea...". Next take: WHITE frost (a pale diffuse/rough layer or
  white specks and cracks), faster glides (push at 3+ m/s once on the ice), all five friends on the ice.
