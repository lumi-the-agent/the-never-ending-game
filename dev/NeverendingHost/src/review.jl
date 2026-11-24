# ── Review: other agents judge the work, without the author's context ───────
#
# There is no regression suite and no tester: the character plays its own game
# as a player at the start of every session (prompts/session.md) and judges it
# by its own taste.
#
# After a work session that finished todos or changed files, a reviewer
# session starts in its own jail (read only except world/reviews), usually
# with another model. It gets what a player or maintainer would get: the todo,
# the author's journal claims, the list of changed files and the sandbox game,
# never the author's conversation. It writes a verdict file; findings that are
# not `pass` go to the top of the author's next session prompt and stay there
# until the author marks the review addressed.
#
# Every few sessions a perfectionist review (art director, game designer and
# demanding player in one) scores the whole game 0-10 per category against the
# bar of a game people would pay for. The scores go to world/reviews/quality.jsonl,
# so every session prompt shows where the game stands, what moved and what is
# weakest; the findings become the author's next todos.

prompt_file(name::AbstractString) = read(joinpath(@__DIR__, "..", "prompts", name), String)

function review_path(jp::JailPaths, name::AbstractString)
    mkpath(reviews_dir(jp))
    return joinpath(reviews_dir(jp), name * ".json")
end

function short_path(jp::JailPaths, p::AbstractString)
    return startswith(p, jp.root) ? relpath(p, jp.root) : p
end

function work_review_prompt(host, n::Int, done::Vector, journal::AbstractString, changed::Vector{String},
                            removed::Vector{String}, out::AbstractString)
    jp = host.jp
    io = IOBuffer()
    println(io, "# Review of work session $n\n")
    println(io, "Write your verdict to `$(out)`.\n")
    if !isempty(done)
        println(io, "## Todos the author marked done")
        for t in done
            println(io, "- #$(t["id"]) $(t["title"])")
            isempty(t["detail"]) || println(io, "  detail: ", t["detail"])
            isempty(t["result"]) || println(io, "  author's result: ", t["result"])
        end
        println(io)
    end
    println(io, "## The author's journal for this session")
    println(io, isempty(strip(journal)) ? "(the author wrote no journal entry: that is itself a finding)" : journal)
    println(io)
    println(io, "## Files changed ($(length(changed)))")
    foreach(p -> println(io, "- ", short_path(jp, p)), first(changed, 80))
    length(changed) > 80 && println(io, "- … and $(length(changed) - 80) more")
    isempty(removed) || (println(io, "\nRemoved:"); foreach(p -> println(io, "- ", short_path(jp, p)), removed))
    println(io)
    print(io, prompt_file("reviewer.md"), "\n", prompt_file("review.md"))
    return String(take!(io))
end

function perfectionist_prompt(jp::JailPaths, n::Int, out::AbstractString)
    io = IOBuffer()
    println(io, "# Perfectionist review after session $n\n\nWrite your verdict to `$(out)`.\n")
    sc = scorecard_lines(jp)
    isempty(sc) || println(io, "## The scores so far (world/reviews/quality.jsonl)\n", sc, "\n")
    goals = goals_text(jp)
    isempty(goals) || println(io, goals, "\n")
    pl = progress_lines(jp)
    isempty(pl) || println(io, pl, " Compare the latest with the first and with the one at the previous perfectionist review.\n")
    println(io, "## The author's open todos (world/state/todos.json)")
    foreach(t -> println(io, t), open_todo_lines(jp; n = typemax(Int)))
    println(io)
    print(io, prompt_file("reviewer.md"), "\n", prompt_file("perfectionist.md"))
    return String(take!(io))
end

function run_review!(host, label::AbstractString, prompt::AbstractString, out::AbstractString;
                     settings::AgentSettings = host.cfg.review, followups = run -> nothing)
    host.reviews += 1
    run = run_agent!(host, :review, label, settings, prompt; followups)
    run === nothing && return nothing
    verdict, why = read_agent_json(out)
    if verdict === nothing
        record!(host.activity, label, "host", "the reviewer wrote no usable verdict ($why)")
        return nothing
    end
    nf = length(get(verdict, "findings", []))
    record!(host.activity, label, "review", "$(get(verdict, "verdict", "?")): $(get(verdict, "summary", "")) ($nf findings)")
    return verdict
end

