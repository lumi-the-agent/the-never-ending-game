# ── Lumi's sense of motion: how things move, measured from what is drawn ────
#
# A still shows a pose, never jitter, a judder, a snap or something racing.
# Before every session the host asks the sandbox (a fresh copy of the human's
# world) for `motion` (live command): the game steps `seconds` at its own frame
# rate, as it does live, and after every frame reads where every body part of
# every creature is drawn (the herds' part transforms: what the renderer gets).
# From those tracks, per creature:
#
#   vibrating  a part turns back more than VIBRATE_RATE times a second
#              (relative to the body, so walking does not hide it);
#   juddering  smooth motion in uneven steps: at speed, a part's step changes
#              from one frame to the next by more than JUDDER of its size;
#   too fast   the body faster than FAST_BODY m/s, a part faster than
#              FAST_PART m/s around the body;
#   snapping   a one-frame jump of a part or of the body (many times its usual
#              step), or a turn of SNAP_TURN or more in one frame;
#   frozen     nothing about it moves at all.
#
# Then it films, from close by, the creature that moves worst (Lumi when all is
# well): 8 consecutive frames (jitter, snaps) and a strip of 24 frames at 10 a
# second (the motion as it plays), and every creature up close at 3 moments
# (broken, detached or floating parts), each tiled into one picture.

"A part step below this (metres per frame) is standing still."
const MOTION_STILL = 0.0005
"Turning back more often than this per second reads as vibrating."
const VIBRATE_RATE = 8.0
"At speed, a step that differs from the one before by this fraction of its size is a judder."
const JUDDER = 0.4
"Metres per second: faster bodies and parts (around the body) are too fast to follow."
const FAST_BODY = 7.0
const FAST_PART = 6.0
"A one-frame jump of a part of at least this (metres, and 8× its usual step) is a snap; turns in radians."
const SNAP_PART = 0.15
const SNAP_TURN = 0.6

"Where one creature and each of its drawn parts were, frame by frame."
struct MotionTrack
    name::String
    body::Vector{Point3f}
    yaw::Vector{Float32}
    parts::Dict{Tuple{Symbol,Int},Vector{Point3f}}    # (part, copy) => where it was drawn
end

MotionTrack(name::AbstractString) = MotionTrack(String(name), Point3f[], Float32[], Dict{Tuple{Symbol,Int},Vector{Point3f}}())

"Add the current frame (the stage just synced) to the tracks, one per creature id."
function record_motion!(tracks::Dict{Int32,MotionTrack}, g::Game)
    for c in g.world.creatures
        tr = get!(() -> MotionTrack(c.name), tracks, c.id)
        push!(tr.body, Point3f(c.pos))
        push!(tr.yaw, c.yaw)
    end
    st = g.stage
    for (sp, h) in st.herds
        ids = st.members[sp]
        isempty(ids) && continue
        for (j, part) in enumerate(h.species[].parts)
            drawn = getproperty(h, Symbol(:part, j, :_pos))[]
            nc = ncopies(part)
            for (i, id) in enumerate(ids), k in 1:nc
                haskey(tracks, id) || continue
                push!(get!(Vector{Point3f}, tracks[id].parts, (part.name, k)), Point3f(drawn[(i - 1) * nc + k]))
            end
        end
    end
    return tracks
end

motion_median(x) = isempty(x) ? 0.0 : sort(collect(x))[cld(length(x), 2)]

"What is wrong with one track of positions `P` (seen relative to the body for a part), at `fps`."
function track_faults(P::Vector{Point3f}, fps::Real)
    v = [P[t + 1] - P[t] for t in 1:(length(P) - 1)]
    s = norm.(v)
    seconds = length(v) / fps
    turns = count(t -> s[t] > MOTION_STILL && s[t - 1] > MOTION_STILL && dot(v[t], v[t - 1]) < 0, 2:length(v))
    fast = filter(t -> s[t] > 0.5 * maximum(s) && s[t] > 4MOTION_STILL && t > 1 && dot(v[t], v[t - 1]) > 0, eachindex(s))
    judder = length(fast) < 8 ? 0.0 : motion_median(abs(s[t] - s[t - 1]) / max(s[t], s[t - 1]) for t in fast)
    usual = motion_median(s)
    big, at = findmax(s)
    return (; turns = turns / seconds, judder, speed = maximum(s; init = 0.0) * fps,
            snap = big >= SNAP_PART && big >= 8usual ? at / fps : nothing, jump = big,
            moves = maximum(norm(p - P[1]) for p in P) > 0.001)
end

