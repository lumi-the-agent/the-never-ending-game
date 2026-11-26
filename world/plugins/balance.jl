# Keep the island level (s114, todo #437: something to PLAY): the island is a seesaw (seesaw.jl) and your
# friends keep spotting things at the shore. Every few seconds someone shouts and a crowd runs to the rim;
# the island tips toward them. You are Lumi, and today you are heavy (five friends' worth): run to the
# other side and the island comes back level. Tip too far for too long and the low shore goes under the sea:
# SPLASH, everyone over there gets wet feet. Three splashes and the game is over; keep it dry for 60 seconds.
const NG = NeverendingGame

const SECONDS = 60.0
const HEAVY = 5.0f0              # Lumi's weight in friends
const SPLASH_ANGLE = 0.095f0     # rad (5.4°): the low shore is under water
const SPLASH_HOLD = 1.3          # s tipped that far before it floods
const LEVEL_ANGLE = 0.035f0      # rad (2°): counts as level
const MAX_SPLASHES = 3
const RIM_R = 14.0f0
const CALL_EVERY = (9.0, 5.0)    # s between two crowd calls, at the start and at the end
const LOOKS = ("Ooh! What's that by the shore?", "Everybody! Over here!", "A shiny thing! Come see!",
               "Did you see that fish?!", "Quick, look at this!", "Is that a boat?")
const WET = ("My feet are wet!", "SPLASH! Lumi!", "Brrr, the sea came in!", "Not again!")
push!(NG.BUSY_GOALS, :balance)

isdefined(Main, :BALANCE_PLOTS) || Core.eval(Main, :(const BALANCE_PLOTS = Dict{Symbol,Any}()))
const P = Main.BALANCE_PLOTS
const PLOTS_VERSION = 1

mutable struct Balance <: MiniGame
    jump::NG.JumpIn
    lumi::Int32
    friends::Vector{Int32}
    state::Symbol          # :ready, :playing, :over
    t::Float64
    t_state::Float64
    next_call::Float64
    tipped::Float64        # s the island has been tipped past SPLASH_ANGLE
    splashes::Int
    level_s::Float64       # s spent level
    flash::Float64
end
function Balance(game)
    j = NG.JumpIn(game)
    Balance(j, j.id, Int32[], :ready, 0.0, 0.0, 3.0, 0.0, 0, 0.0, 0.0)
end

NG.game_title(::Type{Balance}) = "Keep the island level (WASD)"
NG.game_description(::Type{Balance}) =
    "Your friends keep crowding to one shore and the whole island tips. You are heavy today: run to the other side and keep the shore dry for $(Int(SECONDS)) seconds."

const CURRENT_GAME = Ref{Any}(nothing)
ff() = CURRENT_GAME[].plugins["firefly_catch"].mod
ss() = CURRENT_GAME[].plugins["seesaw"].mod
seesaw() = Main.SEESAW[:sys]
flat(a, b) = hypot(a[1] - b[1], a[2] - b[2])

const START_TEXT = """Keep the island level
The island is a seesaw, and your friends keep running to the shore to look at things.
You are heavy today: stand on the other side and the island tips back.
Tip too far and the low shore floods. Three splashes and it's over.
Keep it dry for $(Int(SECONDS)) seconds.

W / S  walk      A / D  turn      Shift  run

Press W to start"""

function ensure_plots!(game)
    get(P, :version, 0) == PLOTS_VERSION && return
    ov = game.stage.overlay
    P[:hud] = textlabel!(ov, Point2f(0.5, 0.93); space = :relative, text = " ", fontsize = 24,
        text_color = RGBf(1, 0.95, 0.6), background_color = RGBAf(0.08, 0.09, 0.12, 0.75),
        strokewidth = 0, padding = 10, cornerradius = 8, visible = false)
    P[:card] = textlabel!(ov, Point2f(0.5, 0.62); space = :relative, text = " ", fontsize = 22, justification = :center,
        text_color = RGBf(1, 0.97, 0.85), background_color = RGBAf(0.07, 0.08, 0.13, 0.86),
        strokewidth = 0, padding = 22, cornerradius = 14, visible = false)
    P[:version] = PLOTS_VERSION