function review_work!(host, n::Int, t0::Real, marks::Dict{String,Int}, before::Dict)
    jp = host.jp
    done = todos_done_since(jp, t0)
    changed, removed = changed_files(before, file_manifest(watched_dirs(jp)))
    filter!(p -> !startswith(p, reviews_dir(jp)), changed)
    isempty(done) && isempty(changed) && return nothing
    out = review_path(jp, @sprintf("session-%04d", n))
    prompt = work_review_prompt(host, n, done, journal_since(jp, marks), changed, removed, out)
    return run_review!(host, "review of session $n", prompt, out; followups = own_eyes(jp))
end

"""
A follow-up for a review that took no screenshot of its own (no new image
under `world/reviews/`), once: the review of session 38 judged the new sea
from the author's screenshots only.
"""
function own_eyes(jp::JailPaths)
    asked = Ref(false)
    return function (run)
        asked[] && return nothing
        for (dir, _, files) in walkdir(reviews_dir(jp)), f in files
            endswith(f, ".png") && mtime(joinpath(dir, f)) >= run.started && return nothing
        end
        asked[] = true
        return "Your verdict rests on the author's evidence only: you took no screenshot of your own. Take live " *
               "screenshots of what this session changed (`NeverendingGame.live_screenshot(\"world/reviews/<name>.png\")`, " *
               "other cameras or times of day where it matters), look at them, then rewrite the verdict file."
    end
end

"The session of the latest perfectionist verdict in `world/reviews` (0 before the first)."
function last_perfectionist(jp::JailPaths)
    ns = (match(r"^perfectionist-(\d+)\.json$", f) for f in readdir(reviews_dir(jp)))
    return maximum((parse(Int, m[1]) for m in ns if m !== nothing); init = 0)
end

function perfectionist!(host, n::Int)
    jp = host.jp
    out = review_path(jp, @sprintf("perfectionist-%04d", n))
    verdict = run_review!(host, "perfectionist review after session $n", perfectionist_prompt(jp, n, out), out;
                          settings = host.cfg.perfectionist, followups = look_closer())
    verdict === nothing && return nothing
    record_scores!(jp, n, verdict)
    supersede_reviews!(jp, basename(out))
    r = file_findings!(jp, first(splitext(basename(out))), verdict)
    record!(host.activity, "perfectionist review after session $n", "host",
            "todos: $(r.closed) closed as done, stale or duplicate, $(r.kept) kept or filed, $(r.superseded) superseded")
    return verdict
end

"""
Close every open review but `keep`: a perfectionist review judges the whole
game, so what still matters from earlier reviews is in its findings, and the
author starts from one list instead of a backlog of nits.
"""
function supersede_reviews!(jp::JailPaths, keep::AbstractString)
    for r in open_reviews(jp)
        r["file"] == keep && continue
        path = joinpath(reviews_dir(jp), r["file"])
        d = read_json(path)
        d["addressed"] = true
        d["superseded_by"] = keep
        write_json(path, d)
    end
end

severity_priority(s::AbstractString) = s == "high" ? 1 : s == "low" ? 3 : 2

"A todo id as a reviewer writes it: 140, \"140\", \"#140\" or null (0: no todo)."
todo_id(x::Integer) = Int(x)
todo_id(x::AbstractString) = something(tryparse(Int, lstrip(strip(x), '#')), 0)
todo_id(::Nothing) = 0

