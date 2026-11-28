# The winch's first check (s173, project winch): the iron drum motor on six pots, a 6:1 gear, a 3 cm oak rope drum and
# 3 m of hemp rope (physics/rope.jl) to a load lying on sand. The motor's circuit and the rope's tension are solved
# together every frame: the tension through the gear is the motor's load torque, the drum's turn reels the rope in.
# s173 results: 0.8 kg crate hauled 2.06 m at 5.1 rev/s; 1.5 kg log jerks 16 cm on the snatch, then stalls (held by
# the pawl); the same log without dead windows (commutate = false) 81 cm; 5 kg crate 1.9 cm, held at 16 N.
#   include("physics/motor.jl"); include("physics/rope.jl"); include("physics/rope_check.jl"); rope_check()
function haul(; m = 1.5, mu = 0.5, ratio = 6.0, rdrum = 0.03, seconds = 15.0, dt = 1 / 30, pawl = true, commutate = true)
    b = Motor.iron_drum_bench(; mu_bearing = 0.05); b.pawl = pawl; b.commutate = commutate
    st = Motor.State(b; on = true)
    r = Rope.Tether((0.0, 0.0, 0.0), (3.0, 0.0, 0.0); n = 12, slack = 1.02)
    load = Rope.Load(; m, mu, x = (3.0, 0.0, 0.0))
    T = 0.0; Tmax = 0.0
    for _ in 1:round(Int, seconds / dt)
        θ0 = st.θ
        Motor.step!(st, b, dt; τload = T * rdrum / ratio)
        T = Rope.step!(r, load, dt; reel = (st.θ - θ0) / ratio * rdrum)
        Tmax = max(Tmax, T)
    end
    (; moved_cm = round(100 * (3.0 - load.x[1]), digits = 1), rev_s = round(st.ω / 2pi, digits = 2), T = round(T, digits = 1),
       Tmax = round(Tmax, digits = 1))
end

function rope_check()
    light = haul(; m = 0.8); log = haul(; m = 1.5); heavy = haul(; m = 5.0)
    @assert light.moved_cm > 150 "a 0.8 kg crate should come in: $light"
    @assert heavy.moved_cm < 10 && heavy.rev_s == 0 "a 5 kg crate on sand is beyond six pots: $heavy"
    @assert isfinite(log.T) "the rope must stay finite: $log"
    (; light, log, heavy)
end

"""
s176 (todo #790): the winch with the rope PILING UP on its drum and a gear between motor and drum. `ratio` motor turns
per drum turn, drum core `r0`, width `W`, rope diameter `d`, `Lw0` metres already on the drum. The working radius comes
from the wound length each step (Rope.wound_radius); pull = gear torque / r, reel = drum turn x r.
"""
function haul_fill(; m = 0.88, mu = 0.5, ratio = 6.0, r0 = 0.02, W = 0.06, d = 0.009, Lw0 = 0.3, grade = 0.08,
                   seconds = 30.0, dt = 1 / 30, dist = 2.3)
    b = Motor.iron_drum_bench(; mu_bearing = 0.05); b.pawl = true
    st = Motor.State(b; on = true)
    r = Rope.Tether((0.0, 0.0, 0.0), (dist, 0.0, 0.0); n = 12, slack = 1.04)
    load = Rope.Load(; m, mu, x = (dist, 0.0, 0.0), grade)
    T = 0.0; Lw = Lw0; rmin = Inf; rmax = 0.0; tstop = seconds
    for k in 1:round(Int, seconds / dt)
        rd = Rope.wound_radius(r0, d, W, Lw); rmin = min(rmin, rd); rmax = max(rmax, rd)
        θ0 = st.θ
        Motor.step!(st, b, dt; τload = T * rd / ratio)
        reel = (st.θ - θ0) / ratio * rd
        Lw += reel
        T = Rope.step!(r, load, dt; reel)
        load.x[1] < 0.35 && (tstop = k * dt; break)
    end
    (; ratio, r0, d, moved_cm = round(100 * (dist - load.x[1]), digits = 1), secs = round(tstop, digits = 1),
       rev_s = round(st.ω / 2pi, digits = 2), r_mm = (round(1e3rmin, digits = 1), round(1e3rmax, digits = 1)), T = round(T, digits = 1))
end
