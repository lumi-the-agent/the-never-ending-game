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
#
# Judged by premise alone, sessions 93-95 got off (3, 4): a shadow that runs off
# and a pocket watch that rewinds the island are different ideas, yet both are
# one more set-piece gag film, the sixth in ten posts. So the judge also groups
# the session's posts and the last `FORM_MEMORY` by form (what kind of change to
# the game, how it reaches the viewer, premise aside), and the host counts how
# many of those share a post's form (`form_score`); a post counts with the higher
# of its two numbers.

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

"How many of the last posts forms are counted over."
const FORM_MEMORY = 10

"A form `k` of the last `FORM_MEMORY` posts share, on the 0-10 scale: one is free, two cost most, three a tenth."
form_score(k::Integer) = k == 0 ? 0 : min(10, 2 + 2k)

"A title as a judge may write it: lowercase letters and digits only."
title_key(t) = lowercase(filter(c -> isletter(c) || isdigit(c), string(t)))

"The judge's settings: the reviewer's provider and model, a short session."
judge_settings(cfg::HostConfig) = AgentSettings(cfg.review.provider, cfg.review.model, 15.0)

"""
The earlier posts as the judges see them: the last `FORM_MEMORY` (the ones forms are counted
over) and the older ones, each in the plain words of the judge who saw it, then the last judge's
form groups.
"""
function earlier_post_lines(io::IO, m::AbstractDict, earlier)
    judged = Dict(s["title"] => s for s in get(m, "judged_posts", Any[]))
    line(p) = (j = get(judged, p.title, nothing);
               "- **$(p.title)**: " * (j === nothing ? p.caption : "$(j["what"]) ($(j["recipe"]))"))
    println(io, "## The last $FORM_MEMORY earlier posts (newest first; forms are counted over these)")
    foreach(p -> println(io, line(p)), first(earlier, FORM_MEMORY))
    if length(earlier) > FORM_MEMORY
        println(io, "\n## Older posts")
        foreach(p -> println(io, line(p)), earlier[FORM_MEMORY+1:end])
    end
    forms = get(m, "forms", Any[])
    if !isempty(forms)
        println(io, "\n## The last judge's forms")
        foreach(f -> println(io, "- $(f["form"]): ", join(f["posts"], ", ")), forms)
    end
    println(io)
end

function repetition_prompt(jp::JailPaths, n::Int, now, earlier, journal::AbstractString, out::AbstractString)
    io = IOBuffer()
    println(io, "# Repetition of session $n\n\nWrite your verdict to `$(out)`.\n")
    println(io, "## This session's posts")
    foreach(p -> println(io, "- **$(p.title)**: $(p.caption)"), now)
    println(io)
    films = [joinpath(site_dir(jp), f) for p in now for f in p.films]
    print(io, film_lines(filter(isfile, films), joinpath(reviews_dir(jp), "motion", @sprintf("session-%04d", n))))
    println(io, "## The author's journal for this session")
    println(io, isempty(strip(journal)) ? "(none)" : journal, "\n")
    earlier_post_lines(io, load_mood(jp), earlier)
    print(io, prompt_file("repetition.md"))
    return String(take!(io))
end

"""
    score_posts(v, verdicts, earlier) -> (groups, scored)

The judge's form `groups` from its verdict `v`, and each of this session's `verdicts` scored: its
`similarity`, how many of the last `FORM_MEMORY` `earlier` posts share its form group (`k`), and
the higher of the two as its `score`. A post the judge put in no group counts as a new form
(`grouped` false).
"""
function score_posts(v::AbstractDict, verdicts, earlier)
    groups = filter(g -> g isa AbstractDict && get(g, "form", nothing) isa AbstractString && get(g, "posts", nothing) isa AbstractVector,
                    get(v, "forms", Any[]))
    group_of = Dict(title_key(t) => g for g in groups for t in g["posts"])
    last_ten = Set(title_key(p.title) for p in first(earlier, FORM_MEMORY))
    scored = map(verdicts) do p
        g = get(group_of, title_key(get(p, "post", "")), nothing)
        k = g === nothing ? 0 : count(in(last_ten), unique(title_key.(g["posts"])))
        sim = clamp(p["similarity"], 0, 10)
        (; p, sim, k, grouped = g !== nothing, form = g === nothing ? "" : string(g["form"]), score = max(sim, form_score(k)))
    end
    return groups, scored