end
show_plots!(on::Bool) = foreach(k -> (P[k].visible[] = on), (:hud, :card))

"A spot on land near the rim in direction φ."
function rim(w, φ, r = RIM_R)
    for rr in (r, r - 2, r - 4, r - 6, 6.0f0)
        x = rr * cos(φ); y = rr * sin(φ)
        NG.on_land(w.island, x, y; margin = 0.6f0) && return NG.ground(w.island, (x, y))
    end
    return nothing
end

function send!(w, ids, φ)
    spot = rim(w, φ)
    spot === nothing && return
    for id in ids
        c = NG.creature(w, id)
        c === nothing && continue
        p = spot + Point3f(randn(w.rng) * 1.6f0, randn(w.rng) * 1.6f0, 0)
        q = NG.on_land(w.island, p[1], p[2]; margin = 0.4f0) ? NG.ground(w.island, (p[1], p[2])) : spot
        c.goal = NG.Goal(:balance, q, :idle, 600.0, 0.0, false, 0, true)
        TARGET[id] = q
    end
end
const TARGET = Dict{Int32,Point3f}()     # friend id => where it was sent last

"Other doings (fishing, pebble words, a dance) took a friend away from the game: back to its spot."
function keep_playing!(m::Balance, w)
    for id in m.friends
        c = NG.creature(w, id)
        (c === nothing || c.goal.kind in (:balance, :feel) || c.action === :sleep) && continue
        NG.leave_interactions!(w, c)
        q = get(TARGET, id, c.pos)
        c.goal = NG.Goal(:balance, q, :idle, 600.0, 0.0, false, 0, true)
    end
end

"Someone spots something: the friends run to one spot at the rim, or later in the game to two."
function call!(m::Balance, w)
    ids = shuffle_ids(w, m.friends)
    isempty(ids) && return
    me = NG.creature(w, m.lumi)
    # mostly the side away from Lumi (so it tips away and you have to cross), sometimes right next to you
    away = Float32(atan(-me.pos[2], -me.pos[1]))
    φ = rand(w.rng) < 0.7 ? away + Float32(randn(w.rng) * 0.6) : Float32(2π * rand(w.rng))
    if m.t > 25 && length(ids) >= 4 && rand(w.rng) < 0.5
        k = max(1, length(ids) ÷ 3)
        send!(w, ids[1:k], φ + Float32(pi) * (0.6f0 + 0.3f0 * rand(w.rng, Float32)))
        send!(w, ids[k+1:end], φ)
    else
        send!(w, ids, φ)
    end
    caller = NG.creature(w, ids[end])
    NG.say!(w, caller, rand(w.rng, LOOKS); duration = 2.4)
    NG.emit!(w, :balance_call; who = caller.name, t = round(m.t; digits = 1))
end
shuffle_ids(w, ids) = sort(ids; by = _ -> rand(w.rng))

function release!(w, id)
    c = NG.creature(w, id)
    c === nothing && return
    c.goal.kind === :balance && (c.goal = NG.Goal(:idle, c.pos, :idle, 1.0, w.t + 1.0, true, 0, false))
end

