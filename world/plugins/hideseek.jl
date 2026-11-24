# Hide and seek: four friends hide behind trees and bushes while Lumi counts to ten. Walk around
# and find them: a hidden friend giggles now and then (a little note pops up over its hiding spot).
# Walk up to one and it jumps out ("You found me!") and joins a parade behind Lumi.
# Start card, clock on the first key, HUD with the nearest giggle's direction, end card with "R to play again".
const NG = NeverendingGame

# best scores survive restarts (state/bests.json, shared by the mini games); a quiet copy never writes
bests_file(game) = joinpath(game.paths.state, "bests.json")
load_best(game, key, default) = (f = bests_file(game); isfile(f) ? Float64(get(NG.read_json(f), key, default)) : Float64(default))
function save_best!(game, key, v)
    game.dash === nothing && return
    # a UI test's round is not the player's best (tests put P[:best] back, not this file)
    game.tests !== nothing && NG.running(game.tests) && return
    f = bests_file(game)
    d = isfile(f) ? NG.read_json(f) : Dict{String,Any}()
    d[key] = v
    NG.write_json(f, d)
end
const N_HIDERS = 4
const TIME_LIMIT = 120.0
const MAX_LEVEL = 4               # each win takes 20 s off the next round's clock (a reason to play twice, review #18)
level(game) = Int(get!(() -> round(Int, load_best(game, "hideseek_level", 1)), P, :level))
time_limit(game) = TIME_LIMIT - 20.0 * (level(game) - 1)
const FIND_RADIUS = 2.6f0       # a friend peeking out beside a trunk counts: Lumi cannot walk through the tree
const GIGGLE_EVERY = (5.0, 9.0)     # seconds between two giggles of one hider
const FOLLOW_GAP = 1.1f0
const HIDE_GOALS = (:hide, :found)
foreach(k -> push!(NG.BUSY_GOALS, k), HIDE_GOALS)   # nobody pulls a hider into a chat

const PLOTS_VERSION = 1
isdefined(Main, :HIDESEEK_PLOTS) || Core.eval(Main, :(const HIDESEEK_PLOTS = Dict{Symbol,Any}()))
const P = Main.HIDESEEK_PLOTS

mutable struct HideSeek <: MiniGame
    jump::NG.JumpIn
    lumi::Int32
    hiders::Vector{Int32}
    spots::Vector{Point3f}
    found::Vector{Bool}
    giggle_at::Vector{Float64}     # play time of each hider's next giggle
    last_giggle::Int               # the hider who giggled last
    heard::Vector{Bool}            # giggled at least once: the HUD points at the nearest one heard
    state::Symbol                  # :ready, :playing, :over
    t::Float64
    t_state::Float64
    flash::Float64
end

function HideSeek(game)
    j = NG.JumpIn(game)
    HideSeek(j, j.id, Int32[], Point3f[], Bool[], Float64[], 0, Bool[], :ready, 0.0, 0.0, 0.0)
end

NG.game_title(::Type{HideSeek}) = "Hide and seek (WASD)"
NG.game_description(::Type{HideSeek}) =
    "Four friends hide behind trees and bushes. Follow their giggles and find them all in $(Int(TIME_LIMIT)) seconds."

# the chase camera, name tags and direction words come from the firefly catch
const CURRENT_GAME = Ref{Any}(nothing)
ff() = CURRENT_GAME[].plugins["firefly_catch"].mod

function ensure_plots!(game)
    get(P, :version, 0) == PLOTS_VERSION && return
    ov = game.stage.overlay
    P[:hud] = textlabel!(ov, Point2f(0.5, 0.93); space = :relative, text = " ", fontsize = 24,
        text_color = RGBf(1, 0.95, 0.6), background_color = RGBAf(0.08, 0.09, 0.12, 0.75),
        strokewidth = 0, padding = 10, cornerradius = 8, visible = false)
    P[:card] = textlabel!(ov, Point2f(0.5, 0.64); space = :relative, text = " ", fontsize = 22, justification = :center,
        text_color = RGBf(1, 0.97, 0.85), background_color = RGBAf(0.07, 0.08, 0.13, 0.86),
        strokewidth = 0, padding = 22, cornerradius = 14, visible = false)
    P[:version] = PLOTS_VERSION
