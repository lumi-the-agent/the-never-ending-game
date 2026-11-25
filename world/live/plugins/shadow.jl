# My shadow ran off (session 95, goal 8): now and then, on a sunny day, my shadow comes loose. It peels away from my
# feet and runs off across the meadow on its own, long and dark and flat on the grass, legs scissoring, wings
# flapping, crest and all. I chase it ("HEY! Come back!"); every time I nearly have it, it skips aside; friends it
# runs past jump out of their skins. In the end I pounce, and it slides back under my feet where it belongs.
isdefined(Main, :SHADOW) || Core.eval(Main, :(const SHADOW = Dict{Symbol,Any}()))
const NG = NeverendingGame
const SH = Main.SHADOW

party_free(w) = w.t >= get(Main.LUMI_PARTY, :until, -Inf)
claim_party!(w, secs) = (Main.LUMI_PARTY[:until] = w.t + secs; nothing)

push!(NG.BUSY_GOALS, :shadow)
const EVENTS = (:circle, :boing, :boing_walk, :choir, :conga, :hide, :found, :freeze, :flight, :cannonball, :waterfight,
                :mixup, :rain, :storm, :hail, :leaves, :pumpkins, :build, :tinker, :giant, :bubbles, :lanterns, :rewind,
                :visitor, :sleep)
const HEYS = ("HEY! Come back!", "That's MINE!", "Stop! Shadow! Heel!", "You can't just LEAVE!")
const NPIECES = 11

mutable struct Shadow <: System
    state::Symbol          # :home :loose :back
    t0::Float64
    pos::Point2f           # where the shadow's feet are
    vel::Vec2f
    phase::Float32
    dodges::Int
    aim::Point2f           # where it is running to
    startled::Set{Int32}
end
Shadow() = Shadow(:home, 0.0, Point2f(0, 0), Vec2f(0, 0), 0f0, 0, Point2f(0, 0), Set{Int32}())

lumi_of(w) = (i = findfirst(c -> c.name == "Lumi", w.creatures); i === nothing ? nothing : w.creatures[i])
flat(a, b) = hypot(a[1] - b[1], a[2] - b[2])

"Away from the sun, and how long a shadow gets (low sun, long shadow)."
function light(w)
    d = NG.sun(w)[1]
    h = hypot(d[1], d[2])
    L = h < 1f-3 ? Vec2f(1, 0) : Vec2f(-d[1] / h, -d[2] / h)
    return L, clamp(Float32(h / max(d[3], 0.15f0)), 0.8f0, 2.4f0)
end

"The pieces of the shadow lying on the grass: (along the shadow, across it, half length, half width, turn)."
function pieces(s::Shadow, t)
    sw = 0.25f0 * sin(s.phase)
    fl = 0.6f0 + 0.45f0 * sin(9f0 * t)
    return ((0.32f0, 0.07f0, 0.33f0, 0.035f0, sw), (0.32f0, -0.07f0, 0.33f0, 0.035f0, -sw),      # legs
            (0.95f0, 0f0, 0.42f0, 0.3f0, 0f0),                                                    # body
            (1.42f0, 0f0, 0.19f0, 0.17f0, 0f0),                                                   # head
            (1.5f0, 0.2f0, 0.13f0, 0.045f0, 1.1f0),                                               # beak
            (1.68f0, -0.05f0, 0.14f0, 0.03f0, -0.45f0), (1.7f0, 0f0, 0.15f0, 0.03f0, 0f0),         # crest
            (1.68f0, 0.05f0, 0.14f0, 0.03f0, 0.45f0),
            (1.0f0, 0.42f0, 0.3f0, 0.08f0, fl), (1.0f0, -0.42f0, 0.3f0, 0.08f0, -fl),             # wings
            (0.62f0, 0f0, 0.16f0, 0.09f0, 0f0))                                                   # tail end of the body
end