function reset!(m::Balance, game)
    w = game.world
    foreach(id -> release!(w, id), m.friends)
    me = NG.creature(w, m.lumi)
    p = NG.ground(w.island, (0.0f0, -3.0f0))
    NG.on_land(w.island, p[1], p[2]) && (me.pos = p)
    me.yaw = Float32(pi / 2) - NG.species_of(me).heading
    friends = [o for o in w.creatures if o.id != me.id && !o.controlled && o.action !== :sleep]
    length(friends) < 4 && (friends = [o for o in w.creatures if o.id != me.id && !o.controlled])
    m.friends = Int32[]
    for (i, o) in enumerate(friends)
        NG.leave_interactions!(w, o)
        a = Float32(2π * i / length(friends))
        q = NG.ground(w.island, (Float32(3 + 1.5 * (i % 2)) * cos(a), Float32(3 + 1.5 * (i % 2)) * sin(a) + 2.0f0))
        NG.on_land(w.island, q[1], q[2]) && (o.pos = q)
        o.action = :idle
        o.goal = NG.Goal(:balance, o.pos, :idle, 600.0, 0.0, false, 0, false)
        TARGET[o.id] = o.pos
        push!(m.friends, o.id)
    end
    empty!(ss().WEIGHTS)
    ss().WEIGHTS[m.lumi] = HEAVY
    s = seesaw()
    s.tilt = Vec2f(0); s.spin = Vec2f(0)
    m.state = :ready; m.t = 0.0; m.t_state = 0.0; m.next_call = 2.5; m.tipped = 0.0; m.splashes = 0
    m.level_s = 0.0; m.flash = 0.0
    best = get!(() -> load_best(game), P, :best)
    Makie.update!(P[:card]; text = best > 0 ? START_TEXT * @sprintf("\nYour best: %.0f s level", best) : START_TEXT)
    P[:card].visible[] = true
end

load_best(game) = (f = joinpath(game.paths.state, "bests.json"); isfile(f) ? Float64(get(NG.read_json(f), "balance", 0.0)) : 0.0)
function save_best!(game, v)
    game.dash === nothing && return
    game.tests !== nothing && NG.running(game.tests) && return
    f = joinpath(game.paths.state, "bests.json")
    d = isfile(f) ? NG.read_json(f) : Dict{String,Any}()
    d["balance"] = v
    NG.write_json(f, d)
end

"The chase camera on where Lumi is drawn (the tipped island), so Lumi stays in the middle of the view."
function camera!(m::Balance, game, dt; snap = false)
    c = NG.creature(game.world, m.lumi)
    p0 = c.pos
    c.pos = Base.invokelatest(ss().drawn, p0)
    Base.invokelatest(m.state === :ready ? ff().start_view! : ff().chase_camera!, game, c, dt; snap)
    c.pos = p0
end

function NG.start!(m::Balance, game)
    CURRENT_GAME[] = game
    NG.start!(m.jump, game)
    ensure_plots!(game)
    show_plots!(true)
    reset!(m, game)
    camera!(m, game, 0.0; snap = true)
end

function NG.input!(m::Balance, game, ev)
    ev.action == Makie.Keyboard.press || return
    if ev.key == Makie.Keyboard.r
        reset!(m, game)
    elseif m.state === :ready && ev.key in (Makie.Keyboard.w, Makie.Keyboard.s, Makie.Keyboard.a, Makie.Keyboard.d, Makie.Keyboard.up)
        m.state = :playing; m.t_state = 0.0
        P[:card].visible[] = false
    end
end

function splash!(m::Balance, w, low)
    m.splashes += 1
    m.flash = 1.5
    m.tipped = -1.5                      # a moment's grace after the sea came in
    wet = [NG.creature(w, id) for id in m.friends]
    wet = [o for o in wet if o !== nothing && o.pos[1] * low[1] + o.pos[2] * low[2] > 4]
    for (i, o) in enumerate(wet)
        NG.feel!(w, o, :scared; seconds = 1.4)
        i <= 2 && NG.say!(w, o, rand(w.rng, WET); duration = 2.0)
    end
    NG.emit!(w, :balance_splash; n = m.splashes, wet = length(wet))
end

