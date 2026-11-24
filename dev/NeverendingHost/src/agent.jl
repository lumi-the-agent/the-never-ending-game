# ── Agent sessions over ACP, any provider, always jailed ─────────────────────
#
# A session is one ACP client: the provider's adapter (from AgentProviders,
# installed by BonitoWorker) runs in the role's jail, with BonitoMCP (Julia
# with Revise) and RomeoDB as its MCP servers. The host sends a prompt, records
# everything the agent does into the activity feed, books the reported cost,
# and ends the session at its deadline or when the budget runs out. The
# implementer and the reviewer are both sessions; they differ in jail, prompt
# and provider.

const ACTIVITY_KEEP = 400

mutable struct Activity
    items::Vector{Dict{String,Any}}
    path::String          # .jail/run/activity.json (dashboard)
    world_log::String     # world/log/agent-<date>.jsonl (everything, kept)
end

Activity(jp::JailPaths) = Activity(Dict{String,Any}[], joinpath(jp.run, "activity.json"), joinpath(jp.world, "log"))

function record!(a::Activity, who::AbstractString, kind::AbstractString, text::AbstractString; data...)
    ev = Dict{String,Any}("time" => now_string(), "who" => String(who), "kind" => String(kind),
                          "text" => first(String(text), 4000))
    for (k, v) in data
        ev[String(k)] = v
    end
    push!(a.items, ev)
    length(a.items) > ACTIVITY_KEEP && popfirst!(a.items)
    mkpath(a.world_log)
    append_jsonl(joinpath(a.world_log, "agent-$(Dates.today()).jsonl"), ev)
    write_json(a.path, a.items)
    return ev
end

mutable struct AgentRun
    role::Symbol
    label::String                 # "session 12", "review 4"
    settings::AgentSettings
    client::ACP.Client
    started::Float64
    deadline::Float64
    cost::Float64                 # cumulative, as reported
    tools::Int
    stop_reason::String
    interrupted::String           # why the host stopped it ("" if it ended by itself)
    wrap_up_since::Float64
    consumer::Task
end

# ── provider, auth, MCP ──────────────────────────────────────────────────────

"Every file in `.jail/secrets/env/` is an environment variable of agent sessions."
function secret_env(jp::JailPaths)
    dir = joinpath(jp.secrets, "env")
    return Dict{String,String}(f => strip(read(joinpath(dir, f), String)) for f in readdir(dir) if !startswith(f, "."))
end

"""
The user's Claude login token runs out before a session would end: it comes
back once their own Claude Code refreshes it, so a run waits rather than
giving up (`run_agent!`).
"""
struct TokenExpiring end

"""
Claude Code's token: `CLAUDE_CODE_OAUTH_TOKEN` from the secrets (made with
`claude setup-token`), else the access token of the user's own login, read
fresh per session and never refreshed from here, so the user's login is left
alone. `(env, "")`, `(TokenExpiring(), why)` or `(nothing, why)`.
"""

function claude_auth(jp::JailPaths, secrets::Dict{String,String}; min_minutes::Real)
    haskey(secrets, "CLAUDE_CODE_OAUTH_TOKEN") && return Dict{String,String}(), ""
    cred = joinpath(jp.user_home, ".claude", ".credentials.json")
    isfile(cred) || return nothing, "no Claude token: put one from `claude setup-token` into .jail/secrets/env/CLAUDE_CODE_OAUTH_TOKEN"
    o = read_json(cred)["claudeAiOauth"]
    left = (o["expiresAt"] / 1000 - time()) / 60
    left < min_minutes && return TokenExpiring(), @sprintf("the user's Claude login token expires in %.0f min; waiting for it to be refreshed", left)
    return Dict("CLAUDE_CODE_OAUTH_TOKEN" => String(o["accessToken"])), ""
end

"The agent's command line and environment for `settings.provider`: `((argv, env, path), \"\")`, `(TokenExpiring(), why)` or `(nothing, why)`."
function provider_launch(jp::JailPaths, settings::AgentSettings)
    prov = AgentProviders.find_provider(settings.provider)
    cmd = BonitoWorker.agent_command(prov)
    env = merge(Dict{String,String}(prov.env), secret_env(jp))
    if prov isa AgentProviders.ClaudeCodeAgent
        # the token is not refreshed inside the jail: it has to outlast the whole session
        auth, why = claude_auth(jp, env; min_minutes = settings.session_minutes + 10)
        auth isa Dict || return auth, why
        merge!(env, auth)
        env["CLAUDE_MAX_TURNS"] = "400"
    end
    return (String[cmd.bin, prov.args...], env, cmd.path), ""
end

julia_mcp(jp::JailPaths) = ACP.MCPServer("julia", "julia";
    args = ["--project=$(jp.root)", "--startup-file=no", "--threads=4", "-e", "using BonitoMCP; BonitoMCP.run_stdio()"])

