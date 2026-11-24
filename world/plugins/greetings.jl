# Play as Lumi ("Jump in" or any mini game that steers Lumi) and the island answers:
# - E waves: the nearest creature turns to Lumi, waves back and says hello.
#   Wave at it again within 12 s and it becomes a friend that follows Lumi in a little parade.
# - Space jumps: everyone close by jumps along, and the parade hops one after another, front to back.
# - A parade of two friends or more draws a crowd: a curious creature it passes runs over ("Ooh, a parade!")
#   and joins at the end, and the whole line hops to welcome it. Five in a row is a celebration.
# A hint card says so when you jump in.
const NG = NeverendingGame

const GREET_RADIUS = 4.5f0
const JUMP_RADIUS = 5.0f0
const FOLLOW_TIME = 35.0
const FOLLOW_GAP = 1.3f0
const HELLOS = ("Hi Lumi!", "Oh, hello!", "Hey there!", "Hello, friend!", "Hi hi!")
const COME = ("Where are we going?", "I'm coming!", "Wait for me!", "A parade!", "Lead the way!")
const BYE = ("That was fun!", "I'll go nap now.", "See you later!", "Phew, what a walk!")
const CURIOUS = ("Ooh, a parade!", "Wait, I'm coming too!", "Can I join?", "Me too, me too!", "A parade? Count me in!")
const JOINABLE = (:idle, :wander, :eat, :social, :dance, :swim, :flowers, :answer, :fish, :beachcomb, :sunbathe)   # everyday goals (the s41 beach and pier pastimes too: with them left out nobody was free to join): busy ones (BUSY_GOALS, races, sleep) are left alone
const PARADE_PULL = 3.2f0     # a curious creature this close to the parade joins it
const PARADE_MAX = 7
const JOIN_GAP = 2.5          # seconds between two joiners, so each one is a moment
const RIPPLE_STEP = 0.16      # seconds between two hops of a ripple down the line
const HINT = """You are Lumi
W / S  walk     A / D  turn     Shift  run
E  wave at a friend (twice: they join your parade)
E  by a flower: pick it, then E by a friend: give it
E  by a pebble: carry it to the critters' stone cairn
Space  jump (your parade hops along, one by one)
X  sneeze (stand close to friends!)
G  try to fly (your friends come to watch)
Walk into the red ball: a friend passes it back"""
# after HINT_FULL seconds the card shrinks to one line of keys (perfectionist-0049: the 8 lines covered a third
# of the view 8 s into Jump in; done when < 10% is covered then)
const HINT_SHORT = "WASD walk    E wave · pick · give    Space jump    X sneeze    G fly"
const HINT_FULL = 5.0
const HINT_END = 20.0

isdefined(Main, :PARADE_LEFT) || Core.eval(Main, :(const PARADE_LEFT = Dict{Int32,String}()))
isdefined(Main, :GREETING_PLOTS) || Core.eval(Main, :(const GREETING_PLOTS = Dict{Symbol,Any}()))
const GP = Main.GREETING_PLOTS

mutable struct Greetings <: System
    last_action::Symbol
    was_controlled::Bool
    hint_t::Float64                    # seconds the hint card has been up, Inf: hidden
    greeted::Dict{Int32,Float64}       # creature id => sim time of the last wave at it
    followers::Vector{Int32}
    follow_until::Dict{Int32,Float64}
    jump_until::Dict{Int32,Float64}    # followers hop in place until then
    jump_at::Dict{Int32,Float64}       # a ripple: each follower starts its hop at this time
    left::Dict{Int32,Float64}          # when a follower left the parade (it does not join again at once)
    last_join::Float64
    best::Int                          # the longest parade so far this play (for the celebration)
end
Greetings() = Greetings(:idle, false, Inf, Dict{Int32,Float64}(), Int32[], Dict{Int32,Float64}(), Dict{Int32,Float64}(),
    Dict{Int32,Float64}(), Dict{Int32,Float64}(), -Inf, 0)

