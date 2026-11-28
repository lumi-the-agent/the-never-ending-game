# The two-coil iron drum motor on clay pots, hauling (s172, project winch). Standalone: reads the torque table that
# physics/motor2d.jl solved (physics/data/drum2-torque.csv: drive per ampere-turn and cogging over the 90 deg period),
# scales it by the coils' turns and by the 3D end correction (em.jl 3D air core 30.4 / 2D 27.5 mN m), and steps the rotor:
#   J dω/dt = kt(θ) I + cog(θ) - friction - load / ratio,   I = (V_pots - kt(θ) ω) / (R_pots + R_coils)
# (back-EMF per rad/s = torque per amp: the same coupling, energy holds). Bearing friction from the drum's own weight.
# The game's motor.jl gets a :drum rotor from the same table next session; this answers 'how fast does it haul'.
module DrumMotor

const TABLE = joinpath(@__DIR__, "data", "drum2-torque.csv")
const END3D = 30.4 / 27.5

function load_table(path = TABLE)
    rows = [parse.(Float64, split(l, ",")) for l in eachline(path) if !startswith(l, "#") && !isempty(strip(l))]
    θ = deg2rad.(getindex.(rows, 1)); kt = getindex.(rows, 2); cog = getindex.(rows, 3)
    return (; θ, kt, cog)
end

"Linear interpolation over the 90 deg period."
function at(tab, v, θ)
    p = pi / 2; x = mod(θ, p); h = tab.θ[2] - tab.θ[1]
    i = clamp(floor(Int, x / h) + 1, 1, length(tab.θ) - 1); f = (x - tab.θ[i]) / h
    (1 - f) * v[i] + f * v[i+1]
end

"""
Run the motor from rest for `seconds` with a rope pulling `F` newtons on a drum of radius `r_drum` behind a `ratio`:1
belt. N turns a coil (two coils in series), wire radius rw, `pots` clay pots in series (0.78 V, 0.5 Ohm each).
Returns the steady speed, the rope's speed, the current and the electric power, and whether it stalled.
"""
function haul(; F = 9.0, r_drum = 0.01, ratio = 2.0, N = 80, rw = 0.35e-3, pots = 6, seconds = 8.0, dt = 1e-4,
              mu_bearing = 0.25, r_axle = 0.003, tab = load_table())
    turn = 2 * 0.09 + 2 * 0.054                           # one turn round the drum (m)
    Rc = 2 * 1.7e-8 * N * turn / (pi * rw^2)               # two coils in series
    V = 0.78pots; Rp = 0.5pots
    m = 7870 * pi * 0.032^2 * 0.09 + 2 * 8960 * N * turn * pi * rw^2
    J = 0.5 * m * 0.032^2
    τfric = mu_bearing * m * 9.81 * r_axle
    τload = F * r_drum / ratio
    θ = 0.3; ω = 0.0; I = 0.0
    for _ in 1:round(Int, seconds / dt)
        kt = END3D * N * at(tab, tab.kt, θ)
        I = (V - kt * ω) / (Rp + Rc)
        τ = kt * I + at(tab, tab.cog, θ)
        # the rope's pull is RESISTANCE (a cart rolling or a log sliding on the level opposes motion, never drives it
        # back), so it acts like friction together with the bearing: it holds a motor that cannot beat it
        res = τfric + τload
        if ω <= 0 && τ <= res
            ω = 0.0
        else
            ω += dt * (τ - res) / J
        end
        θ += ω * dt
    end
    return (rev_s = ω / 2pi, stall_mNm = 1000 * END3D * N * minimum(tab.kt) * V / (Rp + Rc), rope_cm_s = 100 * ω / ratio * r_drum, I = I, P_in_W = V * I, R_coils = Rc,
            τ_load_mNm = 1000τload, τ_fric_mNm = 1000τfric, stalled = ω <= 1e-3)
end

end
