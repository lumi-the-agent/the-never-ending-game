# ── The running game ────────────────────────────────────────────────────────
#
# `run_game()` is the process the host keeps alive in the jail. Each frame:
# live commands (from agents, testers and reviewers), plugin reloads, the
# world step, every plugin system, actors, the mini game, the stage sync, the
# dashboard. RayMakie draws the dashboard on this machine (its window renders
# itself; offscreen it renders for screenshots), browsers draw the same figure
# with WGLMakie (web.jl).
# Every part is timed; the numbers are in `live_status()` and
# `world/state/perf.json`, and a slow game turns into a perf todo.

"Rolling frame time samples (ms) per part of the frame."
struct FrameClock
    parts::Dict{String,Vector{Float64}}
end
FrameClock() = FrameClock(Dict{String,Vector{Float64}}())

const CLOCK_SAMPLES = 300

function tick!(c::FrameClock, part::AbstractString, ms::Real)
    v = get!(() -> Float64[], c.parts, part)
    push!(v, Float64(ms))
    length(v) > CLOCK_SAMPLES && popfirst!(v)
    return ms
end

pctl(v::Vector{Float64}, q::Real) = isempty(v) ? 0.0 : sort(v)[clamp(ceil(Int, q * length(v)), 1, length(v))]

clock_summary(c::FrameClock) =
    Dict(k => Dict("median_ms" => round(pctl(v, 0.5); digits = 2), "p95_ms" => round(pctl(v, 0.95); digits = 2))
         for (k, v) in c.parts)

"A system a plugin registered, with its cost."
mutable struct SystemSlot
    plugin::String
    system::System
    started::Bool
end

system_label(s::SystemSlot) = "system:" * s.plugin * "." * string(nameof(typeof(s.system)))

mutable struct Game
    paths::GamePaths
    world::World
    log::EventLog
    timing::TimingStats
    plugins::Dict{String,Plugin}
    systems::Vector{SystemSlot}
    actor_types::Dict{String,DataType}
    actor_views::Dict{DataType,Any}
    minigame::Union{Nothing,MiniGame}
    controlled::Int32                 # creature driven by the player (0: none)
    stage::Union{Nothing,Stage}
    rig::CameraRig
    dash::Any                         # Dashboard (dashboard.jl), or nothing headless
    screen::Any                       # the RayMakie screen of the dashboard
    live::Any                         # LiveServer (live.jl)
    web::Any                          # WebView (web.jl): the dashboard for browsers
    fps::Int
    frame::Int
    clock::FrameClock
    running::Bool
    last_plugin_check::Float64
    last_snapshot::Float64
    last_frame_record::Float64
    last_panels::Float64
    last_perf::Float64
    slow_minutes::Int
    keys_down::Set{Makie.Keyboard.Button}
    actions::Vector{Function}         # queued by dashboard callbacks, run by the game loop (`later!`)
    tests::Any                        # the current or last UI test run (uitests.jl), or nothing
    driven::Int                       # `interact!` calls in progress: input now comes from a test, not the human
    human_input::Float64              # time() of the human's last input (window or browser), see `human_busy`
    revise::Function                  # applies engine edits (`Revise.revise` from the host), see `follow_edits!`
end

todo_path(g::Game) = todos_file(g.paths)
latest_world(p::GamePaths) = joinpath(p.state, "world.json")

"""
Load the world (latest snapshot or a new one), the plugins, and revive saved
actors. `instance` (publish.jl): `:sandbox`, the plugins the agent edits (a
copy in a session, the worker's stills and clips), or `:live`, the human's.
"""
function Game(root::AbstractString = game_root(); instance::Symbol = :sandbox, fps::Int = 30, quiet::Bool = false)
    p = GamePaths(root, instance)
    w = isfile(latest_world(p)) ? load_snapshot(latest_world(p)) : new_world()
    g = Game(p, w, EventLog(p), TimingStats(joinpath(p.state, "timing.json")), Dict{String,Plugin}(), SystemSlot[],
             Dict{String,DataType}(), Dict{DataType,Any}(), nothing, 0, nothing, CameraRig(), nothing, nothing, nothing,
             nothing, fps, 0, FrameClock(), false, 0.0, time(), 0.0, 0.0, time(), 0, Set{Makie.Keyboard.Button}(),
             Function[], nothing, 0, 0.0, () -> nothing)
    g.actor_types[actor_kind(AssetActor)] = AssetActor     # built in actor types
    revive_actors!(w, g.actor_types)
    quiet || log_event!(g.log, w.t, :game_start; creatures = length(w.creatures), actors = length(w.dormant))   # quiet: a worker's copy (traced stills)
    for f in plugin_files(p.plugins)
        load!(g, f)
    end
    return g
