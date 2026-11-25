# Pumpkin bowling (session 83). Once an island afternoon a pyramid of thirty pumpkins stands stacked on the meadow,
# the friends gather behind it, and Lumi takes a run-up and crashes into it: STRIKE. From then on the pumpkins are
# simulated (gravity, bounces off the ground, each other, bushes, rocks and creatures, rolling down the slope), so
# every crash comes out differently, and friends who get bonked by one say so. They lie about for a few minutes
# and anyone, a friend or a player as Lumi, can kick them about before they are gathered up again.
isdefined(Main, :PUMPKINS) || Core.eval(Main, :(const PUMPKINS = Dict{Symbol,Any}()))
const NG = NeverendingGame

# One island moment at a time (s85, todo 389): the shared claim in Main.LUMI_PARTY (flight, hiccups, boing, ...).
isdefined(Main, :LUMI_PARTY) || Core.eval(Main, :(const LUMI_PARTY = Dict{Symbol,Float64}()))
party_free(w) = w.t >= get(Main.LUMI_PARTY, :until, -Inf)
claim_party!(w, secs) = (Main.LUMI_PARTY[:until] = w.t + secs; nothing)
const PK = Main.PUMPKINS

const SPOT = Point2f(8.5, -0.5)         # the flower meadow west of the Big Boing toadstool (the most open ground there)
const RUN = Vec2f(0, 1)                 # Lumi runs north into it
const R = 0.34f0                        # stacking radius of a pumpkin
const LAYERS = 4                        # 16 + 9 + 4 + 1 = 30 pumpkins
const PUMPKIN = "20261125-080940-055-mesh"   # from the image of 20261125-075522-616-asset (its mesh lost the GPU)
const PUMPKIN_OK = false                       # true once the mesh has been looked at
const G = 9.8f0
const T_GATHER = 4.0; const T_TUMBLE = 9.0; const T_STAY = 200.0; const T_FADE = 2.5
const EVENTS = (:follow, :sleep, :circle, :boing, :boing_walk, :choir, :conga, :hide, :found, :freeze, :flight,
                :paint, :giant, :egg, :lesson, :soar, :snowman, :storm, :build, :tinker, :toadstool, :blossom,
                :swing, :bottle, :leaves, :pumpkin)
const PULL = (:fish, :pebble, :feel, :sunset, :tag, :present, :fetch, :beachcomb, :sunbathe, :flowers)
const BONKS = ("BONK!", "Oof! A pumpkin!", "Hey!", "Ow, my head!", "Pumpkin attack!")

push!(NG.BUSY_GOALS, :pumpkin)

mutable struct Ball
    p::Point3f
    v::Vec3f
    q::Makie.Quaternionf
    r::Float32
    awake::Bool
    still::Float32          # s it has hardly moved
    ground::Bool
end

mutable struct Pumpkins <: System
    state::Symbol           # :idle :gather :run :tumble :stay :fade
    t0::Float64
    day::Int
    balls::Vector{Ball}
    crew::Vector{Int32}
    from::Point3f
    hit::Bool
    last::Dict{Int32,Point3f}       # creatures' positions a frame ago (their velocity, to push pumpkins)
    bonked::Dict{Int32,Float64}
end
Pumpkins() = Pumpkins(:idle, 0.0, -1, Ball[], Int32[], Point3f(0), false, Dict{Int32,Point3f}(), Dict{Int32,Float64}())

lumi_of(w) = (i = findfirst(c -> c.name == "Lumi", w.creatures); i === nothing ? nothing : w.creatures[i])
centre(w) = NG.ground(w.island, (SPOT[1], SPOT[2]))
height(w, x, y) = NG.terrain_height(w.island, x, y)
function normal(w, p)
    e = 0.15f0
    dx = height(w, p[1] + e, p[2]) - height(w, p[1] - e, p[2])
    dy = height(w, p[1], p[2] + e) - height(w, p[1], p[2] - e)
    n = Vec3f(-dx / 2e, -dy / 2e, 1)
    return n / norm(n)
end

