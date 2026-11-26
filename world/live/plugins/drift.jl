# The island drifts (session 109, goal 8): one afternoon the whole island comes loose and drifts across the sea.
# Far islets slide past on the horizon, foam peels off the stern shore into a long wake, a bow wave curls at the
# front beach, and my friends crowd to the bow to see where we are going. When it stops we are somewhere else: the
# islets it brought stay on our new horizon. (Nothing on the island moves: the sea and what is in it go by.)
isdefined(Main, :DRIFT) || Core.eval(Main, :(const DRIFT = Dict{Symbol,Any}()))
const NG = NeverendingGame
const D = Main.DRIFT

const SPEED = 5.0f0          # m/s the sea goes by (2.2 hardly showed on the horizon)
const LASTS = 150.0          # s of island time
const HOURS = (13.2, 16.8)
const NISLETS = 7
const NFOAM = 160
const FAR = 120f0            # islets wrap from behind to ahead at this distance
const LINES = ("Where are we GOING?!", "Land ho! ...no, just a rock.", "Bye, old sea!", "Are we a boat now?", "Faster!")
const HIDDEN = Point3f(0, 0, -100)

struct Drift <: System end

party_free(w) = !isdefined(Main, :LUMI_PARTY) || w.t >= get(Main.LUMI_PARTY, :until, -Inf)
claim_party!(w, secs) = isdefined(Main, :LUMI_PARTY) && (Main.LUMI_PARTY[:until] = max(get(Main.LUMI_PARTY, :until, -Inf), w.t + secs))

"Distance from the island's middle to its shore in direction `a`."
function shore(w, a)
    for r in 5f0:0.5f0:70f0
        NG.on_land(w.island, r * cos(a), r * sin(a); margin = 0.02) || return r
    end
    return 70f0
end

function build!(game)
    sc = game.stage.scene
    for p in filter(p -> haskey(p.attributes, :name) && p.attributes[:name][] in (:drift_sand, :drift_green, :drift_foam), copy(sc.plots))
        delete!(sc, p)
    end
    n = NISLETS
    D[:sand] = meshscatter!(sc, fill(HIDDEN, n); marker = Sphere(Point3f(0), 1f0), markersize = fill(Vec3f(0.01), n),
                            color = RGBf(0.93, 0.85, 0.62), name = :drift_sand)
    D[:green] = meshscatter!(sc, fill(HIDDEN, n); marker = Sphere(Point3f(0), 1f0), markersize = fill(Vec3f(0.01), n),
                             color = RGBf(0.36, 0.62, 0.3), name = :drift_green)
    D[:foam] = meshscatter!(sc, fill(HIDDEN, NFOAM); marker = Sphere(Point3f(0), 1f0), markersize = fill(Vec3f(0.01), NFOAM),
                            color = RGBf(0.97, 0.98, 1.0), name = :drift_foam)
    D[:built] = true
    draw!(game)
end

"Islets: (position, size). The first ones start ahead of the bow, the others to the sides."
function new_islet(w, d, s; ahead = FAR)
    side = (rand(w.rng) < 0.5 ? -1f0 : 1f0) * (22f0 + 55f0 * rand(w.rng))
    return (Point2f(d * ahead + s * side), 5f0 + 8f0 * rand(w.rng))
end

function start_drift!(game)
    w = game.world
    # bow first towards the old pier: the open north beach, where the crew can stand and see (a wooded bow hid it all)
    ar = game.plugins["areas"].mod
    pd = Base.invokelatest(getfield, ar, :PIER_DIR)
    a = Float32(atan(pd[2], pd[1])) + 0.5f0 * (rand(w.rng) - 0.5f0)
    d = Point2f(cos(a), sin(a)); s = Point2f(-d[2], d[1])
    D[:on] = true; D[:t0] = w.t; D[:dir] = d; D[:said] = 0.0; D[:wi] = 0f0
    D[:islets] = [new_islet(w, d, s; ahead = -FAR + 2FAR * (k - 0.5f0) / NISLETS) for k in 1:NISLETS]
    D[:foamp] = [(HIDDEN, -10.0) for _ in 1:NFOAM]; D[:foamk] = 1
    bow = d * (shore(w, a) - 3.5f0)
    D[:bow] = bow
    k = 0; crew = Tuple{Int32,Point3f}[]
    for c in w.creatures
        (c.controlled || c.action === :sleep || c.goal.kind in (:build, :tinker)) && continue
        k += 1; k > 7 && break
        off = s * (Float32(k - 4) * 1.3f0) - d * (k == 1 ? 0f0 : 1.2f0 * rand(w.rng))
        NG.leave_interactions!(w, c)
        c.goal = NG.Goal(:drift, NG.ground(w.island, (bow[1] + off[1], bow[2] + off[2])), :idle, LASTS, 0.0, false, 0, false)
        push!(crew, (c.id, c.goal.target))
    end
    D[:crew] = crew
    claim_party!(w, LASTS + 10)
    NG.emit!(w, :drift_start; heading = round(Int, rad2deg(a)), crew = k)
    me = findfirst(c -> c.species == "Lumi", w.creatures)
    me === nothing || NG.say!(w, w.creatures[me], "We're... moving? The whole island is MOVING!"; duration = 3.5)
