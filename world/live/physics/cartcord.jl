# The cart drives itself on a long cord (s177, project cartcord). The iron drum motor (motor.jl, iron_drum_bench: the
# same Build the winch runs) bolted on the cart's frame, a leather belt from its 10 mm pulley to a 60 mm pulley on the
# rear axle, and a twin copper cord back to the six clay pots on the block. Nothing sets a speed:
#   motor:  J dω/dt = τ_motor(I, θ) - F_belt r_p            (Motor.step!, its circuit now includes the cord's copper)
#   belt:   an elastic band, F = k δ + c δ', δ' = r_p ω - r_a ω_axle; it SLIPS at the capstan limit
#           F_max = 2 T0 (e^(μθ) - 1) / (e^(μθ) + 1) (Euler-Eytelwein, θ the wrap, T0 the pretension)
#   cart:   m dv/dt = F_belt r_a / r_w (at most the rear wheels' grip μ N_rear) - rolling - weight x slope - cord
#   cord:   Rope's tether (particles + springs that only pull, ground friction): one end clipped to the pots by a
#           spring clip, the other tied to the cart. Taut, it pulls the cart back and the clip off: when its tension
#           beats the clip's grip the clip lets go, the circuit opens and the cart coasts on, trailing a dead cord.
# The six pots (9 kg on oak, μ 0.5: 44 N to slide) are far beyond the ~4 N this motor gives at the wheels: the clip, not
# the pots, is what a yank moves. Looked first (rule 6): no belt/capstan or cart model in RomeoDB worth taking for
# these few lines; the motor, rope and soil are mine already (motor.jl, rope.jl, wheelsand.jl).
module CartCord

# Motor (motor.jl) and Rope (rope.jl) are included into the same parent module first
import ..Motor, ..Rope
using LinearAlgebra
const G = 9.81
const RHO_CU = 1.7e-8

Base.@kwdef mutable struct Cart
    m::Float64 = 8.0 + 2.6            # oak frame and wheels + the drum motor (iron 2.3 kg, copper, brushes)
    r_w::Float64 = 0.10               # wheel radius
    crr::Float64 = 0.02               # rolling resistance on planks (oak rim on oak plank)
    mu_grip::Float64 = 0.45           # oak rim on a dry plank: the most the driven wheels push
    rear::Float64 = 0.55              # share of the weight on the driven rear axle (the motor sits over it)
    slope::Float64 = 0.0              # rise per metre along the track
    x::Float64 = 0.3                  # metres from the pots along the track
    v::Float64 = 0.0
end

Base.@kwdef mutable struct Belt
    r_p::Float64 = 0.010              # small pulley (on the motor, or on the countershaft after the gear)
    r_a::Float64 = 0.060              # axle pulley (6:1); it must clear the ground: r_a < r_w - 2 cm
    gear::Float64 = 1.0               # s177: an oak cog pair before the belt (the winch's 6-cog pinion on a 36-cog wheel = 6)
    eta::Float64 = 0.9                # the wooden cogs' efficiency (sliding teeth, tallow)
    T0::Float64 = 15.0                # pretension (N)
    mu::Float64 = 0.4                 # leather on oak
    wrap::Float64 = pi                # on the small pulley
    k::Float64 = 13e3                 # leather 2 kN EA over a 15 cm span
    c::Float64 = 20.0
    δ::Float64 = 0.0
    slipping::Bool = false
end
fmax(b::Belt) = (e = exp(b.mu * b.wrap); 2b.T0 * (e - 1) / (e + 1))

"Twin cord: two 0.75 mm^2 copper conductors there and back, in cloth."
cord_ohm(L; A = 0.75e-6) = 2RHO_CU * L / A

"The whole drive: motor, belt, cart, cord, clip. One `step!(sim, dt)` per millisecond (the game calls it in a loop)."
mutable struct Sim
    b::Motor.Build; st::Motor.State; cart::Cart; belt::Belt; cord::Rope.Tether
    clipped::Bool; F_clip::Float64; Fmax::Float64; F::Float64; Tc::Float64; t::Float64
    F_buf::Vector{Rope.V}; events::Vector{Tuple{Float64,String}}; taut::Bool
    F_ext::Float64                     # s177: a push on the cart along the track (N, + = away from the pots)
end

function Sim(; L_cord = 4.0, F_clip = 2.5, cart = Cart(), belt = Belt(), pots = 6, n = 12, on = true)
    belt.r_a < cart.r_w - 0.02 || error("the axle pulley (r $(belt.r_a)) would scrape the ground under wheels of r $(cart.r_w)")
    b = Motor.iron_drum_bench(; cells = pots)
    b.R_contact += cord_ohm(L_cord)
    st = Motor.State(b; θ0 = 0.3, on)
    cord = Rope.Tether((0.0, 0.0, 0.0), (cart.x, 0.0, 0.0); n, slack = L_cord / cart.x, lin_mass = 0.03, EA = 40e3,
                       mu_ground = 0.5)
    cord.L = L_cord
    Sim(b, st, cart, belt, cord, true, F_clip, fmax(belt), 0.0, 0.0, 0.0, Vector{Rope.V}(undef, n + 1),
        Tuple{Float64,String}[], false, 0.0)