"The pumpkin mesh once the worker has made it (an orange ball until then), centred on its middle. The human's game
waits for PUMPKIN_OK (the mesh looked at); films use it as soon as it exists."
function model!(game)
    haskey(PK, :model) && (PK[:model_ready] || time() - PK[:checked] < 10) && return PK[:model]
    PK[:checked] = time()
    file = joinpath(game.paths.world, "assets", PUMPKIN, "mesh.jls")
    ready = isfile(file) && (PUMPKIN_OK || game.dash === nothing)
    haskey(PK, :model) && PK[:model_ready] == ready && return PK[:model]
    PK[:model_ready] = ready
    if ready
        m0 = NG.AssetModel(NG.Serialization.deserialize(file))
        # the baked texture comes out darker than the picture it was made from (lifted_asset's reason): brighter
        lift(c) = Makie.RGBA{Float32}(min(1f0, 1.35f0 * Makie.red(c)), min(1f0, 1.3f0 * Makie.green(c)), min(1f0, 1.2f0 * Makie.blue(c)), Makie.alpha(c))
        m = NG.AssetModel(m0.mesh, map(lift, m0.color), m0.material)
        ps = GeometryBasics.coordinates(m.mesh)
        lo = Point3f(minimum(p -> p[1], ps), minimum(p -> p[2], ps), minimum(p -> p[3], ps))
        hi = Point3f(maximum(p -> p[1], ps), maximum(p -> p[2], ps), maximum(p -> p[3], ps))
        PK[:model] = (m, (lo + hi) / 2, maximum(hi - lo))
    else
        PK[:model] = (nothing, Point3f(0), 2f0)
    end
    delete!(PK, :plot)
    return PK[:model]
end

"""
A pumpkin of our own while there is no generated one (the worker lost the GPU twice making it, s83): a squashed
ball with eight deep ribs and a dimple on top, 1 unit across; a green stalk is drawn as a second plot.
"""
function pumpkin_mesh()
    nu, nv = 48, 24
    pts = Point3f[]
    for j in 0:nv, i in 0:nu-1
        th = Float32(pi) * j / nv; ph = 2f0 * Float32(pi) * i / nu
        rib = 1 - 0.09f0 * abs(sin(4f0 * ph))^0.7f0                    # eight lobes with creases between
        r = rib * (1 - 0.12f0 * exp(-(th / 0.35f0)^2))                  # a dimple round the stalk
        push!(pts, Point3f(r * sin(th) * cos(ph), r * sin(th) * sin(ph), 0.78f0 * cos(th) - 0.22f0 - 0.1f0 * exp(-(th / 0.3f0)^2)))   # resting on its bottom like the ball it stands for
    end
    idx(i, j) = j * nu + mod(i, nu) + 1
    fs = GeometryBasics.GLTriangleFace[]
    for j in 0:nv-1, i in 0:nu-1
        push!(fs, GeometryBasics.GLTriangleFace(idx(i, j), idx(i + 1, j), idx(i + 1, j + 1)))
        push!(fs, GeometryBasics.GLTriangleFace(idx(i, j), idx(i + 1, j + 1), idx(i, j + 1)))
    end
    ns = fill(Vec3f(0), length(pts))
    for f in fs
        a, b, c = Int.(GeometryBasics.value.(Tuple(f)))
        n = cross(pts[b] - pts[a], pts[c] - pts[a])
        ns[a] += n; ns[b] += n; ns[c] += n
    end
    ns = [norm(v) > 0 ? -v / norm(v) : Vec3f(0, 0, 1) for v in ns]
    return GeometryBasics.Mesh(pts, fs; normal = ns)
end

