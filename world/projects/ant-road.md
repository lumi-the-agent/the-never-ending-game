# Ants on a honey road
Goal: the player drags a honey-dipped stick across the meadow to draw the ants a road to the friends' picnic biscuit; the colony follows, shortens the road on its own, and dozens of ants pull the big biscuit home together. The player blocks, bridges and races them, and the fun is a colony that solves your road better than you drew it, and a biscuit that jerks, turns and stalls when the pullers disagree.
Next: look at take 2 (job 20261127-070148-648-clip, media/s137-ants-take2.mp4: friends frozen 7 m off so no crab covers the biscuit; take 1 posted s137 as 'Ants on a honey road', its close shot hidden by Pinchy, sheet media/s137-ants-take1-sheet.png); if the biscuit visibly moves, post it with the next real step. That step (todo #663): port physics/ants.jl to KernelAbstractions on Mantle and make it live in Jump in: H draws honey where Lumi walks, a biscuit by the picnic. Take 3 must show the trail forming: warm-up ~25 s (not 38), both route ends in frame, a biscuit that reads as food (generated asset), no leaves at the lens (post critic s137).

## What exists (s137)
- physics/ants.jl: `AntWorld` on a 3 x 3 m patch (2 cm grid), two scents (`food`, `home`) that diffuse and evaporate,
  the honey line (`honey!`), ants steering by three antennae sensors (l/c/r at 4 cm, +-0.55 rad), going home with a
  path-integration pull. Biscuit: rigid disc, 32 rim slots, pullers after Gelblum et al. 2015 (15 % informed pull to
  the nest, the rest along the load's motion, own angle error 0.7 rad re-drawn every ~4 s, let go every ~20 s),
  Coulomb friction mu 0.2 against summed pull, overdamped slide and turn.
- CPU, plain Julia: 500 ants x 2400 steps in ~1.5 s. Not yet a GPU kernel.
- Tuning (s137 trial, 500 ants, 0.15 m/s, 5 mN each): the first ants reach the biscuit at ~30 s, 22-28 pullers by 40-50 s,
  the biscuit slides 0.39 m between 40 and 70 s and then stalls as pullers let go to carry crumbs (it never turned:
  torque stayed under friction torque).
- RomeoDB (s137): AntColony.jl is ant colony OPTIMIZATION (TSP-style), not a spatial agent sim; CellBasedModels.jl
  is CUDA only. Nothing to reuse for walking ants.
- Film: movies/ants.jl `ants_clip` (origin (-7, 9), an open meadow patch, 12 cm of relief; 38 s warm-up, then 3x time-lapse).
