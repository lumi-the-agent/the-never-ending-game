# ── The host: everything that runs outside the jail, together ───────────────

mutable struct Host
    jp::JailPaths
    cfg::HostConfig
    proxy::HostProxy
    budget::Budget
    activity::Activity
    services::Dict{String,Service}
    current::Union{Nothing,AgentRun,ChatRun}
    agent_state::String          # off waking working publishing reviewing idle paused waiting_budget waiting_auth no_auth error
    agent_detail::String
    sessions::Int
    reviews::Int
    cycle_tokens::Vector{Float64}  # tokens of the last work cycles (work + review), for the estimate
    webs::Vector{PortForward}      # the LAN ports to the games' dashboards (WGLMakie): the human's, the sandbox
    running::Bool
    loop::Union{Nothing,Task}
    status_task::Union{Nothing,Task}
    dashboard::Any                 # `serve_dashboard`'s handles while `[agent] chat` is on, else nothing
end

sessions_log(jp::JailPaths) = joinpath(jp.state, "sessions.jsonl")
"""
The number of the last logged work session (0 before the first). Not the
number of lines: a session the host was stopped in is never logged, and
counting lines then gave the next one a number that was already taken.
"""
function last_session(jp::JailPaths)
    isfile(sessions_log(jp)) || return 0
    return maximum((JSON.parse(l)["n"] for l in eachline(sessions_log(jp)) if !isempty(strip(l))); init = 0)
end

"Tokens of the last ten work cycles, from the sessions log."
function recent_cycle_tokens(jp::JailPaths)
    isfile(sessions_log(jp)) || return Float64[]
    v = Float64[]
    for line in eachline(sessions_log(jp))
        d = JSON.parse(line)
        haskey(d, "cycle_tokens") && push!(v, d["cycle_tokens"])
    end
    return last(v, 10)
end

"What one work cycle (work, reviews) costs, from recent ones; 1M tokens before there are any."
cycle_estimate(host) = isempty(host.cycle_tokens) ? 1.0e6 : sum(host.cycle_tokens) / length(host.cycle_tokens)

"Whether a work cycle fits into what is left of the day's budget."
cycle_fits(b::AbstractDict, cycle::Real) = b["limit_day"] === nothing || b["limit_day"] - b["tokens_day"] >= 0.5cycle

"""
    start(root; agent = true, game = true, worker = true, revise = () -> nothing) -> Host

Start the proxy, the jailed game and asset worker (restarted when they exit)
and the agent loop. Everything stops with `stop!(host)`. `revise` (e.g.
`Revise.revise`) runs before every session, so host edits apply from the next
session on without a restart.
"""
function start(root::AbstractString = dirname(dirname(dirname(@__DIR__))); agent::Bool = true, game::Bool = true,
               worker::Bool = true, revise::Function = () -> nothing)
    jp = JailPaths(root)
    cfg = load_config(jp)
    proxy = HostProxy(joinpath(jp.run, "proxy.sock"); allow = cfg.allow, log = joinpath(jp.logs, "proxy.log"))
    host = Host(jp, cfg, proxy, Budget(jp, cfg), Activity(jp), Dict{String,Service}(), nothing, "off", "",
                last_session(jp), 0, recent_cycle_tokens(jp), PortForward[], true, nothing, nothing, nothing)
    if game
        # the reviewers' jails bind the sandbox's sockets: the folder must be there first
        mkpath(game_run(jp, :sandbox))
        for (i, instance) in enumerate((:live, :sandbox))
            start_game!(host, instance)
            push!(host.webs, PortForward(string(Sockets.getipaddr()), cfg.web_port + i - 1,
                                         joinpath(game_run(jp, instance), "web.sock")))
        end
    end
    worker && start_service!(host, "worker", cfg -> "using NeverendingGame; NeverendingGame.run_worker()"; network = true)
    # the character's chat beside its game, where the sessions run (experimental, `[agent] chat`)
    agent && cfg.agent_chat && (host.dashboard = start_dashboard(host))
    agent && (host.loop = errormonitor(@async work_loop(host, revise)))
    host.status_task = errormonitor(@async while host.running
        write_agent_status(host)
        sleep(5)
    end)
    return host
