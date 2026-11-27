# ── the post critic: every post looked at as a viewer while it can be fixed ─────
#
# Nobody looked at a post the way someone scrolling the pages does. The idea
# critic judges pitches before anything exists; the session reviewer works
# through its checklist after the post is public, from motion sheets made to
# measure motion. Session 114's seesaw went out as "the whole island tips": the
# picture was rotated, nothing on the island moved, and the reviewer passed it
# from two pictures. Now, when the character ends a turn with a post of this
# session the critic has not seen as it is (its words, pictures and films), a
# critic (`prompts/post.md`, on the reviewer's model) gets each such post as a
# viewer does: its caption, its pictures, and for a film a storyboard of
# `BOARD_FRAMES` frames from start to end with three frames at full size. Its
# verdict goes back to the character as the next turn, while there is time to
# fix the post; at most `POST_CRITIQUES` looks per post a session.
#
# Nov 27: posts the critic called `redo` stayed up as they were, or went up again under a new
# name ("… a take that misses"), and nothing came back to them. A post that missed now stays up
# marked: the character adds a note in its own words (`MISS_NOTE`: what went wrong, what it wants
# to improve), its prompt lists the misses every session (`missed_lines`), and the critic looks
# again whenever a retake changes one, in any later session, until it says `ready`.

"How many frames of a film the storyboard shows, spread from its start to its end."
const BOARD_FRAMES = 16

"How often the critic looks at one post in a session (again only when the post changed)."
const POST_CRITIQUES = 2

"How many older misses (on the pages before the last session) the critic looks at again in one session, latest retake first."
const MISS_RELOOKS = 3

"The host's record of the critic's looks at session `n`'s posts (outside the jail)."
post_log_path(jp::JailPaths, n::Int) = joinpath(jp.state, "posts", @sprintf("session-%04d.json", n))

function load_post_log(jp::JailPaths, n::Int)
    p = post_log_path(jp, n)
    isfile(p) && return read_json(p)
    return Dict{String,Any}("session" => n, "posts" => Dict{String,Any}(), "calls" => 0)
end

save_post_log!(jp::JailPaths, log::AbstractDict) =
    (mkpath(dirname(post_log_path(jp, log["session"]))); write_json(post_log_path(jp, log["session"]), log))

"""
A post as whoever scrolls the pages gets it: id, title and caption as plain text, its media (absolute
paths), and the character's miss note (`nothing` without one; no part of what the critic sees).
"""
function viewed_post(jp::JailPaths, id::AbstractString, html::AbstractString)
    text(m) = m === nothing ? "" : String(strip(replace(m[1], r"<[^>]+>" => "", r"\s+" => " ")))
    return (id = String(id), title = text(match(r"<h3>(.*?)</h3>"s, html)), caption = text(match(r"<p>(.*?)</p>"s, html)),
            media = [joinpath(site_dir(jp), f) for f in post_media(html)], note = miss_note(html))
end

"Every look of the critic at every post, all sessions: post id => `(session, look)`, oldest first."
function post_looks(jp::JailPaths)
    dir = joinpath(jp.state, "posts")
    looks = Dict{String,Vector{Tuple{Int,Dict{String,Any}}}}()
    isdir(dir) || return looks
    for f in sort!(filter(f -> occursin(r"^session-\d+\.json$", f), readdir(dir)))
        log = read_json(joinpath(dir, f))
        for (id, ls) in log["posts"], l in ls
            push!(get!(looks, id, Tuple{Int,Dict{String,Any}}[]), (log["session"], l))
        end
    end
    return looks
end

"The critic's last verdict on a post (`(session, look)`), or `nothing` when it never gave one."
function last_verdict(looks::AbstractDict, id::AbstractString)
    judged = filter(((_, l),) -> l["verdict"] in ("ready", "redo"), get(looks, id, Tuple{Int,Dict{String,Any}}[]))
    return isempty(judged) ? nothing : last(judged)
end

"""
    missed_posts(jp, looks = post_looks(jp)) -> Vector

The posts on the front page the critic last called `redo`, newest first: the post as viewed
(`viewed_post`, with its miss note), its html, and the session and look of that verdict.
"""
function missed_posts(jp::JailPaths, looks::AbstractDict = post_looks(jp))
    out = []
    for (id, html) in session_pieces(jp, 0)
        v = last_verdict(looks, id)
        v === nothing || last(v)["verdict"] != "redo" || push!(out, (post = viewed_post(jp, id, html), html, session = first(v), look = last(v)))
    end
    return out
end

"When session `n` started (unix time), from the sessions log, or `nothing`."
function session_start(jp::JailPaths, n::Int)
    isfile(sessions_log(jp)) || return nothing
    for line in eachline(sessions_log(jp))
        isempty(strip(line)) && continue
        d = JSON.parse(line)
        d["n"] == n && return Float64(d["started"])
    end
    return nothing
end

"How many of the posts that missed the session prompt lists, newest first."
const MISSES_SHOWN = 5

