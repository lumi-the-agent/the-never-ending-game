# Fields that push anything (Sparks from stones)
Goal: the player carries a magnet stone, makes wire, cells and coils from what the island has, and whatever they put together pulls, spins, buzzes or melts by the real fields and currents it makes; fun because every build is the player's own and nothing is scripted.
Next: (s151) retake the scrap crane (todo #717): movies/crane.jl now keeps pegs outside the winding and lets them fall by their weight; still needed: a camera that keeps Lumi's head and the coil (>= 1/5 of the frame) in view, replayed in the sandbox with game frames between shots, then a switch Lumi's beak closes so the pegs drop on a friend.

## Where things are (s147)
- physics/em.jl: `EM.magnet(verts, faces, M)` any closed mesh -> charges (sigma = M.n), `EM.H/B`, `EM.force(src, dst)`,
  `EM.force(Bf, path, I)`, `EM.MATERIALS`. Self test `EM.selftest()`: disc axis field within 0.5% of the closed form
  6 mm off the face; far force = two dipoles up to the 32-gon's area.
- plugins/magnetstone.jl: ferrite block (Br 0.38) at (-3.8, 18.9) on the north beach, 14 iron spikes 12 cm x 6 mm.
  Spike = soft iron rod, M along it = H/N (N of a long rod) up to saturation 1.7e6 A/m; F = (m.grad)B, T = m x B;
  static/kinetic friction 0.5 on sand, yaw against friction torque, sticks on touching the stone, drops when the
  pull at contact is under its weight. 0.05 ms/frame (spikes at rest past 45 cm are skipped: pull <0.2% of friction).
  Pull/friction measured: 8.7x at 15 cm, 0.1x at 25 cm.
- Film movies/magnetstone.jl (camera from the SEA side: inland the hill rises above a low eye).
- tests/magnetstone.jl: a spike 22 cm ahead comes to the carried stone, one 1.2 m aside stays put.
- The stone is magnetised along its LONG axis (x, Lumi's forward): magnetised up, its field level with it was vertical
  and could not turn a floating needle (s147).
- plugins/compassbowl.jl (s147): stone basin at (-4.9, 17.8), a magnetised spike (1 T remanence) on a lily pad, torque
  m x B from the island's 25 uT (+y = north) plus the stone's field from Main.MAGSTONE's charges; water damping from the
  Stokes layer c = pi mu r^4 / delta. Stone 0.6 m away turns it from north to the stone's near end. Film movies/compass.jl.

## Iron magnetises iron (s148, physics/softiron.jl)
- `SoftIron.Rods(centres, axes; L, a, K)`: each rod K segments with their own axial M; face charges A*(M_b - M_b+1);
  ALL segments solved together (I/chi - Infl) M = H_ext.axial, saturated ones held at Ms. `force_torque(S, i, Hext)`.
- Self test: one 12 cm x 6 mm rod in a uniform field = 0.74 of the ellipsoid formula M = H/N (a cylinder's N is larger),
  converged in K from 16 on; two rods end to end magnetise each other more and pull together.
- Pass Hext as a NAMED function (an anonymous global closure made the solve 23x slower: 6.8 -> 0.29 ms for 14 rods, K 8).
- Faces of OTHER rods within 4a are discs (7-point rule): a softened point gives no field just in front of a face, so
  finer segments at a joint pulled less and less. Graded segments (cos spacing) help a little: K = 24 graded ~ K = 32 even.
- The ferrite stone (Br 0.38, 14x11x9 cm), vertical chain under its north end, 1 mm gaps (hold = pull/weight below,
  per joint): 64 even segments 4.98/10.6/1.03/0.16, still drifting down slowly with K. So 2 spikes surely, the 3rd
  right at the edge, the 4th never (K = 8 even said 4: too coarse at the joints). Plugin: K 24 graded for the few
  rods near the stone; a 3rd spike that sometimes hangs and sometimes drops is the honest answer.
