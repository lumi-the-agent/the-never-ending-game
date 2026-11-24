# ── Behaviour: needs, goals, walking, interactions ──────────────────────────
#
# Every creature not driven by the player follows a goal. Goals are chosen by
# utility (`goal_score`) and run by dispatch on their kind, so a plugin adds a
# new behaviour by pushing a kind to `GOAL_KINDS` and defining `goal_score`,
# `start_goal` and optionally `arrive_goal!` / `finish_goal!` for it.

const NEED_DECAY = (hunger = 1 / 700, energy = 1 / 1100, fun = 1 / 450, social = 1 / 550)

function step_needs!(c::Creature, dt::Real)
    n = c.needs; a = c.action
    n.hunger = clamp(n.hunger - dt * NEED_DECAY.hunger + (a === :eat ? dt / 8 : 0), 0, 1)
    tiring = a in (:run, :play, :dance, :jump) ? 2.5 : 1.0
    n.energy = clamp(n.energy - dt * NEED_DECAY.energy * tiring + (a === :sleep ? dt / 90 : 0) +
                     (a === :sit ? dt / 600 : 0), 0, 1)
    n.fun = clamp(n.fun - dt * NEED_DECAY.fun + (a in (:play, :dance, :jump) ? dt / 25 : 0), 0, 1)
    n.social = clamp(n.social - dt * NEED_DECAY.social + (a === :talk ? dt / 15 : 0), 0, 1)
    avg = (n.hunger + n.energy + n.fun + n.social) / 4
    target = clamp(2avg - 1 + 0.3f0 * (c.traits.playfulness - 0.5f0), -1, 1)
    c.mood += Float32((target - c.mood) * min(1, dt / 20))
    return c
end

species_of(c::Creature) = SPECIES[c.species]

function say!(w::World, c::Creature, text::AbstractString; duration = 2.5)
    filter!(s -> s.who != c.id, w.speech)
    push!(w.speech, Speech(c.id, String(text), w.t, w.t + duration))
    emit!(w, :say; who = c.name, text = String(text))
    return nothing
end

nearest(f, items, p) = (best = nothing; bd = Inf32;
    for it in items
        f(it) || continue
        d = norm(Vec2f(it.pos[1] - p[1], it.pos[2] - p[2]))
        d < bd && (best = it; bd = d)
    end; (best, bd))

"Goal kinds nobody interrupts for a chat (plugins push theirs, e.g. :fish)."
const BUSY_GOALS = Set{Symbol}([:interact, :feel])
busy(c::Creature) = c.controlled || c.goal.kind in BUSY_GOALS || c.action === :sleep

# ── choosing goals ──────────────────────────────────────────────────────────

const GOAL_KINDS = Symbol[:eat, :sleep, :play, :social, :wander, :dance, :idle]

goal_score(::Val{:eat}, c, w) = c.needs.hunger < 0.6 ? 0.3 + 3(1 - c.needs.hunger)^2 : 0.02
goal_score(::Val{:sleep}, c, w) = (c.needs.energy < 0.45 ? 2(1 - c.needs.energy) : 0.0) + (is_night(w) ? 1.5 : 0.0)
goal_score(::Val{:play}, c, w) = (1 - c.needs.fun) * (0.4 + c.traits.playfulness)
goal_score(::Val{:social}, c, w) = (1 - c.needs.social) * (0.4 + c.traits.sociability)
goal_score(::Val{:wander}, c, w) = 0.25 + 0.4c.traits.curiosity
goal_score(::Val{:dance}, c, w) = c.mood > 0.4 ? 0.2 : 0.03
goal_score(::Val{:idle}, c, w) = 0.15 + 0.3c.traits.laziness

"A goal of `kind` for `c`, or `nothing` if it is not possible right now."
start_goal(::Val, c, w) = nothing