"The session prompt's list of the posts that missed and wait for a retake, empty when none does."
function missed_lines(jp::JailPaths)
    missed = missed_posts(jp)
    isempty(missed) && return ""
    io = IOBuffer()
    println(io, "## Your posts that missed (", length(missed), " on your pages)")
    println(io, "The post critic said `redo`, and no retake in the same post has worked yet. Each stays up, marked, until ",
            "one does (rule 14): new pictures or a new film replace the old ones, the critic looks again when they change, ",
            "and when it says `ready` you take the note off.")
    for m in first(missed, MISSES_SHOWN)
        print(io, "- `$(m.post.id)` \"$(m.post.title)\" (session $(m.session)): ")
        println(io, m.post.note === nothing ?
                    "no miss note yet: add yours (what went wrong, what you want to improve). The critic said: $(m.look["critique"])" :
                    "your note: $(m.post.note)")
    end
    length(missed) > MISSES_SHOWN && print(io, "(", length(missed) - MISSES_SHOWN, " older ones are not listed.)")
    return String(take!(io))
end

"What the critic saw of a post: its words and each file's size and time (a changed post is looked at again)."
post_key(p) = join([p.title; p.caption; ["$f:$(filesize(f)):$(mtime(f))" for f in p.media]], "|")

"""
    storyboard(film, out) -> (; board, frames, duration)

`BOARD_FRAMES` frames spread over `film` from start to end in one picture (four a row, left to
right, top to bottom), and three frames at full size, a quarter, half and three quarters in.
"""
function storyboard(film::AbstractString, out::AbstractString)
    mkpath(out)
    name = splitext(basename(film))[1]
    _, duration = film_rate(film)
    board = joinpath(out, "$name-board.jpg")
    run(`ffmpeg -v error -y -i $film -vf "fps=$(BOARD_FRAMES)/$(duration),scale=480:-2,tile=4x$(cld(BOARD_FRAMES, 4))" -frames:v 1 -update 1 $board`)
    frames = map((0.25, 0.5, 0.75)) do q
        f = joinpath(out, @sprintf("%s-at-%02d.jpg", name, round(Int, 100q)))
        run(`ffmpeg -v error -y -ss $(q * duration) -i $film -frames:v 1 -update 1 $f`)
        f
    end
    return (; board, frames = collect(frames), duration)
end

"The storyboard of `film` in `dir`, or `nothing` when ffmpeg cannot read the film."
function storyboard_or_nothing(film::AbstractString, dir::AbstractString)
    try
        return storyboard(film, dir)
    catch e
        e isa ProcessFailedException || rethrow()
        return nothing
    end
end

"Each post as a prompt section: its title and caption, its pictures, and each film's storyboard (`boards`)."
function post_lines(io::IO, posts, boards::AbstractDict)
    for p in posts
        println(io, "## Post `$(p.id)`: $(p.title)\n\nCaption: $(p.caption)\n")
        for f in p.media
            if !is_film(f)
                println(io, "- picture: `$f`")
            elseif boards[f] === nothing
                println(io, "- film `$f`: ffmpeg cannot read it (a broken film)")
            else
                b = boards[f]
                @printf(io, "- film `%s`, %.1f s: storyboard `%s` (%d frames from start to end, %.1f s apart); full size a quarter, half and three quarters in: %s\n",
                        f, b.duration, b.board, BOARD_FRAMES, b.duration / BOARD_FRAMES, join(("`$x`" for x in b.frames), ", "))
            end
        end
        println(io)
    end
end

function post_critic_prompt(jp::JailPaths, n::Int, posts, boards::AbstractDict, out::AbstractString)
    io = IOBuffer()
    println(io, "# The new posts of session $n, as the pages show them\n\nWrite your verdict to `$(out)`.\n")
    post_lines(io, posts, boards)
    print(io, named(prompt_file("post.md"), jp))
    return String(take!(io))
end

"""
What the character hears after the critic looked: each post's verdict and problems, where to see what
the critic saw (the storyboards in `boards`), then what to do.
"""
function post_critique_text(jp::JailPaths, posts, byid::AbstractDict, seen::AbstractDict, boards::AbstractDict, left::Real)
    io = IOBuffer()
    println(io, "## The critic on your post(s)")
    for p in posts
        x = get(byid, p.id, nothing)
        x === nothing && (println(io, "- `$(p.id)` \"$(p.title)\": the critic said nothing about it."); continue)
        println(io, "- `$(p.id)` \"$(p.title)\": **$(x["verdict"])**. ", get(x, "critique", ""))
        foreach(pr -> println(io, "  - ", pr), filter(pr -> pr isa AbstractString, get(x, "problems", Any[])))
        shown = [relpath(boards[f].board, jp.world) for f in p.media if get(boards, f, nothing) !== nothing]
        isempty(shown) || println(io, "  - what the critic saw: ", join(("`$b`" for b in shown), ", "))
    end
    redo = [p for p in posts if get(get(byid, p.id, Dict()), "verdict", "") == "redo"]
    healed = [p.id for p in posts if p.note !== nothing && get(get(byid, p.id, Dict()), "verdict", "") == "ready"]
    isempty(healed) || print(io, "\n", join(("`$i`" for i in healed), ", "), " works now: take its miss note off, and let the caption say what the retake shows.")
    if isempty(redo)
        print(io, "\nNothing to fix. Go on with the rest of Now.")
    else
        last_look = [p.id for p in redo if length(seen[p.id]) >= POST_CRITIQUES]
        @printf(io, "\nLook at what the critic saw, then fix it in the post itself (%.0f minutes are left): new pictures or a new film replace the old ones, and the caption says what they show (rule 14: a fix is no new post, and a post that missed never goes up again under a new name). ", left)
        print(io, isempty(last_look) ? "Then end your turn: the critic looks once more. " :
                  "The critic does not look at $(join(("`$i`" for i in last_look), ", ")) again this session. ")
        print(io, "What you cannot fix now stays up as a miss (rule 14): add `<p class=\"miss\">…</p>` to it, one or two sentences ",
              "in your own words on what went wrong and what you want to improve, never the critic's words; it stays on your ",
              "list of misses until a retake in the same post works.")
    end
    return String(take!(io))
