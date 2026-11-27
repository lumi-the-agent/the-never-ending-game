# A top that floats over a ring of lodestone (s148, project levitron, todo #707). By the tops board a ferrite ring
# lies on a slate, a little magnet top spinning on a glass plate above it. Jumped in as Lumi, stand by it:
# 7 adds a copper washer (0.25 g), 8 files one off, HOLD 6 to spin (the longer, the faster: 10 to 40 turns a second)
# and let go: the plate sinks away. physics/levitron.jl moves the top (rigid body, gravity, the ring's field force and
# torque, nothing else): it floats only with 5.5 to 6 g of washers and a fast spin. Too heavy and it never leaves the
# plate; too light or too slow and it slides off sideways and falls. The camera comes close while Lumi stands there.
using GeometryBasics, Makie, LinearAlgebra
isdefined(Main, :FLOATTOP) || Core.eval(Main, :(const FLOATTOP = Dict{Symbol,Any}()))
isdefined(Main, :LOCAL_KEYS) || Core.eval(Main, :(const LOCAL_KEYS = Dict{String,Any}()))
isdefined(Main, :LOCAL_CAMS) || Core.eval(Main, :(const LOCAL_CAMS = Dict{String,Any}()))
const NG = NeverendingGame
const FT = Main.FLOATTOP
Base.include(@__MODULE__, joinpath(@__DIR__, "..", "physics", "levitron.jl"))

const FT_SPOT = (6.0f0, -12.1f0)      # s148: (6.5, -12.3) put the slate into the wire bench board (6.9, -12.6)
const FT_NEAR = 1.3f0
const FT_SPIN = Makie.Keyboard._6
const FT_ADD = Makie.Keyboard._7
const FT_FILE = Makie.Keyboard._8
const FT_WIND = 1.5
const FT_SECS = 15.0

struct FloatTop <: System end

"Closed annulus (outer Ro, inner Ri, z0..z1) with per-vertex colours from `col(phi, k)`."
function ft_annulus(Ro, Ri, z0, z1; n = 48, col = (phi, k) -> RGBf(0.12, 0.11, 0.12))
    V = Point3f[]; C = RGBf[]; F = TriangleFace{Int}[]
    for (k, (r, z)) in enumerate(((Ro, z0), (Ro, z1), (Ri, z1), (Ri, z0))), j in 0:n-1
        phi = 2pi * j / n
        push!(V, Point3f(r * cos(phi), r * sin(phi), z)); push!(C, col(phi, k))
    end
    id(k, j) = (k - 1) * n + mod(j, n) + 1
    for k in 1:4, j in 0:n-1
        k2 = k % 4 + 1
        push!(F, TriangleFace(id(k, j), id(k, j + 1), id(k2, j + 1))); push!(F, TriangleFace(id(k, j), id(k2, j + 1), id(k2, j)))
    end
    GeometryBasics.normal_mesh(GeometryBasics.Mesh(V, F)), C
end

function ft_quat(R)
    t = R[1, 1] + R[2, 2] + R[3, 3]
    if t > 0
        s = sqrt(t + 1) * 2
        Quaternionf((R[3, 2] - R[2, 3]) / s, (R[1, 3] - R[3, 1]) / s, (R[2, 1] - R[1, 2]) / s, s / 4)
    elseif R[1, 1] > R[2, 2] && R[1, 1] > R[3, 3]
        s = sqrt(1 + R[1, 1] - R[2, 2] - R[3, 3]) * 2
        Quaternionf(s / 4, (R[1, 2] + R[2, 1]) / s, (R[1, 3] + R[3, 1]) / s, (R[3, 2] - R[2, 3]) / s)
    elseif R[2, 2] > R[3, 3]
        s = sqrt(1 + R[2, 2] - R[1, 1] - R[3, 3]) * 2
        Quaternionf((R[1, 2] + R[2, 1]) / s, s / 4, (R[2, 3] + R[3, 2]) / s, (R[1, 3] - R[3, 1]) / s)
    else
        s = sqrt(1 + R[3, 3] - R[1, 1] - R[2, 2]) * 2
        Quaternionf((R[1, 3] + R[3, 1]) / s, (R[2, 3] + R[3, 2]) / s, s / 4, (R[2, 1] - R[1, 2]) / s)
    end
end

const FT_NAMES = (:floattop_slate, :floattop_ring, :floattop_disc, :floattop_washers, :floattop_spindle, :floattop_plate)

