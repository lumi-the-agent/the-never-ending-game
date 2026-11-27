# A snowball that grows as it rolls
Goal: after a night of snow the player, as Lumi, pushes a snowball across the meadow; it packs on the snow it rolls over, gets heavier and harder to push uphill, and they lift one onto another to build a snow friend that stands or topples by how well they centred it. Fun: a toy you get better at (deep snow packs faster, slopes run away with it, a lopsided ball rolls crooked), and the bare grass trail shows where you went.
Next: take 2 of the film with a clear camera (take 1 hid half the view behind a prop: list props near the eye and on the sight line first, camera 3 m from the run), then the plugin: a snow field over the meadow, a push key in Jump in, the pick-up as a Mantle kernel.

## Where it stands (s140)
- physics/snow.jl (free time s140): snow falls onto the topmost voxel of each column and slides at 55 deg (sandpile);
  the lantern gets a cap, the roof shelters the steps (media/s140-snowlantern.png).
- physics/snowball.jl: the ball on a snow depth field. Pick-up = all snow in its footprint (spherical cap of the
  layer), mass conserved, radius from packed density 450 kg/m3 (fresh snow 150). Rolling: 7/5 m effective mass,
  picked-up snow at rest shares momentum, Bekker sinkage (Wong's US snow: n 1.6, kc 4.37e3, kphi 196.72e3) sets the
  compaction resistance. Test on a 0.25 slope, 12 cm snow, push 15 N for 2 s: 0.13 m / 4 kg -> 0.41 m / 131 kg in
  14.5 m, sinking 7-12 cm, speed held at 1.6-2.4 m/s by the snow, speeding up on bare grass after.
- movies/snowball.jl: the roll on the island's real ground above the beach (start (-4,12.5), downhill +y).

## Still missing (the critic's warning: it must not become a radius counter)
- Shape: real rolled snowballs grow into barrels (snow sticks in a band across the spin axis); turning spreads it.
  Track the shape (two semi-axes or a voxel ball), so a straight roll gives a wheel that rolls crooked.
- Off-centre mass -> wobble; the ball as a PrintSim affine body with IPC contact for stacking.
- Lumi pushing for real (a force from Lumi's body, slower uphill), lifting a ball only when light enough.
- Sheltered snow (under trees and the cottage roof) from physics/snow.jl over the island, not a uniform layer.
- Take 1 (s140, site/films/snowball-grows.mp4, sheet media/s140-snowball-sheet.png): a MISS. The camera at
  (17.5,-1.2) stood behind a brown prop slab filling the bottom 40 %; the ball is a white dot far off. Take 2: list
  w.props within 2 m of the eye AND along the eye-target line first, and put the camera 3 m from the run, low.
