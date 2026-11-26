# The sea freezes into glass (s126). One cold morning the sea round the island is clear hard ice: fish hang frozen
# mid-swim under it, and the friends nearest the shore slide out onto it. Nothing is keyframed: on the ice a body
# keeps its speed (friction almost nil), a skating push now and then, and bodies that meet bounce off each other
# elastically and spin from the knock. The ice is a thin slab of real glass (ior 1.31) over the glass sea, so the
# tracer bends the seabed and the fish through it; frosted (roughness 0.22) so it reads as ice, not a still mirror (s126 critic).
#   Once a day 7:00-7:30, for SEA_T seconds.   Main.GLASSSEA[:force] = true   freeze now (films, tests);
#   [:at] = (x, y) a point on the ice to skate round (else: the shore nearest the friends).
const NG = NeverendingGame
isdefined(Main, :GLASSSEA) || Core.eval(Main, :(const GLASSSEA = Dict{Symbol,Any}()))
const GS = Main.GLASSSEA

const SEA_FROM_H = 7.0
const SEA_TO_H = 7.5
const SEA_T = 90.0             # s the sea stays ice
const SEA_ICE = 0.05f0         # m, the top of the ice
const SEA_FRICTION = 0.12f0    # 1/s, how fast a slide dies on ice (grass: ~8)
const SEA_R = 0.32f0           # m, a body's radius for bumps
const SEA_BOUNCE = 0.85f0      # restitution
const SEA_SKATERS = 5
const SEA_LINES = ("Whoa!", "Oof!", "Wheee!", "I can't stop!", "Sorry!", "Again!", "My feet are gone!")
const SEA_FISH = 14
const SEA_FROST = 3000         # white frost flakes on the ice, in patches, thickest over the shallows (s127)
const SEA_MARKS = 700          # skate marks: a pale scratch every SEA_MARK_STEP m a body slides, they stay till the thaw
const SEA_MARK_STEP = 0.22f0
const SEA_FROST_RGB = (0.93f0, 0.96f0, 0.99f0)

mutable struct Skater
    vel::Vec2f
    spin::Float32
    kick_at::Float64
    said_at::Float64
end

mutable struct GlassSea <: System
    day::Int
    on::Bool
    until::Float64
    center::Point2f
    sk::Dict{Int32,Skater}
end

gs_find(sc, name) = (i = findfirst(p -> haskey(p.attributes, :name) && p.attributes[:name][] == name, sc.plots);
                     i === nothing ? nothing : sc.plots[i])

function gs_setup!(game)
    sc = game.stage.scene
    for name in (:glasssea_ice, :glasssea_fish, :glasssea_frost, :glasssea_marks)   # plot names are unique: drop a crashed run's plots
        p = gs_find(sc, name)
        p === nothing || delete!(sc, p)
    end
    GS[:ice] = mesh!(sc, Rect3f(Vec3f(-400, -400, -0.01), Vec3f(800, 800, SEA_ICE + 0.01)); color = RGBAf(0.78, 0.92, 0.98, 1.0),
                     material = NG.Hikari.Glass(color = (0.9, 0.96, 1.0), ior = 1.31, roughness = 0.22), name = :glasssea_ice,
                     visible = false)
    GS[:fish] = meshscatter!(sc, fill(Point3f(0, 0, -50), SEA_FISH); marker = Sphere(Point3f(0), 1f0),
                             markersize = Vec3f(0.34, 0.11, 0.15), rotation = fill(Makie.Quaternionf(0, 0, 0, 1), SEA_FISH),
                             color = RGBf(0.98, 0.55, 0.18), material = NG.Hikari.Plastic(color = (0.98, 0.5, 0.15), roughness = 0.25),
                             name = :glasssea_fish, visible = false)
    disc = Makie.Cylinder(Point3f(0, 0, 0), Point3f(0, 0, 1), 1f0)
    frost = NG.Hikari.Diffuse(color = SEA_FROST_RGB)
    GS[:frost] = meshscatter!(sc, fill(Point3f(0, 0, -50), SEA_FROST); marker = disc, markersize = fill(Vec3f(0.5, 0.3, 0.004), SEA_FROST),
                              rotation = fill(Makie.Quaternionf(0, 0, 0, 1), SEA_FROST), color = RGBf(SEA_FROST_RGB...),
                              material = frost, name = :glasssea_frost, visible = false)
    GS[:marks] = meshscatter!(sc, fill(Point3f(0, 0, -50), SEA_MARKS); marker = disc, markersize = Vec3f(0.16, 0.025, 0.003),
                              rotation = fill(Makie.Quaternionf(0, 0, 0, 1), SEA_MARKS), color = RGBf(SEA_FROST_RGB...),
                              material = frost, name = :glasssea_marks, visible = false)
    GS[:scene] = sc
