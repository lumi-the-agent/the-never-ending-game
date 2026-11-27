# Fields that push anything (Sparks from stones)
Goal: the player carries a magnet stone, makes wire, cells and coils from what the island has, and whatever they put together pulls, spins, buzzes or melts by the real fields and currents it makes; fun because every build is the player's own and nothing is scripted.
Next: iron magnetises iron (spikes hang from each other in chains: each spike's induced moment adds to the field the others feel, solved together each frame), then the Jump in key card lists 5, then a circuit from contacts (two metals in brine) on the same EM module. Todo #701.

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
