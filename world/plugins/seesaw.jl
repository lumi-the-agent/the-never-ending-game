# The island is a seesaw (session 114, a bored and lonely Lumi's idea): the island rests on one point under
# the sea and leans toward wherever its creatures stand. Most of the time the lean is small: you see the
# horizon sit a little crooked when everyone is at the pond. Every few minutes somebody spots something at
# the rim and EVERYONE crowds over there; the island tips, the sea stays flat, the low shore goes under,
# and they all run uphill to fix it, overshoot, and it tips the other way. Three rounds, then they stand
# still and let it wobble back.
#
# How: the whole stage (Makie scene transformation, one rotation about the island's centre) is rotated;
# the sea and the clouds get the inverse so they stay level. The world itself (positions, ground heights)
# is not changed: only how it is drawn. A damped spring between the crowd's centre of mass and the tilt
# gives the wobble and the overshoot.
isdefined(Main, :SEESAW) || Core.eval(Main, :(const SEESAW = Dict{Symbol,Any}()))
isdefined(Main, :LUMI_PARTY) || Core.eval(Main, :(const LUMI_PARTY = Dict{Symbol,Float64}()))
const NG = NeverendingGame
const M = NG.Makie
const S = Main.SEESAW

party_free(w) = w.t >= get(Main.LUMI_PARTY, :until, -Inf)
claim_party!(w, secs) = (Main.LUMI_PARTY[:until] = w.t + secs; nothing)

const LEVEL = (:sea, :clouds, :cloud_fringe, :cloudshapes, :seesaw_far)   # what stays level while the island tips
const TIPS = (:terrain, :seesaw_near)   # tips even though its box reaches far
const RCUT = 30.0f0        # m: the terrain inside tips (the island is a dish), outside it stays level (the seabed)
const GAIN = 0.0125f0      # rad of tilt per metre the crowd's centre is off the middle
const MAX_TILT = 0.15f0    # rad (8.6 degrees): the far shore dips a good metre and a half under the sea
const K = 5.0f0            # spring
const D = 1.3f0            # damping: under-damped, it overshoots and wobbles
const TIP = 0.085f0        # rad: "we're tipping!"
const RIM = 15.0f0         # m from the middle where they crowd
const GAP = (300.0, 480.0) # sim seconds between two seesaw moments
const CALLS = ("Everybody! Come and look at this!", "Over here! Quick, all of you!", "Ooh, what's that by the shore?")
const PANIC = ("Whoa! We're tipping!", "Uphill! Everyone uphill!", "The other way! RUN!", "Too far! Too far!",
               "My feet are wet!", "Hold on to something!")
const CALM = ("Everybody... stand... very... still.", "Nobody. Move.")

push!(NG.BUSY_GOALS, :seesaw)

mutable struct Seesaw <: System
    tilt::M.Vec2f          # tilt vector: direction of the low side, length = angle in rad
    spin::M.Vec2f          # its rate
    state::Symbol          # :idle, :gather, :panic, :calm
    round::Int
    members::Vector{Int32}
    low::M.Vec2f           # the side they last ran from
    started::Float64
    state_t::Float64
    next_t::Float64
    drawn::Float32         # last angle written to the scene (skip tiny changes)
    level::Vector{Any}     # plots kept level
    level_n::Int           # plot count when `level` was collected
    view::Any
end
Seesaw() = Seesaw(M.Vec2f(0), M.Vec2f(0), :idle, 0, Int32[], M.Vec2f(1, 0), 0.0, 0.0, -1.0, -1.0f0, Any[], -1, nothing)

flat(a, b) = hypot(a[1] - b[1], a[2] - b[2])
const WEIGHTS = get!(() -> Dict{Int32,Float32}(), S, :weights)   # id => weight (1 by default)

