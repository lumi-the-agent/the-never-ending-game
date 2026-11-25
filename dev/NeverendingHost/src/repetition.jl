# ── repetition: the same thing again is worth a tenth ───────────────────────
#
# Boredom (mood.jl) and the reviewer's surprise asked for new things, and the
# character delivered new event kinds: for twelve sessions (79-90) every post
# showed one recipe (the friends gather for a scripted event, something silly
# happens, everyone laughs, a short film), each counted as new, and the
# reviewer's 5-7 changed little. Now, after every session, a judge (a separate
# agent on the reviewer's model, never the author) compares the session's posts
# with the last `POST_MEMORY` posts by what their films show, and the host
# turns its similarity (0-10) into a penalty, like Pino's for doing the same
# again: from `SIMILAR[1]` on the session is worth less, from `SIMILAR[2]` on a
# tenth (its points and what its new happenings ease boredom), and boredom
# rises by up to `REPEAT_BOREDOM` on top. Everything made goes on the pages,
# finished, half done or failed, so the session's most original post decides:
# posting more never costs. A session that posts nothing is worth a tenth.

"How many earlier posts each session's posts are compared with."
const POST_MEMORY = 30
"The similarity (0-10) from which the penalty starts, and from which it is full."
const SIMILAR = (4, 7)
"The boredom a full repeat adds, on top of the session's usual rise."
const REPEAT_BOREDOM = 0.5

"How much of the penalty a similarity (0-10) brings: none up to 4, all of it from 7."
repeat_share(s::Real) = clamp((s - SIMILAR[1]) / (SIMILAR[2] - SIMILAR[1]), 0, 1)

"What a session with this similarity is worth: 1, down to a tenth for the same again."
repeat_factor(s::Real) = 10.0^(-repeat_share(s))

"The judge's settings: the reviewer's provider and model, a short session."
judge_settings(cfg::HostConfig) = AgentSettings(cfg.review.provider, cfg.review.model, 15.0)

function repetition_prompt(jp::JailPaths, n::Int, now, earlier, journal::AbstractString, out::AbstractString)
    m = load_mood(jp)
    judged = Dict(s["title"] => s for s in get(m, "judged_posts", Any[]))
    io = IOBuffer()
    println(io, "# Repetition of session $n\n\nWrite your verdict to `$(out)`.\n")
    println(io, "## This session's posts")
    foreach(p -> println(io, "- **$(p.title)**: $(p.caption)"), now)
    println(io)
    films = [joinpath(site_dir(jp), f) for p in now for f in p.films]
    print(io, film_lines(filter(isfile, films), joinpath(reviews_dir(jp), "motion", @sprintf("session-%04d", n))))
    println(io, "## The author's journal for this session")
    println(io, isempty(strip(journal)) ? "(none)" : journal, "\n")
    println(io, "## The island's earlier posts (newest first)")
    for p in earlier
        j = get(judged, p.title, nothing)
        println(io, "- **$(p.title)**: ", j === nothing ? p.caption : "$(j["what"]) ($(j["recipe"]))")
    end
    println(io)
    print(io, prompt_file("repetition.md"))
    return String(take!(io))
end

