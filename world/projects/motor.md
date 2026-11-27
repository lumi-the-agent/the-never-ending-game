# A motor fitted by hand
Goal: The player fits a motor together from parts on a bench (two stones, a wooden rotor wound with copper, an axle in forked sticks, a split copper ring, two springy brushes, cells) and touches the last wire: built right it kicks, maybe stalls on its dead spot until flicked with the beak, then whirs; with a stone turned round it runs backwards, with the brushes off it stalls, with the beach lodestone it is too weak. Tinkering until it runs is the game, and every fault is the real fault. Then it drives the cart (big goal).
Next: (honest film is up s155, weak: small, a friend in a glass ball behind it) film 2 close and in real materials (copper, wood grain, iron-black stones), Lumi's beak flicking the stuck rotor (20 rad/s dies, 30 runs; todo #736); then the bench plugin (#734: physics/motorlook.jl draws a build, Motor.State/step!/flick! drive it live at 0.05 ms/frame); then the brine cell (#735; the circuit solver is physics/circuit.jl since s155, NOTES 'The circuit solver').

## s154: physics/motor.jl (passed idea round 1: surprise 8, fun 8, real 7, toward 10)
- Parts only: em.jl magnets (any mesh, any material), one turn of the coil as a polyline (wound N times, wire radius),
  split ring segments and gap, brush angles/width/spring force, cells. Torque = sum of I dl x B over the turn in the
  stones' field; back-EMF = sum of (v x B).dl along the same turn (came out exactly -torque per amp: energy holds);
  switching = which segment each brush overlaps at this angle (open in a gap, :short if one brush bridges both);
  L dI/dt with Neumann's inductance of the turn; Coulomb friction from rotor weight and brush springs.
- `Motor.motor_cases()` (bench size, 3 cells, ferrite): built right runs (11.3 rev/s at 1.5 s, sparks at each handover);
  started on the dead spot does not; a 40 rad/s beak flick starts it; both stones turned round runs backwards;
  one stone turned round: no field in the gap, no torque; beach lodestone (magnetite Br 0.06): 0.13 mN m < friction 0.25: stalls;
  brushes a quarter turn off: stalls; one cell: stalls from pi/2 (ran from 0.8 rad: weak motors depend on the start).
- Film size (x3, movies/motor.jl `film_build`): a 20 deg gap stopped it INSIDE the gap (heavy rotor, too slow to coast
  across); 10 deg gap, 6 cells: lurches 0.46 -> 0.2 -> 0.96 -> 1.18 rev/s over 2 s, 3.7 rev/s at 8 s. Real time, no slow-mo.
- Film: job 20261127-212504-198 -> site/films/first-motor.mp4, pending post my-first-motor. 3/4 view from the ring end,
  Lumi 3.2 m behind (whole body in frame). Weak: the board is a plain brown slab, the stones plain black cylinders;
  nobody visibly closes the circuit (it switches on at 1 s). Next film: Lumi's beak touching the wire, a real wood board.
- Not yet: the rotor's own weight torque (balanced rotor assumed), arcing wear, heating of the coil (Joule), iron core.

## s154 late: the coarse quadrature lied
- rect_turn had 4 segments (one field sample per side at its MIDPOINT, where the stones' field is strongest): torque
  ~30% too high (big bench peak 10.4 -> 7.2 mN m with 10 points per side). With it, motor_cases: everything stalls
  except the flicked one. The film job 20261127-212504-198 (first-motor.mp4) used the coarse turn: NOT posted
  (pending/withdrawn/my-first-motor.json). More brine cells don't help (3 ohm each: current stays ~0.25 A).
  Ways to a motor that starts by itself: cells of lower resistance (bigger plates, closer), more turns, pole pieces as
  long as the coil (iron shoes on the stones: softiron.jl), a narrower ring gap, lighter brushes. All are parts the player picks.
- Big bench (Motor.big_bench, 10 pts per side), from the dead spot, switched on: flick 6 or 12 rad/s dies at once,
  20 rad/s turns ~12 handovers then dies in the gap, 30 rad/s keeps it going (1.29 rev/s at 8 s, 45 sparks). That is
  the retake: a weak flick that fails, then a hard one. em.jl H no longer allocates: Motor.State 10.9 s -> 0.61 s
  (H identical to 6e-16, em selftest unchanged), fine for rebuilding live when the player turns a stone round.
- Honest film queued: job 20261127-213341-002 -> site/films/first-motor-sticks.mp4 (5 s, corrected build: turns 74 deg and sticks),
  pending post my-first-motor. Next film: the flicks (20 dies, 30 runs) with Lumi's beak doing them.
