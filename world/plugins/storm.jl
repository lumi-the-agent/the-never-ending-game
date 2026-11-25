# A thunderstorm (session 76, something the island never had): a black cloud rolls in from the sea, the rain
# comes down, lightning cracks into the meadow, and every friend runs squealing to huddle under the Big Boing
# toadstool. Lumi stays out in it ("It's only a bit of weather!") until the last bolt hits its crest: a puff of
# soot, the crest on end, "...I'm fine." The friends fall about laughing and the cloud moves on.
# Every strike is logged in `ST[:strikes]` as (w.t, kind), so a film can put the thunder under it.
isdefined(Main, :STORM) || Core.eval(Main, :(const STORM = Dict{Symbol,Any}()))
const NG = NeverendingGame
const ST = Main.STORM

const GAP = (3600.0, 6000.0)              # sim seconds between two storms
const T_GATHER = 4.0                      # the cloud rolls in
const STRIKES = (5.0, 7.4, 9.6, 12.4)     # s after the start; the last one hits Lumi
const T_END = 21.0
const CLOUD_Z = 8f0                       # the cloud's middle over the ground (12 was out of every frame)
const NPUFF = 46
const NSEG = 10                           # pieces of one bolt
const NSOOT = 22                          # small grey puffs (14 big black ones read as cartoon bombs, s76 still)
const NMARK = 3
const BOLT = RGBf(0.86, 0.91, 1.0)
const KEEP = (:follow, :interact, :answer, :circle, :build, :tinker, :kite, :kitewatch, :boing, :boing_walk, :sleep,
              :paint, :giant, :choir, :conga, :hide, :found, :freeze, :sneezed, :hiccup, :flight, :egg, :lesson,
              :snowman, :soar, :storm, :toadstool, :blossom)
# a thunderstorm beats any pastime or chore (races, fishing, pebbles, painting); not sleep, a parade or a big event
const EVENTS = (:follow, :sleep, :circle, :boing, :boing_walk, :choir, :conga, :hide, :found, :freeze, :flight,
                :paint, :giant, :egg, :lesson, :soar, :snowman, :storm, :build)
const LUMI_LINES = ("WOOO! Did you SEE that?!", "It's only a bit of weather!", "Come on out, it's FUN!")
const SCREAMS = ("EEEEEK!", "Make room!", "Lumi, get in here!", "I'm not scared, YOU'RE scared!", "Squeeze up!", "Mummy!")
const LAUGHS = ("HA HA HA!", "Your CREST!", "Fine, says Lumi!", "Pffffff!", "Do it again!", "Ha ha... are you OK?")

push!(NG.BUSY_GOALS, :storm)

mutable struct Storm <: System
    state::Symbol          # :idle :on
    t0::Float64
    next_t::Float64
    lumi::Int32
    centre::Point3f        # the toadstool, on the ground
    spot::Point3f          # where Lumi stands out in the open
    from::Vec2f            # where the cloud comes from (flat, unit)
    struck::Int
    said::Int
    huddle::Vector{Int32}
    view::Tuple{Point3f,Point3f}
end
Storm() = Storm(:idle, 0.0, -1.0, 0, Point3f(0), Point3f(0), Vec2f(1, 0), 0, 0, Int32[], (Point3f(0), Point3f(0)))

lumi_of(w) = (i = findfirst(c -> c.name == "Lumi", w.creatures); i === nothing ? nothing : w.creatures[i])
ease(u) = (u = clamp(u, 0, 1); u * u * (3 - 2u))
"Turn `c` towards `yaw` over about half a second (goal 6: setting the yaw at once snapped it round in one frame)."
turn_to!(c, yaw, dt) = (d = mod(yaw - c.yaw + Float32(pi), 2f0 * Float32(pi)) - Float32(pi); c.yaw += d * min(1f0, 6f0 * Float32(dt)))
free(c) = !c.controlled && c.action !== :sleep && c.goal.kind ∉ KEEP && c.goal.kind ∉ NG.BUSY_GOALS

