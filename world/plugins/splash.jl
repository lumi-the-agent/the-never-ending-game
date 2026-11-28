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

const NRINGS = 40; const NDROPS = 520
const RING_T = 2.4                  # s a ring takes to fade
const EVENTS = (:follow, :sleep, :circle, :boing, :boing_walk, :choir, :conga, :hide, :found, :freeze, :flight,
                :paint, :giant, :egg, :lesson, :soar, :snowman, :storm, :build, :tinker, :toadstool, :blossom,
                :swing, :bottle, :leaves, :pumpkin, :hail, :cannonball, :waterfight)
const PULL = (:fish, :pebble, :feel, :sunset, :tag, :present, :fetch, :beachcomb, :sunbathe, :flowers)
const SCORES = ("6!", "7!", "8!", "9!", "7 and a half!", "8!!", "NINE!")
const CHEERS = ("CANNONBALL!", "Here goes!", "Bombs away!", "Watch this one!", "SPLOOSH time!")

push!(NG.BUSY_GOALS, :cannonball); push!(NG.BUSY_GOALS, :waterfight)   # (areas.jl has its own :splash pastime: wading in the pond)
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

"A ripple for traced pictures: a low round swell across a ring of radius 1 (height 1, scaled down per ring)."
function swell_mesh()
    n = 64; m = 6
    pts = Point3f[]
    for i in 0:n-1, j in 0:m
        a = 2f0 * Float32(pi) * i / n; rho = 0.82f0 + 0.18f0 * j / m
        z = sin(Float32(pi) * j / m)
        push!(pts, Point3f(rho * cos(a), rho * sin(a), z))
    end
    idx(i, j) = mod(i, n) * (m + 1) + j + 1
    fs = GeometryBasics.GLTriangleFace[]
    for i in 0:n-1, j in 0:m-1
        push!(fs, GeometryBasics.GLTriangleFace(idx(i, j), idx(i + 1, j), idx(i + 1, j + 1)))
        push!(fs, GeometryBasics.GLTriangleFace(idx(i, j), idx(i + 1, j + 1), idx(i, j + 1)))
    end
    ns = fill(Vec3f(0), length(pts))
    for f in fs
        a, b, c = GeometryBasics.value(f[1]), GeometryBasics.value(f[2]), GeometryBasics.value(f[3])
        v = cross(pts[b] - pts[a], pts[c] - pts[a]); ns[a] += v; ns[b] += v; ns[c] += v
    end
    ns = [norm(v) > 0 ? (v[3] < 0 ? -v : v) / norm(v) : Vec3f(0, 0, 1) for v in ns]
    return GeometryBasics.Mesh(pts, fs; normal = ns)
end