function plot!(game)
    model = model!(game)
    haskey(PK, :plot) && PK[:plot].parent !== nothing && return PK[:plot]
    sc = game.stage.scene
    for p in filter(p -> haskey(p.attributes, :name) && p.attributes[:name][] === :pumpkins, sc.plots)
        delete!(sc, p)
    end
    m = model[1]
    for p in filter(p -> haskey(p.attributes, :name) && p.attributes[:name][] === :pumpkin_stalks, sc.plots)
        delete!(sc, p)
    end
    PK[:stalks] = meshscatter!(sc, [Point3f(0, 0, -50)]; marker = Makie.Cylinder(Point3f(0), Point3f(0, 0, 1), 1f0),
                               markersize = [Vec3f(0)], rotation = [Makie.Quaternionf(0, 0, 0, 1)],
                               color = RGBf(0.3, 0.45, 0.15), name = :pumpkin_stalks)
    PK[:plot] = m === nothing ?
        meshscatter!(sc, [Point3f(0, 0, -50)]; marker = pumpkin_mesh(), markersize = [Vec3f(0)],
                     rotation = [Makie.Quaternionf(0, 0, 0, 1)], color = RGBf(0.96, 0.5, 0.08), name = :pumpkins) :
        NG.asset_instances!(sc, m, [Point3f(0, 0, -50)]; markersize = [Vec3f(0)], rotation = [Makie.Quaternionf(0, 0, 0, 1)],
                            name = :pumpkins)
    PK[:drawn] = -1.0
    return PK[:plot]
end

function draw!(s::Pumpkins, game; shrink = 1f0)
    pl = plot!(game)
    m, mid, ext = PK[:model]
    st = PK[:stalks]
    shrink = max(shrink, 0f0)
    ks = get(PK, :keepset, nothing)
    sh(b) = ks !== nothing && objectid(b) in ks ? 1f0 : shrink     # the toys that stay never shrink
    if isempty(s.balls)
        Makie.update!(pl; arg1 = [Point3f(0, 0, -50)], markersize = [Vec3f(0)], rotation = [Makie.Quaternionf(0, 0, 0, 1)])
        Makie.update!(st; arg1 = [Point3f(0, 0, -50)], markersize = [Vec3f(0)], rotation = [Makie.Quaternionf(0, 0, 0, 1)])
        return
    end
    if m === nothing
        Makie.update!(st; arg1 = [b.p + b.q * Vec3f(0, 0, 0.5f0 * b.r * sh(b)) for b in s.balls],
                      markersize = [Vec3f(0.05f0, 0.05f0, 0.22f0) * b.r * sh(b) / R for b in s.balls],
                      rotation = [b.q * Makie.qrotation(Vec3f(1, 0, 0), 0.25f0) for b in s.balls])
    else
        Makie.update!(st; arg1 = [Point3f(0, 0, -50)], markersize = [Vec3f(0)], rotation = [Makie.Quaternionf(0, 0, 0, 1)])
    end
    ps = Point3f[]; ms = Vec3f[]; rs = Makie.Quaternionf[]
    for b in s.balls
        k = 2.15f0 * b.r / ext * sh(b)          # the mesh's widest side a little over the ball (ribs and stem)
        push!(ps, m === nothing ? b.p : b.p - b.q * (k * Vec3f(mid)))
        push!(ms, m === nothing ? Vec3f(b.r * 1.05f0) * sh(b) : Vec3f(k))
        push!(rs, b.q)
    end
    Makie.update!(pl; arg1 = ps, markersize = ms, rotation = rs)
end


const NTOYS = 6          # pumpkins that stay lying about after a bowling: something to kick at any hour (s86)

"After the bowling: the few pumpkins nearest the stack's spot stay, the rest are gathered up."
function keep_toys!(s::Pumpkins, w)
    ks = get(PK, :keepset, nothing)
    s.balls = ks === nothing ? Ball[] : [b for b in s.balls if objectid(b) in ks]
    foreach(b -> (b.awake = false; b.v = Vec3f(0)), s.balls)
    delete!(PK, :keepset)
end

"A game that never bowled yet still has a few pumpkins lying by the stack's spot to kick about."
function set_out_toys!(s::Pumpkins, w)
    isempty(s.balls) || return
    c = centre(w)
    for i in 1:NTOYS
        a = 2f0 * Float32(pi) * i / NTOYS + 0.4f0; r = 1.2f0 + 0.5f0 * mod(i * 0.618f0, 1f0)
        x, y = c[1] + r * cos(a), c[2] + r * sin(a)
        push!(s.balls, Ball(Point3f(x, y, NG.terrain_height(w.island, x, y) + R), Vec3f(0), NG.rot_z(a), R * (0.9f0 + 0.1f0 * mod(i * 0.37f0, 1f0)), false, 0f0, true))
    end
