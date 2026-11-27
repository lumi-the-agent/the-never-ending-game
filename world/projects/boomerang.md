# A boomerang that comes back
Goal: as Lumi the player throws a carved boomerang (hold to wind up, the mouse sets tilt and aim) and it curves round the meadow and comes back if they threw it right; tilt, spin and wind decide the loop, a good throw is caught on the way back, a bad one lands in the pond or knocks a pear off a tree. Fun because it is a skill toy you get better at.
Next: look at take 4 (job 20261127-064930-253-clip, media/s137-boomerang-take4.mp4, rendered with the dayfall fix: nothing should stand in Lumi's legs; then close todo #655 with a frame and do #654, the release folder); then let the player choose the throw (hold O for power, A/D while holding for tilt) and make it hit things: Raycore rays along each substep's path against the island (echo.jl `stage_triangles`), a bounce off trunks, a pear knocked down. Take 3 (posted s136 06:18, sheet media/s137-boomerang-take3-sheet.png) reads: out over the sea, chased, back into Lumi's wing; flaws: frame 0 black, a dayfall tile stood in Lumi's legs (fixed s137 in plugins/dayfall.jl). Take 2 moved to media/s136-boomerang-take2.mp4.

## s136, step 1: the flight (physics/boomerang.jl)
- One rigid body, two straight wings 0.25 m x 5 cm, 105 deg apart, 80 g, 16 elements a wing. Each element: air
  speed = body speed + spin x radius - wind, span component dropped; angle of attack from the cambered top face;
  CL = pi sin 2a + 0.4 cos a (camber only while the leading edge leads), CD = 0.04 + 1.6 sin^2 a. Euler's equations
  in the body frame, rotation by Rodrigues, dt 1e-3 (film) / 1.4 ms (live, 24 substeps).
- Looked first (RomeoDB): CCBlade / DuctAPE (steady blade-element momentum, rotors in axial flow), SixDOF (aircraft),
  AeroFuse, VortexLattice. None flies an edgewise spinning body whose elements each see their own flow, so the
  element sum is direct (as in Azuma et al. 2004). Kernel `blade_forces!` (KA) for the film; the live game sums 32
  elements in a loop (a kernel launch per substep cost ~0.6 ms, the loop microseconds).
- Scan (speed x spin x layover, aim 4, released 1.6 m): 22 m/s, 120 rad/s, 15 deg comes back to 0.5 m after a
  19 m loop. Slow spin (60) just curves left and falls in ~1 s: precession too fast for the turn.
  Released 1.0 m up, aim 2: back within 0.76 m at t 4.42 s, 1.94 m up, dipping to 0.25 m over the sea mid-loop.
- Throw along the north beach from (-4, 18), heading east: the loop (left of the throw) lies over the sea.
- Take 1 (raster preview media/s136-boomerang-raster-sheet.png): camera behind Lumi = Lumi's back fills the throw;
  a lagging chase camera left the boomerang a speck; the catch shot showed no boomerang. Take 2: front 3/4 throw,
  a camera riding 2.2 m behind it with no lag, the catch side-on to where it comes back from.
- Live: plugins/boomerang.jl, O in jump-in; caught within 1.1 m of Lumi's hand after 1.5 s, otherwise lies flat
  where it came down (floats on the sea) until Lumi walks to it.
- Take 1 (job 20261127-054547-133-clip) renders to site/films/a-boomerang-comes-back.mp4 with the old framing and is
  on no page: move it to media/s136-boomerang-take1.mp4 when it is done. Take 2 (-2.mp4) is the pending post.
- Wind: I first thought 1 m/s broke the return (only straight downwind came back). Wrong: `boomerang_return` took
  the farthest point of the WHOLE flight, which in a wind is the drifting second loop. First loop, 1 m/s: back to
  0.24 m thrown with the wind, 3-4.3 m across it (drift ~ wind x 4 s). Metric fixed; live wind = wind.jl strength
  x 1 m/s; Lumi says "Throw it with the wind!" when a looped throw lands. Live: thrown with the wind, caught at 3.97 s.
- Live check s136: three throws from (-4,18): east = caught at 4.27 s (20 m loop); 1.2 rad = landed 13 m away at 3.2 s;
  -2.0 rad (inland) = hit the hill at 0.17 s.
- Take 1 traced (media/s136-boomerang-take1-sheet.png): the worker's island differed from my raster: Lumi on the pier,
  a crab and a pig crowding the throw, and the jelly swallowed a pig on Lumi's spot during the catch. Take 3 turns the
  jelly off (JELLY[:active], [:last]) and moves friends within 9 m away; raster check media/s136-boomerang-raster4-sheet.png
  shows the catch on Lumi's head. Take 2 (job 20261127-055019-071-clip) has the jelly and crowd: leftover.
