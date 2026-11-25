# The lily pond answers (session 86, goal 3 and the perfectionist s85: "the pond and the sea do not react to
# anyone"). Anyone who wades or hops through the pond sends rings rippling out over it and drops flying; a player
# steering Lumi can splash about at any hour. And once an island afternoon there is a CANNONBALL CONTEST: the
# friends line up round the pond, the two crabs sit as judges holding up their scores, and one after another the
# friends leap in, water flying everywhere, until Lumi takes the run-up of its life.
isdefined(Main, :SPLASH) || Core.eval(Main, :(const SPLASH = Dict{Symbol,Any}()))
const NG = NeverendingGame
const SP = Main.SPLASH
isdefined(Main, :LUMI_PARTY) || Core.eval(Main, :(const LUMI_PARTY = Dict{Symbol,Float64}()))
party_free(w) = w.t >= get(Main.LUMI_PARTY, :until, -Inf)
claim_party!(w, secs) = (Main.LUMI_PARTY[:until] = w.t + secs; nothing)

const NRINGS = 40; const NDROPS = 320
const RING_T = 2.4                  # s a ring takes to fade
const EVENTS = (:follow, :sleep, :circle, :boing, :boing_walk, :choir, :conga, :hide, :found, :freeze, :flight,
                :paint, :giant, :egg, :lesson, :soar, :snowman, :storm, :build, :tinker, :toadstool, :blossom,
                :swing, :bottle, :leaves, :pumpkin, :hail, :cannonball)
const PULL = (:fish, :pebble, :feel, :sunset, :tag, :present, :fetch, :beachcomb, :sunbathe, :flowers)
const SCORES = ("6!", "7!", "8!", "9!", "7 and a half!", "8!!", "NINE!")
const CHEERS = ("CANNONBALL!", "Here goes!", "Bombs away!", "Watch this one!", "SPLOOSH time!")

push!(NG.BUSY_GOALS, :cannonball)   # (areas.jl has its own :splash pastime: wading in the pond)
delete!(NG.BUSY_GOALS, :splash)     # (the first s86 version put the pastime's kind there by mistake)

mutable struct Splash <: System
    state::Symbol               # :idle :gather :dive :after
    t0::Float64
    day::Int
    crew::Vector{Int32}         # divers, Lumi last
    judges::Vector{Int32}
    next::Int
    flights::Dict{Int32,Tuple{Point3f,Float64}}
    rings::Vector{Tuple{Point2f,Float64,Float32}}       # where, when, how strong
    drops::Vector{Tuple{Point3f,Vec3f}}
    last::Dict{Int32,Point3f}
    rippled::Dict{Int32,Float64}
end
Splash() = Splash(:idle, 0.0, -1, Int32[], Int32[], 1, Dict{Int32,Tuple{Point3f,Float64}}(),
                  Tuple{Point2f,Float64,Float32}[], Tuple{Point3f,Vec3f}[], Dict{Int32,Point3f}(), Dict{Int32,Float64}())

pond(game) = game.plugins["areas"].mod.POND
pond_r(game) = game.plugins["areas"].mod.POND_R
lumi_of(w) = (i = findfirst(c -> c.name == "Lumi", w.creatures); i === nothing ? nothing : w.creatures[i])

"The water level: the pond surface areas.jl draws (the highest ground inside it, plus 3 cm)."
function level!(game)
    get!(SP, :level) do
        w = game.world; P = pond(game); R = pond_r(game)
        Float32(maximum(NG.terrain_height(w.island, P[1] + r * cos(a), P[2] + r * sin(a))
                        for r in 0:0.2:R * 1.15 for a in range(0, 2pi; length = 37)) + 0.03)
    end::Float32
end

"A thin flat ring of radius 1 (a ripple), drawn just over the water."
function ring_mesh()
    n = 48
    pts = Point3f[]
    for i in 0:n-1
        a = 2f0 * Float32(pi) * i / n
        push!(pts, Point3f(0.86f0 * cos(a), 0.86f0 * sin(a), 0), Point3f(cos(a), sin(a), 0))
    end
    fs = GeometryBasics.GLTriangleFace[]
    for i in 0:n-1
        a, b = 2i + 1, 2i + 2; c, d = 2mod(i + 1, n) + 1, 2mod(i + 1, n) + 2
        push!(fs, GeometryBasics.GLTriangleFace(a, b, d), GeometryBasics.GLTriangleFace(a, d, c))
    end
    return GeometryBasics.Mesh(pts, fs; normal = fill(Vec3f(0, 0, 1), length(pts)))
