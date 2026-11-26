# ── the character's mood and what it perceives ──────────────────────────────
#
# Like Pino (github.com/pino-the-bird), the character works out what to make from how
# its garden makes it feel. Two pipelines feed that, both run by the host so
# no agent can fake them:
#
# Perception: before a session, the human's game's event log since the last
# session becomes what the character noticed: what the human did (played, wished),
# what the creatures did most and what happened for the first time, what was
# said, what broke. It goes into the session prompt (`perception_lines`).
#
# Mood: after a session, what it put into the garden is scored against how
# tired the character is of each kind of work (`score`, see below): doing the same
# kind again is worth less and less, editing the same plugins again costs.
# Boredom follows what *happens* on the island (`happenings`, below): it grows every
# session and only eases when something the island never had happens in the
# human's game; new kinds of things and the human's company make it happy, no
# company makes it lonely. The state is the host's (`.jail/state/mood.json`); the game and
# the agents read a copy at `/run/neverending/mood.json`. A bored character's
# next session must make something of a kind it is fresh for first: the
# prompt says so, and a session that ends its turn with too little yet is
# sent back to it (`bored_followup`).

# ── what happens on the island: the only cure for boredom ───────────────────
#
# Boredom once followed the kinds of work (a plugin, a film, a post), and a new
# vegetable patch counted like a parade: the island grew, but nothing on it
# surprised anyone. Now each session makes the character more bored
# (`BOREDOM_RISE`). What eases it most is the session's reviewer finding the work
# surprising (`surprise`, 0-10, judged against the last posts), before the next
# session; a happening the island never had before (a kind of event new to the
# human's game's log, `happenings`) eases it a little. A new event kind once eased
# it fully, and the island filled with gather-and-laugh events that each counted
# as new (sessions 79-90, surprise 5-7). Decorations, polish and posts about the
# same things change nothing.

"Event kinds that are the game's machinery or talk, not something happening in the world."
const PLUMBING = Set(["say", "snapshot", "plugin_load", "plugin_removed", "publish", "game_start", "game_stop", "game_crash",
                      "shutdown_request", "plugin_error", "play_start", "play_stop", "day_length", "path_tracing", "renamed",
                      "areas_built"])
const BOREDOM_RISE = 0.25

"What happened in the human's game between `from` and `to`: event kind => who, once per time it happened."
function happenings(jp::JailPaths, from::DateTime, to::DateTime = Dates.now())
    seen = Dict{String,Vector{String}}()
    for ev in live_events(jp, from, to)
        k = string(ev["kind"])
        k in PLUMBING && continue
        push!(get!(Vector{String}, seen, k), string(get(ev, "who", "")))
    end
    return seen
end

"""
Every kind of happening the island had before `until`: from the mood, else from the event log up
to `until` (a session's own events are not history yet; Lumi found that in session 62, when the
list was first built mid-session and its four new happenings counted as old).
"""
function happened_ever!(jp::JailPaths, m::AbstractDict, until::DateTime)
    haskey(m, "happened") && return m["happened"]
    files = filter(f -> startswith(f, "events-") && endswith(f, ".jsonl"), readdir(joinpath(jp.world, "log")))
    first_day = isempty(files) ? Dates.today() : Date(minimum(files)[8:17])
    m["happened"] = sort!(collect(keys(happenings(jp, DateTime(first_day), until))))
    return m["happened"]
end

"What eases boredom: per new happening 0.1, +0.02 for each inhabitant that took part (up to 6), at most 0.3 together."
ease(new::AbstractVector) = min(0.3, sum(h -> 0.1 + 0.02 * min(h["who"], 6), new; init = 0.0))

"The happenings since `from` the island never had: kind and how many took part, most first."
function new_happenings(jp::JailPaths, m::AbstractDict, from::DateTime)
    ever = Set(happened_ever!(jp, m, from))
    new = [Dict{String,Any}("kind" => k, "who" => length(unique(w))) for (k, w) in happenings(jp, from) if !(k in ever)]
    return sort!(new; by = h -> -h["who"])
end