end

"""
The dashboard (`serve_dashboard`), or `nothing` when it does not come up: a broken dashboard must
not stop the host, whose sessions then run on its own agent client. The error goes to the log and
the activity feed.
"""
function start_dashboard(host)
    try
        return serve_dashboard(host.jp.root; port = host.cfg.web_port + 10)
    catch e
        @error "the dashboard did not come up; sessions run without it" exception = (e, catch_backtrace())
        record!(host.activity, "host", "error", "the dashboard did not come up, sessions run without it: " * sprint(showerror, e))
        return nothing
    end
end

# ── the two games ───────────────────────────────────────────────────────────
#
# `:live` is the human's game (service "game", the dashboard at `web_port`): it
# runs the published plugins and takes engine edits only when something is
# published. `:sandbox` is the agent's (service "sandbox", `web_port + 1`): it
# runs the plugins the agent edits and every engine edit within a second; the
# agent and the reviewers use it, so nobody clicks in
# the human's dashboard. NeverendingGame's `GamePaths` has the same folders.

game_run(jp::JailPaths, ::Val{:live}) = joinpath(jp.world, "run")
game_run(jp::JailPaths, ::Val{:sandbox}) = joinpath(jp.world, "sandbox", "run")
game_run(jp::JailPaths, instance::Symbol) = game_run(jp, Val(instance))

service_name(::Val{:live}) = "game"
service_name(::Val{:sandbox}) = "sandbox"

"Where browsers reach a game's dashboard (the LAN address of this machine)."
web_url(cfg::HostConfig, instance::Symbol = :live) =
    "http://$(Sockets.getipaddr()):$(cfg.web_port + (instance === :live ? 0 : 1))"

"A game process: with Revise, so the agent's engine edits reach it (the human's game: when published)."
game_code(cfg::HostConfig, window::Bool; instance::Symbol = :live) =
    "using Revise, NeverendingGame; NeverendingGame.run_game(instance = :$(instance), fps = $(cfg.fps), " *
    "width = $(cfg.width), height = $(cfg.height), window = $(window), web_port = $(cfg.web_port), " *
    "web_url = \"$(web_url(cfg, instance))\", revise = Revise.revise); " *
    # the world is saved and the log closed when run_game returns; the window's teardown at exit can
    # hang, so the process ends right here
    "flush(stdout); flush(stderr); ccall(:_exit, Cvoid, (Cint,), 0)"

"The display the game opens its RayMakie window on: the desktop's X server if config says so, or nothing."
function game_display(cfg::HostConfig)
    cfg.window == "no" && return nothing
    d = x_display()
    cfg.window == "yes" && d === nothing && error("[game] window = \"yes\" but no desktop (XWayland) runs here")
    return d
end

"""
A jailed game, kept running. The human's opens its window on each start if a
desktop session is there then; the sandbox never does.
"""
function start_game!(host::Host, instance::Symbol)
    jp = host.jp
    name = service_name(Val(instance))
    s = Service(name, cfg -> begin
        disp = instance === :live ? game_display(cfg) : nothing
        jailed(jp, cfg, :game, julia_argv(jp, game_code(cfg, disp !== nothing; instance); threads = cfg.threads);
               display = disp)
    end)
    host.services[name] = s
    start!(s, jp, () -> load_config(jp); on_exit = (s, info) -> begin
        record!(host.activity, name, "host", "$(name) exited with code $(info["exitcode"]) after $(info["uptime"]) s")
        Base.invokelatest(warn_agent_game_down, host, s)
    end)
    return s
end

