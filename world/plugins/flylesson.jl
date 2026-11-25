# The little one's first flying lesson (session 71): Lumi shows the chick how ("Like this!"): wings out, a big
# hop. The chick flaps and plops down ("peep..."), flaps harder and plops down again... then the third try
# shoots it up in a great arc and it lands right on top of Lumi's head. Lumi: "...okay, that works too."
# The friends nearby laugh, and the chick rides up there for a while before it hops down.
# The chick is egg.jl's (Main.EGG[:chick]); egg.jl draws it, this moves it while a lesson runs (E[:lesson]).
isdefined(Main, :FLYLESSON) || Core.eval(Main, :(const FLYLESSON = Dict{Symbol,Any}()))
const NG = NeverendingGame
const L = Main.FLYLESSON

const GAP = (1200.0, 2000.0)      # sim seconds between two lessons
const RIDE = 60.0                 # seconds on Lumi's head
const KEEP = (:follow, :choir, :answer, :conga, :circle, :rain, :build, :tinker, :kite, :boing, :boing_walk,
              :hide, :found, :freeze, :sneezed, :hiccup, :flight, :paint, :giant, :egg, :storm, :toadstool, :blossom, :swing, :bottle, :leaves)
const TRY = 2.2                   # seconds per failed try (flap, hop, plop, a sad peep)

push!(NG.BUSY_GOALS, :lesson)

mutable struct FlyLesson <: System
    state::Symbol                 # :idle :show :try :launch :ride
    t0::Float64
    next_t::Float64
    lumi::Int32
    tries::Int
    from::Point3f
    said::Int
end
FlyLesson() = FlyLesson(:idle, 0.0, -1.0, 0, 0, Point3f(0), 0)

E() = Main.EGG
chick() = E()[:chick]
lumi_of(w) = (i = findfirst(c -> c.name == "Lumi", w.creatures); i === nothing ? nothing : w.creatures[i])
flat(a, b) = hypot(a[1] - b[1], a[2] - b[2])
ease(u) = (u = clamp(u, 0, 1); u * u * (3 - 2u))
hold!(c, w, action) = (c.goal.until = w.t + 60; c.goal.action = action; c.action = action)
mine(c) = c !== nothing && c.goal.kind === :lesson
head_seat(me) = me.pos + Point3f(0.04f0 * cos(me.yaw), 0.04f0 * sin(me.yaw), 1.56f0)

"Start a lesson: the chick stands 1.2 m in front of Lumi, facing it."
function begin!(s::FlyLesson, game, me)
    w = game.world
    isdefined(Main, :EGG) && haskey(E(), :chick) && chick()[:hatched] || return false
    f = Point3f(cos(me.yaw), sin(me.yaw), 0)
    q = me.pos + 1.2f0 * f
    NG.on_land(w.island, q[1], q[2]; margin = 0.1) || return false
    c = chick()
    E()[:lesson] = true
    c[:pos] = NG.ground(w.island, (q[1], q[2]))
    c[:yaw] = atan(-f[2], -f[1])
    c[:action] = :idle
    s.lumi = me.id; s.state = :show; s.t0 = w.t; s.tries = 0; s.said = 0
    NG.leave_interactions!(w, me)
    me.controlled || (me.goal = NG.Goal(:lesson, me.pos, :proud, 60.0, w.t + 60, true, 0, false))
    NG.say!(w, me, "Like this! Watch me!"; duration = 2.2)
    NG.emit!(w, :lesson_start; who = me.name)
    return true
end

function finish!(s::FlyLesson, game)
    w = game.world
    E()[:lesson] = false
    me = NG.creature(w, s.lumi)
    if me !== nothing && !me.controlled && mine(me)
        NG.choose_goal!(me, w)
    end
    c = chick()
    c[:pos] = NG.ground(w.island, (c[:pos][1], c[:pos][2]))
    s.state = :idle
    s.next_t = w.t + GAP[1] + (GAP[2] - GAP[1]) * rand(w.rng)
    NG.emit!(w, :lesson_end)
end

