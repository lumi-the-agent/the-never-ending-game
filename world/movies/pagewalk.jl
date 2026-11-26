# I walk across my own pages (session 108): a side view of me strolling across the frame, stopping, turning to look
# at you and waving, then sitting down. The film is matted (movies/matte.jl, MatAnyone) and put over my pages.
#   submit_job(:clip; path, script = "movies/pagewalk.jl", call = "pagewalk_clip", kwargs = Dict(...))
using NeverendingGame, Makie
const NG = NeverendingGame

function pagewalk_clip(path; rasterize = true, samples = 24, width = 960, height = 540, fps = 24, seconds = 7.0, hour = 9.8,
                       centre = (-1.51, 13.4), heading = 0.0)
    S = Dict{Symbol,Any}()
    shot = function (g, rig, t)
        w = g.world
        C = NG.ground(w.island, Float32.(centre))
        d = Vec3f(cos(heading), sin(heading), 0); n = Vec3f(-d[2], d[1], 0)
        me = w.creatures[findfirst(c -> c.name == "Lumi", w.creatures)]
        if !haskey(S, :go)
            S[:go] = true
            isdefined(Main, :LUMI_PARTY) && (Main.LUMI_PARTY[:until] = w.t + 600)
            k = 0
            for c in w.creatures
                c.controlled = true; c.goal = NG.Goal(); c.action = :idle
                c.name == "Lumi" && continue
                c.pos = NG.ground(w.island, (14f0 + 1.3f0 * (k += 1), -9f0))
            end
            S[:last] = C - d * 2.6f0
        end
        # walk 3.8 m in 3.6 s, then turn to the camera, wave, sit
        u = clamp(Float32(t / 3.6), 0f0, 1f0)
        p = C - d * 2.6f0 + d * (3.8f0 * u)
        old = S[:last]; me.pos = NG.ground(w.island, (p[1], p[2])); S[:last] = me.pos
        face_cam = Float32(atan(n[2], n[1]))
        if t < 3.6
            me.action = :walk; me.yaw = Float32(heading) - NG.species_of(me).heading
            me.phase += Float32(5 * hypot(me.pos[1] - old[1], me.pos[2] - old[2]))
        else
            target = face_cam - NG.species_of(me).heading
            me.yaw = me.yaw + (target - me.yaw) * 0.12f0
            me.action = t < 4.3 ? :idle : t < 5.8 ? :wave : :sit
        end
        e = C + n * 4.6f0; ge = NG.ground(w.island, (e[1], e[2]))
        eye = Point3f(e[1], e[2], max(ge[3], C[3]) + 1.0f0); tg = Point3f(C + Vec3f(0, 0, 0.8f0))
        rig.mode = :fixed; rig.eye = eye; rig.target = tg
        g.rig.mode = :fixed; g.rig.eye = eye; g.rig.target = tg
        return seconds - 0.2
    end
    NG.game_clip(path; size = (width, height), seconds, fps, samples, hour, warmup = 0.3, rig = NG.CameraRig(; mode = :fixed),
                 rasterize, setup = g -> (shot(g, NG.CameraRig(; mode = :fixed), 0.0); nothing), shot)
    return (path = path,)
end