function start_goal(::Val{:eat}, c, w)
    bush, d = nearest(p -> p.kind === :bush && get(p.data, "berries", 0) > 0, w.props, c.pos)
    (bush === nothing || d > 35) && return nothing
    dir = normalize(Vec2f(c.pos[1] - bush.pos[1], c.pos[2] - bush.pos[2]) + Vec2f(1.0f-3))
    # just outside the bush's solid footprint (Separation): a target at 0.8 m from a big bush was never
    # reached, the critter walked on the spot "off to the berry bushes" for hours (perfectionist s36)
    r = get(SOLID_FOOTPRINT, :bush, 0.65f0) * bush.scale + 0.7f0 * body_radius(species_of(c)) + 0.1f0
    target = ground(w.island, Point2f(bush.pos[1], bush.pos[2]) + max(0.8f0, r) * dir)
    return Goal(:eat, target, :eat, 6.0, 0.0, false, bush.id, false)
end

function start_goal(::Val{:sleep}, c, w)
    tree, d = nearest(p -> p.kind === :tree, w.props, c.pos)
    target = tree !== nothing && d < 12 ? ground(w.island, tree.pos + Point3f(0.9, 0.4, 0)) : c.pos
    return Goal(:sleep, target, :sleep, is_night(w) ? 240.0 + 120rand(w.rng) : 60.0 + 60rand(w.rng), 0.0, false, 0, false)
end

function start_goal(::Val{:play}, c, w)
    ball, d = nearest(p -> p.kind === :ball, w.props, c.pos)
    if ball !== nothing && d < 18 && rand(w.rng) < 0.6
        return Goal(:ball, ball.pos, :play, 1.5, 0.0, false, ball.id, true)
    end
    return Goal(:play, near_point(w, c.pos, 4), :play, 5.0, 0.0, false, 0, true)
end

function start_goal(::Val{:social}, c, w)
    other, d = nearest(o -> o.id != c.id && !busy(o), w.creatures, c.pos)
    (other === nothing || d > 25) && return nothing
    return Goal(:social, other.pos, :idle, 0.0, 0.0, false, other.id, false)
end

start_goal(::Val{:wander}, c, w) =
    Goal(:wander, near_point(w, c.pos, 10), rand(w.rng) < 0.3 ? :sit : :idle, 2.0 + 4rand(w.rng), 0.0, false, 0, false)
start_goal(::Val{:dance}, c, w) = Goal(:dance, c.pos, :dance, 6.0 + 6rand(w.rng), 0.0, false, 0, false)
start_goal(::Val{:idle}, c, w) =
    Goal(:idle, c.pos, rand(w.rng) < 0.4 ? :sit : :idle, 3.0 + 5rand(w.rng), 0.0, false, 0, false)

function near_point(w::World, p, r)
    for _ in 1:30
        q = Point2f(p[1], p[2]) + r * (2rand(w.rng, Point2f) .- 1)
        on_land(w.island, q[1], q[2]; margin = 0.35f0) && return ground(w.island, q)
    end
    return Point3f(p)
end

function choose_goal!(c::Creature, w::World)
    kinds = GOAL_KINDS
    weights = [max(Float64(goal_score(Val(k), c, w)), 0.0)^2 for k in kinds]
    for _ in 1:4
        r = rand(w.rng) * sum(weights)
        k = kinds[something(findfirst(>=(r), cumsum(weights)), length(kinds))]
        g = start_goal(Val(k), c, w)
        if g !== nothing
            c.goal = g
            return g
        end
    end
    c.goal = start_goal(Val(:wander), c, w)
    return c.goal
end

# ── arriving and finishing ──────────────────────────────────────────────────

arrive_goal!(::Val, c, w) = nothing

function arrive_goal!(::Val{:social}, c, w)
    other = creature(w, c.goal.partner)
    if busy(other)
        c.goal = start_goal(Val(:idle), c, w)
        return nothing
    end
    start_interaction!(w, pick_interaction(w), c, other)
    return nothing
end

function arrive_goal!(::Val{:ball}, c, w)
    ball = prop(w, c.goal.partner)
    dir = normalize(Vec2f(ball.pos[1] - c.pos[1], ball.pos[2] - c.pos[2]) + Vec2f(1.0f-3))
    kick!(ball, 4.0f0 + 4rand(w.rng, Float32), dir)
    rand(w.rng) < 0.5 && say!(w, c, rand(w.rng, ["wheee!", "kick!", "mine!", "boing"]))
    emit!(w, :kick; who = c.name)
    return nothing