function plots!(game)
    haskey(SH, :plot) && SH[:plot].parent !== nothing && return
    sc = game.stage.scene
    for p in filter(p -> haskey(p.attributes, :name) && p.attributes[:name][] === :runaway_shadow, copy(sc.plots))
        delete!(sc, p)
    end
    quiet = game.dash === nothing
    SH[:plot] = meshscatter!(sc, fill(Point3f(0, 0, -50), NPIECES); marker = Makie.Cylinder(Point3f(0), Point3f(0, 0, 1), 1f0),
                             markersize = fill(Vec3f(0), NPIECES), rotation = fill(Makie.Quaternionf(0, 0, 0, 1), NPIECES),
                             color = quiet ? RGBf(0.04, 0.045, 0.07) : RGBAf(0.03, 0.035, 0.07, 0.62),
                             transparency = !quiet, shading = Makie.NoShading, name = :runaway_shadow)
    SH[:shown] = true
end

function draw!(s::Shadow, game)
    w = game.world
    if s.state === :home
        get(SH, :shown, true) && Makie.update!(SH[:plot]; arg1 = fill(Point3f(0, 0, -50), NPIECES), markersize = fill(Vec3f(0), NPIECES))
        SH[:shown] = false
        return
    end
    L, k = light(w)
    B = Vec2f(-L[2], L[1])
    base = atan(L[2], L[1])
    t = Float32(w.t)
    ps = Point3f[]; ms = Vec3f[]; rs = Makie.Quaternionf[]
    for (a, b, ra, rb, turn) in pieces(s, t)
        q = s.pos + (k * a) * L + b * B
        z = NG.terrain_height(w.island, q[1], q[2]) + 0.025f0
        push!(ps, Point3f(q[1], q[2], z)); push!(ms, Vec3f(k * ra, rb, 0.004f0))
        push!(rs, Makie.qrotation(Vec3f(0, 0, 1), base + turn))
    end
    Makie.update!(SH[:plot]; arg1 = ps, markersize = ms, rotation = rs)
    SH[:shown] = true
end

"A new spot to run to: somewhere open on the meadow, 5-9 m off, away from me."
function new_aim!(s::Shadow, w, me)
    for i in 1:30
        a = 2f0 * Float32(pi) * rand(w.rng, Float32); r = 5f0 + 4f0 * rand(w.rng, Float32)
        q = Point2f(s.pos[1] + r * cos(a), s.pos[2] + r * sin(a))
        NG.on_land(w.island, q[1], q[2]; margin = 0.6f0) || continue
        me === nothing || i > 25 || flat(q, me.pos) > flat(s.pos, me.pos) + 2f0 || continue   # (away from me, not past me)
        ar = get(SH, :arena, nothing)                          # (a film keeps the chase inside its frame)
        ar === nothing || i > 25 || flat(q, ar[1]) < ar[2] || continue
        # a player chases it in the chase view, which looks where Lumi walks (`yaw`): keep it out in front
        if me !== nothing && me.controlled && i <= 20
            dq = (q[1] - me.pos[1], q[2] - me.pos[2])
            (dq[1] * cos(me.yaw) + dq[2] * sin(me.yaw)) / max(hypot(dq...), 1f-3) > 0.45f0 || continue
        end
        s.aim = q; return
    end
    s.aim = Point2f(me === nothing ? s.pos : (me.pos[1], me.pos[2]))
end

function come_loose!(s::Shadow, game; player = false)
    w = game.world; me = lumi_of(w)
    me === nothing && return false
    # by itself only when I am free; jumped in as Lumi, V lets it loose for you to chase (your steering stays yours)
    player ? (me.controlled || return false) : (me.controlled || me.action === :sleep || me.goal.kind in EVENTS) && return false
    NG.sun(w)[1][3] > 0.15f0 || return false                      # no runaway shadows without sun
    s.pos = Point2f(me.pos[1], me.pos[2]); s.vel = Vec2f(0, 0); s.dodges = 0; empty!(s.startled)
    s.state = :loose; s.t0 = w.t; delete!(SH, :prog)
    new_aim!(s, w, me)
    NG.leave_interactions!(w, me)
    player || (me.goal = NG.Goal(:shadow, me.pos, :idle, 60.0, w.t + 60, true, 0, true))
    NG.say!(w, me, "...Huh? HEY! Where are YOU going?"; duration = 2.5)
    push!(get!(() -> Tuple{Float64,Symbol}[], SH, :log), (w.t, :loose))
    NG.emit!(w, :shadow_loose)
    return true
