# Climb anything
Goal: as Lumi the player jumps at any wall, trunk or rock, catches whatever edge the claws reach, shimmies along it and pulls up, to reach places nobody can (the cottage roof, the top of the big pine, the sea stack). Fun because the island becomes a climbing route you read with your own eyes, and a missed grab is a real fall.
Next: find why the pad stops at a round beam's equator whatever the wall does: s135's last check found the GeometryBasics Cylinder (Tesselation 48) is a 24-sided prism (48 side triangles, normals out, caps closed), 15 deg facets with a flat vertical one at the equator; tessellate it 192+ (or PrintSim torus_mesh) and see if the stop moves, then film one grab that holds and one that slips (same jump, sharp lip vs round beam r 0.12 m, physics/climbgrab.jl `grab_trial` tracks) with Lumi's real model following the PrintSim pose, side-on and close; then put the round lip's radius from climb.jl's probe profile into the trial instead of a hand-set beam. Speed: 36 ms per step at dt 1e-3 is far from live.

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

- s135 (free time): `climb_edges` returned one lip per column (`break` after the first), so the floor lip at 0.28 m hid
  everything above. Now up to `maxlips = 4` per column (out is 8 x maxlips x columns). Beach hut, width 2.4, 61 columns,
  reach 1.8, gap 0.7: from the east (facing -x) 38 lips at 0.16-1.46 m (was 8, all 0.28); facing -y 33 at 0.29-1.82
  (1.14-1.41 likely the shelf); +y 32 at 0.46-1.69; +x 37 at 0.41-2.19. Not yet sorted into real holds vs clutter.

## Step 2, s135: the grab in PrintSim (physics/climbgrab.jl `grab_trial`)
- Lumi = compound affine body (torso box 0.24x0.28x0.6 m, feathers mu 0.25; claw pad mu 0.6), 2 kg, thrown at a wall
  (speed toward it, 0.6 m/s down), claw pad 2 cm over the lip. 0.8 s at dt 1e-3 = 29 s (36 ms/step); dt 2e-3 tunnels.
- Sharp lip: held at 1 and 3 m/s and with the top tipped 0/20/35/50 deg: the pad hooks the CORNER (contact normal free).
- Round beam (axis over the face): r 0.05 and r 0.12 both SLIP, the claw ends under the beam (z 1.09 / 0.96 for a
  lip at 1.2), but the rigid torso then wedges between beam and wall instead of falling. Flush beam: see below.
- The `held` test (claw z > H - 0.15) was too loose (called r 0.05 a hold); now: pad above H - 0.02 and x < 0.1.
- Hinged at the shoulder (`hinge = true`, two bodies + PrintSim `add_joint!` :hinge): sharp lip holds (pad z 1.215).
  Round beam r 0.12: the pad slides from the top to the beam's equator (x 0.045, z 1.098) and STOPS there, with the
  body at z 0.71, to 3 decimals the same for torso depth 0.05/0.12, block corner tucked 0/5 mm/3 cm, and the wall
  recessed 20 cm (beam over open air). So neither the wall nor the corner holds it: suspect the GeometryBasics
  Cylinder mesh (winding, end caps, 48 facets) or the pad's box corner caught in a facet. Next: check the cylinder
  mesh's normals (they must point out), try a torus_mesh beam (PrintSim's own, major 20 m), and log contact forces.
- s135 last check: `Tesselation(Cylinder, 48)` = 96 faces: 48 side triangles (24 facets of 15 deg, all normals outward) + 48 cap faces.