end

finish_goal!(::Val, c, w) = nothing

function finish_goal!(::Val{:eat}, c, w)
    bush = prop(w, c.goal.partner)
    bush.data["berries"] = max(0, get(bush.data, "berries", 0) - 1)
    remember!(c, w.t, "ate berries")
    emit!(w, :ate; who = c.name)
    return nothing
end

function finish_goal!(::Val{:sleep}, c, w)
    remember!(c, w.t, "had a nap")
    rand(w.rng) < 0.5 && say!(w, c, rand(w.rng, ["*yawn*", "good nap", "mmh, five more minutes"]))
    return nothing
end

finish_goal!(::Val{:dance}, c, w) = (remember!(c, w.t, "danced"); nothing)

# ── moving ──────────────────────────────────────────────────────────────────

wrap_angle(a) = mod(a + Float32(pi), 2Float32(pi)) - Float32(pi)

"""
Surfaces besides the ground that creatures walk on (a pier, a bridge): plugins add
`WALKWAYS[name] = (x, y) -> height or nothing` and remove it in `stop!`.
"""
const WALKWAYS = Dict{String,Any}()

"The height of the walkway under `(x, y)`, or `nothing` when there is none."
function walkway_height(x, y)
    for f in values(WALKWAYS)
        h = Base.invokelatest(f, x, y)
        h === nothing || return Float32(h)
    end
    return nothing
end

"""
    walk_toward!(c, w, target, dt; run) -> arrived::Bool

Turn toward `target` and walk; stays on land. Used by goals and the player.
"""
function walk_toward!(c::Creature, w::World, target, dt::Real; run::Bool = false, reach = 0.35f0)
    d = Vec2f(target[1] - c.pos[1], target[2] - c.pos[2])
    dist = norm(d)
    dist < reach && return true
    move_heading!(c, w, atan(d[2], d[1]), dt; run, maxstep = dist)
    return false
end

function move_heading!(c::Creature, w::World, heading::Real, dt::Real; run::Bool = false, maxstep = Inf32, speed = 1.0f0)
    sp = species_of(c)
    diff = wrap_angle(Float32(heading) - c.yaw)
    c.yaw = wrap_angle(c.yaw + clamp(diff, -5.0f0 * dt, 5.0f0 * dt))
    align = max(0.0f0, cos(diff))
    step = Float32(min(maxstep, sp.speed * (run ? 2.2f0 : 1.0f0) * speed * align * dt))
    nx, ny = c.pos[1] + step * cos(c.yaw), c.pos[2] + step * sin(c.yaw)
    hw = walkway_height(nx, ny)
    hw === nothing && !on_land(w.island, nx, ny; margin = 0.1f0) && return false
    c.pos = hw === nothing ? ground(w.island, (nx, ny)) : Point3f(nx, ny, max(hw, terrain_height(w.island, nx, ny)))
    c.phase += sp.stride * max(step, 0.15f0 * dt)
    c.action = run ? :run : :walk
    c.extra = 0.0f0                     # walking has none; a plugin may set glee on a runner (faces.jl)
    return true
end

function step_goal!(c::Creature, w::World, dt::Real)
    g = c.goal
    if !g.arrived
        if g.kind === :social || g.kind === :ball
            g.target = g.kind === :social ? creature(w, g.partner).pos : prop(w, g.partner).pos
            g.kind === :social && busy(creature(w, g.partner)) && (choose_goal!(c, w); return)
        end
        reach = g.kind === :social ? body_radius(species_of(c)) + body_radius(species_of(creature(w, g.partner))) + 0.15f0 :
                g.kind === :ball ? 0.6f0 : 0.35f0
        moved_before = c.pos
        if walk_toward!(c, w, g.target, dt; run = g.run, reach)
            g.arrived = true
            g.until = w.t + g.duration
            c.action = g.action
            arrive_goal!(Val(g.kind), c, w)
        elseif c.pos == moved_before && abs(wrap_angle(atan(g.target[2] - c.pos[2], g.target[1] - c.pos[1]) - c.yaw)) < 0.1
            choose_goal!(c, w)   # blocked by the coast
        end
    else
        c.action = g.action
        c.extra = action_extra(Val(c.action), c, w)
        if w.t >= g.until && c.goal === g
            finish_goal!(Val(g.kind), c, w)
            choose_goal!(c, w)
        end
    end
    return c
