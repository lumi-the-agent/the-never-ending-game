# ── Playing: mini games and jumping into the game ───────────────────────────

"The built in way to play: steer Lumi with WASD (shift runs), E waves, space jumps."
mutable struct JumpIn <: MiniGame
    id::Int32
end
JumpIn(g::Game) = JumpIn(creature(g.world, "Lumi").id)
game_title(::Type{JumpIn}) = "Jump in (WASD)"
game_description(::Type{JumpIn}) = "Be Lumi (WASD): E twice for a parade; X sneeze, H hiccup, G fly, C sing, P paint, T storm, B bubble, J swallow, U throw up into orbit, K tip my day, L stomp, V shadow, Z rewind."

"Footprint radius (at scale 1) of the props creatures cannot walk through; the Separation plugin fills it."
const SOLID_FOOTPRINT = Dict{Symbol,Float32}()

"How far `c` can walk along `yaw` (up to 4 m) before water or a solid prop stops it."
function free_run(w::World, c::Creature, yaw::Real)
    r = body_radius(species_of(c))
    for d in 0.25f0:0.25f0:4f0
        x, y = c.pos[1] + d * cos(yaw), c.pos[2] + d * sin(yaw)
        on_land(w.island, x, y; margin = 0.1f0) || walkway_height(x, y) !== nothing || return d - 0.25f0
        any(p -> haskey(SOLID_FOOTPRINT, p.kind) && hypot(p.pos[1] - x, p.pos[2] - y) < SOLID_FOOTPRINT[p.kind] * p.scale + r, w.props) &&
            return d - 0.25f0
        # a sleeper next to Lumi's bed: Separation pushed Lumi back and W did nothing (s31 dawn suite)
        any(o -> o !== c && hypot(o.pos[1] - x, o.pos[2] - y) < body_radius(species_of(o)) + r, w.creatures) &&
            return d - 0.25f0
    end
    return 4f0
end

"A creature the player takes over (Lumi asleep in its nook faces a bush) turns to open ground, so W walks at once."
function face_open!(w::World, c::Creature)
    free_run(w, c, c.yaw) >= 1.5f0 && return c
    yaws = [c.yaw + Float32(k * pi / 12) for k in 1:23]
    c.yaw = yaws[argmax([free_run(w, c, a) for a in yaws])]
    return c
end

"""
`c` leaves the chats, boops and dance-offs it is in: the partner goes back to its own life.
A chat kept setting a player's Lumi to :talk every frame, so E (wave) never reached the game.
"""
function leave_interactions!(w::World, c::Creature)
    filter!(w.interactions) do it
        (it.a == c.id || it.b == c.id) || return true
        other = creature(w, it.a == c.id ? it.b : it.a)
        other.controlled || choose_goal!(other, w)
        return false
    end
    c.action = :idle
    return c
end

function start!(m::JumpIn, g::Game)
    c = creature(g.world, m.id)
    leave_interactions!(g.world, c)
    c.controlled = true
    c.goal = Goal()
    face_open!(g.world, c)
    step_into_view!(g.world, c)
    g.rig.mode = :follow
    g.rig.subject = m.id
end

"""
At the start of a jump-in, a Lumi standing in a nook had a bush between it and the chase camera (2 of 5 starts,
s84; perfectionist s82): if the view from behind is blocked, it steps out to the nearest spot within 3.5 m where
it is clear (a cut at the start of play, like the camera's own).
"""
function step_into_view!(w::World, c::Creature)
    a = c.yaw + species_of(c).heading
    fwd = Point3f(cos(a), sin(a), 0)
    clear(p) = obstruction(w, p - 3.2f0 * fwd + Point3f(0, 0, 1.6f0), p + Point3f(0, 0, 0.6f0)) < 0.3f0
    clear(c.pos) && return
    for r in (1.5f0, 2.5f0, 3.5f0), k in 0:7
        b = 2f0 * Float32(pi) * k / 8
        q = (c.pos[1] + r * cos(b), c.pos[2] + r * sin(b))
        on_land(w.island, q[1], q[2]; margin = 0.3) || continue
        p = ground(w.island, q)
        if clear(p)
            c.pos = p
            return
        end
    end
end

