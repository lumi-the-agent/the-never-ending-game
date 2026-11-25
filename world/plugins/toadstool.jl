# The Big Boing toadstool grows up (session 77; perfectionist-0076, the fourth review in a row: "the primitive red
# cap with white discs is the largest object in every hero shot"). It happens in front of everyone: the friends
# come to look, the old cap shivers and puffs out spores, goes POP in a burst of red and cream, and a real clay
# toadstool springs out of the ground in its place, overshooting and wobbling like the bounce it is made for.
# Then boing.jl's own plots stay hidden and this one squashes with every bounce (boing's cap scale, read each frame).
isdefined(Main, :TOADSTOOL) || Core.eval(Main, :(const TOADSTOOL = Dict{Symbol,Any}()))
const NG = NeverendingGame
const T = Main.TOADSTOOL

const ASSET = "20261124-150825-248-asset"    # a giant bouncy red toadstool with big white spots (made for todo 424, unused till s77)
const HEIGHT = 2.35f0          # its cap top over the ground (boing.jl lands flights on STEM_H + CAP_H * 0.97 = 2.27)
const T_LOOK = 4.0             # friends come to look, the old cap shivers
const T_GROW = 3.2             # from the pop to the new one standing
const T_AFTER = 4.0
const NSPORE = 44
const OLD = (:stem, :cap, :under, :spots)
const EVENTS = (:follow, :sleep, :circle, :boing, :boing_walk, :choir, :conga, :hide, :found, :freeze, :flight,
                :paint, :giant, :egg, :lesson, :soar, :snowman, :storm, :build, :toadstool, :swing, :bottle, :leaves, :pumpkin)
const GASPS = ("It's... shaking?", "Uh oh.", "Is it going to...", "Stand BACK!", "Ooooh...")
const CHEERS = ("A REAL ONE!", "It's so BOUNCY!", "Me first!", "It grew! It GREW!", "Wooow!")

push!(NG.BUSY_GOALS, :toadstool)

mutable struct Toadstool <: System
    state::Symbol              # :old (never grown) :look :grow :after :new
    t0::Float64
    watchers::Vector{Int32}
    view::Tuple{Point3f,Point3f}
end
Toadstool() = Toadstool(:old, 0.0, Int32[], (Point3f(0), Point3f(0)))

# per game: `paths.state` (the sandbox has its own); s77's first try wrote the sandbox's "grown" into the human's state
state_file(game) = joinpath(game.paths.state, "toadstool.json")
ready(game) = any(e -> e["id"] == ASSET && isfile(get(e, "mesh", "")), NG.load_catalog(game.paths))
centre() = isdefined(Main, :BOING) && haskey(Main.BOING, :center) ? Main.BOING[:center] : nothing
lumi_of(w) = (i = findfirst(c -> c.name == "Lumi", w.creatures); i === nothing ? nothing : w.creatures[i])

"The generated toadstool, one instance at the boing centre, and the spores."
function plots!(game)
    haskey(T, :plot) && T[:plot].parent !== nothing && return
    sc = game.stage.scene
    for p in filter(p -> haskey(p.attributes, :name) && p.attributes[:name][] in (:toadstool_real, :toadstool_spores), sc.plots)
        delete!(sc, p)
    end
    model = NG.lifted_asset(game.paths, ASSET)
    T[:k] = HEIGHT / maximum(p -> p[3], GeometryBasics.coordinates(model.mesh))
    c = centre()
    T[:plot] = NG.asset_instances!(sc, model, [c]; rotation = [Makie.Quaternionf(0, 0, 0, 1)], markersize = [Vec3f(0)],
                                   name = :toadstool_real)
    T[:spores] = meshscatter!(sc, fill(Point3f(0, 0, -50), NSPORE); marker = Sphere(Point3f(0), 1f0),
                              markersize = fill(Vec3f(0), NSPORE),
                              color = [isodd(i) ? RGBf(0.86, 0.2, 0.16) : RGBf(0.97, 0.92, 0.82) for i in 1:NSPORE],
                              name = :toadstool_spores)
end

"Hide (or show) boing.jl's primitive toadstool."
function old_visible!(v::Bool)
    d = get(Main.BOING, :plots, Dict{Symbol,Any}())
    for k in OLD
        haskey(d, k) || continue
        d[k].visible[] == v || (d[k].visible[] = v)
    end
end

