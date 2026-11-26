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

"Todos marked done after unix time `t0`."
function todos_done_since(jp::JailPaths, t0::Real)
    items, _ = todo_items(jp)
    return filter(items) do t
        t["status"] == "done" || return false
        updated = DateTime(first(t["updated"], 19))
        return datetime2unix(updated) - local_utc_offset() >= t0
    end
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

"The last `## ` entry of the newest journal file."
function last_journal_entry(jp::JailPaths; maxchars::Int = 2500)
    dir = journal_dir(jp)
    isdir(dir) || return ""
    files = sort!(filter(f -> endswith(f, ".md"), readdir(dir)))
    isempty(files) && return ""
    text = read(joinpath(dir, last(files)), String)
    i = findlast("\n## ", "\n" * text)
    entry = i === nothing ? text : text[first(i):end]
    return first(strip(entry), maxchars)
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

"`text` with `{{NAME}}` put in for the character's name (the prompts are written that way)."
named(text::AbstractString, jp::JailPaths) = replace(text, "{{NAME}}" => character_name(jp))

"A wish that says it came true (\"half came true\" is still open)."
const CAME_TRUE = r"(?<!half )came true"i

"The lines of a wish list as items: a heading, a wish (`- ` with its indented lines) or any other line."
function wish_items(text::AbstractString)
    items = Vector{String}[]
    for line in eachline(IOBuffer(text))
        if !isempty(items) && startswith(first(last(items)), "- ") && occursin(r"^\s+\S", line)
            push!(last(items), line)
        else
            push!(items, [line])
        end
    end
    return items
end

"A wish without its story: its lines joined, up to the first parenthesis (where what came of it starts)."
wish_line(item::Vector{String}) = rstrip(first(split(join(strip.(item), " "), " ("; limit = 2)))

"""
    open_wishes(text) -> String

The wish list `text` (world/WISHES.md) without the wishes that came true and without `## Done`:
the title and intro, then each section that still has an open wish, with those wishes, one line
each without what came of them so far.
"""
function open_wishes(text::AbstractString)
    io = IOBuffer()
    heading, sections, done = nothing, false, false
    for item in wish_items(text)
        line = first(item)
        if startswith(line, "## ")
            heading, sections, done = line, true, strip(line) == "## Done"
        elseif startswith(line, "- ")
            (done || any(l -> occursin(CAME_TRUE, l), item)) && continue
            heading === nothing || (println(io, "\n", heading); heading = nothing)
            println(io, wish_line(item))
        elseif !sections
            println(io, line)
        end
    end
    return strip(String(take!(io)))
end

"""
The character's open wishes (world/WISHES.md, the agent's to change; the human's goal 5), for the
session prompt. The ones that came true stay in the file only: with thirty stories of wishes come
true the whole file was most of what the character read before choosing what to make, and each new
idea came out as one more of them, filed under a new heading.
"""
function wishes_text(jp::JailPaths)
    name = character_name(jp)
    isfile(wishes_path(jp)) ||
        return "## $(name)'s wishes\n\nThere is no `world/WISHES.md` yet: write it this session, in $(name)'s voice (goal 5)."
    return open_wishes(read(wishes_path(jp), String)) *
           "\n\nWhat came of these so far, and the wishes that came true, are in `world/WISHES.md`."
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
