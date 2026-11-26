# ── ideas: pitched, criticised and sharpened before anything is built ──────────
#
# Sessions 92-95 wrote ten ideas into the diary and built the one wanted most.
# The radical ones on those lists (the island as a turtle that swims off to a new
# sea, a portal to a tiny island) never had a chance: the character took the one
# it could finish as one more scripted scene, and the judge only caught that
# after the session was spent. Now a session starts with rounds: the character
# pitches its ideas into `ideas/session-NNNN.json` and ends its turn; a critic (a
# separate agent on the reviewer's model, `prompts/ideas.md`) scores each the way
# the session will be judged afterwards (what it is and its form against the
# posts, the reviewer's surprise) and says what is predictable in it, never
# proposing one of its own; the host sends that back as the next turn. An idea
# passes with no repeat penalty, an expected surprise of `IDEA_BAR`, fun of `FUN_BAR`
# (judged by its goal: the mechanic a player gets) and real of `REAL_BAR`; after
# `IDEA_ROUNDS` rounds the strongest goes. While surprise alone
# decided, and "changing what the island is" scored highest, the ideas that went
# (sessions 109-116) wrecked the island: it drifted off, tipped and flooded, got
# buried in sand. Now new mechanisms (physics, particles, simulation) and
# refinements score high, wrecking it without anything to play is capped, and
# fun has to be there too. The rounds are kept outside the jail,
# by session, so a cut-off session goes on where it was.
#
# Before choosing, the session has time to look around (the workbench in
# curiosity.jl, RomeoDB, the checkouts); what it looks at, and whether an idea
# comes from there, is the character's. Only the ideas are judged.

"The surprise (0-10) the critic must expect for an idea to pass."
const IDEA_BAR = 7
"The fun (0-10) the critic must expect as well, judged by the idea's goal: the mechanic a player gets."
const FUN_BAR = 7
"How real (0-10) it must be, simulated rather than scripted (session 126: the game is an engineering project)."
const REAL_BAR = 7
"How many rounds of pitches the critic answers before the strongest idea goes."
const IDEA_ROUNDS = 3
"How often a turn may end without a new round before the session goes on without the critic."
const IDEA_REMINDERS = 2
"Where the character pitches session `n`'s ideas (in its world)."
ideas_path(jp::JailPaths, n::Int) = joinpath(jp.world, "ideas", @sprintf("session-%04d.json", n))

"The host's record of session `n`'s rounds (outside the jail: the critic's word stands)."
ideas_log_path(jp::JailPaths, n::Int) = joinpath(jp.state, "ideas", @sprintf("session-%04d.json", n))

function load_ideas_log(jp::JailPaths, n::Int)
    p = ideas_log_path(jp, n)
    isfile(p) && return read_json(p)
    return Dict{String,Any}("session" => n, "rounds" => Any[], "go" => false, "reminded" => 0)
end

save_ideas_log!(jp::JailPaths, log::AbstractDict) =
    (mkpath(dirname(ideas_log_path(jp, log["session"]))); write_json(ideas_log_path(jp, log["session"]), log))

"The latest session's rounds, or `nothing` before the first."
function last_ideas_log(jp::JailPaths)
    dir = joinpath(jp.state, "ideas")
    isdir(dir) || return nothing
    files = sort!(filter(f -> endswith(f, ".json"), readdir(dir)))
    isempty(files) && return nothing
    return read_json(joinpath(dir, last(files)))
end

"The ideas the character pitched for session `n`: `(ideas, \"\")`, or `(nothing, why)`."
function read_pitches(jp::JailPaths, n::Int)
    v, why = read_agent_json(ideas_path(jp, n))
    v === nothing && return nothing, why
    ideas = v isa AbstractDict ? get(v, "ideas", nothing) : nothing
    ideas isa AbstractVector || return nothing, "no \"ideas\" list"
    ok = [Dict{String,Any}("title" => String(strip(i["title"])), "idea" => String(strip(i["idea"])), "form" => string(get(i, "form", "")),
                           "goal" => string(get(i, "goal", "")))
          for i in ideas if i isa AbstractDict && get(i, "title", nothing) isa AbstractString && get(i, "idea", nothing) isa AbstractString]
    isempty(ok) && return nothing, "no idea with a \"title\" and an \"idea\""
    return ok, ""
