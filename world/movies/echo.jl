# The island answers a clap (s129): Lumi claps at two places, the camera stands where the ear is, and the sound
# is the clap through the island's echo, ray traced off its real geometry (physics/echo.jl, Raycore BVH): at
# (-4, 10) by the pond the late echo is -20 dB, at (-4, -8) -28 dB. The wav is computed in my session (media/s129-echo/).
#   submit_job(:clip; path, script = "movies/echo.jl", call = "echo_clip", kwargs = Dict(...))
using NeverendingGame, Makie
const NG = NeverendingGame

function echo_clip(path; wav, rasterize = false, samples = 24, width = 960, height = 540, fps = 24, seconds = 9.5,
                   hour = 17.3, spots = [(-4f0, 10f0), (-4f0, -8f0)], ears = [(-1.5f0, -1.5f0), (0f0, -2f0)],
                   claps = [1.6, 6.1], cut = 4.6)
    S = Dict{Symbol,Any}()
    place! = function (g, k)
        w = g.world; me = NG.creature(w, "Lumi")
        x, y = spots[k]
        me.pos = NG.ground(w.island, (x, y)); me.controlled = true; me.goal = NG.Goal()
        me.yaw = atan(ears[k][2], ears[k][1]) - NG.species_of(me).heading    # face the camera
        me.action = :idle
        S[:k] = k
    end
    setup = function (g)
        for p in g.stage.scene.plots
            haskey(p.attributes, :name) && p.attributes[:name][] in (:rain, :rainrings, :raincloud) && (p.visible[] = false)
        end
        isdefined(Main, :SHOWERS) && (Main.SHOWERS[:off] = true)
        place!(g, 1)
    end
    shot = function (g, rig, t)
        k = t < cut ? 1 : 2
        get(S, :k, 0) == k || place!(g, k)
        me = NG.creature(g.world, "Lumi")
        x, y = spots[k]; z = me.pos[3] + 0.6f0
        rig.mode = :fixed
        rig.eye = Point3f(x + ears[k][1], y + ears[k][2], z + 0.5f0)   # the ear, where the sound was computed
        rig.target = Point3f(x, y, z + 0.15f0)
        me.controlled = true
        me.action = abs(t - claps[k]) < 0.35 ? :wave : :idle      # the clap
        return nothing
    end
    silent = replace(path, ".mp4" => "-silent.mp4")
    NG.game_clip(silent; size = (width, height), seconds, fps, samples, hour, warmup = 0.3, rasterize,
                 rig = NG.CameraRig(; mode = :fixed), setup, shot, fade = 0.4)
    run(`timeout 300 ffmpeg -y -loglevel error -i $silent -i $wav -map 0:v -map 1:a -c:v copy -c:a aac -b:a 160k -shortest $path`)
    return (path = path, wav = wav)
end