# `provision`: a fresh fork without the index fetches RomeoDB's published one on the first search
romeo_mcp(jp::JailPaths) = ACP.MCPServer("romeo", "julia";
    args = ["--project=$(jp.root)", "--startup-file=no", "--threads=4", "-e",
            "using RomeoDB; RomeoDB.serve(ARGS[1]; provision = true)", jp.romeodb])

"""
The ACP wire to an agent running as a (jailed) subprocess: one JSON message
per line on its stdin/stdout. AgentClientProtocol only ships the worker
transport, so this is the host's own (`send`, `recv`, `close`, `transport_eof`).
"""
struct ProcessTransport <: ACP.Transport
    proc::Base.Process
    lock::ReentrantLock
end

ProcessTransport(cmd::Base.AbstractCmd) = ProcessTransport(open(cmd, "r+"), ReentrantLock())

function ACP.send(t::ProcessTransport, line::AbstractString)
    @lock t.lock begin
        write(t.proc, endswith(line, '\n') ? line : line * "\n")
        flush(t.proc)
    end
    return nothing
end

ACP.recv(t::ProcessTransport) = readline(t.proc)
ACP.transport_eof(t::ProcessTransport) = eof(t.proc)

function Base.close(t::ProcessTransport)
    process_running(t.proc) && kill(t.proc)
    return nothing
end

"Answers what a jailed agent may ask its client: permission yes, file system no (it has its own)."
struct JailedHandler <: ACP.Handler end

function ACP.on_request(::JailedHandler, method::AbstractString, params)
    if method == "session/request_permission"
        options = get(params, "options", [])
        i = findfirst(o -> get(o, "kind", "") in ("allow_once", "allow_always"), options)
        i === nothing && return Dict{String,Any}("outcome" => Dict{String,Any}("outcome" => "cancelled"))
        return Dict{String,Any}("outcome" => Dict{String,Any}("outcome" => "selected", "optionId" => options[i]["optionId"]))
    end
    error("the host does not serve `$method` to a jailed agent")
end

"Pick the model choice matching `model` (by value or name), if the provider offers one."
function select_model!(client::ACP.Client, model::AbstractString)
    isempty(model) && return ""
    for o in ACP.parse_config_options(client.session_result)
        o.category == "model" || o.id == "model" || continue
        i = findfirst(c -> occursin(lowercase(model), lowercase(c.value)) || occursin(lowercase(model), lowercase(c.name)), o.choices)
        i === nothing && return "model '$model' not offered (choices: $(join((c.value for c in o.choices), ", ")))"
        ACP.set_config_option!(client, o.id, o.choices[i].value)
        return ""
    end
    return "the provider has no model option"
end

# ── one session ──────────────────────────────────────────────────────────────

one_line(s::AbstractString; n::Int = 200) = first(replace(s, '\n' => " ⏎ "), n)

"Short text for a tool call in the activity feed."
tool_line(tc::ACP.ToolCall) = one_line(tc.title)
tool_line(tc::ACP.BashCall) = "\$ " * one_line(isempty(tc.command) ? tc.title : tc.command)
function tool_line(tc::ACP.MCPCall)
    code = get(tc.raw_input, "code", nothing)
    return tc.tool_name * (code isa AbstractString ? ": " * one_line(code) : "")
end
tool_line(tc::ACP.GenericTool) = isempty(tc.name) || tc.name == tc.title ? one_line(tc.title) : tc.name * ": " * one_line(tc.title)

function consume!(host, run::AgentRun)
    a = host.activity
    for m in run.client.messages
        if m isa ACP.StreamFlush
            ACP.signal_rendered!(m)
        elseif m isa ACP.AgentMessage
            wait(m)
            t = strip(ACP.text(m))
            isempty(t) || record!(a, run.label, "say", t)
        elseif m isa ACP.ToolCall
            run.tools += 1
            # recorded when it ends: providers fill in the input (the command, the code) after the first frame
            tc = m
            t0 = time()
            errormonitor(@async begin
                wait(tc)
                kind = tc.status == "failed" ? "error" : "tool"
                record!(a, run.label, kind, tool_line(tc) * @sprintf(" (%.0f s%s)", time() - t0,
                                                                     tc.status == "failed" ? ", failed" : ""))
            end)
        elseif m isa ACP.Plan
            record!(a, run.label, "plan", join(("[$(e.status)] $(e.content)" for e in m.entries), "\n"))
        elseif m isa ACP.UsageUpdate
            # the API price equivalent, for the record only: the budget counts tokens (budget.jl)
            m.cost_amount === nothing || (run.cost = m.cost_amount)
        end
    end
end

"""
Send a message into a running turn if the provider supports it (active
steering), otherwise nothing happens and `false` is returned.
"""
function try_steer!(run::AgentRun, text::AbstractString)
    get(run.client.session_result, "bonitoActiveSteering", false) === true || return false
    return ACP.steer!(run.client, String(text))
