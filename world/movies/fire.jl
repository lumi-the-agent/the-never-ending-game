# Fire on the meadow (s152, project fire, physics/fire.jl): a campfire of four logs in a 2 m/s wind, three stakes
# downwind and three upwind. Nothing is staged but the start: the fire model decides which stakes heat, catch, char and
# break. 20 minutes of fire in 12 s (each film frame ~4 s of fire time).
#   submit_job(:clip; path, script = "movies/fire.jl", call = "fire_clip", kwargs = Dict(...))
using NeverendingGame, GeometryBasics, Makie, LinearAlgebra
const NG = NeverendingGame
Base.include(@__MODULE__, joinpath(@__DIR__, "..", "physics", "fire.jl"))   # the worker's script module has no `include`

const FIRE_SPOT = (-3.0f0, -16.0f0)      # s152: 1.4 m clear of every prop AND plotted thing round the fire, the camera and Lumi (the clearest on the island; -9.5,-0.5 had a mushroom in front, -7,6 a house round the camera)

"The scene's fuel bodies, in metres from the spot (ground at z = 0)."
function fire_bodies()
    bs = FireBody[]
    for k in 1:4                          # four logs leaning in a little pile
        a = k * pi / 2 + pi / 4
        push!(bs, fire_body(k, :wood, (0.12cos(a), 0.12sin(a), 0.06), (0.4, 0.09, 0.09); moisture = 0.08, burning = true, T = 700))
    end
    for (i, y) in enumerate((-0.35, 0.0, 0.35))
        push!(bs, fire_body(10 + i, :wood, (0.45, y, 0.5), (0.07, 0.07, 1.0); load = 0.3))    # downwind
        push!(bs, fire_body(20 + i, :wood, (-0.45, y, 0.5), (0.07, 0.07, 1.0); load = 0.3))   # upwind
    end
    return bs
end

"Run the fire and keep a snapshot every `every` seconds: each body's char, burning, broken, fuel share, and the flames."
function fire_run(; minutes = 20, dt = 0.5, every = 4.0, wind = (2f0, 0f0))
    bs = fire_bodies()
    fuel0 = Dict(b.id => b.fuel for b in bs)
    snaps = Any[]
    events = Tuple{Int,Symbol,Float32}[]
    n = round(Int, minutes * 60 / dt); k = max(1, round(Int, every / dt))
    for i in 0:n
        i > 0 && append!(events, fire_step!(bs, dt, i * dt; wind))
        i % k == 0 || continue
        push!(snaps, (t = i * dt,
                      bodies = Dict(b.id => (char = b.char, burning = b.burning, broken = b.broken, broke_at = b.broke_at,
                                             left = b.fuel / fuel0[b.id], T = b.T, pos = b.pos, size = b.size) for b in bs),
                      flames = merged_flames(bs, wind)))
    end
    return bs, snaps, events
end

function flame_mesh(flames, t, origin, byid)
    ms = GeometryBasics.Mesh[]
    for (c, L, Q, ids) in flames
        L < 0.03f0 && continue
        g = [byid[i] for i in ids]
        w = ones(Float32, length(g)); W = Float32(length(g))   # the snapshot keeps ids only: the plain centroid
        bx = sum(w[i] * g[i].pos[1] for i in eachindex(g)) / W
        by = sum(w[i] * g[i].pos[2] for i in eachindex(g)) / W
        bz = minimum(b -> b.pos[3] + 0.5f0 * b.size[3], g)   # from the lowest fuel top: the log pile, not a stake top
        base = Point3f(origin[1] + bx, origin[2] + by, origin[3] + bz)
        axis = Vec3f(origin[1] + c[1], origin[2] + c[2], origin[3] + c[3]) - base     # base -> centre: half the flame
        D = clamp(0.1f0 * L, 0.03f0, 0.09f0)
        sp = clamp(0.5f0 * maximum(b -> max(b.size[1], b.size[2]), g), 0.05f0, 0.4f0)   # tongues spread over the fuel
        for j in 1:7                      # tongues, each flickering in height
            a = 2f0 * Float32(pi) * j / 7 + 0.7f0 * t
            off = j == 1 ? Vec3f(0) : Vec3f(0.6f0 * sp * cos(a), 0.4f0 * sp * sin(a), 0)
            h = 1f0 + 0.2f0 * sin(9f0 * t + 2.1f0 * j) + 0.1f0 * sin(23f0 * t + j)
            b0 = base + off - Vec3f(0, 0, 0.05f0)
            push!(ms, GeometryBasics.normal_mesh(Cylinder(b0, b0 + (j == 1 ? 1.8f0 : 1.4f0 * h) * axis, (j == 1 ? 1f0 : 0.6f0) * D)))
        end
    end
    isempty(ms) && return GeometryBasics.normal_mesh(Cylinder(Point3f(origin[1], origin[2], origin[3] - 2), Point3f(origin[1], origin[2], origin[3] - 1.9f0), 0.01f0))
    return GeometryBasics.expand_faceviews(merge(ms))
end

const WOOD = RGBf(0.55, 0.36, 0.2)
const CHAR = RGBf(0.07, 0.05, 0.04)
char_color(char, left) = (s = clamp(char / 0.008f0 + (1 - left), 0, 1); RGBf((1 - s) * WOOD.r + s * CHAR.r, (1 - s) * WOOD.g + s * CHAR.g, (1 - s) * WOOD.b + s * CHAR.b))

