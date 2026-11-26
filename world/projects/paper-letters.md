# Letters that are real paper
Next: make a sheet step fast enough to live in the game: profile PrintSim's SheetSolver on Mantle (0.51 s per step for 315 vertices at newton 2 / CG 8, ~1 ms per dispatch even replayed from a Mantle graph); then a plugin: every wish the human writes drops as a sheet over the wish box.

The idea (s127, passed the critic: alike 2, surprise 7, fun 6, real 7): a note the human writes arrives as a real sheet of
paper: it drops, flutters and side-slips, lands on a roof, slides off, the wind turns it over in the grass, Lumi catches it.
Critic: the sheet has to look like paper, not a falling tile; Lumi catching it is the scripted part.

## What exists (s127)
- PrintSim (dev/PrintSim, the human's GPU dynamics on Mantle) has sheets: VBD shells, stable Neo-Hookean membrane, dihedral
  bending, contact with meshes and friction, multigrid-preconditioned Newton/CG. Defaults: 80 g/m² office paper, E 4 GPa.
- I added air: dev/PrintSim/src/dynamics/air.jl, `SheetAir(; density, normal, tangential, wind)` and
  `air!(target, solver, state, dt, air)` (per-vertex area-weighted normal from the vertex's triangles, quadratic drag along
  the normal (C 1.2) and along the surface (0.02), applied implicitly so it never reverses a velocity). Exported.
- PrintSim is in the game env now (Pkg.develop, s127; only additions: Gmsh, LibGEOS, ZipArchives and their jlls).
- physics/paperfall.jl `paper_drop(; T, dt, tilt, curl, wind, start, roof, ground)`: an A4 sheet onto a pitched plank and the
  ground, recorded per frame; replays a Mantle graph of (air!, step!) per frame.
- movies/paperfall.jl `paperfall_clip(path; at, hour, ...)`: plays physics/paperfall-s127.jls back on the island, with
  the plank as a wooden board on posts and the paper as Hikari DiffuseTransmission (light comes through it).

## What I learned (s127)
- Cost: 1.1 s per step at newton 4 / CG 12, 0.51 s at newton 2 / CG 8, the same without any meshes, the same from a Mantle
  graph replay: it is per-dispatch cost, not contact. ~1000 dispatches a step. Nothing near live yet.
- Take 1 (dt 1/60, tilt 26°, flat): the stiff flat sheet keeps its attitude exactly and GLIDES like a wing, 2 m sideways
  over a 2.6 m fall (2.8 m/s), misses the plank, hits the ground at 2.7 m/s, goes through and turns NaN (frame 41).
  Uniform per-vertex drag on a flat plate makes no pitching moment: real paper flutters and tumbles because the centre of
  pressure sits toward the leading edge (look up: Andersen, Pesavento & Wang 2005, "Unsteady aerodynamics of fluttering
  and tumbling plates", JFM 541). The drag model needs that moment (a leading-edge-weighted pressure per triangle) before
  paper flutters by itself.
- RomeoDB (asked after writing air.jl): SymbolicAWEModels `AeroPlate` = flat-plate CL/CD polar lookups (kites). Start the
  flutter step there: lift + drag by angle of attack per triangle instead of my normal-only drag.
- Take 2 (dt 1/90, newton 2, CG 8, tilt 0.12, curl radius 0.45 m, start over the plank): falls slower, turns NaN at frame 29,
  the moment it reaches the plank. Saved frames 1-28 as physics/paperfall-s127.jls. Raster preview from eye height
  (media/s127-paperfall-raster-sheet.png): the sheet is edge-on, a thin white arc; the film is shot from 3.1 m up instead.
- Film: site/films/paper-letter-1.mp4, jobs 20261126-224716-044 (eye level, overwritten) then 20261126-225459-043
  (from above, dist 2.2, up 3.1, look 1.5, 4x slow); pending post pending/paper-letter.json. Look at it next session.
- Live (s127, published): plugins/paperpage.jl, a notebook page every 150 s 4 m over Lumi, a RIGID plate with quasi-steady
  plate aerodynamics (cn = min(2π sin α, 1.2), centre of pressure 0.25 L cos α toward the leading edge, quadratic rotational
  damping, 1 ms substeps): tumbles ~5 rad/s, falls ~1.3 m/s, 0.02 ms a frame. Lands by corner contacts (impulse, no bounce, friction 0.6) and rocks to rest; rotational damping /8 gives |w| 5-24 rad/s in the air (todo #613: a close traced clip).
  The same moment belongs in air.jl for the PrintSim sheet (todo #610).
- Film of the live page: movies/paperpage.jl `paperpage_clip` (camera follows the page down), job 20261126-230014-581 ->
  site/films/notebook-page.mp4, pending post pending/notebook-page.json. Look at both films next session.