end

action_extra(::Val, c, w) = 0.0f0

"""
    feel!(w, c, action; seconds = 3.0) -> Bool

A short reaction that shows on the face and the body (faces.jl): `c` stops
where it is and does `action` (`:laugh`, `:cry`, `:pout`, `:gasp`, `:think`,
`:proud`, `:shy`, `:yawn`, `:sigh`, `:scared`, `:angry`, or any action) for
`seconds`, then goes on with its day. A steered or sleeping creature is left
alone (false).
"""
function feel!(w::World, c::Creature, action::Symbol; seconds::Real = 3.0)
    (c.controlled || c.action === :sleep) && return false
    c.goal = Goal(:feel, c.pos, action, Float64(seconds), w.t + seconds, true, 0, false)
    c.action = action
    return true
end
action_extra(::Val{:jump}, c, w) = 0.45f0 * abs(sin(Float32(5w.t) + 6c.seed))
action_extra(::Val{:talk}, c, w) = 1.0f0
action_extra(::Val{:sleep}, c, w) = 1.0f0

# ── interactions between creatures ──────────────────────────────────────────

"Registered interactions and their relative likelihood (plugins add more)."
const INTERACTIONS = Pair{Type,Float64}[]

pick_interaction(w::World) = (ws = last.(INTERACTIONS); r = rand(w.rng) * sum(ws);
    first(INTERACTIONS[something(findfirst(>=(r), cumsum(ws)), length(ws))]))

function face_each_other!(a::Creature, b::Creature)
    a.yaw = atan(b.pos[2] - a.pos[2], b.pos[1] - a.pos[1]) - species_of(a).heading
    b.yaw = atan(a.pos[2] - b.pos[2], a.pos[1] - b.pos[1]) - species_of(b).heading
    return nothing
end

function start_interaction!(w::World, T::Type{<:Interaction}, a::Creature, b::Creature)
    it = T(w, a, b)
    for c in (a, b)
        c.goal = Goal(:interact, c.pos, :idle, 0.0, Inf, true, (c === a ? b : a).id, false)
        c.action = :idle
    end
    face_each_other!(a, b)
    push!(w.interactions, it)
    emit!(w, :interaction; kind = string(nameof(T)), a = a.name, b = b.name)
    return it
end

function end_interaction!(w::World, it::Interaction, a::Creature, b::Creature)
    for c in (a, b)
        c.controlled || c.goal.kind !== :interact || choose_goal!(c, w)   # only the ones still in it
    end
    return nothing
end

"Two creatures chat: lines alternate, the speaker talks, the listener reacts."
mutable struct Chat <: Interaction
    a::Int32
    b::Int32
    lines::Vector{Tuple{Int32,String}}
    i::Int
    next::Float64
end

Chat(w::World, a::Creature, b::Creature) = Chat(a.id, b.id, chat_lines(w, a, b), 0, w.t)