function ft_ensure!(game)
    haskey(FT, :top) && return
    sc = game.stage.scene
    for p in copy(sc.plots)
        haskey(p.attributes, :name) && p.attributes[:name][] in FT_NAMES && delete!(sc, p)
    end
    w = game.world
    g = NG.ground(w.island, FT_SPOT)
    P = Point3f(g[1], g[2], g[3] + 0.04f0)
    FT[:P] = P; FT[:zr] = P[3] + 0.025f0
    slate = GeometryBasics.normal_mesh(Cylinder(P - Point3f(0, 0, 0.04f0), P, 0.22f0))
    mesh!(sc, slate; color = RGBf(0.30, 0.32, 0.34), name = :floattop_slate,
          material = NG.Hikari.Diffuse(color = (0.30, 0.32, 0.34), roughness = 0.6f0))
    rm, _ = ft_annulus(0.075, 0.025, -0.025, 0.0)
    r = mesh!(sc, rm; color = RGBf(0.12, 0.11, 0.12), name = :floattop_ring,
              material = NG.Hikari.Diffuse(color = (0.12, 0.11, 0.12), roughness = 0.45f0))
    translate!(r, Vec3f(P[1], P[2], FT[:zr]))
    dm, dc = ft_annulus(0.015, 0.003, -0.003, 0.003; col = (phi, k) -> k == 2 && iseven(floor(Int, phi / (pi / 3))) ? RGBf(0.80, 0.15, 0.10) : RGBf(0.93, 0.88, 0.75))
    sp = GeometryBasics.normal_mesh(Cylinder(Point3f(0, 0, -0.012), Point3f(0, 0, 0.022), 0.003f0))
    FT[:washers] = 0.00575
    FT[:top] = [mesh!(sc, dm; color = dc, name = :floattop_disc, material = NG.Hikari.Diffuse(color = (0.9, 0.9, 0.9), roughness = 0.5f0)),
                mesh!(sc, ft_washer_mesh(FT[:washers]); color = RGBf(0.85, 0.45, 0.25), name = :floattop_washers,
                      material = NG.Hikari.Copper(roughness = 0.2f0)),
                mesh!(sc, sp; color = RGBf(0.7, 0.5, 0.3), name = :floattop_spindle, material = NG.Hikari.Diffuse(color = (0.7, 0.5, 0.3), roughness = 0.4f0))]
    pm = GeometryBasics.normal_mesh(Cylinder(Point3f(0, 0, -0.003), Point3f(0, 0, 0), 0.05f0))
    FT[:plate] = mesh!(sc, pm; color = RGBAf(0.9, 0.95, 1.0, 0.3), name = :floattop_plate, material = NG.Hikari.Glass())
    FT[:run] = nothing; FT[:task] = nothing; FT[:t0] = w.t; FT[:spin] = 0.0; FT[:phi] = 0.0
    R = Levitron.ring(); t = Levitron.top(; washers = FT[:washers])
    FT[:rest] = Levitron.hover_height(R, t)[1] - 0.012      # the plate's height: where the field balances the top
    # Jump in's key card shows this while Lumi stands here (greetings.jl LOCAL_KEYS)
    Main.LOCAL_KEYS["floattop"] = g -> get(FT, :near, false) ? "hold 6 spin the magnet top   7 washer on   8 file one off   ($(round(1000FT[:washers]; digits = 2)) g)" : nothing
    return
end

"Copper washers stacked on the spindle: their height from their mass (copper 8960 kg/m^3, 6 mm / 3 mm rings)."
ft_washer_mesh(m) = ft_annulus(0.006, 0.0031, 0.003, 0.003 + m / (8960 * pi * (0.006^2 - 0.0031^2)))[1]

# In Jump in the camera comes close while Lumi stands by the ring (a 3 cm top is a few pixels from the follow
# camera; scaling the top up instead would break the balance: magnetic push ~ size^2, weight ~ size^3).
# greetings.jl's Jump in camera asks LOCAL_CAMS first.
function ft_view(game)
    get(FT, :near, false) && game.minigame isa NG.JumpIn || return nothing
    P = FT[:P]; zr = FT[:zr]
    (Point3f(P[1] + 0.06f0, P[2] - 0.42f0, zr + 0.2f0), Point3f(P[1], P[2], zr + 0.05f0))
end

function ft_place!(x, Rm, zp)
    P = FT[:P]; zr = FT[:zr]
    q = ft_quat(Rm); o = Vec3f(P[1] + x[1], P[2] + x[2], zr + x[3])
    for p in FT[:top]
        Makie.rotate!(p, q); translate!(p, o)
    end
    translate!(FT[:plate], Vec3f(P[1], P[2], zr + zp))
end

