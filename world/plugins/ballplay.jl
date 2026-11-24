# Ball play: as Lumi (Play → Jump in) walk into the red ball and you kick it. Critters
# nearby run after it and pass it back to you. Keep the passes going: every pass counts,
# and a streak of 3, 5, 8... gets cheers and hearts from the whole group.
const NG = NeverendingGame

const KICK_REACH = 0.75f0     # Lumi's toe to the ball's middle
const CHASE_RADIUS = 14f0     # critters this close to the ball join in
const STREAK_GAP = 14.0       # seconds: a pass back later than this starts a new streak
const PASS_LINES = ("To you, Lumi!", "Catch!", "Your turn!", "Wheee!", "Back to you!", "Kick it here!")
const STREAK_LINES = Dict(3 => "Three in a row!", 5 => "Five passes! Wow!", 8 => "Eight! Best team ever!", 12 => "Twelve! Legends!")

push!(NG.BUSY_GOALS, :fetch)
push!(NG.BUSY_GOALS, :rally_wait)  # a critter waiting for the ball to come back stays in the game
wait_ball!(c, w, action = :idle) = (c.goal = NG.Goal(:rally_wait, c.pos, action, 12.0, w.t + 12.0, true, 0, false); c.action = action)

mutable struct BallPlay <: System
    kick_t::Float64            # Lumi's last kick (cooldown)
    last_pass::Float64         # when a critter last passed to Lumi
    streak::Int
    best::Int
    passer::Int32              # who will pass next (0: nobody chasing)
    receiver::Int32            # whom the passer passes to (0: Lumi)
    rally::Int                 # passes in a critters' own game (0: none)
    rally_len::Int
    speed::Float32             # the ball's speed last frame (a jump: somebody kicked it)
    fetch_until::Float64       # the fetcher gives up after this
    pass_t::Float64            # the last critter pass: the receiver lets the ball roll to it first
    trap_t::Float64            # when the fetcher stopped the ball under its foot (-100: not yet)
end
BallPlay() = BallPlay(-10.0, -100.0, 0, 0, 0, 0, 0, 0, 0f0, 0.0, -100.0, -100.0)

const PASS_GAP = 1.7          # seconds between two critter passes: a player sees each one
const WIND_UP = 0.55          # the fetcher holds the trapped ball this long, then kicks

# critters' own ball games (a waiting partner holds :rally_wait so a chat does not pull it away)
const RALLIES = true
const RALLY_LINES = ("Over to you!", "Catch!", "Heads up!", "Your go!", "Hup!", "Nice one!")
const RALLY_END = ("Good game!", "Again tomorrow!", "Phew!", "I win! ...I think.")

emote(id, kind) = isdefined(Main, :EMOTES) && haskey(Main.EMOTES, :emote) && Base.invokelatest(Main.EMOTES[:emote], id, kind)

const LAST_KICK = Ref("")     # who fetched the last kick of Lumi's, or everyone's state when nobody could
can_fetch(c) = !c.controlled && !NG.busy(c) && c.goal.kind ∉ (:follow, :answer, :circle, :fetch) && c.species != "Lumi"

"Lumi kicks the ball the way it faces; the nearest free critter runs after it."
function lumi_kick!(s::BallPlay, w, me, ball)
    dir = Vec2f(cos(me.yaw), sin(me.yaw))
    NG.kick!(ball, me.action === :run ? 7.5f0 : 5.5f0, dir)
    s.kick_t = w.t
    if s.rally > 0          # Lumi steals the ball from a critters' game: it is Lumi's game now
        for id in (s.passer, s.receiver)
            c = id == 0 ? nothing : NG.creature(w, id)
            c === nothing || c.goal.kind ∉ (:fetch, :rally_wait) || NG.choose_goal!(c, w)
        end
        s.passer = 0; s.receiver = 0; s.rally = 0
    end
    passed_back = w.t - s.last_pass < STREAK_GAP && s.streak > 0
    passed_back || (s.streak = 0)
    NG.emit!(w, :ball_kick; who = me.name)
    # the nearest critter who is free fetches it (one at a time, so it is a game of passes)
    best = nothing; bd = CHASE_RADIUS
    for c in w.creatures
        can_fetch(c) || continue
        d = hypot(c.pos[1] - ball.pos[1], c.pos[2] - ball.pos[2])
        d < bd && (best = c; bd = d)
    end
    # why nobody ran (a flaky play test printed only the state after the fact)
    LAST_KICK[] = best === nothing ? join(["$(c.name) $(c.goal.kind)/$(c.action) ctl=$(c.controlled) $(round(hypot(c.pos[1] - ball.pos[1], c.pos[2] - ball.pos[2]); digits = 1))m"
                                            for c in w.creatures if c !== me], "; ") : "fetch: $(best.name)"
    best === nothing && return
    best.goal = NG.Goal(:fetch, ball.pos, :play, 1.0, w.t + 20, false, ball.id, true)
    s.passer = best.id; s.fetch_until = w.t + 20
    rand(w.rng) < 0.5 && NG.say!(w, best, rand(w.rng, ("Mine!", "I've got it!", "Ooh, the ball!")); duration = 1.5)