end
show_plots!(on::Bool) = foreach(k -> (P[k].visible[] = on), (:hud, :card))

const START_TEXT = """Hide and seek
Your friends hid behind trees and bushes while you counted to ten!
Watch for giggles: a little note pops up over a hiding friend.
Walk up close to find them. Find all $N_HIDERS in $(Int(TIME_LIMIT)) seconds.

W / S  walk      A / D  turn      Shift  run

Press W to start"""

flat(a, b) = hypot(a[1] - b[1], a[2] - b[2])

"Is `q` a spot a creature of radius `r` can stand on: land, no walkway, outside every solid footprint?"
standable(w, q, r) = NG.on_land(w.island, q[1], q[2]; margin = 0.8f0) && NG.walkway_height(q[1], q[2]) === nothing &&
    !any(p -> haskey(NG.SOLID_FOOTPRINT, p.kind) && flat(p.pos, q) < NG.SOLID_FOOTPRINT[p.kind] * p.scale + 0.7f0 * r + 0.15f0, w.props)

"""
Hiding spots: just behind a tree or a big bush, on the side away from Lumi, so the prop hides the
friend from where the player starts. Spread out; the first one is close by (a first play finds it fast).
"""
function hiding_spots(w, from, r)
    cands = Tuple{Float32,Point3f}[]
    for p in w.props
        (p.kind === :tree || (p.kind === :bush && p.scale > 0.8f0)) || continue
        d = flat(p.pos, from)
        6f0 < d < 0.8f0 * w.island.radius || continue
        dir = Vec2f(p.pos[1] - from[1], p.pos[2] - from[2]) / d
        foot = get(NG.SOLID_FOOTPRINT, p.kind, 0.5f0) * p.scale
        for turn in (0f0, 0.5f0, -0.5f0)
            dd = Vec2f(dir[1] * cos(turn) - dir[2] * sin(turn), dir[1] * sin(turn) + dir[2] * cos(turn))
            q = NG.ground(w.island, Point2f(p.pos[1], p.pos[2]) + (foot + 0.7f0 * r + 0.35f0) * dd)
            standable(w, q, r) && (push!(cands, (d, q)); break)
        end
    end
    sort!(cands; by = first)
    out = Point3f[]
    for (d, q) in cands     # the nearest first, then spread out
        all(o -> flat(o, q) > 6f0, out) && push!(out, q)
        length(out) == N_HIDERS && break
    end
    return out
end

"""
Has Lumi reached the tree or bush that hides a friend at `q`? Walking straight at a giggle ends
against the trunk on the near side, a few metres from the friend: touching its cover finds it too.
"""
function at_cover(w, q, me)
    best, bd = nothing, Inf32
    for p in w.props
        (p.kind === :tree || p.kind === :bush) && haskey(NG.SOLID_FOOTPRINT, p.kind) || continue
        d = flat(p.pos, q) - NG.SOLID_FOOTPRINT[p.kind] * p.scale
        d < bd && (best = p; bd = d)
    end
    (best === nothing || bd > 1.2f0) && return false
    foot = NG.SOLID_FOOTPRINT[best.kind] * best.scale
    return flat(best.pos, me) < foot + 1.0f0 && flat(q, me) < 2foot + FIND_RADIUS
end

function release!(w, id)
    c = NG.creature(w, id)
    c === nothing && return
    c.goal.kind in HIDE_GOALS && (c.goal = NG.Goal(:idle, c.pos, :idle, 1.0, w.t + 1.0, true, 0, false))
end