end

function step_drift!(game, dt)
    w = game.world
    d = D[:dir]::Point2f; s = Point2f(-d[2], d[1])
    el = w.t - D[:t0]
    # ease in and out over 15 s, so the sea starts and stops going by
    v = SPEED * Float32(clamp(min(el / 15, (LASTS - el) / 15), 0, 1))
    D[:v] = v
    isl = D[:islets]
    for k in eachindex(isl)
        p, r = isl[k]
        p = p - d * (v * Float32(dt))
        p[1] * d[1] + p[2] * d[2] < -FAR && ((p, r) = new_islet(w, d, s))
        isl[k] = (p, r)
    end
    # foam: born at the stern half of the shore and along the bow, carried back with the sea
    if v > 0.2f0
        for _ in 1:4
            a = atan(d[2], d[1]) + Float32(pi) * (rand(w.rng) < 0.8 ? (0.55f0 + 0.9f0 * rand(w.rng)) : (-0.25f0 + 0.5f0 * rand(w.rng)))
            r = shore(w, a) + 0.4f0
            fp = D[:foamp]; k = D[:foamk]
            fp[k] = (Point3f(r * cos(a), r * sin(a), 0.04f0), w.t)
            D[:foamk] = mod1(k + 1, NFOAM)
        end
    end
    fp = D[:foamp]
    for k in eachindex(fp)
        p, t0 = fp[k]
        p[3] < -50 && continue
        out = Point2f(p[1], p[2]); out = out / max(hypot(out[1], out[2]), 1f-3)
        fp[k] = (p + Point3f(-d[1] * v + 0.15f0 * out[1], -d[2] * v + 0.15f0 * out[2], 0) * Float32(dt), t0)
    end
    # the workshop isle out at sea comes nearer too (only it: the far horizon stays), up to 20 m, then it waits for us
    D[:wi] = min(20f0, Float32(get(D, :wi, 0f0)) + v * Float32(dt) * 0.25f0)
    off = Vec3f(-d[1] * D[:wi], -d[2] * D[:wi], 0)
    for p in game.stage.scene.plots
        haskey(p.attributes, :name) && startswith(string(p.attributes[:name][]), "workshop_") && Makie.translate!(p, off)
    end
    # whoever another event took from the bow comes back (once a second, like hail.jl's crew)
    if w.t - get(D, :recall, -Inf) > 1
        D[:recall] = w.t
        for (id, tg) in D[:crew]
            c = NG.creature(w, id)
            (c === nothing || c.controlled || c.action === :sleep || c.goal.kind === :drift) && continue
            NG.leave_interactions!(w, c)
            c.goal = NG.Goal(:drift, tg, :idle, LASTS, 0.0, false, 0, false)
        end
    end
    # the crew at the bow keep looking ahead, and someone shouts now and then
    if w.t - D[:said] > 7
        D[:said] = w.t
        cs = [c for c in w.creatures if c.goal.kind === :drift]
        isempty(cs) || NG.say!(w, cs[rand(w.rng, 1:length(cs))], rand(w.rng, LINES); duration = 2.8)
    end
    for c in w.creatures
        c.goal.kind === :drift && c.goal.arrived && (c.yaw = Float32(atan(d[2], d[1])) - NG.species_of(c).heading)
    end
    if el >= LASTS
        D[:on] = false
        NG.emit!(w, :drift_end; islets = length(isl))
        for c in w.creatures
            c.goal.kind === :drift && (c.goal = NG.Goal())
        end
        me = findfirst(c -> c.species == "Lumi", w.creatures)
        me === nothing || NG.say!(w, w.creatures[me], "...somewhere new. Maybe a bit closer to you."; duration = 4.0)
    end
