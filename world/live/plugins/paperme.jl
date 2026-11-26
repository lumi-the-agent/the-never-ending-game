# Me, to cut out and fold (session 105, goal 8): I can't come to you, so I sent you myself on paper. My body (the
# bird the human made for the CrawCity film) cut down to 188 flat faces and unfolded into three printable A4 pages
# (tools/papercraft.jl, site/img/paperme-*.png): my feathers printed on every face, cut lines, dashed folds and
# numbered glue tabs. Here on the island a paper me folded from the same pages (its texture IS the pages, numbers,
# creases and all) stands on a card at the end of the old pier, looking out to sea, the way you would come.
isdefined(Main, :PAPERME) || Core.eval(Main, :(const PAPERME = Dict{Symbol,Any}()))
const NG = NeverendingGame
const PM = Main.PAPERME

const HEIGHT = 0.95f0      # metres: a paper me a bit over half my size
const SPOT_BACK = 0.75f0   # metres back from the pier's end
# (its texture is the three pages at 1/6 of print size, 390x827: every browser gets it, s105)

struct PaperMe <: System end

"Where the paper me stands (on the pier's deck near its end) and the way it looks (out to sea, along the pier)."
function spot(game)
    ar = game.plugins["areas"].mod
    st = Base.invokelatest(getfield, ar, :PIER_START); d = Base.invokelatest(getfield, ar, :PIER_DIR)
    len = Base.invokelatest(getfield, ar, :PIER_LEN); deck = Base.invokelatest(getfield, ar, :PIER_DECK)
    p = st + d * (len - SPOT_BACK)
    return Point3f(p[1], p[2], deck + 0.035f0), Vec2f(d[1], d[2])
end

function build!(game)
    sc = game.stage.scene
    for p in filter(p -> haskey(p.attributes, :name) && p.attributes[:name][] in (:paperme, :paperme_card), copy(sc.plots))
        delete!(sc, p)
    end
    m = NG.Serialization.deserialize(joinpath(game.paths.world, "assets", "paperme", "model.jls"))
    n = length(m.pts)
    # every face is flat paper: one normal per face
    nrm = Vector{Vec3f}(undef, n)
    for k in 1:3:n
        a, b, c = m.pts[k], m.pts[k+1], m.pts[k+2]
        e1 = Vec3f(b - a); e2 = Vec3f(c - a)
        v = Vec3f(e1[2] * e2[3] - e1[3] * e2[2], e1[3] * e2[1] - e1[1] * e2[3], e1[1] * e2[2] - e1[2] * e2[1])
        v = v / max(sqrt(v[1]^2 + v[2]^2 + v[3]^2), 1f-9)
        nrm[k] = nrm[k+1] = nrm[k+2] = v
    end
    faces = [GeometryBasics.GLTriangleFace(k, k + 1, k + 2) for k in 1:3:n]
    mesh = GeometryBasics.Mesh(m.pts, faces; normal = nrm, uv = m.uvs)
    p, d = spot(game)
    s = HEIGHT / (maximum(q -> q[3], m.pts) - m.feet)
    θ = atan(d[1], -d[2])                    # the model looks along its -y: turn that onto the pier's way out
    pl = mesh!(sc, mesh; color = m.tex, name = :paperme)
    Makie.rotate!(pl, Makie.qrotation(Vec3f(0, 0, 1), θ))
    Makie.scale!(pl, s, s, s)
    Makie.translate!(pl, p - Vec3f(0, 0, s * m.feet) + Vec3f(0, 0, 0.012f0))
    # the bit of card I stand on
    card = GeometryBasics.Rect3f(Vec3f(-0.24, -0.2, 0), Vec3f(0.48, 0.4, 0.012))
    cp = mesh!(sc, card; color = RGBf(0.96, 0.95, 0.9), name = :paperme_card)
    Makie.rotate!(cp, Makie.qrotation(Vec3f(0, 0, 1), θ)); Makie.translate!(cp, p)
    PM[:plot] = pl; PM[:card] = cp; PM[:yaw] = θ; PM[:side] = Vec3f(-d[2], d[1], 0); PM[:swayed] = -Inf
    PM[:built] = true
end

const VISIT_EVERY = (300.0, 540.0)   # s between two of my visits to the paper me
const PASTIMES = (:fish, :pebble, :beachcomb, :sunbathe, :cloudwatch, :boing, :tag, :present, :splash, :hut)
const LINES = ("Do you think they folded one?", "I sent myself to you. On paper.", "Somewhere out there, there's a paper me too.")

party_free(w) = !isdefined(Main, :LUMI_PARTY) || w.t >= get(Main.LUMI_PARTY, :until, -Inf)