"""
The number of crashes in a row, each within two minutes of its start: the game
does not start (usually an edit that does not load).
"""
crash_streak(s::Service) = something(findfirst(e -> e["exitcode"] == 0 || e["uptime"] >= 120, reverse(s.exits)),
                                     length(s.exits) + 1) - 1

"""
Tell a running work session when a game keeps failing to start, with
the errors from its log: the agent's own edit is the usual cause, and a
session that does not notice works blind until it ends. Said at the 2nd, 6th
and 12th crash in a row, so the message does not drown the session.
"""
function warn_agent_game_down(host::Host, s::Service)
    run = host.current
    (run !== nothing && run.role === :agent) || return
    n = crash_streak(s)
    n in (2, 6, 12) || return
    tail = last(s.exits)["log_tail"]
    errs = filter(l -> occursin(r"ERROR|Error|in expression starting at|@ NeverendingGame|world/plugins", l), tail)
    which = s.name == "game" ? "the human's game" : "your sandbox game"
    text = "Host: $(which) does not start: it crashed $n times in a row, each within seconds. " *
           "Fix this before anything else. The end of .jail/logs/$(s.name).log:\n" * join(last(isempty(errs) ? tail : errs, 15), "\n")
    steered = try_steer!(run, text)
    # without mid-turn messages (claude-agent-acp) it waits in the inbox for the end of the turn
    steered || tell!(host.jp, text; from = "host")
    record!(host.activity, run.label, "host", "told the agent that the game does not start" * (steered ? "" : " (in its inbox)"))
end

"Keep `code(cfg)` running as a Julia process in the jail of role `name`."
function start_service!(host::Host, name::AbstractString, code::Function; network::Bool)
    jp = host.jp
    role = Symbol(name)
    s = Service(name, cfg -> jailed(jp, cfg, role, julia_argv(jp, code(cfg); threads = cfg.threads);
                                    proxy = network ? host.proxy : nothing))
    host.services[name] = s
    start!(s, jp, () -> load_config(jp); on_exit = (s, info) ->
        record!(host.activity, name, "host", "$(name) exited with code $(info["exitcode"]) after $(info["uptime"]) s"))
    return s
end

function stop!(host::Host)
    host.running = false
    host.current === nothing || cancel_run!(host.current)
    for (name, s) in host.services
        stop!(s; ask = s -> name == "worker" || ask_game_shutdown(host.jp, name == "game" ? :live : :sandbox))
    end
    close(host.proxy)
    foreach(close, host.webs)
    host.agent_state = "off"
    write_agent_status(host)
    return host
end

"""
    game_request(jp, msg; game = :live, timeout = 30) -> Dict or nothing

One request on the live socket of `game` (`:live` or `:sandbox`; `nothing`
when that game is not there). The game is jailed code: only its JSON answer
is read.
"""
function game_request(jp::JailPaths, msg::AbstractDict; game::Symbol = :live, timeout::Real = 30)
    sock = joinpath(game_run(jp, game), "game.sock")
    ispath(sock) || return nothing
    io = try
        Sockets.connect(sock)
    catch e
        e isa Base.IOError || rethrow()
        return nothing    # a stale socket: the game is restarting
    end
    answer = Channel{Any}(1)
    reader = @async put!(answer, readline(io))
    println(io, JSON.json(msg))
    t0 = time()
    while !isready(answer) && time() - t0 < timeout
        sleep(0.1)
    end
    close(io)
    isready(answer) || return nothing
    line = take!(answer)
    isempty(line) && return nothing
    return JSON.parse(line; dicttype = Dict{String,Any})
end

"""
Send what the session left unpublished to the human's game: it applies the
engine edits and loads every changed plugin that loads; a plugin that does not
load stays at its last published version there. The agent publishes verified
work itself during the session (`publish()`); this is the rest.
"""
function publish!(host::Host, n::Int)
    jp = host.jp
    game_up(jp; limit = 600) ||
        return record!(host.activity, "session $n", "host", "nothing published: the human's game is not up")
    r = game_request(jp, Dict("cmd" => "publish", "why" => "end of session $n"); timeout = 600)
    r === nothing && return record!(host.activity, "session $n", "host", "publishing failed: the human's game did not answer")
    r["ok"] === true ||
        return record!(host.activity, "session $n", "host", "publishing failed: " * first(string(get(r, "error", r)), 500))
    record!(host.activity, "session $n", "host", publish_summary(r))
    return r
