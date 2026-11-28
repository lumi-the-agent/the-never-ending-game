# The cart's motor on a rope: winch anything up the beach
Goal: The player stakes the new iron-stator motor in the sand, hooks its rope to anything (a log, a boulder, the empty cart, the cart with friends aboard) and the motor hauls it or stalls by its own solved torque; the player rebuilds it (turns on the iron, how many pots, drum diameter as the gear) until it drags the cart onto the plank track. The motor that wins goes onto the cart unchanged. Fun: a test bench for anything on the island, and the cart's drive designed by hauling real things.
Next: the winch IN THE GAME: the motor bench rebuilt as the iron drum motor (Motor.iron_drum_bench: real iron drum, two varnished copper coils, 4-segment commutator, oak frame), a pulley + hemp belt to an oak rope drum (ratio and grease as the player's choices), a rope (PrintSim rods) to the empty cart on the planks; it hauls at what physics/drummotor.jl says (dry 6:1 4.4 cm/s, greased 4:1 9.5 cm/s); a traced film following the rope.

Passed s172 (round 3 of 3, the critic's pick of a non-pass: surprise 6 fun 7 real 6 toward 8). The human s172: "back to
kindergarten times? ... nothing of the electric car itself moved since s159". This project IS the car's motor.
Critic's dangers: (1) softiron saturation and the rope tuned until the loaded cart only just makes the planks;
(2) the film as one more fixed shot of a turning drum. So: NOTHING is tuned to a load; the film follows the rope.

## The power budget, before building (s172, from NOTES 'Power budget')
- Six clay pots ~0.3 W each = ~1.8 W electric. At a generous 50% motor efficiency ~0.9 W at the rope.
- Empty cart 60 kg on planks (rolling 0.01-0.02): ~6-12 N -> ~8-15 cm/s. A real, watchable crawl.
- Empty cart in dry sand 60-92 N -> ~1-1.5 cm/s. Loaded cart (510 kg) in sand 1000-1540 N -> ~1 mm/s: it CAN'T, honestly.
  So the pots haul the EMPTY cart up the planks; the loaded cart needs the accumulator (next road step). That limit is the
  island's, and it is the reason the Plante jar comes next, not a wall to fake past.
- Torque: a 9 N pull on a 1 cm drum (the axle itself) = 0.09 N m; at 0.1 m/s that drum turns 1.6 rev/s. The stone motor
  gave mN m (lodestone 0.13 mN m): the iron stator must give ~100x more, or a reduction (a worm or a capstan) between.
- Materials: wrought iron horseshoe (bloomery iron, mu_r ~ 1000s, Ms ~ 1.7 T), varnished copper coil, oak drum, hemp rope.

## s172 MEASURED (physics/stator.jl, coilcrane.jl coils + softiron.jl iron; big-bench rotor 9 x 5.4 cm)
- Ferrite stones (smooth): 71 mT at the rotor's middle, 81 mT 2 mm off the face. (The ROUGH stone mesh read 25 mT 2 mm
  off its face: the 3x3 quadrature fails that close; use rough = false or a distance check for near-face probes.)
- Wound iron poles, air-core rotor, 160 A-turns a coil: 6 mT. The back yoke adds ~nothing: the 72 mm air gap (the
  whole rotor) is the reluctance. Iron through the rotor (4 mm gaps): 15 mT (rod-chain corners leak; ideal ~50).
- On SIX POTS (4.7 V, 3 Ohm walls) the field coils' NI vs turns: 25->38, 200->242, 800->578, 1600->752 A-turns =
  3.5 / 22 / 53 / 69 mT, and the coils alone eat the pots' whole matched power (~1.8 W). More turns help only until the
  coil's resistance matches the pots' walls; at a fixed supply NI tends to V x (wire section / turn length / rho).
  So: ON CLAY POTS A WOUND STATOR NEVER BEATS THE FERRITE STONES. It pays off on the lead accumulator (low resistance).
- Ferrite stones + an IRON CORE through the rotor: 81 -> 277 mT in the gap (iron at 29% of Ms), no power at all.
  The cheap 3.4x is iron in the ROTOR. That is the next part; the wound stator waits for the accumulator.
- (later s172) rotor_torque (physics/stator.jl): an iron BAR through the big-bench coil, N 80, stones smooth ferrite:
  drive torque (tau(+1A) - tau(-1A))/2 averaged over a half turn 18.1 mN m/A vs 10.8 air-core (1.7x, not 3.4x: the copper
  is not where the bar concentrates the field), BUT cogging (reluctance, the bar aligning with the stones) +-690 mN m at
  30/150 deg: 40x the drive. A bar rotor locks. Real motors went bar (Siemens H, 1856) -> ring (Pacinotti 1860, Gramme
  1871) -> drum: ROUND iron whose reluctance does not change with angle, copper on its rim in the gap. softiron.jl's
  axial rods cannot be round iron (magnetisation along each rod only): the round rotor needs 2D magnetostatics.
- (later s172) physics/motor2d.jl: the cross-section as 2D magnetostatics (A_x, Ferrite.jl, 1 mm quads, saturating iron
  by Picard on B = mu0 H + 1.7 tanh(...), torque by Arkkio's gap Maxwell stress). VALIDATED: air-core rotor at 90 deg,
  80 A-turns = 27.5 mN m (3D em.jl: 30.4). ROUND IRON DRUM (r 3.2 cm, 4 mm gap, copper in slots at 2.7 cm): 67.1 mN m
  = 2.4x the air core, converged by 16 passes; linear iron said 58.5 with 17 T spikes in the slot bridges (leakage that
  saturation stops). One solve ~0.2 s. Sweep over the half turn: see below.
- SWEEP (half turn, 80 A-turns, saturating iron): drum drive 0/-0.7/38.6/67.1/38.9/-0.4/0 mN m at 0..180 by 30,
  MEAN 20.8 vs air core 9.9 (2D; 3D air core 10.8: 2D within 8%). Drum COGGING <= 0.05 mN m: round iron does not lock.
  Iron peak 0.82 T. One coil drives only at 60-120 deg -> a second coil at 90 deg (Siemens' drum, 4 segments).
- On six pots: rotor N 80, 0.35 mm wire, 23 m = 1.0 Ohm; stall I = 4.7 / (3 + 1) = 1.17 A -> ~24 mN m mean. The empty
  cart on planks needs ~0.09 N m at a 1 cm drum: a 4:1 reduction (pulley + belt to a bigger drum). Real, and filmable.
- TWO COILS at 90 deg, both commutated, in series (Siemens' drum, 4 segments): drive 65.8/53.3/40.1/32.4/40.7/51.5/67.1
  mN m per 80 A-turns each at 1..89 deg, MEAN 50.1, MIN 32.4: NO DEAD SPOT, starts anywhere; cogging 0. On six pots
  (2 x 1 Ohm coils in series): I ~0.94 A, ~47 mN m mean (30 worst) -> a 2:1 belt for the 0.09 N m the empty cart needs.
- TABLE: physics/data/drum2-torque.csv (two-coil drum, every 5 deg over the 90 deg period, drive per ampere-turn, cogging,
  iron peak): mean 0.598 mN m per A-turn (47.8 per 80). The game's motor.jl :drum rotor reads this (x end correction).
- HAUL (physics/drummotor.jl, two-coil drum from the CSV x 3D end correction 1.105, six pots, 1 cm rope drum, rope
  load as RESISTANCE not a driving torque): free 8.3 rev/s. Empty cart on planks (9 N): DRY bearing (2.3 kg iron drum,
  3 mm axle, mu 0.25 = 17.9 mN m, a third of the torque) stalls at 2/3/4:1 (stops at the 45 deg weak spot: 33 mN m min
  stall), hauls at 6:1 = 4.35 cm/s (2.9 W). GREASED (mu 0.05): 3:1 = 8.4 cm/s, 4:1 = 9.5 cm/s. Dry sand (76 N): still
  stalls at 32:1. Loaded cart: hopeless on pots (accumulator, #781). PLAYER CHOICES that matter, all real: grease the
  bearing, belt ratio, pots, turns (wire resistance vs pots' walls).
- IN motor.jl (s172, additive; the drum = false path is identical to the published copy, checked by running both):
  Build(drum = true, coils = 2) takes its torque per amp from physics/data/drum2-torque.csv (x N x 3D end correction),
  back-EMF = -torque per amp, circuit always closed (the table holds the 4-segment commutation). Motor.iron_drum_bench():
  from rest on six pots 6.1 rev/s dry (I 0.64 A), 9.2 greased (mu 0.05), starts from its weak 45 deg spot too.
  NOT YET: its inductance is the air-core turn's (iron raises it: transients only), no sparks at the 4 handovers.
- s172 END: PUBLISHED plugins/irondrum.jl: the iron drum motor (iron drum, two copper coils, 4-segment ring, brushes,
  oak posts, the ferrite stones) on a round oak block at (4.85,-14.3), 0.6 m west of the bench; Motor.step! on
  iron_drum_bench every frame (7.1 rev/s at 4.4 s), 0.06 ms. Raster media/s172-irondrum-2.png. Missing: the six pots and
  cords drawn to it, a switch (it always runs), commutator gaps, the belt/rope/cart, a traced look.
- s172 LAST: the drum motor got a SWITCH (published): K within 0.8 m in Jump in; Lumi walks over every 200 s when nobody
  plays and pecks it (goal :drum, action :eat); at 5 rev/s it calls out the speed; off, it coasts to rest in ~3 s on the
  bearing (18.6 mN m against J 1.2e-3). Events :drum_switch, :drum_spun_up. Not done: pots/cords drawn to it.
- s172 SOUND (published): site/voice/game/drum-on.wav (spin-up 4 s) and drum-off.wav (coast from full speed), synthesised
  from Motor.step! at 22 kHz: a click at each commutator handover (4 a turn) as loud as the current it breaks, the
  torque ripple's hum (12 harmonics of 4 x rev/s), brush hiss with speed. Played in every open page on switching
  (irondrum.jl id_sound!, via the voice plugin's sessions). Not heard by me: no page open in the sandbox; check in a browser.