"A standing spot `r` m from `c` in direction `d` (turned a little until it is on land)."
function spot_from(w, c, d, r)
    for da in (0f0, 0.4f0, -0.4f0, 0.8f0, -0.8f0, 1.4f0, -1.4f0, 2.2f0, -2.2f0, Float32(pi))
        a = atan(d[2], d[1]) + da
        x = c[1] + r * cos(a); y = c[2] + r * sin(a)
        NG.on_land(w.island, x, y; margin = 0.4f0) && return NG.ground(w.island, (x, y))
    end
    return nothing
end

function start_storm!(s::Storm, game; player = false)
    w = game.world
    (isdefined(Main, :BOING) && haskey(Main.BOING, :center)) || return false
    me = lumi_of(w)
    me === nothing && return false
    b = Main.BOING[:center]
    s.centre = NG.ground(w.island, (b[1], b[2]))
    d = Vec2f(me.pos[1] - b[1], me.pos[2] - b[2]); n = hypot(d[1], d[2])
    d = n < 0.5f0 ? Vec2f(1, 0) : d / n
    # already out in the meadow near the toadstool: it stays where it is (a walk can wedge between trunks)
    sp = player || 3f0 < n < 14f0 ? me.pos : spot_from(w, s.centre, d, 5f0)
    sp === nothing && return false
    set_spot!(s, sp)
    s.lumi = me.id; s.state = :on; s.t0 = w.t; s.struck = 0; s.said = 0
    empty!(s.huddle)
    ST[:strikes] = Tuple{Float64,Symbol}[]
    ST[:marks] = Point3f[]
    delete!(ST, :bolt); delete!(ST, :soot)
    # called by the player (T as Lumi, s77): the storm comes to them and leaves the steering alone
    ST[:player] = player
    if !player
        NG.leave_interactions!(w, me)
        me.goal = NG.Goal(:storm, s.spot, :proud, 60.0, w.t + 60, false, 0, true)
    end
    NG.say!(w, me, player ? "Uh oh. Was that... my cloud?" : "Ooh, look at that cloud!"; duration = 2.5)
    ST[:waited] = 0.0; ST[:check] = (me.pos, w.t)
    NG.emit!(w, :storm_start; who = me.name)
    return true
end

"""
Where Lumi stands in the storm, and the one framing for the whole storm (s74: no switching between states):
from the side, the toadstool and Lumi both in the frame, tilted up a little for the cloud and the bolts.
"""
function set_spot!(s::Storm, sp)
    s.spot = sp
    u = Vec2f(s.spot[1] - s.centre[1], s.spot[2] - s.centre[2]); u = u / max(hypot(u[1], u[2]), 1f-3)
    v = Vec2f(-u[2], u[1])
    s.from = v
    mid = (s.centre + s.spot) / 2
    d = 8f0 + 0.6f0 * hypot(s.spot[1] - s.centre[1], s.spot[2] - s.centre[2])
    eye = mid + Point3f(d * v[1] - 0.8f0 * u[1], d * v[2] - 0.8f0 * u[2], 1.8f0)
    s.view = (eye, mid + Point3f(0, 0, 3.4f0))
end

"Everyone free near the toadstool runs for it, screaming, and huddles round the stem."
function run_for_cover!(s::Storm, w)
    cs = [c for c in w.creatures if c.id != s.lumi && c.goal.kind ∉ EVENTS && !c.controlled &&
          c.action !== :sleep && hypot(c.pos[1] - s.centre[1], c.pos[2] - s.centre[2]) < 30]
    n = length(cs)
    for (i, c) in enumerate(cs)
        a = 2f0 * Float32(pi) * (i - 1) / max(n, 1) + 0.3f0
        r = 1.0f0 + 0.45f0 * isodd(i)
        target = NG.ground(w.island, (s.centre[1] + r * cos(a), s.centre[2] + r * sin(a)))
        NG.leave_interactions!(w, c)
        c.goal = NG.Goal(:storm, target, :scared, 60.0, w.t + 60, false, 0, true)
        push!(s.huddle, c.id)
        i <= 3 && NG.say!(w, c, SCREAMS[mod1(i + s.struck, length(SCREAMS))]; duration = 2.0)
    end
