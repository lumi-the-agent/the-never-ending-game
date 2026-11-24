# ── Jailed processes that should always run (game, asset worker) ────────────
#
# A `Service` is restarted when it exits, with a growing pause so a crash loop
# does not burn the machine. Each start appends to `.jail/logs/<name>.log`;
# exits are recorded in `.jail/run/services.json` with the log tail, which the
# next agent session is shown.

mutable struct Service
    name::String
    cmd::Function                       # cfg -> Cmd, rebuilt on every start (config.toml is live)
    proc::Union{Nothing,Base.Process}
    want::Bool
    started::Float64
    restarts::Int
    backoff::Float64
    exits::Vector{Dict{String,Any}}     # most recent last
    task::Union{Nothing,Task}
end

Service(name::AbstractString, cmd::Function) = Service(String(name), cmd, nothing, false, 0.0, 0, 5.0, Dict{String,Any}[], nothing)

log_path(jp::JailPaths, name::AbstractString) = joinpath(jp.logs, name * ".log")

isrunning(s::Service) = s.proc !== nothing && process_running(s.proc)

function launch!(s::Service, jp::JailPaths, cfg::HostConfig)
    log = open(log_path(jp, s.name), "a")
    println(log, "\n==== ", now_string(), " start ", s.name, " ====")
    flush(log)
    s.proc = run(pipeline(s.cmd(cfg); stdin = devnull, stdout = log, stderr = log); wait = false)
    close(log)   # the child holds its own descriptor
    s.started = time()
    return s
end

"""
    start!(s, jp, cfg_fn; on_exit)

Keep `s` running until `stop!`. `cfg_fn()` returns the current config (so a
restart picks up edits); `on_exit(s, info)` is called after every exit.
"""
function start!(s::Service, jp::JailPaths, cfg_fn; on_exit = (s, info) -> nothing)
    s.want = true
    s.task = errormonitor(@async begin
        while s.want
            launched = try
                # latest world: edits to the host apply on the next restart
                Base.invokelatest(launch!, s, jp, cfg_fn())
                true
            catch e
                e isa InterruptException && rethrow()
                # a broken command line (a host bug) is reported and retried, never silent
                on_exit(s, Dict{String,Any}("service" => s.name, "time" => now_string(), "exitcode" => -1,
                                            "signal" => 0, "uptime" => 0.0,
                                            "log_tail" => split(sprint(showerror, e, catch_backtrace()), '\n')))
                false
            end
            if !launched
                sleep(60)
                continue
            end
            wait(s.proc)
            uptime = time() - s.started
            info = Dict{String,Any}("service" => s.name, "time" => now_string(), "exitcode" => s.proc.exitcode,
                                    "signal" => s.proc.termsignal, "uptime" => round(uptime; digits = 1),
                                    "log_tail" => tail_lines(log_path(jp, s.name), 40))
            push!(s.exits, info)
            length(s.exits) > 20 && popfirst!(s.exits)
            on_exit(s, info)
            s.want || break
            # a clean exit (asked to restart) or a long healthy run: come back at once;
            # a crash loop waits longer each time
            s.backoff = s.proc.exitcode == 0 ? 1.0 : uptime > 600 ? 5.0 : min(2s.backoff, 300.0)
            s.restarts += 1
            sleep(s.backoff)
        end
    end)
    return s
end

"""
Stop restarting and kill the jail (bwrap takes everything inside with it).
`ask` is tried first for a clean exit (e.g. the game saving its snapshot).
"""
function stop!(s::Service; grace::Real = 10, ask = s -> nothing)
    s.want = false
    isrunning(s) || return s
    ask(s)
    t0 = time()
    while isrunning(s) && time() - t0 < grace
        sleep(0.2)
    end
    isrunning(s) && kill(s.proc, Base.SIGTERM)
    t0 = time()
    while isrunning(s) && time() - t0 < grace
        sleep(0.2)
    end
    isrunning(s) && kill(s.proc, Base.SIGKILL)
    return s
end

status_dict(s::Service) = Dict{String,Any}("name" => s.name, "running" => isrunning(s), "restarts" => s.restarts,
                                           "uptime" => isrunning(s) ? round(time() - s.started) : 0.0,
                                           "last_exit" => isempty(s.exits) ? nothing : last(s.exits))
