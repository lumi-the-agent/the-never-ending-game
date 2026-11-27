# ── the big goal: one aim above the projects, chosen and grown with a critic ────
#
# Nov 27: fifteen projects, none finished, each a film of its own, nothing above them. Rule 9
# then asked for a big goal of the character's own (`world/BIG_GOAL.md`), and the first one,
# written in two minutes, was "Everything I make with my hands keeps what I did to it": a
# principle, not a game anyone would remember, clip or play for hours. So a critic
# (`prompts/big_goal.md`, on the reviewer's model) chooses it: the character pitches candidates
# into `world/ideas/big-goal.json` and ends its turn, and the critic scores each
# (`BIG_GOAL_SCORES`). Twenty rounds later none had reached `BIG_GOAL_BAR` in every score, and
# the human: "the big goal can be developed iteratively, and improved over time with the
# feedback". So the strongest candidate with at least `BIG_GOAL_START` in each becomes the big
# goal, and it grows from there: every round the critic scores it again next to the new
# candidates, its word on it is in the character's prompt, and a candidate that scores higher
# replaces it. Without a big goal the host asks for rounds (at most `BIG_GOAL_SESSION_ROUNDS` a
# session); with one, a round runs whenever the character pitches. The host writes the big goal
# into `BIG_GOAL.md`: its head (title, pitch, play, the moment) and under `## Road` a checklist
# of the steps to it. The head is the critic's choice (a changed head is put back after the
# next round); the road is the character's to work through: tick steps off, add, split and
# nest them, within `ROAD_ITEMS` lines of `ROAD_LINE` characters, so it never becomes pages of
# text. The rounds are kept outside the jail.

"The critic's bar: the score (0-10) in each of `BIG_GOAL_SCORES` the big goal is grown towards."
const BIG_GOAL_BAR = 8
"What a candidate must score in each of `BIG_GOAL_SCORES` to become the big goal, or to replace it."
const BIG_GOAL_START = 6
"How many rounds the critic answers in one session; the rounds go on the next session."
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
"The host's record of the rounds and of the big goal the critic chose (outside the jail: the critic's word stands)."
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

"""
The host's record: every round (`"rounds"`), this session's counts, and in `"approved"` the big goal
the critic chose (its pitch, its latest scores and critique, `"round"` it was chosen in, `"scored"`
the round it was last scored in, and the `"head"` the host wrote), or `nothing`.
"""
function load_big_goal_log(jp::JailPaths)
    p = big_goal_log_path(jp)
    isfile(p) && return read_json(p)
    return Dict{String,Any}("approved" => nothing, "rounds" => Any[], "session" => 0, "session_rounds" => 0, "reminded" => 0)
end

save_big_goal_log!(jp::JailPaths, log::AbstractDict) = write_json(big_goal_log_path(jp), log)

"Whether the head of `BIG_GOAL.md` is the big goal the critic chose, as the host wrote it."
big_goal_in_force(jp::JailPaths, log::AbstractDict = load_big_goal_log(jp)) =
    log["approved"] !== nothing && log["approved"]["head"] == first(split_big_goal(big_goal_text(jp)))

"Where the big goal stands, and for the character (`own`) what to do about it."
function big_goal_status(jp::JailPaths, log::AbstractDict; own::Bool = true)
    g = log["approved"]
    g === nothing && return "not chosen by the critic yet" * (own ? ": step 3 of Now" : "")
    big_goal_in_force(jp, log) || return "its head is not the one the critic chose" * (own ? ": pitch your change, step 3 of Now" : "")
    return "chosen by the critic in session $(g["session"])" * (own ? "; a better version you pitch replaces it, step 3 of Now" : "")
end

"""
The prompts' big goal section (for the character, or with `own = false` for the idea critic as the
character's): the head, the critic's latest scores and word on it (only in the character's own), and
the road's open steps (the done ones counted), with what is wrong with the road's size.
"""
function big_goal_lines(jp::JailPaths; whose::AbstractString = "Your", own::Bool = true)
    head, road = split_big_goal(big_goal_text(jp))
    log = load_big_goal_log(jp)
    g = log["approved"]
    io = IOBuffer()
    println(io, "## $whose big goal (`world/BIG_GOAL.md`, ", big_goal_status(jp, log; own), ")")
    print(io, isempty(head) ? "(none yet)" : first(head, BIG_GOAL_CHARS))
    own && g !== nothing &&
        print(io, "\n\nThe critic on it in round $(g["scored"]): ", score_list(g, "/10"), " (its bar: $BIG_GOAL_BAR in each). ", g["critique"])
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

"A pitched big goal as the critic reads it, with `road` (its pitched one by default) as its steps."
big_goal_pitch_line(g::AbstractDict, road::AbstractString = isempty(g["road"]) ? "not said" : join(g["road"], "; ")) =
    "- **$(g["title"])**: $(g["pitch"]) Play: $(isempty(g["play"]) ? "not said" : g["play"]). " *
    "The moment: $(isempty(g["moment"]) ? "not said" : g["moment"]). The road: $road."