end

function bolt_points(w, target)
    top = target + Point3f(1.6f0 * (rand(w.rng, Float32) - 0.5f0), 1.6f0 * (rand(w.rng, Float32) - 0.5f0), 0)
    top = Point3f(top[1], top[2], target[3] + CLOUD_Z - 1.5f0)
    pts = Point3f[]
    for k in 0:NSEG
        u = k / NSEG
        p = top + (target - top) * Float32(u)
        j = 0.75f0 * sin(Float32(pi) * Float32(u))
        push!(pts, k == 0 || k == NSEG ? p : p + Point3f(j * (2rand(w.rng, Float32) - 1), j * (2rand(w.rng, Float32) - 1), 0))
    end
    return pts
end

function strike!(s::Storm, w, me, k)
    if k == length(STRIKES)
        # the last one: Lumi's crest
        target = me.pos + Point3f(0, 0, 1.55f0)
        ST[:soot] = (target, w.t)
        me.controlled || (me.goal = NG.Goal(:storm, me.pos, :gasp, 60.0, w.t + 60, true, 0, false))
        me.action = :gasp
        NG.say!(w, me, "!!!"; duration = 1.6)
        NG.emit!(w, :storm_zap; who = me.name)
    else
        a = 2f0 * Float32(pi) * rand(w.rng, Float32)
        p = spot_from(w, me.pos, Vec2f(cos(a), sin(a)), 3f0 + 2f0 * rand(w.rng, Float32))
        target = p === nothing ? me.pos + Point3f(3, 0, 0) : p
        push!(ST[:marks], target)
        NG.say!(w, me, LUMI_LINES[k]; duration = 2.0)
        k == 1 && run_for_cover!(s, w)
    end
    ST[:bolt] = (bolt_points(w, target), w.t)
    push!(ST[:strikes], (w.t, k == length(STRIKES) ? :zap : :strike))
    NG.emit!(w, :storm_strike; k)
end

function finish!(s::Storm, game)
    w = game.world
    for id in s.huddle
        c = NG.creature(w, id)
        c !== nothing && !c.controlled && c.goal.kind === :storm && NG.choose_goal!(c, w)
    end
    me = NG.creature(w, s.lumi)
    me !== nothing && !me.controlled && me.goal.kind === :storm && NG.choose_goal!(me, w)
    empty!(s.huddle)
    ST[:player] = false
    s.state = :idle
    s.next_t = w.t + GAP[1] + (GAP[2] - GAP[1]) * rand(w.rng)
    NG.emit!(w, :storm_end)
end

