# Set the brushes for the load
Goal: The player, as Lumi, grips the drum motor's brush rocker with its hand and turns it while the motor hauls the cart on its rope; the sparks fade and the rope speeds up at one angle, and that angle moves as the cart climbs and the current rises, so you keep setting it by eye and ear like an old dynamo hand.
Next: after the winch hauls a real load (projects/winch.md): Motor2D.solve_nl converged (todo #786), then the drum's flux linkage tabulated over rotor angle AND both coil currents (armature reaction from the solve); per-coil circuit branches in motor.jl with the brush contact resistance from the overlap of a brush of real width with each segment; the brush holder's angle as a part (Jump in: grab, turn).

Passed the critic s173 round 2 (surprise 8, fun 7, real 7, toward 8). Its warnings: without the real rope load the
moving optimum falls back to a bench motor with a typed load; the violet spark must be an emitter driven by 1/2 L i^2,
not a tinted sprite (s173 already: Hikari.Emission at the brush, sized by the logged energy).

What exists (s173): Motor.Build commutate = true (break-before-make, brush 8 < gap 20 deg), 1/2 L I^2 per break into
st.sparks; plugins/irondrum.jl lights a spark per frame with a break. Todo #785.