"""
Creatures a plugin moves by itself for a moment (Lumi's flight on G): creature id => until (`w.t`). The jump-in step
leaves a held creature alone, so the plugin's pose (`:fly`) is what the player sees (s105, review #516).
"""
const HELD = Dict{Int,Float64}()

function step!(m::JumpIn, g::Game, dt)
    c = creature(g.world, m.id)
    get(HELD, Int(c.id), -Inf) > g.world.t && return
    k = g.keys_down
    K = Makie.Keyboard
    fwd = (K.w in k) - (K.s in k)
    turn = (K.a in k) - (K.d in k)
    c.yaw += Float32(2.2 * turn * dt)
    run = K.left_shift in k
    if fwd != 0
        move_heading!(c, g.world, c.yaw + (fwd < 0 ? Float32(pi) : 0.0f0), dt; run)
    else
        c.action = K.space in k ? :jump : K.e in k ? :wave : :idle
        c.extra = action_extra(Val(c.action), c, g.world)
    end
end

function stop!(m::JumpIn, g::Game)
    c = creature(g.world, m.id)
    c.controlled = false
    g.rig.subject = 0
end

"All mini game types the plugins registered, plus jumping in."
minigame_types(g::Game) = vcat(DataType[JumpIn], [T for p in values(g.plugins) for T in p.minigames])

function start_minigame!(g::Game, T::Type{<:MiniGame})
    g.minigame === nothing || stop_minigame!(g)
    m = try
        mg = Base.invokelatest(T, g)
        Base.invokelatest(start!, mg, g)
        mg
    catch e
        e isa InterruptException && rethrow()
        report_problem!(g, "Mini game $(game_title(T)) does not start", sprint(showerror, e, catch_backtrace()))
        nothing
    end
    m === nothing && return
    g.minigame = m
    log_event!(g.log, g.world.t, :play_start; game = game_title(T))
    g.dash === nothing || (g.dash.play_button.label[] = "Stop")
end

function start_selected!(g::Game)
    sel = g.dash.play_menu.selection[]
    types = minigame_types(g)
    i = findfirst(T -> Base.invokelatest(game_title, T) == sel, types)
    start_minigame!(g, i === nothing ? JumpIn : types[i])
end

function stop_minigame!(g::Game)
    m = g.minigame
    m === nothing && return
    g.minigame = nothing
    try
        Base.invokelatest(stop!, m, g)
    catch e
        e isa InterruptException && rethrow()
        report_problem!(g, "Mini game $(game_title(typeof(m))) failed in stop!", sprint(showerror, e, catch_backtrace()))
    end
    log_event!(g.log, g.world.t, :play_stop; game = game_title(typeof(m)))
    g.dash === nothing || (g.dash.play_button.label[] = "Play")
end

"""
A mini game in the human's game ends when nobody touched the dashboard for five minutes: the
player left (s48: a Jump in left running kept Lumi under the player's control all session, so
Lumi could not show its work). The sandbox keeps what the agent and the tests start.
"""
end_abandoned_play!(::Val{:sandbox}, g::Game) = nothing
end_abandoned_play!(::Val{:live}, g::Game) = time() - g.human_input < 300 || stop_minigame!(g)

function step_minigame!(g::Game, dt)
    m = g.minigame
    try
        Base.invokelatest(step!, m, g, dt)
        Base.invokelatest(finished, m) && stop_minigame!(g)
    catch e
        e isa InterruptException && rethrow()
        g.minigame = nothing
        report_problem!(g, "Mini game $(game_title(typeof(m))) failed and was stopped", sprint(showerror, e, catch_backtrace()))
        g.dash === nothing || (g.dash.play_button.label[] = "Play")
    end
end

"Keys go to the game when the text box does not have them."
function key_to_game!(g::Game, ev::Makie.KeyEvent)
    g.dash !== nothing && g.dash.tell_box.focused[] && (empty!(g.keys_down); return)
    ev.action == Makie.Keyboard.press && push!(g.keys_down, ev.key)
    ev.action == Makie.Keyboard.release && delete!(g.keys_down, ev.key)
    m = g.minigame
    m === nothing && return
    try
        Base.invokelatest(input!, m, g, ev)
    catch e
        e isa InterruptException && rethrow()
        stop_minigame!(g)
        report_problem!(g, "Mini game $(game_title(typeof(m))) failed in input!", sprint(showerror, e, catch_backtrace()))
    end
end