"The road in `BIG_GOAL.md` as the critic reads it: every step, done ones marked."
function road_line(jp::JailPaths)
    items = road_items(last(split_big_goal(big_goal_text(jp))))
    isempty(items) && return "none in the file"
    return "$(count(i -> i.done, items)) of $(length(items)) steps done: " * join(((i.done ? "[done] " : "") * i.text for i in items), "; ")
end

function big_goal_critic_prompt(jp::JailPaths, r::Int, pitched, log::AbstractDict, out::AbstractString)
    io = IOBuffer()
    println(io, "# Big goal, round $r\n\nWrite your verdict to `$(out)`.\n")
    g = log["approved"]
    if g !== nothing
        println(io, "## The current big goal (chosen in round $(g["round"]))")
        println(io, big_goal_pitch_line(g, road_line(jp)))
        println(io, "Last scored in round $(g["scored"]): ", score_list(g), ": ", g["critique"], "\n")
    end
    println(io, "## This round's candidates")
    foreach(g -> println(io, big_goal_pitch_line(g)), pitched)
    println(io)
    rounds = log["rounds"]
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

"A verdict entry's scores (a missing one counts as 0) and its critique."
verdict_scores(g::AbstractDict) =
    Dict{String,Any}(s => (x = get(g, s, nothing); clamp(x isa Real ? x : 0, 0, 10)) for s in BIG_GOAL_SCORES), string(get(g, "critique", ""))

"The critic's verdict `v` on this round's `pitched` big goals: each one with its scores and critique."
function score_big_goals(v::AbstractDict, pitched)
    byname = Dict(title_key(g["title"]) => g for g in pitched)
    verdicts = filter(g -> g isa AbstractDict && haskey(byname, title_key(string(get(g, "title", "")))), get(v, "goals", Any[]))
    return map(verdicts) do g
        d = copy(byname[title_key(g["title"])])
        d["scores"], d["critique"] = verdict_scores(g)
        d
    end
end

big_goal_strength(g::AbstractDict) = sum(values(g["scores"]))

"Whether a candidate is good enough to become the big goal (`BIG_GOAL_START` in each score)."
can_lead(g::AbstractDict) = all(s -> g["scores"][s] >= BIG_GOAL_START, BIG_GOAL_SCORES)

"A big goal's scores in a line: `clear 8, memorable 6, …` (`suffix` after each number)."
score_list(g::AbstractDict, suffix::AbstractString = "") = join(("$s $(g["scores"][s])$suffix" for s in BIG_GOAL_SCORES), ", ")

"The big goal's head as the host writes it into `BIG_GOAL.md`, in the character's words from its pitch."
big_goal_head_text(g::AbstractDict) = """
    # $(g["title"])

    $(g["pitch"])

    Play: $(g["play"])

    The moment people share: $(g["moment"])"""

"A road of `steps` (a new big goal's pitched ones): open, but a step done on `old_road` in the same words stays done."
function road_text(steps, old_road::AbstractString)
    done = Set(i.text for i in road_items(old_road) if i.done)
    return join(((x in done ? "- [x] " : "- [ ] ") * x for x in steps if !isempty(x)), "\n")
end

write_big_goal!(jp::JailPaths, head::AbstractString, road::AbstractString) =
    write(big_goal_path(jp), head * "\n\n" * ROAD_HEADING * "\n\n" * road * "\n")

"What the character hears after a round: the critic's word on its big goal and each candidate, then what comes next."
function big_goal_critique_text(scored, current, r::Int, rel::AbstractString, outcome::Symbol, chosen)
    io = IOBuffer()
    println(io, "## The critic on your big goal (round $r)")
    current === nothing || println(io, "- your big goal, **$(current["title"])**: ", score_list(current, "/10"), ". ", current["critique"])
    foreach(g -> println(io, "- **$(g["title"])**: ", score_list(g, "/10"), ". ", g["critique"]), scored)
    if outcome === :chosen
        print(io, "\n\"$(chosen["title"])\" is your big goal now: the strongest so far, with at least $BIG_GOAL_START in each. ",
              "The host wrote it into `world/BIG_GOAL.md`, its road as a checklist. It grows from here: the critic's bar is ",
              "$BIG_GOAL_BAR in each, its word on it is in your prompt, and a better version you pitch replaces it. ",
              "Now your ideas (step 3), each a step towards it.")
    elseif outcome === :better
        print(io, "\n\"$(chosen["title"])\" scores higher than your big goal and replaces it. The host wrote it into ",
              "`world/BIG_GOAL.md`; road steps you had done, in the same words, stay done. Now your ideas (step 3).")
    elseif outcome === :kept
        print(io, "\nNone scores higher than your big goal: it stays. Now your ideas (step 3).")
    elseif outcome === :again
        print(io, "\nNone has at least $BIG_GOAL_START in each of ", join(BIG_GOAL_SCORES, ", "), ". Write round $(r + 1) into `$rel`: ",
              "sharpen what the critic found strong, drop the rest, add new candidates far from everything so far; then end your turn.")
    else
        print(io, "\nNo big goal yet this session; the rounds go on next session. Now your ideas (step 3).")
    end
    return String(take!(io))
