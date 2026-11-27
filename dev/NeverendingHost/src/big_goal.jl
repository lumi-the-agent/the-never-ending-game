# ── the big goal: one aim above the projects, passed by a critic ────────────────
#
# Nov 27: fifteen projects, none finished, each a film of its own, nothing above them. Rule 9
# then asked for a big goal of the character's own (`world/BIG_GOAL.md`), and the first one,
# written in two minutes, was "Everything I make with my hands keeps what I did to it": a
# principle, not a game anyone would remember, clip or play for hours. Now a big goal counts
# only once a critic (`prompts/big_goal.md`, on the reviewer's model) has passed it: the
# character pitches candidates into `world/ideas/big-goal.json` and ends its turn, the critic
# scores each (`BIG_GOAL_SCORES`), and the rounds go on (at least `BIG_GOAL_MIN_ROUNDS`, at most
# `BIG_GOAL_SESSION_ROUNDS` a session, across sessions until one passes). The host writes the
# strongest that passes into `BIG_GOAL.md`: its head (title, pitch, play, the moment) and under
# `## Road` a checklist of the steps to it. The head stays as the critic passed it (a changed
# head goes back to the critic); the road is the character's to work through: tick steps off,
# add, split and nest them, within `ROAD_ITEMS` lines of `ROAD_LINE` characters, so it never
# becomes pages of text. The rounds are kept outside the jail.

"What a big goal must score (0-10) on each of `BIG_GOAL_SCORES` to pass."
const BIG_GOAL_BAR = 8
"How many rounds a big goal goes through at least, however early one passes."
const BIG_GOAL_MIN_ROUNDS = 3
"How many rounds the critic answers in one session; the search goes on the next session."
const BIG_GOAL_SESSION_ROUNDS = 5
"How often a turn may end without a new round before the session goes on without the critic."
const BIG_GOAL_REMINDERS = 2
"How many of the earlier rounds the critic sees."
const BIG_GOAL_SHOWN_ROUNDS = 4
"How much of the big goal's head the prompts show."
const BIG_GOAL_CHARS = 1500
"The scores a big goal is judged on (`fit`: whether it leads where the human wants the game to go)."
const BIG_GOAL_SCORES = ("clear", "memorable", "shareable", "play", "fit")
"How many lines the road may have, done ones included, and how long one may be."
const ROAD_ITEMS = 30
const ROAD_LINE = 160
"The heading the road starts under."
const ROAD_HEADING = "## Road"

big_goal_path(jp::JailPaths) = joinpath(jp.world, "BIG_GOAL.md")
"Where the character pitches its big goals (in its world)."
big_goal_pitch_path(jp::JailPaths) = joinpath(jp.world, "ideas", "big-goal.json")
"The host's record of the rounds and of the big goal that passed (outside the jail: the critic's word stands)."
big_goal_log_path(jp::JailPaths) = joinpath(jp.state, "big_goal.json")

big_goal_text(jp::JailPaths) = isfile(big_goal_path(jp)) ? String(strip(read(big_goal_path(jp), String))) : ""

"The big goal's head (all before the road) and its road (the lines under `ROAD_HEADING`)."
function split_big_goal(text::AbstractString)
    i = findfirst(ROAD_HEADING, text)
    i === nothing && return String(strip(text)), ""
    return String(strip(text[1:prevind(text, first(i))])), String(strip(text[nextind(text, last(i)):end]))
end

"""
    road_items(road) -> Vector{NamedTuple}

The road's checklist lines (`- [ ] step`, `- [x] step`, nested by two spaces a level): each one's
depth, whether it is done and its text. Other lines are not steps.
"""
function road_items(road::AbstractString)
    items = NamedTuple{(:depth, :done, :text),Tuple{Int,Bool,String}}[]
    for line in eachsplit(road, '\n')
        m = match(r"^(\s*)[-*] \[([ xX])\] (.+)$", line)
        m === nothing && continue
        push!(items, (depth = length(m[1]) ÷ 2, done = m[2] != " ", text = String(strip(m[3]))))
    end
    return items
end

