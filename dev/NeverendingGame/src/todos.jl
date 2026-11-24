# ── The agent's todo list. It is never empty. ────────────────────────────────

mutable struct Todo
    id::Int
    title::String
    detail::String
    kind::Symbol          # :build :look :motion :world :feature :review :fix :explore :user
    status::Symbol        # :open :doing :done :dropped
    priority::Int         # 1 (urgent) … 5 (someday)
    source::Symbol        # :agent :user :system :review
    created::String
    updated::String
    est_minutes::Float64  # the agent's estimate before starting
    spent_minutes::Float64
    result::String        # what came out; media paths, verdicts
end

function Todo(id, title; detail = "", kind = :build, priority = 3, source = :agent, est_minutes = 15.0)
    now = string(Dates.now())
    return Todo(id, title, detail, kind, :open, priority, source, now, now, est_minutes, 0.0, "")
end

todo_dict(t::Todo) = Dict{String,Any}(String(f) => (v = getfield(t, f); v isa Symbol ? String(v) : v)
                                      for f in fieldnames(Todo))

function todo_from_dict(d::AbstractDict)
    now = string(Dates.now())
    return Todo(Int(d["id"]), d["title"], get(d, "detail", ""), Symbol(get(d, "kind", "build")),
                Symbol(get(d, "status", "open")), Int(get(d, "priority", 3)), Symbol(get(d, "source", "agent")),
                get(d, "created", now), get(d, "updated", now), Float64(get(d, "est_minutes", 15.0)),
                Float64(get(d, "spent_minutes", 0.0)), get(d, "result", ""))
end

# The list lives in `world/state/todos.json` and is changed by several processes
# (the game, the agent's Julia sessions), so every change is a locked
# read-modify-write of the file; nobody keeps a copy in memory.

function load_todos(path::AbstractString)
    isfile(path) || return Todo[]
    return [todo_from_dict(x) for x in read_json(path)["items"]]
end

save_todos(path::AbstractString, items::Vector{Todo}) =
    write_json(path, Dict("items" => [todo_dict(t) for t in sort(items; by = t -> t.id)]))

"""
    update_todos!(f, path) -> f(items)

Run `f` on the current list under a lock and save what it leaves.
"""
function update_todos!(f, path::AbstractString)
    mkpath(dirname(path))
    return FileWatching.Pidfile.mkpidlock(path * ".lock"; stale_age = 60) do
        items = load_todos(path)
        r = f(items)
        save_todos(path, items)
        r
    end
end

open_todos(items::Vector{Todo}) =
    sort!(filter(t -> t.status in (:open, :doing), items); by = t -> (t.status != :doing, t.priority, t.id))

function add_todo!(path::AbstractString, title::AbstractString; kw...)
    return update_todos!(path) do items
        t = Todo(isempty(items) ? 1 : maximum(t -> t.id, items) + 1, String(title); kw...)
        push!(items, t)
        t
    end
end

function set_status!(path::AbstractString, id::Integer, status::Symbol; result::AbstractString = "",
                     spent_minutes = nothing)
    return update_todos!(path) do items
        i = findfirst(t -> t.id == id, items)
        i === nothing && error("no todo #$id")
        t = items[i]
        t.status = status
        t.updated = string(Dates.now())
        isempty(result) || (t.result = isempty(t.result) ? String(result) : t.result * "\n" * result)
        spent_minutes === nothing || (t.spent_minutes += spent_minutes)
        t
    end
end

# Problems the game files (source :system) say what is broken NOW: they close
# when the thing they are about loads cleanly again, and a problem that comes
# back reopens its todo instead of filing a new one.

"""
    file_problem!(path, title, detail; kind) -> the todo, or `nothing` when it is already open

An open, urgent todo for a problem: a problem that was closed (fixed by the
agent or by `close_problems!`) and happens again reopens its todo.
"""
function file_problem!(path::AbstractString, title::AbstractString, detail::AbstractString; kind::Symbol = :fix)
    return update_todos!(path) do items
        any(t -> t.title == title && t.status in (:open, :doing), items) && return nothing
        i = findlast(t -> t.title == title && t.source == :system && t.status in (:done, :dropped), items)
        if i === nothing
            t = Todo(maximum(t -> t.id, items; init = 0) + 1, String(title); kind, priority = 1, source = :system)
            push!(items, t)
        else
            t = items[i]
            t.status, t.priority, t.updated = :open, 1, string(Dates.now())
            t.result *= "\nHappened again at $(t.updated)."
        end
        t.detail = first(String(detail), 3000)
        t
    end
end

"Close the open problems whose titles start with one of `prefixes`, saying `why`."
function close_problems!(path::AbstractString, prefixes::Vector{String}, why::AbstractString)
    return update_todos!(path) do items
        closed = filter(t -> t.source == :system && t.status in (:open, :doing) &&
                             any(x -> startswith(t.title, x), prefixes), items)
        for t in closed
            t.status, t.updated = :dropped, string(Dates.now())
            t.result *= (isempty(t.result) ? "" : "\n") * "Closed at $(t.updated): $(why)."
        end
        closed
    end
end