"The faults of every creature that was there the whole time: name => list of (fault, detail, weight)."
function motion_faults(tracks::Dict{Int32,MotionTrack}, n::Int, fps::Real)
    out = Pair{String,Vector{Tuple{Symbol,String,Float64}}}[]
    for tr in values(tracks)
        length(tr.body) == n && all(p -> length(p) == n, values(tr.parts)) || continue
        faults = Tuple{Symbol,String,Float64}[]
        body = track_faults(tr.body, fps)
        body.speed > FAST_BODY && push!(faults, (:fast, @sprintf("moves at %.1f m/s", body.speed), body.speed / FAST_BODY))
        body.snap === nothing || push!(faults, (:snap, @sprintf("jumps %.2f m in one frame at %.1f s", body.jump, body.snap), 3.0))
        turn, at = findmax([abs(rem2pi(Float64(tr.yaw[t + 1] - tr.yaw[t]), RoundNearest)) for t in 1:(n - 1)])
        turn >= SNAP_TURN && push!(faults, (:snap, @sprintf("turns %.0f° in one frame at %.1f s", rad2deg(turn), at / fps), 3.0))
        moves = body.moves
        for ((name, k), P) in sort!(collect(tr.parts); by = first)
            f = track_faults([p - b for (p, b) in zip(P, tr.body)], fps)
            moves |= f.moves
            label = k == 1 ? string(name) : "$(name) ($(k))"
            f.turns > VIBRATE_RATE && push!(faults, (:vibrating, @sprintf("%s turns back %.0f times a second", label, f.turns), f.turns / VIBRATE_RATE))
            f.judder > JUDDER && push!(faults, (:juddering, @sprintf("%s moves in uneven steps (%.0f%% from frame to frame)", label, 100f.judder), f.judder / JUDDER))
            f.speed > FAST_PART && push!(faults, (:fast, @sprintf("%s swings at %.1f m/s", label, f.speed), f.speed / FAST_PART))
            f.snap === nothing || push!(faults, (:snap, @sprintf("%s jumps %.2f m in one frame at %.1f s", label, f.jump, f.snap), 2.0))
        end
        moves || push!(faults, (:frozen, "nothing about it moves", 0.5))
        push!(out, tr.name => faults)
    end
    return sort!(out; by = first)
end

const MOTION_KINDS = [:vibrating => "Vibrating (turning back faster than $(Int(VIBRATE_RATE)) times a second)",
                      :juddering => "Juddering (smooth moves in uneven steps)",
                      :snap => "Snapping (one-frame jumps and turns)",
                      :fast => "Too fast to follow",
                      :frozen => "Frozen (nothing moves at all)"]

"""
    sense_motion!(game, dir; seconds = 3, fps = 30) -> (; text, images)

Lumi's sense of motion (see the top of this file): `seconds` of the world measured frame by frame,
and the pictures of `film_motion!` in `dir`. The game's camera takes over again on its next frame.
"""
function sense_motion!(g::Game, dir::AbstractString; seconds::Real = 3, fps::Int = 30)
    mkpath(dir)
    n = round(Int, seconds * fps)
    tracks = Dict{Int32,MotionTrack}()
    for _ in 1:n
        Base.invokelatest(frame!, g, 1 / fps)
        record_motion!(tracks, g)
    end
    faults = motion_faults(tracks, n, fps)
    io = IOBuffer()
    @printf(io, "Measured from what is drawn: %d creatures over %g s at %d frames a second.\n", length(faults), seconds, fps)
    for (kind, title) in MOTION_KINDS
        hits = [(name, [d for (k, d, _) in fs if k === kind]) for (name, fs) in faults]
        filter!(h -> !isempty(h[2]), hits)
        isempty(hits) && continue
        println(io, "- ", title, ": ", join(("$name: " * join(first(ds, 3), ", ") for (name, ds) in first(hits, 8)), "; "),
                length(hits) > 8 ? "; and $(length(hits) - 8) more" : "")
    end
    fine = count(((_, fs),) -> isempty(fs), faults)
    println(io, "- Moving well: $fine of $(length(faults)).")
    # the one that moves worst (frozen ones are no film), else Lumi
    weight(fs) = sum((w for (k, _, w) in fs if k !== :frozen); init = 0.0)
    who = isempty(faults) || maximum(weight ∘ last, faults) == 0 ? "Lumi" : first(faults[argmax(map(weight ∘ last, faults))])
    images = film_motion!(g, dir, who, [c.name for c in first(g.world.creatures, 12)]; fps)
    println(io, "Look at these, they are the motion itself:")
    println(io, "- $(images.steps): $who, 8 consecutive frames 1/$fps s apart (jitter, snaps)")
    println(io, "- $(images.strip): $who, 24 frames at 10 frames a second, 2.4 s as it plays (how it moves)")
    println(io, "- $(images.closeups): every creature up close, 3 moments 0.4 s apart each (broken, detached or floating parts)")
    return (; text = String(take!(io)), images = collect(images))
end