end

function plots!(game)
    haskey(SP, :rings) && SP[:rings].parent !== nothing && return
    sc = game.stage.scene
    for p in filter(p -> haskey(p.attributes, :name) && p.attributes[:name][] in (:splash_rings, :splash_drops), sc.plots)
        delete!(sc, p)
    end
    hide = [Point3f(0, 0, -50)]
    SP[:rings] = meshscatter!(sc, hide; marker = ring_mesh(), markersize = [Vec3f(0)], color = [RGBAf(0.9, 0.97, 1.0, 0.0)],
                              transparency = true, shading = Makie.NoShading, name = :splash_rings)
    SP[:drops] = meshscatter!(sc, hide; marker = Sphere(Point3f(0), 1f0), markersize = [Vec3f(0)],
                              color = RGBf(0.82, 0.93, 1.0), name = :splash_drops)
    SP[:shown] = true
end

"A splash at `p`: rings and a burst of drops, `k` 0.3 (a step) .. 2 (Lumi's cannonball)."
function splash!(s::Splash, w, p, k; log = false)
    push!(s.rings, (Point2f(p[1], p[2]), w.t, Float32(k)))
    k > 0.8f0 && push!(s.rings, (Point2f(p[1], p[2]), w.t + 0.25, Float32(0.7k)), (Point2f(p[1], p[2]), w.t + 0.55, Float32(0.45k)))
    length(s.rings) > NRINGS && deleteat!(s.rings, 1:length(s.rings) - NRINGS)
    n = round(Int, 12 + 60k)
    for i in 1:n
        a = 2f0 * Float32(pi) * rand(w.rng, Float32); e = 0.5f0 + 0.5f0 * rand(w.rng, Float32)
        sp = (1.5f0 + 3.5f0 * rand(w.rng, Float32)) * sqrt(Float32(k))
        push!(s.drops, (Point3f(p[1], p[2], p[3]) + Point3f(0.3f0 * cos(a), 0.3f0 * sin(a), 0.05f0),
                        Vec3f(cos(a) * (1 - e) * sp, sin(a) * (1 - e) * sp, e * sp * 1.6f0)))
    end
    length(s.drops) > NDROPS && deleteat!(s.drops, 1:length(s.drops) - NDROPS)
    log && push!(get!(() -> Tuple{Float64,Symbol}[], SP, :log), (w.t, k > 1.5 ? :big : :splash))
end

function draw!(s::Splash, game)
    w = game.world
    lvl = level!(game); R = pond_r(game)
    ps = Point3f[]; ms = Vec3f[]; cs = RGBAf[]
    filter!(r -> w.t - r[2] < RING_T, s.rings)
    for (c, born, k) in s.rings
        age = Float32(w.t - born); age < 0 && continue
        r = 0.15f0 + (0.9f0 + 0.5f0 * k) * age
        a = 0.85f0 * min(1f0, k + 0.3f0) * (1 - age / Float32(RING_T)) * clamp((R + 0.2f0 - r) / 0.6f0, 0f0, 1f0)
        a <= 0.01f0 && continue
        push!(ps, Point3f(c[1], c[2], lvl + 0.015f0)); push!(ms, Vec3f(r, r, 1)); push!(cs, RGBAf(0.9, 0.97, 1.0, a))
    end
    if isempty(ps)
        get(SP, :rings_shown, true) && Makie.update!(SP[:rings]; arg1 = [Point3f(0, 0, -50)], markersize = [Vec3f(0)], color = [RGBAf(1, 1, 1, 0)])
        SP[:rings_shown] = false
    else
        Makie.update!(SP[:rings]; arg1 = ps, markersize = ms, color = cs); SP[:rings_shown] = true
    end
    if isempty(s.drops)
        get(SP, :drops_shown, true) && Makie.update!(SP[:drops]; arg1 = [Point3f(0, 0, -50)], markersize = [Vec3f(0)])
        SP[:drops_shown] = false
    else
        Makie.update!(SP[:drops]; arg1 = [d[1] for d in s.drops], markersize = [Vec3f(0.07f0) for _ in s.drops]); SP[:drops_shown] = true
    end
