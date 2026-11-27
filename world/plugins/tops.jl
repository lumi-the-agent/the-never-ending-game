# Spin a top (s143, project tops). A round wooden tippe top lies on a board by the workshop at (5.6, -13). Jumped in
# as Lumi, stand by it: HOLD 1 to wind the string (the longer, the harder: 40 to 220 rad/s; an 8 cm top), let go and it spins.
# physics/top.jl simulates it (its own mass and inertia from its turned profile, contact at the lowest point of its
# surface, sliding friction) on a thread, and the frame plays back what it solved: a weak spin wobbles and rolls it
# onto its rim, a hard one turns it upside down onto its stem. Nothing is scripted; the flip is friction.
using GeometryBasics, Makie, LinearAlgebra
isdefined(Main, :TOPS) || Core.eval(Main, :(const TOPS = Dict{Symbol,Any}()))
isdefined(Main, :LOCAL_KEYS) || Core.eval(Main, :(const LOCAL_KEYS = Dict{String,Any}()))
isdefined(Main, :LOCAL_CAMS) || Core.eval(Main, :(const LOCAL_CAMS = Dict{String,Any}()))
const NG = NeverendingGame
const TPS = Main.TOPS
Base.include(@__MODULE__, joinpath(@__DIR__, "..", "physics", "top.jl"))

const TP_SPOT = (5.6f0, -13.0f0)
const TP_NEAR = 1.4f0
const TP_WIND = 1.5          # seconds of holding for the hardest spin
const TP_KEY = Makie.Keyboard._1

struct Tops <: System end

# Lumi-sized (s143): at 2 cm it was a few pixels in the follow camera. Scaled to R = 8 cm (1 kg) the same top flips at
# the same omega sqrt(R/g): 150-180 rad/s stands it on its stem after 5-6 s, 90-120 flips it and drops it on its rim.
const TP_R = 0.08
const TP_K = 6.4e4           # contact stiffness for 1 kg (sinks 0.15 mm)

"The tippe top (hollow round body, stem with a ball end), as in movies/top.jl but TP_R big."
function tp_shape()
    zt, rt = tippe_profile(; R = TP_R, cut = 1.6, stem_len = 1.0, stem_r = 0.22)
    rin = [z <= 1.6 * TP_R ? min(x, 0.9 * r) : 0.0 for (z, x, r) in zip(zt, tippe_hollow(zt; R = TP_R, wall = 0.15), rt)]
    return TopShape(zt, rt, rin)
end

"Surface of revolution around the centre of mass, painted in sectors so the spin shows (same as movies/top.jl's top_mesh)."
function tp_mesh(S::TopShape; nphi = 32, cols = (RGBf(0.10, 0.25, 0.65), RGBf(0.93, 0.85, 0.66)))
    V = Point3f[]; C = RGBf[]
    nz = length(S.z)
    for i in 1:nz, j in 0:nphi-1
        phi = 2pi * j / nphi
        push!(V, Point3f(S.r[i] * cos(phi), S.r[i] * sin(phi), S.z[i] - S.zc))
        push!(C, cols[1 + (div(j, 4) % 2)])
    end
    push!(V, Point3f(0, 0, S.z[1] - S.zc)); push!(C, cols[1])
    push!(V, Point3f(0, 0, S.z[end] - S.zc)); push!(C, cols[2])
    idx(i, j) = (i - 1) * nphi + mod(j, nphi) + 1
    F = TriangleFace{Int}[]
    for i in 1:nz-1, j in 0:nphi-1
        push!(F, TriangleFace(idx(i, j), idx(i + 1, j), idx(i + 1, j + 1)))
        push!(F, TriangleFace(idx(i, j), idx(i + 1, j + 1), idx(i, j + 1)))
    end
    b, t = length(V) - 1, length(V)
    for j in 0:nphi-1
        push!(F, TriangleFace(b, idx(1, j + 1), idx(1, j)))
        push!(F, TriangleFace(t, idx(nz, j), idx(nz, j + 1)))
    end
    return V, F, C
end

tp_place(V, F, fr, base) = GeometryBasics.normal_mesh(GeometryBasics.Mesh([Point3f(base .+ fr.pos .+ qrot(fr.q) * v) for v in V], F))