function reset!(m::HideSeek, game)
    w = game.world
    foreach(id -> release!(w, id), m.hiders)
    c = NG.creature(w, m.lumi)
    # always from the berry race's meadow start line: from wherever Lumi stood, the first giggle could lie
    # past a tree and a rock, and W/A/D steered it into the nook between them (s39, 2 of 7 runs)
    let
        s = Base.invokelatest(game.plugins["berry_race"].mod.start_spot, w)
        s === nothing || (c.pos = s[1]; c.yaw = atan(s[1][2] - s[2].pos[2], s[1][1] - s[2].pos[1]))
    end
    NG.face_open!(w, c)
    friends = [o for o in w.creatures if o.id != c.id && !o.controlled && o.action !== :sleep && o.goal.kind ∉ NG.BUSY_GOALS]
    length(friends) < N_HIDERS && append!(friends, [o for o in w.creatures if o.id != c.id && !o.controlled && o ∉ friends])
    sort!(friends; by = o -> flat(o.pos, c.pos))
    spots = hiding_spots(w, c.pos, 0.5f0)
    n = min(length(spots), length(friends), N_HIDERS)
    m.hiders = Int32[]; m.spots = Point3f[]
    for k in 1:n
        o = friends[k]
        NG.leave_interactions!(w, o)
        o.pos = spots[k]                      # they ran off while Lumi counted (the start card)
        o.yaw = atan(c.pos[2] - o.pos[2], c.pos[1] - o.pos[1]) + 0.6f0 * (rand(w.rng, Float32) - 0.5f0)
        o.goal = NG.Goal(:hide, o.pos, :sit, 1e6, w.t + 1e6, true, 0, false)
        push!(m.hiders, o.id); push!(m.spots, spots[k])
    end
    m.found = fill(false, n)
    m.giggle_at = [1.0 + 2.5k for k in 1:n]   # the nearest giggles first
    m.last_giggle = 0
    m.heard = fill(false, n)
    empty!(PEEK)
    m.state = :ready; m.t = 0.0; m.t_state = 0.0; m.flash = 0.0
    lv = level(game)
    Makie.update!(P[:card]; text = lv == 1 ? START_TEXT :
        replace(START_TEXT, "Hide and seek\n" => "Hide and seek  ·  Level $lv\n",
                "in $(Int(TIME_LIMIT)) seconds" => "in $(Int(time_limit(game))) seconds"))
    P[:card].visible[] = true
end

function NG.start!(m::HideSeek, game)
    CURRENT_GAME[] = game
    NG.start!(m.jump, game)
    ensure_plots!(game)
    show_plots!(true)
    reset!(m, game)
    Base.invokelatest(ff().start_view!, game, NG.creature(game.world, m.lumi), 0.0; snap = true)   # Lumi under the card (tester s45)
end

function NG.input!(m::HideSeek, game, ev)
    ev.action == Makie.Keyboard.press || return
    if ev.key == Makie.Keyboard.r
        reset!(m, game)
    elseif m.state === :ready && ev.key in (Makie.Keyboard.w, Makie.Keyboard.s, Makie.Keyboard.a, Makie.Keyboard.d, Makie.Keyboard.up)
        m.state = :playing; m.t_state = 0.0
        P[:card].visible[] = false
    end
end

emote(id, kind) = haskey(Main.EMOTES, :emote) && Base.invokelatest(Main.EMOTES[:emote], id, kind)

const FOUND_LINES = ("You found me!", "Aww, found!", "Hee hee, you got me!", "How did you see me?")
const PEEK = Dict{Int32,Float64}()    # hider id => play time its peek ends
const GIGGLES = ("hee hee", "hihi", "*giggle*")

function step_parade!(m, w, me, dt)
    for (k, id) in enumerate(m.hiders)
        m.found[k] || continue
        c = NG.creature(w, id)
        (c === nothing || c.goal.kind !== :found) && continue
        # a zig-zag parade, half a step off to alternate sides: straight behind Lumi the friends walked
        # between the chase camera and the player and filled the bottom of the view
        n = count(view(m.found, 1:k))
        side = (isodd(n) ? 1f0 : -1f0) * 0.9f0
        back = me.pos - FOLLOW_GAP * (0.4f0 + 0.6f0 * n) * Point3f(cos(me.yaw), sin(me.yaw), 0)
        target = back + side * Point3f(-sin(me.yaw), cos(me.yaw), 0)
        standable(w, target, 0.4f0) || (target = back)     # the side slot is in a bush or a trunk: fall in line
        d = flat(target, c.pos)
        if m.state === :over
            c.goal.action = :jump            # everyone found: the whole parade hops
        elseif d > 0.4f0
            NG.move_heading!(c, w, atan(target[2] - c.pos[2], target[1] - c.pos[1]), dt; run = d > 3, maxstep = d)
            c.goal.action = c.action
        else
            c.goal.action = :idle
        end
    end