function fire_parts(; minutes = 20, seconds = 12.0)
    _, snaps, events = fire_run(; minutes)
    bs = fire_bodies()                    # the bodies as they stood at the start: the visuals move them by the snapshots
    S = Dict{Symbol,Any}(:bodies => bs, :snaps => snaps, :events => events)
    setup = function (gm)
        for p in gm.stage.scene.plots
            haskey(p.attributes, :name) && p.attributes[:name][] in (:rain, :rainrings, :raincloud, :paperme, :paperme_card, :dayfall_tiles, :jelly_coat, :autumn_fall) && (p.visible[] = false)
        end
        isdefined(Main, :SHOWERS) && (Main.SHOWERS[:off] = true)
        w = gm.world
        g = NG.ground(w.island, FIRE_SPOT)
        S[:o] = Point3f(g[1], g[2], g[3])
        for c in w.creatures
            hypot(c.pos[1] - FIRE_SPOT[1], c.pos[2] - FIRE_SPOT[2]) < 7 && c.name != "Lumi" && (c.pos = NG.ground(w.island, (FIRE_SPOT[1] + 14f0, FIRE_SPOT[2] - 9f0)); c.goal = NG.Goal())
            c.name == "Lumi" && (c.controlled = true)
        end
        o = S[:o]
        S[:plots] = Dict{Int,Any}()
        for b in bs
            m = GeometryBasics.expand_faceviews(GeometryBasics.normal_mesh(Rect3f(Vec3f(-b.size[1] / 2, -b.size[2] / 2, -b.size[3] / 2), Vec3f(b.size...))))
            p = mesh!(gm.stage.scene, m; color = WOOD, material = NG.Hikari.Diffuse(color = (0.55, 0.36, 0.2), roughness = 0.9f0), name = Symbol("fire_body_", b.id))
            S[:plots][b.id] = p
        end
        S[:flame] = mesh!(gm.stage.scene, flame_mesh(snaps[1].flames, 0f0, o, snaps[1].bodies); color = RGBf(1.0, 0.55, 0.15),
                          material = NG.Hikari.Emission(color = (1.0, 0.52, 0.14), strength = 6.0), name = :fire_flame)
    end
    place! = function (gm, t)
        o = S[:o]
        k = clamp(1 + round(Int, t / seconds * (length(snaps) - 1)), 1, length(snaps))
        sn = snaps[k]
        for b in bs
            st = sn.bodies[b.id]
            p = S[:plots][b.id]
            # logs: across the pile, each turned to its own angle; stakes upright, tipping downwind once broken
            if b.id <= 4
                a = b.id * Float32(pi) / 2 + Float32(pi) / 4
                Makie.rotate!(p, Makie.qrotation(Vec3f(0, 0, 1), a))
                sc = max(st.left, 0.15f0)
                Makie.scale!(p, 1f0, sc, sc)
                Makie.translate!(p, o[1] + b.pos[1], o[2] + b.pos[2], o[3] + b.pos[3] * sc)
            else
                fall = st.broken ? clamp((sn.t - st.broke_at) / 25f0, 0f0, 1f0) : 0f0   # ~25 s of fire time = ~0.25 s of film
                ang = fall * 1.45f0
                Makie.rotate!(p, Makie.qrotation(Vec3f(0, 1, 0), ang))
                h = b.size[3] / 2
                # pivot at the foot: the centre swings round the base
                Makie.translate!(p, o[1] + b.pos[1] + h * sin(ang), o[2] + b.pos[2], o[3] + h * cos(ang))
            end
            p.color[] = char_color(st.char, st.left)
        end
        S[:flame][1][] = flame_mesh(sn.flames, Float32(t), o, sn.bodies)
        return sn
    end
    shot = function (gm, rig, t)
        for p in gm.stage.scene.plots
            haskey(p.attributes, :name) && p.attributes[:name][] in (:autumn_fall, :autumn_pile) && (p.visible[] = false)
        end
        o = S[:o]
        place!(gm, t)
        me = NG.creature(gm.world, "Lumi")
        if me !== nothing      # Lumi watches from the upwind side, out of the smoke
            me.pos = NG.ground(gm.world.island, (o[1] - 1.25f0, o[2] + 0.9f0)); me.yaw = Float32(atan(-0.9, 1.25))
        end
        rig.mode = :fixed
        rig.eye = Point3f(o[1] + 0.2f0, o[2] - 2.9f0, o[3] + 1.0f0)
        rig.target = Point3f(o[1] - 0.05f0, o[2] + 0.2f0, o[3] + 0.45f0)
        return nothing
    end
    setup, shot, S
end

function fire_clip(path; rasterize = false, samples = 20, width = 960, height = 540, fps = 24, seconds = 12.0, hour = 18.3, minutes = 20)
    setup, shot, S = fire_parts(; minutes, seconds)
    res = NG.game_clip(path; size = (width, height), seconds, fps, samples, hour, warmup = 0.3, rasterize,
                       rig = NG.CameraRig(; mode = :fixed), setup, shot, fade = 0)
    ev = [(id, string(e), round(t / 60; digits = 1)) for (id, e, t) in S[:events]]
    return merge(res, (; path, events = string(ev)))
end