"""
The newest session review's surprise and fun (0-10, the reviewer's), moving boredom and joy once,
before the next session: surprise moves boredom (a 6, a nice twist, holds it; every point above eases
it by 0.08, every point below adds as much), fun moves joy the same way (0.04 a point from 6).
Reviews before session 116 have no fun (nor does one that gives none as a number): their surprise moves joy.
Since session 127 a review also says how `real` the work is (simulated, not scripted): boredom then moves
with the mean of surprise and real.
"""
function feel_surprise!(jp::JailPaths, m::AbstractDict)
    files = sort!(filter(f -> occursin(r"^session-\d+\.json$", f), readdir(reviews_dir(jp))))
    isempty(files) && return m
    n = parse(Int, match(r"\d+", last(files)).match)
    n > get(m, "surprise_seen", 0) || return m
    r = read_json(joinpath(reviews_dir(jp), last(files)))
    m["surprise_seen"] = n
    s = get(r, "surprise", nothing)
    s isa Real || return m
    f = get(r, "fun", s)
    f isa Real || (f = s)
    rl = get(r, "real", nothing)
    rl isa Real && (s = (s + rl) / 2)      # since session 127 how real it is moves boredom with the surprise
    m["last_surprise"] = Dict{String,Any}("session" => n, "score" => s, "why" => string(get(r, "surprise_why", "")), "fun" => f)
    m["boredom"] = round(clamp(m["boredom"] - 0.08 * (s - 6), 0, 1); digits = 2)
    m["joy"] = round(clamp(m["joy"] + 0.04 * (f - 6), 0, 1); digits = 2)
    return m
end

mood_path(jp::JailPaths) = joinpath(jp.state, "mood.json")

function load_mood(jp::JailPaths)
    isfile(mood_path(jp)) && return read_json(mood_path(jp))
    return Dict{String,Any}("boredom" => 0.3, "joy" => 0.5, "loneliness" => 0.0, "last_contact" => now_string(),
                            "sessions" => Any[], "start" => garden_snapshot(jp),
                            "perceived_until" => Dates.format(Dates.now() - Hour(3), "yyyy-mm-ddTHH:MM:SS"))
end

"Save the mood and its read only copy for the game and the agents (with the feeling word)."
function save_mood!(jp::JailPaths, m::AbstractDict)
    write_json(mood_path(jp), m)
    view = Dict{String,Any}(k => m[k] for k in ("boredom", "joy", "loneliness"))
    view["feeling"] = feeling(m)
    view["why"] = mood_reason(m)
    view["updated"] = now_string()
    write_json(joinpath(jp.run, "mood.json"), view)
    return m
end

function feeling(m::AbstractDict)
    m["boredom"] >= 0.6 && return "bored"
    m["loneliness"] >= 0.7 && return "lonely"
    m["joy"] >= 0.65 && return "proud"
    m["boredom"] <= 0.25 && return "curious"
    return "content"
end

# ── what counts as made, and how much it is worth ───────────────────────────
#
# Like Pino, the character tires of doing the same thing. Each session's work falls
# into kinds (`KINDS`): a new system (plugin), polishing existing plugins, a
# generated asset, pictures, a film, sound, a new post on its pages, a wish
# come true. Every kind has a fatigue: +1 each session that does it, ×0.6 each
# session after, so it fades over a few sessions. What a kind is worth falls
# steeply with its fatigue (×e^(-1.2·fatigue)): done last session ≈ 30 %, two in
# a row ≈ 15 %, after that close to nothing. The first time ever of a kind earns
# a bonus. A session that brings no real variety raises boredom. A film and the
# post every session (rule 14) are not kinds to vary and never tire: while films
# tired too (40 % after one), sessions 96-98 posted stills. Refining what exists
# (editing plugins) never tires either, and editing the same plugins again costs
# nothing (until session 115 it did): making something better is never worth less.