"""
    closeup_view(world, creature) -> (eye, target)

A close three-quarter view of a creature's face, turned round it until nothing is in the way:
`obstruction`, and bushes right beside it on the eye's side (which `obstruction` lets pass, so the
game can watch a creature at a bush).
"""
function closeup_view(w::World, c::Creature)
    sp = species_of(c)
    target = c.pos + Point3f(0, 0, 0.6f0 * sp.height)
    z = clamp(sp.height / 1.2f0, 0.6f0, 1.2f0)
    heading = c.yaw + sp.heading
    best = (Inf32, target + Point3f(2z * cos(heading), 2z * sin(heading), z))
    for d in (2.2f0 * z, 1.6f0 * z, 3.0f0 * z), lift in (0.35f0, 0.7f0),
        turn in (0.6f0, -0.6f0, 0.2f0, -0.2f0, 1.1f0, -1.1f0, 1.6f0, -1.6f0, 2.4f0, -2.4f0, Float32(pi))
        a = heading + turn
        eye = target + Point3f(d * cos(a), d * sin(a), lift * d)
        score = obstruction(w, eye, target) + bushes_between(w, eye, target)
        score < best[1] && (best = (score, eye))
        score == 0 && break
    end
    return best[2], target
end

bushes_between(w::World, eye, target) =
    sum((max(0.0f0, 0.75f0 * p.scale - segment_distance(eye, target, p.pos + Point3f(0, 0, 0.45f0 * p.scale)))
         for p in w.props if p.kind === :bush && dot(Vec3f(p.pos - target), Vec3f(eye - target)) > 0); init = 0.0f0)

"""
    shots!(game, dir, names; moments, every, fps) -> Matrix{String}

Pictures of each creature in `names` from close by at `moments` moments, `every` frames (1/fps
each) apart: `[moment, creature]`. Each creature's camera is chosen once (`closeup_view`) and
then moves along with it, so its own motion shows against a steady background.
"""
function shots!(g::Game, dir::AbstractString, names::Vector{String}; moments::Int, every::Int, fps::Int)
    paths = Matrix{String}(undef, moments, length(names))
    views = Dict{String,Tuple{Vec3f,Vec3f}}()
    for m in 1:moments
        for _ in 1:every
            Base.invokelatest(frame!, g, 1 / fps)
        end
        for (j, name) in enumerate(names)
            c = creature(g.world, name)
            eye, target = get!(views, name) do
                e, t = closeup_view(g.world, c)
                (Vec3f(e - c.pos), Vec3f(t - c.pos))
            end
            look!(g.stage.scene, c.pos + eye, c.pos + target)
            sync_text!(g.stage, g.world)
            paths[m, j] = joinpath(dir, "shot-$(m)-$(j).png")
            Makie.save(paths[m, j], view_pixels(g))
        end
    end
    return paths
end

"`files` tiled `columns` wide into `path`, each `width` pixels wide; the files are used up."
function tile!(path::AbstractString, files::AbstractVector{String}; columns::Int, width::Int)
    dir = mktempdir()
    foreach(((i, f),) -> mv(f, joinpath(dir, "t$i.png")), enumerate(files))   # ffmpeg reads a numbered row
    rows = cld(length(files), columns)
    run(`ffmpeg -v error -y -i $(joinpath(dir, "t%d.png")) -vf "scale=$width:-2,tile=$(columns)x$(rows)" -frames:v 1 -update 1 $path`)
    rm(dir; recursive = true)
    return path
end

"""
    film_motion!(game, dir, who, everyone; fps) -> (; steps, strip, closeups)

The pictures of the sense of motion in `dir`: `who` in 8 consecutive frames and in 24 frames at
10 frames a second, and everyone up close at 3 moments. Without the overlay (names, bubbles); the
game's camera takes over again on its next frame.
"""
function film_motion!(g::Game, dir::AbstractString, who::String, everyone::Vector{String}; fps::Int)
    st = g.stage
    shown = st.overlay.visible[]
    st.overlay.visible[] = false
    tmp = mktempdir()
    steps = tile!(joinpath(dir, "motion.png"), vec(shots!(g, tmp, [who]; moments = 8, every = 1, fps)); columns = 4, width = 480)
    strip = tile!(joinpath(dir, "motion-strip.png"), vec(shots!(g, tmp, [who]; moments = 24, every = fps ÷ 10, fps));
                  columns = 6, width = 320)
    # creature by creature (a row holds two), each at its 3 moments
    closeups = tile!(joinpath(dir, "creatures.png"), vec(shots!(g, tmp, everyone; moments = 3, every = round(Int, 0.4fps), fps));
                     columns = 6, width = 320)
    rm(tmp; recursive = true)
    st.overlay.visible[] = shown
    return (; steps, strip, closeups)
end

function live_command(g::Game, ::Val{:motion}, msg)
    g.screen === nothing && return Dict{String,Any}("ok" => false, "error" => "the game runs headless")
    # without a "dir" the pictures go to media/motion (todo #531: a call without one failed with a KeyError)
    r = sense_motion!(g, String(get(msg, "dir", joinpath(g.paths.media, "motion"))))
    return Dict{String,Any}("ok" => true, "text" => r.text, "images" => r.images)
end