function NG.step!(s::Storm, game, dt)
    w = game.world
    s.next_t < 0 && (s.next_t = w.t + 2400.0)
    draw!(s, game)
    # T while the player is Lumi calls the storm (perfectionist-0076: the best gag could not be played)
    tdown = Makie.Keyboard.t in game.keys_down
    if tdown && !get(ST, :tdown, false) && s.state === :idle
        me = lumi_of(w)
        me !== nothing && me.controlled && start_storm!(s, game; player = true)
    end
    ST[:tdown] = tdown
    if s.state === :idle
        testing = game.tests !== nothing && NG.running(game.tests)
        busy_game = game.minigame !== nothing && !(game.minigame isa NG.JumpIn)
        if w.t >= s.next_t && !testing && !busy_game && 10 < 24 * NG.daytime(w) < 17
            me = lumi_of(w)
            event = any(c -> c.goal.kind in KEEP && c.goal.kind ∉ (:follow, :sleep, :interact, :answer), w.creatures)
            ok = !event && me !== nothing && free(me) && start_storm!(s, game)
            ok || (s.next_t = w.t + 300)
        end
        return
    end
    me = NG.creature(w, s.lumi)
    pl = get(ST, :player, false)
    if me === nothing || me.controlled && !pl || game.minigame !== nothing && !(game.minigame isa NG.JumpIn)
        return finish!(s, game)
    end
    el = w.t - s.t0
    if !me.controlled
        me.goal.kind === :storm || (me.goal = NG.Goal(:storm, s.spot, :proud, 60.0, w.t + 60, false, 0, true))
        me.goal.until = w.t + 60
    end
    # the first bolt waits until Lumi is out in the open, in the storm's view (at most 20 s: it may be stuck)
    # no progress in 3 s: the storm comes to where Lumi is
    if !pl && s.struck == 0 && !me.goal.arrived && w.t - ST[:check][2] > 3
        if hypot(me.pos[1] - ST[:check][1][1], me.pos[2] - ST[:check][1][2]) < 0.4f0
            set_spot!(s, me.pos)
            me.goal = NG.Goal(:storm, me.pos, :proud, 60.0, w.t + 60, true, 0, false)
        end
        ST[:check] = (me.pos, w.t)
    end
    if !pl && s.struck == 0 && !me.goal.arrived && el > T_GATHER && get(ST, :waited, 0.0) < 20
        ST[:waited] = get(ST, :waited, 0.0) + (el - T_GATHER)
        s.t0 = w.t - T_GATHER
        el = T_GATHER
    end
    while s.struck < length(STRIKES) && el >= STRIKES[s.struck + 1]
        s.struck += 1
        strike!(s, w, me, s.struck)
    end
    # one another plugin took away has left the huddle
    filter!(id -> (c = NG.creature(w, id); c !== nothing && c.goal.kind === :storm), s.huddle)
    if s.struck == length(STRIKES)
        h = el - STRIKES[end]
        act = h < 1.8 ? :gasp : h < 4.2 ? :sigh : :laugh
        me.controlled || (me.action = act; me.goal.action = act)
        if h >= 1.8 && s.said == 0
            s.said = 1
            NG.say!(w, me, "...I'm fine."; duration = 2.6)
        elseif h >= 3.0 && s.said == 1
            s.said = 2
            for (i, id) in enumerate(s.huddle)
                c = NG.creature(w, id)
                c.goal = NG.Goal(:storm, c.pos, :laugh, 60.0, w.t + 60, true, 0, false)
                c.action = :laugh
                i <= 3 && NG.say!(w, c, LAUGHS[mod1(i, length(LAUGHS))]; duration = 2.4)
            end
        end
    elseif !me.controlled && me.goal.arrived
        # out in the open, wings out at the sky
        me.action = :proud; me.goal.action = :proud
        turn_to!(me, atan(s.from[2], s.from[1]), dt)
    end
    # the huddle trembles under the cap (the shower's own roles would make some dance)
    for id in s.huddle
        c = NG.creature(w, id)
        c.goal.arrived && (c.action = c.goal.action)
        # laughing, they turn to look at Lumi
        c.goal.arrived && c.action === :laugh &&
            turn_to!(c, atan(me.pos[2] - c.pos[2], me.pos[1] - c.pos[1]) - NG.species_of(c).heading, dt)
    end
    el >= T_END && finish!(s, game)
    return
end