"What each kind of work is worth fresh, and what the prompt suggests for it."
const KINDS = Dict(
    "feature" => (4.0, "a new system: a place, creature, tool, interaction or mini game (a new plugin)"),
    "polish"  => (1.0, "polishing what exists (editing plugins)"),
    "asset"   => (1.0, "a generated 3D asset placed in the world (make-asset)"),
    "picture" => (1.0, "path traced pictures of a moment for your pages"),
    "film"    => (6.0, "a film: a VideoEditor project with cameras, path traced (make-movie)"),
    "sound"   => (4.0, "sound: your voice telling a story, music, the island's noises (Kokoro and the other voice models)"),
    "post"    => (2.0, "a new post on your pages: path traced pictures or a film, a caption of one to three sentences"),
    "wish"    => (3.0, "a wish from WISHES.md come true"),
    "self"    => (6.0, "yourself: your own body, face and how you move, a character people love to watch (goal 5)"),
)
"Worth the same every time: a film, the post every session makes (rule 14), refining what exists, a wish (its own thing each time)."
const NEVER_TIRE = ("film", "post", "polish", "wish")
"Whether doing kind `k` again is worth less."
tires(k) = !(k in NEVER_TIRE)
const FATIGUE_KEEP = 0.6       # each session a kind's fatigue is multiplied by this, then +1 if it was done
const FATIGUE_BITE = 1.2       # value × exp(-FATIGUE_BITE × fatigue)
const FIRST_BONUS = 4.0        # the first time ever of a kind

ext(f) = lowercase(last(splitext(f)))
is_film(f) = ext(f) in (".mp4", ".webm", ".mov")
is_sound(f) = ext(f) in (".ogg", ".mp3", ".wav", ".flac", ".opus")
is_picture(f) = ext(f) in (".png", ".jpg", ".jpeg", ".webp")

"Wishes come true: the items under `## Done` in world/WISHES.md."
function wishes_done(jp::JailPaths)
    isfile(wishes_path(jp)) || return 0
    done, n = false, 0
    for l in eachline(wishes_path(jp))
        startswith(l, "## ") && (done = startswith(lowercase(l), "## done"))
        done && startswith(l, "- ") && (n += 1)
    end
    return n
end

"""
The character's own body as it is defined: the engine and plugin files named after it (its
name in world/NAME) or after its bird body (bird.jl, birdbody.jl). A change is work on itself
(kind "self"). Until Nov 24 this hashed `function sprout()` in species.jl, which became a
one-line call into bird.jl: the crest and the wings did not count as work on itself.
"""
function self_print(jp::JailPaths)
    src = joinpath(jp.root, "dev", "NeverendingGame", "src")
    keys = (lowercase(character_name(jp)), "bird")
    files = [joinpath(d, f) for d in (src, joinpath(jp.world, "plugins")) for f in readdir(d)
             if endswith(f, ".jl") && any(k -> occursin(k, lowercase(f)), keys)]
    return string(hash([read(f, String) for f in sort!(files)]))
end

"Posts on the character's pages: the pieces of world/site/index.html."
function posts_count(jp::JailPaths)
    f = joinpath(jp.world, "site", "index.html")
    return isfile(f) ? count("class=\"piece\"", read(f, String)) : 0
end

"What the garden holds that counts as made: plugins (file => mtime), generated meshes, files of the pages and releases, posts, wishes come true."
function garden_snapshot(jp::JailPaths)
    pdir, adir = joinpath(jp.world, "plugins"), joinpath(jp.world, "assets")
    plugins = Dict{String,Any}(f => mtime(joinpath(pdir, f)) for f in readdir(pdir)
                               if endswith(f, ".jl") && !startswith(f, "_"))
    assets = [d for d in readdir(adir) if isfile(joinpath(adir, d, "mesh.jls"))]
    pages = String[]
    for top in ("site", "releases")
        dir = joinpath(jp.world, top)
        isdir(dir) || continue
        for (root, _, files) in walkdir(dir), f in files
            push!(pages, relpath(joinpath(root, f), jp.world))
        end
    end
    return Dict{String,Any}("plugins" => plugins, "assets" => assets, "pages" => pages, "wishes" => wishes_done(jp),
                            "posts" => posts_count(jp), "self" => self_print(jp))
end

"How big a new plugin is, as a share of a full one (120 lines): a stub is worth little."
plugin_size(jp::JailPaths, f) = (p = joinpath(jp.world, "plugins", f); isfile(p) ? min(1.0, countlines(p) / 120) : 0.0)