function NG.step!(::FloatTop, game, dt)
    game.stage === nothing && return
    me = NG.creature(game.world, "Lumi")
    me === nothing && return
    ft_ensure!(game)
    w = game.world
    t = FT[:task]
    if t !== nothing && istaskdone(t)
        FT[:run] = fetch(t)                       # a failed solve throws here: the plugin error shows it
        FT[:task] = nothing; FT[:t0] = w.t; FT[:said] = false
    end
    run = FT[:run]
    if run === nothing                            # spinning down on the plate (or still)
        FT[:spin] = max(0.0, FT[:spin] - 0.5 * dt)
        FT[:phi] += 2pi * FT[:spin] * dt
        c, s = cos(FT[:phi]), sin(FT[:phi])
        ft_place!([0.0, 0.0, FT[:rest] + 0.012], [c -s 0; s c 0; 0 0 1], FT[:rest])
    else
        frs = run.frames
        k = clamp(round(Int, (w.t - FT[:t0]) * 24) + 1, 1, length(frs))
        tt, x, Rm, zp, phi = frs[k]
        if tt < 0.8
            c, s = cos(phi), sin(phi); Rm = Rm * [c -s 0; s c 0; 0 0 1]
        end
        fell = !isnan(run.fell) && tt >= run.fell
        if fell                                   # it slid off the field: it lies on the slate beside the ring
            a = atan(x[2], x[1])
            x = [0.11 * cos(a), 0.11 * sin(a), -0.022]; Rm = [cos(a) 0 sin(a); sin(a) 0 -cos(a); 0 1 0]
        end
        ft_place!(x, Rm, zp)
        if !get(FT, :said, true) && (fell || k == length(frs))
            FT[:said] = true
            secs = round(fell ? run.fell - 0.8 : tt - 0.8; digits = 1)
            NG.say!(w, me, fell ? "It floated $(secs) s, then slid off." : "It's still floating! $(secs) s and counting."; duration = 2.5)
            NG.emit!(w, :float_top; seconds = secs, washers_g = round(1000FT[:washers]; digits = 2))
        end
        if k == length(frs) && !fell             # the run ended in the air: keep it there, spinning, until a new spin
            nothing
        end
    end
    free = game.minigame === nothing || game.minigame isa NG.JumpIn
    P = FT[:P]
    near = me.controlled && free && hypot(me.pos[1] - P[1], me.pos[2] - P[2]) < FT_NEAR
    FT[:near] = near
    Main.LOCAL_CAMS["floattop"] = ft_view
    keys = game.keys_down
    for (name, key, dm) in ((:add_down, FT_ADD, 0.00025), (:file_down, FT_FILE, -0.00025))
        down = key in keys
        if near && down && !get(FT, name, false) && FT[:task] === nothing
            FT[:washers] = clamp(FT[:washers] + dm, 0.004, 0.0075)
            Makie.update!(FT[:top][2]; arg1 = ft_washer_mesh(FT[:washers]))
            NG.say!(w, me, "$(round(1000FT[:washers]; digits = 2)) g of copper on it."; duration = 1.5)
        end
        FT[name] = down
    end
    down = FT_SPIN in keys
    if near && down && !get(FT, :down, false)
        FT[:wind_from] = w.t; FT[:run] = nothing
        NG.say!(w, me, "Spinning it up..."; duration = 1.2)
    elseif near && !down && get(FT, :down, false) && FT[:task] === nothing
        held = clamp(w.t - get(FT, :wind_from, w.t), 0.0, FT_WIND)
        spin = 10.0 + 30.0 * held / FT_WIND
        FT[:spin] = spin
        R = Levitron.ring(); tp = Levitron.top(; washers = FT[:washers])
        if Levitron.hover_height(R, tp) === nothing
            NG.say!(w, me, "Too heavy: it won't lift off the plate."; duration = 2.0)
        else
            wsh = FT[:washers]
            FT[:task] = Threads.@spawn Levitron.launch(; washers = wsh, spin, secs = FT_SECS, hold = 0.8)
            me.action = :wave
            NG.say!(w, me, "$(round(Int, spin)) turns a second. Plate down!"; duration = 1.6)
        end
    end
    FT[:down] = down
    return
end

function NG.stop!(::FloatTop, game)
    delete!(Main.LOCAL_KEYS, "floattop")
    delete!(Main.LOCAL_CAMS, "floattop")
    game.stage === nothing && return
    for p in copy(game.stage.scene.plots)
        haskey(p.attributes, :name) && p.attributes[:name][] in FT_NAMES && delete!(game.stage.scene, p)
    end
    delete!(FT, :top)
end

register!(FloatTop())