end

"Frost in patches round `c`: cluster seeds, flakes round each, kept where the water under the ice is shallow (white
shore ice) more often than over the deep."
function gs_frost!(is, c)
    fp = Point3f[]; fs = Vec3f[]; fr = Makie.Quaternionf[]
    tries = 0
    while length(fp) < SEA_FROST && tries < 40 * SEA_FROST
        tries += 1
        a = 2pi * rand(); r = 18 * sqrt(rand())
        sx, sy = c[1] + r * cos(a), c[2] + r * sin(a)
        gs_on_ice(is, sx, sy) || continue
        deep = SEA_ICE - NG.terrain_height(is, sx, sy)
        rand() < 0.2 + 0.8 * exp(-deep / 1.5) || continue
        for _ in 1:rand(15:40)
            length(fp) >= SEA_FROST && break
            x, y = sx + 1.1 * randn(), sy + 1.1 * randn()
            gs_on_ice(is, x, y) || continue
            big = 0.05f0 + 0.3f0 * rand(Float32)^2 * Float32(exp(-(SEA_ICE - NG.terrain_height(is, x, y)) / 2.5))
            push!(fp, Point3f(x, y, SEA_ICE + 0.002f0 + 0.002f0 * rand(Float32)))
            push!(fs, Vec3f(big, big * (0.35f0 + 0.5f0 * rand(Float32)), 0.004f0))
            push!(fr, Makie.qrotation(Vec3f(0, 0, 1), Float32(2pi * rand())))
        end
    end
    while length(fp) < SEA_FROST
        push!(fp, Point3f(0, 0, -50)); push!(fs, Vec3f(0.01)); push!(fr, Makie.Quaternionf(0, 0, 0, 1))
    end
    Makie.update!(GS[:frost]; arg1 = fp, markersize = fs, rotation = fr)
    GS[:frost].visible = true
    GS[:markpos] = fill(Point3f(0, 0, -50), SEA_MARKS)
    GS[:markrot] = fill(Makie.Quaternionf(0, 0, 0, 1), SEA_MARKS)
    GS[:marknext] = 1
    GS[:marklast] = Dict{Int32,Point2f}()
    GS[:markdirty] = false
    Makie.update!(GS[:marks]; arg1 = GS[:markpos], rotation = GS[:markrot])
    GS[:marks].visible = true
end

"A slide leaves a scratch on the ice every SEA_MARK_STEP m, along the way it went (a ring of SEA_MARKS, oldest first out)."
function gs_mark!(id, x, y, vel)
    last = GS[:marklast]::Dict{Int32,Point2f}
    p = get(last, id, nothing)
    p === nothing && (last[id] = Point2f(x, y); return)
    hypot(x - p[1], y - p[2]) < SEA_MARK_STEP && return
    last[id] = Point2f(x, y)
    norm(vel) < 0.4f0 && return
    k = GS[:marknext]::Int
    pos = GS[:markpos]::Vector{Point3f}; rot = GS[:markrot]::Vector{Makie.Quaternionf}
    pos[k] = Point3f(x, y, SEA_ICE + 0.005f0)
    rot[k] = Makie.qrotation(Vec3f(0, 0, 1), atan(vel[2], vel[1]))
    GS[:marknext] = k % SEA_MARKS + 1
    GS[:markdirty] = true
end

function gs_marks_draw!()
    get(GS, :markdirty, false) || return
    GS[:markdirty] = false
    Makie.update!(GS[:marks]; arg1 = GS[:markpos], rotation = GS[:markrot])
end

"Water just off the shore nearest (x, y): march out from the island's middle along that bearing."
function gs_shore(is, x, y)
    a = atan(y, x)
    for r in 4f0:0.5f0:40f0
        NG.terrain_height(is, r * cos(a), r * sin(a)) < -0.3f0 && return Point2f((r + 4) * cos(a), (r + 4) * sin(a))
    end
    return Point2f(30cos(a), 30sin(a))
end

gs_on_ice(is, x, y) = NG.terrain_height(is, x, y) < SEA_ICE