"""
    session_work(jp, start, now) -> Dict

What a session put into the garden, by kind, from two `garden_snapshot`s:
the raw amount of each kind (before fatigue) and the lists behind it.
"""
function session_work(jp::JailPaths, start::AbstractDict, now::AbstractDict)
    p0, p1 = start["plugins"], now["plugins"]
    new_plugins = sort!([f for f in keys(p1) if !haskey(p0, f)])
    touched = sort!([f for f in keys(p1) if haskey(p0, f) && p1[f] != p0[f]])
    new_pages = setdiff(now["pages"], start["pages"])
    pictures = filter(f -> is_picture(f) && !occursin("/voice/", f), new_pages)
    # a start snapshot from before posts were counted (Nov 24) has no "posts": nothing counts as posted then
    posts = max(0, now["posts"] - get(start, "posts", now["posts"]))
    amount = Dict{String,Float64}(
        "feature" => sum(f -> plugin_size(jp, f), first(new_plugins, 2); init = 0.0),
        "asset" => min(length(setdiff(now["assets"], start["assets"])), 3),
        "picture" => min(length(pictures), 3),
        "film" => any(is_film, new_pages) ? 1.0 : 0.0,
        "sound" => any(is_sound, new_pages) ? 1.0 : 0.0,
        "post" => min(posts, 2),
        "wish" => max(0, now["wishes"] - start["wishes"]),
        # a start snapshot from before the character's body was tracked (Nov 24) has no "self": no change then
        "self" => get(start, "self", now["self"]) == now["self"] ? 0.0 : 1.0,
    )
    return Dict{String,Any}("amount" => amount, "new_plugins" => new_plugins, "touched" => touched,
                            "new_pages" => first(new_pages, 6), "new_assets" => Int(amount["asset"]), "wishes" => Int(amount["wish"]))
end

"""
    score(m, work) -> Dict

What a session's work is worth to the character in mood `m` (its fatigues and the
kinds it ever did): per kind `value × amount × e^(-1.2 fatigue)` (+ the first
time bonus), polishing a point per plugin edited, up to 3. Returns the session record.
"""
function score(m::AbstractDict, d::AbstractDict)
    fat, ever = m["fatigue"], m["kinds_ever"]
    worth = Dict{String,Float64}()
    for (k, a) in d["amount"]
        a > 0 || continue
        v = first(KINDS[k]) * a * (tires(k) ? exp(-FATIGUE_BITE * get(fat, k, 0.0)) : 1.0)
        k in ever || (v += FIRST_BONUS)
        worth[k] = round(v; digits = 1)
    end
    isempty(d["touched"]) || (worth["polish"] = first(KINDS["polish"]) * min(length(d["touched"]), 3))
    r = Dict{String,Any}(d)
    r["values"] = worth
    r["kinds"] = sort!(collect(keys(worth)))
    r["points"] = round(sum(values(worth); init = 0.0); digits = 1)
    return r
end

"After a session: each kind (that `tires`) it did tires (+1), the others rest (×0.6)."
function tire!(m::AbstractDict, r::AbstractDict)
    fat = m["fatigue"]
    for k in keys(KINDS)
        tires(k) || (delete!(fat, k); continue)
        fat[k] = round(FATIGUE_KEEP * get(fat, k, 0.0) + (k in r["kinds"] ? 1.0 : 0.0); digits = 2)
    end
    union!(m["kinds_ever"], r["kinds"])
    return m
end

"What a record from before kinds were counted (sessions up to 57) made, by kind (pictures on the pages came with a post)."
function record_work(r::AbstractDict)
    pics = count(f -> is_picture(f) && startswith(f, "site/img"), r["new_pages"])
    amount = Dict{String,Float64}("feature" => min(2.0, length(r["new_plugins"])), "asset" => min(r["new_assets"], 3),
                                  "wish" => r["wishes"], "picture" => min(pics, 3), "film" => any(is_film, r["new_pages"]) ? 1.0 : 0.0,
                                  "sound" => any(is_sound, r["new_pages"]) ? 1.0 : 0.0, "post" => pics > 0 ? 1.0 : 0.0, "self" => 0.0)
    return Dict{String,Any}("amount" => amount, "new_plugins" => r["new_plugins"], "touched" => r["touched"],
                            "new_pages" => r["new_pages"], "new_assets" => r["new_assets"], "wishes" => r["wishes"])
