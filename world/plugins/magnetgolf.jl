# Putting over a hidden magnet stone (s151, idea "Putting over buried magnet stones", project ironsand). A sand tray
# on the north beach at (-3.5, 18.8) with a lodestone buried somewhere under its sand, at a place, depth and pose
# nobody shows you, and a cup at the far end. Jumped in as Lumi at the tray: turn to aim, hold 8 and let go to putt
# (the longer you hold, the harder, up and down again). The iron ball rolls by physics/magnetgolf.jl: the stone's
# field (em.jl) on the ball's induced moment, rolling resistance on sand, rims it bounces off. It bends, speeds up or
# gets caught where the stone is; you putt again from where it lies. In the cup, the stone shows where it was, and a
# new one is buried.
using GeometryBasics, Makie, LinearAlgebra, Random
isdefined(Main, :LOCAL_CAMS) || Core.eval(Main, :(const LOCAL_CAMS = Dict{String,Any}()))
isdefined(Main, :LOCAL_KEYS) || Core.eval(Main, :(const LOCAL_KEYS = Dict{String,Any}()))
isdefined(Main, :MAGNETGOLF) || Core.eval(Main, :(const MAGNETGOLF = Dict{Symbol,Any}()))
const NG = NeverendingGame
const GS = Main.MAGNETGOLF
Base.include(@__MODULE__, joinpath(@__DIR__, "..", "physics", "em.jl"))
Base.include(@__MODULE__, joinpath(@__DIR__, "..", "physics", "ironsand.jl"))
Base.include(@__MODULE__, joinpath(@__DIR__, "..", "physics", "magnetgolf.jl"))

const GF_SPOT = (-3.5, 18.8)
const GF_L = 0.48; const GF_W = 0.26          # tray half length (x) and half width (y), m
const GF_R = 0.015                             # the iron ball's radius
const GF_KEY = Makie.Keyboard._8
const GF_CUP = (0.36, 0.0); const GF_CUPR = 0.025
const GF_START = (-0.38, 0.0)
const GF_NEAR = 0.75                           # from the tray's start end (the iron sand patch is 1.5 m east)
const GF_SAND = Makie.Keyboard._9
const GF_SN = 1200                             # iron sand grains over the tray's middle (0.5 m square)
const GF_SUB = 20
const GF_HIDE = Point3f(0, 0, -50)
const GF_DT = 4e-3

struct MagnetGolfToy <: System end

gfz(w, x, y) = Float64(NG.ground(w.island, (Float32(x), Float32(y)))[3])

function gf_bury!()
    rng = Random.MersenneTwister(round(Int, time() * 1000) % 100000)
    x = -0.12 + 0.36rand(rng); y = 0.16 * (2rand(rng) - 1); depth = 0.02rand(rng)
    tilt = rand(rng) < 0.4 ? pi / 2 : 0.0; az = 2pi * rand(rng)
    GS[:stone] = [MagnetGolf.Stone(; x, y, depth, tilt, az, sides = 16, quad = 3)]
    GS[:truth] = (; x, y, depth, tilt)
    GS[:ball] = (GF_START[1], GF_START[2], 0.0, 0.0); GS[:rest] = true; GS[:putts] = 0
    GS[:shown] = nothing
    GS[:sand] = nothing; GS[:sprinkled] = false; GS[:tap] = 0; GS[:flat] = nothing
    st = GS[:stone]
    GS[:task] = Threads.@spawn IronSand.Sand(st; N = GF_SN, w = 0.5, seed = rand(rng, 1:10^6))
    haskey(GS, :trail) && (empty!(GS[:trail]); Makie.update!(GS[:trailplot]; arg1 = [Point3f(0, 0, -50)]))
    return
end

