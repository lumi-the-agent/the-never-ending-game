# Lay the plank road yourself
Goal: (passed s181, round 2: surprise 7 fun 7 real 7 toward 8) The player carries oak planks from a stack and drops them where they want the road; each lands on the island's sand by contact and rests where it settles (rocking on a hump, bridging a hollow, one end up on another plank). Then the cart drives over THEIR road: smooth where it is laid well, a thump at a gap, a see-saw where a plank rests on another, a stall at a step. Laying a good road is the skill; the cart (and later the dune crest) is the judge.
Next: per-body (per-island) step bounds in PrintSim's BodySolver, so a plank resting on the sand no longer freezes the ones still falling (dev/PrintSim/src/dynamics/affine.jl step!: s.step_bound is ONE scalar for all bodies, and body_line_search! is global). Then plank C dropped across plank B's end (body-body contact), then the planks as bodies in the game replacing the berm road (cartcord.jl), then the cart's wheels as bodies on joints (NOT kinematic: the critic's warning).

## s181: the first drop (physics/plankdrop.jl, physics/data/plank-ground.csv, plankdrop-s181.jls)
- The ground: NG.ground sampled under the road (x 2.3-4.3, y -15.0 to -14.44, 4 cm), meshed as triangles (1400), an
  add_mesh! static collider mu 0.6. Planks: box_mesh 0.6 x 0.12 x 0.02 m oak 700 kg/m3 (1.0 kg), add_body!.
- One plank from 3 cm: free fall exact, lands 0.08 s, at rest by 0.12 s, 0.75 deg along / 3.1 deg across (the sand's
  slope there), centre 2.4 mm above the mean surface (resting on the high points). ~90 ms a step at dt 1e-3.
- THREE planks (lifts 0.10, 0.15, 0.35 m): plank 1 lands at ~0.2 s and at that moment planks 2 and 3 STOP IN MID AIR
  (5 cm and 25 cm above the sand) for the rest of the run. Cause: the CCD step bound and the line search are global,
  one resting contact gives every body a ~0 step. That's the film of s181 (movies/plankdrop.jl plank_drop, replays the
  solved poses at half speed, hides the cartcord plots).