end

"""
A mood saved before fatigue existed: the recorded sessions are scored again
in order, as if the character had always tired of doing the same thing, and boredom
and joy follow (the human's company is not in the records: loneliness stays).
"""
function with_fatigue!(m::AbstractDict)
    haskey(m, "fatigue") && return m
    m["fatigue"] = Dict{String,Any}()
    m["kinds_ever"] = filter(!=("self"), collect(keys(KINDS)))   # before Nov 24 the character had made every kind but itself
    m["boredom"], m["joy"] = 0.0, 0.5
    m["sessions"] = map(m["sessions"]) do old
        r = score(m, record_work(old))
        r["session"] = old["session"]
        feel_session!(m, r, false)
        tire!(m, r)
        r
    end
    return m
end

"""
How a session moves boredom and joy (before its kinds tire): boredom grows by `BOREDOM_RISE`, a
little less for varied work (0.02 a point), and eases with what newly happened (`ease`); joy
follows the points, the new happenings and the human's company.
"""
function feel_session!(m::AbstractDict, r::AbstractDict, contact::Bool)
    p = r["points"]
    new = get(r, "happenings", Any[])
    eased = ease(new) * get(r, "repeat_factor", 1.0)     # a repeat's new event kinds are hardly new
    m["boredom"] = round(clamp(m["boredom"] + BOREDOM_RISE - 0.02p - eased, 0, 1); digits = 2)
    m["joy"] = round(clamp(0.6m["joy"] + 0.04p + 0.1 * min(length(new), 3) + (contact ? 0.15 : 0.0), 0, 1); digits = 2)
    return m
end

"What a session's record says it made, and what it was worth."
function made_parts(r::AbstractDict)
    parts = String[]
    isempty(r["new_plugins"]) || push!(parts, "new " * join(r["new_plugins"], ", "))
    r["new_assets"] > 0 && push!(parts, "$(r["new_assets"]) new generated mesh(es)")
    r["wishes"] > 0 && push!(parts, "$(r["wishes"]) wish(es) come true")
    isempty(r["new_pages"]) || push!(parts, "new pages/films: " * join(r["new_pages"], ", "))
    hs = get(r, "happenings", Any[])
    isempty(hs) || push!(parts, "NEW ON THE ISLAND: " * join(("$(h["kind"]) ($(h["who"]) taking part)" for h in hs), ", "))
    rp = get(r, "repetition", nothing)
    if rp !== nothing && rp["score"] >= SIMILAR[1]
        push!(parts, isempty(rp["post"]) ? @sprintf("NOTHING POSTED (worth ×%.2f)", r["repeat_factor"]) :
                     @sprintf("A REPEAT: \"%s\" %s/10 like \"%s\"%s (worth ×%.2f)", rp["post"], get(rp, "similarity", rp["score"]),
                              rp["nearest"], get(rp, "form_count", 0) > 0 ? ", its form in $(rp["form_count"]) of the last $FORM_MEMORY" : "",
                              r["repeat_factor"]))
    end
    isempty(parts) && push!(parts, "nothing new")
    isempty(r["touched"]) || push!(parts, "edited " * join(r["touched"], ", "))
    vals = get(r, "values", nothing)
    vals === nothing || isempty(vals) || push!(parts, "worth: " * join(("$k $(v)" for (k, v) in sort!(collect(vals))), ", "))
    return join(parts, "; ")
end

"One line for a session's record."
made_line(r::AbstractDict) = "session $(r["session"]): " * made_parts(r) * " ($(r["points"]) points)"

mood_reason(m::AbstractDict) = join((made_line(r) for r in last(m["sessions"], 3)), "\n")

# ── the session's start and end ─────────────────────────────────────────────