function gf_ensure!(game)
    haskey(GS, :plots) && haskey(GS, :stone) && return
    sc = game.stage.scene
    for p in copy(sc.plots)
        haskey(p.attributes, :name) && startswith(string(p.attributes[:name][]), "magnetgolf_") && delete!(sc, p)
    end
    w = game.world
    ox, oy = GF_SPOT
    # the tray stands level on its highest corner
    zt = maximum(gfz(w, ox + sx * GF_L, oy + sy * GF_W) for sx in (-1, 1), sy in (-1, 1)) + 0.05
    GS[:zt] = zt
    L = Float32(GF_L); Wd = Float32(GF_W); th = 0.025f0; z = Float32(zt); dep = 0.16f0
    wood = NG.Hikari.Diffuse(color = (0.45, 0.28, 0.15), roughness = 0.8f0)
    rims = [Rect3f(Point3f(ox - L - th, oy - Wd - th, z - dep), Vec3f(2L + 2th, th, dep + 0.015f0)),
            Rect3f(Point3f(ox - L - th, oy + Wd, z - dep), Vec3f(2L + 2th, th, dep + 0.015f0)),
            Rect3f(Point3f(ox - L - th, oy - Wd, z - dep), Vec3f(th, 2Wd, dep + 0.015f0)),
            Rect3f(Point3f(ox + L, oy - Wd, z - dep), Vec3f(th, 2Wd, dep + 0.015f0))]
    plots = Any[]
    for (k, r) in enumerate(rims)
        push!(plots, mesh!(sc, GeometryBasics.normal_mesh(r); color = RGBf(0.45, 0.28, 0.15), material = wood, name = Symbol("magnetgolf_rim$k")))
    end
    push!(plots, mesh!(sc, GeometryBasics.normal_mesh(Rect3f(Point3f(ox - L, oy - Wd, z - dep), Vec3f(2L, 2Wd, dep))); color = RGBf(0.86, 0.76, 0.56),
                       material = NG.Hikari.Diffuse(color = (0.86, 0.76, 0.56), roughness = 1f0), name = :magnetgolf_sand))
    cx, cy = ox + GF_CUP[1], oy + GF_CUP[2]
    push!(plots, mesh!(sc, GeometryBasics.normal_mesh(Cylinder(Point3f(cx, cy, z - 0.01f0), Point3f(cx, cy, z + 0.001f0), Float32(GF_CUPR))); color = RGBf(0.02, 0.02, 0.02),
                       material = NG.Hikari.Diffuse(color = (0.02, 0.02, 0.02), roughness = 1f0), name = :magnetgolf_cup))
    GS[:stoneplot] = mesh!(sc, GeometryBasics.normal_mesh(Cylinder(Point3f(0, 0, -0.003f0), Point3f(0, 0, 0.006f0), 0.05f0)); color = RGBf(0.2, 0.19, 0.18), visible = false,
                           material = NG.Hikari.Diffuse(color = (0.2, 0.19, 0.18), roughness = 0.9f0), name = :magnetgolf_stone)
    iron = NG.Hikari.Conductor(ior = (2.9f0, 2.9f0, 2.9f0), extinction = (3.0f0, 3.0f0, 3.0f0), roughness = 0.25f0)
    ball = GeometryBasics.normal_mesh(GeometryBasics.Tessellation(Sphere(Point3f(0), Float32(GF_R)), 24))
    GS[:ballplot] = meshscatter!(sc, [Point3f(ox + GF_START[1], oy, z + GF_R)]; marker = ball, markersize = 1f0,
                                 color = RGBf(0.35, 0.35, 0.37), material = iron, name = :magnetgolf_ball)
    # the groove the last putt pressed into the sand: you read the bend from it
    dent = GeometryBasics.normal_mesh(Cylinder(Point3f(0, 0, 0), Point3f(0, 0, 0.0015f0), 0.006f0))
    GS[:trailplot] = meshscatter!(sc, [Point3f(0, 0, -50)]; marker = dent, markersize = 1f0, color = RGBf(0.66, 0.56, 0.38),
                                  material = NG.Hikari.Diffuse(color = (0.66, 0.56, 0.38), roughness = 1f0), name = :magnetgolf_trail)
    GS[:trail] = Point3f[]
    a = Float32(IronSand.Grain().a)
    gm = GeometryBasics.normal_mesh(Cylinder(Point3f(0, 0, -2.6a), Point3f(0, 0, 2.6a), a))
    GS[:grains] = meshscatter!(sc, fill(GF_HIDE, GF_SN); marker = gm, markersize = 1f0, rotation = fill(Makie.Quaternionf(0, 0, 0, 1), GF_SN),
                               color = RGBf(0.07, 0.07, 0.08), name = :magnetgolf_grains,
                               material = NG.Hikari.Diffuse(color = (0.07, 0.07, 0.08), roughness = 0.45f0))
    GS[:plots] = plots
    Main.LOCAL_KEYS["magnetgolf"] = g -> get(GS, :near, false) ? (get(GS, :rest, true) ? (get(GS, :sprinkled, false) ? "turn to aim, hold 8 to putt   9 tap the sand" : "turn to aim, hold 8 to putt   9 sprinkle iron sand") : nothing) : nothing
    # the tray is a metre long and Lumi is a metre tall: look from the sea side, down on the tray, Lumi at its end
    Main.LOCAL_CAMS["magnetgolf"] = g -> (get(GS, :near, false) && g.minigame isa NG.JumpIn) ?
        (Point3f(ox - 0.05, oy + 1.05, GS[:zt] + 1.0), Point3f(ox + 0.02, oy - 0.05, GS[:zt])) : nothing
    gf_bury!()
    return