end

"The game root: `NEVERENDING_ROOT` in the jail, else the folder this package is checked out in."
game_root() = get(ENV, "NEVERENDING_ROOT", default_root())

# ── problems the agent must hear about ──────────────────────────────────────

"Log an error from a plugin and make sure there is an open, urgent todo about it (`file_problem!`)."
function report_problem!(g::Game, title::AbstractString, detail::AbstractString; kind::Symbol = :fix)
    log_event!(g.log, g.world.t, :plugin_error; title, detail = first(detail, 4000))
    @error title detail = first(detail, 2000)
    file_problem!(todo_path(g), title, detail; kind)
    return nothing
end

"The beginnings of the titles `report_problem!` files for what plugin `p` registers."
problem_prefixes(p::Plugin) =
    ["Plugin $(p.name) does not load"; "system:$(p.name).";
     "The dashboard panels did not rebuild after loading plugin $(p.name)";
     ["Actor $(actor_kind(T)) " for T in p.actor_types]; ["Actors $(actor_kind(T)) " for T in p.actor_types];
     ["Mini game $(Base.invokelatest(game_title, T)) " for T in p.minigames];
     ["Panel $(Base.invokelatest(panel_title, x)) " for x in p.panels]]

# ── plugins ─────────────────────────────────────────────────────────────────

"Load (or reload) plugin `file` of the game's plugin folder and swap its registrations in."
load!(g::Game, file::AbstractString) = install!(g, load_plugin(first(splitext(file)), joinpath(g.paths.plugins, file)))

"Swap a loaded plugin's registrations in (a broken one is reported, and its old version taken out)."
function install!(g::Game, p::Plugin)
    name = p.name
    old = get(g.plugins, name, nothing)
    if !isempty(p.error)
        g.plugins[name] = p
        old === nothing || unload!(g, old)
        report_problem!(g, "Plugin $(name) does not load", p.error)
        return p
    end
    old === nothing || unload!(g, old)
    g.plugins[name] = p
    close_problems!(todo_path(g), problem_prefixes(p), "plugin $(name) loaded cleanly")
    for s in p.systems
        push!(g.systems, SystemSlot(name, s, false))
    end
    for T in p.actor_types
        g.actor_types[actor_kind(T)] = T
    end
    for (kind, err) in revive_actors!(g.world, g.actor_types)
        report_problem!(g, "Actors $(kind) do not restore", err)
    end
    log_event!(g.log, g.world.t, :plugin_load; plugin = name, systems = length(p.systems),
               actors = length(p.actor_types), minigames = length(p.minigames), panels = length(p.panels),
               ms = round(p.load_ms; digits = 1))
    if g.dash !== nothing
        # rebuilding the panels after a reload killed the game (s34, s35): clear_layout! passed a
        # GridLayout to remove_from_gridlayout! (fixed s36). A future rebuild failure files a todo
        try
            dashboard_plugins_changed!(g)
        catch e
            e isa InterruptException && rethrow()
            report_problem!(g, "The dashboard panels did not rebuild after loading plugin $(name)",
                            sprint(showerror, e, catch_backtrace()))
        end
    end
    return p
end