end

"Thirty pumpkins stacked four layers high, asleep (they hold still until something knocks them)."
function stack!(s::Pumpkins, w)
    c = centre(w)
    empty!(s.balls)
    base = 0f0; nb = 0
    for i in 1:LAYERS, j in 1:LAYERS
        x = c[1] + (i - (LAYERS + 1) / 2) * 2R; y = c[2] + (j - (LAYERS + 1) / 2) * 2R
        base += height(w, x, y); nb += 1
    end
    base /= nb
    for k in 0:LAYERS-1
        n = LAYERS - k
        for i in 1:n, j in 1:n
            x = c[1] + (i - (n + 1) / 2) * 2R; y = c[2] + (j - (n + 1) / 2) * 2R
            z = k == 0 ? height(w, x, y) + R : base + R + k * sqrt(2f0) * R
            seed = 17i + 31j + 7k
            q = NG.rot_z(6.283f0 * mod(seed * 0.618f0, 1f0))
            push!(s.balls, Ball(Point3f(x, y, z), Vec3f(0), q, R * (0.9f0 + 0.1f0 * mod(seed * 0.37f0, 1f0)), false, 0f0, true))
        end
    end
end

"Bushes, rocks and trunks near the pyramid as upright cylinders: (x, y, radius, top)."
function obstacles(w)
    get!(PK, :obstacles) do
        c = centre(w)
        obs = [(p.pos[1], p.pos[2], NG.SOLID_FOOTPRINT[p.kind] * p.scale, p.pos[3] + (p.kind === :tree ? 6f0 : 1.4f0) * p.scale)
               for p in w.props if haskey(NG.SOLID_FOOTPRINT, p.kind) && hypot(p.pos[1] - c[1], p.pos[2] - c[2]) < 25]
        # what plugins built (the workshop's bench and crates...) and the Big Boing toadstool's stem
        if isdefined(Main, :EXTRA_SOLIDS)
            for v in values(Main.EXTRA_SOLIDS), (q, r) in v
                push!(obs, (q[1], q[2], r, c[3] + 1.5f0))
            end
        end
        if isdefined(Main, :BOING) && haskey(Main.BOING, :center)
            b = Main.BOING[:center]; push!(obs, (b[1], b[2], 0.9f0, b[3] + 2.5f0))
        end
        obs
    end
end