function NG.start!(s::Greetings, game)
    game.stage === nothing && return
    haskey(GP, :hint) && return nothing
    GP[:hint] = textlabel!(game.stage.overlay, Point2f(0.5, 0.2); space = :relative, text = HINT, fontsize = 22,
        justification = :center, text_color = RGBf(1, 0.97, 0.85), background_color = RGBAf(0.07, 0.08, 0.13, 0.82),
        strokewidth = 0, padding = 16, cornerradius = 12, visible = false)
end

NG.stop!(s::Greetings, game) = haskey(GP, :hint) && (GP[:hint].visible[] = false)

"Turn `c` to look at `p`."
face!(c, p) = (c.yaw = atan(p[2] - c.pos[2], p[1] - c.pos[1]))

"An answer for `seconds`: the creature stands, does `action` and then goes back to its own life."
answer!(c, w, action, seconds) = (c.goal = NG.Goal(:answer, c.pos, action, seconds, w.t + seconds, true, 0, false); c.action = action)

# a sign over the creature's head (plugins/emotes.jl), when that plugin runs
emote(id, kind) = isdefined(Main, :EMOTES) && haskey(Main.EMOTES, :emote) && Base.invokelatest(Main.EMOTES[:emote], id, kind)

free(c) = !c.controlled && c.goal.kind !== :interact && c.goal.kind !== :follow

function wave!(s::Greetings, w, me)
    # the nearest one that can answer: an awake creature a step further away beats a sleeper
    # right next to Lumi (the wave used to go to the sleeper, "Zzz", and the awake one ignored it)
    best = nothing; bd = Inf32
    for c in w.creatures
        (c === me || c.controlled) && continue      # a chatting creature breaks off its chat for Lumi (it used to ignore the wave)
        d = norm(Vec2f(c.pos[1] - me.pos[1], c.pos[2] - me.pos[2]))
        d < GREET_RADIUS || continue
        score = d + (c.action === :sleep ? 100f0 : 0f0) + (c.goal.kind in NG.BUSY_GOALS ? 50f0 : 0f0) + (c.goal.kind === :interact ? 3f0 : 0f0)
        score < bd && (best = c; bd = score)
    end
    best === nothing && return
    c = best
    c.goal.kind === :follow && return NG.say!(w, c, "Hi again!"; duration = 1.5)
    if c.action === :sleep
        NG.say!(w, c, "Zzz…"; duration = 2)
        emote(c.id, :sleep)
        return
    end
    c.goal.kind === :interact && NG.leave_interactions!(w, c)
    face!(c, me.pos)
    if haskey(s.greeted, c.id) && w.t - s.greeted[c.id] < 12
        # the second wave: a new friend joins the parade
        delete!(s.greeted, c.id)
        join_parade!(s, w, me, c, rand(w.rng, COME))
    else
        s.greeted[c.id] = w.t
        answer!(c, w, :wave, 2.5)
        c.mood = min(1.0f0, c.mood + 0.1f0)
        NG.say!(w, c, rand(w.rng, HELLOS); duration = 2.5)
        emote(c.id, :hey)
        NG.remember!(c, w.t, "Lumi waved at me")
        NG.emit!(w, :greet; who = c.name, by = me.name)
    end
end

function join_parade!(s::Greetings, w, me, c, line)
    push!(s.followers, c.id)
    s.follow_until[c.id] = w.t + FOLLOW_TIME
    for id in s.followers    # a growing parade stays together: nobody leaves right after a new friend came
        s.follow_until[id] = max(s.follow_until[id], w.t + 20)
    end
    c.goal = NG.Goal(:follow, c.pos, :idle, FOLLOW_TIME, w.t + FOLLOW_TIME + 5, true, me.id, false)
    c.action = :jump
    c.mood = min(1.0f0, c.mood + 0.2f0)
    NG.say!(w, c, line; duration = 2.5)
    emote(c.id, :heart); emote(me.id, :heart)
    NG.remember!(c, w.t, "followed Lumi")
    NG.emit!(w, :follow; who = c.name, leader = me.name)
    n = length(s.followers)
    if n > s.best && n in (3, 5, PARADE_MAX)
        NG.say!(w, me, n == 3 ? "A parade! To a lantern, or to the stone pile!" : n == 5 ? "Five friends in a row!" : "The whole island is here!"; duration = 3)
        emote(me.id, :note)
    end
    s.best = max(s.best, n)
    ripple!(s, w; skip = c.id)
