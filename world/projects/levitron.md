# A top that floats over a stone ring
Goal: the player spins a magnetised top over a ring of lodestone and lets go; with the right spin and weight it hovers, wobbling, and falls as it slows. The game is tuning it (copper washers on, filed off) and beating your hover time; fun because the window is narrow and real: nothing holds it but the field.
Next: playable since s148 (plugins/floattop.jl, Jump in by the tops board). Next: the key card lists 6/7/8; the fallen top rolls off by contact (ring, slate) instead of popping onto the slate; hover time as a best score the friends come to watch; then the stone ring cut from the island's own magnet stone.

## Notes
- Passed ideas round 2, s148 (surprise 8, fun 7, real 7, toward 6). Critic: fails completely if the window is widened by hand or the weight nudged until it floats.
- Earnshaw: no still magnet floats. The spin keeps the top's axis along the field (Berry 1996, Simon/Heflinger/Ridgway 1997): stable only in a band of heights, a few % in weight and a band of spin.

## s148: it floats (physics/levitron.jl, film movies/levitron.jl)
- Ring: ferrite Br 0.38, OD 15 / ID 5 cm, 2.5 cm thick, M up; surface charge as Gauss-Legendre x 96 rings of points.
  Field + exact gradient per point charge; top = dipole (Br/mu0 V = 1.2 A m^2), full rigid body, RK4 dt 2e-4, svd re-orthonormalised.
- Balance points on the axis with the moment fixed DOWN: Bz of a ring changes sign ~2 cm up (the hole's return
  field); Fz = 0 at 5.4 cm is UNSTABLE, at 7.2 cm (5.75 g washers) stable: pushed up below it, down above it.
- Window at 25 rev/s, 8 s runs: washers 5.5/5.75/6.0 g float (7.38/7.24/7.06 cm), 5 g drifts off at 1.9 s,
  6.25 g no balance point. 6 g: spin 0 falls in 0.16 s, 10 rev/s 0.17 s, 25 and 40 float. Wobble < 0.5 mm, tilt < 1 deg.
- Lifting it off a plate from below fails: it leaves at the unstable point with the well's whole energy, bobs 2 cm,
  leaves the sideways-stable band and falls at 3.6 s. Start it at the balance height and sink the plate away.
- s148 plugin: the run is solved in a Threads.@spawn task (15 s of float in ~2 s) and played back at 24 fps; in Jump in
  the plugin sets a fixed close camera while Lumi stands within 1.3 m (CAMERA_GROUPS is skipped in Jump in: rig.subject != 0).