function load_big_goal_log(jp::JailPaths)
    p = big_goal_log_path(jp)
    isfile(p) && return read_json(p)
    return Dict{String,Any}("approved" => nothing, "rounds" => Any[], "session" => 0, "session_rounds" => 0, "reminded" => 0)
end

save_big_goal_log!(jp::JailPaths, log::AbstractDict) = write_json(big_goal_log_path(jp), log)

"Whether the head of `BIG_GOAL.md` is the big goal the critic passed, as the host wrote it."
big_goal_passed(jp::JailPaths, log::AbstractDict = load_big_goal_log(jp)) =
    log["approved"] !== nothing && log["approved"]["head"] == first(split_big_goal(big_goal_text(jp)))

"""
The prompts' big goal section (for the character, and for the idea critic as the character's):
the head, and the road's open steps (the done ones counted), with what is wrong with the road's size.
"""
function big_goal_lines(jp::JailPaths; whose::AbstractString = "Your")
    head, road = split_big_goal(big_goal_text(jp))
    log = load_big_goal_log(jp)
    io = IOBuffer()
    println(io, "## $whose big goal (`world/BIG_GOAL.md`, ",
            big_goal_passed(jp, log) ? "passed by the critic in session $(log["approved"]["session"]))" :
            "not passed by the critic yet: step 3 of Now)")
    print(io, isempty(head) ? "(none yet)" : first(head, BIG_GOAL_CHARS))
    items = road_items(road)
    isempty(items) && return String(take!(io))
    done = count(i -> i.done, items)
    println(io, "\n\nThe road ($done of $(length(items)) steps done):")
    foreach(i -> println(io, "  "^i.depth, "- [ ] ", first(i.text, ROAD_LINE)), filter(i -> !i.done, items))
    long = count(i -> length(i.text) > ROAD_LINE, items)
    (length(items) > ROAD_ITEMS || long > 0) &&
        print(io, "The road is too long (", length(items), " steps", long > 0 ? ", $long longer than $ROAD_LINE characters" : "",
              "): keep it to $ROAD_ITEMS short lines; fold finished parts into one done step.")
    return String(take!(io))
end

"The big goals the character pitched: `(goals, \"\")`, or `(nothing, why)`."
function read_big_goal_pitches(jp::JailPaths)
    v, why = read_agent_json(big_goal_pitch_path(jp))
    v === nothing && return nothing, why
    goals = v isa AbstractDict ? get(v, "goals", nothing) : nothing
    goals isa AbstractVector || return nothing, "no \"goals\" list"
    field(g, k) = String(strip(string(get(g, k, ""))))
    steps(g) = (r = get(g, "road", Any[]); r isa AbstractVector ? [String(strip(string(x))) for x in r] : [field(g, "road")])
    ok = [merge(Dict{String,Any}(k => field(g, k) for k in ("title", "pitch", "play", "moment")), Dict{String,Any}("road" => steps(g)))
          for g in goals if g isa AbstractDict && get(g, "title", nothing) isa AbstractString && get(g, "pitch", nothing) isa AbstractString]
    isempty(ok) && return nothing, "no goal with a \"title\" and a \"pitch\""
    return ok, ""
end

"A pitched big goal as the critic reads it."
big_goal_pitch_line(g::AbstractDict) =
    "- **$(g["title"])**: $(g["pitch"]) Play: $(isempty(g["play"]) ? "not said" : g["play"]). " *
    "The moment: $(isempty(g["moment"]) ? "not said" : g["moment"]). " *
    "The road: $(isempty(g["road"]) ? "not said" : join(g["road"], "; "))."

function big_goal_critic_prompt(jp::JailPaths, r::Int, pitched, rounds, out::AbstractString)
    io = IOBuffer()
    println(io, "# Big goal, round $r\n\nWrite your verdict to `$(out)`.\n")
    println(io, "## This round's candidates")
    foreach(g -> println(io, big_goal_pitch_line(g)), pitched)
    println(io)
    if !isempty(rounds)
        shown = last(rounds, BIG_GOAL_SHOWN_ROUNDS)
        println(io, "## Earlier rounds, and what the critic said")
        for (k, rd) in zip(length(rounds) - length(shown) + 1:length(rounds), shown), g in rd["scored"]
            println(io, "- round $k, **$(g["title"])**: $(g["pitch"]) (", score_list(g), ": $(g["critique"]))")
        end
        println(io)
    end
    goals = goals_text(jp)
    isempty(goals) || println(io, goals, "\n")
    print(io, named(prompt_file("big_goal.md"), jp))
    return String(take!(io))