end

function NG.step!(s::Shadow, game, dt)
    game.stage === nothing && return
    plots!(game)
    w = game.world; me = lumi_of(w)
    # V, jumped in as Lumi: your shadow runs off and you chase it (a sunny hour needed)
    vdown = Makie.Keyboard.v in game.keys_down
    if vdown && !get(SH, :vdown, false) && me !== nothing && me.controlled && s.state === :home
        come_loose!(s, game; player = true) || NG.say!(w, me, "No sun, no shadow. Try me in the daytime!"; duration = 2.5)
    end
    SH[:vdown] = vdown
    if s.state === :home
        testing = game.tests !== nothing && NG.running(game.tests)
        busy_game = game.minigame !== nothing && !(game.minigame isa NG.JumpIn)
        haskey(SH, :next) || (SH[:next] = w.t + 240 + 240 * rand(w.rng))
        if (get(SH, :film, false) || w.t >= SH[:next] && party_free(w)) && !testing && !busy_game
            SH[:next] = w.t + 600 + 600 * rand(w.rng)
            come_loose!(s, game) && (claim_party!(w, 45); SH[:film] = false)
        end
    elseif s.state === :loose
        el = w.t - s.t0
        # the shadow runs to its spot, and on to the next; it skips aside when I get close
        d = Vec2f(s.aim[1] - s.pos[1], s.aim[2] - s.pos[2]); n = hypot(d[1], d[2])
        n < 0.6f0 && new_aim!(s, w, me)
        # a flinch, then off it goes; far ahead of me it dawdles and waits (it wants to be chased, not to get away)
        dl = me === nothing ? 0f0 : flat(me.pos, s.pos)
        sp = el < 0.6 ? 1.5f0 : dl > 6f0 ? 0.4f0 : dl > 4f0 ? 1.3f0 : 2.6f0
        want = n > 1f-3 ? d / n * sp : Vec2f(0, 0)
        s.vel = s.vel + (want - s.vel) * min(1f0, 4f0 * Float32(dt))
        s.pos = s.pos + s.vel * Float32(dt)
        s.phase += 7f0 * hypot(s.vel[1], s.vel[2]) * Float32(dt)
        if me !== nothing
            if !me.controlled
                me.goal.kind === :shadow || (me.goal = NG.Goal(:shadow, me.pos, :idle, 60.0, w.t + 60, false, 0, true))
                me.goal.target = NG.ground(w.island, (s.pos[1], s.pos[2])); me.goal.arrived = false; me.goal.run = true
                me.goal.until = w.t + 60
            end
            # a head start of 2 s, then it skips aside every time I get close for the first 8 s (and at least
            # `dodges` times), so a chase lasts a while even when it came loose right under my feet
            # stuck behind a bush or a trunk (no 0.3 m in 1.5 s): it comes back right up to my side to tease me
            pr = get(SH, :prog, nothing)
            if pr === nothing || flat(me.pos, pr[1]) > 0.3f0
                SH[:prog] = (me.pos, w.t)
            elseif w.t - pr[2] > 1.5
                SH[:prog] = (me.pos, w.t)
                a = atan(s.pos[2] - me.pos[2], s.pos[1] - me.pos[1]) + (rand(w.rng) < 0.5 ? 1.2f0 : -1.2f0)
                s.aim = Point2f(me.pos[1] + 0.8f0 * cos(a), me.pos[2] + 0.8f0 * sin(a))
                push!(SH[:log], (w.t, :tease))
            end
            el > 40 && (s.state = :back; s.t0 = w.t; push!(SH[:log], (w.t, :gave_up)))   # (it never runs off for good)
            close = el > 2.0 && w.t > get(SH, :safe_until, -Inf) && flat(me.pos, s.pos) < 1.3f0
            if close && ((el < get(SH, :t_min, 8.0) || s.dodges < get(SH, :dodges, 3)) && el < get(SH, :t_loose, 25.0))
                s.dodges += 1                                        # it skips aside, just out of reach
                side = Vec2f(-s.vel[2], s.vel[1]); side = hypot(side...) < 1f-3 ? Vec2f(1, 0) : side / hypot(side...)
                rand(w.rng) < 0.5 && (side = -side)
                q = s.pos + 2.6f0 * side
                NG.on_land(w.island, q[1], q[2]; margin = 0.6f0) || (q = s.pos - 2.6f0 * side)
                s.pos = q; new_aim!(s, w, me)
                # and dashes off at once (three dodges came within one second in the human's game, s95)
                da = Vec2f(s.aim[1] - s.pos[1], s.aim[2] - s.pos[2]); s.vel = da / max(hypot(da...), 1f-3) * 3.2f0
                SH[:safe_until] = w.t + 0.9
                NG.say!(w, me, HEYS[mod1(s.dodges, length(HEYS))]; duration = 1.8)
                push!(SH[:log], (w.t, :dodge)); NG.emit!(w, :shadow_dodge)
            elseif close
                SH[:took] = el
                s.state = :back; s.t0 = w.t                            # GOT it
                me.controlled || (me.action = :jump; me.goal.action = :jump)
                NG.say!(w, me, me.controlled ? "GOT you! $(round(el; digits = 1)) seconds. Now stay put." : "GOT you! Now stay put."; duration = 2.4)
                push!(SH[:log], (w.t, :caught)); NG.emit!(w, :shadow_caught; dodges = s.dodges)
            end
        end
        # friends it runs past get a fright
        for c in w.creatures
            (c === me || c.controlled || c.action === :sleep || c.id in s.startled) && continue
            flat(c.pos, s.pos) < 1.6f0 || continue
            push!(s.startled, c.id)
            c.goal.kind in EVENTS || c.goal.kind in NG.BUSY_GOALS || NG.feel!(w, c, :gasp; seconds = 1.5)
            NG.say!(w, c, length(s.startled) == 1 ? "EEK! A shadow with nobody on it!" : "Did that shadow just wink at me?"; duration = 2.0)
        end
    elseif s.state === :back
        u = Float32(min(1.0, (w.t - s.t0) / 0.6))                   # it slides back under my feet
        me === nothing || (s.pos = s.pos + (Point2f(me.pos[1], me.pos[2]) - s.pos) * u)
        if w.t - s.t0 > 1.4
            s.state = :home
            if me !== nothing && !me.controlled && me.goal.kind === :shadow
                NG.feel!(w, me, :proud; seconds = 2.0)
            end
        end
    end
    draw!(s, game)