"""
    file_findings!(jp, review, verdict)

The perfectionist owns the review part of the todo list, as it owns the open
reviews (`supersede_reviews!`): the todos it closes in `todos` are closed with
its reason, each finding updates the open todo it names in `todo` or becomes a
new one (the named one takes the finding's title), and the open review todos
it neither names nor keeps are superseded.
So the list does not grow by eight copies of the same complaints every round.
"""
function file_findings!(jp::JailPaths, review::AbstractString, verdict::AbstractDict)
    stamp = string(Dates.now())
    note!(t, text) = (t["result"] = isempty(t["result"]) ? text : t["result"] * "\n" * text; t["updated"] = stamp)
    return update_todo_items!(jp) do items
        byid = Dict{Int,Dict{String,Any}}(t["id"] => t for t in items)
        named(id) = (t = get(byid, id, nothing); t !== nothing && is_open(t) ? t : nothing)
        kept = Set{Int}()
        closed = 0
        for c in get(verdict, "todos", [])
            t = named(todo_id(get(c, "id", nothing)))
            t === nothing && continue
            action = get(c, "action", "")
            if action == "keep"
                push!(kept, t["id"])
                isempty(get(c, "title", "")) || (t["title"] = first(c["title"], 100); t["updated"] = stamp)
            elseif action in ("done", "drop")
                t["status"] = action == "done" ? "done" : "dropped"
                note!(t, "$(review): $(get(c, "why", ""))")
                closed += 1
            end
        end
        next = maximum(t -> t["id"], items; init = 0)
        for f in get(verdict, "findings", [])
            what = get(f, "what", "")
            parts = ["$(label): $(get(f, key, ""))" for (label, key) in
                     (("Where", "where"), ("Suggestion", "suggestion"), ("Done when", "done_when"), ("Evidence", "evidence"))
                     if !isempty(get(f, key, ""))]
            detail = join(["$(review) [$(get(f, "category", "?")), $(get(f, "severity", "?"))]: $(what)"; parts], "\n")
            priority = severity_priority(get(f, "severity", "medium"))
            t = named(todo_id(get(f, "todo", nothing)))
            if t === nothing
                next += 1
                t = Dict{String,Any}("id" => next, "status" => "open", "created" => stamp,
                                     "est_minutes" => 30.0, "spent_minutes" => 0.0, "result" => "")
                push!(items, t)
                byid[next] = t
            end
            # a named todo takes the finding's current words: its old title may say what is no longer true
            t["title"], t["kind"], t["source"] = first(get(f, "title", what), 100), "review", "review"
            t["detail"], t["priority"], t["updated"] = detail, priority, stamp
            push!(kept, t["id"])
        end
        # review todos: filed by the host, or by the author from a review (kind review)
        superseded = filter(t -> t["status"] == "open" && "review" in (t["source"], t["kind"]) && !(t["id"] in kept), items)
        for t in superseded
            t["status"] = "dropped"
            note!(t, "Superseded by $(review).")
        end
        (; closed, kept = length(kept), superseded = length(superseded))
    end
end

"""
A follow-up for a perfectionist review that ends within eight minutes, once:
the second one ever judged the game in 1.7 minutes without playing anything.
"""
function look_closer()
    asked = Ref(false)
    return function (run)
        (asked[] || time() - run.started > 8 * 60) && return nothing
        asked[] = true
        return "You ended after $(round(Int, (time() - run.started) / 60)) minutes. A perfectionist review plays every mini " *
               "game through `interact!` for a minute, looks at the latest progress shots next to older ones, " *
               "and takes its own screenshots in every camera mode. Do what you skipped, then rewrite the verdict file."
    end
end

# ── the scorecard ────────────────────────────────────────────────────────────

quality_log(jp::JailPaths) = joinpath(reviews_dir(jp), "quality.jsonl")

"Append a perfectionist verdict's scores (`category => 0-10`) to the scorecard."
function record_scores!(jp::JailPaths, n::Int, verdict::AbstractDict)
    scores = Dict{String,Any}(k => v["score"] for (k, v) in get(verdict, "scores", Dict()) if v isa AbstractDict && haskey(v, "score"))
    isempty(scores) && return nothing
    append_jsonl(quality_log(jp), Dict("session" => n, "time" => now_string(), "scores" => scores))
end

"Every scorecard entry, oldest first."
function quality_history(jp::JailPaths)
    path = quality_log(jp)
    isfile(path) || return Dict{String,Any}[]
    return [JSON.parse(l; dicttype = Dict{String,Any}) for l in eachline(path) if !isempty(strip(l))]
end

"The latest perfectionist scores (`category => 0-10`), empty before the first review."
latest_scores(jp::JailPaths) = (h = quality_history(jp); isempty(h) ? Dict{String,Any}() : last(h)["scores"])

"""
The latest scores, weakest first, with the change since the review before
(`lighting 4 (+1)`). Empty before the first perfectionist review.
"""
function scorecard_lines(jp::JailPaths)
    h = quality_history(jp)
    isempty(h) && return ""
    cur = last(h)["scores"]
    prev = length(h) > 1 ? h[end - 1]["scores"] : Dict{String,Any}()
    io = IOBuffer()
    println(io, "After session $(last(h)["session"]) (", length(h) == 1 ? "the first review" : "$(length(h)) reviews so far",
            "), 0-10, weakest first:")
    for (k, v) in sort!(collect(cur); by = last)
        d = haskey(prev, k) ? v - prev[k] : nothing
        print(io, "- $k: $v")
        d === nothing || d == 0 || print(io, d > 0 ? " (+$d)" : " ($d)")
        println(io)
    end
    return String(take!(io))
end