end

function zto(d)
    x, y, z, w = -d[2], d[1], 0.0, 1.0 + d[3]
    n = sqrt(x^2 + y^2 + z^2 + w^2)
    Makie.Quaternionf(Float32(x / n), Float32(y / n), Float32(z / n), Float32(w / n))
end

"the iron sand on the tray: hidden until sprinkled, flat as it lands, standing into the field after taps"
function gf_drawsand!()
    S = GS[:sand]; pg = GS[:grains]
    if S === nothing || !GS[:sprinkled]
        get(GS, :sandshown, true) && Makie.update!(pg; arg1 = fill(GF_HIDE, GF_SN))
        GS[:sandshown] = false
        return
    end
    # redraw only while something changes (a tap, the sprinkle)
    (GS[:tap] == 0 && get(GS, :sandshown, false) && get(GS, :drawn_flat, nothing) === GS[:flat]) && return
    a = S.g.a; k = GS[:tap]
    hop = k > 0 ? 0.004 * 4 * (k / GF_SUB) * (1 - k / GF_SUB) : 0.0
    dirs = GS[:flat] === nothing ? S.dir : GS[:flat]
    ox, oy = GF_SPOT
    pos = Vector{Point3f}(undef, GF_SN); rot = Vector{Makie.Quaternionf}(undef, GF_SN)
    for i in 1:GF_SN
        p = S.pos[i]; d = dirs[i]
        inside = abs(p[1]) < GF_L - 0.01 && abs(p[2]) < GF_W - 0.01
        pos[i] = inside ? Point3f(ox + p[1], oy + p[2], GS[:zt] + a + 2.6a * d[3] + hop) : GF_HIDE
        rot[i] = zto(d)
    end
    Makie.update!(pg; arg1 = pos, rotation = rot)
    GS[:sandshown] = true; GS[:drawn_flat] = GS[:flat]
end

