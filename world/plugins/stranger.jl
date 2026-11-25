# A stranger washes ashore (session 97, goal 8): one morning someone new lies on the south beach, a kind the island
# has never had: a small periwinkle creature with a spiral sea shell on its back and one big eye on a stalk. It
# bobs in on the surf, lies tipped over on the sand a while, rights itself and starts to look about. It does not
# speak our way. The friends are frightened of it at first and run; every time one meets it they trust it a little
# more (kept per friend across days), so the island slowly gets to know it: scared, then curious, then friends.
# It is shy itself: when someone shrieks it backs away; when someone waves it gives a little hop.
isdefined(Main, :STRANGER) || Core.eval(Main, :(const STRANGER = Dict{Symbol,Any}()))
const NG = NeverendingGame
const ST = Main.STRANGER

const ASSET = "20261125-195347-007-asset"   # its generated body (until looked at: a hand-made stand-in)
const BODY_OK = true             # looked at in s97 (media/s97/body-side2.png): faces mesh -y, turned a quarter
const SPEED = 0.45f0
const MEET_R = 3.6f0
const MEET_GAP = 25.0            # s before the same friend counts another meeting
const TRUST_STEP = 0.1f0         # curious after 3 meetings, friends after 7 (twice as fast with me beside it)
const SCARED = ("W-who are YOU?!", "EEK! It's looking at me!", "What IS that?", "It has ONE eye!")
const CURIOUS = ("...hello?", "Are you lost?", "Do you like berries?", "Where did you come from?")
const VISIT_LINES = ("Morning, Shell. Still here?", "Shell! Want to see the pond?", "They'll come round, Shell. They did with me.",
                     "Hello again, Shell.")
const FRIENDLY = ("Hi, Shell!", "Shell! Over here!", "Morning, Shell!", "Want to come fishing?")

mutable struct Stranger <: System
    state::Symbol                # :away :ashore :waking :roam :backoff
    t0::Float64
    pos::Point3f
    yaw::Float32
    aim::Point2f
end
Stranger() = Stranger(:away, 0.0, Point3f(0, 0, -50), 0f0, Point2f(0, 0))

lumi_of(w) = (i = findfirst(c -> c.name == "Lumi", w.creatures); i === nothing ? nothing : w.creatures[i])
flat(a, b) = hypot(a[1] - b[1], a[2] - b[2])
state_file(game) = joinpath(game.paths.state, "stranger.json")
trust(name) = get(ST[:trust]::Dict{String,Float64}, name, 0.0)

"Where the surf brings it in: the south shore, at the last bit of land before the water (on a little sand)."
function landing(w)
    best = nothing
    for a in range(-pi / 2 - 0.5, -pi / 2 + 0.5; length = 21), r in 40f0:-0.5f0:5f0
        x, y = r * Float32(cos(a)), r * Float32(sin(a))
        if NG.on_land(w.island, x, y; margin = 0.15f0)
            (best === nothing || r > best[3]) && (best = (x, y, r))
            break
        end
    end
    best === nothing && return Point2f(0, -10), Point2f(0, -1)
    x, y, r = best
    return Point2f(x, y), Point2f(-x / r, -y / r)          # where it lies, and inland
end

ground_at(w, p) = NG.ground(w.island, (p[1], p[2]))

function new_aim!(s, w)
    # half the time it is curious about the nearest of us and goes over (stopping a little short)
    if rand(w.rng) < 0.5
        cs = [c for c in w.creatures if c.action !== :sleep && flat(c.pos, s.pos) < 15f0]
        if !isempty(cs)
            c = argmin(c -> flat(c.pos, s.pos), cs)
            d = Vec2f(c.pos[1] - s.pos[1], c.pos[2] - s.pos[2]); n = max(hypot(d...), 1f-3)
            s.aim = Point2f(c.pos[1] - 2f0 * d[1] / n, c.pos[2] - 2f0 * d[2] / n)
            return
        end
    end
    for _ in 1:20
        a = 2f0 * Float32(pi) * rand(w.rng, Float32); r = 3f0 + 6f0 * rand(w.rng, Float32)
        q = Point2f(s.pos[1] + r * cos(a), s.pos[2] + r * sin(a))
        NG.on_land(w.island, q[1], q[2]; margin = 0.3f0) || continue
        s.aim = q; return
    end
    s.aim = Point2f(s.pos[1], s.pos[2])
end

