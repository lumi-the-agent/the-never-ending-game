# ── The files the agent keeps in the world ──────────────────────────────────
#
#   world/state/todos.json      the todo list (written by NeverendingGame)
#   world/journal/<date>.md     one `## ` entry per piece of work
#   world/inbox/*.json          messages from the human, moved to inbox/read once delivered
#   world/outbox/*.json         messages from the agent to the human
#   world/reviews/*.json        verdicts of the review agent
#
# The host reads them to build prompts and status; they are written by jailed
# code, so a file that does not parse is reported, not trusted.

"""Parse an agent written JSON file: `(value, "")`, or `(nothing, why)` when it is missing or broken."""
function read_agent_json(path::AbstractString)
    isfile(path) || return nothing, "missing"
    text = read(path, String)
    value = try
        JSON.parse(text; dicttype = Dict{String,Any})
    catch e
        e isa ArgumentError || rethrow()
        return nothing, "does not parse: " * first(sprint(showerror, e), 300)
    end
    return value, ""
end

todos_path(jp::JailPaths) = joinpath(jp.world, "state", "todos.json")

function todo_items(jp::JailPaths)
    d, why = read_agent_json(todos_path(jp))
    d === nothing && return Dict{String,Any}[], why
    return Vector{Dict{String,Any}}(d["items"]), ""
end

"""
    update_todo_items!(f, jp) -> f(items)

Change the todo list under the lock NeverendingGame's `update_todos!` takes,
so the game or the agent writing at the same moment loses nothing.
"""
function update_todo_items!(f, jp::JailPaths)
    path = todos_path(jp)
    return Pidfile.mkpidlock(path * ".lock"; stale_age = 60) do
        items, why = todo_items(jp)
        isempty(why) || error("world/state/todos.json: $why")
        r = f(items)
        write_json(path, Dict("items" => sort!(items; by = t -> t["id"])))
        r
    end
end

is_open(t::AbstractDict) = t["status"] in ("open", "doing")

function open_todo_lines(jp::JailPaths; n::Int = 10)
    items, why = todo_items(jp)
    isempty(why) || why == "missing" || return ["(world/state/todos.json $why)"]
    open = filter(is_open, items)
    sort!(open; by = t -> (t["status"] != "doing", t["priority"], t["id"]))
    return [@sprintf("- #%d [p%d %s from %s%s] %s", t["id"], t["priority"], t["kind"], t["source"],
                     t["status"] == "doing" ? ", doing" : "", t["title"]) for t in first(open, n)]
end

"Seconds the local clock is ahead of UTC (todo timestamps are local)."
local_utc_offset() = round(Dates.value(Dates.now() - Dates.now(Dates.UTC)) / 1000)

journal_dir(jp::JailPaths) = joinpath(jp.world, "journal")

"Sizes of the journal files, to find what a session appended."
journal_marks(jp::JailPaths) =
    isdir(journal_dir(jp)) ? Dict(f => filesize(joinpath(journal_dir(jp), f)) for f in readdir(journal_dir(jp))) :
    Dict{String,Int}()

"Journal text appended since `marks`."
function journal_since(jp::JailPaths, marks::Dict{String,Int})
    io = IOBuffer()
    for (f, sz) in sort!(collect(journal_marks(jp)))
        before = get(marks, f, 0)
        sz > before || continue
        open(joinpath(journal_dir(jp), f)) do fio
            seek(fio, before)
            write(io, read(fio))
        end
    end
    return String(take!(io))
end

inbox_dir(jp::JailPaths) = joinpath(jp.world, "inbox")

"Messages from the human not yet delivered, oldest first (they stay until `mark_read!`)."
function unread_messages(jp::JailPaths)
    dir = inbox_dir(jp)
    isdir(dir) || return Pair{String,Dict{String,Any}}[]
    msgs = Pair{String,Dict{String,Any}}[]
    for f in sort!(filter(f -> endswith(f, ".json"), readdir(dir)))
        d, why = read_agent_json(joinpath(dir, f))
        push!(msgs, f => (d === nothing ? Dict{String,Any}("time" => "?", "text" => "(unreadable message: $why)") : d))
    end
    return msgs
end

"Whether an unread message from the human (the dashboard, a chat, the supervisor for them) waits in the inbox."
human_waiting(jp::JailPaths) = any(((_, m),) -> startswith(get(m, "from", "human"), "human"), unread_messages(jp))

function mark_read!(jp::JailPaths, names)
    dir = inbox_dir(jp)
    mkpath(joinpath(dir, "read"))
    for f in names
        # a message can be delivered twice in one session (prompt and follow up): it is read already
        isfile(joinpath(dir, f)) && mv(joinpath(dir, f), joinpath(dir, "read", f); force = true)
    end
