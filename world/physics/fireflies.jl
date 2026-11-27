# Fireflies that fall into step (s131). Each fly is a pulse-coupled oscillator: a phase φ in [0,1) runs at its own
# natural rate 1/T; at φ = 1 it flashes and starts over. A flash it SEES (a neighbour within `see` metres, or the
# player's lantern within `lantern_see`) shifts its phase by a phase response curve: early in its cycle (just
# flashed) it waits a little, late in its cycle it hurries. That is the model biologists fit to Pteroptyx and
# Photinus fireflies (Buck 1988; Ermentrout 1991: advance AND delay, so a fly can lock to a beat a bit faster OR
# slower than its own; Mirollo & Strogatz 1990 for pure advance). Locking only happens inside a band of tempos
# (an Arnold tongue): a lantern far off the field's own beat is ignored, one near it is followed, and a slow drift
# of the lantern's tempo drags the whole field along.
# Runs as two KernelAbstractions kernels (advance, then couple on the previous frame's flashes, which is the
# fly's reaction delay); the same code runs on KA.CPU() or Mantle.Device().
using Raycore, GeometryBasics, Random
const KA = Raycore.KernelAbstractions
using .KA: @kernel, @index

Base.@kwdef mutable struct Swarm{V,P}
    pos::P                 # Vector{Point3f}: where each fly hovers
    φ::V                   # phase 0..1
    rate::V                # 1/T, flashes per second
    fired::Vector{Bool}    # flashed this step (host side, read by the renderer)
    age::V                 # seconds since the last flash (for the glow)
    fired_d::Any           # device copies
    pos_d::Any
end

@kernel function ff_advance!(φ, rate, fired, age, dt)
    i = @index(Global)
    @inbounds begin
        p = φ[i] + rate[i] * dt
        f = p >= 1f0
        φ[i] = f ? p - floor(p) : p
        fired[i] = f
        age[i] = f ? 0f0 : age[i] + dt
    end
end

# PRC: Δφ = -eps * sin(2πφ) / 2π (delay just after a flash, advance before the next); a phase pushed past 1
# flashes now (absorption), which is what makes a group lock tight.
@kernel function ff_couple!(φ, fired_now, fired, pos, n, see2, eps, lpos, lfired, lsee2, leps, maxkick)
    i = @index(Global)
    @inbounds begin
        pi_ = pos[i]
        kick = 0f0
        twopi = 6.2831855f0
        s = -sin(twopi * φ[i]) / twopi
        for j in 1:n
            (j == i || !fired[j]) && continue
            d = pos[j] - pi_
            d[1]^2 + d[2]^2 + d[3]^2 < see2 && (kick += eps * s)
        end
        kick = clamp(kick, -maxkick, maxkick)
        if lfired
            d = lpos - pi_
            d[1]^2 + d[2]^2 + d[3]^2 < lsee2 && (kick += leps * s)
        end
        p = φ[i] + kick
        fired_now[i] = p >= 1f0
        φ[i] = clamp(p, 0f0, 0.9999f0)
    end
end

"""
    ff_swarm(centre, n; spread = (7, 5), height = (0.4, 2.2), period = 0.55, jitter = 0.08, seed = 1, ground)

`n` flies scattered over an ellipse around `centre` (x, y), `height` metres over `ground(x, y)`, natural periods
`period` seconds ± `jitter` (relative), random phases.
"""
function ff_swarm(centre, n; spread = (7f0, 5f0), height = (0.4f0, 2.2f0), period = 0.55f0, jitter = 0.08f0,
                  seed = 1, ground = (x, y) -> 0f0)
    rng = Random.Xoshiro(seed)
    pos = Point3f[]
    while length(pos) < n
        u, v = 2rand(rng, Float32) - 1, 2rand(rng, Float32) - 1
        u^2 + v^2 > 1 && continue
        x = centre[1] + spread[1] * u; y = centre[2] + spread[2] * v
        push!(pos, Point3f(x, y, ground(x, y) + height[1] + (height[2] - height[1]) * rand(rng, Float32)^1.5f0))
    end
    rate = Float32[1 / (period * (1 + jitter * (2rand(rng, Float32) - 1))) for _ in 1:n]
    Swarm(; pos, φ = rand(rng, Float32, n), rate, fired = fill(false, n), age = fill(10f0, n),
          fired_d = fill(false, n), pos_d = pos)
end

"""
    ff_step!(sw, dt; lantern = nothing, lantern_fired = false, backend = KA.CPU(), see = 2.5, eps = 0.06,
             lantern_see = 6, lantern_eps = 0.35, maxkick = 0.2)

One step: phases advance by `dt`, then each fly reacts to the flashes of the step before (its reaction delay)
and to the lantern if it flashed this step. Fills `sw.fired` with who flashes now.
"""
# Defaults measured s131 (300 flies over 8x5 m, periods 0.55 s ± 8%, r = Kuramoto order after 2-16 s): no lantern
# r 0.1-0.25 (twinkle, small local clusters); lantern on the field's beat (0.55 s) r 0.95 within 2 s; lantern at
# 0.35 s r 0.1-0.3 (ignored). Neighbour eps 0.06 synced the whole field by itself in 1 s: too strong.
function ff_step!(sw::Swarm, dt; lantern = Point3f(0, 0, -100), lantern_fired = false, backend = KA.CPU(),
                  see = 2.5f0, eps = 0.012f0, lantern_see = 7f0, lantern_eps = 0.6f0, maxkick = 0.06f0)
    n = length(sw.φ)
    prev = copy(sw.fired)                       # last step's flashes: what each fly saw
    ff_advance!(backend, 64)(sw.φ, sw.rate, sw.fired, sw.age, Float32(dt); ndrange = n)
    now = similar(sw.fired)
    ff_couple!(backend, 64)(sw.φ, now, prev, sw.pos, n, Float32(see)^2, Float32(eps), Point3f(lantern),
                            lantern_fired, Float32(lantern_see)^2, Float32(lantern_eps), Float32(maxkick); ndrange = n)
    KA.synchronize(backend)
    @inbounds for i in 1:n
        if now[i] && !sw.fired[i]               # pushed over the edge: flashes now
            sw.fired[i] = true; sw.age[i] = 0f0; sw.φ[i] = 0f0
        end
    end
    return sw
end

"How much of the field flashes together: the Kuramoto order parameter r = |mean(exp(2πiφ))| (0 random, 1 one beat)."
ff_order(sw::Swarm) = abs(sum(cis(2π * p) for p in sw.φ) / length(sw.φ))