end

"The parade hops one after another, front to back, like a wave down the line."
function ripple!(s::Greetings, w; skip = Int32(-1))
    for (k, id) in enumerate(s.followers)
        id == skip && continue
        s.jump_at[id] = w.t + RIPPLE_STEP * (k - 1)
    end
end

const SPOTS = Ref((-Inf, Point3f[]))    # (sim time, the dance circle's lantern spots), refreshed every few seconds

"""
A parade of three or more led to a lantern's dance spot turns into a dance ring there, with Lumi in the middle
(plugins/dancecircle.jl does the dancing).
"""
function parade_party!(s::Greetings, game, w, me)
    p = get(game.plugins, "dancecircle", nothing)
    p === nothing && return
    dc = only(p.systems)
    dc.active && return
    if w.t - SPOTS[][1] > 5
        SPOTS[] = (w.t, Base.invokelatest(p.mod.dance_spots, game))
    end
    spots = SPOTS[][2]
    isempty(spots) && return
    k = argmin([flat(q, me.pos) for q in spots])
    flat(spots[k], me.pos) < 2.6f0 || return
    ids = copy(s.followers)
    Base.invokelatest(p.mod.start_circle!, dc, game; spot = spots[k], dancers = ids, line = "A parade party!") || return
    empty!(s.followers); empty!(s.jump_at)
    for id in ids
        delete!(s.follow_until, id); s.left[id] = w.t
    end
    NG.say!(w, me, "Everyone, dance!"; duration = 2.5)
    emote(me.id, :note)
    NG.emit!(w, :parade_party; who = me.name, dancers = length(ids))
end

const CAIRN_TRIP = Ref(-Inf)    # sim time of the last parade at the cairn

"""
A parade of two or more led up to the critters' stone cairn (plugins/cairns.jl): every friend runs off to find
a pebble and sets it on the pile, one after another, while the cairn's camera frames each stone.
"""
function parade_cairn!(s::Greetings, game, w, me)
    haskey(game.plugins, "cairns") && isdefined(Main, :CAIRN_STATE) || return
    C = Main.CAIRN_STATE
    site = get(C, :site, nothing)
    (site === nothing || flat(site, me.pos) > 2.8f0 || w.t - CAIRN_TRIP[] < 60) && return
    sent = Int32[]
    for id in copy(s.followers)
        c = NG.creature(w, id)
        c === nothing && continue
        g = Base.invokelatest(NG.start_goal, Val(:pebble), c, w)
        g === nothing && continue
        c.goal = g
        push!(sent, id)
        filter!(!=(id), s.followers); delete!(s.follow_until, id); delete!(s.jump_at, id)
        s.left[id] = w.t
        NG.say!(w, c, rand(w.rng, ("I'll find a big one!", "A stone for the pile!", "Race you to a pebble!", "On it!")); duration = 2)
    end
    isempty(sent) && return
    CAIRN_TRIP[] = w.t
    NG.say!(w, me, "Everyone, bring a stone!"; duration = 2.5)
    emote(me.id, :hey)
    NG.emit!(w, :parade_cairn; who = me.name, helpers = length(sent))
end

"A parade of two or more pulls in a curious creature it passes, one every few seconds."
function draw_crowd!(s::Greetings, w, me)
    (length(s.followers) >= 2 && length(s.followers) < PARADE_MAX && w.t - s.last_join > JOIN_GAP) || return
    line = [me; [w.creatures[i] for i in eachindex(w.creatures) if w.creatures[i].id in s.followers]]
    best = nothing; bd = PARADE_PULL
    for c in w.creatures
        (c.controlled || c.action === :sleep || c.goal.kind ∉ JOINABLE || c.id in s.followers) && continue
        w.t - get(s.left, c.id, -Inf) < 25 && continue
        d = minimum(m -> norm(Vec2f(c.pos[1] - m.pos[1], c.pos[2] - m.pos[2])), line)
        d < bd && (best = c; bd = d)
    end
    best === nothing && return
    s.last_join = w.t
    face!(best, me.pos)
    join_parade!(s, w, me, best, rand(w.rng, CURIOUS))