end

"""
    big_goal_followup(host, n, run) -> String or nothing

When a turn of session `n` ends: the critic's next round on the candidates in `big_goal_pitch_path`
and the current big goal, when there are new ones; without a big goal in force, a reminder to
pitch them. `nothing` while the session wraps up, after `BIG_GOAL_SESSION_ROUNDS` rounds or
`BIG_GOAL_REMINDERS` turns without a new round this session, and while the big goal stands and
nothing new is pitched.
"""
function big_goal_followup(host, n::Int, run)
    jp = host.jp
    run.wrap_up_since == 0 || return nothing
    log = load_big_goal_log(jp)
    log["session"] == n || (log["session"] = n; log["session_rounds"] = 0; log["reminded"] = 0)
    (log["session_rounds"] >= BIG_GOAL_SESSION_ROUNDS || log["reminded"] > BIG_GOAL_REMINDERS) && return nothing
    rel = relpath(big_goal_pitch_path(jp), jp.world)
    label = "big goal"
    rounds = log["rounds"]
    current = log["approved"]
    pitched, why = read_big_goal_pitches(jp)
    unchanged = pitched !== nothing && !isempty(rounds) && pitched == last(rounds)["pitched"]
    if pitched === nothing || unchanged
        big_goal_in_force(jp, log) && return nothing
        log["reminded"] += 1
        save_big_goal_log!(jp, log)
        if log["reminded"] > BIG_GOAL_REMINDERS
            record!(host.activity, label, "host", "no new round after $BIG_GOAL_REMINDERS reminders: the session goes on without the critic")
            return nothing
        end
        current === nothing || return "The head of `world/BIG_GOAL.md` is not the big goal the critic chose: pitch your change in `$rel` " *
                                      "(step 3 of Now), then end your turn; the critic scores it next to your big goal."
        return unchanged ? "`$rel` has not changed since the critic answered: write round $(length(rounds) + 1) there, then end your turn." :
               "Your big goal has not been chosen by the critic yet, and there are no candidates in `$rel` ($why): pitch them there " *
               "(step 3 of Now), then end your turn; the critic answers."
    end
    r = length(rounds) + 1
    out = review_path(jp, @sprintf("big-goal-%d", r))
    rm(out; force = true)           # a round of a cut-off session's earlier run is not this one
    run_agent!(host, :review, "$label, round $r", judge_settings(host.cfg), big_goal_critic_prompt(jp, r, pitched, log, out))
    v, why = read_agent_json(out)
    scored = v isa AbstractDict ? score_big_goals(v, pitched) : Any[]
    if isempty(scored)
        log["reminded"] = BIG_GOAL_REMINDERS + 1
        save_big_goal_log!(jp, log)
        record!(host.activity, label, "host", "the critic gave no usable answer ($(isempty(why) ? "no scored goal" : why))")
        return nothing
    end
    if current !== nothing && get(v, "current", nothing) isa AbstractDict
        current["scores"], current["critique"] = verdict_scores(v["current"])
        current["scored"] = r
    end
    push!(rounds, Dict{String,Any}("session" => n, "pitched" => pitched, "scored" => scored, "time" => now_string(),
                                   "current" => current === nothing ? nothing :
                                                Dict("title" => current["title"], "scores" => current["scores"], "critique" => current["critique"])))
    log["session_rounds"] += 1
    able = filter(can_lead, scored)
    best = isempty(able) ? nothing : argmax(big_goal_strength, able)
    chosen = best !== nothing && (current === nothing || big_goal_strength(best) > big_goal_strength(current)) ? best : nothing
    outcome = chosen !== nothing ? (current === nothing ? :chosen : :better) :
              current !== nothing ? :kept :
              log["session_rounds"] < BIG_GOAL_SESSION_ROUNDS ? :again : :later
    old_head, old_road = split_big_goal(big_goal_text(jp))
    if chosen !== nothing
        head = big_goal_head_text(chosen)
        write_big_goal!(jp, head, road_text(chosen["road"], old_road))
        log["approved"] = merge(chosen, Dict{String,Any}("session" => n, "round" => r, "scored" => r, "head" => head, "time" => now_string()))
    elseif current !== nothing && old_head != current["head"]
        write_big_goal!(jp, current["head"], old_road)       # the head is the critic's choice; the road stays the character's
    end
    save_big_goal_log!(jp, log)
    strongest = argmax(big_goal_strength, scored)
    record!(host.activity, "$label, round $r", "review",
            "strongest \"$(strongest["title"])\" (" * score_list(strongest) * ")" *
            (outcome === :chosen ? "; it is the big goal now" : outcome === :better ? "; it replaces the big goal" :
             outcome === :kept ? "; the big goal \"$(current["title"])\" stays (" * score_list(current) * ")" : ""))
    return big_goal_critique_text(scored, current, r, rel, outcome, chosen)
end