function NG.step!(::MagnetGolfToy, game, dt)
    game.stage === nothing && return
    me = NG.creature(game.world, "Lumi")
    me === nothing && return
    gf_ensure!(game)
    w = game.world
    t0 = time_ns()
    ox, oy = GF_SPOT
    free = game.minigame === nothing || game.minigame isa NG.JumpIn
    near = me.controlled && free && hypot(me.pos[1] - ox - GF_START[1], me.pos[2] - oy - GF_START[2]) < GF_NEAR
    GS[:near] = near
    down = GF_KEY in game.keys_down
    if near && GS[:rest] && GS[:shown] === nothing
        if down && !get(GS, :down, false)
            GS[:charge] = time()
        elseif !down && get(GS, :down, false) && haskey(GS, :charge)
            # strength: up and down over 1.6 s of holding, 0.25 .. 1.0 m/s
            h = mod(time() - GS[:charge], 1.6) / 0.8; h = h > 1 ? 2 - h : h
            v = 0.25 + 0.75h
            x, y = GS[:ball]
            GS[:ball] = (x, y, v * cos(me.yaw), v * sin(me.yaw)); GS[:rest] = false
            GS[:putts] += 1
            empty!(GS[:trail])
            NG.emit!(w, :magnetgolf_putt)
        end
    end
    GS[:down] = down
    if !GS[:rest]
        x, y, vx, vy = GS[:ball]
        for _ in 1:max(1, round(Int, min(dt, 0.05) / GF_DT))
            x, y, vx, vy, rest = MagnetGolf.rollstep(GS[:stone], x, y, vx, vy; r = GF_R, dt = GF_DT)
            # the rims: the ball bounces off them, losing half its speed across
            lim = (GF_L - GF_R, GF_W - GF_R)
            abs(x) > lim[1] && (x = sign(x) * lim[1]; vx = -0.5vx)
            abs(y) > lim[2] && (y = sign(y) * lim[2]; vy = -0.5vy)
            if hypot(x - GF_CUP[1], y - GF_CUP[2]) < GF_CUPR && hypot(vx, vy) < 0.6
                x, y, vx, vy = GF_CUP[1], GF_CUP[2], 0.0, 0.0
                GS[:shown] = time(); rest = true
                tr = GS[:truth]
                sp = GS[:stoneplot]
                Makie.translate!(sp, Vec3f(ox + tr.x, oy + tr.y, GS[:zt]))
                sp.visible[] = true
                NG.say!(w, me, GS[:putts] == 1 ? "In, first go! The stone was right there." : "In! $(GS[:putts]) putts. There was the stone."; duration = 3.0)
                NG.feel!(w, me, :proud)
                NG.emit!(w, :magnetgolf_cup)
            end
            tr = GS[:trail]
            p = Point3f(ox + x, oy + y, GS[:zt])
            (isempty(tr) || norm(p - tr[end]) > 0.008f0) && push!(tr, p)
            rest && (GS[:rest] = true; break)
        end
        GS[:ball] = (x, y, vx, vy)
        Makie.update!(GS[:trailplot]; arg1 = isempty(GS[:trail]) ? [Point3f(0, 0, -50)] : copy(GS[:trail]))
    end
    if GS[:shown] !== nothing && time() - GS[:shown] > 4.0
        GS[:stoneplot].visible[] = false
        gf_bury!()
    end
    if GS[:sand] === nothing && istaskdone(GS[:task])
        GS[:sand] = fetch(GS[:task])                  # a failed build throws here, on purpose
    end
    S = GS[:sand]
    sd = GF_SAND in game.keys_down
    if near && sd && !get(GS, :sdown, false) && S !== nothing && GS[:tap] == 0 && GS[:shown] === nothing
        if !GS[:sprinkled]
            GS[:sprinkled] = true
            GS[:flat] = [(cos(t), sin(t), 0.0) for t in 2pi .* rand(GF_SN)]
            NG.emit!(w, :magnetgolf_sprinkle)
        else
            GS[:tap] = 1
        end
    end
    GS[:sdown] = sd
    if S !== nothing && GS[:tap] > 0
        IronSand.substep!(S); GS[:tap] += 1
        GS[:tap] > GF_SUB && (IronSand.orient!(S); GS[:flat] = nothing; GS[:tap] = 0)
    end
    gf_drawsand!()
    x, y = GS[:ball]
    inz = GS[:shown] !== nothing ? -0.02 : 0.0           # in the cup it sits down in the hole
    Makie.update!(GS[:ballplot]; arg1 = [Point3f(ox + x, oy + y, GS[:zt] + GF_R + inz)])
    GS[:ms] = (time_ns() - t0) / 1e6
    return
end

function NG.stop!(::MagnetGolfToy, game)
    game.stage === nothing && return
    for p in copy(game.stage.scene.plots)
        haskey(p.attributes, :name) && startswith(string(p.attributes[:name][]), "magnetgolf_") && delete!(game.stage.scene, p)
    end
    delete!(GS, :plots)
end

register!(MagnetGolfToy())
