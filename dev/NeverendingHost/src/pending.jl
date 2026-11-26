# ── pending posts: written when the render is queued, up when it is done ──────
#
# A post could only be written once its film existed, so the character waited
# for its renders (sessions 118-120: 6-10 waits each, up to 89 minutes asked
# for) instead of working on. Now it writes the post the moment it queues the
# render, as `world/pending/<name>.json`:
#
#     {"jobs": ["<worker job id>", ...], "piece": "<div class=\"piece\"><span class=\"date\"></span>...</div>"}
#
# and goes on. The host looks every `PENDING_EVERY` seconds: when all its jobs
# are done and what it shows exists, the piece goes on top of the pages, dated
# then, and the character's feed tool runs (in the worker's jail: it is the
# character's code). A job that failed, or a piece that cannot go up, is moved
# to `pending/failed/` and the character is told why. A post that goes up after
# the session is pushed with the next one, and reviewed by the next review.

"How often the host looks at the pending posts, in seconds."
const PENDING_EVERY = 20

pending_dir(jp::JailPaths) = joinpath(jp.world, "pending")

"Whether a pending post waits for its jobs."
has_pending(jp::JailPaths) = isdir(pending_dir(jp)) && any(endswith(".json"), readdir(pending_dir(jp)))

"The date a post shows, as the character writes it (`26 November 2026, 12:27`)."
post_date(t::DateTime = Dates.now()) = Dates.format(t, "d U yyyy, HH:MM")

"""
    pending_state(jp, v) -> :wait, :ready or the reason it cannot go up

A pending post `v` (its `jobs` and its `piece`): `:wait` while a job is queued or running, `:ready`
when all are done and the piece is whole, otherwise why not.
"""
function pending_state(jp::JailPaths, v::AbstractDict)
    piece = get(v, "piece", nothing)
    piece isa AbstractString && startswith(strip(piece), "<div class=\"piece\"") || return "its \"piece\" is no <div class=\"piece\">"
    occursin(r"<span class=\"date\">[^<]*</span>", piece) || return "its piece has no <span class=\"date\"></span> for the date"
    jobs = get(v, "jobs", Any[])
    jobs isa AbstractVector && all(j -> j isa AbstractString, jobs) || return "its \"jobs\" is no list of job ids"
    for id in jobs
        f = joinpath(jp.world, "jobs", id * ".json")
        isfile(f) || return "job $id does not exist"
        j = read_json(f)
        j["status"] == "failed" && return "job $id failed: " * first(split(string(get(j, "error", "")), '\n'))
        j["status"] == "done" || return :wait
    end
    missing = missing_media(jp, piece)
    isempty(missing) || return "it shows $(join(missing, ", ")), which is not there after its jobs are done"
    return :ready
end

"Put `piece` on top of the character's pages, dated now, and run its feed tool in the worker's jail; `nothing`, or why it cannot."
function put_on_pages!(host, piece::AbstractString)
    jp = host.jp
    page = joinpath(site_dir(jp), "index.html")
    isfile(page) || return "there is no site/index.html"
    html = read(page, String)
    dated = replace(piece, r"<span class=\"date\">[^<]*</span>" => "<span class=\"date\">$(post_date())</span>")
    i = findfirst("<div class=\"piece\"", html)
    i === nothing && return "site/index.html has no post to put a new one before"
    atomic_write(page, html[1:prevind(html, first(i))] * strip(dated) * "\n" * html[first(i):end])
    err = IOBuffer()
    feed = pipeline(jailed(jp, host.cfg, :worker, ["python3", "-I", "tools/site_feed.py", "site"]; cwd = jp.world);
                    stdout = devnull, stderr = err)
    success(feed) || record!(host.activity, "pending posts", "host", "the feed tool failed: " * first(String(take!(err)), 500))
    return nothing
end

"""
Every `PENDING_EVERY` seconds: the pending posts that are ready onto the pages (`put_up_pending_posts!`),
then the pages onto the blog once they settled (`publish_settled_pages!`).
"""
function publish_pending_posts!(host)
    put_up_pending_posts!(host)
    publish_settled_pages!(host)
    return nothing
end

"Every pending post whose jobs are done goes up; one that cannot is moved aside, and the character told why."
function put_up_pending_posts!(host)
    jp = host.jp
    dir = pending_dir(jp)
    isdir(dir) || return nothing
    for f in sort!(filter(endswith(".json"), readdir(dir)))
        path = joinpath(dir, f)
        v, why = read_agent_json(path)
        state = v isa AbstractDict ? pending_state(jp, v) : "unreadable ($why)"
        state === :wait && continue
        state === :ready && (state = something(put_on_pages!(host, v["piece"]), :posted))
        if state === :posted
            mkpath(joinpath(dir, "posted"))
            mv(path, joinpath(dir, "posted", f); force = true)
            record!(host.activity, "pending posts", "host", "$f is on the pages")
        else
            mkpath(joinpath(dir, "failed"))
            mv(path, joinpath(dir, "failed", f); force = true)
            record!(host.activity, "pending posts", "host", "$f cannot go up: $state")
            tell!(jp, "Host: your pending post $f did not go up: $state. It is in pending/failed/."; from = "host")
        end
    end
    return nothing
end

"""
The pages on the blog once they settled (`pages_settled`): a post goes public when it is on the pages,
not when the session ends. Until session 128 this ran only in the host's own agent sessions, so with
the sessions in the dashboard chat (since 68) every post waited for the end of its session, and a
pending post finished after one for the end of the next.
"""
publish_settled_pages!(host) =
    !isempty(host.cfg.blog_repo) && pages_settled(host.jp) && online!(publish_blog!, host, host.sessions + 1, "publishing the blog")

"`publish_pending_posts!` every `PENDING_EVERY` seconds while the host runs (the latest code each time)."
function pending_posts_loop(host)
    while host.running
        Base.invokelatest(publish_pending_posts!, host)
        sleep(PENDING_EVERY)
    end
end