"Before a session: what the garden holds now, and how lonely the character got (12 hours without the human: fully)."
function mood_session_start!(jp::JailPaths, contact::Bool)
    m = with_fatigue!(load_mood(jp))
    contact && (m["last_contact"] = now_string())
    hours = (Dates.now() - DateTime(m["last_contact"])).value / 3.6e6
    m["loneliness"] = round(clamp(hours / 12, 0, 1); digits = 2)
    if cut_off(m)
        # nothing it made is dropped: this session goes on from the same start, so the work counts
        # and gets posted (`cut_off_lines`); twice in a row, the work was dropped (Nov 25)
        m["cut_off"] = m["started"]
    else
        delete!(m, "cut_off")
        m["start"] = garden_snapshot(jp)
        m["started"] = now_string()
    end
    happened_ever!(jp, m, DateTime(m["started"]))       # the history, before this session's events
    feel_surprise!(jp, m)
    return save_mood!(jp, m)
end

"""
After a session: what it made is scored against the character's fatigue and moves
it (`feel_session!`), after a repeat's penalty (`feel_repetition!`, when `repetition` is the
judge's verdict). Then the kinds and plugins it did tire. Returns the session's record.
"""
function mood_session_end!(jp::JailPaths, n::Int, contact::Bool; repetition::Union{Nothing,AbstractDict} = nothing)
    m = with_fatigue!(load_mood(jp))
    r = score(m, session_work(jp, m["start"], garden_snapshot(jp)))
    r["session"] = n
    r["happenings"] = new_happenings(jp, m, DateTime(get(m, "started", m["perceived_until"])))
    union!(m["happened"], [h["kind"] for h in r["happenings"]])
    isempty(r["happenings"]) || (m["last_new"] = Dict{String,Any}("session" => n, "kinds" => [h["kind"] for h in r["happenings"]]))
    repetition === nothing || feel_repetition!(m, r, repetition)
    feel_session!(m, r, contact)
    contact && (m["last_contact"] = now_string(); m["loneliness"] = 0.0)
    tire!(m, r)
    push!(m["sessions"], r)
    length(m["sessions"]) > 20 && popfirst!(m["sessions"])
    m["ended"] = now_string()
    delete!(m, "cut_off")
    save_mood!(jp, m)
    return r
end

"""
Whether the last session was cut off (the host stopped or restarted while it ran): it started
and never ended. A mood from before `ended` was kept (Nov 25) has none: its sessions count as ended.
"""
cut_off(m::AbstractDict) = haskey(m, "ended") && DateTime(m["ended"]) < DateTime(m["started"])

"The prompt's section on a session that was cut off and what it had made, empty when none was."
function cut_off_lines(jp::JailPaths)
    m = load_mood(jp)
    haskey(m, "cut_off") || return ""
    w = session_work(jp, m["start"], garden_snapshot(jp))
    made = String[]
    isempty(w["new_plugins"]) || push!(made, "new plugins " * join(w["new_plugins"], ", "))
    isempty(w["touched"]) || push!(made, "edited plugins " * join(w["touched"], ", "))
    isempty(w["new_pages"]) || push!(made, "new on your pages " * join(w["new_pages"], ", "))
    tf = joinpath(jp.world, "state", "thought.json")
    thought = isfile(tf) ? string(get(read_json(tf), "text", "")) : ""
    return "## Your last session was cut off
The host stopped while your session from $(m["started"]) ran (not your doing). " *
           "Nothing you made is dropped: this session goes on from there. What you had made: " *
           (isempty(made) ? "nothing the host can see (look at your diary)" : join(made, "; ")) * "." *
           (isempty(thought) ? "" : " Your last thought: \"$thought\".") *
           " Finish it and post it, or post it as it is, before anything new."
end

"""
The prompt's mood section: how the character feels now, and nothing of how it got there (the
sessions behind it and what they were worth are in the read only copy, /run/neverending/mood.json).
"""
function mood_lines(jp::JailPaths)
    m = load_mood(jp)
    name = character_name(jp)
    io = IOBuffer()
    @printf(io, "## How %s feels (the host's measure; read only at /run/neverending/mood.json)\n%s feels **%s** (boredom %.2f, joy %.2f, loneliness %.2f).\n",
            name, name, feeling(m), m["boredom"], m["joy"], m["loneliness"])
    m["loneliness"] >= 0.7 && println(io, "$name misses the human: make something for them (a page, a film, a note) and tell them with say_to_human.")
    print(io, "Show it in the world: how $name looks and behaves follows its `feeling` in /run/neverending/mood.json, so the human sees how $name is.")
    return String(take!(io))
end