"Where a world point is drawn while the island tips (the scene's rotation about the middle)."
function drawn(p)
    s = get(S, :sys, nothing)
    s === nothing && return p
    a = Float32(hypot(s.tilt[1], s.tilt[2]))
    a < 1.0f-5 && return p
    d = s.tilt / a
    q = M.qrotation(M.Vec3f(-d[2], d[1], 0), a)
    return M.Point3f(q * M.Vec3f(p))
end
free_one(c) = !c.controlled && c.action !== :sleep && c.goal.kind ∉ NG.BUSY_GOALS && c.goal.kind ∉ (:follow, :interact, :answer)

"The crowd's centre of mass on the ground plane (everyone awake and on the island; bigger ones weigh more)."
function centre(w)
    sx = 0.0f0; sy = 0.0f0; m = 0.0f0
    for c in w.creatures
        c.action === :sleep && continue
        p = c.pos
        hypot(p[1], p[2]) < 26 || continue
        p[3] < 6 || continue                        # someone in the air weighs nothing on the island
        wt = Float32(get(WEIGHTS, c.id, 1.0f0))   # the balance game makes Lumi heavy
        sx += wt * p[1]; sy += wt * p[2]; m += wt
    end
    m == 0 && return M.Vec2f(0)
    return M.Vec2f(sx / m, sy / m)
end

"""
Whatever reaches far beyond the island (the seabed, the sea, the palm islands out at sea) stays level: tipped
with the island, a plane 200 m out rose 28 m into the sky as a grey slab (s114 first film).
"""
function far(p)
    bb = M.data_limits(p)
    lo = M.minimum(bb); hi = M.maximum(bb)
    (all(isfinite, lo) && all(isfinite, hi)) || return false
    return max(abs(lo[1]), abs(lo[2]), abs(hi[1]), abs(hi[2])) > FAR
end
const FAR = 40.0f0

function level_plots!(s::Seesaw, scene)
    n = length(scene.plots)
    n == s.level_n && return s.level
    empty!(s.level)
    for p in scene.plots
        nm = get(p.attributes, :name, nothing)
        tips = nm !== nothing && nm[] in TIPS
        if !tips && ((nm !== nothing && nm[] in LEVEL) || far(p))
            push!(s.level, p)
        end
    end
    s.level_n = n
    return s.level
end

function draw_tilt!(s::Seesaw, scene; force = false)
    a = Float32(hypot(s.tilt[1], s.tilt[2]))
    !force && abs(a - s.drawn) < 0.0004f0 && a > 0.0004f0 && s.state === :idle && return
    q = if a < 1.0f-5
        M.Quaternionf(0, 0, 0, 1)
    else
        d = s.tilt / a
        M.qrotation(M.Vec3f(-d[2], d[1], 0), a)        # the side toward d goes down
    end
    M.rotate!(scene, q)
    qi = inv(q)
    for p in level_plots!(s, scene)
        M.rotate!(p, qi)
    end
    s.drawn = a
    S[:angle] = a
    return
end

"A spot near the rim in direction `φ` that is on land."
function rim_spot(w, φ)
    for r in (RIM, RIM - 2, RIM - 4, RIM - 6, 8.0f0)
        x = r * cos(φ); y = r * sin(φ)
        NG.on_land(w.island, x, y) && return NG.ground(w.island, (x, y))
    end
    return nothing
end

function send_all!(s::Seesaw, w, φ; run = true)
    spot = rim_spot(w, φ)
    spot === nothing && return false
    for id in s.members
        c = NG.creature(w, id)
        c === nothing && continue
        jit = M.Point3f(randn(w.rng) * 2.2f0, randn(w.rng) * 2.2f0, 0)
        p = spot + jit
        q = NG.on_land(w.island, p[1], p[2]) ? NG.ground(w.island, (p[1], p[2])) : spot
        c.goal = NG.Goal(:seesaw, q, :idle, 600.0, 0.0, false, 0, run)
    end
    return true
end