"""
Lines of a chat. Topics come from needs, memories and species quirks; a
`world/dialogue.json` written by a language model can add more (see plugins).
"""
function chat_lines(w::World, a::Creature, b::Creature)
    sa, sb = species_of(a), species_of(b)
    lines = Tuple{Int32,String}[(a.id, rand(w.rng, ["Hi $(b.name)!", "Oh, $(b.name)!", "$(rand(w.rng, sa.sounds)) hello!"]))]
    push!(lines, (b.id, rand(w.rng, ["Hey $(a.name).", "$(rand(w.rng, sb.sounds))", "Hello hello!"])))
    topics = Tuple{String,String}[]
    a.needs.hunger < 0.5 && push!(topics, ("I'm so hungry...", "The berry bushes are full!"))
    a.needs.energy < 0.4 && push!(topics, ("*yawn* I need a nap.", "Same. The shade under the trees is nice."))
    is_night(w) && push!(topics, ("Look at all the stars!", "I counted three. Then I fell asleep."))
    !isempty(a.memory) && push!(topics, ("Guess what: I $(split(last(a.memory), "] ")[end]).", "No way!"))
    append!(topics, [("Have you seen what Lumi is building?", "Lumi is always up to something."),
                     ("Do you think the ocean ends somewhere?", "Probably at another ocean."),
                     ("I had a dream I was a $(rand(w.rng, collect(keys(SPECIES)))).", "Was it nice?"),
                     (QUIRKS[sa.name][1], QUIRKS[sa.name][2])])
    q, r = rand(w.rng, topics)
    push!(lines, (a.id, q)); push!(lines, (b.id, r))
    push!(lines, (a.id, rand(w.rng, ["See you!", "*boop*", "Bye bye!", rand(w.rng, sa.sounds)])))
    return lines
end

const QUIRKS = Dict(
    "Lumi" => ("I'm writing everything down, you know.", "Even this?"),
    "Snootle" => ("I smelled something amazing over there.", "It was probably you."),
    "Fluffkin" => ("I think I'm turning into a cumulus.", "You look very fluffy today."),
    "Blorbo" => ("blorb.", "...blorb?"),
    "Crabbit" => ("Which way is forward again?", "Sideways, as always."),
)

function step!(it::Chat, w::World, dt::Real)
    a, b = creature(w, it.a), creature(w, it.b)
    if w.t >= it.next
        it.i += 1
        it.i > length(it.lines) && return false
        who, text = it.lines[it.i]
        speaker = who == a.id ? a : b
        say!(w, speaker, text; duration = 2.4)
        it.next = w.t + 2.6
    end
    speaking = it.i >= 1 ? it.lines[min(it.i, end)][1] : a.id
    for c in (a, b)
        c.action = c.id == speaking ? :talk : (c.mood > 0.3 ? :idle : :sit)
        c.extra = c.id == speaking ? 1.0f0 : 0.0f0
    end
    return true
end

function end_interaction!(w::World, it::Chat)
    a, b = creature(w, it.a), creature(w, it.b)
    remember!(a, w.t, "chatted with $(b.name)"); remember!(b, w.t, "chatted with $(a.name)")
    end_interaction!(w, it, a, b)
end

"Nose boop: a hop toward each other, a bump, giggles."
mutable struct Boop <: Interaction
    a::Int32
    b::Int32
    start::Float64
end
Boop(w::World, a::Creature, b::Creature) = Boop(a.id, b.id, w.t)

function step!(it::Boop, w::World, dt::Real)
    a, b = creature(w, it.a), creature(w, it.b)
    τ = w.t - it.start
    τ > 3.0 && return false
    for c in (a, b)
        c.action = τ < 1.2 ? :play : τ < 2.0 ? :jump : :idle
        c.extra = c.action === :jump ? 0.3f0 * abs(sin(Float32(6τ))) : 0.0f0
        c.phase += Float32(8dt)
    end
    τ - dt < 1.2 <= τ && (say!(w, a, "boop!"; duration = 1.5); emit!(w, :boop; a = a.name, b = b.name))
    τ - dt < 1.6 <= τ && say!(w, b, rand(w.rng, ["hehe", "boop back!", "*giggles*"]); duration = 1.5)
    return true
end

function end_interaction!(w::World, it::Boop)
    a, b = creature(w, it.a), creature(w, it.b)
    for c in (a, b)
        c.needs.fun = min(1, c.needs.fun + 0.15f0); c.needs.social = min(1, c.needs.social + 0.2f0)
    end
    remember!(a, w.t, "booped $(b.name)"); remember!(b, w.t, "got booped by $(a.name)")
    end_interaction!(w, it, a, b)
end

"Dance-off: both dance, the happier one wins."
mutable struct DanceOff <: Interaction
    a::Int32
    b::Int32
    start::Float64