end

"Drops fly and fall back; a drop that lands on the water leaves a tiny ring."
function drops!(s::Splash, game, dt)
    w = game.world; lvl = level!(game); P = pond(game); R = pond_r(game)
    dt = Float32(clamp(dt, 0, 0.05))
    keep = Tuple{Point3f,Vec3f}[]
    for (p, v) in s.drops
        v = v + Vec3f(0, 0, -9.8f0 * dt); p = p + v * dt
        if p[3] < lvl && v[3] < 0
            hypot(p[1] - P[1], p[2] - P[2]) < R && rand(w.rng) < 0.12 && push!(s.rings, (Point2f(p[1], p[2]), w.t, 0.25f0))
            continue
        end
        p[3] < NG.terrain_height(w.island, p[1], p[2]) && continue
        push!(keep, (p, v))
    end
    s.drops = keep
end

"Anyone moving through the water ripples it (a player steering Lumi too, at any hour)."
function waders!(s::Splash, game)
    w = game.world; P = pond(game); R = pond_r(game); lvl = level!(game)
    for c in w.creatures
        last = get(s.last, c.id, c.pos); s.last[c.id] = c.pos
        hypot(c.pos[1] - P[1], c.pos[2] - P[2]) < R * 0.95f0 || continue
        haskey(s.flights, c.id) && continue
        moved = hypot(c.pos[1] - last[1], c.pos[2] - last[2])
        jumping = c.action === :jump
        (moved > 0.01f0 || jumping) || continue
        w.t - get(s.rippled, c.id, -Inf) < (jumping ? 0.5 : 0.35) && continue
        s.rippled[c.id] = w.t
        splash!(s, w, Point3f(c.pos[1], c.pos[2], lvl), jumping ? 0.9f0 : 0.35f0)
    end
end

"The camera's side for the contest: the clearest of eight, chosen once per contest."
function contest_view(game)
    get!(SP, :view) do
        w = game.world; P = pond(game); lvl = level!(game)
        target = Point3f(P[1], P[2], lvl + 0.9f0)
        best = (Inf32, Point3f(P[1], P[2] - 7f0, lvl + 2.4f0))
        for k in 0:7
            a = 2f0 * Float32(pi) * k / 8
            q = (P[1] + 7f0 * cos(a), P[2] + 7f0 * sin(a))
            eye = Point3f(q[1], q[2], max(lvl, NG.terrain_height(w.island, q[1], q[2])) + 2.4f0)
            o = NG.obstruction(w, eye, target)
            o < best[1] && (best = (o, eye))
        end
        (best[2], target)
    end
end