"One frame of the pumpkins' physics, in 4 substeps: gravity, the ground, obstacles, creatures, each other."
function physics!(s::Pumpkins, game, dt)
    w = game.world
    any(b -> b.awake, s.balls) || return false
    dt = Float32(clamp(dt, 0, 0.05))
    nsub = 4; h = dt / nsub
    obs = obstacles(w)::Vector{NTuple{4,Float32}}      # (typed: as Any it cost 9 ms a frame)
    # creatures as moving bodies: a sphere over the feet, moving as they moved this frame
    bodies = Tuple{Int32,Point3f,Float32,Vec3f}[]
    for c in w.creatures
        last = get(s.last, c.id, c.pos)
        v = dt > 0 ? Vec3f(c.pos - last) / dt : Vec3f(0)
        norm(v) > 12 && (v = Vec3f(0))
        sp = NG.species_of(c)
        rad = 0.32f0 * sp.height
        push!(bodies, (c.id, c.pos + Point3f(0, 0, rad), rad, v))
    end
    for _ in 1:nsub
        for b in s.balls
            b.awake || continue
            b.v += Vec3f(0, 0, -G * h)
            b.p += b.v * h
            gz = height(w, b.p[1], b.p[2])
            b.ground = b.p[3] - b.r < gz + 0.01f0
            if b.p[3] - b.r < gz
                n = normal(w, b.p)
                b.p = Point3f(b.p[1], b.p[2], gz + b.r)
                vn = dot(b.v, n)
                vn < 0 && (b.v -= (1 + (vn < -1.5f0 ? 0.3f0 : 0f0)) * vn * n)
                b.v *= (1 - (norm(b.v) < 0.5f0 ? 3f0 : 0.9f0) * h)   # rolling resistance in the grass, more when slow
            end
            for (x, y, r, top) in obs
                b.p[3] - b.r > top && continue
                d = Vec2f(b.p[1] - x, b.p[2] - y); l = norm(d)
                (l < r + b.r && l > 1f-4) || continue
                n2 = d / l
                b.p = Point3f(x + n2[1] * (r + b.r), y + n2[2] * (r + b.r), b.p[3])
                vn = b.v[1] * n2[1] + b.v[2] * n2[2]
                vn < 0 && (b.v -= 1.4f0 * vn * Vec3f(n2[1], n2[2], 0))
            end
            for (id, cp, cr, cv) in bodies
                d = b.p - cp; l = norm(d)
                (l < b.r + cr && l > 1f-4) || continue
                n = d / l
                b.p = cp + n * (b.r + cr)
                vr = dot(b.v - cv, n)
                if vr < 0
                    b.v -= 1.5f0 * vr * n
                    -vr > 2.5f0 && bonk!(s, w, id)
                end
            end
        end
        nb = length(s.balls)
        for i in 1:nb, j in i+1:nb
            a = s.balls[i]; b = s.balls[j]
            (a.awake || b.awake) || continue
            d = b.p - a.p; l = norm(d); m = a.r + b.r
            (l < m && l > 1f-5) || continue
            n = d / l
            a.awake = true; b.awake = true; a.still = 0; b.still = 0
            a.p -= n * ((m - l) / 2); b.p += n * ((m - l) / 2)
            vr = dot(b.v - a.v, n)
            if vr < 0
                j_ = -(1.3f0) * vr / 2
                a.v -= j_ * n; b.v += j_ * n
            end
        end
    end
    for b in s.balls
        b.awake || continue
        # rolling: turn about the axis across the motion, as far as it rolled
        vxy = Vec3f(b.v[1], b.v[2], 0); sp = norm(vxy)
        if sp > 0.02f0
            axis = normalize(cross(Vec3f(0, 0, 1), vxy))
            b.q = Makie.qrotation(axis, sp * dt / b.r) * b.q
        end
        b.still = norm(b.v) < 0.15f0 && b.ground ? b.still + dt : 0f0
        b.still > 0.5f0 && (b.awake = false; b.v = Vec3f(0))
    end
    return true
end

"A pumpkin hit someone hard: they say so (a friend in nobody's event only)."
function bonk!(s::Pumpkins, w, id)
    w.t - get(s.bonked, id, -Inf) < 3 && return
    s.state === :run && (m = lumi_of(w); m !== nothing && m.id == id) && return    # the bowler itself
    s.bonked[id] = w.t
    c = NG.creature(w, id)
    c === nothing && return
    NG.say!(w, c, BONKS[mod1(Int(id) + length(s.bonked), length(BONKS))]; duration = 1.6)
    push!(get!(() -> Tuple{Float64,Symbol}[], PK, :log), (w.t, :bonk))
    NG.emit!(w, :pumpkin_bonk; who = c.name)
    c.controlled && return
    if c.goal.kind === :pumpkin
        # one of the crowd: a gasp, then a laugh, without leaving (feel! would replace the goal: s73)
        c.goal = NG.Goal(:pumpkin, c.pos, :gasp, 60.0, w.t + 60, true, 0, false); c.action = :gasp
        get!(() -> Dict{Int32,Float64}(), PK, :recover)[id] = w.t + 1.3
    elseif c.goal.kind ∉ EVENTS && c.goal.kind ∉ NG.BUSY_GOALS
        NG.feel!(w, c, :gasp; seconds = 1.4)
    end
end

"Kicks wake sleeping pumpkins: anything moving that touches one (the physics then pushes it)."
function wake_touched!(s::Pumpkins, w)
    for c in w.creatures
        last = get(s.last, c.id, c.pos)
        hypot(c.pos[1] - last[1], c.pos[2] - last[2]) > 0.01f0 || continue
        rad = 0.32f0 * NG.species_of(c).height
        for b in s.balls
            b.awake && continue
            norm(b.p - (c.pos + Point3f(0, 0, rad))) < b.r + rad + 0.05f0 && (b.awake = true)
        end
    end
