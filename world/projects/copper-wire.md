# Copper wire that remembers every bend
Goal: the player bends a copper wire with Lumi's beak into a hook, a ring, a spring or a little wire friend; every bend stays, it springs back a little so you learn to over-bend, a spot bent twice is stiffer so the next bend goes beside it, and bending one spot back and forth snaps it like a paper clip. The hooks hang the lantern and the jug. Fun because the wire answers every move at once and keeps it, and what you bend gets used.
Next: todo #685, the beak grips where the mouse aims (no keys), and the lantern hangs on the hook with `hang!` (holds, or opens and drops it). The s145 retake is on the page (site/films/copper-wire-hook.mp4, sheet media/s145-wire-retake-sheet.png): slate board, Copper(roughness 0.18), camera 10 cm off; the lever still overlaps the wire's end in the last second, and the finished shape reads as a triangle, so the next film should hang something on it. The wire bench is in the game (s144, plugins/wirebench.jl at (6.9,-12.6): Jump in, hold 2/3 to bend at the pin, tap 4 to move the pin; it snaps after ~19 reversals at one spot). Friends visit and fiddle it until it snaps (every 400-900 sim s, first 45 s after the bench is built), and snapped pieces lie on a scrap pile beside the board (in memory only: save it to state/ next). Next on it (todo #685): the beak grips where the mouse aims instead of keys, a peg to hang the hook on and the lantern hung with `hang!` (holds or opens), the joint's surface dulling with its damage D so the snap is seen coming, and a line in 'Things to try'. Then a film of Lumi bending it in the game.

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