end

"The fetcher reached the ball: it passes it back to Lumi, and the streak grows."
function pass_back!(s::BallPlay, w, c, me, ball)
    to = Vec2f(me.pos[1] - ball.pos[1], me.pos[2] - ball.pos[2])
    d = norm(to)
    # just hard enough to roll up to Lumi (damping 1.3/s: distance ≈ speed / 1.3)
    NG.kick!(ball, clamp(1.3f0 * d + 0.6f0, 2.5f0, 9f0), to / max(d, 1f-3))
    c.yaw = atan(to[2], to[1]) - NG.species_of(c).heading
    c.goal = NG.Goal(:answer, c.pos, :jump, 1.5, w.t + 1.5, true, 0, false); c.action = :jump
    s.streak += 1; s.best = max(s.best, s.streak); s.last_pass = w.t; s.passer = 0
    line = get(STREAK_LINES, s.streak, nothing)
    if line === nothing
        NG.say!(w, c, rand(w.rng, PASS_LINES); duration = 1.8)
        emote(c.id, :note)
    else
        NG.say!(w, c, line; duration = 2.5)
        for o in w.creatures   # everyone close by cheers
            hypot(o.pos[1] - me.pos[1], o.pos[2] - me.pos[2]) < 10 || continue
            emote(o.id, :heart)
            if o !== c && can_fetch(o)      # and hops for joy where it stands
                o.goal = NG.Goal(:answer, o.pos, :jump, 1.6, w.t + 1.6, true, 0, false); o.action = :jump
            end
        end
        NG.emit!(w, :ball_streak; who = c.name, passes = s.streak)
    end
    NG.remember!(c, w.t, "played ball with Lumi")
    NG.emit!(w, :ball_pass; who = c.name, streak = s.streak)
end

"Turn `c` smoothly (about 4 rad/s) to face `p`."
function turn_to!(c, p, dt)
    want = atan(p[2] - c.pos[2], p[1] - c.pos[1]) - NG.species_of(c).heading
    d = rem2pi(Float32(want - c.yaw), RoundNearest)
    c.yaw += clamp(d, -4f0 * Float32(dt), 4f0 * Float32(dt))
end

"The nearest free critter to the ball other than `not`, within `r` metres."
function nearest_free(w, ball, not, r)
    best = nothing; bd = r
    for c in w.creatures
        (c === not || !can_fetch(c) || c.action === :sleep) && continue
        d = hypot(c.pos[1] - ball.pos[1], c.pos[2] - ball.pos[2])
        d < bd && (best = c; bd = d)
    end
    return best
end

"A critter kicked the ball on its own: a friend nearby runs for it and they pass it back and forth."
function start_rally!(s::BallPlay, w, kicker, ball; night_ok = false)
    !night_ok && NG.night_factor(w) > 0.5f0 && return      # at night they are off to bed (the test plays one anyway)
    f = nearest_free(w, ball, kicker, 12f0)
    f === nothing && return
    f.goal = NG.Goal(:fetch, ball.pos, :play, 1.0, w.t + 15, false, ball.id, true)
    wait_ball!(kicker, w)
    s.passer = f.id; s.receiver = kicker.id; s.rally = 1; s.fetch_until = w.t + 15; s.rally_len = rand(w.rng, 4:7)
    s.pass_t = w.t; s.trap_t = -100.0     # the kick counts as a pass: the friend may not pass on at once
    NG.say!(w, f, rand(w.rng, ("Ooh, pass it here!", "Mine!", "Let's play!")); duration = 1.8)
    NG.emit!(w, :ball_rally; who = f.name, with = kicker.name)
end

