# Set the brushes for the load
Goal: The player, as Lumi, grips the drum motor's brush rocker with its hand and turns it while the motor hauls the cart on its rope; the sparks fade and the rope speeds up at one angle, and that angle moves as the cart climbs and the current rises, so you keep setting it by eye and ear like an old dynamo hand.
Next: after the winch hauls a real load (projects/winch.md): (s175 done: Motor2D.solve_newton converges, L_d ~8 mH at 0.64 A) then the drum's flux linkage tabulated over rotor angle AND both coil currents (armature reaction from the solve); per-coil circuit branches in motor.jl with the brush contact resistance from the overlap of a brush of real width with each segment; the brush holder's angle as a part (Jump in: grab, turn).

Passed the critic s173 round 2 (surprise 8, fun 7, real 7, toward 8). Its warnings: without the real rope load the
moving optimum falls back to a bench motor with a typed load; the violet spark must be an emitter driven by 1/2 L i^2,
not a tinted sprite (s173 already: Hikari.Emission at the brush, sized by the logged energy).

What exists (s173): Motor.Build commutate = true (break-before-make, brush 8 < gap 20 deg), 1/2 L I^2 per break into
st.sparks; plugins/irondrum.jl lights a spark per frame with a break. Todo #785.

## s176: the post 'Where the brushes let go' missed again (critic, second look)
- The retake must be a FILM, not a still (a still can't show a brush letting go). Needs: brushes in sprung holders
  (a copper leaf on a clamp, the spring visible), the commutator's 4 segments and gaps readable (bright copper, dark mica
  gaps, lit), the arc as a thin emissive streak at the trailing edge, not a sphere, and the drum lit (no black half frame).
  Brushes are 30 deg wide now (make-before-break): the arc comes only from commutate!'s leftover current.
