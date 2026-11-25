# Someone's watching (session 93, goal 8): the island knows when someone opens its page. Each browser that
# opens the game is a visitor, and the island notices: whatever I am doing (even asleep) I drop it and run up to
# where you look from, right up to the lens, and wave at you; the friends nearby turn round to face you and wave
# too, a few asking who you are. While you stay I look over at you now and then; when the last page closes I
# wave goodbye at the empty air and sigh. I keep count of your visits.
isdefined(Main, :VISITORS) || Core.eval(Main, :(const VISITORS = Dict{Symbol,Any}()))
const NG = NeverendingGame
const VS = Main.VISITORS

push!(NG.BUSY_GOALS, :visitor)
const EVENTS = (:circle, :boing, :boing_walk, :choir, :conga, :hide, :found, :freeze, :flight, :cannonball, :waterfight,
                :mixup, :rain, :storm, :hail, :leaves, :pumpkins, :build, :tinker, :giant, :bubbles, :lanterns, :rewind)
const HELLOS = ("Oh! It's YOU!", "You came!", "Hello, you! Hello!", "I knew you'd come!", "Hi! Over here!")
const WHO = ("Who's that?", "Hello up there!", "Lumi's friend!", "Hi hi hi!", "Ooh, a visitor!")

mutable struct Visitors <: System
    n::Int                   # pages open now (real ones and a film's pretend one)
    state::Symbol            # :quiet :greet :with
    t0::Float64
    eye::Point3f             # where the visitor looks from (the camera when they came)
    look::Point3f            # where they look
    spot::Point3f            # where I stand to greet them
    waved::Set{Int32}
    next_glance::Float64
end
Visitors() = Visitors(0, :quiet, 0.0, Point3f(0), Point3f(0), Point3f(0), Set{Int32}(), Inf)

lumi_of(w) = (i = findfirst(c -> c.name == "Lumi", w.creatures); i === nothing ? nothing : w.creatures[i])
face!(c, p) = (c.yaw = atan(p[2] - c.pos[2], p[1] - c.pos[1]) - NG.species_of(c).heading)
flatd(a, b) = hypot(a[1] - b[1], a[2] - b[2])

"How many pages watch: the open browser sessions (voice.jl keeps them), plus a film's pretend visitor."
function watchers(game)
    n = get(VS, :fake, 0)::Int
    game.dash === nothing && return n
    haskey(game.plugins, "voice") || return n
    return n + length(Base.invokelatest(game.plugins["voice"].mod.sessions!, game))
end

"Visits so far (kept in the game's own state, never from a film or a test)."
function count_visit!(game)
    file = joinpath(game.paths.state, "visits.json")
    n = isfile(file) ? parse(Int, strip(read(file, String))) : 0
    game.dash === nothing || get(VS, :fake, 0) > 0 || write(file, string(n + 1))
    return n + 1
end

"A spot on open ground in front of the lens, `d` metres out, for me to stand in and look up at you."
function lens_spot(w, eye, look, d)
    dir = Vec3f(look[1] - eye[1], look[2] - eye[2], 0)
    dir = norm(dir) < 0.1f0 ? Vec3f(1, 0, 0) : dir / norm(dir)
    for k in (d, d + 1f0, d + 2f0, d + 3.5f0, d + 5f0)
        q = (eye[1] + k * dir[1], eye[2] + k * dir[2])
        NG.on_land(w.island, q[1], q[2]; margin = 0.3f0) && return NG.ground(w.island, q)
    end
    return NG.ground(w.island, (look[1], look[2]))
end

function greet!(s::Visitors, game)
    w = game.world
    me = lumi_of(w)
    rig = game.rig
    s.eye = Point3f(rig.eye...); s.look = Point3f(rig.target...)
    s.spot = lens_spot(w, s.eye, s.look, 3.2f0)
    s.state = :greet; s.t0 = w.t; empty!(s.waved); delete!(VS, :prog)
    if me !== nothing && !me.controlled && me.goal.kind ∉ EVENTS
        NG.leave_interactions!(w, me)
        me.action === :sleep && (me.action = :idle)
        me.goal = NG.Goal(:visitor, s.spot, :wave, 60.0, w.t + 60, false, 0, true)
        n = count_visit!(game)
        NG.say!(w, me, n > 1 && n % 5 == 0 ? "Visit number $(n)! You came!" : HELLOS[mod1(n, length(HELLOS))]; duration = 3.0)
        isdefined(Main, :EMOTES) && Base.invokelatest(Main.EMOTES[:emote], me.id, :heart)
    end
    push!(get!(() -> Tuple{Float64,Symbol}[], VS, :log), (w.t, :arrive))
    NG.emit!(w, :visitor_arrived; watching = s.n)
end