"The fetcher passes to its friend; the friend becomes the next fetcher."
function rally_pass!(s::BallPlay, w, c, ball)
    r = NG.creature(w, s.receiver)
    if r === nothing || s.rally >= s.rally_len || !(r.goal.kind in (:answer, :rally_wait) || can_fetch(r))
        NG.say!(w, c, rand(w.rng, RALLY_END); duration = 2)
        emote(c.id, :heart); r === nothing || emote(r.id, :heart)
        NG.remember!(c, w.t, "played ball with a friend")
        NG.choose_goal!(c, w)
        r === nothing || r.goal.kind !== :rally_wait || NG.choose_goal!(r, w)
        s.passer = 0; s.receiver = 0; s.rally = 0
        return
    end
    to = Vec2f(r.pos[1] - ball.pos[1], r.pos[2] - ball.pos[2]); d = norm(to)
    NG.kick!(ball, clamp(1.3f0 * d + 0.4f0, 2.5f0, 8f0), to / max(d, 1f-3))
    c.yaw = atan(to[2], to[1]) - NG.species_of(c).heading
    wait_ball!(c, w, :jump)
    rand(w.rng) < 0.6 && NG.say!(w, c, rand(w.rng, RALLY_LINES); duration = 1.6)
    emote(c.id, :note)
    r.goal = NG.Goal(:fetch, ball.pos, :play, 1.0, w.t + 15, false, ball.id, true)   # run: a walker never catches a rolling ball
    s.passer = r.id; s.receiver = c.id; s.rally += 1; s.fetch_until = w.t + 15; s.pass_t = w.t
    NG.emit!(w, :ball_pass; who = c.name, to = r.name, rally = s.rally)
end

function NG.step!(s::BallPlay, game, dt)
    w = game.world
    i = findfirst(p -> p.kind === :ball, w.props)
    i === nothing && return
    ball = w.props[i]
    # a ball that came to rest at the water's edge (where nobody can walk round it) rolls back up the beach
    v = get(ball.data, "vel", nothing)
    if (v === nothing || hypot(v[1], v[2]) < 0.05) && !NG.on_land(w.island, ball.pos[1], ball.pos[2]; margin = 1.5f0)
        d = -Vec2f(ball.pos[1], ball.pos[2])
        NG.kick!(ball, 4f0, d / max(norm(d), 1f-3))
    end
    me = NG.creature(w, "Lumi")
    me === nothing && return
    speed = v === nothing ? 0f0 : Float32(hypot(v[1], v[2]))
    kicked = speed > s.speed + 1.5f0
    s.speed = speed
    lumi_playing = me.controlled && hypot(me.pos[1] - ball.pos[1], me.pos[2] - ball.pos[2]) < 15
    if lumi_playing && s.rally > 0          # Lumi comes over: the critters' own game ends, the ball is Lumi's
        for id in (s.passer, s.receiver)
            c = id == 0 ? nothing : NG.creature(w, id)
            c === nothing || c.goal.kind ∉ (:fetch, :rally_wait) || NG.choose_goal!(c, w)
        end
        s.passer = 0; s.receiver = 0; s.rally = 0
    end
    if RALLIES && kicked && s.passer == 0 && !lumi_playing
        # a critter kicked it by itself (the engine's ball play): maybe a friend joins in
        k = findmin(c -> c === me ? Inf32 : hypot(c.pos[1] - ball.pos[1], c.pos[2] - ball.pos[2]), w.creatures)
        k[1] < 1.5f0 && rand(w.rng) < 0.8 && start_rally!(s, w, w.creatures[k[2]], ball)
    end
    if me.controlled && w.t - s.kick_t > 0.6 && me.action in (:walk, :run) &&
       hypot(me.pos[1] - ball.pos[1], me.pos[2] - ball.pos[2]) < KICK_REACH * ball.scale
        lumi_kick!(s, w, me, ball)
    end
    show_counter!(s, game)
    s.passer == 0 && return
    c = NG.creature(w, s.passer)
    if c === nothing || c.goal.kind !== :fetch || (s.receiver == 0 && !me.controlled)
        s.passer = 0; s.receiver = 0; s.rally = 0
        return
    end
    c.goal.target = ball.pos                  # run where the ball rolls
    # reach: the critter's own size (a big Sir Sniffsalot stopped by Separation 1.2 m off the ball never got it)
    reach = max(0.7f0, 0.6f0 * NG.body_radius(NG.species_of(c)) + 0.35f0 * ball.scale)
    # "arrived" stops the engine walking it, and 1 s later the goal ends: while the ball is still
    # rolling away that left the fetcher standing (and the game over), so it keeps chasing
    c.goal.arrived && hypot(c.pos[1] - ball.pos[1], c.pos[2] - ball.pos[2]) >= reach && (c.goal.arrived = false; c.goal.until = s.fetch_until)
    c.goal.arrived && (c.goal.until = max(c.goal.until, w.t + 1.0))   # waiting for the ball to slow down
    # both turn as a player would: the friend watches the ball come, the fetcher lines up its pass while it winds up
    r = s.receiver == 0 ? me : NG.creature(w, s.receiver)
    if r !== nothing && !r.controlled && r.goal.kind === :rally_wait
        turn_to!(r, ball.pos, dt)
    end
    s.trap_t > 0 && r !== nothing && turn_to!(c, r.pos, dt)
    near = hypot(c.pos[1] - ball.pos[1], c.pos[2] - ball.pos[2]) < reach
    s.trap_t < max(s.pass_t, s.kick_t, s.last_pass) && (s.trap_t = -100.0)   # a trap from an earlier fetch does not count
    if near && s.trap_t < 0 && speed < 4f0
        # trap: the ball stops dead at the fetcher's feet, it hops once and lines up the pass
        ball.data["vel"] = [0.0, 0.0]; s.speed = 0f0; s.trap_t = w.t
        c.action = :jump
    end
    if near && s.trap_t > 0 && w.t - s.trap_t > WIND_UP && w.t - s.pass_t > PASS_GAP   # two critters side by side ping-ponged 3 passes in a second
        s.trap_t = -100.0
        s.receiver == 0 ? pass_back!(s, w, c, me, ball) : rally_pass!(s, w, c, ball)
    elseif w.t > s.fetch_until                # lost it (rolled to the beach, stuck behind a bush)
        NG.say!(w, c, "Too fast for me!"; duration = 1.8)
        NG.choose_goal!(c, w); s.passer = 0; s.streak = 0; s.receiver = 0; s.rally = 0; s.trap_t = -100.0
    end
    return