function plots!(game)
    haskey(SP, :rings) && SP[:rings].parent !== nothing && return
    sc = game.stage.scene
    for p in filter(p -> haskey(p.attributes, :name) && p.attributes[:name][] in (:splash_rings, :splash_drops), sc.plots)
        delete!(sc, p)
    end
    hide = [Point3f(0, 0, -50)]
    # water, not paint (s89, the human: "a flat slate-grey lid with white rings painted on it, and the splash is pale
    # plastic marbles"): in traced pictures a ripple is a low glass swell on the water that bends and mirrors the
    # light, and a drop is a glass bead; live, the rings stay soft translucent highlights (alpha, which tracing ignores)
    traced = game.dash === nothing
    SP[:traced] = traced
    SP[:rings] = traced ?
        meshscatter!(sc, hide; marker = swell_mesh(), markersize = [Vec3f(0)], color = RGBAf(0.75, 0.9, 0.95, 1.0),
                     material = NG.Hikari.Glass(color = (0.95, 0.99, 1.0), ior = 1.33, roughness = 0.0), name = :splash_rings) :
        meshscatter!(sc, hide; marker = ring_mesh(), markersize = [Vec3f(0)], color = [RGBAf(0.9, 0.97, 1.0, 0.0)],
                     transparency = true, shading = Makie.NoShading, name = :splash_rings)
    SP[:drops] = meshscatter!(sc, hide; marker = Sphere(Point3f(0), 1f0), markersize = [Vec3f(0)],
                              color = RGBf(0.82, 0.93, 1.0), material = NG.Hikari.Glass(color = (0.97, 1.0, 1.0), ior = 1.33, roughness = 0.0),
                              name = :splash_drops)
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
        # a ring fades out before its far side would reach the bank (rings on the grass, s87)
        dc = hypot(c[1] - pond(game)[1], c[2] - pond(game)[2])
        a = 0.85f0 * min(1f0, k + 0.3f0) * (1 - age / Float32(RING_T)) * clamp((R + 0.05f0 - (dc + r)) / 0.5f0 + 0.3f0, 0f0, 1f0)
        a <= 0.01f0 && continue
        push!(ps, Point3f(c[1], c[2], lvl + 0.015f0)); push!(ms, Vec3f(r, r, 1)); push!(cs, RGBAf(0.9, 0.97, 1.0, a))
    end
    if get(SP, :traced, false) && !isempty(ps)
        Makie.update!(SP[:rings]; arg1 = ps, markersize = [Vec3f(m[1], m[2], 0.035f0 * c.alpha) for (m, c) in zip(ms, cs)]); SP[:rings_shown] = true
    elseif isempty(ps)
        get(SP, :rings_shown, true) && Makie.update!(SP[:rings]; arg1 = [Point3f(0, 0, -50)], markersize = [Vec3f(0)],
                                                     color = get(SP, :traced, false) ? RGBAf(0.75, 0.9, 0.95, 1.0) : [RGBAf(1, 1, 1, 0)])
        SP[:rings_shown] = false
    else
        Makie.update!(SP[:rings]; arg1 = ps, markersize = ms, color = cs); SP[:rings_shown] = true
    end
    th = get(SP, :throws, nothing)
    alld = th === nothing || isempty(th) ? s.drops : vcat(s.drops, [(t[1], t[2]) for t in th])
    if isempty(alld)
        get(SP, :drops_shown, true) && Makie.update!(SP[:drops]; arg1 = [Point3f(0, 0, -50)], markersize = [Vec3f(0)])
        SP[:drops_shown] = false
    else
        Makie.update!(SP[:drops]; arg1 = [d[1] for d in alld], markersize = [Vec3f(0.07f0) for _ in alld]); SP[:drops_shown] = true
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

"The judges' scores, 0.7 s after a splash."
function scores!(s::Splash, w)
    (haskey(SP, :score_at) && w.t >= SP[:score_at][1]) || return
    big = SP[:score_at][2]; delete!(SP, :score_at)
    for (j, id) in enumerate(s.judges)
        x = NG.creature(w, id); x === nothing && continue
        NG.say!(w, x, big ? (j == 1 ? "TEN!!" : "ELEVEN!!!") : SCORES[mod1(s.next + 3j, length(SCORES))]; duration = 1.6)
        x.action = :jump; x.goal.action = :jump
    end
    push!(SP[:log], (w.t, :score))
end

const ALLIN = ("Wheee!", "Me too!", "Wait for me!", "Coming in!", "Clackety SPLASH!", "Geronimooo!")

"Turn from yaw a towards b by the fraction f, the short way round."
yaw_toward(a, b, f) = a + f * (mod(b - a + Float32(pi), 2.0f0 * Float32(pi)) - Float32(pi))

"""
s180: after a jump into the pond at `at` (from `from`): `under` seconds under water while it turns round to face the
`edge`, then it swims there at ~1.1 m/s, rising as it goes. `t` = seconds since it hit the water. True when it is out.
"""
function swim_back!(x, from, at, edge, t, under)
    hd = NG.species_of(x).heading
    ya = atan(at[2] - from[2], at[1] - from[1]) - hd           # the way it flew in
    yb = atan(edge[2] - at[2], edge[1] - at[1]) - hd           # the way out
    if t < under
        x.pos = at - Point3f(0, 0, 0.4f0)
        x.yaw = yaw_toward(ya, yb, clamp(t / under, 0.0f0, 1.0f0))
        return false
    end
    dur = max(hypot(edge[1] - at[1], edge[2] - at[2]) / 1.1f0, 0.5f0)
    e = clamp((t - under) / dur, 0.0f0, 1.0f0); e = e * e * (3 - 2e)
    x.pos = at + (edge - at) * e - Point3f(0, 0, 0.4f0 * (1 - e))
    x.yaw = yb
    e < 1 && (x.action = :walk; x.goal.action = :walk)
    return e >= 1
