# Climb anything
Goal: as Lumi the player jumps at any wall, trunk or rock, catches whatever edge the claws reach, shimmies along it and pulls up, to reach places nobody can (the cottage roof, the top of the big pine, the sea stack). Fun because the island becomes a climbing route you read with your own eyes, and a missed grab is a real fall.
Next: the beach hut still (posted s134 04:36, redone 04:41 and 04:44, media/s134-climbedges-4.png; the shelf at ~1.2 m was NOT found 'Where my claws could hold', site/img/climb-edges.png) found only the floor lip at 0.28 m: the wall top was out of the 1.8 m reach from the bbox (the platform sticks out), and a gabled roof has no flat top: let lips also be ridges/eaves (a top up to 50 degrees with an overhang below) and aim from the wall itself, not the bbox. Then the hang: Lumi as a PrintSim affine body, two claw contacts with IPC, holding only inside the Coulomb cone (todo #649).

## Passed the critic (s134, round 3)
surprise 7, fun 8, real 7. The critic's warning: IPC contact of an affine body on a thin lip is where jitter and
creep start; a film where Lumi trembles on the ledge or teleports over the lip is one more glitch reel. No scripted
breaks (the snapping twig was dropped for that reason).

## Step 1, s134: the edge finder (physics/climb.jl `climb_edges`)
- A KA kernel, one thread per probe column across Lumi's facing; horizontal rays climb up a steep face (|n_z| < 0.342)
  until it ends (no wall within reach, or a step back > 0.25 m); a ray down just behind the face finds a flat top
  (n_z > 0.866). Raycore TLAS from physics/echo.jl `echo_tlas(solid_triangles(scene), backend)`: 4.3 M triangles,
  1.6 s to build on the CPU (build it once per prop change, not per frame).
- Measured in the sandbox at the camera obscura hut (bbox x -16.32..-13.25, y -12.58..-9.43): east and north walls
  12 lips each at 1.91 m above the ground, top n_z 1.0; west and south walls none (to find out). 0.4-0.7 ms per
  call for 25 columns x 58 heights on the CPU backend (1 s the first call: compile).
- Film/still script: movies/climbedges.jl `climbedges_still` (lips as :glowdot points, Lumi at the east wall).

- s134 traced stills (movies/climbedges.jl, in my session, 64 spp, 80 s each once compiled): the obscura hut is NOT in
  scratch games (plugins/obscura.jl:96, films build their own), so the first two tries found nothing. Beach hut
  (bbox x -11.14..-8.88, y -13.22..-11.16): 8 lips, all on the floor lip at 0.28 m. media/s134-climbedges-2.png.