end

"Write a message from the human into the agent's inbox."
function tell!(jp::JailPaths, text::AbstractString; from::AbstractString = "human")
    dir = inbox_dir(jp)
    mkpath(dir)
    name = Dates.format(Dates.now(), "yyyymmdd-HHMMSS-sss") * ".json"
    write_json(joinpath(dir, name), Dict("from" => from, "time" => now_string(), "text" => String(text)))
    return name
end

"Messages the agent wrote to the human, newest last."
function outbox(jp::JailPaths; n::Int = 20)
    dir = joinpath(jp.world, "outbox")
    isdir(dir) || return Dict{String,Any}[]
    files = sort!(filter(f -> endswith(f, ".json"), readdir(dir)))
    return [something(first(read_agent_json(joinpath(dir, f))), Dict{String,Any}("text" => "(unreadable)"))
            for f in last(files, n)]
end

goals_path(jp::JailPaths) = joinpath(jp.world, "GOALS.md")

"The human's standing goals (world/GOALS.md, read only for the agents), or empty."
goals_text(jp::JailPaths) = isfile(goals_path(jp)) ? strip(read(goals_path(jp), String)) : ""

wishes_path(jp::JailPaths) = joinpath(jp.world, "WISHES.md")

name_path(jp::JailPaths) = joinpath(jp.world, "NAME")

"""
    character_name(jp) -> String

The name of the island's main character, the agent itself (world/NAME, one line, the agent's
to change: it chooses its own name). Sprout, the name it was born with, until it has.
"""
character_name(jp::JailPaths) = isfile(name_path(jp)) ? String(strip(read(name_path(jp), String))) : "Sprout"

"""
`text` with its placeholders filled: `{{DIRECTION}}` with the human's direction for the game
(prompts/direction.md, shared by the rules and the critics), then `{{NAME}}` with the character's name.
"""
named(text::AbstractString, jp::JailPaths) =
    replace(replace(text, "{{DIRECTION}}" => strip(prompt_file("direction.md"))), "{{NAME}}" => character_name(jp))

"The character's own memory: what it chose to remember, the only thing of its past the session prompt shows."
memory_path(jp::JailPaths) = joinpath(jp.world, "MEMORY.md")

"How much of `memory_path` the session prompt shows, so the prompt does not grow with the character's past."
const MEMORY_CHARS = 4000

"The prompt's memory section: the first `MEMORY_CHARS` of what the character chose to remember."
function memory_lines(jp::JailPaths)
    text = isfile(memory_path(jp)) ? strip(read(memory_path(jp), String)) : ""
    io = IOBuffer()
    println(io, "## What you chose to remember (`world/MEMORY.md`, the first $MEMORY_CHARS characters)")
    print(io, isempty(text) ? "(nothing yet)" : first(text, MEMORY_CHARS))
    length(text) > MEMORY_CHARS && print(io, "\n[cut here: the rest is not shown]")
    return String(take!(io))
end

reviews_dir(jp::JailPaths) = joinpath(jp.world, "reviews")

"Reviews whose findings the implementer has not addressed yet."
function open_reviews(jp::JailPaths)
    dir = reviews_dir(jp)
    isdir(dir) || return Dict{String,Any}[]
    out = Dict{String,Any}[]
    for f in sort!(filter(f -> endswith(f, ".json"), readdir(dir)))
        d, why = read_agent_json(joinpath(dir, f))
        d === nothing && continue
        get(d, "addressed", false) === true && continue
        get(d, "verdict", "pass") == "pass" && isempty(get(d, "findings", [])) && continue
        d["file"] = f
        push!(out, d)
    end
    return out
end

# ── what a session changed ───────────────────────────────────────────────────

const SKIP_DIRS = ("log", "media", "run", "snapshots", "inbox", "jobs", ".git", "frames")

"`path => (mtime, size)` for every file under `dirs`, skipping logs, media and sockets."
function file_manifest(dirs::Vector{String})
    m = Dict{String,Tuple{Float64,Int}}()
    for d in dirs
        isdir(d) || continue
        for (root, subdirs, files) in walkdir(d)
            filter!(s -> !(s in SKIP_DIRS), subdirs)
            for f in files
                p = joinpath(root, f)
                st = stat(p)
                isfile(st) && (m[p] = (st.mtime, st.size))
            end
        end
    end
    return m
end

function changed_files(before::Dict, after::Dict)
    changed = sort!([p for (p, v) in after if get(before, p, nothing) != v])
    removed = sort!([p for p in keys(before) if !haskey(after, p)])
    return changed, removed
end

watched_dirs(jp::JailPaths) = [jp.world, joinpath(jp.root, "dev", "NeverendingGame")]
