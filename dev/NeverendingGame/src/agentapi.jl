# ── What the agent calls from its Julia session ─────────────────────────────
#
#   todos(); todo!("title"; detail, kind, priority); doing!(id); done!(id, "result with evidence")
#   journal!("title", "what I did, what I learned, what is next")
#   think!("building a lookout bench on the hill")    Lumi's thought bubble
#   say_to_human("…")
#   live_status(), live_eval(code), live_screenshot(path), live_reload()   (live.jl: your sandbox game;
#   `game = :live` looks at the human's)
#   publish(; why)                                                         (publish.jl)
#   submit_job(:asset; prompt = "…"), job(id), wait_job(id)                (assets.jl)
#
# All of them work on `game_root()`, so they need no setup.

world_paths() = GamePaths(game_root())
todos_file() = todos_file(world_paths())

"The open todos, most urgent first."
todos() = open_todos(load_todos(todos_file()))

"""
    todo!(title; detail = "", kind = :build, priority = 3, est_minutes = 15) -> Todo

Add a todo. `kind`: :build :look :motion :world :feature :review :fix :perf :explore.
Priority 1 is urgent, 5 is someday.
"""
todo!(title::AbstractString; kw...) = add_todo!(todos_file(), title; source = :agent, kw...)

"Mark todo `id` as being worked on."
doing!(id::Integer) = set_status!(todos_file(), id, :doing)

"""
    done!(id, result)

Mark todo `id` done. `result` says what came out and where the evidence is
(screenshot paths, frame times): the reviewer reads it.
"""
done!(id::Integer, result::AbstractString; spent_minutes = nothing) =
    set_status!(todos_file(), id, :done; result, spent_minutes)

"Drop todo `id` (with the reason in `result`)."
drop!(id::Integer, result::AbstractString) = set_status!(todos_file(), id, :dropped; result)

"""
    think!(text)

What Lumi is making right now, in Lumi's voice and in a player's words
("building a lookout bench on the hill"): its thought bubble in the human's
game shows it for three hours. Say what you make, never how (no plugin, test
or fix talk). Call it whenever you start on something.
"""
think!(text::AbstractString) =
    write_json(thought_file(world_paths()), Dict("text" => String(text), "unix" => time(), "time" => string(Dates.now())))

"""
    journal!(title, text)

Append an entry to today's journal (`world/journal/<date>.md`). The next
session starts with the last entry, so write what you did, what you learned
and what comes next.
"""
function journal!(title::AbstractString, text::AbstractString)
    dir = joinpath(world_paths().world, "journal")
    mkpath(dir)
    open(joinpath(dir, "$(Dates.today()).md"), "a") do io
        println(io, "\n## ", Dates.format(Dates.now(), "HH:MM"), " · ", title, "\n")
        println(io, strip(text))
    end
    return nothing
end

"""
    say_to_human(text)

A message for the human: shown on the dashboard and kept in `world/outbox`.
"""
function say_to_human(text::AbstractString)
    dir = joinpath(world_paths().world, "outbox")
    mkpath(dir)
    name = Dates.format(Dates.now(), "yyyymmdd-HHMMSS-sss") * ".json"
    write_json(joinpath(dir, name), Dict("time" => string(Dates.now()), "text" => String(text)))
    return name
end