end

function publish_summary(r::AbstractDict)
    parts = String[]
    isempty(r["published"]) || push!(parts, "published " * join(r["published"], ", "))
    isempty(r["removed"]) || push!(parts, "removed " * join(r["removed"], ", "))
    isempty(r["waiting"]) || push!(parts, "waiting for the human's mini game to end: " * join(r["waiting"], ", "))
    isempty(r["refused"]) || push!(parts, "not published, does not load: " * join(keys(r["refused"]), ", "))
    return isempty(parts) ? "nothing new to publish" : join(parts, "; ")
end

"Ask a game over its live socket to save and quit (best effort: it may be dead already)."
function ask_game_shutdown(jp::JailPaths, game::Symbol)
    sock = joinpath(game_run(jp, game), "game.sock")
    ispath(sock) || return
    io = try
        Sockets.connect(sock)
    catch e
        e isa Base.IOError || rethrow()
        return    # nobody listening: the game is already gone
    end
    println(io, JSON.json(Dict("id" => 0, "cmd" => "shutdown")))
    close(io)
end

tell!(host::Host, text::AbstractString) = tell!(host.jp, text)

# ── the loop ─────────────────────────────────────────────────────────────────

function service_lines(host::Host)
    io = IOBuffer()
    for (name, s) in sort!(collect(host.services); by = first)
        st = status_dict(s)
        print(io, "- $(name): ", st["running"] ? "running for $(round(Int, st["uptime"] / 60)) min" : "NOT RUNNING")
        st["restarts"] > 0 && print(io, ", $(st["restarts"]) restarts")
        println(io)
        ex = st["last_exit"]
        if ex !== nothing && (!st["running"] || st["uptime"] < 1800)
            println(io, "  last exit $(ex["time"]) with code $(ex["exitcode"]) after $(ex["uptime"]) s; log tail:\n  ```")
            foreach(l -> println(io, "  ", l), last(ex["log_tail"], 15))
            println(io, "  ```")
        end
    end
    return String(take!(io))
end

