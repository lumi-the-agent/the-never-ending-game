# Cloud watching (session 101, goal 8): bored, I lie down in the grass and stare at the sky, a few friends flop down
# beside me, and a cloud right above us slowly gathers into a shape: a heart, then it melts into a fish, then into a
# pig. Each time someone shouts what they see ("A FISH!", "That one's ME!"). Then it comes apart and drifts off.
# The cloud is real puffs (lit spheres, like the island's other clouds) that move from shape to shape.
isdefined(Main, :CLOUDSHAPES) || Core.eval(Main, :(const CLOUDSHAPES = Dict{Symbol,Any}()))
isdefined(Main, :LUMI_PARTY) || Core.eval(Main, :(const LUMI_PARTY = Dict{Symbol,Any}()))
const NG = NeverendingGame
const CS = Main.CLOUDSHAPES

party_free(w) = w.t >= get(Main.LUMI_PARTY, :until, -Inf)
claim_party!(w, secs) = (Main.LUMI_PARTY[:until] = w.t + secs; nothing)

const N = 48                       # puffs
const EVERY = (420.0, 780.0)       # s between two cloud watches
const HOLD = 9.0                   # s a shape holds
const MORPH = 4.0                  # s from one shape to the next
const SHAPES = (:heart, :fish, :pig)
const SHOUTS = Dict(:heart => ("A heart!", "Aww, a heart!"), :fish => ("A FISH! Gloop, look!", "It's a fish!"),
                    :pig => ("That one's ME!", "A pig! With a curly tail!"))
push!(NG.BUSY_GOALS, :cloudwatch)

struct CloudShapes <: System end

"N points (u sideways, v up, in metres) along the outline and inside a shape."
function shape_points(k)
    pts = Point2f[]
    if k === :heart
        for i in 1:N
            t = 2pi * i / N
            push!(pts, 0.42f0 * Point2f(16 * sin(t)^3, 13cos(t) - 5cos(2t) - 2cos(3t) - cos(4t)))
        end
    elseif k === :fish
        for i in 1:34                                  # the body, an ellipse
            t = 2pi * i / 34
            push!(pts, Point2f(5.5f0 * cos(t), 2.8f0 * sin(t)))
        end
        for i in 1:7                                   # the tail: two fins spreading back from the body
            a = Float32(i / 7)
            push!(pts, Point2f(-5.5f0 - 3.2f0 * a, 3f0 * a))
            push!(pts, Point2f(-5.5f0 - 3.2f0 * a, -3f0 * a))
        end
    else                                               # a pig: a round body, two ears, a snout, a curl
        for i in 1:32
            t = 2pi * i / 32
            push!(pts, Point2f(5f0 * cos(t), 4.2f0 * sin(t)))
        end
        append!(pts, [Point2f(-3, 4.6), Point2f(-2.2, 5.6), Point2f(-1.6, 4.4), Point2f(1.6, 4.4), Point2f(2.2, 5.6), Point2f(3, 4.6)])
        append!(pts, [Point2f(-1, -0.6), Point2f(0, -0.4), Point2f(1, -0.6), Point2f(0, -1.3)])
        append!(pts, [Point2f(5.6, 1.2), Point2f(6.4, 1.8), Point2f(6.6, 0.8), Point2f(6, 0.4)])
        while length(pts) < N
            push!(pts, Point2f(0, 1.5))
        end
    end
    return pts[1:N]
end

"Shape points out in the sky: upright, facing the watchers, high above and a little ahead of them."
function in_sky(c, dir, uv)
    side = Vec3f(-dir[2], dir[1], 0)
    return [c + side * p[1] + Vec3f(0, 0, 1) * p[2] for p in uv]
end

