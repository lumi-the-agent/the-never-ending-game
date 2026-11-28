# The cart's motor on a rope: winch anything up the beach
Goal: (passed s173, round 2: surprise 6 fun 8 real 7 toward 9) The player hooks the drum motor's rope to anything on the island (a log, a crate, the empty cart, a friend on the cart) and picks a pulley; the motor hauls it or stalls by what it weighs and how it rolls, and the stall shows: rope taut, drum stopped, the brushes sparking bright on the stall current. Nothing quoted or fitted: rope, cart mass (mesh volume x density) and rolling by contact, torque from the circuit each step.
Next: (s173 done: physics/rope.jl hauls a 0.8 kg crate 2 m, the 1.5 kg log stalls in the brushes' dead windows; s174: the s173 spark film was dark blocks behind the stone, retake drum_spark2 queued, sparks dimmer/bluer.) 1) brush width as a part: make-before-break (brush wider than the gap) so a loaded motor never sits in a dead window; 2) the rope + pawl IN THE GAME by the drum, drawn as a tube through rope.jl's particles, coiling on an oak drum; 3) the empty cart (mass from its mesh) on the planks hauled 30 cm+ = the perfectionist's done_when for #780; film it.

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

## s173 free time: DOES THE DRUM MOTOR SPARK BLUE IN THE DARK? (rough, honest)
- motor.jl's drum Build records NO sparks: the drum path treats the circuit as always closed (the 2D table holds the
  commutation). But the Build's own geometry is brush_w 8 deg < gap 20 deg (iron_drum_bench keeps the defaults):
  BREAK-BEFORE-MAKE, the brush leaves a segment with the full ~0.64 A running. The table and the parts disagree.
- Coil inductance with the iron drum (Motor2D, magnet2d env, flux from A_x at the side centres, N 80, 9 cm):
  air core 0.75 mH; linear iron 64 mH (mu_r 300) to 422 mH (2000), scaling with mu_r = flux closing round each slot
  through the 2 mm iron bridge, which saturates at a few A-turns. Saturating solve with the stones on, -26..+26 A-turns:
  ~3 mH large-signal, BUT lambda(NI) came out non-monotone (Picard 16 passes not converged): treat 1-5 mH as the range.
  The drum is SOLID iron: skin depth ~0.7 mm at the commutation time scale (~8 ms) -> eddies lower L further.
- So per break ~1/2 L I^2 = 0.2-1 mJ (0.6 at 3 mH), ~4 breaks a rev x 6 rev/s. 0.64 A is above copper's minimum arc
  current (~0.43 A, min arc voltage ~13 V), and a micrometre gap opening at 0.7 m/s sees L dI/dt >> 330 V (Paschen): a
  real small arc, visible in the dark (ESD sparks of 10 uJ show). Colour: air N2 lines 337-400 nm = violet-blue;
  copper vapour (an arc above min current) adds green 510-521 nm. On pots: a faint blue-violet/green flicker at the
  brushes, only in real dark. On the accumulator (amps): bright, eroding.
- TO DO if it goes in: Build drum path logs a spark per brush break (gap > brush_w) and drops the drive for those
  12 deg of each 90 (or widen brushes > gap: then the shorted coil decays with tau = L/R ~3 ms over the bridge time and
  sparks smaller). Converge solve_nl (more passes, smaller relax) before trusting L.

- s173 IN THE GAME (published): Motor.Build commutate = true, L_circuit = 4e-3 (iron_drum_bench): the circuit opens
  for 12 deg of each 90 (drum_open), 1/2 L I^2 logged per break: 18 sparks/s at 4.9 rev/s free, 0.62 mJ mean, 1.4 at
  start. plugins/irondrum.jl: 4 copper segments with 20 deg gaps on an oak hub, a spark light (Hikari.Emission
  strength 60, r 2.2 mm) at each brush's trailing edge in every frame with a break, sized by sqrt(E / 0.6 mJ); event
  kind :commutator_spark (once per run). Coils drawn as 4 x 3 turns of 1 mm wire; the stones are Motor.rough_stone
  with mo_stone; six pots of its own on the sand 0.4 m south + cords to the brushes. drum_spun_up now at > 4.5 rev/s.
  Traced at 19:45 (media/s173-spark-traced.png): both brushes flash and light the ring orange. Film:
  site/films/drum-sparks.mp4 (movies/drumspark.jl). Sparks are white-orange on camera, not violet: emission
  (0.62,0.74,1) at 60 saturates; try ~20 and bluer.