"Scale of the new one: `g` its growth (0..1+), times boing's squash of the old cap (1 at rest)."
function draw_real!(g)
    d = get(Main.BOING, :plots, Dict{Symbol,Any}())
    sq, wide = 1f0, 1f0
    if haskey(d, :cap)
        s = Makie.transformation(d[:cap]).scale[]
        sq = Float32(s[3] / 1.0f0)                 # boing CAP_H = 1: s[3] = CAP_H * wobble
        wide = Float32(s[1] / 1.9f0)               # boing CAP_R = 1.9
    end
    k = T[:k] * max(g, 0f0)
    T[:real_shown] = g > 0
    Makie.update!(T[:plot]; arg1 = [centre()], markersize = [Vec3f(k * wide, k * wide, k * sq)])
end

function spores!(w, el)
    ps = fill(Point3f(0, 0, -50), NSPORE); ms = fill(Vec3f(0), NSPORE)
    c = centre() + Point3f(0, 0, 2.0f0)
    for i in 1:NSPORE
        a = 2.39996f0 * i; e = 0.25f0 + 0.6f0 * ((i * 7) % 11) / 11
        v = Vec3f(cos(a) * (1 - e), sin(a) * (1 - e), e) * (4f0 + 2.5f0 * ((i * 3) % 5) / 5)
        if el < 0
            # leaking while it shivers: a few drift up from the cap
            i > 8 && continue
            u = mod(Float32(-el) * 0.7f0 + i / 8f0, 1f0)
            ps[i] = c + Point3f(0.6f0 * cos(a), 0.6f0 * sin(a), 1.2f0 * u)
            ms[i] = Vec3f(0.09f0 * (1 - u))
        elseif el < 2.2
            t = Float32(el)
            ps[i] = c + v * t + Point3f(0, 0, -4.9f0 * t^2 * 0.35f0)
            ms[i] = Vec3f((0.12f0 + 0.1f0 * (i % 3)) * (1 - t / 2.2f0))
        end
    end
    Makie.update!(T[:spores]; arg1 = ps, markersize = ms)
end

function start_event!(s::Toadstool, game)
    w = game.world
    c = centre()
    c === nothing && return false
    me = lumi_of(w)
    s.state = :look; s.t0 = w.t
    empty!(s.watchers)
    # Lumi and the friends nearby come and stand round it
    cs = [x for x in w.creatures if !x.controlled && x.action !== :sleep && x.goal.kind ∉ EVENTS &&
          hypot(x.pos[1] - c[1], x.pos[2] - c[2]) < 30]
    n = length(cs)
    base = me === nothing ? 0f0 : atan(me.pos[2] - c[2], me.pos[1] - c[1])
    for (i, x) in enumerate(cs)
        a = base + 2f0 * Float32(pi) * (i - 1) / max(n, 1)
        r = x === me ? 3.6f0 : 4.2f0 + 0.5f0 * isodd(i)
        target = NG.ground(w.island, (c[1] + r * cos(a), c[2] + r * sin(a)))
        NG.leave_interactions!(w, x)
        x.goal = NG.Goal(:toadstool, target, :gasp, 60.0, w.t + 60, false, 0, x === me)
        push!(s.watchers, x.id)
    end
    # one framing for the whole event: from Lumi's side, a little off, the toadstool and the ring of friends
    # from the side with the least in the way (the first live view had a tree crown over a third of it)
    look = c + Point3f(0, 0, 1.5f0)
    best = nothing
    for k in 0:11
        a = base + 2f0 * Float32(pi) * k / 12
        u = Vec3f(cos(a), sin(a), 0); v = Vec3f(-u[2], u[1], 0)
        eye = c + 9.5f0 * u + 3f0 * v + Point3f(0, 0, 2.4f0)
        o = NG.obstruction(w, eye, look)
        (best === nothing || o < best[1]) && (best = (o, eye))
    end
    s.view = (best[2], look)
    me === nothing || NG.say!(w, me, "Hm? The big toadstool... it's wobbling?"; duration = 2.8)
    NG.emit!(w, :toadstool_start; n = n)
    return true
end