# ── what you see: the black cloud, the bolt, scorch marks, a puff of soot ────────────────────────────
function plots!(game)
    haskey(ST, :plots) && first(values(ST[:plots])).parent !== nothing && return ST[:plots]
    sc = game.stage.scene
    for p in filter(p -> haskey(p.attributes, :name) && p.attributes[:name][] in (:storm_cloud, :storm_bolt, :storm_soot, :storm_marks), sc.plots)
        delete!(sc, p)
    end
    hidden(n) = (fill(Point3f(0, 0, -60), n), fill(Vec3f(0), n))
    q0 = Makie.Quaternionf(0, 0, 0, 1)
    P = Dict{Symbol,Any}()
    ps, ms = hidden(NPUFF)
    cols = [RGBf(0.30f0 + 0.2f0 * (i % 3 == 0), 0.32f0 + 0.2f0 * (i % 3 == 0), 0.37f0 + 0.18f0 * (i % 3 == 0)) for i in 1:NPUFF]
    P[:cloud] = meshscatter!(sc, ps; marker = Sphere(Point3f(0), 1f0), markersize = ms, color = cols, name = :storm_cloud)
    ps, ms = hidden(NSEG)
    # a quiet copy (a traced film) makes the bolt a light: the whole scene flashes with it
    P[:bolt] = game.dash === nothing ?
        meshscatter!(sc, ps; marker = Cylinder(Point3f(0), Point3f(0, 0, 1), 1f0), markersize = ms, rotation = fill(q0, NSEG),
                     color = BOLT, shading = Makie.NoShading, material = NG.Hikari.Emission(color = (0.86, 0.91, 1.0), strength = 40.0),
                     name = :storm_bolt) :
        meshscatter!(sc, ps; marker = Cylinder(Point3f(0), Point3f(0, 0, 1), 1f0), markersize = ms, rotation = fill(q0, NSEG),
                     color = BOLT, shading = Makie.NoShading, name = :storm_bolt)
    ps, ms = hidden(NSOOT)
    P[:soot] = meshscatter!(sc, ps; marker = Sphere(Point3f(0), 1f0), markersize = ms, color = RGBf(0.36, 0.35, 0.35), name = :storm_soot)
    ps, ms = hidden(NMARK)
    P[:marks] = meshscatter!(sc, ps; marker = Sphere(Point3f(0), 1f0), markersize = ms, color = RGBf(0.13, 0.11, 0.09), name = :storm_marks)
    ST[:plots] = P
end