function arrive!(s::Stranger, game)
    w = game.world
    p, inland = landing(w)
    ST[:inland] = inland
    s.pos = ground_at(w, p - 2.5f0 * inland) + Point3f(0, 0, -0.25f0)      # out in the surf
    s.yaw = atan(inland[2], inland[1])
    s.state = :ashore; s.t0 = w.t
    ST[:land_at] = p
    push!(get!(() -> Tuple{Float64,Symbol}[], ST, :log), (w.t, :ashore))
    NG.emit!(w, :stranger_ashore)
    # I go down to see who it is
    me = lumi_of(w)
    if me !== nothing && !me.controlled && me.action !== :sleep && me.goal.kind ∉ NG.BUSY_GOALS
        NG.leave_interactions!(w, me)
        me.goal = NG.Goal(:stranger, ground_at(w, p + 1.6f0 * inland), :walk, 20.0, w.t + 60, false, 0, true)
        ST[:greet] = :going; ST[:greet_t] = w.t
    end
end

use_body(game) = (BODY_OK || get(ST, :body_try, false)) && isfile(joinpath(game.paths.world, "assets", ASSET, "mesh.jls"))

function plots!(game)
    haskey(ST, :plot) && ST[:plot].parent !== nothing && return
    sc = game.stage.scene
    for p in filter(p -> haskey(p.attributes, :name) && p.attributes[:name][] === :stranger_body, copy(sc.plots))
        delete!(sc, p)
    end
    # the hand-made stand-in: body, shell, eye stalk ball, pupil (until the generated body is looked at)
    ST[:plot] = meshscatter!(sc, fill(Point3f(0, 0, -50), 4); marker = Sphere(Point3f(0), 1f0), markersize = fill(Vec3f(0), 4),
                             rotation = fill(Makie.Quaternionf(0, 0, 0, 1), 4),
                             color = [RGBf(0.55, 0.62, 0.95), RGBf(0.93, 0.78, 0.6), RGBf(0.98, 0.97, 0.93), RGBf(0.08, 0.08, 0.12)],
                             name = :stranger_body)
    # its generated body (one instance), once looked at; the stand-in then stays hidden
    for p in filter(p -> haskey(p.attributes, :name) && p.attributes[:name][] === :stranger_mesh, copy(sc.plots))
        delete!(sc, p)
    end
    delete!(ST, :mesh)
    use_body(game) && (ST[:mesh] = NG.asset_instances!(sc, NG.lifted_asset(game.paths, ASSET), [Point3f(0, 0, -50)];
                                                      markersize = [Vec3f(0)], rotation = [Makie.Quaternionf(0, 0, 0, 1)],
                                                      name = :stranger_mesh))
end

function draw!(s::Stranger, game)
    w = game.world
    if s.state === :away
        Makie.update!(ST[:plot]; arg1 = fill(Point3f(0, 0, -50), 4), markersize = fill(Vec3f(0), 4))
        haskey(ST, :mesh) && Makie.update!(ST[:mesh]; arg1 = [Point3f(0, 0, -50)], markersize = [Vec3f(0)])
        return
    end
    t = Float32(w.t)
    tip = s.state === :ashore ? 1.25f0 : s.state === :waking ? 1.25f0 * max(0f0, 1f0 - Float32(w.t - s.t0) / 1.2f0) : 0f0
    hop = s.state in (:roam, :backoff) ? 0.04f0 * abs(sin(7f0 * t)) : 0f0
    q = Makie.qrotation(Vec3f(0, 0, 1), s.yaw) * Makie.qrotation(Vec3f(1, 0, 0), tip)
    P = s.pos + Point3f(0, 0, hop)
    at(v) = P + q * v
    look = 0.04f0 * sin(1.3f0 * t)                     # the eye peers about
    eye = Vec3f(0.2f0, look, 0.42f0)
    ps = [at(Vec3f(0, 0, 0.16f0)), at(Vec3f(-0.08f0, 0, 0.3f0)), at(eye), at(eye + Vec3f(0.07f0, 0, 0))]
    ms = [Vec3f(0.3f0, 0.18f0, 0.16f0), Vec3f(0.2f0, 0.2f0, 0.22f0), Vec3f(0.09f0), Vec3f(0.035f0)]
    if haskey(ST, :mesh)
        Makie.update!(ST[:plot]; arg1 = fill(Point3f(0, 0, -50), 4), markersize = fill(Vec3f(0), 4))
        qm = q * Makie.qrotation(Vec3f(0, 0, 1), get(ST, :mesh_turn, Float32(pi / 2))::Float32)     # (which way the mesh faces: looked at once)
        Makie.update!(ST[:mesh]; arg1 = [P], markersize = [Vec3f(get(ST, :mesh_size, 0.55f0)::Float32)], rotation = [qm])
    else
        Makie.update!(ST[:plot]; arg1 = ps, markersize = ms, rotation = fill(q, 4))
    end
end

