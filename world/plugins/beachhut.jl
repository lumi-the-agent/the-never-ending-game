# The beach hut (session 99): the first thing my friends voted for (the first live vote, 25 November 2026, 21:42:
# a beach hut, chosen by Pinchy, Sir Sniffsalot and Wibbles). It stands on the south beach above the tide line,
# facing the sea, and the friends who voted for it go there now and then to sit in its doorway and look at the water
# ("My hut!"). Its generated body (driftwood planks, a striped awning) comes from the worker; until I have looked at
# it on the island, a little hand-made hut of planks and a striped roof stands there.
isdefined(Main, :BEACHHUT) || Core.eval(Main, :(const BEACHHUT = Dict{Symbol,Any}()))
const NG = NeverendingGame
const BH = Main.BEACHHUT

const ASSET = "20261125-214250-671-asset"
const BODY_OK = false
const VISIT_EVERY = (60.0, 150.0)
const LINES = ("My hut!", "Best seat on the island.", "I voted for this.", "Listen to the sea...")

struct BeachHut <: System end

"Where it stands: up the south beach from where Shell came ashore, facing the sea."
function spot(game)
    get!(BH, :spot) do
        w = game.world
        st = get(game.plugins, "stranger", nothing)
        p, inland = st === nothing ? (Point2f(0, -20), Point2f(0, 1)) : Base.invokelatest(st.mod.landing, w)
        q = p + 4.5f0 * inland + 3f0 * Point2f(-inland[2], inland[1])
        (NG.ground(w.island, (q[1], q[2])), atan(-inland[2], -inland[1]))
    end
end

"The friends who voted for it (the human's vote record), else everyone."
function fans(game)
    f = joinpath(game.paths.state, "vote.json")
    isfile(f) || return String[]
    d = NG.read_json(f)
    hs = [h for h in get(d, "history", Any[]) if get(h, "key", "") == "beachhut"]
    isempty(hs) && return String[]
    return [String(k) for (k, v) in get(hs[1], "voters", Dict()) if v == "a beach hut"]
end

function plots!(game)
    haskey(BH, :plot) && BH[:plot].parent !== nothing && return
    sc = game.stage.scene
    for p in filter(p -> haskey(p.attributes, :name) && p.attributes[:name][] in (:beachhut, :beachhut_mesh), copy(sc.plots))
        delete!(sc, p)
    end
    (p, yaw) = spot(game)
    q = Makie.qrotation(Vec3f(0, 0, 1), yaw)
    at(v) = p + q * v
    use_mesh = (BODY_OK || get(BH, :try, false)) && isfile(joinpath(game.paths.world, "assets", ASSET, "mesh.jls"))
    if use_mesh
        BH[:plot] = NG.asset_instances!(sc, NG.lifted_asset(game.paths, ASSET), [p]; markersize = [Vec3f(get(BH, :size, 2.2f0))],
                                        rotation = [q * Makie.qrotation(Vec3f(0, 0, 1), Float32(pi / 2))], name = :beachhut_mesh)
    else
        # the stand-in: plank walls with a doorway towards the sea, a striped roof
        box = Rect3f(Vec3f(-0.5, -0.5, 0), Vec3f(1, 1, 1))
        ps = [at(Vec3f(-0.55, 0, 0)), at(Vec3f(0.1, 0.62, 0)), at(Vec3f(0.1, -0.62, 0)), at(Vec3f(0.55, 0.42, 0)), at(Vec3f(0.55, -0.42, 0)),
              at(Vec3f(0, 0, 1.25)), at(Vec3f(0, 0.25, 1.32)), at(Vec3f(0, -0.25, 1.32))]
        ms = [Vec3f(0.08, 1.3, 1.25), Vec3f(1.3, 0.08, 1.25), Vec3f(1.3, 0.08, 1.25), Vec3f(0.08, 0.45, 1.25), Vec3f(0.08, 0.45, 1.25),
              Vec3f(1.6, 1.6, 0.06), Vec3f(1.6, 0.25, 0.08), Vec3f(1.6, 0.25, 0.08)]
        wood = RGBf(0.7, 0.58, 0.42)
        BH[:plot] = meshscatter!(sc, ps; marker = box, markersize = ms, rotation = fill(q, length(ps)),
                                 color = [wood, wood, wood, wood, wood, RGBf(0.92, 0.9, 0.85), RGBf(0.85, 0.2, 0.2), RGBf(0.85, 0.2, 0.2)],
                                 name = :beachhut)
    end
end

function NG.step!(::BeachHut, game, dt)
    game.stage === nothing && return
    plots!(game)
    w = game.world
    for c in w.creatures                                          # who made it to the door
        c.goal.kind === :hut && c.goal.arrived || continue
        c.id in get!(() -> Set{Int32}(), BH, :sat) && continue
        push!(BH[:sat], c.id)
        NG.emit!(w, :beachhut_sit; who = c.name)
    end
    w.t >= get(BH, :visit_at, w.t + 1) || (haskey(BH, :visit_at) || (BH[:visit_at] = w.t + 30); return)
    BH[:visit_at] = w.t + 10
    names = fans(game)
    cs = [c for c in w.creatures if (isempty(names) || c.name in names) && !c.controlled && c.action !== :sleep &&
          c.goal.kind ∉ NG.BUSY_GOALS && c.goal.kind !== :follow]
    isempty(cs) && return                                         # (everyone busy: look again in 10 s)
    BH[:visit_at] = w.t + VISIT_EVERY[1] + (VISIT_EVERY[2] - VISIT_EVERY[1]) * rand(w.rng)
    c = cs[rand(w.rng, 1:length(cs))]
    (p, yaw) = spot(game)
    door = NG.ground(w.island, (p[1] + 1.0f0 * cos(yaw), p[2] + 1.0f0 * sin(yaw)))
    NG.leave_interactions!(w, c)
    delete!(get!(() -> Set{Int32}(), BH, :sat), c.id)
    # its own goal kind: as a plain :wander the walk was taken over by every crowd on the way, and in the first
    # 20 live minutes not one visitor came within 6 m of the door (s99, log/frames)
    c.goal = NG.Goal(:hut, door, :sit, 20.0, w.t + 90, false, 0, false)
    NG.say!(w, c, LINES[rand(w.rng, 1:length(LINES))]; duration = 2.5)
    NG.emit!(w, :beachhut_visit; who = c.name)
end

NG.start!(::BeachHut, game) = (delete!(BH, :plot); delete!(BH, :spot); delete!(BH, :visit_at); nothing)

function NG.stop!(::BeachHut, game)
    haskey(BH, :plot) && BH[:plot].parent !== nothing && delete!(BH[:plot].parent, BH[:plot])
    delete!(BH, :plot)
end

register!(BeachHut())