end
DanceOff(w::World, a::Creature, b::Creature) = DanceOff(a.id, b.id, w.t)

function step!(it::DanceOff, w::World, dt::Real)
    a, b = creature(w, it.a), creature(w, it.b)
    τ = w.t - it.start
    τ < dt && say!(w, a, "Dance-off! ♪"; duration = 2.0)
    τ > 9.0 && return false
    for c in (a, b)
        c.action = τ < 8.0 ? :dance : :idle
    end
    if τ - dt < 8.0 <= τ
        winner = a.mood >= b.mood ? a : b
        say!(w, winner, rand(w.rng, ["I win!", "Nailed it.", "*takes a bow*"]); duration = 2.0)
        emit!(w, :danceoff; winner = winner.name, loser = (winner === a ? b : a).name)
    end
    return true
end

function end_interaction!(w::World, it::DanceOff)
    a, b = creature(w, it.a), creature(w, it.b)
    for c in (a, b)
        c.needs.fun = min(1, c.needs.fun + 0.3f0)
    end
    remember!(a, w.t, "had a dance-off with $(b.name)"); remember!(b, w.t, "had a dance-off with $(a.name)")
    end_interaction!(w, it, a, b)
end

function init_interactions!()
    empty!(INTERACTIONS)
    push!(INTERACTIONS, Chat => 0.6, Boop => 0.25, DanceOff => 0.15)
    return INTERACTIONS
end

# ── props that move or grow ─────────────────────────────────────────────────

function kick!(ball::Prop, speed::Float32, dir::Vec2f)
    ball.data["vel"] = [speed * dir[1], speed * dir[2]]
    return ball
end

ball_radius(p::Prop) = 0.25f0 * p.scale

step!(::Val, p::Prop, w::World, dt) = nothing

function step!(::Val{:ball}, p::Prop, w::World, dt)
    v = get(p.data, "vel", nothing)
    (v === nothing || hypot(v[1], v[2]) < 0.02) && return nothing
    vx, vy = Float32(v[1]), Float32(v[2])
    nx, ny = p.pos[1] + vx * dt, p.pos[2] + vy * dt
    if !on_land(w.island, nx, ny; margin = 0.1f0)
        vx, vy = -vx, -vy           # bounce back from the beach
        nx, ny = p.pos[1], p.pos[2]
    end
    p.pos = ground(w.island, (nx, ny))
    damp = exp(-1.3f0 * dt)
    p.data["vel"] = [vx * damp, vy * damp]
    p.data["roll"] = get(p.data, "roll", 0.0) + hypot(vx, vy) * dt / ball_radius(p)
    p.data["dir"] = atan(vy, vx)
    return nothing
end

function step!(::Val{:bush}, p::Prop, w::World, dt)
    # one berry regrows every two minutes
    if floor(w.t / 120) != floor((w.t - dt) / 120)
        p.data["berries"] = min(6, get(p.data, "berries", 0) + 1)
    end
    return nothing
end

# ── the world step ──────────────────────────────────────────────────────────

"""
    step!(w, dt)

Advance the world by `dt` sim seconds: needs, goals, interactions, props,
speech bubbles. Player controlled creatures only update their needs.
"""
function step!(w::World, dt::Real)
    w.t += dt
    for c in w.creatures
        step_needs!(c, dt)
        (c.controlled || c.goal.kind === :interact) && continue
        step_goal!(c, w, dt)
    end
    filter!(w.interactions) do it
        # a creature taken out of the chat (a dance circle, a fetch, a test, the player) ends it:
        # the chat went on setting its action, and its end overwrote the new goal (s30 flaky dance/ball tests)
        taken = any(id -> (c = creature(w, id); c.controlled || c.goal.kind !== :interact), (it.a, it.b))
        alive = !taken && step!(it, w, dt)
        alive || end_interaction!(w, it)
        alive
    end
    for p in w.props
        step!(Val(p.kind), p, w, dt)
    end
    filter!(s -> s.until > w.t, w.speech)
    return w
end
