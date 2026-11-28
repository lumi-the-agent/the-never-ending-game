# A retake that lands after the session: wait for the clip job, then put its film over the posted one (rule 14: a
# retake replaces the film in the same post). Errors (and copies nothing) when the job did not finish well.
#   submit_job(:run; script = "tools/swap_film.jl", call = "swap_film", kwargs = Dict("job" => id, "from" => ..., "to" => ...))
using NeverendingGame

function swap_film(; job::AbstractString, from::AbstractString, to::AbstractString, timeout = 5400)
    root = NeverendingGame.game_root()
    j = NeverendingGame.wait_job(job; timeout, root)
    j["status"] == "done" || error("clip job $job ended $(j["status"]): the posted film stays")
    src = joinpath(root, "world", from); dst = joinpath(root, "world", to)
    isfile(src) && filesize(src) > 100_000 || error("$src is missing or too small ($(isfile(src) ? filesize(src) : 0) bytes)")
    cp(src, dst; force = true)
    Dict("copied" => src, "to" => dst, "bytes" => filesize(dst))
end