end

"""
    judge_repetition!(host, n, marks) -> Dict or nothing

After session `n`: how alike its posts (since the mood's `started`, which a cut-off session
keeps) are to the earlier ones, judged by a separate agent (`prompts/repetition.md`): by what
each is (`similarity`) and by form (the judge groups, the host counts how many of the last
`FORM_MEMORY` share it). A post counts with the higher of the two; the most original post
decides. No post: 10, nothing new. `nothing` without a usable verdict (noted in the activity feed).
"""
function judge_repetition!(host, n::Int, marks::Dict{String,Int})
    jp = host.jp
    since = datetime2unix(DateTime(load_mood(jp)["started"])) - local_utc_offset()
    ids = Set(p.id for p in session_posts(jp, since))
    if isempty(ids)
        record!(host.activity, "repetition of session $n", "review", "nothing posted: worth ×0.10")
        return Dict{String,Any}("session" => n, "score" => 10, "similarity" => 10, "post" => "", "nearest" => "",
                                "shared" => "nothing posted", "form" => "", "form_count" => 0, "forms" => Any[], "judged" => Any[])
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
    groups, scored = score_posts(v, verdicts, earlier)
    for x in scored
        x.grouped || record!(host.activity, label, "host", "the judge gave \"$(get(x.p, "post", ""))\" no form: counted as a new one")
    end
    best = argmin(x -> x.score, scored)
    rep = Dict{String,Any}("session" => n, "score" => best.score, "similarity" => best.sim, "post" => string(get(best.p, "post", "")),
                           "nearest" => string(get(best.p, "nearest", "")), "shared" => string(get(best.p, "shared", "")),
                           "form" => best.form, "form_count" => best.k,
                           "forms" => [Dict{String,Any}("form" => string(g["form"]), "posts" => string.(g["posts"])) for g in groups],
                           "judged" => [Dict{String,Any}("session" => n, "title" => string(get(x.p, "post", "")), "form" => x.form,
                                                         "what" => string(get(x.p, "what", "")), "recipe" => string(get(x.p, "recipe", "")))
                                        for x in scored])
    f = repeat_factor(best.score)
    record!(host.activity, label, "review", "$(rep["post"]): $(best.sim)/10 like $(rep["nearest"]) ($(rep["shared"])); " *
            "form \"$(best.form)\" shared by $(best.k) of the last $FORM_MEMORY" * (f < 1 ? @sprintf("; worth ×%.2f", f) : ""))
    return rep
end

"""
What a repeat does to a session's record and the mood (in `mood_session_end!`, before the
session is felt): points × `repeat_factor`, which also scales what its new happenings ease;
boredom up by `REPEAT_BOREDOM` × `repeat_share`, joy down by 0.2 × that. The judged posts join
the mood's catalogue of judged posts (the next judges compare with their plain descriptions), and
the judge's form groups replace the last ones (the next judge starts from them, the author sees them).
"""
function feel_repetition!(m::AbstractDict, r::AbstractDict, rep::AbstractDict)
    s = rep["score"]
    r["repeat_factor"] = repeat_factor(s)
    r["repetition"] = Dict{String,Any}(k => rep[k] for k in ("score", "similarity", "post", "nearest", "shared", "form", "form_count"))
    r["points"] = round(r["points"] * r["repeat_factor"]; digits = 1)
    m["boredom"] = round(clamp(m["boredom"] + REPEAT_BOREDOM * repeat_share(s), 0, 1); digits = 2)
    m["joy"] = round(clamp(m["joy"] - 0.2 * repeat_share(s), 0, 1); digits = 2)
    m["last_repetition"] = merge(r["repetition"], Dict{String,Any}("session" => rep["session"], "factor" => r["repeat_factor"]))
    isempty(rep["forms"]) || (m["forms"] = rep["forms"])
    judged = append!(get!(m, "judged_posts", Any[]), rep["judged"])
    length(judged) > 2POST_MEMORY && deleteat!(judged, 1:length(judged) - 2POST_MEMORY)
    return m
end