end

"""
    posts_to_look_at(jp, n, started, seen) -> Vector

The posts the critic has not seen as they are now (`seen`: session `n`'s looks so far, at most
`POST_CRITIQUES` a post): every one since the last session started (`started` without one), and
of the older misses (`missed_posts`) the latest retakes, `MISS_RELOOKS` a session.
"""
function posts_to_look_at(jp::JailPaths, n::Int, started::Real, seen::AbstractDict)
    looks = post_looks(jp)
    unseen(p) = (earlier = get(looks, p.id, Tuple{Int,Dict{String,Any}}[]);
                 !isempty(p.media) && all(isfile, p.media) && length(get(seen, p.id, Any[])) < POST_CRITIQUES &&
                 (isempty(earlier) || last(last(earlier))["key"] != post_key(p)))
    recent = [viewed_post(jp, id, html) for (id, html) in session_pieces(jp, something(session_start(jp, n - 1), started))]
    ids = Set(p.id for p in recent)
    older = [m.post for m in missed_posts(jp, looks) if !(m.post.id in ids)]
    quota = MISS_RELOOKS - count(p -> haskey(seen, p.id), older)
    retakes = sort!(filter(unseen, older); by = p -> -maximum(mtime, p.media))
    return [filter(unseen, recent); first(retakes, max(quota, 0))]
end

"""
    post_critic_followup(host, n, run) -> String or nothing

When a turn of session `n` ends with posts the critic has not seen as they are now (those since the
last session started, so one that went up at its end or between the two too, and the misses of any
session, `missed_posts`; at most `POST_CRITIQUES` looks per post a session):
the critic's verdict on them, for the character to fix. `nothing` without such posts, and while the
session wraps up (noted in the activity).
"""
function post_critic_followup(host, n::Int, run)
    jp = host.jp
    log = load_post_log(jp, n)
    seen = log["posts"]
    fresh = posts_to_look_at(jp, n, run.started, seen)
    isempty(fresh) && return nothing
    label = "posts of session $n"
    if run.wrap_up_since != 0
        record!(host.activity, label, "host", "not looked at by the critic (the session was wrapping up): " * join((p.id for p in fresh), ", "))
        return nothing
    end
    dir = joinpath(reviews_dir(jp), "posts", @sprintf("session-%04d", n))
    boards = Dict{String,Any}(f => storyboard_or_nothing(f, dir) for p in fresh for f in p.media if is_film(f))
    log["calls"] += 1
    out = review_path(jp, @sprintf("posts-%04d-%d", n, log["calls"]))
    rm(out; force = true)               # a look of a cut-off session's earlier run is not this one
    run_agent!(host, :review, label, judge_settings(host.cfg), post_critic_prompt(jp, n, fresh, boards, out))
    v, why = read_agent_json(out)
    verdicts = v isa AbstractDict ? filter(x -> x isa AbstractDict && get(x, "post", nothing) isa AbstractString &&
                                                get(x, "verdict", nothing) in ("ready", "redo"), get(v, "posts", Any[])) : Any[]
    byid = Dict(String(x["post"]) => x for x in verdicts)
    for p in fresh
        x = get(byid, p.id, Dict{String,Any}())
        push!(get!(seen, p.id, Any[]), Dict{String,Any}("time" => now_string(), "key" => post_key(p), "verdict" => get(x, "verdict", "none"),
                                                        "problems" => get(x, "problems", Any[]), "critique" => get(x, "critique", "")))
    end
    save_post_log!(jp, log)
    if isempty(byid)
        record!(host.activity, label, "host", "the critic gave no usable answer ($(isempty(why) ? "no verdict" : why))")
        return nothing
    end
    record!(host.activity, label, "review", join(("$(p.id): $(get(get(byid, p.id, Dict()), "verdict", "none"))" for p in fresh), "; "))
    return post_critique_text(jp, fresh, byid, seen, boards, (run.deadline - time()) / 60)
end
