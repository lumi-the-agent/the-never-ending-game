# ── The budget: tokens per rolling day ──────────────────────────────────────
#
# On a subscription nothing is billed; what is limited is how much of the plan
# the agents use. The host counts the tokens every agent session consumed (all
# roles together) from Claude Code's own transcripts in the jail homes, over a
# rolling 24 hours, against `tokens_per_day` in config.toml:
#
#     tokens = input + cache writes + output + cache reads × cache_read_weight
#
# (a cache read is a fraction of the cost of fresh input). Free models (OpenCode's
# `*-free`) do not count. When the day is spent no session starts until enough
# usage is older than 24 hours; the game and the worker keep running. Every
# session prompt says how much is left and when the next break ends, so the
# agent can put long worker jobs into the break.

struct Usage
    time::Float64       # unix seconds
    tokens::Float64     # weighted, see above
    raw::Int            # all tokens including cache reads
end

mutable struct Budget
    homes::Vector{String}             # jail homes whose ~/.claude/projects are read
    state_path::String                # .jail/run/budget.json
    cfg::HostConfig
    offsets::Dict{String,Int}         # bytes of each transcript already read
    seen::Set{String}                 # message ids already counted
    usage::Vector{Usage}              # last 24 h
end

Budget(jp::JailPaths, cfg::HostConfig) =
    Budget([home(jp, r) for r in ROLES], joinpath(jp.run, "budget.json"), cfg, Dict{String,Int}(), Set{String}(), Usage[])

"One assistant message's usage from a transcript line: `(id, Usage)` or nothing."
function parse_usage(line::AbstractString, cache_read_weight::Real)
    occursin("\"usage\"", line) || return nothing
    d = JSON.parse(line; dicttype = Dict{String,Any})
    get(d, "type", "") == "assistant" || return nothing
    m = d["message"]
    u = get(m, "usage", nothing)
    u === nothing && return nothing
    n(k) = Int(something(get(u, k, 0), 0))
    input, write_, read_, output = n("input_tokens"), n("cache_creation_input_tokens"), n("cache_read_input_tokens"), n("output_tokens")
    t = datetime2unix(DateTime(first(d["timestamp"], 23)))       # UTC
    return String(get(m, "id", "")), Usage(t, input + write_ + output + cache_read_weight * read_,
                                           input + write_ + output + read_)
end

"Read what the transcripts gained since the last call; forget usage older than a day."
function refresh!(b::Budget)
    for h in b.homes
        dir = joinpath(h, ".claude", "projects")
        isdir(dir) || continue
        for (root, _, files) in walkdir(dir), f in files
            endswith(f, ".jsonl") || continue
            path = joinpath(root, f)
            off = get(b.offsets, path, 0)
            filesize(path) <= off && continue
            open(path) do io
                seek(io, off)
                while !eof(io)
                    line = readline(io; keep = true)
                    endswith(line, '\n') || break        # still being written
                    off += sizeof(line)
                    r = parse_usage(line, b.cfg.cache_read_weight)
                    r === nothing && continue
                    id, u = r
                    (isempty(id) || id in b.seen) && continue
                    push!(b.seen, id)
                    push!(b.usage, u)
                end
            end
            b.offsets[path] = off
        end
    end
    filter!(u -> u.time > time() - 86400, b.usage)
    return b
end

"Tokens used since unix time `t`, for measuring one session (usage leaving the rolling day does not count against it)."
tokens_since(b::Budget, t::Real) = (refresh!(b); sum(u -> u.time >= t ? u.tokens : 0.0, b.usage; init = 0.0))

"When at least `need` of `cap` tokens are free again (unix time), given the usage in the window."
function free_again_at(b::Budget, cap::Float64, need::Real)
    free = cap - sum(u -> u.tokens, b.usage; init = 0.0)
    free >= need && return time()
    for u in sort(b.usage; by = u -> u.time)
        free += u.tokens
        free >= need && return u.time + 86400
    end
    return time() + 86400
end

"""
    summary(budget; session_tokens) -> Dict

Today's usage against the cap: `state` ("ok", "low", "exhausted"), how many
work cycles of `session_tokens` still fit and when the next one can start.
Without a cap (`tokens_per_day = 0`) the state is always "ok" and `limit_day`
is `nothing`.
"""
function summary(b::Budget; session_tokens::Real = 0)
    refresh!(b)
    return budget_summary(b.cfg.tokens_per_day, b, session_tokens)
end

function budget_summary(::Nothing, b::Budget, session_tokens::Real)
    return Dict{String,Any}(
        "state" => "ok", "fraction" => 0.0, "tokens_day" => sum(u -> u.tokens, b.usage; init = 0.0),
        "limit_day" => nothing, "raw_tokens_day" => sum(u -> u.raw, b.usage; init = 0),
        "session_tokens" => session_tokens, "updated" => now_string())
end

function budget_summary(cap::Float64, b::Budget, session_tokens::Real)
    used = sum(u -> u.tokens, b.usage; init = 0.0)
    raw = sum(u -> u.raw, b.usage; init = 0)
    frac = used / cap
    state = frac >= 1 ? "exhausted" : frac >= b.cfg.low_fraction ? "low" : "ok"
    per = session_tokens > 0 ? session_tokens : 0.1cap
    return Dict{String,Any}(
        "state" => state, "fraction" => frac, "tokens_day" => used, "limit_day" => cap, "raw_tokens_day" => raw,
        "session_tokens" => per, "sessions_left" => max(0, floor(Int, (cap - used) / per)),
        "next_session_at" => free_again_at(b, cap, per), "all_free_at" => free_again_at(b, cap, cap),
        "updated" => now_string())
end

function update_budget!(b::Budget; kw...)
    s = summary(b; kw...)
    write_json(b.state_path, s)
    return s
end

short_tokens(x::Real) = x >= 1e6 ? @sprintf("%.2fM", x / 1e6) : @sprintf("%.0fk", x / 1e3)
clock(t::Real) = Dates.format(unix2datetime(t) + (Dates.now() - Dates.now(Dates.UTC)), "HH:MM")
