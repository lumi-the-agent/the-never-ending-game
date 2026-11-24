# A day in my new life (session 61, Lumi's wish): Lumi left to itself at one hour of the day, the
# camera watching its face the whole time. No puppeting: what it does is what it would do.
# One call is one scene; the worker renders one job per hour (morning, noon, afternoon).
#   include("world/movies/day_in_life.jl"); day_scene("media/s61/day-09.mp4"; hour = 9.0, rasterize = true)
using NeverendingGame, Makie, LinearAlgebra
const NG = NeverendingGame

function day_scene(path; hour = 9.0, rasterize = false, samples = 40, width = 960, height = 540, fps = 24,
                   seconds = 8.0, warmup = 6)
    S = Dict{Symbol,Any}()
    shot = function (g, rig, t)
        w = g.world
        b = only(filter(c -> c.species == "Lumi", w.creatures))
        # close and low, from the side of the face that is clearest (face_view backs off high over
        # the island when trees are near: Lumi a speck in the preview); keep the side while it is clear
        sh = NG.species_of(b).height
        target = b.pos + Point3f(0, 0, 0.6f0 * sh)
        head = b.yaw + NG.species_of(b).heading
        view(a) = (target + Point3f(3.4f0 * cos(head + a), 3.4f0 * sin(head + a), 0.9f0), target)
        # anything big within reach of the lens (a bush, a friend wandering past: the preview filled
        # with green) counts on top of `obstruction`
        function crowd(e)
            o = 0f0
            for p in w.props
                p.kind in (:bush, :tree) && (o += max(0f0, 1.0f0 * p.scale + 0.8f0 - hypot(p.pos[1] - e[1], p.pos[2] - e[2])))
            end
            for c in w.creatures
                c.id == b.id && continue
                # ahead along the line or beside the lens
                o += 2f0 * max(0f0, 1.6f0 - hypot(c.pos[1] - e[1], c.pos[2] - e[2]))
                o += max(0f0, 0.9f0 - NG.segment_distance(e, target, c.pos + Point3f(0, 0, 0.4f0)))
            end
            # the pond's reeds (drawn by areas.jl, not props) stood across Lumi's legs in the
            # s61 morning scene: any point of the sight line near the pond rim counts
            pond, pr = Point2f(-5.5, 10.5), 2.3f0
            for s in 0f0:0.1f0:0.9f0
                q = e + s * (target - e)
                abs(hypot(q[1] - pond[1], q[2] - pond[2]) - pr) < 0.5f0 && (o += 0.5f0)
            end
            return o
        end
        cost(x) = NG.obstruction(w, view(x)...) + crowd(view(x)[1])
        a = get(S, :side, 0.7f0)
        if cost(a) > 0.3f0
            a = argmin(x -> cost(x) + 0.05f0 * abs(x), (0.7f0, -0.7f0, 0.3f0, -0.3f0, 1.3f0, -1.3f0, 2.0f0, -2.0f0))
        end
        S[:side] = a
        eye, target = view(a)
        # first frame, a big jump, or the gliding eye ends up in a bush: cut
        if !haskey(S, :eye) || norm(eye - S[:eye]) > 4f0 || NG.obstruction(w, S[:eye], S[:target]) + crowd(S[:eye]) > 0.3f0
            S[:eye] = eye; S[:target] = target
        else                                                  # else a slow glide (about a second)
            S[:eye] += 0.04f0 * (eye - S[:eye]); S[:target] += 0.12f0 * (target - S[:target])
        end
        rig.mode = :fixed; rig.eye = S[:eye]; rig.target = S[:target]
        return nothing
    end
    NG.game_clip(path; size = (width, height), seconds, fps, samples, hour, warmup,
                 rig = NG.CameraRig(; mode = :fixed), rasterize, shot, fade = 0.6)
end
