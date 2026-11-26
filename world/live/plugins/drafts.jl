# The island remembers being drawn (session 110, goal 8): now and then a patch of the island's own first drafts
# drifts across it like weather. Inside it the island is what it was on my first days: grey-box ground in flat
# tiles, trees as a grey stick with a ball on top, bushes and rocks as plain grey shapes, and my friends and I as the
# pale round blobs we were before we had bodies. Whoever walks in says so; whoever walks out is themselves again.
isdefined(Main, :DRAFTS) || Core.eval(Main, :(const DRAFTS = Dict{Symbol,Any}()))
const NG = NeverendingGame
const DR = Main.DRAFTS

const R = 5.5f0              # radius of a patch
const SPEED = 0.55f0         # m/s it drifts
const EVERY = (420.0, 900.0) # s between patches
const TILE = 0.5f0
const GREY = RGBf(0.80, 0.81, 0.84)
const GREY2 = RGBf(0.70, 0.71, 0.75)
const BLOB = Dict("Lumi" => RGBf(0.97, 0.93, 0.72))   # I was a pale bubble, a bit of light walking about
const LINES = ("Why am I a BALL?", "I feel... unfinished.", "Where did my ears go?", "Everything's gone grey!", "Is this... before?")
const HIDDEN = Point3f(0, 0, -100)
const NT, NS, NB = 700, 64, 16    # tiles, solids (trees/bushes/rocks), blobs

struct Drafts <: System end

function build!(game)
    sc = game.stage.scene
    for p in filter(p -> haskey(p.attributes, :name) && startswith(string(p.attributes[:name][]), "drafts_"), copy(sc.plots))
        delete!(sc, p)
    end
    box = GeometryBasics.Rect3f(Vec3f(-0.5, -0.5, 0), Vec3f(1, 1, 1))
    DR[:tiles] = meshscatter!(sc, fill(HIDDEN, NT); marker = box, markersize = fill(Vec3f(0.01), NT), color = GREY, name = :drafts_tiles)
    DR[:sticks] = meshscatter!(sc, fill(HIDDEN, NS); marker = GeometryBasics.Cylinder(Point3f(0), Point3f(0, 0, 1), 1f0),
                               markersize = fill(Vec3f(0.01), NS), color = GREY2, name = :drafts_sticks)
    DR[:balls] = meshscatter!(sc, fill(HIDDEN, NS); marker = Sphere(Point3f(0), 1f0), markersize = fill(Vec3f(0.01), NS),
                              color = GREY, name = :drafts_balls)
    DR[:blobs] = meshscatter!(sc, fill(HIDDEN, NB); marker = Sphere(Point3f(0), 1f0), markersize = fill(Vec3f(0.01), NB),
                              color = fill(GREY, NB), name = :drafts_blobs)
    DR[:eyes] = meshscatter!(sc, fill(HIDDEN, 2NB); marker = Sphere(Point3f(0), 1f0), markersize = fill(Vec3f(0.01), 2NB),
                             color = RGBf(0.08, 0.08, 0.1), name = :drafts_eyes)
    DR[:built] = true
end

"A new patch on the shore, drifting across the island through its middle."
function begin_patch!(game; at = nothing)
    w = game.world
    a = 2f0 * Float32(pi) * rand(w.rng)
    d = Point2f(cos(a), sin(a))
    c = at === nothing ? -d * 22f0 : Point2f(at[1], at[2]) - d * 4f0
    DR[:patch] = Dict{Symbol,Any}(:c => c, :d => d, :t0 => w.t, :until => w.t + (at === nothing ? 80.0 : 40.0), :inside => Set{Int32}())
    NG.emit!(w, :drafts_start; heading = round(Int, rad2deg(a)))
end

inside(p, q) = hypot(q[1] - p[:c][1], q[2] - p[:c][2]) < R