end

"The nearest hiding spot not found yet (of the friends heard giggling, with `heard_only`), or nothing."
function hint_spot(m::HideSeek, c; heard_only = true)
    ks = [k for k in eachindex(m.hiders) if !m.found[k] && (m.heard[k] || !heard_only)]
    isempty(ks) ? nothing : m.spots[ks[argmin([flat(m.spots[k], c.pos) for k in ks])]]
end

function NG.step!(m::HideSeek, game, dt)
    w = game.world
    c = NG.creature(w, m.lumi)
    mod = ff()
    # name tags and speech bubbles would give the hiders away: off while seeking, back on at the end
    Base.invokelatest(mod.name_tags!, game, m.state === :over)
    m.state === :playing ? NG.step!(m.jump, game, dt) : (c.action = m.state === :over && all(m.found) ? :dance : :idle)
    m.t_state += dt
    Base.invokelatest(m.state === :ready ? mod.start_view! : mod.chase_camera!, game, c, dt)
    m.state === :playing && (m.t += dt)
    m.flash = max(0.0, m.flash - dt)
    for (k, id) in enumerate(m.hiders)
        o = NG.creature(w, id)
        o === nothing && continue
        if !m.found[k]
            o.goal.kind === :hide || continue              # a shower or a wave took it: it is out of the game
            m.state === :playing || continue
            # a peek ends: back down behind the cover
            m.t > get(PEEK, id, Inf) && (o.goal.action = :sit; delete!(PEEK, id))
            if m.t >= m.giggle_at[k]
                emote(id, :note)
                # and it peeks: hops up behind its tree for a moment, turned towards Lumi (you can catch it in the act)
                o.goal.action = :jump; PEEK[id] = m.t + 1.2
                o.yaw = atan(c.pos[2] - o.pos[2], c.pos[1] - o.pos[1])
                NG.say!(w, o, rand(w.rng, GIGGLES); duration = 1.2)
                m.last_giggle = k; m.heard[k] = true
                # the nearest friend giggles most: the clues lead somewhere instead of pulling every way
                near = hint_spot(m, c; heard_only = false) == m.spots[k]
                m.giggle_at[k] = m.t + (near ? 0.6 : 1.4) * (GIGGLE_EVERY[1] + (GIGGLE_EVERY[2] - GIGGLE_EVERY[1]) * rand(w.rng))
            end
            if flat(o.pos, c.pos) < FIND_RADIUS || at_cover(w, o.pos, c.pos)
                m.found[k] = true
                m.flash = 1.2
                o.goal = NG.Goal(:found, o.pos, :jump, 1e6, w.t + 1e6, true, c.id, false)
                o.yaw = atan(c.pos[2] - o.pos[2], c.pos[1] - o.pos[1])
                NG.say!(w, o, rand(w.rng, FOUND_LINES); duration = 2.0)
                emote(id, :hey)
                NG.say!(w, c, count(m.found) == length(m.found) ? "Found everyone!" : "Found you, $(o.name)!"; duration = 1.5)
                NG.emit!(w, :hideseek_found; who = o.name, by = c.name, n = count(m.found))
                m.last_giggle == k && (m.last_giggle = 0)
            end
        end
    end
    # a found friend first hops out of its hiding spot for a second, then walks along behind Lumi
    for (k, id) in enumerate(m.hiders)
        o = NG.creature(w, id)
        (m.found[k] && o !== nothing && o.goal.kind === :found && o.goal.action === :jump && m.state === :playing &&
         w.t > o.goal.until - 1e6 + 1.0) && (o.goal.action = :idle)   # until = the moment it was found + 1e6
    end
    m.state === :playing && step_parade!(m, w, c, dt)
    left = max(0.0, time_limit(game) - m.t)
    nfound = count(m.found)
    if m.state === :playing && (nfound == length(m.found) || left <= 0)
        m.state = :over; m.t_state = 0.0
        won = nfound == length(m.found)
        best = get!(() -> load_best(game, "hideseek", Inf), P, :best)
        best < 1 && (best = P[:best] = Inf)        # a 0.0 s round (no key pressed, a test) is no best (as firefly_catch)
        newbest = won && 1 <= m.t < best
        newbest && (P[:best] = m.t; save_best!(game, "hideseek", m.t))
        lv = level(game)
        if won && lv < MAX_LEVEL      # the next round is a step harder
            P[:level] = lv + 1; save_best!(game, "hideseek_level", lv + 1)
        end
        up = !won ? "" : lv < MAX_LEVEL ? "\nNext round: level $(lv + 1), $(Int(time_limit(game))) seconds!" : "\nTop level: you are a master seeker!"
        for (k, id) in enumerate(m.hiders)
            o = NG.creature(w, id)
            (o === nothing || o.goal.kind ∉ HIDE_GOALS) && continue
            o.goal.action = :jump
            won && (emote(id, :heart); NG.say!(w, o, rand(w.rng, ("Again! Again!", "You're good at this!", "Yay, Lumi!")); duration = 3.0))
            if !won && !m.found[k]     # the ones not found come out of hiding and run over to show where they were
                NG.say!(w, o, rand(w.rng, ("I was here all along!", "Ta-daa! Here I am!", "You walked right past me!")); duration = 3.0)
                emote(id, :hey)
                to = NG.ground(w.island, Point2f(c.pos[1], c.pos[2]) + 1.4f0 * Point2f(cos(0.8f0k), sin(0.8f0k)))
                o.goal = NG.Goal(:wander, NG.on_land(w.island, to[1], to[2]; margin = 0.5f0) ? to : o.pos, :jump, 3.0, 0.0, false, 0, true)
            end
        end
        Makie.update!(P[:card]; text = won ?
            @sprintf("You found all %d in %.1f s!\n%s%s\n\nPress R to play again", nfound, m.t,
                     newbest ? "A new best time!" : @sprintf("Your best: %.1f s", best), up) :
            @sprintf("Time's up! You found %d of %d.\nThe others were behind the trees: watch for the little notes.\n\nPress R to play again", nfound, length(m.found)))
        P[:card].visible[] = true
    end
    msg = if m.state === :ready
        "Press W to start"
    elseif m.state === :over
        nfound == length(m.found) ? "Found everyone!" : @sprintf("Time's up: %d/%d found", nfound, length(m.found))
    else
        q = hint_spot(m, c)
        hint = if q !== nothing
            @sprintf("a giggle %.0f m %s", flat(q, c.pos), Base.invokelatest(mod.direction_word, c, q))
        else
            "listen for giggles..."
        end
        @sprintf("Found %d/%d    %3.0f s left    %s", nfound, length(m.found), left, hint)
    end
    Makie.update!(P[:hud]; text = msg)
    # the start card says "Press W to start" itself: no second prompt above it (tester s44)
    (m.state !== :ready) == P[:hud].visible[] || (P[:hud].visible[] = m.state !== :ready)
    P[:hud].text_color[] = m.flash > 0 ? RGBf(0.55, 1, 0.55) : RGBf(1, 0.95, 0.6)
end

NG.finished(m::HideSeek) = m.state === :over && m.t_state > 60

function NG.stop!(m::HideSeek, game)
    w = game.world
    foreach(id -> release!(w, id), m.hiders)
    Base.invokelatest(ff().name_tags!, game, true)
    get(P, :version, 0) == PLOTS_VERSION && show_plots!(false)
    NG.stop!(m.jump, game)
    game.rig.mode = :follow
end

register!(HideSeek)