end

function start_bowling!(s::Pumpkins, game)
    w = game.world
    c = centre(w)
    me = lumi_of(w)
    (me === nothing || me.controlled || me.goal.kind in EVENTS || me.action === :sleep) && return false
    # free friends, and those at a pastime (fishing, pebbles, tag...: a big moment beats them, like boing.jl's PULL)
    cs = [x for x in w.creatures if !x.controlled && x.action !== :sleep && x.goal.kind ∉ EVENTS &&
          (x.goal.kind ∉ NG.BUSY_GOALS || x.goal.kind in PULL) && x !== me && hypot(x.pos[1] - c[1], x.pos[2] - c[2]) < 50]
    sort!(cs; by = x -> hypot(x.pos[1] - c[1], x.pos[2] - c[2]))
    cs = cs[1:min(end, 5)]
    length(cs) < 3 && return false          # (s83 review: a crew of two made a thin show; it tries again in 5 s)
    stack!(s, w)
    # Lumi runs in from the side it is on (it never walks through the stack to get to its start)
    away = Vec2f(me.pos[1] - c[1], me.pos[2] - c[2]); away = norm(away) > 0.5f0 ? away / norm(away) : -RUN
    for turn in (0f0, 0.6f0, -0.6f0, 1.2f0, -1.2f0, 3.14f0)
        d = Vec2f(cos(turn) * away[1] - sin(turn) * away[2], sin(turn) * away[1] + cos(turn) * away[2])
        if NG.on_land(w.island, c[1] + 6f0 * d[1], c[2] + 6f0 * d[2]; margin = 0.3)
            away = d; break
        end
    end
    PK[:dir] = -away; delete!(PK, :side)
    s.from = NG.ground(w.island, (c[1] + 6f0 * away[1], c[2] + 6f0 * away[2]))
    s.crew = Int32[x.id for x in cs]
    n = length(s.crew)
    for (i, x) in enumerate(cs)
        # a half ring on the far side of the pyramid: right where the pumpkins will roll
        a = atan(PK[:dir][2], PK[:dir][1]) + Float32(pi) * (-0.35f0 + 0.7f0 * (i - 1) / max(n - 1, 1))
        t = NG.ground(w.island, (c[1] + 4.6f0 * cos(a), c[2] + 4.6f0 * sin(a)))
        NG.leave_interactions!(w, x)
        x.goal = NG.Goal(:pumpkin, t, :idle, 120.0, w.t + 120, false, 0, true)
    end
    NG.leave_interactions!(w, me)
    me.goal = NG.Goal(:pumpkin, s.from, :idle, 120.0, w.t + 120, false, 0, true)
    s.state = :gather; s.t0 = w.t; s.hit = false
    PK[:log] = Tuple{Float64,Symbol}[(w.t, :start)]
    NG.say!(w, me, "Who wants to see a STRIKE?"; duration = 2.6)
    NG.emit!(w, :pumpkin_start; n = n)
    return true
end

function release!(s::Pumpkins, w)
    for id in s.crew
        x = NG.creature(w, id)
        x === nothing || x.controlled || x.goal.kind !== :pumpkin || NG.choose_goal!(x, w)
    end
    me = lumi_of(w)
    me === nothing || me.controlled || me.goal.kind !== :pumpkin || NG.choose_goal!(me, w)
    empty!(s.crew)
end