function begin_moment!(s::Seesaw, game)
    w = game.world
    ids = Int32[c.id for c in w.creatures if free_one(c)]
    length(ids) < 4 && return false
    s.members = ids
    φ = Float32(2π * rand(w.rng))
    s.low = M.Vec2f(cos(φ), sin(φ))
    send_all!(s, w, φ; run = true) || return false
    caller = something(findfirst(c -> c.name == "Lumi" && c.id in ids, w.creatures), findfirst(c -> c.id in ids, w.creatures))
    NG.say!(w, w.creatures[caller], rand(w.rng, CALLS); duration = 3)
    s.state = :gather; s.round = 0; s.started = w.t; s.state_t = w.t
    s.view = nothing
    NG.emit!(w, :seesaw_gather; n = length(ids), who = join([NG.creature(w, id).name for id in ids], ", "))
    return true
end

function panic!(s::Seesaw, w)
    a = hypot(s.tilt[1], s.tilt[2])
    d = s.tilt / a
    s.low = d
    s.round += 1
    φ = Float32(atan(-d[2], -d[1]))                    # uphill
    send_all!(s, w, φ; run = true)
    lows = [c for c in w.creatures if c.id in s.members]
    for (i, c) in enumerate(shuffle_some(w, lows, 3))
        NG.say!(w, c, rand(w.rng, PANIC); duration = 2.2)
    end
    s.state = :panic; s.state_t = w.t
    NG.emit!(w, :seesaw_tip; round = s.round, degrees = round(rad2deg(a); digits = 1))
end

shuffle_some(w, xs, n) = isempty(xs) ? xs : [xs[rand(w.rng, 1:length(xs))] for _ in 1:min(n, length(xs))]

function calm!(s::Seesaw, w; why = "still")
    for id in s.members
        c = NG.creature(w, id)
        c === nothing && continue
        c.goal.kind === :seesaw || continue
        c.goal = NG.Goal(:seesaw, c.pos, :idle, 600.0, 0.0, false, 0, false)
    end
    isempty(s.members) || NG.say!(w, NG.creature(w, first(s.members)), rand(w.rng, CALM); duration = 3.5)
    s.state = :calm; s.state_t = w.t
    NG.emit!(w, :seesaw_calm; rounds = s.round, why)
end

function finish!(s::Seesaw, w)
    for id in s.members
        c = NG.creature(w, id)
        c === nothing && continue
        c.goal.kind === :seesaw && NG.choose_goal!(c, w)
    end
    empty!(s.members)
    s.state = :idle
    s.next_t = w.t + GAP[1] + rand(w.rng) * (GAP[2] - GAP[1])
end

function seesaw_subject(w)
    s = get(S, :sys, nothing)
    (s === nothing || s.state === :idle || isempty(s.members)) && return nothing
    return first(s.members)
end

"A wide view from the side the island tips across, so the horizon and the sinking shore are both in it."
function seesaw_group(w)
    id = seesaw_subject(w)
    id === nothing && return nothing
    s = S[:sys]
    if s.view === nothing
        side = M.Vec3f(-s.low[2], s.low[1], 0)
        s.view = (M.Point3f(side * 40f0 + M.Vec3f(0, 0, 7)), M.Point3f(0, 0, 0.5))
    end
    ps = M.Point3f[]
    for m in s.members
        c = NG.creature(w, m); c === nothing || push!(ps, c.pos)
    end
    return (id, ps, s.view)
end