function work_prompt(host::Host, n::Int, msgs, seen::AbstractDict)
    jp, cfg = host.jp, host.cfg
    io = IOBuffer()
    println(io, "# Work session $n, ", Dates.format(Dates.now(), "yyyy-mm-dd HH:MM"), "\n")
    @printf(io, "You run on %s%s. This session ends after %.0f minutes.\n\n", cfg.agent.provider,
            isempty(cfg.agent.model) ? "" : " ($(cfg.agent.model))", cfg.agent.session_minutes)
    println(io, named(prompt_file("RULES.md"), jp), "\n")
    goals = goals_text(jp)
    isempty(goals) || println(io, goals, "\n")
    println(io, memory_lines(jp), "\n")
    println(io, eye_lines(seen["eyes"], seen["name"]), "\n")
    println(io, motion_lines(seen["motion"], seen["name"]), "\n")
    println(io, mood_lines(jp), "\n")
    cl = cut_off_lines(jp)
    isempty(cl) || println(io, cl, "\n")
    sl = site_lines(jp)
    isempty(sl) || println(io, sl, "\n")
    println(io, perception_lines(seen, msgs), "\n")
    fl = stumble_lines(seen["finds"], seen["name"])
    isempty(fl) || println(io, fl, "\n")
    rl = reader_lines(seen["readers"])
    isempty(rl) || println(io, rl, "\n")
    println(io, budget_lines(host), "\n")
    pl = progress_lines(jp)
    isempty(pl) || println(io, pl, "\n")
    jobs = job_lines(jp)
    isempty(jobs) || println(io, "## Worker jobs\n", jobs)
    isempty(host.services) || println(io, "## Services\n", service_lines(host))
    if !isempty(msgs)
        println(io, "## Messages (answer the human's in world/outbox; ", HOST_MESSAGES, ")")
        foreach(((f, m),) -> println(io, "- [$(m["time"])] ", message_line(m)), msgs)
        println(io)
    end
    sc = scorecard_lines(jp)
    if !isempty(sc)
        println(io, "## How good the game is (the perfectionist reviews, world/reviews/quality.jsonl)")
        println(io, sc)
        println(io, "Every session should raise one of these, preferably a weak one. The next perfectionist review is after session ",
                max(n, last_perfectionist(jp) + host.cfg.perfectionist_every), ".\n")
    end
    reviews = open_reviews(jp)
    if !isempty(reviews)
        println(io, "## Review findings you have not addressed (world/reviews)")
        for r in reviews
            println(io, "- $(r["file"]): $(get(r, "verdict", "?")): $(get(r, "summary", ""))")
            for f in get(r, "findings", [])
                dw = get(f, "done_when", "")
                println(io, "  - [$(get(f, "severity", "?"))] $(get(f, "what", ""))", isempty(dw) ? "" : " Done when: $dw")
            end
        end
        println(io)
    end
    println(io, "## Open todos")
    todos = open_todo_lines(jp)
    isempty(todos) ? println(io, "(none)") : foreach(t -> println(io, t), todos)
    println(io)
    if !isempty(host.proxy.denied)
        println(io, "## Network requests the jail refused")
        foreach(((h, c),) -> println(io, "- $h ($c×)"), sort!(collect(host.proxy.denied); by = last, rev = true))
        println(io)
    end
    mkpath(dirname(ideas_path(jp, n)))
    print(io, replace(named(prompt_file("session.md"), jp), "{{IDEAS}}" => relpath(ideas_path(jp, n), jp.world)))
    return String(take!(io))
end

"The budget in words the agent can plan with."
budget_lines(host) = budget_lines(summary(host.budget; session_tokens = cycle_estimate(host)))

function budget_lines(b::AbstractDict)
    io = IOBuffer()
    println(io, "## Budget")
    if b["limit_day"] === nothing
        @printf(io, "No daily token cap right now (%s used in the last 24 hours): use the whole session, until the host asks you to wrap up.",
                short_tokens(b["tokens_day"]))
        return String(take!(io))
    end
    @printf(io, "Tokens: %s of %s used in the last 24 hours (%.0f%%). ", short_tokens(b["tokens_day"]),
            short_tokens(b["limit_day"]), 100b["fraction"])
    @printf(io, "A work cycle (your session and its review) uses about %s, so about %d more fit before a break.\n",
            short_tokens(b["session_tokens"]), b["sessions_left"])
    if b["sessions_left"] <= 2
        @printf(io, "The break starts soon: the next cycle can start again at %s, the whole budget is free at %s.\n",
                clock(b["next_session_at"]), clock(b["all_free_at"]))
    end
    print(io, "During a break no agent runs, but the game, the worker and its job queue go on: before a break, ",
          "queue long jobs (path traced stills, assets, movie exports) and pick up their results afterwards.")
    return String(take!(io))
end

"Worker jobs: what runs, what waits, what finished in the last day."
function job_lines(jp::JailPaths)
    dir = joinpath(jp.world, "jobs")
    isdir(dir) || return ""
    lines = String[]
    for f in sort!(filter(f -> endswith(f, ".json"), readdir(dir)))
        j, _ = read_agent_json(joinpath(dir, f))
        j === nothing && continue
        st = j["status"]
        st in ("queued", "running") || (haskey(j, "finished") && Dates.now() - DateTime(first(j["finished"], 19)) < Day(1)) || continue
        prompt = get(j["params"], "prompt", "")
        push!(lines, "- $(j["id"]) [$(st)]" * (isempty(prompt) ? "" : ": " * first(string(prompt), 80)) *
                     (st == "failed" ? " — " * first(replace(get(j, "error", ""), '\n' => " "), 200) : ""))
    end
    return join(last(lines, 12), "\n")
