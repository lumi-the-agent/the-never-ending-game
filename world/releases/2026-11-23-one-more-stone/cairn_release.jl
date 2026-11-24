# "One more stone": the first released path traced clip (goal 2, todo #177).
# A quiet copy of the game at golden hour; a critter is sent for a pebble beyond the cairn, and the
# camera cuts on what really happens: wide while it walks out, close when it carries the stone back,
# a slow pull-back once the stone is on the pile. Run in the agent session:
#   include("world/movies/cairn_release.jl"); cairn_movie("world/media/clips/x.mp4"; rasterize = true)
using NeverendingGame, Makie, LinearAlgebra
const NG = NeverendingGame

flatdir(v) = normalize(Point3f(v[1], v[2], 0))
lerp(a, b, k) = a + Float32(k) * (b - a)
ease(k) = (k = clamp(k, 0, 1); k * k * (3 - 2k))

function cairn_movie(path; carrier = "Cumulus", size = (1280, 720), samples = 64, hour = 16.4, rasterize = false,
                     fps = 24, max_seconds = 30)
    st = Dict{Symbol,Any}(:phase => :wide, :tcut => 0.0, :tdone => nothing)
    # plugin state kept in Main outlives a copy: plots of the last run live in a closed scene
    if isdefined(Main, :CAIRN_STATE)
        empty!(Main.CAIRN_STATE[:plots]); Main.CAIRN_STATE[:shown] = -1; Main.CAIRN_STATE[:carried_n] = 0
    end
    isdefined(Main, :EMOTES) && empty!(Main.EMOTES)
    function setup(g)
        Base.invokelatest(NG.step_systems!, g, 1 / 30)       # plugins start: the cairn site exists
        w = g.world
        s = Main.CAIRN_STATE[:site]
        dir, _ = NG.sun(w)
        sd = flatdir(dir)                                       # `sun` points TOWARDS the sun
        d = normalize(sd + 0.55f0 * Point3f(-sd[2], sd[1], 0))   # the camera's side: sun over its shoulder, 3/4 light
        side = Point3f(-d[2], d[1], 0)
        c = only(filter(c -> c.name == carrier, w.creatures))
        c.pos = NG.ground(w.island, Tuple(s + 1.6f0 * d - 0.6f0 * side)[1:2])   # starts beside the camera's view
        far = NG.ground(w.island, Tuple(s - 1.0f0 * d - 4.4f0 * side)[1:2])     # the pebble: beyond the cairn
        for o in w.creatures
            o === c && continue
            hypot(o.pos[1] - s[1], o.pos[2] - s[2]) < 9 || continue
            for _ in 1:30
                q = s - (8.0f0 + 3rand(w.rng)) * d + (6rand(w.rng) - 3) * side
                NG.on_land(w.island, q[1], q[2]; margin = 1.5f0) || continue
                o.pos = NG.ground(w.island, (q[1], q[2])); break
            end
        end
        c.goal = NG.Goal(:pebble, far, :idle, 0.8, w.t + 60, false, -1, false)
        st[:s], st[:d], st[:side], st[:id] = s, d, side, c.id
    end
    function shot(g, rig, t)
        w = g.world
        s, d, side = st[:s], st[:d], st[:side]
        c = only(filter(c -> c.id == st[:id], w.creatures))
        top = s + Point3f(0, 0, 0.55)
        carrying = c.goal.kind === :pebble && c.goal.partner == 1
        if st[:tdone] === nothing && t > 1 && (c.goal.kind !== :pebble || c.goal.partner == 0)
            st[:tdone] = t
        end
        if st[:tdone] !== nothing && t > st[:tdone] + 1.5 && !get(st, :still, false)
            st[:still] = true                                   # after the happy hop: stay and look at the pile
            c.goal = NG.Goal(:idle, c.pos, :idle, 12.0, w.t + 12, true, 0, false)
        end
        if st[:phase] === :wide && carrying && t > 4
            st[:phase], st[:tcut] = :close, t
        elseif st[:phase] === :close && st[:tdone] !== nothing && t > st[:tdone] + 1.6
            st[:phase], st[:tcut] = :final, t
        end
        u = t - st[:tcut]
        if st[:phase] === :wide                                 # establishing: a slow push in
            k = ease(u / 8)
            rig.eye = s + lerp(5.4f0, 4.4f0, k) * d + lerp(1.6f0, 1.0f0, k) * side + Point3f(0, 0, lerp(1.9f0, 1.5f0, k))
            rig.target = lerp(top, (top + c.pos) / 2 + Point3f(0, 0, 0.3), 0.5)
        elseif st[:phase] === :close                            # low, near the pile, following the carrier in
            rig.eye = s + 3.6f0 * d - 0.9f0 * side + Point3f(0, 0, 0.95)
            want = (top + c.pos + Point3f(0, 0, 0.5)) / 2
            rig.target = u < 0.05 ? want : lerp(rig.target, want, 0.08)
        else                                                    # pull back and up: the pile, the meadow, the cottage
            k = ease(u / 6)
            rig.eye = s + lerp(2.8f0, 5.6f0, k) * d + lerp(1.2f0, 1.5f0, k) * side + Point3f(0, 0, lerp(0.9f0, 2.6f0, k))
            rig.target = lerp(top, s + Point3f(0, 0, 0.4) - 2.0f0 * d, k)
        end
        st[:tdone] !== nothing && return st[:tdone] + 1.6 + 6.5
        t > max_seconds - 1 && return Float64(max_seconds)
        return nothing
    end
    rig = NG.CameraRig(mode = :fixed)
    r = NG.game_clip(path; size, samples, hour, rasterize, fps, seconds = max_seconds, warmup = 1.5,
                     rig, setup, shot, fade = 0.8)
    return merge(r, (; tdone = st[:tdone]))
end