"""
    judge_repetition!(host, n, t0, marks) -> Dict or nothing

After session `n`: how alike its posts (since the mood's `started`, which a cut-off session
keeps) are to the earlier ones, judged by a separate agent (`prompts/repetition.md`). The most
original post decides: its score, the earlier post it is like and what they share, with every
post's plain description for the next judges. No post: 10, nothing new. `nothing` without a
usable verdict (noted in the activity feed).
"""
function judge_repetition!(host, n::Int, marks::Dict{String,Int})
    jp = host.jp
    since = datetime2unix(DateTime(load_mood(jp)["started"])) - local_utc_offset()
    ids = Set(p.id for p in session_posts(jp, since))
    if isempty(ids)
        record!(host.activity, "repetition of session $n", "review", "nothing posted: worth ×0.10")
        return Dict{String,Any}("session" => n, "score" => 10, "post" => "", "nearest" => "", "shared" => "nothing posted",
                                "judged" => Any[])
    end
    posts = recent_posts(jp; n = POST_MEMORY + length(ids))
    now = filter(p -> p.id in ids, posts)
    earlier = first(filter(p -> !(p.id in ids), posts), POST_MEMORY)
    out = review_path(jp, @sprintf("repetition-%04d", n))
    label = "repetition of session $n"
    prompt = repetition_prompt(jp, n, now, earlier, journal_since(jp, marks), out)
    run_agent!(host, :review, label, judge_settings(host.cfg), prompt) === nothing && return nothing
    v, why = read_agent_json(out)
    verdicts = v === nothing ? Any[] : filter(p -> p isa AbstractDict && get(p, "similarity", nothing) isa Real, get(v, "posts", Any[]))
    if isempty(verdicts)
        record!(host.activity, label, "host", "the judge wrote no usable verdict ($(isempty(why) ? "no scored post" : why))")
        return nothing
    end
    best = argmin(p -> p["similarity"], verdicts)
    s = clamp(best["similarity"], 0, 10)
    rep = Dict{String,Any}("session" => n, "score" => s, "post" => string(get(best, "post", "")),
                           "nearest" => string(get(best, "nearest", "")), "shared" => string(get(best, "shared", "")),
                           "judged" => [Dict{String,Any}("session" => n, "title" => string(get(p, "post", "")),
                                                         "what" => string(get(p, "what", "")), "recipe" => string(get(p, "recipe", "")))
                                        for p in verdicts])
    f = repeat_factor(s)
    record!(host.activity, label, "review", "$(rep["post"]): $(s)/10 like $(rep["nearest"]) ($(rep["shared"]))" *
            (f < 1 ? @sprintf("; worth ×%.2f", f) : ""))
    return rep
end

"""
What a repeat does to a session's record and the mood (in `mood_session_end!`, before the
session is felt): points × `repeat_factor`, which also scales what its new happenings ease;
boredom up by `REPEAT_BOREDOM` × `repeat_share`, joy down by 0.2 × that. The judged posts join
the mood's catalogue of judged posts (the next judges compare with their plain descriptions).
"""
function feel_repetition!(m::AbstractDict, r::AbstractDict, rep::AbstractDict)
    s = rep["score"]
    r["repeat_factor"] = repeat_factor(s)
    r["repetition"] = Dict{String,Any}(k => rep[k] for k in ("score", "post", "nearest", "shared"))
    r["points"] = round(r["points"] * r["repeat_factor"]; digits = 1)
    m["boredom"] = round(clamp(m["boredom"] + REPEAT_BOREDOM * repeat_share(s), 0, 1); digits = 2)
    m["joy"] = round(clamp(m["joy"] - 0.2 * repeat_share(s), 0, 1); digits = 2)
    m["last_repetition"] = merge(r["repetition"], Dict{String,Any}("session" => rep["session"], "factor" => r["repeat_factor"]))
    judged = append!(get!(m, "judged_posts", Any[]), rep["judged"])
    length(judged) > 2POST_MEMORY && deleteat!(judged, 1:length(judged) - 2POST_MEMORY)
    return m
end

"The prompt's lines on repetition: the rule and how the last judged session fared."
function repetition_lines(m::AbstractDict)
    io = IOBuffer()
    print(io, "After every session a judge compares what you made with your last $POST_MEMORY posts by what it is and does ",
          "(not by props, place or words). Your most original post decides, so posting everything you made never costs. ",
          "From $(SIMILAR[1])/10 alike on the session is worth less, from $(SIMILAR[2])/10 on a tenth, and boredom rises by up to ",
          "$REPEAT_BOREDOM more; a session that posts nothing is worth a tenth too.")
    lr = get(m, "last_repetition", nothing)
    lr === nothing && return String(take!(io))
    if isempty(lr["post"])
        @printf(io, "\nSession %d posted nothing", lr["session"])
    else
        @printf(io, "\nSession %d's most original post, \"%s\", was %s/10 alike to \"%s\" (%s)", lr["session"], lr["post"],
                lr["score"], lr["nearest"], lr["shared"])
    end
    print(io, lr["factor"] < 1 ? @sprintf(": worth ×%.2f.", lr["factor"]) : ": no penalty.")
    return String(take!(io))
end