function begin_watch!(game, me)
    w = game.world
    a = atan(-me.pos[2], -me.pos[1])                    # look inland-ish over the island
    dir = Vec2f(cos(a), sin(a))
    centre = me.pos + Point3f(dir[1] * 15f0, dir[2] * 15f0, 12f0)          # low enough to frame with us under it
    CS[:watch] = Dict{Symbol,Any}(:t0 => w.t, :centre => centre, :dir => dir, :me => me.id, :said => Set{Int}(),
                                  :start => [centre + Vec3f(9randn(w.rng, Float32), 9randn(w.rng, Float32), 3randn(w.rng, Float32)) for _ in 1:N],
                                  :friends => Int32[])
    NG.leave_interactions!(w, me)
    me.yaw = atan(dir[2], dir[1]) - NG.species_of(me).heading
    me.goal = NG.Goal(:cloudwatch, me.pos, :sit, 600.0, w.t + 600, true, 0, false)
    NG.say!(w, me, "Nothing to do... I'll just watch the clouds."; duration = 3.0)
    # a few friends flop down beside me
    cs = [c for c in w.creatures if c.id != me.id && !c.controlled && c.action !== :sleep &&
          c.goal.kind ∉ NG.BUSY_GOALS && c.goal.kind !== :follow && hypot(c.pos[1] - me.pos[1], c.pos[2] - me.pos[2]) < 18]
    sort!(cs; by = c -> hypot(c.pos[1] - me.pos[1], c.pos[2] - me.pos[2]))
    for (i, c) in enumerate(cs[1:min(3, end)])
        off = Vec2f(-dir[2], dir[1]) * Float32((i - 2) * 1.6 + (i >= 2 ? 1.6 : -1.6)) - dir * 0.6f0
        spot = NG.ground(w.island, (me.pos[1] + off[1], me.pos[2] + off[2]))
        NG.on_land(w.island, spot[1], spot[2]; margin = 0.2f0) || continue
        NG.leave_interactions!(w, c)
        c.goal = NG.Goal(:cloudwatch, spot, :sit, 600.0, w.t + 600, false, 0, false)
        push!(CS[:watch][:friends], c.id)
    end
    claim_party!(w, 3 * (HOLD + MORPH) + 20)
    NG.emit!(w, :cloudwatch_start; friends = length(CS[:watch][:friends]))
end

function positions(wt, wa)
    el = wt - wa[:t0]
    stage = el / (HOLD + MORPH)                         # 0: gathering into the first shape, 1, 2: morphs, 3: apart
    i = clamp(floor(Int, stage), 0, 3)
    u = clamp(Float32((el - i * (HOLD + MORPH)) / MORPH), 0f0, 1f0)
    u = u * u * (3 - 2u)
    shp(k) = in_sky(wa[:centre], wa[:dir], shape_points(SHAPES[k]))
    from = i == 0 ? wa[:start] : shp(i)
    to = i <= 2 ? shp(i + 1) : [p + Vec3f(12f0 * wa[:dir][1], 12f0 * wa[:dir][2], 4f0) + Vec3f(0, 0, 0) for p in shp(3)]
    pts = [Point3f(f + (t - f) * u) for (f, t) in zip(from, to)]
    fade = i == 3 ? 1f0 - u : clamp(Float32(el / MORPH), 0f0, 1f0)
    return pts, fade, i, u
end

function draw!(game, pts, fade)
    sc = game.stage.scene
    if !haskey(CS, :plot) || CS[:plot].parent === nothing
        CS[:plot] = meshscatter!(sc, fill(Point3f(0, 0, -80), N); marker = Sphere(Point3f(0), 1f0), markersize = fill(0f0, N),
                                 color = RGBf(0.97, 0.97, 1.0), name = :cloudshapes)
        CS[:drawn] = false
    end
    if pts === nothing
        get(CS, :drawn, true) && Makie.update!(CS[:plot], fill(Point3f(0, 0, -80), N); markersize = fill(0f0, N))
        CS[:drawn] = false
        return
    end
    ms = [fade * (1.25f0 + 0.45f0 * sin(1.7f0 * j)) for j in 1:N]
    Makie.update!(CS[:plot], pts; markersize = ms)
    CS[:drawn] = true
end

function finish!(w)
    wa = CS[:watch]
    for id in [wa[:me]; wa[:friends]]
        c = NG.creature(w, id)
        c === nothing || c.goal.kind !== :cloudwatch || c.controlled || NG.choose_goal!(c, w)
    end
    me = NG.creature(w, wa[:me])
    me === nothing || me.controlled || NG.say!(w, me, "...that was nice, actually."; duration = 3.0)
    NG.emit!(w, :cloudwatch_end)
    CS[:watch] = nothing
end