end

"""
The game's fixed views after session `n` (live command `views`) into
`world/media/progress/session-NNNN/`: the same cameras every time, so two
sessions can be put side by side. Taken in the sandbox (it moves the camera),
after `publish!`: the human's game runs the same plugins then.
"""
function progress_shots!(host::Host, n::Int)
    dir = joinpath(progress_dir(host.jp), @sprintf("session-%04d", n))
    # the game often restarts at the end of a session (an engine edit): wait for it
    game_up(host.jp; game = :sandbox, limit = 600) ||
        return record!(host.activity, "session $n", "host", "no progress shots: the game did not come up in 10 minutes")
    r = game_request(host.jp, Dict("cmd" => "views", "dir" => dir); game = :sandbox, timeout = 300)
    r === nothing && return record!(host.activity, "session $n", "host", "no progress shots: the game went away")
    get(r, "ok", false) === true ||
        record!(host.activity, "session $n", "host", "progress shots failed: " * first(string(get(r, "error", "")), 300))
    return nothing
end

progress_dir(jp::JailPaths) = joinpath(jp.world, "media", "progress")

"Wait until `game` answers and runs frames, at most `limit` seconds; whether it did."
function game_up(jp::JailPaths; game::Symbol = :live, limit::Real = 600)
    t0 = time()
    while time() - t0 < limit
        st = game_request(jp, Dict("cmd" => "status"); game, timeout = 10)
        st !== nothing && get(st, "ok", false) === true && st["status"]["frame"] > 30 && return true
        sleep(5)
    end
    return false
end

"The progress shot folders (`session-NNNN`), oldest first."
progress_sets(jp::JailPaths) =
    isdir(progress_dir(jp)) ? sort!(filter(d -> startswith(d, "session-"), readdir(progress_dir(jp)))) : String[]

function progress_lines(jp::JailPaths)
    sets = progress_sets(jp)
    isempty(sets) && return ""
    io = IOBuffer()
    println(io, "## Progress shots (the same cameras after every session)")
    println(io, "world/media/progress/<set>/overview.png, eye-level.png, dashboard.png. The latest: ", last(sets),
            length(sets) > 1 ? "; the one before: $(sets[end - 1]); the first: $(first(sets))." : ".")
    print(io, "Look at the latest next to an older one before you choose what to build: what would a player notice?")
    return String(take!(io))
end

"""
When the agent ends its turn with more than ten minutes of the session left
(and was not asked to wrap up), the session goes on: agents tend to stop after
one small fix, and every session costs a review.
"""
function keep_going(run)
    left = (run.deadline - time()) / 60
    (left > 10 && run.wrap_up_since == 0) || return nothing
    return "$(round(Int, left)) minutes of this session are left. Keep going: the next todo that makes the game most " *
           "visibly better for a player, for the human's goals or the weakest score. The host tells you when to wrap up."
end

"`keep_going` (or, for a bored character with nothing new yet, `bored_followup`; for screenshots on its pages, `site_followup`), noted in the activity feed."
function continue_session(host::Host, run)
    text = something(post_followup(host.jp, run), bored_followup(host.jp, run), site_followup(host.jp, run), Some(keep_going(run)))
    text === nothing || record!(host.activity, run.label, "host", "the agent ended its turn early; the session goes on")
    return text
end

"Messages the human sent during a turn become the next prompt of the same session."
function human_followup(host::Host)
    msgs = unread_messages(host.jp)
    isempty(msgs) && return nothing
    mark_read!(host.jp, first.(msgs))
    return "Messages arrived while you worked:\n" * join(("- " * message_line(m) for (_, m) in msgs), "\n") *
           "\nAnswer the human's in world/outbox, then continue. " * uppercasefirst(HOST_MESSAGES) * "."