end

"The pass counter at the top of the view while a streak runs in Jump in."
function show_counter!(s::BallPlay, game)
    haskey(BP, :counter) || return
    on = game.minigame isa NG.JumpIn && s.streak > 0 && game.world.t - s.last_pass < STREAK_GAP
    txt = "Passes  $(s.streak)     best  $(s.best)"
    p = BP[:counter]
    p.visible[] == on || (p.visible[] = on)
    on && p.text[] != txt && (p.text[] = txt)
end

isdefined(Main, :BALLPLAY) || Core.eval(Main, :(const BALLPLAY = Dict{Symbol,Any}()))
const BP = Main.BALLPLAY
const CURRENT = Ref{Any}(nothing)
"The fetcher while critters play ball among themselves (the watching camera turns to it)."
watch_rally(w) = (s = CURRENT[]; s === nothing || s.rally == 0 || s.passer == 0 ? nothing : s.passer)

"Frame the whole rally (both critters and the ball) from the side, not the fetcher's back."
function rally_group(w)
    id = watch_rally(w)
    id === nothing && return nothing
    s = CURRENT[]
    a = NG.creature(w, s.passer); b = NG.creature(w, s.receiver)
    i = findfirst(p -> p.kind === :ball, w.props)
    (a === nothing || b === nothing || i === nothing) && return nothing
    return id, [a.pos, b.pos, w.props[i].pos]
end

function NG.start!(s::BallPlay, game)
    CURRENT[] = s
    NG.CAMERA_MOMENTS["ballplay"] = watch_rally
    isdefined(NG, :CAMERA_GROUPS) && (NG.CAMERA_GROUPS["ballplay"] = rally_group)
    game.stage === nothing && return
    haskey(BP, :counter) && BP[:counter].parent === game.stage.overlay && return
    BP[:counter] = textlabel!(game.stage.overlay, Point2f(0.5, 0.92); space = :relative, text = "Passes  0", fontsize = 24,
        text_color = RGBf(1, 0.97, 0.85), background_color = RGBAf(0.07, 0.08, 0.13, 0.75),
        strokewidth = 0, padding = 12, cornerradius = 10, visible = false)
    return
end
function NG.stop!(s::BallPlay, game)
    c = s.passer == 0 ? nothing : NG.creature(game.world, s.passer)
    c === nothing || c.goal.kind !== :fetch || NG.choose_goal!(c, game.world)
    s.passer = 0; s.receiver = 0; s.rally = 0
    delete!(NG.CAMERA_MOMENTS, "ballplay")
    isdefined(NG, :CAMERA_GROUPS) && delete!(NG.CAMERA_GROUPS, "ballplay")
    haskey(BP, :counter) && (BP[:counter].visible[] = false)
end

register!(BallPlay())