"Take a plugin's registrations out of the running game (its actors sleep until it is back)."
function unload!(g::Game, p::Plugin)
    for slot in filter(s -> s.plugin == p.name, g.systems)
        slot.started && guarded(g, "stop", slot) do
            stop!(slot.system, g)
        end
    end
    filter!(s -> s.plugin != p.name, g.systems)
    for T in p.actor_types
        suspend_actors!(g.world, T)
        delete!(g.actor_types, actor_kind(T))
        view = pop!(g.actor_views, T, nothing)
        view === nothing || g.stage === nothing || delete!(g.stage.scene, view)
    end
    if g.minigame !== nothing && typeof(g.minigame) in p.minigames
        stop_minigame!(g)
    end
    return p
end

function check_plugins!(g::Game)
    files = plugin_files(g.paths.plugins)
    for f in files
        name = first(splitext(f))
        p = get(g.plugins, name, nothing)
        (p === nothing || mtime(joinpath(g.paths.plugins, f)) != p.mtime) &&
            !reload_waits(Val(g.paths.instance), g, name) && load!(g, f)
    end
    for name in collect(keys(g.plugins))
        name * ".jl" in files && continue
        unload!(g, g.plugins[name])
        delete!(g.plugins, name)
        log_event!(g.log, g.world.t, :plugin_removed; plugin = name)
    end
end

"""
Run plugin code `f`. A throw switches the system off and is reported; the frame
goes on. (`what` names the call for the report.)
"""
function guarded(f, g::Game, what::AbstractString, slot::SystemSlot)
    try
        Base.invokelatest(f)
        return true
    catch e
        e isa InterruptException && rethrow()
        filter!(s -> s !== slot, g.systems)
        report_problem!(g, "$(system_label(slot)) failed in $(what) and was switched off",
                        sprint(showerror, e, catch_backtrace()))
        return false
    end
end

# ── work from the dashboard ─────────────────────────────────────────────────

"""
    later!(game, f)

Run `f()` at the start of the next frame, from the game loop. Dashboard
callbacks do only this: they fire inside the window's render task, whose world
is older than the plugins and every Revise edit, and an error there would end
the window's render loop.
"""
later!(g::Game, f::Function) = (push!(g.actions, f); nothing)

function run_actions!(g::Game)
    isempty(g.actions) && return
    todo = copy(g.actions)
    empty!(g.actions)
    for f in todo
        try
            Base.invokelatest(f)
        catch e
            e isa InterruptException && rethrow()
            report_problem!(g, "A dashboard action failed: " * first(sprint(showerror, e), 100),
                            sprint(showerror, e, catch_backtrace()))
        end
    end
end

# ── one frame ───────────────────────────────────────────────────────────────

timed_ms(f) = (t0 = time_ns(); f(); (time_ns() - t0) / 1e6)

function step_systems!(g::Game, dt::Real)
    for slot in copy(g.systems)
        if !slot.started
            slot.started = guarded(() -> start!(slot.system, g), g, "start!", slot)
            slot.started || continue
        end
        ms = timed_ms(() -> guarded(() -> step!(slot.system, g, dt), g, "step!", slot))
        tick!(g.clock, system_label(slot), ms)
    end
end

function step_actors!(g::Game, dt::Real)
    for a in copy(g.world.actors)
        try
            Base.invokelatest(step!, a, g, dt)
        catch e
            e isa InterruptException && rethrow()
            T = typeof(a)
            n = suspend_actors!(g.world, T)
            report_problem!(g, "Actor $(actor_kind(T)) failed in step! ($n put to sleep)", sprint(showerror, e, catch_backtrace()))
        end
    end
end

step!(::Actor, game, dt) = nothing

function sync_actors!(g::Game)
    g.stage === nothing && return
    groups = Dict{DataType,Vector{Actor}}()
    for a in g.world.actors
        push!(get!(() -> Actor[], groups, typeof(a)), a)
    end
    for (T, actors) in groups
        view = get!(() -> Base.invokelatest(visual, T, g.stage.scene), g.actor_views, T)
        Base.invokelatest(sync_visual!, view, [a for a in actors], g)
    end
    for (T, view) in g.actor_views
        haskey(groups, T) || Base.invokelatest(sync_visual!, view, Actor[], g)
    end
end

function drain_world_events!(g::Game)
    for (kind, data) in g.world.events
        log_event!(g.log, g.world.t, kind; (Symbol(k) => v for (k, v) in data)...)
    end
    empty!(g.world.events)