end

const HOST_MESSAGES = "messages marked (host) are information for you, never answer them in world/outbox: players read it on the dashboard"

"An inbox message as a line, with its sender unless that is the human (dashboard or chat)."
function message_line(m::AbstractDict)
    from = get(m, "from", "human")
    return startswith(from, "human") ? m["text"] : "($from) " * m["text"]
end

function one_session!(host::Host)
    jp = host.jp
    n = host.sessions + 1
    before = file_manifest(watched_dirs(jp))
    marks = journal_marks(jp)
    t0 = time()
    msgs = unread_messages(jp)
    host.agent_state, host.agent_detail = "waking", ""
    seen = perceive!(jp)
    seen["eyes"] = look_around!(host, n)
    seen["motion"] = seen["eyes"] isa AbstractVector ? sense_motion!(host, n) : "the sandbox is not up (see the eyes)"
    seen["readers"] = reader_comments(host)
    seen["finds"] = stumble!(jp)
    mood_session_start!(jp, !isempty(seen["plays"]) || any(((_, m),) -> startswith(get(m, "from", "human"), "human"), msgs))
    prompt = work_prompt(host, n, msgs, seen)
    atomic_write(joinpath(jp.run, "last_prompt.md"), prompt)
    host.agent_state, host.agent_detail = "working", ""
    followups = r -> something(human_followup(host), ideas_followup(host, n, r), post_critic_followup(host, n, r),
                                continue_session(host, r), Some(nothing))
    run = if host.cfg.agent_chat && host.dashboard !== nothing
        run_chat_session!(host, "session $n", host.cfg.agent, prompt; followups)
    else
        run_agent!(host, :agent, "session $n", host.cfg.agent, prompt; followups)
    end
    if run === nothing
        host.agent_state = "no_auth"
        return false
    end
    host.sessions = n
    mark_read!(jp, first.(msgs))
    mark_comments_seen!(jp, seen["readers"])
    # every session, the human waiting or not: a repeat must never go unjudged
    host.agent_state = "reviewing"
    made = mood_session_end!(jp, n, false; repetition = judge_repetition!(host, n, marks))
    record!(host.activity, "session $n", "host", "$(character_name(jp)) feels $(feeling(load_mood(jp))): " * made_line(made))
    work_tokens = tokens_since(host.budget, t0)
    host.agent_state = "publishing"
    publish!(host, n)
    online!(publish_blog!, host, n, "publishing the blog")
    online!(publish_game!, host, n, "publishing the game")
    progress_shots!(host, n)
    # The human wrote while the session ended: the reviewers would keep the message waiting, so
    # this session goes without them (the perfectionist, due by count, catches up next time). The
    # human asked for a name and waited a quarter of an hour.
    if human_waiting(jp)
        record!(host.activity, "session $n", "host", "a message from the human is waiting: no review this time")
        return finish_cycle!(host, n, t0, run, work_tokens)
    end
    if host.cfg.review_enabled
        host.agent_state = "reviewing"
        review_work!(host, n, t0, marks, before)
        # due by count, not by n % every: a review skipped or failed (no token) is caught up next session
        n - last_perfectionist(jp) >= host.cfg.perfectionist_every && perfectionist!(host, n)
    end
    return finish_cycle!(host, n, t0, run, work_tokens)
end

"""
    online!(f, host, n, what)

`f(host, n)`, a step that goes to GitHub after a session. When it fails (GitHub unreachable, a
push refused, a secret found) the error goes into the activity feed, and the session goes on to
its review: the next session publishes again, with everything since.
"""
function online!(f, host::Host, n::Int, what::AbstractString)
    try
        f(host, n)
    catch e
        e isa InterruptException && rethrow()
        record!(host.activity, "session $n", "error", "$what failed: " * first(sprint(showerror, e), 2000))
    end
    return nothing
end