end

function critic_prompt(jp::JailPaths, n::Int, round::Int, pitched, rounds, earlier, out::AbstractString)
    io = IOBuffer()
    println(io, "# Ideas for session $n, round $round of $IDEA_ROUNDS\n\nWrite your verdict to `$(out)`.\n")
    println(io, "## This round's ideas")
    foreach(i -> println(io, "- **$(i["title"])**", isempty(i["form"]) ? "" : " (form: $(i["form"]))", ": ", i["idea"],
                         isempty(i["goal"]) ? " Goal: none given." : " Goal: " * i["goal"]), pitched)
    println(io)
    if !isempty(rounds)
        println(io, "## Earlier rounds, and what the critic said")
        for (r, rd) in enumerate(rounds), i in rd["ideas"]
            println(io, "- round $r, **$(i["title"])**: $(i["idea"]) (surprise $(i["surprise"]): $(i["critique"]))")
        end
        println(io)
    end
    goals = goals_text(jp)
    isempty(goals) || println(io, goals, "\n")
    earlier_post_lines(io, load_mood(jp), earlier)
    print(io, named(prompt_file("ideas.md"), jp))
    return String(take!(io))
end

"""
    score_ideas(v, pitched, earlier) -> Vector{Dict}

The critic's verdict `v` on this round's `pitched` ideas, scored by the host as the session will
be: an idea's repeat penalty from the higher of its `similarity` and its form (how many of the last
`FORM_MEMORY` `earlier` posts are in `same_form`), its expected `surprise`, `fun` and `real`, and
whether it passes. A verdict without `fun` counts it as its surprise, one without `real` as 0.
"""
function score_ideas(v::AbstractDict, pitched, earlier)
    text = Dict(title_key(i["title"]) => i["idea"] for i in pitched)
    last_ten = Set(title_key(p.title) for p in first(earlier, FORM_MEMORY))
    verdicts = filter(i -> i isa AbstractDict && get(i, "similarity", nothing) isa Real && get(i, "surprise", nothing) isa Real,
                      get(v, "ideas", Any[]))
    return map(verdicts) do i
        same = get(i, "same_form", Any[])
        k = same isa AbstractVector ? count(in(last_ten), unique(title_key.(same))) : 0
        sim, surprise = clamp(i["similarity"], 0, 10), clamp(i["surprise"], 0, 10)
        f = get(i, "fun", nothing)
        fun = clamp(f isa Real ? f : surprise, 0, 10)
        r = get(i, "real", nothing)
        real = clamp(r isa Real ? r : 0, 0, 10)
        s = max(sim, form_score(k))
        title = string(get(i, "title", ""))
        Dict{String,Any}("title" => title, "idea" => get(text, title_key(title), ""), "similarity" => sim,
                         "nearest" => string(get(i, "nearest", "")), "form_count" => k, "surprise" => surprise, "fun" => fun, "real" => real,
                         "worth" => repeat_factor(s), "passes" => repeat_share(s) == 0 && surprise >= IDEA_BAR && fun >= FUN_BAR && real >= REAL_BAR,
                         "critique" => string(get(i, "critique", "")))
    end
end

"How strong an idea is when none passes: its surprise, fun and how real it is, less its repeat penalty."
strength(i::AbstractDict) = i["worth"] * (i["surprise"] + get(i, "fun", i["surprise"]) + get(i, "real", 0))

"An idea as the critic saw it, in a line."
function idea_line(i::AbstractDict)
    how = i["passes"] ? "passes" : i["worth"] < 1 ? @sprintf("would be worth ×%.2f", i["worth"]) :
          i["surprise"] < IDEA_BAR ? "too expected" : get(i, "real", 0) < REAL_BAR ? "not real enough" : "not fun enough"
    form = i["form_count"] == 0 ? "its form in none of your last $FORM_MEMORY posts" : "its form in $(i["form_count"]) of your last $FORM_MEMORY"
    return "- **$(i["title"])**: $(i["similarity"])/10 like \"$(i["nearest"])\", $form, surprise $(i["surprise"])/10, fun $(i["fun"])/10, real $(get(i, "real", 0))/10: $how. $(i["critique"])"
end