end

"""
Everybody in (s89): after Lumi's big one the judges and all the divers jump in at once from round the pond,
each to its own spot in the water, a dozen rings crossing on the real water, and they come up laughing.
"""
function all_in!(s::Splash, game, el)
    A = get(SP, :allin, nothing); A === nothing && return
    w = game.world; P = pond(game); R = pond_r(game); lvl = level!(game)
    if el >= 2.2 && !SP[:allin_go]
        SP[:allin_go] = true
        ids = vcat(s.judges, s.crew)
        for (i, id) in enumerate(ids)
            x = NG.creature(w, id); (x === nothing || x.controlled) && continue
            a = atan(x.pos[2] - P[2], x.pos[1] - P[1]) + 0.4f0 * (rand(w.rng, Float32) - 0.5f0)
            r = R * (0.2f0 + 0.4f0 * rand(w.rng, Float32))
            A[id] = (x.pos, Point3f(P[1] + r * cos(a), P[2] + r * sin(a), lvl), w.t + 0.35 * rand(w.rng))
            NG.say!(w, x, x.name == "Lumi" ? "JUDGES TOO! EVERYBODY IN!" : ALLIN[mod1(i, length(ALLIN))]; duration = 1.5)
        end
        push!(SP[:log], (w.t, :allin))
    end
    L = SP[:allin_landed]::Set{Int32}
    for (id, (from, land, since)) in collect(A)
        x = NG.creature(w, id); x === nothing && (delete!(A, id); continue)
        Ta = max(0.95f0, hypot(land[1] - from[1], land[2] - from[2]) / 6.0f0)   # s180: <= ~6 m/s across
        u = Float32((w.t - since) / Ta)
        u < 0 && continue
        if u < 1
            x.pos = from + (land - from) * u + Point3f(0, 0, 2.0f0 * 4u * (1 - u))
            x.action = :jump; x.goal.action = :jump
            x.yaw = atan(land[2] - from[2], land[1] - from[1]) - NG.species_of(x).heading
        else
            # s180: under for a moment, turning round down there, then it SWIMS to the edge (it used to pop up at the edge
            # in one frame: live_motion saw 0.67 m jumps, 20 m/s and 179 deg turns in one frame)
            back = NG.ground(w.island, (from[1], from[2]))
            c = Point3f(P[1], P[2], lvl)
            edge = c + 0.9f0 * (back - c)
            u < 1.8f0 && (id in L || (push!(L, id); splash!(s, w, land, 1.15f0; log = true)))
            if swim_back!(x, from, land, edge, Float32(w.t - since) - Ta, 0.76f0)
                delete!(A, id)
                x.goal = NG.Goal(:cannonball, back, :laugh, 60.0, w.t + 60, false, 0, false); x.action = :laugh
            end
        end
    end
end

function finish!(s::Splash, w)
    for id in vcat(s.crew, s.judges)
        x = NG.creature(w, id)
        x === nothing || x.controlled || x.goal.kind !== :cannonball || NG.choose_goal!(x, w)
    end
    empty!(s.crew); empty!(s.judges); empty!(s.flights)
    delete!(SP, :allin); delete!(SP, :allin_go); delete!(SP, :allin_landed); delete!(SP, :score_at)
    s.state = :idle
    NG.emit!(w, :splash_end)
end


# ------------------------------------------------------------------ the water fight (s87)

const FIGHT_T = 18.0
const EEKS = ("EEK!", "Hey!!", "COLD!", "You'll pay for that!", "Bleh, pond water!", "Got you back!")

