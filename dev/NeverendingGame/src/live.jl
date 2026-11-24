# ── The live socket: agents talking to the running game ─────────────────────
#
# `world/run/game.sock`, one JSON request per line, one JSON answer per line:
#
#   {"id": 1, "cmd": "status"}
#   {"id": 2, "cmd": "eval", "code": "length(game.world.creatures)"}
#   {"id": 3, "cmd": "screenshot", "path": "/…/shot.png"}
#   {"id": 4, "cmd": "reload"}                  (check plugins now)
#   {"id": 5, "cmd": "shutdown"}
#
# Requests are executed by the game loop between two frames, so they see a
# consistent world and may change it. `eval` runs `code` as the body of a
# function of `game`; it costs frame time, which shows up in the stats.
#
# Client side (any Julia session in the jail): `live_status()`,
# `live_eval(code)`, `live_screenshot(path)`, `live_reload()`.

struct LiveRequest
    msg::Dict{String,Any}
    reply::Channel{Dict{String,Any}}
end

mutable struct LiveServer
    path::String
    server::Sockets.PipeServer
    requests::Channel{LiveRequest}
    task::Task
    mod::Module              # where `eval` code runs, with the game's names in scope
end

function live_module()
    m = Module(:Live)
    Core.eval(m, PLUGIN_IMPORTS)
    return m
end

live_socket(p::GamePaths) = joinpath(p.run, "game.sock")

function start_live!(g::Game)
    path = live_socket(g.paths)
    mkpath(dirname(path))
    ispath(path) && rm(path)
    server = Sockets.listen(path)
    requests = Channel{LiveRequest}(64)
    task = errormonitor(@async while isopen(server)
        conn = try
            accept(server)
        catch e
            isopen(server) || break   # closed by stop_live!
            rethrow()
        end
        errormonitor(@async Base.invokelatest(serve_live, conn, requests))
    end)
    return LiveServer(path, server, requests, task, live_module())
end

function serve_live(conn::IO, requests::Channel{LiveRequest})
    try
        while isopen(conn) && !eof(conn)
            line = readline(conn)
            isempty(strip(line)) && continue
            msg = JSON.parse(line; dicttype = Dict{String,Any})
            req = LiveRequest(msg, Channel{Dict{String,Any}}(1))
            put!(requests, req)
            println(conn, JSON.json(take!(req.reply)))
        end
    catch e
        # the client went away mid answer
        e isa Base.IOError || e isa EOFError || rethrow()
    finally
        close(conn)
    end
end

function stop_live!(l::LiveServer)
    close(l.server)
    ispath(l.path) && rm(l.path)
end

"Answer every waiting request (called by the game loop between frames)."
function handle_live_commands!(g::Game)
    l = g.live
    l === nothing && return
    while isready(l.requests)
        req = take!(l.requests)
        cmd = string(get(req.msg, "cmd", "?"))
        t0 = time_ns()
        answer = try
            live_command(g, Val(Symbol(cmd)), req.msg)
        catch e
            e isa InterruptException && rethrow()
            # a failing command (a screenshot the tracer refuses) is the client's answer, not the game's end
            err = sprint(showerror, e, catch_backtrace())
            report_problem!(g, "Live command $(cmd) failed", err)
            Dict{String,Any}("ok" => false, "error" => first(err, 20_000))
        end
        tick!(g.clock, "live:" * cmd, (time_ns() - t0) / 1e6)
        answer["id"] = get(req.msg, "id", 0)
        put!(req.reply, answer)
    end
end

live_command(g::Game, ::Val{C}, msg) where {C} = Dict{String,Any}("ok" => false, "error" => "unknown command $(C)")

function live_command(g::Game, ::Val{:status}, msg)
    return Dict{String,Any}("ok" => true, "status" => game_status(g))
end

function game_status(g::Game)
    w = g.world
    return Dict{String,Any}(
        "game" => string(g.paths.instance), "sim_time" => round(w.t; digits = 1), "daytime" => round(daytime(w); digits = 3), "frame" => g.frame,
        "fps_target" => g.fps, "frame_ms" => clock_summary(g.clock),
        "creatures" => length(w.creatures), "props" => length(w.props), "actors" => length(w.actors),
        "dormant_actors" => length(w.dormant),
        "plugins" => Dict(n => (isempty(p.error) ? "ok" : "error: " * first(p.error, 300)) for (n, p) in g.plugins),
        "systems" => [system_label(s) for s in g.systems],
        "minigames" => [game_title(T) for p in values(g.plugins) for T in p.minigames],
        "playing" => g.minigame === nothing ? "" : game_title(typeof(g.minigame)),
        "path_tracing" => g.screen !== nothing && !g.screen.rasterize,
        "headless" => g.dash === nothing)