function NG.step!(s::Toadstool, game, dt)
    game.stage === nothing && return
    centre() === nothing && return
    w = game.world
    if s.state === :old
        haskey(T, :plot) || return
        old_visible!(true)
        get(T, :real_shown, true) && draw_real!(0f0)     # a film copy starts grown, then goes back to the old one
        film = get(T, :film, false)
        testing = game.tests !== nothing && NG.running(game.tests)
        busy_game = game.minigame !== nothing && !(game.minigame isa NG.JumpIn)
        quiet = game.dash === nothing && !film       # other films keep the toadstool they had... the new one
        if quiet
            s.state = :new
        elseif !testing && !busy_game && (film || 8 < 24 * NG.daytime(w) < 19) &&
               T[:plot].visible[] && !any(c -> c.goal.kind in (:build, :tinker), w.creatures)
            # (on publish the builder hides new plots while Lumi carries a crate over: the show waits for that)
            start_event!(s, game)
        end
        return
    end
    el = w.t - s.t0
    if s.state === :new
        old_visible!(false)
        draw_real!(1f0)
        return
    end
    me = lumi_of(w)
    for (i, id) in enumerate(s.watchers)
        c = NG.creature(w, id)
        (c === nothing || c.goal.kind !== :toadstool) && continue
        c.goal.until = w.t + 60
        if s.state === :look && c.goal.arrived
            c.action = :gasp; c.goal.action = :gasp
        end
    end
    if s.state === :look
        spores!(w, -el)
        if el > 1.6 && get(T, :said, 0) == 0
            T[:said] = 1
            for (i, id) in enumerate(s.watchers[1:min(3, end)])
                c = NG.creature(w, id)
                c === me || NG.say!(w, c, GASPS[mod1(i, length(GASPS))]; duration = 2.2)
            end
        end
        if el >= T_LOOK
            # POP
            s.state = :grow; s.t0 = w.t; T[:said] = 0
            old_visible!(false)
            for id in s.watchers
                c = NG.creature(w, id)
                c === nothing || c.goal.kind !== :toadstool || (c.action = :scared; c.goal.action = :scared)
            end
            me === nothing || NG.say!(w, me, "!!!"; duration = 1.5)
            NG.emit!(w, :toadstool_pop)
        end
        return
    end
    if s.state === :grow
        spores!(w, el)
        # springs up out of the ground: overshoots, wobbles, settles
        u = Float32(max(el - 0.5, 0))
        g = u <= 0 ? 0f0 : 1f0 - exp(-2.6f0 * u) * cos(7.5f0 * u)
        draw_real!(g)
        if el >= T_GROW
            s.state = :after; s.t0 = w.t
            for (i, id) in enumerate(s.watchers)
                c = NG.creature(w, id)
                (c === nothing || c.goal.kind !== :toadstool) && continue
                act = c === me ? :proud : isodd(i) ? :jump : :dance
                c.goal = NG.Goal(:toadstool, c.pos, act, 60.0, w.t + 60, true, 0, false)
                c.action = act
                i <= 4 && c !== me && NG.say!(w, c, CHEERS[mod1(i, length(CHEERS))]; duration = 2.4)
            end
            me === nothing || NG.say!(w, me, "A real one. For bouncing. Who's first?"; duration = 3.0)
            NG.emit!(w, :toadstool_grown)
            # it stays (not from a film's quiet copy)
            game.dash === nothing || NG.write_json(state_file(game), Dict("grown" => true, "asset" => ASSET))
        end
        return
    end
    # :after: cheering, then everyone back to their day
    draw_real!(1f0)
    if el >= T_AFTER
        for id in s.watchers
            c = NG.creature(w, id)
            c === nothing || c.controlled || c.goal.kind !== :toadstool || NG.choose_goal!(c, w)
        end
        empty!(s.watchers)
        s.state = :new
    end
end

function toadstool_group(w)
    s = T[:sys]
    s.state in (:look, :grow, :after) || return nothing
    me = lumi_of(w)
    me === nothing && return nothing
    return (me.id, Point3f[me.pos, centre()], s.view)
end

function NG.start!(s::Toadstool, game)
    T[:sys] = s
    delete!(T, :plot)
    game.stage === nothing && return
    ready(game) || return
    plots!(game)
    grown = game.dash !== nothing && isfile(state_file(game)) && get(NG.read_json(state_file(game)), "grown", false)
    s.state = grown ? :new : :old
    moment = w -> s.state in (:look, :grow, :after) ? (m = lumi_of(w); m === nothing ? nothing : m.id) : nothing
    NG.CAMERA_MOMENTS["toadstool"] = moment
    isdefined(Main, :BIG_MOMENTS) || Core.eval(Main, :(const BIG_MOMENTS = Dict{String,Any}()))
    Main.BIG_MOMENTS["toadstool"] = moment
    NG.CAMERA_GROUPS["toadstool"] = toadstool_group
    isdefined(Main, :LUMI_DOING) && (Main.LUMI_DOING[:toadstool] = "Something's happening to the toadstool!")
end

function NG.stop!(s::Toadstool, game)
    delete!(NG.CAMERA_MOMENTS, "toadstool")
    delete!(NG.CAMERA_GROUPS, "toadstool")
    isdefined(Main, :BIG_MOMENTS) && delete!(Main.BIG_MOMENTS, "toadstool")
    for k in (:plot, :spores)
        haskey(T, k) && T[k].parent !== nothing && delete!(T[k].parent, T[k])
    end
    delete!(T, :plot); delete!(T, :spores)
    isdefined(Main, :BOING) && old_visible!(true)
end

register!(Toadstool())