function NG.step!(::CloudShapes, game, dt)
    game.stage === nothing && return
    w = game.world
    wa = get(CS, :watch, nothing)
    if wa === nothing
        draw!(game, nothing, 0f0)
        haskey(CS, :next) || (CS[:next] = w.t + 90 + 120 * rand(w.rng))
        testing = game.tests !== nothing && NG.running(game.tests)
        film = get(CS, :film, false)
        h = NG.daytime(w)
        (film || (!testing && w.t >= CS[:next] && 0.32 < h < 0.75 && party_free(w))) || return
        CS[:next] = w.t + 20                               # (not now: look again soon)
        i = findfirst(c -> c.name == "Lumi", w.creatures)
        i === nothing && return
        me = w.creatures[i]
        (me.controlled || me.action === :sleep || !NG.on_land(w.island, me.pos[1], me.pos[2]; margin = 0.1f0)) && return
        (film || me.goal.kind ∉ NG.BUSY_GOALS) || return
        CS[:film] = false
        CS[:next] = w.t + EVERY[1] + (EVERY[2] - EVERY[1]) * rand(w.rng)
        begin_watch!(game, me)
        return
    end
    me = NG.creature(w, wa[:me])
    if me === nothing || me.goal.kind !== :cloudwatch
        finish!(w); return                                 # something else took me
    end
    pts, fade, i, u = positions(w.t, wa)
    draw!(game, pts, fade)
    if i <= 2 && u >= 1 && !(i in wa[:said])           # a shape is complete: someone shouts what it is
        push!(wa[:said], i)
        k = SHAPES[i + 1]
        who = isempty(wa[:friends]) ? me : something(NG.creature(w, wa[:friends][mod1(i + 1, length(wa[:friends]))]), me)
        NG.say!(w, who, SHOUTS[k][rand(w.rng, 1:2)]; duration = 3.0)
        NG.emit!(w, :cloud_shape; shape = k, who = who.name)
    end
    w.t - wa[:t0] > 3 * (HOLD + MORPH) + MORPH && finish!(w)
end

"While we watch: the camera lies in the grass behind us and looks up at the cloud."
function watch_view(w)
    wa = get(CS, :watch, nothing)
    wa === nothing && return nothing
    me = NG.creature(w, wa[:me])
    (me === nothing || me.controlled) && return nothing
    d = wa[:dir]
    # far behind us and low: the watchers at the bottom of the frame, the whole shape above them (a 45 deg view)
    eye = me.pos + Point3f(-d[1] * 13f0, -d[2] * 13f0, 1.2f0)
    target = me.pos + Point3f(d[1] * 8f0, d[2] * 8f0, 6.4f0)
    return (me.id, Point3f[me.pos, wa[:centre]], (eye, target))
end

function NG.start!(::CloudShapes, game)
    CS[:watch] = nothing; CS[:film] = false; delete!(CS, :next)
    if game.stage !== nothing
        for p in filter(p -> haskey(p.attributes, :name) && p.attributes[:name][] === :cloudshapes, copy(game.stage.scene.plots))
            delete!(game.stage.scene, p)
        end
    end
    delete!(CS, :plot)
    NG.CAMERA_GROUPS["cloudshapes"] = watch_view
    NG.CAMERA_MOMENTS["cloudshapes"] = w -> (wa = get(CS, :watch, nothing); wa === nothing ? nothing : wa[:me])
    # asked before the other moments (garden.jl): with CAMERA_MOMENTS alone a tag game kept the camera (s101)
    isdefined(Main, :BIG_MOMENTS) && (Main.BIG_MOMENTS["cloudshapes"] = NG.CAMERA_MOMENTS["cloudshapes"])
    isdefined(Main, :LUMI_DOING) && (Main.LUMI_DOING[:cloudwatch] = "watching the clouds")
    return nothing
end

function NG.stop!(::CloudShapes, game)
    get(CS, :watch, nothing) === nothing || finish!(game.world)
    haskey(CS, :plot) && CS[:plot].parent !== nothing && delete!(CS[:plot].parent, CS[:plot])
    delete!(CS, :plot)
    delete!(NG.CAMERA_GROUPS, "cloudshapes"); delete!(NG.CAMERA_MOMENTS, "cloudshapes")
    isdefined(Main, :BIG_MOMENTS) && delete!(Main.BIG_MOMENTS, "cloudshapes")
end

register!(CloudShapes())