function gs_freeze!(sys::GlassSea, game; forced = false)
    w = game.world
    is = w.island
    friends = [c for c in w.creatures if c.name != "Lumi" && !c.controlled &&
               (forced || (c.action !== :sleep && !(c.goal.kind in NG.BUSY_GOALS)))]
    isempty(friends) && return
    if haskey(GS, :at)
        a = GS[:at]; sys.center = Point2f(a[1], a[2])
    else
        mx = sum(c.pos[1] for c in friends) / length(friends); my = sum(c.pos[2] for c in friends) / length(friends)
        sys.center = gs_shore(is, mx, my)
    end
    sort!(friends, by = c -> hypot(c.pos[1] - sys.center[1], c.pos[2] - sys.center[2]))
    empty!(sys.sk)
    for c in first(friends, SEA_SKATERS)
        sys.sk[c.id] = Skater(Vec2f(0), 0f0, w.t + rand(), -Inf)
        c.action === :sleep && (c.action = :idle)
        c.goal = NG.Goal(:glasssea, c.pos, :idle, SEA_T, w.t + SEA_T, true, 0, false)
    end
    sys.on = true; sys.until = w.t + SEA_T
    GS[:ice].visible = true
    # fish frozen mid-swim round the skating ground, each caught in a different turn
    fp = Point3f[]; fr = Makie.Quaternionf[]
    for k in 1:SEA_FISH
        a = 2pi * rand(); r = 2 + 9 * rand()
        x, y = sys.center[1] + r * cos(a), sys.center[2] + r * sin(a)
        gs_on_ice(is, x, y) || continue
        push!(fp, Point3f(x, y, max(NG.terrain_height(is, x, y) + 0.2f0, -0.25f0 - 0.5f0 * rand(Float32))))
        push!(fr, Makie.qrotation(Vec3f(0, 0, 1), Float32(2pi * rand())))
    end
    while length(fp) < SEA_FISH
        push!(fp, Point3f(0, 0, -50)); push!(fr, Makie.Quaternionf(0, 0, 0, 1))
    end
    Makie.update!(GS[:fish]; arg1 = fp, rotation = fr)
    GS[:fish].visible = true
    gs_frost!(is, sys.center)
    me = findfirst(c -> c.name == "Lumi", w.creatures)
    me === nothing || NG.say!(w, w.creatures[me], "The sea froze! Everyone out!")
    NG.emit!(w, :glasssea_freeze; skaters = length(sys.sk))
end

function gs_thaw!(sys::GlassSea, game)
    w = game.world
    for (id, _) in sys.sk
        c = NG.creature(w, id)
        c === nothing && continue
        c.goal.kind == :glasssea && (c.goal = NG.Goal())
        # back to the nearest shore if the thaw caught it out there
        NG.on_land(w.island, c.pos[1], c.pos[2]) || (c.pos = gs_land(w.island, c.pos))
    end
    empty!(sys.sk)
    sys.on = false
    GS[:ice].visible = false; GS[:fish].visible = false
    GS[:frost].visible = false; GS[:marks].visible = false
    NG.emit!(w, :glasssea_thaw)
end

function gs_land(is, p)
    a = atan(p[2], p[1]); r = hypot(p[1], p[2])
    while r > 0 && !NG.on_land(is, r * cos(a), r * sin(a); margin = 0.5f0)
        r -= 0.5f0
    end
    return NG.ground(is, (Float32(r * cos(a)), Float32(r * sin(a))))
end