end

"""
    score_big_goals(v, pitched) -> Vector{Dict}

The critic's verdict `v` on this round's `pitched` big goals: each one's scores (a missing one counts
as 0) and whether it passes (every score at least `BIG_GOAL_BAR`).
"""
function score_big_goals(v::AbstractDict, pitched)
    byname = Dict(title_key(g["title"]) => g for g in pitched)
    verdicts = filter(g -> g isa AbstractDict && haskey(byname, title_key(string(get(g, "title", "")))), get(v, "goals", Any[]))
    return map(verdicts) do g
        d = copy(byname[title_key(g["title"])])
        d["scores"] = Dict{String,Any}(s => (x = get(g, s, nothing); clamp(x isa Real ? x : 0, 0, 10)) for s in BIG_GOAL_SCORES)
        d["critique"] = string(get(g, "critique", ""))
        d["passes"] = all(s -> d["scores"][s] >= BIG_GOAL_BAR, BIG_GOAL_SCORES)
        d
    end
end

big_goal_strength(g::AbstractDict) = sum(values(g["scores"]))

"A big goal's scores in a line: `clear 8, memorable 6, …` (`suffix` after each number)."
score_list(g::AbstractDict, suffix::AbstractString = "") = join(("$s $(g["scores"][s])$suffix" for s in BIG_GOAL_SCORES), ", ")

"The passed big goal's head as the host writes it into `BIG_GOAL.md`, in the character's words from its pitch."
big_goal_head_text(g::AbstractDict, n::Int, r::Int) = """
    # $(g["title"])

    $(g["pitch"])

    Play: $(g["play"])

    The moment people share: $(g["moment"])

    (Passed the critic in session $n, round $r: $(score_list(g)).)"""

"The passed big goal's file: its head, and its pitched road as the first open steps."
big_goal_file_text(g::AbstractDict, head::AbstractString) =
    head * "\n\n" * ROAD_HEADING * "\n\n" * join(("- [ ] " * x for x in g["road"] if !isempty(x)), "\n") * "\n"

"What the character hears after a round: the critic's word on each candidate, then what comes next."
function big_goal_critique_text(scored, r::Int, rel::AbstractString, outcome::Symbol, chosen)
    io = IOBuffer()
    println(io, "## The critic on your big goal (round $r)")
    for g in scored
        how = g["passes"] ? "passes" : "below $BIG_GOAL_BAR in " * join(filter(s -> g["scores"][s] < BIG_GOAL_BAR, collect(BIG_GOAL_SCORES)), ", ")
        println(io, "- **$(g["title"])**: ", score_list(g, "/10"), ": $how. $(g["critique"])")
    end
    if outcome === :passed
        print(io, "\n\"$(chosen["title"])\" passed after $r rounds; the host wrote it into `world/BIG_GOAL.md`. ",
              "Now your ideas (step 3), each a step towards it.")
    elseif outcome === :early
        passed = join(("\"$(g["title"])\"" for g in scored if g["passes"]), ", ")
        print(io, "\n$passed would pass, but a big goal goes through at least $BIG_GOAL_MIN_ROUNDS rounds. ",
              "Write round $(r + 1) into `$rel`: sharpen what the critic found strong, drop the rest, add new candidates ",
              "far from everything so far; then end your turn.")
    elseif outcome === :again
        print(io, "\nNone passed. The bar: $BIG_GOAL_BAR in each of ", join(BIG_GOAL_SCORES, ", "), ". Write round $(r + 1) into `$rel`: ",
              "sharpen what the critic found strong, drop the rest, add new candidates far from everything so far; then end your turn.")
    else
        print(io, "\nNo big goal passed this session. `world/BIG_GOAL.md` stays as it is, not passed, and the rounds go on ",
              "next session. Now your ideas (step 3).")
    end
    return String(take!(io))