end

function jump!(s::Greetings, w, me)
    ripple!(s, w)              # followers hop in a wave, front to back, then walk on
    for c in w.creatures
        c === me && continue
        near = norm(Vec2f(c.pos[1] - me.pos[1], c.pos[2] - me.pos[2])) < JUMP_RADIUS
        if c.goal.kind === :follow
            continue
        elseif near && free(c) && c.action !== :sleep && c.goal.kind ∉ NG.BUSY_GOALS   # a dance ring or a rain party keeps its own steps
            face!(c, me.pos)
            answer!(c, w, :jump, 1.6)
            emote(c.id, :note)
        end
    end
end

const NEXT_NOTE = Dict{Int32,Float64}()   # follower id => sim time of its next hummed note
flat(a, b) = hypot(a[1] - b[1], a[2] - b[2])
standable(w, q) = NG.on_land(w.island, q[1], q[2]; margin = 0.8f0) && NG.walkway_height(q[1], q[2]) === nothing &&
    !any(p -> haskey(NG.SOLID_FOOTPRINT, p.kind) && flat(p.pos, q) < NG.SOLID_FOOTPRINT[p.kind] * p.scale + 0.45f0, w.props)

function step_followers!(s::Greetings, w, me, dt)
    lead = me
    n = 0
    for id in copy(s.followers)
        i = findfirst(c -> c.id == id, w.creatures)
        c = i === nothing ? nothing : w.creatures[i]
        # a critter walking over for a chat or a boop took a friend out of the parade (s43: the butterfly test's
        # friend was booped away on the walk over): it says sorry and stays in line. (:follow in NG.BUSY_GOALS
        # instead stopped the parade's dance ring at a lantern.)
        if c !== nothing && c.goal.kind === :interact && me.controlled && w.t <= s.follow_until[id]
            NG.leave_interactions!(w, c)
            c.goal = NG.Goal(:follow, c.pos, :idle, FOLLOW_TIME, s.follow_until[id] + 5, true, me.id, false)
            NG.say!(w, c, rand(w.rng, ("Later! I'm with Lumi!", "Can't stop, parade!")); duration = 2)
        end
        if c === nothing || c.goal.kind !== :follow || w.t > s.follow_until[id] || !me.controlled
            filter!(!=(id), s.followers)
            delete!(s.follow_until, id); delete!(s.jump_at, id)
            s.left[id] = w.t
            # why it left, for flaky parade tests (todo #230): Main.PARADE_LEFT (creature id => reason)
            Main.PARADE_LEFT[id] = c === nothing ? "gone" : c.goal.kind !== :follow ? "goal $(c.goal.kind)" :
                             !me.controlled ? "Lumi not steered" : "follow time ran out"
            if c !== nothing && c.goal.kind === :follow
                NG.say!(w, c, rand(w.rng, BYE); duration = 2)
                answer!(c, w, :wave, 1.5)
            end
            continue
        end
        # a parade lasts while Lumi leads it: walking on keeps the friends 12 s more, and their goal must not run out
        # before that (the engine then picked a new one, at night :sleep, and the parade fell apart on the way, s42)
        me.action in (:walk, :run) && (s.follow_until[id] = max(s.follow_until[id], w.t + 12))
        c.goal.until = max(c.goal.until, s.follow_until[id] + 5)
        # a V behind Lumi, alternating sides and wider further back: a straight line walked between the
        # chase camera and Lumi and filled the view with the last friend's back (s40, tests/shots/parade-join.png)
        n += 1
        side = (isodd(n) ? 1f0 : -1f0) * (0.8f0 + 0.3f0 * n)
        fwd = Point3f(cos(me.yaw), sin(me.yaw), 0)
        back = me.pos - FOLLOW_GAP * (0.5f0 + 0.45f0 * n) * fwd
        target = back + side * Point3f(-fwd[2], fwd[1], 0)
        standable(w, target) || (target = lead.pos - FOLLOW_GAP * Point3f(cos(lead.yaw), sin(lead.yaw), 0))   # a bush, a trunk or the pier: fall in line
        d = norm(Vec2f(target[1] - c.pos[1], target[2] - c.pos[2]))
        if haskey(s.jump_at, id) && w.t >= s.jump_at[id]    # its turn in the ripple
            delete!(s.jump_at, id)
            c.goal.action = :jump; c.action = :jump
            s.jump_until[id] = w.t + 1.1
            emote(id, :note)
        end
        c.goal.action === :jump && w.t > get(s.jump_until, id, 0.0) && (c.goal.action = :idle)
        if length(s.followers) >= 2 && w.t >= get!(NEXT_NOTE, id, w.t + 2 + 3rand(w.rng))   # a parade hums as it goes: notes over it, seen from afar
            emote(id, :note)
            NEXT_NOTE[id] = w.t + 3.5 + 3rand(w.rng)
        end
        if d > 0.4f0 && c.goal.action !== :jump
            NG.move_heading!(c, w, atan(target[2] - c.pos[2], target[1] - c.pos[1]), dt; run = d > 3, maxstep = d)
            c.goal.action = c.action
        elseif c.goal.action !== :jump
            c.goal.action = :idle
        end
        lead = c
    end
