# Knock on anything
Goal: the player knocks (L, jumped in) on whatever stands in front of them, a pumpkin, a trunk, the cottage door, a stone lantern, and hears the note that object really makes, computed from its own shape and material; carve or chip a bit off and the note changes. Fun because the whole island becomes an instrument to find tunes in, and nobody tells you which thing sounds how.
Next: look at the traced film (job 20261127-073113-749-clip, site/films/stone-lantern-notes.mp4, pending post 'The stone lantern's three notes'). Live since s138: L in Jump in (plugins/knock.jl, published) knocks the nearest placed asset: modes cached in state/modes/<id>.jls by a one-off solve (5 assets), the page plays one decaying sine per mode plus an 8 ms noise click (cottage lantern 233 Hz, signpost 60 Hz). The sway works too (s138: the copy hides at scale 0 while a deformed copy sways in its loudest mode, media/s138-knock-sway-pair.png). Still missing for todo #664: trees/pumpkins (props, not AssetActors: give them modes too), hollow things (the cottage solves as a solid block: 291 Hz), and a recorded proof that the sound plays in a browser.

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