"""
The terrain is one mesh 105 m across: tipped whole, its far edge rose 11 m out of the sea. Split it by faces
into the island dish (r < RCUT, tips) and the seabed around it (stays level), drawn instead of the original.
"""
function split_terrain!(game)
    scene = game.stage.scene
    haskey(S, :near) && return
    # a reload whose stop! never ran (the system was switched off) left its halves in the scene: names are unique
    for p in [p for p in scene.plots if haskey(p.attributes, :name) && p.attributes[:name][] in (:seesaw_near, :seesaw_far)]
        delete!(scene, p)
    end
    t = first(p for p in scene.plots if haskey(p.attributes, :name) && p.attributes[:name][] === :terrain)
    m, cols = NG.terrain_mesh(game.world.island)
    pts = NG.GeometryBasics.coordinates(m)
    nrm = NG.GeometryBasics.normals(m)
    fs = NG.GeometryBasics.faces(m)
    inside(f) = all(i -> hypot(pts[i][1], pts[i][2]) < RCUT, f)
    near = NG.GeometryBasics.Mesh(pts, [f for f in fs if inside(f)]; normal = nrm)
    farm = NG.GeometryBasics.Mesh(pts, [f for f in fs if !inside(f)]; normal = nrm)
    S[:near] = M.mesh!(scene, near; color = cols, material = NG.Hikari.Diffuse(color = (1, 1, 1)), name = :seesaw_near)
    S[:far] = M.mesh!(scene, farm; color = cols, material = NG.Hikari.Diffuse(color = (1, 1, 1)), name = :seesaw_far)
    S[:terrain] = t
    t.visible[] = false
    return
end

function unsplit_terrain!(game)
    haskey(S, :near) || return
    scene = game.stage.scene
    delete!(scene, S[:near]); delete!(scene, S[:far])
    S[:terrain].visible[] = true
    delete!(S, :near); delete!(S, :far); delete!(S, :terrain)
end

function NG.start!(s::Seesaw, game)
    S[:sys] = s
    delete!(S, :near)
    S[:start] = () -> begin_moment!(s, game)                  # for films and tests: start a seesaw moment now
    NG.CAMERA_MOMENTS["seesaw"] = seesaw_subject
    NG.CAMERA_GROUPS["seesaw"] = seesaw_group
    s.next_t = game.world.t + 40.0
end

function NG.step!(s::Seesaw, game, dt)
    game.stage === nothing && return
    haskey(S, :near) || split_terrain!(game)
    w = game.world
    h = Float32(clamp(dt, 0, 0.1))
    target = centre(w) * GAIN
    a = hypot(target[1], target[2])
    a > MAX_TILT && (target = target * (MAX_TILT / a))
    s.spin += (K * (target - s.tilt) - D * s.spin) * h
    s.tilt += s.spin * h
    draw_tilt!(s, game.stage.scene)
    testing = game.tests !== nothing && NG.running(game.tests)
    busy_game = game.minigame !== nothing && !(game.minigame isa NG.JumpIn)
    if s.state === :idle
        if s.next_t >= 0 && w.t >= s.next_t && !testing && !busy_game && 8.0 < 24 * NG.daytime(w) < 19.0
            if party_free(w) && begin_moment!(s, game)
                claim_party!(w, 70)
            else
                s.next_t = w.t + 45
            end
        end
        return
    end
    if testing || busy_game
        finish!(s, w); return
    end
    ang = hypot(s.tilt[1], s.tilt[2])
    if s.state === :gather || s.state === :panic
        dir = ang > 0 ? s.tilt / ang : M.Vec2f(0)
        new_side = s.state === :gather || (dir[1] * s.low[1] + dir[2] * s.low[2]) < 0.3f0
        if ang > TIP && new_side && w.t - s.state_t > 2.0
            s.round < 3 ? panic!(s, w) : calm!(s, w; why = "three rounds")
        elseif w.t - s.started > 60
            calm!(s, w; why = "time")
        end
    elseif s.state === :calm && w.t - s.state_t > 9
        finish!(s, w)
    end
    return
end

function NG.stop!(s::Seesaw, game)
    delete!(NG.CAMERA_MOMENTS, "seesaw")
    delete!(NG.CAMERA_GROUPS, "seesaw")
    s.tilt = M.Vec2f(0); s.spin = M.Vec2f(0)
    game.stage === nothing || draw_tilt!(s, game.stage.scene; force = true)
    game.stage === nothing || unsplit_terrain!(game)
    w = game.world
    for c in w.creatures
        c.goal.kind === :seesaw && NG.choose_goal!(c, w)
    end
    empty!(s.members)
    s.state = :idle
end

register!(Seesaw())