end

"""
A chase camera for playing: always behind Lumi so W goes "into" the screen, rising over
trees instead of swinging around them (the follow view turns around Lumi, which loses the player).
"""
const CHASE_VIEWS = ((0f0, 7f0, 3.2f0), (0f0, 5f0, 2f0), (0f0, 4f0, 1.3f0), (0.35f0, 6f0, 3f0), (-0.35f0, 6f0, 3f0),
    (0.35f0, 4.5f0, 1.5f0), (-0.35f0, 4.5f0, 1.5f0), (0f0, 6f0, 4.4f0), (0.7f0, 5f0, 2f0), (-0.7f0, 5f0, 2f0), (0f0, 4f0, 6f0))   # last: over the crowns, 7.7 m from Lumi (5, 7.5 was 9.5 m, s53 tests)
const CHASE_K = Ref(1)    # the view in use: kept while it stays about as good as the best, so the camera does not flicker

"""
Trees and bushes between the eye and Lumi, as solid cylinders (pines are wide low down, which the engine's
two crown balls miss): samples along the line of sight and the eye itself, 1 per sample inside a tree.
"""
function trees_in_view(w, eye, target)
    o = 0f0
    for s in (0f0, 0.12f0, 0.25f0, 0.38f0, 0.5f0, 0.62f0, 0.74f0, 0.85f0)
        q = eye + s * (target - eye)
        for p in w.props
            if p.kind === :tree
                r = 1.6f0 * p.scale
                (q[1] - p.pos[1])^2 + (q[2] - p.pos[2])^2 < r^2 && p.pos[3] + 0.6f0 * p.scale < q[3] < p.pos[3] + 4.6f0 * p.scale && (o += 1f0)
            elseif p.kind === :bush    # a big bush in front hid Lumi completely (s39, media/s39-peek.png)
                r = 0.95f0 * p.scale
                (q[1] - p.pos[1])^2 + (q[2] - p.pos[2])^2 < r^2 && q[3] < p.pos[3] + 1.4f0 * p.scale && (o += 1f0)
            end
        end
    end
    return o
end