"What the character hears after a round: the critic's word on each idea, then pass, another round, or the strongest."
function critique_text(scored, round::Int, rel::AbstractString)
    io = IOBuffer()
    println(io, "## The critic on your ideas (round $round of $IDEA_ROUNDS)")
    foreach(i -> println(io, idea_line(i)), scored)
    passed = filter(i -> i["passes"], scored)
    then = "build it, film or path trace it, publish it and post it (rule 14), before anything else, and tell the human's " *
           "game what you are up to with `NeverendingGame.think!`."
    if !isempty(passed)
        print(io, "\nPassed: ", join(("\"$(i["title"])\"" for i in passed), ", "), ". Take the one of them you want most: ", then)
    elseif round < IDEA_ROUNDS
        print(io, "\nNone passed yet. The bar: nothing like your last posts in what it is or in its form, a surprise of ",
              "$IDEA_BAR, fun of $FUN_BAR and real of $REAL_BAR. Write round $(round + 1) into `$rel`: sharpen what the critic found ",
              "strong, drop the rest, and add new ones far from everything so far; then end your turn.")
    else
        best = argmax(strength, scored)
        print(io, "\nNone passed in $IDEA_ROUNDS rounds. The strongest is \"$(best["title"])\"; take it, or one without a ",
              "penalty you want more: ", then)
    end
    return String(take!(io))
end

"""
    ideas_followup(host, n, run) -> String or nothing

When a turn of session `n` ends before its idea is chosen: the critic's next round on the ideas
the character pitched (`ideas_path`), or a reminder to pitch them. `nothing` once an idea goes,
while the session wraps up, or after `IDEA_REMINDERS` turns without a new round (noted).
"""
function ideas_followup(host, n::Int, run)
    jp = host.jp
    run.wrap_up_since == 0 || return nothing
    log = load_ideas_log(jp, n)
    log["go"] && return nothing
    rel = relpath(ideas_path(jp, n), jp.world)
    label = "ideas for session $n"
    rounds = log["rounds"]
    pitched, why = read_pitches(jp, n)
    unchanged = pitched !== nothing && !isempty(rounds) && pitched == last(rounds)["pitched"]
    if pitched === nothing || unchanged
        if log["reminded"] >= IDEA_REMINDERS
            log["go"] = true
            save_ideas_log!(jp, log)
            record!(host.activity, label, "host", "no new round of ideas after $IDEA_REMINDERS reminders: the session goes on without the critic")
            return nothing
        end
        log["reminded"] += 1
        save_ideas_log!(jp, log)
        return unchanged ? "`$rel` has not changed since the critic answered: write round $(length(rounds) + 1) there, then end your turn." :
               "Your ideas for this session are not in `$rel` yet ($why): write them there (step 3 of Now), then end your turn; " *
               "the critic answers."
    end
    r = length(rounds) + 1
    out = review_path(jp, @sprintf("ideas-%04d-%d", n, r))
    rm(out; force = true)           # a round of a cut-off session's earlier run is not this one
    earlier = recent_posts(jp; n = POST_MEMORY)
    run_agent!(host, :review, "$label, round $r", judge_settings(host.cfg), critic_prompt(jp, n, r, pitched, rounds, earlier, out))
    v, why = read_agent_json(out)
    scored = v isa AbstractDict ? score_ideas(v, pitched, earlier) : Any[]
    if isempty(scored)
        log["go"] = true
        save_ideas_log!(jp, log)
        record!(host.activity, label, "host", "the critic gave no usable answer ($(isempty(why) ? "no scored idea" : why))")
        return "The critic gave no usable answer this time. Take the idea you want most and build it, film or " *
               "path trace it, publish it and post it (rule 14), before anything else."
    end
    push!(rounds, Dict{String,Any}("pitched" => pitched, "ideas" => scored, "time" => now_string()))
    passed = count(i -> i["passes"], scored)
    log["go"] = passed > 0 || r >= IDEA_ROUNDS
    save_ideas_log!(jp, log)
    best = argmax(strength, scored)
    record!(host.activity, "$label, round $r", "review",
            "$passed of $(length(scored)) passed; strongest \"$(best["title"])\" (surprise $(best["surprise"]))")
    return critique_text(scored, r, rel)
end