function NG.step!(m::Balance, game, dt)
    w = game.world
    c = NG.creature(w, m.lumi)
    m.state === :playing ? NG.step!(m.jump, game, dt) : (c.action = m.state === :over && m.splashes < MAX_SPLASHES ? :dance : :idle)
    m.t_state += dt
    camera!(m, game, dt)
    m.flash = max(0.0, m.flash - dt)
    s = seesaw()
    a = Float32(hypot(s.tilt[1], s.tilt[2]))
    low = a > 0 ? s.tilt / a : Vec2f(1, 0)
    if m.state === :playing
        m.t += dt
        keep_playing!(m, w)
        a < LEVEL_ANGLE && (m.level_s += dt)
        if m.t >= m.next_call
            call!(m, w)
            u = clamp(m.t / SECONDS, 0, 1)
            gap = CALL_EVERY[1] + (CALL_EVERY[2] - CALL_EVERY[1]) * u
            m.next_call = m.t + gap * (0.8 + 0.4 * rand(w.rng))
        end
        m.tipped = a > SPLASH_ANGLE ? m.tipped + dt : max(min(m.tipped, 0.0), m.tipped - dt)
        m.tipped >= SPLASH_HOLD && splash!(m, w, low)
        if m.splashes >= MAX_SPLASHES || m.t >= SECONDS
            m.state = :over; m.t_state = 0.0
            won = m.splashes < MAX_SPLASHES
            best = get!(() -> load_best(game), P, :best)
            newbest = won && m.level_s > best
            newbest && (P[:best] = m.level_s; save_best!(game, m.level_s))
            for id in m.friends
                o = NG.creature(w, id)
                o === nothing && continue
                o.goal = NG.Goal(:balance, o.pos, won ? :jump : :idle, 600.0, 0.0, false, 0, false)
                won || NG.feel!(w, o, :pout; seconds = 2.0)
            end
            won && NG.say!(w, NG.creature(w, m.friends[1]), "You kept our feet dry!"; duration = 3.0)
            NG.emit!(w, :balance_over; won, splashes = m.splashes, level = round(m.level_s; digits = 1))
            Makie.update!(P[:card]; text = won ?
                @sprintf("Dry feet for %d seconds!\nThe island was level for %.0f s%s.\n\nPress R to play again",
                         Int(SECONDS), m.level_s, newbest ? " (a new best)" : @sprintf(" (best %.0f s)", best)) :
                @sprintf("SPLASH! The sea came in three times.\nYou held it for %.0f seconds.\nStand on the side away from the crowd!\n\nPress R to play again", m.t))
            P[:card].visible[] = true
        end
    end
    deg = rad2deg(a)
    msg = if m.state === :ready
        "Press W to start"
    elseif m.state === :over
        m.splashes < MAX_SPLASHES ? "Level island!" : "Splash!"
    else
        high = Point3f(-low[1] * RIM_R, -low[2] * RIM_R, 0)
        go = a < LEVEL_ANGLE ? "level" : "high side " * Base.invokelatest(ff().direction_word, c, high)
        warn = m.tipped > 0.3 ? "  TIPPING!" : ""
        @sprintf("%2.0f s left    tilt %3.1f°  %s%s    splashes %d/%d", max(0, SECONDS - m.t), deg, go, warn, m.splashes, MAX_SPLASHES)
    end
    Makie.update!(P[:hud]; text = msg)
    (m.state !== :ready) == P[:hud].visible[] || (P[:hud].visible[] = m.state !== :ready)
    P[:hud].text_color[] = m.flash > 0 ? RGBf(0.5, 0.8, 1) : m.tipped > 0.3 ? RGBf(1, 0.55, 0.45) : RGBf(1, 0.95, 0.6)
end

NG.finished(m::Balance) = m.state === :over && m.t_state > 60

function NG.stop!(m::Balance, game)
    w = game.world
    foreach(id -> release!(w, id), m.friends)
    haskey(game.plugins, "seesaw") && empty!(game.plugins["seesaw"].mod.WEIGHTS)
    get(P, :version, 0) == PLOTS_VERSION && show_plots!(false)
    NG.stop!(m.jump, game)
    game.rig.mode = :follow
end

register!(Balance)