end

"""
    big_goal_followup(host, n, run) -> String or nothing

When a turn of session `n` ends while `BIG_GOAL.md` is not the big goal the critic passed: the
critic's next round on the candidates in `big_goal_pitch_path`, or a reminder to pitch them.
`nothing` once one passed, while the session wraps up, after `BIG_GOAL_SESSION_ROUNDS` rounds or
`BIG_GOAL_REMINDERS` turns without a new round this session (the rounds go on next session).
"""
function big_goal_followup(host, n::Int, run)
    jp = host.jp
    run.wrap_up_since == 0 || return nothing
    log = load_big_goal_log(jp)
    big_goal_passed(jp, log) && return nothing
    log["session"] == n || (log["session"] = n; log["session_rounds"] = 0; log["reminded"] = 0)
    (log["session_rounds"] >= BIG_GOAL_SESSION_ROUNDS || log["reminded"] > BIG_GOAL_REMINDERS) && return nothing
    rel = relpath(big_goal_pitch_path(jp), jp.world)
    label = "big goal"
    rounds = log["rounds"]
    pitched, why = read_big_goal_pitches(jp)
    unchanged = pitched !== nothing && !isempty(rounds) && pitched == last(rounds)["pitched"]
    if pitched === nothing || unchanged
        log["reminded"] += 1
        save_big_goal_log!(jp, log)
        if log["reminded"] > BIG_GOAL_REMINDERS
            record!(host.activity, label, "host", "no new round after $BIG_GOAL_REMINDERS reminders: the session goes on without the critic")
            return nothing
        end
        return unchanged ? "`$rel` has not changed since the critic answered: write round $(length(rounds) + 1) there, then end your turn." :
               "Your big goal has not passed the critic yet, and there are no candidates in `$rel` ($why): pitch them there " *
               "(step 3 of Now), then end your turn; the critic answers."
    end
    r = length(rounds) + 1
    out = review_path(jp, @sprintf("big-goal-%d", r))
    rm(out; force = true)           # a round of a cut-off session's earlier run is not this one
    run_agent!(host, :review, "$label, round $r", judge_settings(host.cfg), big_goal_critic_prompt(jp, r, pitched, rounds, out))
    v, why = read_agent_json(out)
    scored = v isa AbstractDict ? score_big_goals(v, pitched) : Any[]
    if isempty(scored)
        log["reminded"] = BIG_GOAL_REMINDERS + 1
        save_big_goal_log!(jp, log)
        record!(host.activity, label, "host", "the critic gave no usable answer ($(isempty(why) ? "no scored goal" : why))")
        return nothing
    end
    push!(rounds, Dict{String,Any}("session" => n, "pitched" => pitched, "scored" => scored, "time" => now_string()))
    log["session_rounds"] += 1
    passed = filter(g -> g["passes"], scored)
    since = log["approved"] === nothing ? 0 : log["approved"]["round"]      # the rounds since the last big goal passed
    chosen = isempty(passed) ? nothing : argmax(big_goal_strength, passed)
    outcome = chosen !== nothing && r - since >= BIG_GOAL_MIN_ROUNDS ? :passed :
              chosen !== nothing ? :early :
              log["session_rounds"] < BIG_GOAL_SESSION_ROUNDS ? :again : :later
    if outcome === :passed
        head = big_goal_head_text(chosen, n, r)
        write(big_goal_path(jp), big_goal_file_text(chosen, head))
        log["approved"] = Dict{String,Any}("session" => n, "round" => r, "title" => chosen["title"], "head" => head,
                                           "scores" => chosen["scores"], "time" => now_string())
    end
    save_big_goal_log!(jp, log)
    best = argmax(big_goal_strength, scored)
    record!(host.activity, "$label, round $r", "review",
            "$(length(passed)) of $(length(scored)) passed; strongest \"$(best["title"])\" (" *
            score_list(best) * ")" * (outcome === :passed ? "; it is the big goal now" : ""))
    return big_goal_critique_text(scored, r, rel, outcome, chosen)
end