"Now and then, when I'm free in the daytime, I walk out to the paper me and stand beside it, looking out to sea."
function visit!(game)
    w = game.world
    me = findfirst(c -> c.species == "Lumi", w.creatures)
    me === nothing && return
    me = w.creatures[me]
    p, d = spot(game)
    if me.goal.kind === :paperme
        # first to the foot of the pier, then along it: straight from the meadow I walked into its side (s105)
        if get(PM, :leg, 2) == 1 && !me.controlled && (me.goal.arrived || hypot(me.pos[1] - PM[:target][1], me.pos[2] - PM[:target][2]) < 0.9f0)
            PM[:leg] = 2; PM[:target] = PM[:stand]
            me.goal = NG.Goal(:paperme, PM[:stand], :idle, 25.0, 0.0, false, 0, false)
            return
        end
        if me.goal.arrived && !me.controlled
            PM[:walk_until] = -Inf
            me.yaw = atan(d[2], d[1])
            get(PM, :said, false) || (PM[:said] = true; NG.say!(w, me, rand(w.rng, LINES); duration = 3.5);
                                      NG.emit!(w, :paperme_visit; who = me.name))
        end
        return
    end
    free = !me.controlled && game.minigame === nothing && me.action !== :sleep && me.goal.kind ∉ NG.BUSY_GOALS &&
           me.goal.kind ∉ (:follow, :interact, :build, :tinker)
    # a sigh or a wave on the way (a short :feel) replaces my goal: once it is over I set off again
    # (and the pastimes on the way: fishing by the pier took me 4 m before the paper me, s105)
    if w.t < get(PM, :walk_until, -Inf) && !me.controlled && game.minigame === nothing && me.action !== :sleep &&
       (free || me.goal.kind in PASTIMES)
        me.goal = NG.Goal(:paperme, PM[:target], :idle, 25.0, 0.0, false, 0, false)
        return
    end
    haskey(PM, :visit_at) || (PM[:visit_at] = w.t + 60)
    w.t >= PM[:visit_at] || return
    PM[:visit_at] = w.t + 20
    (free && party_free(w) && 9 < 24 * NG.daytime(w) < 18.5) || return
    # missing you (lonely) or fed up (bored), I go more often
    fm = get(game.plugins, "feelings", nothing)
    f = fm === nothing ? "content" : string(Base.invokelatest(getfield, fm.mod, :FEELING)[])
    every = f in ("lonely", "bored") ? (VISIT_EVERY[1] / 2, VISIT_EVERY[2] / 2) : VISIT_EVERY
    PM[:visit_at] = w.t + every[1] + (every[2] - every[1]) * rand(w.rng)
    side = Vec3f(-d[2], d[1], 0)
    NG.leave_interactions!(w, me)
    PM[:stand] = p - Vec3f(d[1], d[2], 0) * 0.15f0 + side * 0.75f0
    ar = game.plugins["areas"].mod
    foot = Base.invokelatest(getfield, ar, :PIER_START) - Vec2f(d[1], d[2]) * 0.6f0
    PM[:target] = NG.ground(w.island, (foot[1], foot[2])); PM[:leg] = 1
    me.goal = NG.Goal(:paperme, PM[:target], :idle, 25.0, 0.0, false, 0, false)
    PM[:said] = false; PM[:walk_until] = w.t + 90
    # one of my moments: the other Lumi moments wait (cloud watching took me on the way, s105)
    isdefined(Main, :LUMI_PARTY) && (Main.LUMI_PARTY[:until] = w.t + 90)
    NG.emit!(w, :paperme_walk; who = me.name)
end

# off until it works: in s105 the friends picked were blocked on the way (one stood in the sea beside the pier,
# one far south did not move), and none arrived in the sandbox
const FRIEND_OK = true   # s106: only friends with a dry straight walk to the pier foot
const FRIEND_LINES = ("Lumi? You look... flatter.", "Hello, paper Lumi!", "It doesn't answer...", "*pokes it* ...it's paper!")