end

function save_world!(g::Game; reason::AbstractString = "periodic")
    save_snapshot(latest_world(g.paths), g.world)
    if reason != "periodic" || time() - g.last_snapshot > 1800
        save_snapshot(joinpath(g.paths.snapshots, Dates.format(Dates.now(), "yyyymmdd-HHMMSS") * ".json"), g.world)
    end
    g.last_snapshot = time()
    log_event!(g.log, g.world.t, :snapshot; reason)
end

"Once a minute: frame statistics to `state/perf.json`; three slow minutes in a row become a perf todo."
function check_perf!(g::Game)
    s = clock_summary(g.clock)
    write_json(joinpath(g.paths.state, "perf.json"), Dict("fps_target" => g.fps, "parts" => s, "time" => string(Dates.now())))
    total = get(g.clock.parts, "frame", Float64[])
    budget = 1000 / g.fps
    g.slow_minutes = pctl(total, 0.95) > 1.2budget ? g.slow_minutes + 1 : 0
    if g.slow_minutes >= 3
        worst = sort!([(pctl(v, 0.5), k) for (k, v) in g.clock.parts if k != "frame"]; rev = true)
        lines = join([@sprintf("%-40s %.1f ms", k, ms) for (ms, k) in first(worst, 6)], "\n")
        report_problem!(g, @sprintf("Frames are slow: p95 %.0f ms (budget %.0f ms)", pctl(total, 0.95), budget),
                        "Median cost per part of the frame:\n" * lines; kind = :perf)
        g.slow_minutes = 0
    end
end

"""
    frame!(g, dt; render)

One frame of the live game. `render`: produce a picture (someone watches, or
a screenshot was asked for).
"""
function frame!(g::Game, dt::Real)
    run_actions!(g)
    w = g.world
    tick!(g.clock, "sim", timed_ms(() -> step!(w, dt)))
    tick!(g.clock, "actors", timed_ms(() -> step_actors!(g, dt)))
    step_systems!(g, dt)
    g.minigame === nothing || end_abandoned_play!(Val(g.paths.instance), g)
    if g.minigame !== nothing
        tick!(g.clock, "minigame", timed_ms(() -> step_minigame!(g, dt)))
    end
    drain_world_events!(g)
    if w.t - g.last_frame_record >= FRAME_DT
        log_frame!(g.log, frame_record(w))
        g.last_frame_record = w.t
    end
    if g.stage !== nothing
        tick!(g.clock, "sync", timed_ms() do
            sync!(g.stage, w)
            sync_actors!(g)
            update_camera!(g.rig, w, g.stage.scene, dt)
        end)
    end
    if g.dash !== nothing && time() - g.last_panels > 0.5
        tick!(g.clock, "panels", timed_ms(() -> update_dashboard!(g)))
        g.last_panels = time()
    end
    return g
end

