# The camera has a mood (session 107, plugins/moodcam.jl): the camera watches me, gets bored, drifts off to a flower
# on the shore and stares at it with the sea behind, then sighs back to me.
#   submit_job(:clip; path, script = "movies/moodcam.jl", call = "moodcam_clip", kwargs = Dict(...))
using NeverendingGame, Makie
const NG = NeverendingGame

function moodcam_clip(path; rasterize = true, samples = 24, width = 960, height = 540, fps = 24, seconds = 10.0, hour = 9.6,
                      flower = (-3.44, 18.55), lumi = (-1.51, 13.4))
    S = Dict{Symbol,Any}()
    ease(u) = (u = clamp(u, 0f0, 1f0); u * u * (3 - 2u))
    mix(a, b, u) = a + (b - a) * u
    shot = function (g, rig, t)
        w = g.world
        F = NG.ground(w.island, Float32.(flower)); L = NG.ground(w.island, Float32.(lumi))
        d = Vec3f(L[1] - F[1], L[2] - F[2], 0); d = d / hypot(d[1], d[2])      # from the flower inland, to me
        s = Vec3f(-d[2], d[1], 0)
        if !haskey(S, :go)
            S[:go] = true
            isdefined(Main, :LUMI_PARTY) && (Main.LUMI_PARTY[:until] = w.t + 600)
            k = 0
            for c in w.creatures
                c.controlled = true; c.goal = NG.Goal(); c.action = :idle
                c.name == "Lumi" && continue
                hypot(c.pos[1] - L[1], c.pos[2] - L[2]) < 14 && (c.pos = NG.ground(w.island, (12f0 + 1.3f0 * (k += 1), -8f0)))
            end
            me = w.creatures[findfirst(c -> c.name == "Lumi", w.creatures)]
            me.pos = L; me.yaw = Float32(atan(-s[2], -s[1])) - NG.species_of(me).heading   # looking along the shore
        end
        me = w.creatures[findfirst(c -> c.name == "Lumi", w.creatures)]
        # me: a front three-quarter view, as the follow camera has it
        fwd = Vec3f(-s[1], -s[2], 0)
        eye1 = Point3f(L + fwd * 3.2f0 + d * 1.2f0 + Vec3f(0, 0, 1.4f0)); tg1 = Point3f(L + Vec3f(0, 0, 0.9f0))
        # the flower on the shore, the sea behind it (moodcam.jl `distraction`)
        eye2 = Point3f(F + d * 1.5f0 + s * 0.5f0 + Vec3f(0, 0, 0.7f0)); tg2 = Point3f(F + Vec3f(0, 0, 0.3f0))
        u = t < 2.5 ? 0f0 : t < 5.0 ? ease(Float32((t - 2.5) / 2.5)) : t < 7.5 ? 1f0 : 1f0 - ease(Float32((t - 7.5) / 2.3))
        # while the camera stares, I notice it is gone and turn to look for it
        if t > 6.0
            a = Float32(atan(eye1[2] - L[2], eye1[1] - L[1])) - NG.species_of(me).heading
            me.yaw = me.yaw + (a - me.yaw) * 0.08f0
            me.action = t > 8.6 ? :wave : :idle
        end
        eye = Point3f(mix(eye1, eye2, u)); tg = Point3f(mix(tg1, tg2, u))
        rig.mode = :fixed; rig.eye = eye; rig.target = tg
        g.rig.mode = :fixed; g.rig.eye = eye; g.rig.target = tg
        return seconds - 0.2
    end
    NG.game_clip(path; size = (width, height), seconds, fps, samples, hour, warmup = 0.3, rig = NG.CameraRig(; mode = :fixed),
                 rasterize, setup = g -> (S[:early] = true; shot(g, NG.CameraRig(; mode = :fixed), 0.0); nothing), shot)
    return (path = path,)
end