function start_contest!(s::Splash, game)
    w = game.world
    P = pond(game); R = pond_r(game); lvl = level!(game)
    me = lumi_of(w)
    (me === nothing || me.controlled || me.goal.kind in EVENTS || me.action === :sleep) && return false
    free(x) = !x.controlled && x.action !== :sleep && x.goal.kind ∉ EVENTS && (x.goal.kind ∉ NG.BUSY_GOALS || x.goal.kind in PULL) && x !== me
    cs = sort([x for x in w.creatures if free(x) && hypot(x.pos[1] - P[1], x.pos[2] - P[2]) < 60];
              by = x -> hypot(x.pos[1] - P[1], x.pos[2] - P[2]))
    judges = [x for x in cs if x.species == "Crabbit"][1:min(end, 2)]
    length(judges) < 2 && (judges = cs[1:min(end, 2)])
    divers = [x for x in cs if !(x in judges)][1:min(end, 4)]
    length(divers) < 2 && return false
    delete!(SP, :view)
    eye, _ = contest_view(game)
    toward = atan(eye[2] - P[2], eye[1] - P[1])        # the camera's side of the pond
    s.crew = Int32[x.id for x in divers]; push!(s.crew, me.id)
    s.judges = Int32[x.id for x in judges]
    n = length(s.crew)
    for (i, id) in enumerate(s.crew)
        x = NG.creature(w, id)
        a = toward + Float32(pi) + Float32(pi) * (-0.4f0 + 0.8f0 * (i - 1) / max(n - 1, 1))     # the far side
        q = NG.ground(w.island, (P[1] + (R + 1.3f0) * cos(a), P[2] + (R + 1.3f0) * sin(a)))
        NG.leave_interactions!(w, x)
        x.goal = NG.Goal(:cannonball, q, :idle, 120.0, w.t + 120, false, 0, true)
    end
    for (j, id) in enumerate(s.judges)
        x = NG.creature(w, id)
        a = toward + (j == 1 ? 1f0 : -1f0) * 1.75f0           # at the sides, facing the pond (in front they hid it)
        q = NG.ground(w.island, (P[1] + (R + 1.3f0) * cos(a), P[2] + (R + 1.3f0) * sin(a)))
        NG.leave_interactions!(w, x)
        x.goal = NG.Goal(:cannonball, q, :idle, 120.0, w.t + 120, false, 0, true)
    end
    s.state = :gather; s.t0 = w.t; s.next = 1; empty!(s.flights); delete!(SP, :score_at)
    SP[:log] = Tuple{Float64,Symbol}[(w.t, :start)]
    NG.say!(w, me, "CANNONBALL CONTEST! Judges, get your claws ready!"; duration = 3.0)
    NG.emit!(w, :splash_start; n = n)
    return true
end

function finish!(s::Splash, w)
    for id in vcat(s.crew, s.judges)
        x = NG.creature(w, id)
        x === nothing || x.controlled || x.goal.kind !== :cannonball || NG.choose_goal!(x, w)
    end
    empty!(s.crew); empty!(s.judges); empty!(s.flights)
    s.state = :idle
    NG.emit!(w, :splash_end)
end