"""
Sent instead of `keep_going` when a bored character ends its turn while nothing new has happened
in the human's game this session (the turn ends, the session does not).
"""
function bored_followup(jp::JailPaths, run)
    m = with_fatigue!(load_mood(jp))
    m["boredom"] >= 0.5 || return nothing
    isempty(new_happenings(jp, m, DateTime(get(m, "started", m["perceived_until"])))) || return nothing
    left = (run.deadline - time()) / 60
    (left > 10 && run.wrap_up_since == 0) || return nothing
    return "Nothing new has happened on the island this session, and $(character_name(jp)) is bored (boredom $(m["boredom"])). " *
           "$(round(Int, left)) minutes are left: make something the island never had, and publish it so it is in the human's game."
end

# ── perception: what the character noticed in the human's game ──────────────

"The human's game's events with `wall` in [from, to) (the log is the jailed game's: unreadable lines are skipped)."
function live_events(jp::JailPaths, from::DateTime, to::DateTime = Dates.now())
    dir = joinpath(jp.world, "log")
    out = Dict{String,Any}[]
    for day in Date(from):Day(1):Date(to)
        f = joinpath(dir, "events-$(day).jsonl")
        isfile(f) || continue
        for l in eachline(f)
            ev = try
                JSON.parse(l; dicttype = Dict{String,Any})
            catch e
                e isa ArgumentError || rethrow()
                continue       # a line cut off when the game stopped
            end
            w = get(ev, "wall", "")
            (w isa String && length(w) >= 19) || continue
            t = DateTime(first(w, 19))
            from <= t < to && push!(out, ev)
        end
    end
    return out
end

"Event kinds seen in the week before `t`, to tell what happened for the first time."
function known_kinds(jp::JailPaths, t::DateTime)
    kinds = Set{String}()
    for ev in live_events(jp, t - Day(7), t)
        push!(kinds, string(ev["kind"]))
    end
    return kinds
end

"""
    perception(jp, since) -> Dict

What happened in the human's game since `since`: the human's plays, what the
creatures did (most first), what happened for the first time, the character's own
doings, some things said, what broke.
"""
function perception(jp::JailPaths, since::DateTime)
    evs = live_events(jp, since)
    name = character_name(jp)
    kinds = Dict{String,Int}()
    sprout = Dict{String,Int}()
    said = String[]
    plays = Dict{String,Int}()
    broke = String[]
    for ev in evs
        k = string(ev["kind"])
        who = string(get(ev, "who", ""))
        k == "play_start" && (g = string(get(ev, "game", "?")); plays[g] = get(plays, g, 0) + 1)
        k == "plugin_error" && push!(broke, first(string(get(ev, "title", "")), 100))
        if k == "say"
            line = "$who: " * string(get(ev, "text", ""))
            line in said || push!(said, line)
            length(said) > 50 && popfirst!(said)
        end
        k in PLUMBING && continue
        kinds[k] = get(kinds, k, 0) + 1
        occursin(name, who) && (sprout[k] = get(sprout, k, 0) + 1)
    end
    known = known_kinds(jp, since)
    total = sum(values(kinds); init = 0)
    top = sort!(collect(kinds); by = last, rev = true)
    share = total == 0 ? 0.0 : sum(last.(first(top, 3))) / total
    return Dict{String,Any}("since" => string(since), "events" => total, "plays" => plays, "top" => first(top, 10),
                            "first_time" => sort!([k for k in keys(kinds) if !(k in known)]),
                            "sprout" => sort!(collect(sprout); by = last, rev = true), "top3_share" => share,
                            "said" => last(said, 6), "broke" => unique(broke), "name" => name)
end

"""
Before a session: what the character noticed since the last one (the window moves on).
"""
function perceive!(jp::JailPaths)
    m = load_mood(jp)
    p = perception(jp, DateTime(m["perceived_until"]))
    m["perceived_until"] = now_string()
    save_mood!(jp, m)
    return p
end