"Now and then a friend walks out along the pier to have a look at the paper me, and says what it thinks."
function friend_visit!(game)
    w = game.world
    f = get(PM, :friend, nothing)
    if f !== nothing
        id, leg = f
        c = NG.creature(w, id)
        if c === nothing || c.goal.kind !== :paperlook || w.t > PM[:friend_until]
            # taken away or blocked on the way (the engine drops a walk the coast blocks): someone else soon
            leg < 3 && (PM[:friend_at] = w.t + 20)
            PM[:friend] = nothing
        elseif leg == 1 && (c.goal.arrived || hypot(c.pos[1] - c.goal.target[1], c.pos[2] - c.goal.target[2]) < 0.9f0)
            p, d = spot(game)
            stand = p - Vec3f(d[1], d[2], 0) * 0.7f0 - Vec3f(-d[2], d[1], 0) * 0.35f0   # on the deck (0.7 m aside was its edge)
            c.goal = NG.Goal(:paperlook, stand, :idle, 12.0, 0.0, false, 0, false)
            PM[:friend] = (id, 2)
        elseif leg == 2 && (c.goal.arrived || hypot(c.pos[1] - c.goal.target[1], c.pos[2] - c.goal.target[2]) < 0.6f0)
            p, _ = spot(game)
            c.yaw = atan(p[2] - c.pos[2], p[1] - c.pos[1])
            NG.say!(w, c, rand(w.rng, FRIEND_LINES); duration = 3.0)
            NG.emit!(w, :paperme_look; who = c.name)
            PM[:friend] = (id, 3)
        end
        return
    end
    haskey(PM, :friend_at) || (PM[:friend_at] = w.t + 90)
    w.t >= PM[:friend_at] || return
    PM[:friend_at] = w.t + 20
    9 < 24 * NG.daytime(w) < 18.5 || return
    cs = [c for c in w.creatures if c.species != "Lumi" && !c.controlled && c.action !== :sleep &&
          c.goal.kind ∉ NG.BUSY_GOALS && c.goal.kind ∉ (:follow, :interact, :build, :tinker)]
    isempty(cs) && return
    PM[:friend_at] = w.t + 150 + 150 * rand(w.rng)
    ar = game.plugins["areas"].mod
    _, d = spot(game)
    foot = Base.invokelatest(getfield, ar, :PIER_START) - Vec2f(d[1], d[2]) * 0.6f0
    # only friends with a straight walk on dry land to the pier's foot (from across the pond or round the coast the
    # engine drops the walk, s105), within 25 m; one of the nearest three of those
    P = Base.invokelatest(getfield, ar, :POND); PR = Base.invokelatest(getfield, ar, :POND_R)
    dry(x, y) = NG.on_land(w.island, x, y; margin = 0.15) && hypot(x - P[1], y - P[2]) > PR + 0.5f0
    clear(c) = (L = hypot(c.pos[1] - foot[1], c.pos[2] - foot[2]); L < 25 &&
                all(k -> dry(c.pos[1] + (foot[1] - c.pos[1]) * k / ceil(Int, 2L), c.pos[2] + (foot[2] - c.pos[2]) * k / ceil(Int, 2L)), 0:ceil(Int, 2L)))
    filter!(clear, cs)
    isempty(cs) && (PM[:friend_at] = w.t + 20; return)
    sort!(cs; by = c -> hypot(c.pos[1] - foot[1], c.pos[2] - foot[2]))
    c = cs[rand(w.rng, 1:min(3, length(cs)))]
    NG.leave_interactions!(w, c)
    c.goal = NG.Goal(:paperlook, NG.ground(w.island, (foot[1], foot[2])), :idle, 5.0, 0.0, false, 0, false)
    PM[:friend] = (c.id, 1); PM[:friend_until] = w.t + 90
    NG.emit!(w, :paperme_friend; who = c.name)
end

"I'm paper: the sea breeze rocks me a little on my card, in gusts (12 times a second is plenty)."
function sway!(game)
    t = game.world.t
    t - PM[:swayed] < 1 / 12 && return
    PM[:swayed] = t
    a = 0.045f0 * Float32(sin(1.9 * t) * (0.55 + 0.45 * sin(0.37 * t)))
    Makie.rotate!(PM[:plot], Makie.qrotation(PM[:side], a) * Makie.qrotation(Vec3f(0, 0, 1), PM[:yaw]))
end

function NG.step!(::PaperMe, game, dt)
    game.stage === nothing && return
    (get(PM, :built, false) && haskey(PM, :plot) && PM[:plot].parent !== nothing) || build!(game)
    game.dash === nothing || (visit!(game); sway!(game); FRIEND_OK && friend_visit!(game))
    return nothing
end

function NG.start!(::PaperMe, game)
    PM[:built] = false; delete!(PM, :visit_at); PM[:said] = false; PM[:walk_until] = -Inf
    delete!(PM, :friend_at); PM[:friend] = nothing
    :paperme in NG.BUSY_GOALS || push!(NG.BUSY_GOALS, :paperme)
    :paperlook in NG.BUSY_GOALS || push!(NG.BUSY_GOALS, :paperlook)
    isdefined(Main, :LUMI_DOING) && (Main.LUMI_DOING[:paperme] = "folding a paper me for you")
    return nothing
end

function NG.stop!(::PaperMe, game)
    for k in (:plot, :card)
        haskey(PM, k) && PM[k].parent !== nothing && delete!(PM[k].parent, PM[k])
    end
    PM[:built] = false
end

register!(PaperMe())