function NG.step!(s::FlyLesson, game, dt)
    w = game.world
    s.next_t < 0 && (s.next_t = w.t + 400.0)
    if s.state === :idle
        testing = game.tests !== nothing && NG.running(game.tests)
        busy_game = game.minigame !== nothing && !(game.minigame isa NG.JumpIn)
        if w.t >= s.next_t && !testing && !busy_game && 9 < 24 * NG.daytime(w) < 18
            me = lumi_of(w)
            ok = me !== nothing && !me.controlled && me.goal.kind ∉ KEEP && me.goal.kind ∉ NG.BUSY_GOALS &&
                 me.action !== :sleep && begin!(s, game, me)
            ok || (s.next_t = w.t + 90)
        end
        return
    end
    me = NG.creature(w, s.lumi)
    if me === nothing || game.minigame !== nothing && !(game.minigame isa NG.JumpIn)
        return finish!(s, game)
    end
    c = chick()
    ours = !me.controlled && (mine(me) || s.state === :ride)
    el = w.t - s.t0
    if s.state in (:show, :try, :launch) && ours
        mine(me) || (me.goal = NG.Goal(:lesson, me.pos, :proud, 60.0, w.t + 60, true, 0, false))
        me.yaw = atan(c[:pos][2] - me.pos[2], c[:pos][1] - me.pos[1])
    end
    ground = NG.ground(w.island, (c[:pos][1], c[:pos][2]))
    if s.state === :show
        # wings out, flap, a big hop
        ours && hold!(me, w, el < 1.0 ? :proud : el < 1.8 ? :dance : :jump)
        c[:action] = :gasp
        el >= 2.8 && (s.state = :try; s.t0 = w.t; s.tries = 1; s.said = 0; ours && hold!(me, w, :proud))
    elseif s.state === :try
        # flap... hop... plop
        if el < 0.8
            c[:action] = :dance; c[:pos] = ground
        elseif el < 1.5
            u = Float32((el - 0.8) / 0.7)
            c[:pos] = ground + Point3f(0, 0, (0.25f0 + 0.1f0 * s.tries) * 4u * (1 - u))
            c[:action] = :jump
        else
            c[:pos] = ground; c[:action] = :shy
            if s.said < s.tries
                s.said = s.tries
                NG.say!(w, me, s.tries == 1 ? "Almost! Again!" : "Flap HARDER!"; duration = 1.6)
                ours && hold!(me, w, s.tries == 1 ? :laugh : :proud)
            end
        end
        if el >= TRY
            if s.tries < 2
                s.tries += 1; s.t0 = w.t
            else
                s.state = :launch; s.t0 = w.t; s.from = c[:pos]
                ours && hold!(me, w, :proud)
            end
        end
    elseif s.state === :launch
        # flapping like mad... then WHOOSH, up in a great arc and down onto Lumi's head
        if el < 1.0
            c[:action] = :dance
            c[:pos] = ground + Point3f(0, 0, 0.05f0 * abs(sin(Float32(30el))))
        else
            u = Float32(clamp((el - 1.0) / 1.4, 0, 1))
            to = head_seat(me)
            p = s.from + (to - s.from) * Float32(ease(u))
            c[:pos] = p + Point3f(0, 0, 2.6f0 * 4u * (1 - u))
            c[:action] = :jump
            c[:yaw] += Float32(9 * dt) * (1 - u)
            ours && hold!(me, w, :gasp)
            if u >= 1
                s.state = :ride; s.t0 = w.t
                c[:yaw] = me.yaw
                NG.say!(w, me, "...okay. That works too."; duration = 2.6)
                NG.emit!(w, :lesson_landed; who = me.name)
                # the friends nearby laugh (todo #325: feelings on the faces)
                n = 0
                for f in w.creatures
                    (f.id == me.id || f.controlled || f.action === :sleep || f.goal.kind in NG.BUSY_GOALS) && continue
                    flat(f.pos, me.pos) < 10 || continue
                    NG.feel!(w, f, :laugh; seconds = 3.0) && (n += 1)
                    n == 1 && NG.say!(w, f, rand(w.rng, ("Bravo!", "Ha ha ha!", "Nailed it!", "Again!")); duration = 1.8)
                    n >= 4 && break
                end
            end
        end
    else   # :ride
        c[:pos] = head_seat(me)
        c[:yaw] = me.yaw
        c[:action] = el < 3 ? :proud : :idle
        if el > 2.6 && mine(me)
            hold!(me, w, :laugh)
            el > 5 && (NG.choose_goal!(me, w))      # Lumi goes on with its day, the chick stays up there
        end
        el > RIDE && finish!(s, game)
    end
    return
end

"Side view of Lumi and the chick, wide enough for the arc."
function lesson_group(w)
    s = L[:sys]
    (s.state === :idle || s.state === :ride && w.t - s.t0 > 6) && return nothing
    me = NG.creature(w, s.lumi)
    me === nothing && return nothing
    c = chick()
    mid = (me.pos + NG.ground(w.island, (c[:pos][1], c[:pos][2]))) / 2
    side = Point3f(-sin(me.yaw), cos(me.yaw), 0)
    eye = mid + 5.0f0 * side + Point3f(0, 0, 1.7f0)
    return (me.id, Point3f[me.pos, c[:pos]], (eye, mid + Point3f(0, 0, 1.0f0)))
end

function NG.start!(s::FlyLesson, game)
    L[:sys] = s
    isdefined(Main, :EGG) && (Main.EGG[:lesson] = false)
    moment = w -> (s.state === :idle || s.state === :ride && w.t - s.t0 > 6) ? nothing : s.lumi
    NG.CAMERA_MOMENTS["flylesson"] = moment
    isdefined(Main, :BIG_MOMENTS) || Core.eval(Main, :(const BIG_MOMENTS = Dict{String,Any}()))
    Main.BIG_MOMENTS["flylesson"] = moment
    NG.CAMERA_GROUPS["flylesson"] = lesson_group
    isdefined(Main, :LUMI_DOING) && (Main.LUMI_DOING[:lesson] = "Teaching the little one to fly!")
end

function NG.stop!(s::FlyLesson, game)
    delete!(NG.CAMERA_MOMENTS, "flylesson")
    delete!(NG.CAMERA_GROUPS, "flylesson")
    isdefined(Main, :BIG_MOMENTS) && delete!(Main.BIG_MOMENTS, "flylesson")
    s.state === :idle || finish!(s, game)
end

register!(FlyLesson())
