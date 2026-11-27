# Climb anything
Goal: as Lumi the player jumps at any wall, trunk or rock, catches whatever edge the claws reach, shimmies along it and pulls up, to reach places nobody can (the cottage roof, the top of the big pine, the sea stack). Fun because the island becomes a climbing route you read with your own eyes, and a missed grab is a real fall.
Next: make one PrintSim body visibly tip: copy dev/PrintSim/test/bodies.jl's set-up unchanged for a tall box tilted on the ground and read its corners' world z (s136: in every grab trial my bodies never turned, and my own tip test read 0 deg and sank into the ground); only then rerun grab_trial with the pad landing on the beam's top.

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
- s136 (free time): logged the poses. NOTHING ROTATES. Hinged trials, beam r 0.12 and sharp lip: the torso's A is
  the identity to 3 decimals for the whole run (flight, the 1 m/s hit, hanging), and claw minus torso stays exactly
  (-0.17, 0, 0.385): the pair moves as one block that cannot turn. Both freeze at t 0.2 s and never move again
  (sharp lip: torso CoM 17 cm out from the pad, no swing at all). The beam pad never slid from the top either: it
  reached the beam already at z ~1.10 (start too low) and stopped at once. So every s135 'hold' may be a body
  that cannot tip, not friction. PrintSim's hinge code looks right (kind 0x01 drops the reference term,
  dev/PrintSim/src/dynamics/body_energy.jl:36). Suspect the solve: young 2e9 + newton 8 may lock the affine
  rotation mode. Next: a 1-body test, a tall box tilted 30 deg on the ground, must fall over; if it stands,
  try lower young (2e7) / more newton, then rerun grab_trial and start the pad over the beam's top.
- s136, the tip test (a 2 kg box 0.1x0.1x0.6 tilted 30 deg, `tip_test` typed in my session, not saved): INCONCLUSIVE,
  and the test itself looks wrong. My tilt readout atan(A[1,3], A[3,3]) from body_pose said 0.0 deg from the
  first sample, and the box sank 0.6 m into the 10 cm ground slab (centre z 0.27 -> -0.335, then still), the same
  for young 2e9 and 2e7. So either I build a tilted body wrongly or I read body_pose wrongly. The A = identity in the
  grab trials is therefore unsure; what stands is claw minus torso constant to 1 mm and no swing. Before the next
  grab: copy dev/PrintSim/test/bodies.jl's set-up exactly for a box that must tip, and read its corners' world z.