"One skater's frame: walk to the ice, then glide, push off now and then, and keep near the middle."
function gs_skate!(sys::GlassSea, w, c, s::Skater, dt)
    is = w.island
    c.goal.kind == :glasssea || (c.goal = NG.Goal(:glasssea, c.pos, :idle, SEA_T, sys.until, true, 0, false))
    c.goal.target = c.pos; c.goal.arrived = true
    x, y = c.pos[1], c.pos[2]
    if !gs_on_ice(is, x, y)
        d = Vec2f(sys.center[1] - x, sys.center[2] - y)
        dir = d / max(norm(d), 1f-3)
        s.vel = 2.4f0 * dir                       # trots down to the ice
        c.action = :run; c.phase += 9f0 * dt
        c.yaw = atan(dir[2], dir[1])
        nx, ny = x + s.vel[1] * dt, y + s.vel[2] * dt
        c.pos = gs_on_ice(is, nx, ny) ? Point3f(nx, ny, SEA_ICE) : NG.ground(is, (nx, ny))
        return
    end
    if w.t >= s.kick_at                           # a skating push: mostly on along the slide, back to the middle when far out
        s.kick_at = w.t + 1.6 + 2.2 * rand()
        to = Vec2f(sys.center[1] - x, sys.center[2] - y)
        far = norm(to) > 7f0
        a = far ? atan(to[2], to[1]) + 0.6f0 * (rand(Float32) - 0.5f0) : Float32(2pi * rand())
        s.vel += (far ? 2.2f0 : 1.6f0) * Vec2f(cos(a), sin(a))
        c.phase += 2f0
    end
    s.vel *= exp(-SEA_FRICTION * Float32(dt))
    sp = norm(s.vel)
    sp > 4.5f0 && (s.vel *= 4.5f0 / sp)
    nx, ny = x + s.vel[1] * dt, y + s.vel[2] * dt
    if !gs_on_ice(is, nx, ny)                     # the shore stops the slide: bounce back off it
        s.vel = -0.5f0 * s.vel
        nx, ny = x, y
    end
    c.pos = Point3f(nx, ny, SEA_ICE)
    gs_mark!(c.id, nx, ny, s.vel)
    if abs(s.spin) > 0.3f0
        c.yaw = NG.wrap_angle(c.yaw + s.spin * Float32(dt))
        s.spin *= exp(-0.7f0 * Float32(dt))
    elseif sp > 0.2f0
        c.yaw = NG.wrap_angle(c.yaw + clamp(NG.wrap_angle(atan(s.vel[2], s.vel[1]) - c.yaw), -3f0 * dt, 3f0 * dt))
    end
    c.action = :idle                              # gliding: the legs stay still, the body slides
end

"Bodies that meet on the ice bounce off each other (equal masses, restitution SEA_BOUNCE) and spin from the knock."
function gs_bumps!(sys::GlassSea, w)
    ids = collect(keys(sys.sk))
    for a in 1:length(ids), b in a+1:length(ids)
        ca = NG.creature(w, ids[a]); cb = NG.creature(w, ids[b])
        (ca === nothing || cb === nothing) && continue
        d = Vec2f(cb.pos[1] - ca.pos[1], cb.pos[2] - ca.pos[2])
        dist = norm(d)
        (dist > 2SEA_R || dist < 1f-4) && continue
        n = d / dist
        sa, sb = sys.sk[ids[a]], sys.sk[ids[b]]
        vn = dot(sb.vel - sa.vel, n)
        vn >= 0 && continue                       # already parting
        j = -(1 + SEA_BOUNCE) * vn / 2
        sa.vel -= j * n; sb.vel += j * n
        t = Vec2f(-n[2], n[1])
        knock = dot(sb.vel - sa.vel, t)
        sa.spin += 3f0 * j + 2f0 * knock; sb.spin -= 3f0 * j + 2f0 * knock
        push = (2SEA_R - dist) / 2
        ca.pos -= Point3f(push * n[1], push * n[2], 0); cb.pos += Point3f(push * n[1], push * n[2], 0)
        if j > 0.6f0
            for (c, s) in ((ca, sa), (cb, sb))
                w.t - s.said_at > 3 || continue
                s.said_at = w.t
                NG.say!(w, c, rand(SEA_LINES))
            end
            NG.emit!(w, :glasssea_bump; a = ca.name, b = cb.name, speed = Float64(2j))
        end
    end
end

function NG.step!(sys::GlassSea, game, dt)
    game.stage === nothing && return
    (get(GS, :scene, nothing) === game.stage.scene && haskey(GS, :marks)) || gs_setup!(game)
    w = game.world
    GS[:sys] = sys
    hour = 24 * NG.daytime(w)
    day = floor(Int, w.t / w.day_length)
    if get(GS, :force, false) && !sys.on
        GS[:force] = false
        gs_freeze!(sys, game; forced = true)
    elseif !sys.on && day != sys.day && SEA_FROM_H <= hour < SEA_TO_H && game.minigame === nothing
        sys.day = day
        gs_freeze!(sys, game)
    end
    sys.on || return
    if w.t >= sys.until
        gs_thaw!(sys, game)
        return
    end
    dt = Float32(clamp(dt, 0, 0.05))
    for (id, s) in sys.sk
        c = NG.creature(w, id)
        (c === nothing || c.controlled) && continue
        gs_skate!(sys, w, c, s, dt)
    end
    gs_bumps!(sys, w)
    gs_marks_draw!()
end

function NG.stop!(sys::GlassSea, game)
    sys.on && game.stage !== nothing && gs_thaw!(sys, game)
end

:glasssea in NG.BUSY_GOALS || push!(NG.BUSY_GOALS, :glasssea)
register!(GlassSea(-1, false, 0.0, Point2f(0), Dict{Int32,Skater}()))