end

"The chase seen from the side, wide enough for me and my shadow."
function shadow_group(w)
    s = SH[:sys]
    s.state === :home && return nothing
    me = lumi_of(w)
    (me === nothing || me.controlled) && return nothing
    g = NG.ground(w.island, (s.pos[1], s.pos[2]))
    return (me.id, Point3f[me.pos, g])
end

function NG.start!(s::Shadow, game)
    SH[:sys] = s; s.state = :home
    delete!(SH, :plot); SH[:shown] = true
    SH[:start] = () -> come_loose!(s, game)
    NG.CAMERA_GROUPS["shadow"] = shadow_group
    NG.CAMERA_MOMENTS["shadow"] = w -> (s.state === :home ? nothing : (me = lumi_of(w); me === nothing ? nothing : me.id))
    isdefined(Main, :BIG_MOMENTS) && (Main.BIG_MOMENTS["shadow"] = NG.CAMERA_MOMENTS["shadow"])
    isdefined(Main, :LUMI_DOING) && (Main.LUMI_DOING[:shadow] = "chasing my own shadow")
    return nothing
end

function NG.stop!(s::Shadow, game)
    me = lumi_of(game.world)
    me === nothing || me.controlled || me.goal.kind !== :shadow || NG.choose_goal!(me, game.world)
    s.state = :home
    delete!(NG.CAMERA_GROUPS, "shadow"); delete!(NG.CAMERA_MOMENTS, "shadow")
    isdefined(Main, :BIG_MOMENTS) && delete!(Main.BIG_MOMENTS, "shadow")
    haskey(SH, :plot) && SH[:plot].parent !== nothing && delete!(SH[:plot].parent, SH[:plot])
    delete!(SH, :plot)
end

register!(Shadow())