end

function watchdog!(host, run::AgentRun, turn)
    grace = 240.0
    while !ACP.isover(turn)
        sleep(10)
        ACP.isover(turn) && break
        b = update_budget!(host.budget)
        left = run.deadline - time()
        reason = b["state"] == "exhausted" ? "the budget is used up" :
                 b["state"] == "low" ? "the budget is running low" :
                 left < 300 ? "the session time is nearly up" : ""
        if !isempty(reason) && run.wrap_up_since == 0
            run.wrap_up_since = time()
            steered = try_steer!(run, "Host: $reason. Finish what you are doing, commit it, write your journal entry and end the turn within a few minutes.")
            record!(host.activity, run.label, "host", "asked to wrap up ($reason)" * (steered ? "" : ", provider cannot take mid-turn messages"))
        end
        over = left < 0 || (run.wrap_up_since > 0 && time() - run.wrap_up_since > grace && b["state"] == "exhausted")
        if over && isempty(run.interrupted)
            run.interrupted = left < 0 ? "session time limit" : "budget used up"
            record!(host.activity, run.label, "host", "cancelled: $(run.interrupted)")
            ACP.cancel!(run.client)
        elseif !isempty(run.interrupted) && time() - max(run.deadline, run.wrap_up_since) > grace + 120
            record!(host.activity, run.label, "host", "closed: the agent did not stop after cancel")
            close(run.client)
            break
        end
        write_agent_status(host)
    end
end

"""
    run_agent!(host, role, settings, prompt; followups) -> AgentRun or nothing

One jailed session of `settings.provider`: `prompt`, then each prompt
`followups(run)` returns (e.g. messages the human sent meanwhile) until it
returns nothing. `nothing` when the session could not start (the reason is in
the activity feed).
"""
function run_agent!(host, role::Symbol, label::AbstractString, settings::AgentSettings, prompt::AbstractString;
                    followups = run -> nothing)
    jp, cfg = host.jp, host.cfg
    launch, why = provider_launch(jp, settings)
    if launch isa TokenExpiring
        # the reviews of session 39 were skipped for this: wait, as long as it takes
        record!(host.activity, label, "host", "waiting: $why")
        state = host.agent_state
        while launch isa TokenExpiring && host.running
            host.agent_state, host.agent_detail = "waiting_auth", why
            sleep(60)
            launch, why = provider_launch(jp, settings)
        end
        host.agent_state, host.agent_detail = state, ""
    end
    if !(launch isa Tuple)
        record!(host.activity, label, "host", "cannot start: $why")
        host.agent_detail = why
        return nothing
    end
    argv, env, path = launch
    host.proxy.allow = all_hosts(cfg)
    log = open(joinpath(jp.logs, "$(role).log"), "a")
    println(log, "\n==== ", now_string(), " ", label, " ", settings.provider, " ", settings.model, " ====")
    flush(log)
    cmd = pipeline(jailed(jp, cfg, role, argv; env, path, proxy = host.proxy); stderr = log)
    client = ACP.Client(ProcessTransport(cmd), jp.world, JailedHandler(); mcp_servers = [julia_mcp(jp), romeo_mcp(jp)], fs = false)
    close(log)
    problem = select_model!(client, settings.model)
    isempty(problem) || record!(host.activity, label, "host", problem)
    run = AgentRun(role, String(label), settings, client, time(), time() + 60settings.session_minutes, 0.0, 0, "", "", 0.0,
                   Task(nothing))
    run.consumer = errormonitor(@async consume!(host, run))
    host.current = run
    record!(host.activity, label, "host", "started $(settings.provider)" * (isempty(settings.model) ? "" : " ($(settings.model))"))
    next = String(prompt)
    try
        while next !== nothing
            turn = ACP.prompt!(client, next)
            dog = errormonitor(@async watchdog!(host, run, turn))
            result = try
                ACP.wait_turn!(turn)
            catch e
                # the agent died or answered the prompt with an error: the session is over
                e isa ACP.ConnectionClosed || e isa ErrorException || rethrow()
                run.interrupted = "agent error: " * first(sprint(showerror, e), 500)
                Dict{String,Any}("stopReason" => "error")
            end
            wait(dog)
            run.stop_reason = string(get(result, "stopReason", "?"))
            (!isempty(run.interrupted) || run.stop_reason != "end_turn" || time() > run.deadline) && break
            next = followups(run)
        end
    finally
        close(client)
        wait(run.consumer)
        host.current = nothing
    end
    record!(host.activity, label, "host", @sprintf("ended (%s) after %.1f min, %d tool calls",
                                                   isempty(run.interrupted) ? run.stop_reason : run.interrupted,
                                                   (time() - run.started) / 60, run.tools))
    return run
end