"A scoop of water flung from `from` towards `to`: a fan of drops on arcs that land about there in 0.6 s."
function throw!(w, from::Point3f, to::Point3f, who::Int32; n = 16)
    th = get!(() -> Tuple{Point3f,Vec3f,Int32}[], SP, :throws)
    T = 0.6f0
    for i in 1:n
        jit = Vec3f(0.6f0 * (rand(w.rng, Float32) - 0.5f0), 0.6f0 * (rand(w.rng, Float32) - 0.5f0), 0.3f0 * rand(w.rng, Float32))
        d = (to + jit) - from
        v = Vec3f(d[1] / T, d[2] / T, (d[3] + 0.5f0 * 9.8f0 * T^2) / T) * (0.9f0 + 0.2f0 * rand(w.rng, Float32))
        push!(th, (from, v, who))
    end
    length(th) > 400 && deleteat!(th, 1:length(th) - 400)
    push!(get!(() -> Tuple{Float64,Symbol}[], SP, :log), (w.t, :throw))
end

"The flung water flies; a drop that hits someone (not the one who threw it) soaks them, and they answer."
function throws!(s::Splash, game, dt)
    th = get(SP, :throws, nothing)
    (th === nothing || isempty(th)) && return
    w = game.world; lvl = level!(game)
    dt = Float32(clamp(dt, 0, 0.05))
    keep = Tuple{Point3f,Vec3f,Int32}[]
    F = get(SP, :fight, nothing)
    for (p, v, who) in th
        v = v + Vec3f(0, 0, -9.8f0 * dt); p = p + v * dt
        hit = false
        for c in w.creatures
            c.id == who && continue
            norm(p - (c.pos + Point3f(0, 0, 0.55f0))) < 0.45f0 || continue
            hit = true
            if w.t - get(get!(() -> Dict{Int32,Float64}(), SP, :soaked), c.id, -Inf) > 1.2
                SP[:soaked][c.id] = w.t
                NG.say!(w, c, c.name == "Lumi" ? "WAH! Right in the beak!" : EEKS[mod1(Int(c.id) + length(SP[:soaked]), length(EEKS))]; duration = 1.4)
                push!(SP[:log], (w.t, :hit))
                NG.emit!(w, :waterfight_hit; who = c.name)
                if !c.controlled
                    c.action = :jump
                    F === nothing || (F[:answer][c.id] = (w.t + 0.7, who))      # and splashes back
                end
            end
            break
        end
        hit && continue
        if p[3] < lvl && v[3] < 0
            rand(w.rng) < 0.15 && push!(s.rings, (Point2f(p[1], p[2]), w.t, 0.3f0))
            continue
        end
        p[3] < NG.terrain_height(w.island, p[1], p[2]) - 0.1f0 && continue
        push!(keep, (p, v, who))
    end
    SP[:throws] = keep
end

"Pond spots for the fighters: a loose ring inside the water."
fight_spot(game, i, n) = (P = pond(game); a = 2f0 * Float32(pi) * (i - 1) / n + 0.5f0;
                          NG.ground(game.world.island, (P[1] + 1.35f0 * cos(a), P[2] + 1.35f0 * sin(a))))

function start_fight!(s::Splash, game)
    w = game.world
    me = lumi_of(w)
    (me === nothing || me.controlled || me.goal.kind in EVENTS || me.action === :sleep) && return false
    P = pond(game)
    free(x) = !x.controlled && x.action !== :sleep && x.goal.kind ∉ EVENTS && (x.goal.kind ∉ NG.BUSY_GOALS || x.goal.kind in PULL) && x !== me
    cs = sort([x for x in w.creatures if free(x) && hypot(x.pos[1] - P[1], x.pos[2] - P[2]) < 60]; by = x -> hypot(x.pos[1] - P[1], x.pos[2] - P[2]))
    cs = cs[1:min(end, 4)]
    length(cs) < 3 && return false
    crew = Int32[[x.id for x in cs]; me.id]
    for (i, id) in enumerate(crew)
        x = NG.creature(w, id)
        NG.leave_interactions!(w, x)
        x.goal = NG.Goal(:waterfight, fight_spot(game, i, length(crew)), :idle, 120.0, w.t + 120, false, 0, true)
    end
    SP[:fight] = Dict{Symbol,Any}(:crew => crew, :t0 => w.t, :next => Dict{Int32,Float64}(id => w.t + 3.0 + 0.6i for (i, id) in enumerate(crew)),
                                  :answer => Dict{Int32,Tuple{Float64,Int32}}(), :finale => false)
    SP[:log] = Tuple{Float64,Symbol}[(w.t, :fight)]
    delete!(SP, :view); contest_view(game)
    NG.say!(w, me, "Last one in the pond is a soggy cabbage!"; duration = 2.8)
    NG.emit!(w, :waterfight_start; n = length(crew))
    return true