"""
    run_game(; root, instance, fps, width, height, headless, window, web_port, web_url, revise)

A running game, until a `shutdown` arrives on its live socket: `instance`
`:live` is the human's, `:sandbox` the agent's (publish.jl). Unless
`headless` it has its dashboard: RayMakie on this machine (a window when
`window`, else offscreen for screenshots and tests), WGLMakie for browsers at
`web_url` (served on `web_port` inside the jail, see web.jl). `revise` (the
host passes `Revise.revise`) applies engine edits: the sandbox calls it once a
second, the human's game when something is published; the frame is called in
the latest world.
"""
function run_game(; root::AbstractString = game_root(), instance::Symbol = :live, fps::Int = 30, width::Int = 1280,
                  height::Int = 720, headless::Bool = false, window::Bool = false, web_port::Int = 8790,
                  web_url::AbstractString = "", revise::Function = () -> nothing)
    prepare_instance!(Val(instance), GamePaths(root, instance))
    g = Game(root; instance, fps)
    g.revise = revise
    if !headless
        # latest world: the plugins loaded in `Game` (their mini game titles, panels) are newer than this call
        Base.invokelatest(build_dashboard!, g, (width, height); window)
        window || Makie.colorbuffer(g.screen)    # compile the render path now, not on the first screenshot
        fake_interaction()    # now: loaded later, it is too new for the code that loads it (`ui_pos` in a live eval)
    end
    g.live = start_live!(g)
    headless || (g.web = serve_web!(g; port = web_port, url = web_url))
    g.running = true
    dt = 1 / fps
    next = time()
    failures = 0
    try
        while g.running
            # latest world, as the frame: live commands edited since the start (Revise) apply at once
            Base.invokelatest(handle_live_commands!, g)
            if time() - g.last_plugin_check > 1
                # the host keeps the output in a log file: flush so a crash leaves its last words there
                flush(stdout); flush(stderr)
                follow_edits!(Val(instance), g)
                Base.invokelatest(check_plugins!, g)
                # new plots (plugins, actors) get their WGLMakie colours
                g.web === nothing || Base.invokelatest(fill_raster_colors!, g.dash.fig.scene, g.web.colored)
                g.last_plugin_check = time()
            end
            # "frame" is the player's frame: live commands (screenshots, evals) and plugin
            # checks are timed apart (`live:*`), so a screenshot is not a slow frame
            t0 = time_ns()
            try
                Base.invokelatest(frame!, g, dt)
                failures = 0
            catch e
                e isa InterruptException && rethrow()
                # an engine bug: report it and keep the world alive, so a fix (Revise) can land
                # live; only a frame that keeps failing ends the process
                failures += 1
                failures == 1 && report_problem!(g, "A frame failed: " * first(sprint(showerror, e), 120),
                                                 sprint(showerror, e, catch_backtrace()))
                failures >= 100 && rethrow()
            end
            tick!(g.clock, "frame", (time_ns() - t0) / 1e6)
            g.frame += 1
            tick_tests!(g)
            time() - g.last_snapshot > 300 && save_world!(g)
            if time() - g.last_perf > 60
                check_perf!(g)
                g.last_perf = time()
            end
            # pace to the target rate; when behind, do not try to catch up
            next = max(next + dt, time() - dt)
            sleep(max(0.001, next - time()))
        end
    catch e
        # record why the loop ended, then let it end
        log_event!(g.log, g.world.t, :game_crash; error = first(sprint(showerror, e), 2000))
        rethrow()
    finally
        save_world!(g; reason = "shutdown")
        log_event!(g.log, g.world.t, :game_stop; frames = g.frame)
        close(g.log)
        g.live === nothing || stop_live!(g.live)
        g.web === nothing || stop_web!(g.web)
    end
    return g
end

"""
    release!(game)

Let a finished game go (a film's, in the worker or a session): what its plugins keep in their own
globals is emptied. A plugin loads into a new module for every game, and that module lives as long as
the process does (its types are never freed); a plugin that kept the game in a global
(`nightshots`' `CURRENT`, `balance`'s `CURRENT_GAME`) kept the whole game, its scene and GPU buffers
with it: about 5 GB per film, until the worker was killed at 51 GB (Nov 26). What a plugin shares
on purpose, a container that is also a global of `Main` or of a package (`const S = Main.SEESAW`,
an alias of an engine list), is left alone.
"""
function release!(g::Game)
    shared = Base.IdSet{Any}()
    for m in (Main, Base.loaded_modules_array()...), n in names(m; all = true)
        isdefined(m, n) && push!(shared, getglobal(m, n))
    end
    for p in values(g.plugins)
        p.mod === nothing && continue
        for n in names(p.mod; all = true)
            isdefined(p.mod, n) || continue
            v = getglobal(p.mod, n)
            v in shared || release_value!(v)
        end
    end
    return nothing
end

"Empty what a finished plugin module holds: a `Ref` that may hold `nothing`, a dict, a set, a vector of references."
release_value!(v) = nothing
release_value!(r::Base.RefValue{T}) where {T} = (Nothing <: T && (r[] = nothing); nothing)
release_value!(d::AbstractDict) = (empty!(d); nothing)
release_value!(s::AbstractSet) = (empty!(s); nothing)
release_value!(v::Vector{T}) where {T} = (isbitstype(T) || empty!(v); nothing)