end

function live_command(g::Game, ::Val{:eval}, msg)
    code = String(msg["code"])
    try
        f = Core.eval(g.live.mod, Meta.parse("game -> begin\n" * code * "\nend"))
        result = Base.invokelatest(f, g)
        return Dict{String,Any}("ok" => true, "result" => first(repr(MIME"text/plain"(), result), 20_000))
    catch e
        e isa InterruptException && rethrow()
        # the agent's code failed: the error is the answer, the game goes on
        return Dict{String,Any}("ok" => false, "error" => first(sprint(showerror, e, catch_backtrace()), 20_000))
    end
end

function live_command(g::Game, ::Val{:screenshot}, msg)
    g.screen === nothing && return Dict{String,Any}("ok" => false, "error" => "the game runs headless")
    path = String(msg["path"])
    mkpath(dirname(path))
    img = Makie.colorbuffer(g.screen)
    Makie.save(path, img)
    return Dict{String,Any}("ok" => true, "path" => path, "size" => [size(img, 2), size(img, 1)])
end

function live_command(g::Game, ::Val{:path_tracing}, msg)
    g.screen === nothing && return Dict{String,Any}("ok" => false, "error" => "the game runs headless")
    set_path_tracing!(g, msg["on"] === true)
    return Dict{String,Any}("ok" => true, "path_tracing" => !g.screen.rasterize)
end

function live_command(g::Game, ::Val{:reload}, msg)
    check_plugins!(g)
    g.last_plugin_check = time()
    return Dict{String,Any}("ok" => true, "plugins" => Dict(n => (isempty(p.error) ? "ok" : first(p.error, 2000)) for (n, p) in g.plugins))
end

"Save the world now (the host asks before the sandbox copies the human's world)."
function live_command(g::Game, ::Val{:save}, msg)
    save_world!(g; reason = string(get(msg, "reason", "asked")))
    return Dict{String,Any}("ok" => true)
end

function live_command(g::Game, ::Val{:shutdown}, msg)
    # who stopped the game: the session 23/24 restarts every ~6 min had no recorded cause
    log_event!(g.log, g.world.t, :shutdown_request; msg = string(msg))
    g.running = false
    return Dict{String,Any}("ok" => true)
end

# ── client ──────────────────────────────────────────────────────────────────

"""
    live(cmd; game = :sandbox, kw...) -> Dict

Send one command to a running game and return its answer: your sandbox, or
with `game = :live` the human's game (look there, never change it). Every
`live_*` function takes `game`. Throws when the game is not running (no
socket) or the command failed.
"""
function live(cmd::AbstractString; root::AbstractString = game_root(), game::Symbol = :sandbox, kw...)
    sock = live_socket(GamePaths(root, game))
    ispath(sock) || error("the $(game) game is not running (no $(sock)): it is starting (1-3 min) or it ",
                          "does not start, and then the end of $(game_log(root, Val(game))) says why")
    msg = Dict{String,Any}("id" => rand(1:10^9), "cmd" => cmd)
    for (k, v) in kw
        msg[String(k)] = v
    end
    io = Sockets.connect(sock)
    try
        println(io, JSON.json(msg))
        answer = JSON.parse(readline(io); dicttype = Dict{String,Any})
        answer["ok"] === true || error("live $(cmd): " * string(get(answer, "error", answer)))
        return answer
    finally
        close(io)
    end
end

"The host's log of a game process (`.jail/logs`, named after its service)."
game_log(root::AbstractString, ::Val{:live}) = joinpath(root, ".jail", "logs", "game.log")
game_log(root::AbstractString, ::Val{:sandbox}) = joinpath(root, ".jail", "logs", "sandbox.log")

"Frame times, plugins, systems, mini games of the running game."
live_status(; kw...) = live("status"; kw...)["status"]

"""
    live_eval(code) -> String

Run `code` inside the running game, between two frames, as the body of a
function of `game` (the `Game`): `live_eval("length(game.world.actors)")`.
Returns the result's text.
"""
live_eval(code::AbstractString; kw...) = live("eval"; code, kw...)["result"]

"Save what the dashboard shows right now to `path` (png). `game = :live`: what the human sees."
live_screenshot(path::AbstractString; kw...) = live("screenshot"; path = abspath(path), kw...)["path"]

"""
    live_path_tracing(on)

Switch the game's RayMakie screen between path tracing (`true`, progressive:
the picture refines while nothing moves) and raster (`false`, fast). Browsers
always draw with WGLMakie.
"""
live_path_tracing(on::Bool; kw...) = live("path_tracing"; on, kw...)["path_tracing"]

"Load changed plugins now instead of within the next second; returns each plugin's state."
live_reload(; kw...) = live("reload"; kw...)["plugins"]