function meet!(s::Stranger, game, c)
    w = game.world
    tr = ST[:trust]::Dict{String,Float64}
    k = trust(c.name)
    NG.leave_interactions!(w, c)
    c.yaw = atan(s.pos[2] - c.pos[2], s.pos[1] - c.pos[1]) - NG.species_of(c).heading
    i = mod1(Int(c.id) + length(tr), 4)
    if k < 0.3
        NG.feel!(w, c, :scared; seconds = 1.6)
        NG.say!(w, c, SCARED[i]; duration = 2.2)
        s.state = :backoff; s.t0 = w.t
        away = Vec2f(s.pos[1] - c.pos[1], s.pos[2] - c.pos[2]); away = away / max(hypot(away...), 1f-3)
        s.aim = Point2f(s.pos[1] + 2.5f0 * away[1], s.pos[2] + 2.5f0 * away[2])
        how = :scared
    elseif k < 0.7
        NG.feel!(w, c, :think; seconds = 2.0)
        NG.say!(w, c, CURIOUS[i]; duration = 2.2)
        how = :curious
    else
        NG.feel!(w, c, :wave; seconds = 2.0)
        NG.say!(w, c, FRIENDLY[i]; duration = 2.0)
        ST[:happy_until] = w.t + 1.5
        how = :friendly
    end
    # with me standing by it, they trust it twice as fast (I vouch for it)
    me = lumi_of(w)
    vouch = me !== nothing && flat(me.pos, s.pos) < 4f0 ? 2 : 1
    tr[c.name] = min(1.0, k + vouch * TRUST_STEP)
    k < 0.7 <= tr[c.name] && NG.emit!(w, :stranger_friend; who = c.name)
    push!(get!(() -> Tuple{Float64,Symbol}[], ST, :log), (w.t, how))
    NG.emit!(w, :stranger_meet; who = c.name, how = how)
end

function NG.step!(s::Stranger, game, dt)
    game.stage === nothing && return
    plots!(game)
    w = game.world
    if s.state === :away
        # it comes in on the first morning after it was made, or at once in a film
        h = 24 * NG.daytime(w)
        (get(ST, :film, false) || !get(ST, :arrived, false) && 6 < h < 21.5) && arrive!(s, game)
        s.state === :away || (ST[:arrived] = true; ST[:film] = false)
    elseif s.state === :ashore
        el = w.t - s.t0
        p = ST[:land_at]::Point2f; inland = ST[:inland]::Point2f
        u = Float32(clamp(el / 4.0, 0, 1)); u = u * u * (3 - 2u)
        g = ground_at(w, p - 2.5f0 * (1 - u) * inland)
        s.pos = g + Point3f(0, 0, -0.25f0 * (1 - u) + 0.05f0 * sin(3f0 * Float32(el)) * (1 - u))   # bobbing in on the surf
        el > 9 && (s.state = :waking; s.t0 = w.t; push!(ST[:log], (w.t, :waking)))
    elseif s.state === :waking
        w.t - s.t0 > 1.4 && (s.state = :roam; new_aim!(s, w))
    else
        d = Vec2f(s.aim[1] - s.pos[1], s.aim[2] - s.pos[2]); n = hypot(d...)
        if n < 0.3f0
            s.state === :backoff && (s.state = :roam)
            w.t >= get(ST, :pause_until, -Inf) && rand(w.rng) < 0.02 && new_aim!(s, w)
        else
            sp = s.state === :backoff ? 1.6f0 : SPEED
            step = d / n * min(n, sp * Float32(dt))
            s.yaw = atan(d[2], d[1]) + (s.state === :backoff ? Float32(pi) : 0f0)     # backs away still looking at you
            s.pos = ground_at(w, (s.pos[1] + step[1], s.pos[2] + step[2]))
        end
        # whoever comes close: a meeting (once per friend every MEET_GAP s)
        last = get!(() -> Dict{Int32,Float64}(), ST, :met)::Dict{Int32,Float64}
        for c in w.creatures
            (c.controlled || c.action === :sleep || c.goal.kind in NG.BUSY_GOALS || c.name == "Lumi") && continue
            flat(c.pos, s.pos) < MEET_R || continue
            w.t - get(last, c.id, -Inf) > MEET_GAP || continue
            last[c.id] = w.t
            meet!(s, game, c)
            break
        end
    end
    # now and then I go and keep Shell company (my friends trust it faster with me beside it)
    me = lumi_of(w)
    if s.state in (:roam, :backoff) && get(ST, :greet, :none) !== :going && me !== nothing && !me.controlled &&
       me.action !== :sleep && me.goal.kind ∉ NG.BUSY_GOALS && w.t >= get(ST, :visit_at, w.t + 1)
        ST[:visit_at] = w.t + 480 + 300 * rand(w.rng)
        NG.leave_interactions!(w, me)
        me.goal = NG.Goal(:stranger, ground_at(w, (s.pos[1], s.pos[2])), :walk, 20.0, w.t + 60, false, 0, false)
        ST[:greet] = :going; ST[:greet_t] = w.t
    end
    haskey(ST, :visit_at) || (ST[:visit_at] = w.t + 240)
    # my greeting when I get there
    if get(ST, :greet, :none) === :going && me !== nothing && !me.controlled && me.goal.kind === :stranger && !me.goal.arrived
        me.goal.target = ground_at(w, (s.pos[1], s.pos[2]))
    end
    if get(ST, :greet, :none) === :going && me !== nothing && !me.controlled
        if me.goal.kind !== :stranger
            # something else took me (a game, a party): back to the beach once it lets go, for a minute at most
            if w.t - get(ST, :greet_t, w.t) > 60
                ST[:greet] = :none
            elseif me.action !== :sleep && me.goal.kind ∉ NG.BUSY_GOALS
                NG.leave_interactions!(w, me)
                me.goal = NG.Goal(:stranger, ground_at(w, (s.pos[1], s.pos[2])), :walk, 20.0, w.t + 60, false, 0, true)
            end
        elseif flat(me.pos, s.pos) < 2.2f0 || me.goal.arrived
            me.yaw = atan(s.pos[2] - me.pos[2], s.pos[1] - me.pos[1]) - NG.species_of(me).heading
            me.goal = NG.Goal(:stranger, me.pos, :think, 6.0, w.t + 6, true, 0, false); me.action = :think
            NG.say!(w, me, get(ST, :visits, 0) == 0 ? "Oh! Hello there... where did YOU come from? I'll call you Shell." :
                           VISIT_LINES[mod1(get(ST, :visits, 0), length(VISIT_LINES))]; duration = 3.5)
            ST[:visits] = get(ST, :visits, 0) + 1
            ST[:happy_until] = w.t + 2
            NG.emit!(w, :stranger_visit; visits = ST[:visits])
            ST[:greet] = :done
            push!(ST[:log], (w.t, :greeted))
        end
    end
    draw!(s, game)
    if game.dash !== nothing && w.t >= get(ST, :save_at, -Inf)
        ST[:save_at] = w.t + 60
        NG.write_json(state_file(game), Dict("arrived" => get(ST, :arrived, false), "trust" => ST[:trust],
                                             "pos" => [s.pos[1], s.pos[2]], "state" => string(s.state),
                                             "visits" => get(ST, :visits, 0)))
    end
