# ── motion sheets: a film's motion as pictures and numbers ──────────────────
#
# Reviewers and agents see images, not motion: a still shows a pose, never a
# pop, a snap, jitter or a stiff move. `motion_sheet(film)` turns a film into
# what can be looked at (ffmpeg only, no packages):
#
#   <name>-overview.jpg  12 frames spread over the film: what happens, the poses;
#   <name>-steps.jpg     8 consecutive frames (1/fps apart) around the sharpest
#                        jump between two frames that is not a cut: smooth motion
#                        changes a little and evenly from frame to frame, a pop or
#                        a snap shows as one frame that does not follow;
#   the numbers          how much each frame differs from the one before (ffmpeg's
#                        scene score, 0 to 1), its cuts and its jumps.
#
# The host makes these for the reviews (review.jl). In a Julia session:
#     include("/sim/Programmieren/SimGame/dev/NeverendingHost/tools/motion_sheet.jl")
#     print(motion_sheet("world/site/films/my-film.mp4"; out = "world/media/motion").text)

using Printf

"A frame-to-frame change this large is a cut (a new shot), not motion."
const MOTION_CUT = 0.3

"""
    motion_sheet(film; out = <the film's folder>, name = <the film's name>) -> (; text, images)

The overview and steps sheets of `film` in `out`, and a few lines on its motion (see the top of
this file).
"""
function motion_sheet(film::AbstractString; out::AbstractString = dirname(abspath(film)),
                      name::AbstractString = splitext(basename(film))[1])
    mkpath(out)
    fps, duration = film_rate(film)
    change = frame_changes(film)
    n = length(change)
    typical = film_median(change)
    cuts = findall(>=(MOTION_CUT), change)
    # a new shot settles for a few frames (the camera swings in): those are no jumps either
    near_cut(i) = any(c -> 0 <= i - c <= 4, cuts)
    jumps = sort!(findall(i -> max(4typical, 0.01) <= change[i] < MOTION_CUT && !near_cut(i), eachindex(change));
                  by = i -> -change[i])
    overview = joinpath(out, "$(name)-overview.jpg")
    run(`ffmpeg -v error -y -i $film -vf "fps=12/$(duration),scale=480:-2,tile=4x3" -frames:v 1 -update 1 $overview`)
    # the steps start 3 frames before the largest jump (or in the middle of a film without one)
    centre = isempty(jumps) ? n ÷ 2 : first(jumps)
    from = clamp(centre - 3, 1, max(n - 7, 1))
    steps = joinpath(out, "$(name)-steps.jpg")
    run(`ffmpeg -v error -y -ss $((from - 1) / fps) -i $film -vf "scale=480:-2,tile=4x2" -frames:v 1 -update 1 $steps`)
    secs(i) = @sprintf("%.2f s", (i - 1) / fps)
    io = IOBuffer()
    @printf(io, "%s: %.1f s at %g fps (%d frames)\n", basename(film), duration, fps, n)
    @printf(io, "change between frames (0 to 1): typical %.4f, 95%% %.4f\n", typical, film_quantile(change, 0.95))
    println(io, "cuts (≥ $(MOTION_CUT)): ", isempty(cuts) ? "none" : join(secs.(cuts), ", "))
    println(io, "jumps (≥ 4× typical, not cuts): ", length(jumps),
            isempty(jumps) ? "" : "; the largest at " * join((secs(i) * @sprintf(" (%.3f)", change[i]) for i in first(jumps, 5)), ", "))
    println(io, "overview: $overview (12 frames over the film)")
    println(io, "steps: $steps (8 consecutive frames from ", secs(from), isempty(jumps) ? ", the middle" : ", around the largest jump", ")")
    return (; text = String(take!(io)), images = [overview, steps])
end

"Frames per second and length in seconds of a film's video."
function film_rate(film::AbstractString)
    info = Dict(split(l, '='; limit = 2) for l in eachline(`ffprobe -v error -select_streams v:0 -show_entries stream=r_frame_rate -show_entries format=duration -of default=nw=1 $film`))
    num, den = parse.(Float64, split(info["r_frame_rate"], '/'))
    return num / den, parse(Float64, info["duration"])
end

"How much each frame differs from the one before (ffmpeg's scene score; the first frame 0)."
frame_changes(film::AbstractString) =
    [parse(Float64, last(split(l, '='))) for l in eachline(`ffmpeg -v error -i $film -vf "scale=320:-2,select='gte(scene,0)',metadata=print:file=-" -f null -`)
     if startswith(l, "lavfi.scene_score=")]

film_quantile(x::AbstractVector, q::Real) = isempty(x) ? 0.0 : sort(x)[clamp(round(Int, q * length(x)), 1, length(x))]
film_median(x::AbstractVector) = film_quantile(x, 0.5)