end

function step_fight!(s::Splash, game, dt)
    F = get(SP, :fight, nothing)
    F === nothing && return
    w = game.world; P = pond(game)
    el = w.t - F[:t0]
    crew = F[:crew]
    FT = get(SP, :fight_t, FIGHT_T)::Float64
    me = lumi_of(w)
    for (i, id) in enumerate(crew)        # called back if another event took them; facing whoever is next
        x = NG.creature(w, id)
        (x === nothing || x.controlled) && continue
        x.goal.kind === :waterfight || (NG.leave_interactions!(w, x);
            x.goal = NG.Goal(:waterfight, fight_spot(game, i, length(crew)), :idle, 120.0, w.t + 120, false, 0, true))
        x.goal.until = w.t + 60
    end
    pos(id) = (x = NG.creature(w, id); x === nothing ? nothing : x.pos)
    if el < FT - 4
        for id in crew
            x = NG.creature(w, id)
            (x === nothing || x.controlled || !x.goal.arrived) && continue
            ans = get(F[:answer], id, nothing)
            target = nothing
            if ans !== nothing && w.t >= ans[1]
                target = ans[2]; delete!(F[:answer], id)
            elseif w.t >= get(F[:next], id, Inf)
                others = [o for o in crew if o != id]
                target = others[rand(w.rng, 1:length(others))]
            end
            target === nothing && continue
            tp = pos(target); tp === nothing && continue
            F[:next][id] = w.t + 1.6 + 1.6rand(w.rng)
            x.yaw = atan(tp[2] - x.pos[2], tp[1] - x.pos[1]) - NG.species_of(x).heading
            x.action = :wave; x.goal.action = :wave
            throw!(w, x.pos + Point3f(0, 0, 0.6f0), tp + Point3f(0, 0, 0.55f0), id)
        end
    elseif !F[:finale] && me !== nothing
        # the finale: everyone turns on Lumi at once
        F[:finale] = true
        for id in crew
            id == me.id && continue
            x = NG.creature(w, id); x === nothing && continue
            x.yaw = atan(me.pos[2] - x.pos[2], me.pos[1] - x.pos[1]) - NG.species_of(x).heading
            x.action = :wave
            throw!(w, x.pos + Point3f(0, 0, 0.6f0), me.pos + Point3f(0, 0, 0.6f0), id; n = 24)
        end
        NG.say!(w, NG.creature(w, crew[1]), "EVERYBODY GET LUMI!"; duration = 2.0)
        push!(SP[:log], (w.t, :finale))
    elseif el >= FT
        for id in crew
            x = NG.creature(w, id)
            x === nothing || x.controlled || x.goal.kind !== :waterfight || NG.choose_goal!(x, w)
        end
        me === nothing || NG.say!(w, me, "...I give up. I am one hundred percent pond."; duration = 3.0)
        delete!(SP, :fight)
        NG.emit!(w, :waterfight_end)
    end
end

"Q as Lumi near the pond flings a scoop of water the way you face (the friends answer when they are hit)."
function player_throw!(s::Splash, game)
    w = game.world; me = lumi_of(w)
    (me === nothing || !me.controlled) && return
    q = NG.Makie.Keyboard.q in game.keys_down
    was = get(SP, :q_down, false); SP[:q_down] = q
    (q && !was) || return
    P = pond(game)
    hypot(me.pos[1] - P[1], me.pos[2] - P[2]) < pond_r(game) + 1.5f0 || return
    a = me.yaw
    throw!(w, me.pos + Point3f(0, 0, 0.6f0), me.pos + Point3f(3f0 * cos(a), 3f0 * sin(a), 0.4f0), me.id; n = 20)
    splash!(s, w, Point3f(me.pos[1], me.pos[2], level!(game)), 0.5f0)