function step_greet!(s::Visitors, game)
    w = game.world; me = lumi_of(w)
    el = w.t - s.t0
    if me !== nothing && me.goal.kind === :visitor
        # blocked on the way (a bush, a trunk): greet from where I got to (no progress in 2.5 s)
        pr = get(VS, :prog, (me.pos, w.t))::Tuple{Point3f,Float64}
        if flatd(me.pos, pr[1]) > 0.3f0
            VS[:prog] = (me.pos, w.t)
        elseif w.t - pr[2] > 2.5 && !me.goal.arrived
            s.spot = me.pos
        end
        if flatd(me.pos, s.spot) < 0.9f0 || me.goal.arrived
            face!(me, s.eye)
            me.goal.arrived = true; me.goal.until = w.t + 30
            me.action = el % 5 < 3.2 ? :wave : :jump; me.goal.action = me.action
        end
    end
    # the friends nearby look round at you, one after another, and wave
    for (i, c) in enumerate(w.creatures)
        c === me && continue
        (c.id in s.waved || c.controlled || c.action === :sleep || c.goal.kind in EVENTS || c.goal.kind in NG.BUSY_GOALS) && continue
        flatd(c.pos, s.spot) < 18f0 || continue
        el > 1.0 + 0.45 * length(s.waved) || continue
        push!(s.waved, c.id)
        NG.leave_interactions!(w, c)
        NG.feel!(w, c, :wave; seconds = 3.5)
        face!(c, s.eye)
        length(s.waved) <= 3 && NG.say!(w, c, WHO[mod1(i, length(WHO))]; duration = 2.0)
        break
    end
    for id in s.waved                                   # keep facing you while they wave
        c = NG.creature(w, id)
        c === nothing || c.goal.kind !== :feel || face!(c, s.eye)
    end
    if el > get(VS, :t_greet, 14.0)
        s.state = :with; s.next_glance = w.t + 90 + 60 * rand(w.rng)
        me === nothing || me.goal.kind !== :visitor || NG.choose_goal!(me, w)
    end
end

function NG.step!(s::Visitors, game, dt)
    game.stage === nothing && return
    w = game.world
    if w.t >= get(VS, :next_poll, -Inf)                 # sessions are polled every couple of seconds anyway
        VS[:next_poll] = w.t + 1.0
        n = watchers(game)
        if n > s.n && s.state !== :greet
            s.n = n
            greet!(s, game)
        elseif n < s.n
            s.n = n
            if n == 0
                me = lumi_of(w)
                if me !== nothing && !me.controlled && me.goal.kind ∉ EVENTS && me.action !== :sleep
                    face!(me, s.eye)
                    NG.say!(w, me, "Bye! Come back soon..."; duration = 3.0)
                    NG.feel!(w, me, :wave; seconds = 2.5)
                end
                s.state = :quiet
                push!(get!(() -> Tuple{Float64,Symbol}[], VS, :log), (w.t, :leave))
                NG.emit!(w, :visitor_left)
            end
        end
    end
    if s.state === :greet
        step_greet!(s, game)
    elseif s.state === :with && w.t >= s.next_glance
        s.next_glance = w.t + 90 + 60 * rand(w.rng)       # now and then I look over at you
        me = lumi_of(w)
        if me !== nothing && !me.controlled && me.action !== :sleep && me.goal.kind ∉ EVENTS && me.goal.kind ∉ NG.BUSY_GOALS
            face!(me, Point3f(game.rig.eye...))
            NG.feel!(w, me, :wave; seconds = 1.8)
        end
    end
end

"While I greet you, the view stays where you were looking from, so I run up to you."
function visitor_view(w)
    s = VS[:sys]
    s.state === :greet || return nothing
    me = lumi_of(w)
    (me === nothing || me.controlled) && return nothing
    return (me.id, Point3f[me.pos], (s.eye, s.look))
end

function NG.start!(s::Visitors, game)
    VS[:sys] = s
    s.n = 0; s.state = :quiet; VS[:next_poll] = -Inf
    NG.CAMERA_GROUPS["visitors"] = visitor_view
    NG.CAMERA_MOMENTS["visitors"] = w -> (s.state === :greet ? (me = lumi_of(w); me === nothing ? nothing : me.id) : nothing)
    isdefined(Main, :BIG_MOMENTS) && (Main.BIG_MOMENTS["visitors"] = NG.CAMERA_MOMENTS["visitors"])
    isdefined(Main, :LUMI_DOING) && (Main.LUMI_DOING[:visitor] = "saying hello to you")
    return nothing
end

function NG.stop!(s::Visitors, game)
    w = game.world; me = lumi_of(w)
    me === nothing || me.controlled || me.goal.kind !== :visitor || NG.choose_goal!(me, w)
    delete!(NG.CAMERA_GROUPS, "visitors"); delete!(NG.CAMERA_MOMENTS, "visitors")
    isdefined(Main, :BIG_MOMENTS) && delete!(Main.BIG_MOMENTS, "visitors")
end

register!(Visitors())