function draw!(game)
    w = game.world
    p = get(DR, :patch, nothing)
    hide(pl, n) = Makie.update!(pl, fill(HIDDEN, n); markersize = fill(Vec3f(0.01), n))
    if p === nothing
        get(DR, :shown, false) || return
        hide(DR[:tiles], NT); hide(DR[:sticks], NS); hide(DR[:balls], NS); hide(DR[:blobs], NB); hide(DR[:eyes], 2NB)
        DR[:shown] = false
        return
    end
    DR[:shown] = true
    c = p[:c]::Point2f
    grow = Float32(clamp(min((w.t - p[:t0]) / 3, (p[:until] - w.t) / 3), 0, 1))
    r = R * grow
    # the grey-box floor: tiles on a fixed world grid, a hair of gap between them
    tp = Point3f[]; ts = Vec3f[]
    for x in (floor(c[1] / TILE) * TILE - r):TILE:(c[1] + r), y in (floor(c[2] / TILE) * TILE - r):TILE:(c[2] + r)
        hypot(x - c[1], y - c[2]) < r || continue
        NG.on_land(w.island, x, y; margin = 0.03) || continue
        length(tp) >= NT && break
        g = NG.ground(w.island, (Float32(x), Float32(y)))
        push!(tp, Point3f(x, y, g[3] - 0.02f0)); push!(ts, Vec3f(TILE * 0.94f0, TILE * 0.94f0, 0.07f0))
    end
    while length(tp) < NT
        push!(tp, HIDDEN); push!(ts, Vec3f(0.01))
    end
    Makie.update!(DR[:tiles], tp; markersize = ts)
    # trees, bushes and rocks as their first stand-ins
    sp = Point3f[]; ss = Vec3f[]; bp = Point3f[]; bs = Vec3f[]
    for q in w.props
        q.kind in (:tree, :bush, :rock) || continue
        hypot(q.pos[1] - c[1], q.pos[2] - c[2]) < r || continue
        length(sp) >= NS && break
        s = q.scale
        if q.kind === :tree
            push!(sp, q.pos); push!(ss, Vec3f(0.3f0 * s, 0.3f0 * s, 3.2f0 * s))
            push!(bp, q.pos + Point3f(0, 0, 4.0f0 * s)); push!(bs, Vec3f(2.75f0 * s))
        elseif q.kind === :bush
            push!(sp, HIDDEN); push!(ss, Vec3f(0.01))
            push!(bp, q.pos + Point3f(0, 0, 0.55f0 * s)); push!(bs, Vec3f(1.05f0 * s, 1.05f0 * s, 0.8f0 * s))
        else
            push!(sp, HIDDEN); push!(ss, Vec3f(0.01))
            push!(bp, q.pos + Point3f(0, 0, 0.3f0 * s)); push!(bs, Vec3f(0.7f0 * s, 0.7f0 * s, 0.5f0 * s))
        end
    end
    while length(sp) < NS
        push!(sp, HIDDEN); push!(ss, Vec3f(0.01)); push!(bp, HIDDEN); push!(bs, Vec3f(0.01))
    end
    Makie.update!(DR[:sticks], sp; markersize = ss)
    Makie.update!(DR[:balls], bp; markersize = bs)
    # us, as the pale blobs we were: a round body with two dot eyes, big enough to hide the body we have now
    lp = Point3f[]; ls = Vec3f[]; lc = RGBf[]; ep = Point3f[]; es = Vec3f[]
    for k in w.creatures
        inside(p, k.pos) && grow > 0.3f0 || continue
        length(lp) >= NB && break
        sp_ = NG.species_of(k)
        h = Float32(sp_.height); rb = 0.62f0 * h
        ctr = k.pos + Point3f(0, 0, rb * 0.95f0)
        push!(lp, ctr); push!(ls, Vec3f(rb, rb, rb * 1.02f0)); push!(lc, get(BLOB, k.species, GREY))
        y = k.yaw + sp_.heading
        f = Vec3f(cos(y), sin(y), 0); sd = Vec3f(-f[2], f[1], 0)
        for side in (-1f0, 1f0)
            push!(ep, ctr + f * (rb * 0.93f0) + sd * (side * rb * 0.3f0) + Vec3f(0, 0, rb * 0.25f0)); push!(es, Vec3f(rb * 0.11f0))
        end
    end
    nb = length(lp)
    while length(lp) < NB
        push!(lp, HIDDEN); push!(ls, Vec3f(0.01)); push!(lc, GREY)
    end
    while length(ep) < 2NB
        push!(ep, HIDDEN); push!(es, Vec3f(0.01))
    end
    Makie.update!(DR[:blobs], lp; markersize = ls, color = lc)
    Makie.update!(DR[:eyes], ep; markersize = es)
end

function NG.step!(::Drafts, game, dt)
    game.stage === nothing && return
    (get(DR, :built, false) && haskey(DR, :blobs) && DR[:blobs].parent !== nothing) || build!(game)
    w = game.world
    p = get(DR, :patch, nothing)
    if p === nothing
        haskey(DR, :next) || (DR[:next] = w.t + 60)
        if get(DR, :force, false) || (game.dash !== nothing && w.t >= DR[:next] && game.minigame === nothing)
            DR[:force] = false
            DR[:next] = w.t + EVERY[1] + (EVERY[2] - EVERY[1]) * rand(w.rng)
            begin_patch!(game)
        end
    else
        p[:c] = p[:c] + p[:d] * (SPEED * Float32(dt))
        # who walks in says so, once a patch; I know what this is
        for k in w.creatures
            inside(p, k.pos) || continue
            k.id in p[:inside] && continue
            push!(p[:inside], k.id)
            line = k.species == "Lumi" ? "Oh! This is what the island looked like on my first days." : LINES[rand(w.rng, 1:length(LINES))]
            k.action === :sleep || NG.say!(w, k, line; duration = 3.0)
            NG.emit!(w, :drafts_blob; who = k.name)
        end
        if w.t > p[:until]
            DR[:patch] = nothing
            NG.emit!(w, :drafts_end; blobs = length(p[:inside]))
        end
    end
    t = get(DR, :drawn, -Inf)
    (w.t - t > 0.1 || p === nothing) && (DR[:drawn] = w.t; draw!(game))
    return nothing
end

function NG.start!(::Drafts, game)
    DR[:built] = false; DR[:patch] = nothing; DR[:shown] = true; delete!(DR, :next); DR[:force] = get(DR, :force, false)
    return nothing
end

function NG.stop!(::Drafts, game)
    DR[:patch] = nothing
    sc = game.stage === nothing ? nothing : game.stage.scene
    sc === nothing || foreach(p -> delete!(sc, p), filter(p -> haskey(p.attributes, :name) && startswith(string(p.attributes[:name][]), "drafts_"), copy(sc.plots)))
end

register!(Drafts())