function NG.step!(s::Pumpkins, game, dt)
    game.stage === nothing && return
    w = game.world
    plot!(game)
    el = w.t - s.t0
    me = lumi_of(w)
    if s.state === :idle
        if get(PK, :shown, true)
            draw!(s, game); PK[:shown] = false
        end
        film = get(PK, :film, false)
        testing = game.tests !== nothing && NG.running(game.tests)
        busy_game = game.minigame !== nothing && !(game.minigame isa NG.JumpIn)
        day = floor(Int, w.t / w.day_length)
        if (film || day != s.day && 13.5 < 24 * NG.daytime(w) < 17) && !testing && !busy_game && w.t >= get(PK, :try_at, -Inf)
            PK[:try_at] = w.t + 5
            if (film || party_free(w)) && start_bowling!(s, game)
                s.day = day; PK[:film] = false; claim_party!(w, 30)
            end
        end
        # the few pumpkins left lying about after a bowling (or set out at the start) stay kickable at any hour
        if !isempty(s.balls)
            wake_touched!(s, w)
            physics!(s, game, dt) && (draw!(s, game); PK[:drawn] = w.t)
        end
        foreach(c -> s.last[c.id] = c.pos, w.creatures)
        return
    end
    PK[:shown] = true
    c = centre(w)
    for (id, t) in collect(get(PK, :recover, Dict{Int32,Float64}()))
        w.t < t && continue
        delete!(PK[:recover], id)
        x = NG.creature(w, id)
        x !== nothing && x.goal.kind === :pumpkin && (x.goal.action = :laugh; x.action = :laugh)
    end
    if s.state in (:gather, :run, :tumble)
        for id in s.crew
            x = NG.creature(w, id)
            (x === nothing || x.goal.kind !== :pumpkin) && continue
            x.goal.until = w.t + 60
            x.goal.arrived && (x.yaw = atan(c[2] - x.pos[2], c[1] - x.pos[1]) - NG.species_of(x).heading)
        end
        filter!(id -> (x = NG.creature(w, id); x !== nothing && x.goal.kind === :pumpkin), s.crew)
    end
    if s.state === :gather
        me !== nothing && me.goal.kind === :pumpkin && (me.goal.until = w.t + 60)
        ready = me !== nothing && me.goal.kind === :pumpkin && hypot(me.pos[1] - s.from[1], me.pos[2] - s.from[2]) < 1.5
        if el >= get(PK, :t_gather, T_GATHER) && (ready || el > 9)
            if me === nothing || me.goal.kind !== :pumpkin || me.controlled
                s.state = :tumble; s.t0 = w.t     # Lumi was called away: the pyramid just stands there, then is gathered
            else
                s.state = :run; s.t0 = w.t
                me.goal = NG.Goal(:pumpkin, c, :run, 60.0, w.t + 60, true, 0, false)   # (arrived: the engine leaves the run to us)
                PK[:run_from] = me.pos
                NG.say!(w, me, "Here... I... COME!"; duration = 2.0)
                push!(PK[:log], (w.t, :run))
            end
        else
            me !== nothing && me.goal.arrived && (me.yaw = atan(c[2] - me.pos[2], c[1] - me.pos[1]) - NG.species_of(me).heading)
        end
    elseif s.state === :run
        # Lumi runs straight at the pyramid (6 m/s) and on through its first row, then the pumpkins have it
        from = PK[:run_from]
        dir = Vec3f(c[1] - from[1], c[2] - from[2], 0); L = norm(dir); dir = dir / L
        d = Float32(min(el * 6.0, L - 0.3))
        p = from + dir * d
        me.pos = NG.ground(w.island, (p[1], p[2]))
        me.action = :run; me.goal.action = :run; me.goal.until = w.t + 60
        me.yaw = atan(dir[2], dir[1]) - NG.species_of(me).heading
        if !s.hit && any(b -> norm(b.p - (me.pos + Point3f(0, 0, 0.5f0))) < b.r + 0.55f0, s.balls)
            s.hit = true
            PK[:hit_at] = w.t
            push!(PK[:log], (w.t, :strike))
            NG.emit!(w, :pumpkin_strike)
        end
        if s.hit && w.t - PK[:hit_at] > 0.25 || d >= L - 0.31f0
            s.hit || (push!(PK[:log], (w.t, :strike)); s.hit = true)
            s.state = :tumble; s.t0 = w.t
            NG.say!(w, me, "STRIIIIKE!"; duration = 2.4)
            me.goal = NG.Goal(:pumpkin, me.pos, :proud, 60.0, w.t + 60, true, 0, false); me.action = :proud
        end
    elseif s.state === :tumble
        if el >= get(PK, :t_tumble, T_TUMBLE)
            me === nothing || me.controlled || me.goal.kind !== :pumpkin ||
                NG.say!(w, me, "Again! Who stacks them up again?"; duration = 2.6)
            release!(s, w)
            s.state = :stay; s.t0 = w.t
            NG.emit!(w, :pumpkin_end)
        end
    elseif s.state === :stay
        if el >= T_STAY
            s.state = :fade; s.t0 = w.t
            c = centre(w)
            PK[:keepset] = Set(objectid(b) for b in sort(s.balls; by = b -> hypot(b.p[1] - c[1], b.p[2] - c[2]))[1:min(end, NTOYS)])
        end
    elseif s.state === :fade
        if el >= T_FADE
            keep_toys!(s, w)
            s.state = :idle; PK[:shown] = true
            draw!(s, game)
            return
        end
    end
    s.state === :gather || wake_touched!(s, w)
    moved = physics!(s, game, dt)
    if moved || s.state === :fade || get(PK, :drawn, -1.0) < 0
        draw!(s, game; shrink = s.state === :fade ? Float32(1 - el / T_FADE) : 1f0)
        PK[:drawn] = w.t
    end
    foreach(x -> s.last[x.id] = x.pos, w.creatures)