end

"The camera goes to the beach while it comes in and I go to meet it."
function arrival_moment(w)
    s = ST[:sys]
    s.state in (:ashore, :waking) || get(ST, :greet, :none) === :going || return nothing
    me = lumi_of(w)
    me === nothing || me.controlled ? nothing : me.id
end
function arrival_view(w)
    s = ST[:sys]
    (s.state in (:ashore, :waking) || get(ST, :greet, :none) === :going) || return nothing
    me = lumi_of(w)
    (me === nothing || me.controlled) && return nothing
    return (me.id, Point3f[me.pos, s.pos])
end

function NG.start!(s::Stranger, game)
    ST[:sys] = s
    delete!(ST, :plot)
    ST[:trust] = Dict{String,Float64}()
    f = state_file(game)
    if isfile(f)
        d = NG.read_json(f)
        ST[:arrived] = get(d, "arrived", false)
        ST[:visits] = Int(get(d, "visits", get(ST, :visits, 0)))      # (so a restart does not name it all over again)
        for (k, v) in get(d, "trust", Dict())
            ST[:trust][String(k)] = Float64(v)
        end
        if ST[:arrived] && haskey(d, "pos")
            s.pos = ground_at(game.world, Point2f(Float32(d["pos"][1]), Float32(d["pos"][2]))); s.state = :roam; new_aim!(s, game.world)
        end
    else
        ST[:arrived] = false
    end
    push!(NG.BUSY_GOALS, :stranger)
    NG.CAMERA_GROUPS["stranger"] = arrival_view
    isdefined(Main, :BIG_MOMENTS) && (Main.BIG_MOMENTS["stranger"] = arrival_moment)
    isdefined(Main, :LUMI_DOING) && (Main.LUMI_DOING[:stranger] = "meeting someone new")
    return nothing
end

function NG.stop!(s::Stranger, game)
    delete!(NG.CAMERA_GROUPS, "stranger")
    isdefined(Main, :BIG_MOMENTS) && delete!(Main.BIG_MOMENTS, "stranger")
    for k in (:plot, :mesh)
        haskey(ST, k) && ST[k].parent !== nothing && delete!(ST[k].parent, ST[k])
        delete!(ST, k)
    end
end

register!(Stranger())
