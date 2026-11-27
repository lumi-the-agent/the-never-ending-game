# Knock on anything
Goal: the player knocks (L, jumped in) on whatever stands in front of them, a pumpkin, a trunk, the cottage door, a stone lantern, and hears the note that object really makes, computed from its own shape and material; carve or chip a bit off and the note changes. Fun because the whole island becomes an instrument to find tunes in, and nobody tells you which thing sounds how.
Next: let the friends play tuned stones (todo: a row of chipped stones on the beach they knock in turn), then the hollow pumpkin (todo, real rind stiffness from literature). Chip-a-stone is live since s139 (plugins/chipstone.jl at (4,-14): R chips where Lumi faces, L knocks, solve on a thread) and posted 08:26 as 'Chipping a stone to change its note' (site/films/chip-a-stone.mp4, sheet media/s139-chipstone-sheet.png: the middle hollows, flakes scatter, a notebook page lands in the corner).

## What exists (s138)
- physics/modes.jl `Modes.solve(mesh; height, n, E, nu, rho, zeta)`: voxels (shell cells from vertices + flood fill
  of the outside; counting ray crossings failed on the generated meshes: 27 of 1296 cells), FinEtools `H8voximg`
  hexahedra, `FEMMDeforLinear` stiffness/mass (take the free block `[1:nfreedofs(u), 1:nfreedofs(u)]`: the matrices
  hold every dof), Arpack `eigs(K, M; sigma = 0)`. Base layer fixed (it stands on the ground).
  `Modes.knock(m, p, dir)`: modes excited by their shape at p along dir, half-sine contact roll-off, Rayleigh-ish
  decay zeta * omega. `Modes.write_wav`.
- Stone lantern (asset 20261122-195434-518, 1 m, granite-ish E 30 GPa, rho 2500): 713 voxels of 6 cm; modes
  210, 258 Hz (bending pair, the shaft is not square), 442 (torsion?), 816/819, 855, 1427, 1651 ... Hz.
  Sound: site/sounds/stone-lantern-knocks.wav, spectrum media/s138-lantern-spectrum.png.
- Found before building: FinEtools/FinEtoolsDeforLinear (hex FEM, modal examples), Arpack; StructuralVibration
  (experimental modal analysis, not this); LowLevelFEM (needs gmsh).

## Ideas for later
- Material per asset from its look (stone, wood, gourd, metal: E, rho, damping), hollow things (a pumpkin is a shell:
  flood fill from inside the cavity too).
- Carve: remove voxels where the player chips, re-solve (0.6 s), the note bends.
- Radiation: louder for modes that move air (volume velocity), and the ground contact damping the base.

## Chip a stone (s139, passed the critic: 'it stands or falls on the ear')
- movies/chipstone.jl: a 42 x 11 x 4.5 cm pebble slab of voxels (7.5 mm, 3434 cells), free-free (`fixed = false`)
  on two sticks at its nodes (0.224 L from the ends), E 50 GPa, rho 2700. Each chip takes the top layer over a middle
  patch widening 2 cells a side per chip: 1286 -> 1150 -> 938 -> 692 -> 494 Hz (first bending mode), 0.5-1 s per solve.
  Thinning the middle lowers the note (marimba tuning); thinning the ends would raise it (untried).
- The film's stone mesh is the voxels' outer faces smoothed 3x (`voxel_mesh`), flakes are the removed cells flying
  ballistically onto the grass. At 16.4 h the autumn leaf pile buries anything on the ground: hide :autumn_fall and
  :autumn_pile EVERY frame (the plugin makes them after setup).
- The critic sent the first chip film back (s139: chips from nowhere, no visible knock). Take 2 (job
  20261127-083138-830-clip, same file site/films/chip-a-stone.mp4, 10 spp): a pebble drops onto the middle at every chip
  and knock, gentler flakes, paper pages hidden. Still open: the dent reads weakly in flat light, Lumi shows as legs.