function chase_camera!(game, c, dt; snap = false)
    w = game.world
    target = c.pos + Point3f(0, 0, 0.6f0)
    a = c.yaw + NG.species_of(c).heading + Float32(pi)
    view(k) = (v = CHASE_VIEWS[k]; target + Point3f(v[2] * cos(a + v[1]), v[2] * sin(a + v[1]), v[3]))
    # a plugin's own view for the steered creature (CAMERA_GROUPS 3rd element: the kite holder, from
    # behind and low, looking up the string; tester s57 saw only string leave the top of the frame)
    for g in values(NG.CAMERA_GROUPS)
        v = Base.invokelatest(g, w)
        (v === nothing || Int32(v[1]) != c.id || length(v) < 3) && continue
        k = snap ? 1f0 : Float32(1 - exp(-3dt / 0.45))
        game.rig.mode = :fixed
        game.rig.eye += k * (Point3f(v[3][1]) - game.rig.eye)
        game.rig.target += k * (Point3f(v[3][2]) - game.rig.target)
        return
    end
    best = (Inf32, 1)
    for k in eachindex(CHASE_VIEWS)        # behind and a bit above, then lower, slightly turned, higher
        o = (NG.obstruction(w, view(k), target) + trees_in_view(w, view(k), target)) + 0.01f0 * k
        o < best[1] && (best = (o, k))
        o <= 0.01f0 * k && break
    end
    keep = CHASE_K[] <= length(CHASE_VIEWS) && (NG.obstruction(w, view(CHASE_K[]), target) + trees_in_view(w, view(CHASE_K[]), target)) + 0.01f0 * CHASE_K[] <= best[1] + 0.3f0
    keep || (CHASE_K[] = best[2])
    eye = view(CHASE_K[])
    k = snap ? 1f0 : Float32(1 - exp(-3dt / 0.45))
    game.rig.mode = :fixed
    game.rig.eye += k * (eye - game.rig.eye)
    game.rig.target += k * (target - game.rig.target)
end

"E by a flower picks it, E with a flower gives it (plugins/flowergift.jl), E by a loose pebble picks it up (cairns.jl): then this press is no wave."
function flower_e(game, w, me)
    for name in ("flowergift", "cairns", "boing")
        p = get(game.plugins, name, nothing)
        (p === nothing || !isdefined(p.mod, :uses_e)) && continue
        Base.invokelatest(p.mod.uses_e, w, me) && return true
    end
    return false
end

function NG.step!(s::Greetings, game, dt)
    w = game.world
    i = findfirst(c -> c.name == "Lumi", w.creatures)
    i === nothing && return
    me = w.creatures[i]
    a = me.action
    if me.controlled
        a === :wave && s.last_action !== :wave && !flower_e(game, w, me) && wave!(s, w, me)
        a === :jump && s.last_action !== :jump && jump!(s, w, me)
    end
    s.last_action = a
    isempty(s.followers) || step_followers!(s, w, me, dt)
    me.controlled && draw_crowd!(s, w, me)
    me.controlled && length(s.followers) >= 3 && parade_party!(s, game, w, me)
    me.controlled && length(s.followers) >= 2 && parade_cairn!(s, game, w, me)
    me.controlled || (s.best = 0)
    # the hint card: full for 5 s, then one line until 20 s, whenever you jump in as Lumi (not over a mini game's own start card)
    if haskey(GP, :hint)
        jumped_in = game.minigame isa NG.JumpIn
        if jumped_in && !s.was_controlled
            s.hint_t = 0.0
        end
        s.hint_t += dt
        # once the player walks off, the full card makes way at once (tester s59: it covered the strut for 4 s)
        jumped_in && 1.5 < s.hint_t < HINT_FULL && me.action in (:walk, :run) && (s.hint_t = HINT_FULL)
        show =jumped_in && s.hint_t < HINT_END
        GP[:hint].visible[] == show || (GP[:hint].visible[] = show)
        txt, fs = s.hint_t < HINT_FULL ? (HINT, 22) : (HINT_SHORT, 17)
        show && GP[:hint].text[] != txt && (GP[:hint].text[] = txt; GP[:hint].fontsize[] = fs)
    end
    # Jump in's follow camera; orbit and free round Lumi are freecam.jl's (the chase used to take
    # every pick, so all three menu modes looked the same while playing, the human 2026-11-23)
    if game.minigame isa NG.JumpIn && NG.camera_pick(game) === :follow
        chase_camera!(game, me, dt; snap = !s.was_controlled)
    end   # after a jump-in, freecam.jl brings back the camera the player had chosen
    s.was_controlled = game.minigame isa NG.JumpIn
end

register!(Greetings())