function NG.step!(s::Splash, game, dt)
    game.stage === nothing && return
    plots!(game)
    w = game.world
    P = pond(game); lvl = level!(game)
    waders!(s, game)
    drops!(s, game, dt)
    el = w.t - s.t0
    if s.state === :idle
        film = get(SP, :film, false)
        testing = game.tests !== nothing && NG.running(game.tests)
        busy_game = game.minigame !== nothing && !(game.minigame isa NG.JumpIn)
        day = floor(Int, w.t / w.day_length)
        if (film || day != s.day && 14 < 24 * NG.daytime(w) < 16.5) && !testing && !busy_game && w.t >= get(SP, :try_at, -Inf)
            SP[:try_at] = w.t + 5
            if (film || party_free(w)) && start_contest!(s, game)
                s.day = day; SP[:film] = false; claim_party!(w, 40)
            end
        end
    else
        c = Point3f(P[1], P[2], lvl)
        # keep the crew and the judges (another event that took one gets it back, like the hail's recall)
        for id in vcat(s.crew, s.judges)
            x = NG.creature(w, id)
            (x === nothing || x.controlled) && continue
            if x.goal.kind !== :cannonball
                NG.leave_interactions!(w, x); x.goal = NG.Goal(:cannonball, x.pos, :idle, 120.0, w.t + 120, true, 0, false)
            end
            x.goal.until = w.t + 60
            x.goal.arrived && !haskey(s.flights, id) && (x.yaw = atan(P[2] - x.pos[2], P[1] - x.pos[1]) - NG.species_of(x).heading)
        end
        if s.state === :gather && el >= get(SP, :t_gather, 5.0)
            s.state = :dive; s.t0 = w.t; SP[:next_at] = w.t
        elseif s.state === :dive
            if s.next <= length(s.crew) && w.t >= SP[:next_at]
                x = NG.creature(w, s.crew[s.next])
                big = x.name == "Lumi"
                s.flights[x.id] = (x.pos, w.t)
                NG.say!(w, x, big ? "STAND BACK! This is the BIG one!" : CHEERS[mod1(s.next, length(CHEERS))]; duration = 1.8)
                push!(SP[:log], (w.t, big ? :lumi : :jump))
                s.next += 1
                SP[:next_at] = w.t + (s.next == length(s.crew) ? 3.0 : 2.4)
            end
            for (id, (from, since)) in collect(s.flights)
                x = NG.creature(w, id)
                x === nothing && (delete!(s.flights, id); continue)
                big = x.name == "Lumi"
                T = big ? 1.3 : 0.9
                u = Float32((w.t - since) / T)
                if u < 1
                    h = big ? 3.4f0 : 1.8f0
                    x.pos = from + (c - from) * u + Point3f(0, 0, h * 4u * (1 - u))
                    x.action = :jump; x.goal.action = :jump
                    x.yaw = atan(c[2] - from[2], c[1] - from[1]) - NG.species_of(x).heading
                elseif !haskey(SP, Symbol(:landed_, id, :_, round(Int, since)))
                    SP[Symbol(:landed_, id, :_, round(Int, since))] = true
                    x.pos = c - Point3f(0, 0, 0.4f0)
                    splash!(s, w, c, big ? 2.0f0 : 1.0f0; log = true)
                    SP[:score_at] = (w.t + 0.7, big)
                elseif u < 1 + 0.6f0 / Float32(T)
                    x.pos = c - Point3f(0, 0, 0.4f0)       # under the water for a moment
                else
                    delete!(s.flights, id)
                    back = NG.ground(w.island, (from[1], from[2]))
                    x.pos = c + 0.92f0 * (back - c) + Point3f(0, 0, 0)      # pops up at the edge, dripping
                    x.goal = NG.Goal(:cannonball, back, :laugh, 60.0, w.t + 60, false, 0, false); x.action = :laugh
                end
            end
            if haskey(SP, :score_at) && w.t >= SP[:score_at][1]
                big = SP[:score_at][2]; delete!(SP, :score_at)
                for (j, id) in enumerate(s.judges)
                    x = NG.creature(w, id); x === nothing && continue
                    NG.say!(w, x, big ? (j == 1 ? "TEN!!" : "ELEVEN!!!") : SCORES[mod1(s.next + 3j, length(SCORES))]; duration = 1.6)
                    x.action = :jump; x.goal.action = :jump
                end
                push!(SP[:log], (w.t, :score))
            end
            if s.next > length(s.crew) && isempty(s.flights) && w.t >= SP[:next_at] - 1.0
                s.state = :after; s.t0 = w.t
                me = lumi_of(w)
                me === nothing || NG.say!(w, me, "...Did I win? I'm soaked!"; duration = 2.6)
            end
        elseif s.state === :after
            w.t - s.t0 >= 4.0 && finish!(s, w)
        end
    end
    draw!(s, game)
end

function splash_group(w)
    s = SP[:sys]
    s.state in (:gather, :dive, :after) || return nothing
    me = lumi_of(w)
    (me === nothing || me.controlled) && return nothing
    v = get(SP, :view, nothing)
    v === nothing && return nothing
    return (me.id, Point3f[v[2], me.pos], v)
end

function NG.start!(s::Splash, game)
    SP[:sys] = s
    for k in (:rings, :drops, :level, :view)
        delete!(SP, k)
    end
    SP[:rings_shown] = true; SP[:drops_shown] = true
    SP[:start] = () -> start_contest!(s, game)
    moment = w -> s.state in (:gather, :dive, :after) ? (m = lumi_of(w); m === nothing ? nothing : m.id) : nothing
    NG.CAMERA_MOMENTS["splash"] = moment
    isdefined(Main, :BIG_MOMENTS) || Core.eval(Main, :(const BIG_MOMENTS = Dict{String,Any}()))
    Main.BIG_MOMENTS["splash"] = moment
    NG.CAMERA_GROUPS["splash"] = splash_group
end

function NG.stop!(s::Splash, game)
    delete!(NG.CAMERA_MOMENTS, "splash")
    delete!(NG.CAMERA_GROUPS, "splash")
    isdefined(Main, :BIG_MOMENTS) && delete!(Main.BIG_MOMENTS, "splash")
    s.state === :idle || finish!(s, game.world)
    for k in (:rings, :drops)
        haskey(SP, k) && SP[k].parent !== nothing && delete!(SP[k].parent, SP[k])
        delete!(SP, k)
    end
end

register!(Splash())