end

function step!(s::Sim, dt)
    cart = s.cart; belt = s.belt; st = s.st
    # belt between the small pulley (after the cogs) and the axle pulley (the axle turns with the wheels on planks)
    ωa = cart.v / cart.r_w
    rate = belt.r_p * st.ω / belt.gear - belt.r_a * ωa
    F = belt.k * belt.δ + belt.c * rate
    if abs(F) > s.Fmax
        F = sign(F) * s.Fmax; belt.δ = sign(F) * s.Fmax / belt.k
        belt.slipping || push!(s.events, (s.t, "belt slips"))
        belt.slipping = true
    else
        belt.slipping = false
        belt.δ += rate * dt
    end
    Motor.step!(st, s.b, dt; τload = F * belt.r_p / (belt.gear * (F > 0 ? belt.eta : 1 / belt.eta)))
    # the cart: belt at the ground (grip-limited), rolling, the slope, the cord
    Fd = clamp(F * belt.r_a / cart.r_w, -cart.mu_grip * cart.rear * cart.m * G, cart.mu_grip * cart.rear * cart.m * G)
    Fs = -cart.m * G * cart.slope / sqrt(1 + cart.slope^2)
    Tc, Tclip = cord_step!(s.cord, cart, s.clipped, dt, s.F_buf)
    Fn = Fd + Fs - Tc + s.F_ext
    roll = cart.crr * cart.m * G
    if abs(cart.v) < 1e-6 && abs(Fn) <= roll
        cart.v = 0.0
    else
        vn = cart.v + dt * (Fn - roll * sign(abs(cart.v) > 1e-6 ? cart.v : Fn)) / cart.m
        cart.v = (cart.v != 0 && vn * cart.v < 0) ? 0.0 : vn
    end
    cart.x += cart.v * dt
    if s.clipped && Tclip > s.F_clip
        s.clipped = false; st.on = false
        push!(s.events, (s.t, "the clip pulls off the pot: circuit open"))
    end
    !s.taut && Tc > 0.5 && (s.taut = true; push!(s.events, (s.t, "cord taut")))
    s.F = F; s.Tc = Tc; s.t += dt
    s
end

"""
    drive(; L_cord = 4.0, seconds = 40, F_clip = 2.5, cart = Cart(), belt = Belt(), pots = 6, dt = 1e-3)

The motor switched on with the cart standing 0.3 m from the pots and `L_cord` metres of cord lying in a heap by them.
Returns a time series (t, x, v, rev_s, I, F_belt, T_cord, clip, slipping) and the events.
"""
function drive(; seconds = 40.0, dt = 1e-3, every = 0.1, kw...)
    s = Sim(; kw...); out = NamedTuple[]
    while s.t < seconds
        step!(s, dt)
        if isempty(out) || s.t - out[end].t >= every - 1e-9
            push!(out, (; t = s.t, x = s.cart.x, v = s.cart.v, rev_s = s.st.ω / 2pi, I = s.st.I, F_belt = s.F, T_cord = s.Tc,
                        clip = s.clipped, slipping = s.belt.slipping))
        end
    end
    (; series = out, events = s.events, R_cord = cord_ohm(s.cord.L), F_belt_max = s.Fmax)
end

"Advance the cord over dt: first particle at the pots (held by the clip, or free once it let go), last at the cart."
function cord_step!(r::Rope.Tether, cart::Cart, clipped::Bool, dt, F::Vector{Rope.V})
    n = length(r.x) - 1
    L0 = r.L / n
    h = min(1e-4, 0.3 * L0 / sqrt(r.EA / r.lin_mass))
    ns = max(1, ceil(Int, dt / h)); h = dt / ns
    Tend = 0.0; T1 = 0.0
    for _ in 1:ns
        fill!(F, zero(Rope.V))
        for k in 1:n
            T, u = Rope.tension(r, k)
            F[k] += T * u; F[k+1] -= T * u
            k == n && (Tend = T)
            k == 1 && (T1 = T)
        end
        m = r.lin_mass * L0
        for i in (clipped ? 2 : 1):n
            Fi = F[i] + Rope.V(0.0, 0.0, -m * G)
            Fi += Rope.ground_friction(F[i], r.v[i], m, r.mu_ground, h)
            Fi = Rope.V(Fi[1], Fi[2], 0.0)
            v = Rope.slide(r.v[i], Fi, m, h)
            r.v[i] = Rope.t3(v); r.x[i] = Rope.t3(Rope.v3(r.x[i]) + h * v)
        end
        r.x[n+1] = (cart.x, 0.0, 0.0); r.v[n+1] = (cart.v, 0.0, 0.0)
    end
    Tend, T1
end

end
