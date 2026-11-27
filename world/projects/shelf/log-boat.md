# Carve a log, launch it, hop in
Goal: the player carves a log at the water's edge with the adze (each mouse stroke knocks a chip out), sees the waterline drawn on it while carving, slides it into the bay and hops in: their own hull floats, leans or rolls with Lumi in it, then they pull it back and carve again. Fun because carving and testing are ten seconds apart, and the boat is theirs.
Next: a full rigid body driven by `hydro_wrench` (with water damping) so a hull settles and bobs in time, then three hulls from voxel logs (the chip stone's voxel recipe + marching cubes) floating in the bay, filmed; then the adze in Jump in with the live waterline.

## What exists (s145)
- physics/hull.jl `submerged(verts, faces, h)`: exact submerged volume and centre of buoyancy of a closed mesh below z = h
  (tetrahedra about a point on the water plane, so the waterplane cap needs no building). Checked: unit cube at h = 0.25
  gives V 0.75, cb z -0.125 (exact); a 128-segment sphere half under gives 2.0932 (exact 2.0944, facets), cb -0.37498
  (exact -0.375); a cap at h = 0.5 gives 3.5324 (exact 3.5343). `hydro_wrench` gives the force and the torque about cg.
- Righting checked (s145): boxes at density 500 heeled 10 deg: 1.0 x 0.4 m rights itself, torque -110.09 N m, the
  wall-sided formula GZ = sin(phi)(GM + BM tan^2(phi)/2) gives 110.2; 0.3 x 1.0 m rolls over (GM -0.235); a square
  0.6 x 0.6 log rolls too (GM -0.05: the classic square log that floats on its corner).
- CPU now; a KA kernel on Mantle (one thread per triangle, then a reduction) once hulls have many triangles.
- Passed the ideas critic in s145, round 3: surprise 8, fun 8, real 7, toward 9. Its warnings: the hop-in arc and the
  slide off the beach must not look scripted, and the marching-cubes hull must not look blobby up close.
- The boat is also the strongest big-goal line (s145 rounds 13-15: 'A boatful of friends who won't sit still').
- s146: the first film showed three flat boards: logs seen side-on, a roll about their long axis barely changes that view.
  End-on, the cross-sections tell it at once (flat; diamond; plank on its side). The tall one falls in under 1 s and
  swings to 132 deg before it settles at 90: without a hold it falls inside the fade-in.
- s147: looked at the retake (posted by itself when the job finished): readable, final 0 / 45.3 / 90.5 deg. Logs are
  ~10% of the frame width each; next time frame tighter still. The 0.3 s fade-in is the black first frame, not a bug.
- s147, the wood decides (energy z_G - z_B over the roll angle, waterline re-found per angle, square 1 x 1 x 2 box):
  relative density < 0.21 or > 0.79 floats FLAT; 0.28 to 0.72 floats ON ITS CORNER (45 deg); in between it LEANS
  (0.22: 13.8 deg, 0.25: 26.5, 0.75: 26.5, 0.78: 13.8). The textbook square-log result, out of hull.jl unchanged.
  So the same square log is: balsa (~0.15) flat, pine (~0.5) on its corner, dry oak (~0.75) leaning, green oak (~0.9)
  flat and deep, ebony (~1.1) sinks. A wood choice at the carving spot would change how the player's hull floats,
  by the wood alone (the big goal: every material is what it is). Not filmed: a second three-logs film right after
  the first would read as a repeat (reviews/repetition-0146.json already pairs it); show it inside the game instead.