function draw!(s::Storm, game)
    game.stage === nothing && return
    P = plots!(game)
    w = game.world
    on = s.state === :on
    (on || get(ST, :shown, false)) || return
    ST[:shown] = on
    el = Float32(w.t - s.t0)
    # the cloud: rolls in from the side, stays over the toadstool and Lumi, rolls on
    ps = fill(Point3f(0, 0, -60), NPUFF); ms = fill(Vec3f(0), NPUFF)
    if on
        me_ = NG.creature(w, s.lumi)
        mid = get(ST, :player, false) && me_ !== nothing ? me_.pos : (s.centre + s.spot) / 2   # it follows the player
        k = 45f0 * (1f0 - Float32(ease(el / T_GATHER))) - 45f0 * Float32(ease((el - (T_END - 4)) / 4))
        c = mid + Point3f(k * s.from[1], k * s.from[2], CLOUD_Z) + Point3f(0.4f0 * sin(0.3f0 * el), 0, 0)
        for i in 1:NPUFF
            a = 2.39996f0 * i; r = sqrt(Float32(i) / NPUFF)
            o = Point3f(9.5f0 * r * cos(a), 6.5f0 * r * sin(a), 1.3f0 * (1 - r^2) * (0.7f0 + 0.3f0 * sin(3f0 * i)))
            ps[i] = c + o
            R = 2.7f0 - 1.2f0 * r + 0.35f0 * sin(7f0 * i)
            ms[i] = Vec3f(R, R, 0.7f0 * R)
        end
    end
    Makie.update!(P[:cloud]; arg1 = ps, markersize = ms)
    # the bolt: flickers (on, off, on) for 0.3 s
    bp = fill(Point3f(0, 0, -60), NSEG); bm = fill(Vec3f(0), NSEG); br = fill(Makie.Quaternionf(0, 0, 0, 1), NSEG)
    if on && haskey(ST, :bolt)
        pts, t = ST[:bolt]
        age = w.t - t
        if age < 0.3 && !(0.08 < age < 0.13)
            for k in 1:NSEG
                d = Vec3f(pts[k + 1] - pts[k])
                L = sqrt(sum(abs2, d))
                bp[k] = pts[k]; br[k] = Makie.rotation_between(Vec3f(0, 0, 1), d / max(L, 1f-4))
                bm[k] = Vec3f(0.07f0, 0.07f0, L)
            end
        end
    end
    Makie.update!(P[:bolt]; arg1 = bp, markersize = bm, rotation = br)
    # soot: a dark puff out of Lumi's crest, spreading and thinning
    sp = fill(Point3f(0, 0, -60), NSOOT); sm = fill(Vec3f(0), NSOOT)
    if on && haskey(ST, :soot)
        p, t = ST[:soot]
        age = Float32(w.t - t)
        if age < 3f0
            for i in 1:NSOOT
                a = 2.39996f0 * i; e = 0.9f0 * (i / NSOOT) - 0.3f0
                dir = Vec3f(cos(a) * sqrt(1 - e^2), sin(a) * sqrt(1 - e^2), e)
                sp[i] = p + (0.15f0 + 0.9f0 * sqrt(age)) * dir + Point3f(0, 0, 0.35f0 * age)
                R = (0.1f0 + 0.13f0 * sqrt(age)) * max(0f0, 1f0 - age / 3f0) * (0.75f0 + 0.5f0 * sin(5f0 * i))
                sm[i] = Vec3f(R)
            end
        end
    end
    Makie.update!(P[:soot]; arg1 = sp, markersize = sm)
    mp = fill(Point3f(0, 0, -60), NMARK); mm = fill(Vec3f(0), NMARK)
    if on
        for (i, p) in enumerate(get(ST, :marks, Point3f[]))
            i > NMARK && break
            mp[i] = p + Point3f(0, 0, 0.01f0); mm[i] = Vec3f(0.6f0, 0.6f0, 0.02f0)
        end
    end
    Makie.update!(P[:marks]; arg1 = mp, markersize = mm)
    return
end

function storm_group(w)
    s = ST[:sys]
    s.state === :idle && return nothing
    me = NG.creature(w, s.lumi)
    (me === nothing || me.controlled) && return nothing     # the player's chase camera stays theirs
    return (me.id, Point3f[me.pos, s.centre], s.view)
end

function NG.start!(s::Storm, game)
    ST[:sys] = s
    ST[:start] = () -> start_storm!(s, game)      # a film or a test: Base.invokelatest(Main.STORM[:start])
    delete!(ST, :plots); ST[:shown] = true
    game.stage === nothing || plots!(game)
    moment = w -> s.state === :idle ? nothing : s.lumi
    NG.CAMERA_MOMENTS["storm"] = moment
    isdefined(Main, :BIG_MOMENTS) || Core.eval(Main, :(const BIG_MOMENTS = Dict{String,Any}()))
    Main.BIG_MOMENTS["storm"] = moment
    NG.CAMERA_GROUPS["storm"] = storm_group
    isdefined(Main, :LUMI_DOING) && (Main.LUMI_DOING[:storm] = "Ooh, a storm!")
end

function NG.stop!(s::Storm, game)
    delete!(NG.CAMERA_MOMENTS, "storm")
    delete!(NG.CAMERA_GROUPS, "storm")
    isdefined(Main, :BIG_MOMENTS) && delete!(Main.BIG_MOMENTS, "storm")
    s.state === :idle || finish!(s, game)
    for p in values(get(ST, :plots, Dict{Symbol,Any}()))
        p.parent === nothing || delete!(p.parent, p)
    end
    delete!(ST, :plots)
end

register!(Storm())
