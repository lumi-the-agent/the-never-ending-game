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
# fix the post; at most `POST_CRITIQUES` looks per post.

"How many frames of a film the storyboard shows, spread from its start to its end."
const BOARD_FRAMES = 16

"How often the critic looks at one post in a session (again only when the post changed)."
const POST_CRITIQUES = 2

"The host's record of the critic's looks at session `n`'s posts (outside the jail)."
post_log_path(jp::JailPaths, n::Int) = joinpath(jp.state, "posts", @sprintf("session-%04d.json", n))

function load_post_log(jp::JailPaths, n::Int)
    p = post_log_path(jp, n)
    isfile(p) && return read_json(p)
    return Dict{String,Any}("session" => n, "posts" => Dict{String,Any}(), "calls" => 0)
end

save_post_log!(jp::JailPaths, log::AbstractDict) =
    (mkpath(dirname(post_log_path(jp, log["session"]))); write_json(post_log_path(jp, log["session"]), log))

"A post as whoever scrolls the pages gets it: id, title and caption as plain text, its media (absolute paths)."
function viewed_post(jp::JailPaths, id::AbstractString, html::AbstractString)
    text(m) = m === nothing ? "" : String(strip(replace(m[1], r"<[^>]+>" => "", r"\s+" => " ")))
    return (id = String(id), title = text(match(r"<h3>(.*?)</h3>"s, html)), caption = text(match(r"<p>(.*?)</p>"s, html)),
            media = [joinpath(site_dir(jp), f) for f in post_media(html)])
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

"What the character hears after the critic looked: each post's verdict and problems, then what to do."
function post_critique_text(posts, byid::AbstractDict, seen::AbstractDict, left::Real)
    io = IOBuffer()
    println(io, "## The critic on your new post(s)")
    for p in posts
        x = get(byid, p.id, nothing)
        x === nothing && (println(io, "- `$(p.id)` \"$(p.title)\": the critic said nothing about it."); continue)
        println(io, "- `$(p.id)` \"$(p.title)\": **$(x["verdict"])**. ", get(x, "critique", ""))
        foreach(pr -> println(io, "  - ", pr), filter(pr -> pr isa AbstractString, get(x, "problems", Any[])))
    end
    redo = [p for p in posts if get(get(byid, p.id, Dict()), "verdict", "") == "redo"]
    if isempty(redo)
        print(io, "\nNothing to fix. Go on with the rest of Now.")
    else
        last_look = [p.id for p in redo if length(seen[p.id]) >= POST_CRITIQUES]
        @printf(io, "\nFix what it found in the post itself (%.0f minutes are left): new pictures or a new film replace the old ones, and the caption says what they show (rule 14: a fix is no new post). ", left)
        print(io, isempty(last_look) ? "Then end your turn: the critic looks once more." :
                  "The critic does not look at $(join(("`$i`" for i in last_look), ", ")) again this session; end your turn when it is fixed.")
    end
    return String(take!(io))
end

"""
    post_critic_followup(host, n, run) -> String or nothing

When a turn of session `n` ends with posts of this session the critic has not seen as they are now
(at most `POST_CRITIQUES` looks per post): the critic's verdict on them, for the character to fix.
`nothing` without such posts, and while the session wraps up (noted in the activity).
"""
function post_critic_followup(host, n::Int, run)
    jp = host.jp
    log = load_post_log(jp, n)
    seen = log["posts"]
    posts = [viewed_post(jp, id, html) for (id, html) in session_pieces(jp, run.started)]
    fresh = filter(posts) do p
        looks = get(seen, p.id, Any[])
        !isempty(p.media) && all(isfile, p.media) && length(looks) < POST_CRITIQUES &&
            (isempty(looks) || last(looks)["key"] != post_key(p))
    end
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
    return post_critique_text(fresh, byid, seen, (run.deadline - time()) / 60)
end