"The prompt's perception section."
function perception_lines(p::AbstractDict, msgs)
    io = IOBuffer()
    println(io, "## What $(p["name"]) noticed in the human's game since ", first(p["since"], 16))
    human = [m for (_, m) in msgs if startswith(get(m, "from", "human"), "human")]
    if isempty(p["plays"]) && isempty(human)
        println(io, "- The human did not play and left no message.")
    else
        isempty(p["plays"]) || println(io, "- The human played: ", join(("$g ($(n)×)" for (g, n) in p["plays"]), ", "), ".")
        isempty(human) || println(io, "- The human left $(length(human)) message(s) (below).")
    end
    if p["events"] > 0
        println(io, "- What the creatures did most ($(p["events"]) events): ", join(("$k $n" for (k, n) in p["top"]), ", "), ".")
        p["top3_share"] > 0.6 && @printf(io, "- The same three things were %.0f%% of everything: the garden is getting samey.\n", 100p["top3_share"])
        isempty(p["first_time"]) || println(io, "- For the first time this week: ", join(p["first_time"], ", "), ".")
        isempty(p["sprout"]) || println(io, "- $(p["name"]) itself: ", join(("$k $n" for (k, n) in p["sprout"]), ", "), ".")
    else
        println(io, "- Nothing happened in the world (the game was down?).")
    end
    isempty(p["said"]) || println(io, "- Overheard: ", join(("\"$s\"" for s in p["said"]), "; "), ".")
    isempty(p["broke"]) || println(io, "- What broke: ", join(p["broke"], "; "), ".")
    print(io, "Let it move you: what delighted you, what bored you, what the human did. Write it into your diary (the journal) and let it shape the next wish.")
    return String(take!(io))
end

# ── the character's eyes ────────────────────────────────────────────────────

"""
    look_around!(host, n) -> image paths, or why there are none

The character's eyes before session `n`: the human's game saves its world, the
sandbox restarts as a fresh copy of it, and renders what the character sees ahead,
left, behind and right (live command `eyes`) into
`world/media/eyes/session-NNNN/`. The agent starts the session looking at them.
"""
function look_around!(host, n::Int)
    jp = host.jp
    s = game_request(jp, Dict("cmd" => "save", "reason" => "the sandbox copies it"); timeout = 60)
    (s !== nothing && s["ok"] === true) ||
        record!(host.activity, "session $n", "host", "the human's game did not save before the sandbox copied it: " *
                (s === nothing ? "no answer" : first(string(get(s, "error", s)), 200)))
    sock = joinpath(game_run(jp, :sandbox), "game.sock")
    ask_game_shutdown(jp, :sandbox)
    t0 = time()
    while ispath(sock) && time() - t0 < 120
        sleep(1)
    end
    game_up(jp; game = :sandbox, limit = 600) ||
        return "the sandbox did not come up in 10 minutes; the end of .jail/logs/sandbox.log says why"
    dir = joinpath(jp.world, "media", "eyes", @sprintf("session-%04d", n))
    r = game_request(jp, Dict("cmd" => "eyes", "dir" => dir); game = :sandbox, timeout = 300)
    r === nothing && return "the sandbox did not answer"
    r["ok"] === true || return first(string(get(r, "error", r)), 300)
    return String.(r["paths"])
end

"""
    sense_motion!(host, n) -> String

The character's sense of motion before session `n`: the sandbox (the fresh copy `look_around!`
made) measures how every creature moves over a few seconds, frame by frame, and films the one
that moves worst (live command `motion`, NeverendingGame's motionsense.jl). The text for the
prompt, or why there is none.
"""
function sense_motion!(host, n::Int)
    dir = joinpath(host.jp.world, "media", "eyes", @sprintf("session-%04d", n))
    r = game_request(host.jp, Dict("cmd" => "motion", "dir" => dir); game = :sandbox, timeout = 300)
    r === nothing && return "the sandbox did not answer"
    r["ok"] === true || return "it failed: " * first(string(get(r, "error", r)), 300)
    return String(r["text"])
end

motion_lines(text::AbstractString, name) =
    "## How things move right now ($(name)'s sense of motion: the host measured it in a fresh copy of the human's world)\n" * text

eye_lines(paths::AbstractVector, name) =
    "## What $name sees right now (a fresh copy of the human's world; you are $name: open these images first)\n" *
    join(paths, "\n")
eye_lines(why::AbstractString, name) = "## What $name sees\n$(name)'s eyes are closed: $why. Make it see again first."