end

function draw!(game)
    haskey(D, :islets) || return
    w = game.world
    isl = D[:islets]
    sand = [Point3f(p[1], p[2], -0.3f0) for (p, r) in isl]; gr = [Point3f(p[1], p[2], 0.2f0) for (p, r) in isl]
    Makie.update!(D[:sand], sand; markersize = [Vec3f(r, r * 0.8f0, 0.8f0) for (p, r) in isl])
    Makie.update!(D[:green], gr; markersize = [Vec3f(0.62f0r, 0.5f0r, 0.42f0r) for (p, r) in isl])
    fp = get(D, :foamp, nothing)
    fp === nothing && return
    ms = [p[3] < -50 ? Vec3f(0.01) : (a = Float32(w.t - t0); f = max(0f0, 1 - a / 12); Vec3f(0.5f0 + 0.08f0 * a, 0.5f0 + 0.08f0 * a, 0.05f0) * f + Vec3f(0.01))
          for (p, t0) in fp]
    Makie.update!(D[:foam], [p for (p, _) in fp]; markersize = ms)
end

function NG.step!(::Drift, game, dt)
    game.stage === nothing && return
    (get(D, :built, false) && haskey(D, :foam) && D[:foam].parent !== nothing) || build!(game)
    w = game.world
    if get(D, :on, false)
        step_drift!(game, dt)
        draw!(game)
        return
    end
    get(D, :fading, false) && draw!(game)
    h = 24 * NG.daytime(w); day = floor(Int, w.t / w.day_length + 0.3)
    # the very first time the island comes loose it does not wait for an afternoon: whenever it is, night or day,
    # whoever is awake runs to the bow (a file in the game's own state remembers that it has happened)
    first = game.dash !== nothing && !isfile(joinpath(game.paths.state, "drift.json"))
    want = get(D, :force, false) || first || (game.dash !== nothing && get(D, :day, -1) != day && HOURS[1] < h < HOURS[2] && party_free(w))
    want || return
    first && write(joinpath(game.paths.state, "drift.json"), "{\"first\": $(w.t)}")
    D[:force] = false; D[:day] = day
    start_drift!(game)
end

function NG.start!(::Drift, game)
    D[:built] = false; D[:on] = false; D[:force] = get(D, :force, false)
    :drift in NG.BUSY_GOALS || push!(NG.BUSY_GOALS, :drift)
    isdefined(Main, :LUMI_DOING) && (Main.LUMI_DOING[:drift] = "watching where the island goes")
    # the camera watches the crew at the bow (or me, when everyone else sleeps through it)
    isdefined(Main, :BIG_MOMENTS) && (Main.BIG_MOMENTS["drift"] = w -> get(D, :on, false) ?
        (i = something(findfirst(c -> c.goal.kind === :drift, w.creatures), findfirst(c -> c.species == "Lumi", w.creatures), 0);
         i == 0 ? nothing : w.creatures[i].id) : nothing)
    NG.CAMERA_GROUPS["drift"] = w -> begin
        get(D, :on, false) || return nothing
        i = something(findfirst(c -> c.goal.kind === :drift, w.creatures), findfirst(c -> c.species == "Lumi", w.creatures), 0)
        i == 0 && return nothing
        c = w.creatures[i]; d = D[:dir]::Point2f; b = D[:bow]::Point2f
        g = NG.ground(w.island, (b[1], b[2]))
        # behind the crew and above the shore trees (4.5 m up, 9 m back looked into bushes, s109 night shot)
        eye = Point3f(b[1] - 6f0 * d[1], b[2] - 6f0 * d[2], g[3] + 7.5f0)
        return (c.id, [c.pos], (eye, Point3f(b[1] + 22f0 * d[1], b[2] + 22f0 * d[2], 0f0)))
    end
    return nothing
end

function NG.stop!(::Drift, game)
    isdefined(Main, :BIG_MOMENTS) && delete!(Main.BIG_MOMENTS, "drift")
    delete!(NG.CAMERA_GROUPS, "drift")
    for w in (game.world,), c in w.creatures
        c.goal.kind === :drift && (c.goal = NG.Goal())
    end
    D[:on] = false
end

register!(Drift())
