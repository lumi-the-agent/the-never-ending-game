# Copper wire that remembers every bend
Goal: the player bends a copper wire with Lumi's beak into a hook, a ring, a spring or a little wire friend; every bend stays, it springs back a little so you learn to over-bend, a spot bent twice is stiffer so the next bend goes beside it, and bending one spot back and forth snaps it like a paper clip. The hooks hang the lantern and the jug. Fun because the wire answers every move at once and keeps it, and what you bend gets used.
Next: (s147, the human: the motor is one rig; make electromagnetism general) physics/em.jl is the start: any closed mesh + magnetisation -> field anywhere, force/torque on other magnets and on any current path (checked: disc axis field within 0.5% of the closed form, far force = two dipoles up to the polygon's area). Next: the motor's wire as a free 6-DOF body pushed by EM.force (not one axis), the circuit from what touches what, then soft iron (induced M, a volume solve) and the GPU kernel. Todo #701. Older: #691 (wire bench motor), #692 (bench crashed), #685 beak grips.

## What exists (s144)
- physics/wire.jl: planar quasi-static wire, joints with elastic-plastic bending (yield moment sigma*Z, Hollomon hardening),
  springback on release, Coffin-Manson fatigue with Miner's rule per plastic reversal, `hang!` for a weight at a node.
  Numbers (1.5 mm annealed Cu, 1 mm segments): 95 deg over 7 mm needs 0.068 N m and springs back ~1 deg (tight bends
  spring back little; a wide bend springs back more); a reverse bend at a hardened spot goes into the soft wire beside
  it (6.2 deg vs -10.7 deg per joint); +-90 deg back and forth snaps after 7 half cycles.
- movies/wire.jl: a lever turning round a pin bends the wire twice into a hook (99 and 149 deg kept), on the tops board
  (5.6, -13), copper = Hikari.Copper().
- Looked for an existing elastoplastic rod in RomeoDB: PtFEM, Amaru (axial plastic rod only), PeriLab (peridynamics);
  nothing with bending plasticity, springback and fatigue, so the joint model is my own (it is ~40 lines).

## Later
- 3D wire (twist and out-of-plane bends) as a discrete elastic rod on the GPU (Mantle) once the beak grips it live.
- Show the tiredness: the surface at a joint dulls and roughens with its damage D (roughness from D), so the snap is
  seen coming, not a hidden timer (the critic's worry).
- Over-bending as a skill: wide bends (a ring, a spring) spring back visibly.


## s146: the bent wire that spins by itself (the human asked for a real electric motor)
- physics/homopolar.jl: AA cell (1.5 V, 0.12 ohm) on a NdFeB disc (Br 1.2 T, 25 x 6 mm) as 10 loops x 64 exact
  Biot-Savart segments; dF = I dl x B summed along the wire's real polyline (0.7 mm pieces); torque about the axis.
  Rim pressure from the bend: an arm bent `squeeze` tighter than the magnet presses 3EI/L^3 * squeeze (copper E 117 GPa).
  Coulomb friction static/kinetic at the rim and the dimple, air drag, and a fitted contact-chatter loss 1e-6 N m s
  per contact (the only fitted number: it brings the heart to ~25 rev/s). Fly-off when m w^2 e > dimple grip.
- Results: ~11 A; heart torque 3.9e-4 N m -> 24.7 rev/s; one-arm flies off after 5.8 ms; a heart squeezed 0.6 mm
  (N 0.068 N) has static friction 5.9e-4 > 3.9e-4 and never starts. Without the chatter loss the heart ran 163 rev/s.
- Not yet: Magnetostatics.jl (CurrentLoopAnalytic) for the magnet; back-EMF (0.03 V at 1000 rad/s, small); the wire
  after fly-off is a simple ballistic hop in the film, not a rigid body.