function tp_ensure!(game)
    haskey(TPS, :obs) && get(TPS, :R, 0.0) == TP_R && return
    # built before at another size (a reload): take the old plots away first (plot names are unique in a scene)
    for p in copy(game.stage.scene.plots)
        haskey(p.attributes, :name) && p.attributes[:name][] in (:tops_live_board, :tops_live_top) && delete!(game.stage.scene, p)
    end
    TPS[:R] = TP_R; TPS[:task] = nothing
    w = game.world
    g = NG.ground(w.island, TP_SPOT)
    base = Point3f(g[1], g[2], g[3] + 0.05f0)
    S = tp_shape()
    V, F, C = tp_mesh(S)
    rest = spin_top(S; omega = 0.0, tilt = 0.6, seconds = 1.5, air = 1e-10, k = TP_K, dt = 4e-5)   # lying as it settles by itself
    TPS[:V] = V; TPS[:F] = F; TPS[:base] = base
    TPS[:frames] = rest; TPS[:t0] = w.t - 100.0; TPS[:task] = nothing
    board = GeometryBasics.expand_faceviews(GeometryBasics.normal_mesh(Cylinder(base - Point3f(0, 0, 0.05f0), base, 0.7f0)))
    mesh!(game.stage.scene, board; color = RGBf(0.55, 0.38, 0.22), name = :tops_live_board,
          material = NG.Hikari.Diffuse(color = (0.55, 0.38, 0.22), roughness = 0.4f0))
    TPS[:obs] = Observable(tp_place(V, F, rest[end], base))
    mesh!(game.stage.scene, TPS[:obs]; color = C, name = :tops_live_top,
          material = NG.Hikari.Diffuse(color = (0.8, 0.6, 0.4), roughness = 0.3f0))
    return
end

function NG.step!(::Tops, game, dt)
    game.stage === nothing && return
    me = NG.creature(game.world, "Lumi")
    me === nothing && return
    tp_ensure!(game)
    w = game.world
    t = TPS[:task]
    if t !== nothing && istaskdone(t)
        TPS[:frames] = fetch(t)               # a failed solve throws here: the plugin error shows it
        TPS[:task] = nothing; TPS[:t0] = w.t; TPS[:flipped] = false
    end
    frs = TPS[:frames]
    k = clamp(round(Int, (w.t - TPS[:t0]) / (frs[2].t - frs[1].t)) + 1, 1, length(frs))
    if k != get(TPS, :k, 0)
        TPS[:obs][] = tp_place(TPS[:V], TPS[:F], frs[k], TPS[:base])
        TPS[:k] = k
    end
    if !get(TPS, :flipped, true) && frs[k].tilt > deg2rad(150)
        TPS[:flipped] = true
        NG.say!(w, me, "It stood up on its head!"; duration = 2.0)
        NG.emit!(w, :top_flip; spin = round(TPS[:omega]))
    end
    free = game.minigame === nothing || game.minigame isa NG.JumpIn
    b = TPS[:base]
    near = me.controlled && free && hypot(me.pos[1] - b[1], me.pos[2] - b[2]) < TP_NEAR
    TPS[:near] = near
    Main.LOCAL_KEYS["tops"] = g -> get(TPS, :near, false) ? "hold 1 wind and spin the wooden top" : nothing   # Jump in's key card (greetings.jl)
    # a close look like wirebench's was tried s148 and showed the board's edge without the top: not yet (todo)
    down = TP_KEY in game.keys_down
    if near && down && !get(TPS, :down, false)
        TPS[:wind_from] = w.t
        NG.say!(w, me, "Winding the string..."; duration = 1.2)
    elseif near && !down && get(TPS, :down, false) && TPS[:task] === nothing
        held = clamp(w.t - get(TPS, :wind_from, w.t), 0.0, TP_WIND)
        omega = 40.0 + 180.0 * held / TP_WIND
        TPS[:omega] = omega
        S = tp_shape()          # fresh: a reloaded plugin has a new TopShape type, an old one in TPS fails (s143)
        TPS[:task] = Threads.@spawn spin_top(S; omega, tilt = 0.15 + 0.06 * rand(), seconds = 16.0, air = 1e-10, mu = 0.35, k = TP_K, dt = 4e-5)
        me.action = :wave
        NG.say!(w, me, "Whirr! $(round(Int, omega / 2pi)) turns a second."; duration = 1.6)
        NG.emit!(w, :top_spin; spin = round(omega))
    end
    TPS[:down] = down
    return
end

register!(Tops())