end

"The view: square onto Lumi's run, the pyramid in the middle and the friends behind it."
function pumpkin_view(w)
    c = centre(w); d = get(PK, :dir, RUN)
    side = get!(PK, :side) do        # the side of the run with fewer bushes and trunks between the camera and the stack
        clutter(sd) = count(obstacles(w)) do (x, y, r, top)
            e = Vec2f(c[1] + 7.2f0 * sd[1], c[2] + 7.2f0 * sd[2]); t = Vec2f(c[1], c[2]); q = Vec2f(x, y)
            u = clamp(dot(q - e, t - e) / dot(t - e, t - e), 0f0, 1f0)
            norm(q - (e + u * (t - e))) < r + 0.6f0
        end
        a = Vec2f(-d[2], d[1]); b = -a
        clutter(a) <= clutter(b) ? a : b
    end
    return (c + Point3f(7.2f0 * side[1] - 1.6f0 * d[1], 7.2f0 * side[2] - 1.6f0 * d[2], 2.3f0),
            c + Point3f(-1.2f0 * d[1], -1.2f0 * d[2], 0.8f0))
end

function pumpkin_group(w)
    s = PK[:sys]
    s.state in (:gather, :run, :tumble) || return nothing
    me = lumi_of(w)
    (me === nothing || me.controlled) && return nothing
    return (me.id, Point3f[centre(w), me.pos], pumpkin_view(w))
end

function NG.start!(s::Pumpkins, game)
    PK[:sys] = s
    game.stage === nothing || set_out_toys!(s, game.world)
    PK[:drawn] = -1.0
    delete!(PK, :plot); delete!(PK, :model); delete!(PK, :obstacles)
    PK[:shown] = true
    PK[:start] = () -> start_bowling!(s, game)
    moment = w -> s.state in (:gather, :run, :tumble) ? (m = lumi_of(w); m === nothing ? nothing : m.id) : nothing
    NG.CAMERA_MOMENTS["pumpkins"] = moment
    isdefined(Main, :BIG_MOMENTS) || Core.eval(Main, :(const BIG_MOMENTS = Dict{String,Any}()))
    Main.BIG_MOMENTS["pumpkins"] = moment
    NG.CAMERA_GROUPS["pumpkins"] = pumpkin_group
end

function NG.stop!(s::Pumpkins, game)
    delete!(NG.CAMERA_MOMENTS, "pumpkins")
    delete!(NG.CAMERA_GROUPS, "pumpkins")
    isdefined(Main, :BIG_MOMENTS) && delete!(Main.BIG_MOMENTS, "pumpkins")
    s.state in (:gather, :run, :tumble) && release!(s, game.world)
    haskey(PK, :plot) && PK[:plot].parent !== nothing && delete!(PK[:plot].parent, PK[:plot])
    haskey(PK, :stalks) && PK[:stalks].parent !== nothing && delete!(PK[:stalks].parent, PK[:stalks])
    delete!(PK, :plot)
end

register!(Pumpkins())