end

function NG.step!(s::Splash, game, dt)
    game.stage === nothing && return
    plots!(game)
    w = game.world
    P = pond(game); lvl = level!(game)
    waders!(s, game)
    drops!(s, game, dt)
    throws!(s, game, dt)
    step_fight!(s, game, dt)
    player_throw!(s, game)
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
        # the water fight: once a late morning, or for a film
        ff = get(SP, :film_fight, false)
        if !haskey(SP, :fight) && (ff || day != get(SP, :fight_day, -1) && 11.5 < 24 * NG.daytime(w) < 13.5) && !testing && !busy_game &&
           w.t >= get(SP, :fight_try, -Inf)
            SP[:fight_try] = w.t + 5
            if (ff || party_free(w)) && start_fight!(s, game)
                SP[:fight_day] = day; SP[:film_fight] = false; claim_party!(w, 25)
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
                # s180: no faster than ~6 m/s across the ground (a creature still far from the edge flew at 16-26 m/s)
                T = max(big ? 1.3 : 0.9, hypot(c[1] - from[1], c[2] - from[2]) / 6.0)
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
                else
                    # s180: under the water for a moment (turning round), then it swims back to the edge (was a pop)
                    back = NG.ground(w.island, (from[1], from[2]))
                    if swim_back!(x, from, c, c + 0.92f0 * (back - c), Float32(w.t - since) - Float32(T), 0.6f0)
                        delete!(s.flights, id)
                        x.goal = NG.Goal(:cannonball, back, :laugh, 60.0, w.t + 60, false, 0, false); x.action = :laugh
                    end
                end
            end
            scores!(s, w)
            if s.next > length(s.crew) && isempty(s.flights) && w.t >= SP[:next_at] - 1.0
                s.state = :after; s.t0 = w.t
                me = lumi_of(w)
                me === nothing || NG.say!(w, me, "...Did I win? I'm soaked!"; duration = 1.6)
                SP[:allin] = Dict{Int32,Tuple{Point3f,Point3f,Float64}}(); SP[:allin_go] = false; SP[:allin_landed] = Set{Int32}()
            end
        elseif s.state === :after
            scores!(s, w)
            all_in!(s, game, el)
            w.t - s.t0 >= (haskey(SP, :allin) ? 8.0 : 4.0) && finish!(s, w)
        end
    end
    draw!(s, game)
end

function splash_group(w)
    s = SP[:sys]
    (s.state in (:gather, :dive, :after) || haskey(SP, :fight)) || return nothing
    me = lumi_of(w)
    (me === nothing || me.controlled) && return nothing
    v = get(SP, :view, nothing)
    v === nothing && return nothing
    return (me.id, Point3f[v[2], me.pos], v)
end

"The pond's floor to wade on (the engine's step refuses ground this close to the sea without it, s86-87)."
function pond_floor(game)
    A = game.plugins["areas"].mod; P = A.POND; R = A.POND_R; isl = game.world.island
    (x, y) -> hypot(x - P[1], y - P[2]) < R + 0.9f0 ? NG.terrain_height(isl, x, y) : nothing   # the low sandy bank too
end

function NG.start!(s::Splash, game)
    SP[:sys] = s
    NG.WALKWAYS["pond"] = pond_floor(game)
    for k in (:rings, :drops, :level, :view)
        delete!(SP, k)
    end
    SP[:rings_shown] = true; SP[:drops_shown] = true
    SP[:start] = () -> start_contest!(s, game)
    moment = w -> (s.state in (:gather, :dive, :after) || haskey(SP, :fight)) ? (m = lumi_of(w); m === nothing ? nothing : m.id) : nothing
    NG.CAMERA_MOMENTS["splash"] = moment
    isdefined(Main, :BIG_MOMENTS) || Core.eval(Main, :(const BIG_MOMENTS = Dict{String,Any}()))
    Main.BIG_MOMENTS["splash"] = moment
    NG.CAMERA_GROUPS["splash"] = splash_group
end

function NG.stop!(s::Splash, game)
    delete!(NG.WALKWAYS, "pond")
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