- s173 PASSED (critic round 2) also 'Set the brushes for the load' (surprise 8 fun 7 real 7 toward 8): per-coil
  commutation with L(θ, I1, I2) from saturating solves over angle AND both currents (armature reaction from the solve),
  brush contact resistance from patch overlap, Lumi's hand turns the rocker in Jump in; needs THIS winch's real load
  first (todo #785). Critic's warnings for the winch: a rod chain wrapped round a drum under IPC is where it breaks or
  gets swapped for a spring -> use the tether + reel-length model (above), honest and the field's own method; a cart
  creeping on planks is slow to watch: film the stall and the choice (pulley), not the creep.
- LOOKED (rule 6, s173): no rope/rod type in PrintSim (sheets, affine bodies, FE solids, joints, steppers). RomeoDB:
  KiteModels (tether particles + reel-out), SymbolicAWEModels (pulley_rope_mass, Pulley), WinchModels (motor/gearbox/
  drum, TorqueControlledMachine), WinchControllers. Their tethers are tied to kite models; the equations are a few
  lines, so rope.jl writes the same model for our drum (cite them), WinchModels for the drum/gear inertia if it fits.
- s173 FIRST HAUL (physics/rope.jl, module Rope: tether particles + reel length, Coulomb ground friction; motor.jl
  step!(...; τload) = rope tension x drum r / ratio; drum r 3 cm, 6:1, greased bearing, 12 segments of hemp EA 25 kN):
  a 1.5 kg log on sand (needs 7.36 N) moves 16 cm, then STALLS FOR GOOD at T 7.3 N; a 5 kg crate moves 2.4 cm and the
  taut rope then drives the drum BACKWARDS (-0.8 rev/s). Both from the s173 break-before-make brushes: 12 deg of every
  90 is a DEAD WINDOW (circuit open, no torque); a loaded motor that stops in one never restarts, and with no torque the
  rope's stretch unwinds the drum. Real winches have a PAWL (ratchet) and real motors brushes WIDER than the gaps
  (make-before-break, the brushes project). Those are the player's first two choices. Next: a pawl on the rope drum,
  brush width as a Build part (wide = no dead window, the shorted coil's L/R decides the spark), then the cart.
  rope.jl now SVector-based: 3 x 15 s hauls in 0.17 s (~0.13 ms a frame), game-ready; needs the GAME env (StaticArrays).
- s173 WITH A PAWL (Build pawl = true: the shaft turns forward only) and a stable rope (substep follows the segment's
  omega = sqrt(EA/lin_mass)/L0; NaN before when the rope reeled short), 15 s, r 3 cm, 6:1, greased: 0.8 kg crate on
  sand HAULED 2.06 m at 5.1 rev/s (T 4 N); 1.5 kg log (needs 7.36 N) jerks 16 cm on the SNATCH (slack rope snaps taut:
  Tmax 18.5 N = 2.5x steady) then stalls, held 7.2 N; the same log with NO dead windows (commutate = false, i.e. what
  make-before-break brushes would give) moves 81 cm, still 1.5 rev/s; 5 kg crate 1.9 cm, held at 16 N by the pawl.
  Six pots are AT THE EDGE for a 1.5 kg log on sand: brush width decides it. The snatch is worth showing (rope jumps).
  Test code: the haul2 function in this note's session (motor.jl step!(st, b, dt; τload) + Rope.step!(r, load, dt; reel)).