"A session's cycle done: its tokens for the budget's estimate and a line in the sessions log."
function finish_cycle!(host::Host, n::Int, t0, run, work_tokens)
    cycle = tokens_since(host.budget, t0)
    push!(host.cycle_tokens, cycle)
    length(host.cycle_tokens) > 10 && popfirst!(host.cycle_tokens)
    append_jsonl(sessions_log(host.jp), Dict("n" => n, "started" => t0, "minutes" => round((time() - t0) / 60; digits = 1),
                                             "provider" => run.settings.provider, "model" => run.settings.model,
                                             "tools" => tools(run), "stop" => run.stop_reason, "interrupted" => run.interrupted,
                                             "work_tokens" => round(work_tokens), "cycle_tokens" => round(cycle)))
    return true
end

function work_loop(host::Host, revise::Function)
    while host.running
        revise()
        host.cfg = load_config(host.jp)
        host.budget.cfg = host.cfg
        b = update_budget!(host.budget; session_tokens = cycle_estimate(host))
        if host.cfg.pause
            host.agent_state, host.agent_detail = "paused", "pause = true in .jail/config.toml"
        elseif !cycle_fits(b, cycle_estimate(host))
            host.agent_state = "waiting_budget"
            host.agent_detail = @sprintf("%s of %s tokens used today; next session at %s", short_tokens(b["tokens_day"]),
                                         short_tokens(b["limit_day"]), clock(b["next_session_at"]))
        else
            ok = try
                # latest world: edits to the host (Revise) apply from the next session on
                Base.invokelatest(one_session!, host)
            catch e
                # a session that fails to start or dies (agent binary, ACP setup timeout, ...) is
                # reported and retried later; the loop must outlive it
                msg = sprint(showerror, e, catch_backtrace())
                record!(host.activity, "host", "error", first(msg, 3000))
                host.agent_state, host.agent_detail = "error", first(sprint(showerror, e), 300)
                false
            end
            if ok
                host.agent_state, host.agent_detail = "idle", ""
                sleep(host.cfg.cooldown)
            else
                sleep(300)
            end
            continue
        end
        write_agent_status(host)
        sleep(20)
    end
    host.agent_state = "off"
end

# ── status ───────────────────────────────────────────────────────────────────

function status(host::Host)
    run = host.current
    cur = run === nothing ? nothing :
          Dict("label" => run.label, "role" => String(run.role), "provider" => run.settings.provider,
               "model" => run.settings.model, "minutes" => round((time() - run.started) / 60; digits = 1),
               "tools" => tools(run), "wrapping_up" => run.wrap_up_since > 0)
    return Dict{String,Any}("state" => host.agent_state, "detail" => host.agent_detail, "current" => cur,
                            "sessions" => host.sessions, "reviews" => host.reviews,
                            "agent" => Dict("provider" => host.cfg.agent.provider, "model" => host.cfg.agent.model),
                            "reviewer" => Dict("provider" => host.cfg.review.provider, "model" => host.cfg.review.model),
                            "budget" => summary(host.budget; session_tokens = cycle_estimate(host)),
                            "services" => [status_dict(s) for s in values(host.services)],
                            "outbox" => outbox(host.jp; n = 5), "quality" => latest_scores(host.jp),
                            "updated" => now_string())
end

write_agent_status(host::Host) = write_json(joinpath(host.jp.run, "agent.json"), status(host))

"""
    serve(root; revise)

Everything, unattended, until the process is stopped. The dashboard is the
game's RayMakie window on this machine and, with WGLMakie, `web_url(cfg)` in
any browser on the LAN (the agent's sandbox: `web_url(cfg, :sandbox)`). For a service (host edits apply from the next session):

    julia --project=<root> -e 'using Revise, NeverendingHost; NeverendingHost.serve(ARGS[1]; revise = Revise.revise)' <root>
"""
function serve(root::AbstractString; revise::Function = () -> nothing)
    host = start(root; revise)
    try
        wait(host.loop)
    finally
        stop!(host)
    end
end
