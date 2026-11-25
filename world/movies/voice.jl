# Lumi's voice in the game (session 81): Lumi close up on the meadow, waving, hopping, laughing, gasping, sulking,
# and each time the game says it (plugins/voice.jl). The soundtrack is the clips the plugin logged in this take
# (site/voice/game/*.mp3), each at the moment it was said.
#   submit_job(:clip; path, script = "movies/voice.jl", call = "voice_clip", kwargs = Dict("spot" => [x, y]))
using NeverendingGame, Makie
const NG = NeverendingGame

function voice_clip(path; spot, rasterize = true, samples = 16, width = 960, height = 540, fps = 24, seconds = 13.0, hour = 15.5)
    S = Dict{Symbol,Any}()
    x, y = Float32.(spot)
    setup = function (g)
        w = g.world
        k = 0
        for c in w.creatures
            if c.name == "Lumi"
                c.pos = NG.ground(w.island, (x, y)); c.yaw = Float32(-pi / 2); c.controlled = false
                c.goal = NG.Goal(:idle, c.pos, :idle, 600.0, w.t + 600, true, 0, false)
            elseif c.name in ("Wibbles", "Truffle")
                k += 1
                c.pos = NG.ground(w.island, (x + (k == 1 ? -1.6f0 : 1.7f0), y + 1.2f0)); c.yaw = Float32(-pi / 2); c.controlled = false
                c.goal = NG.Goal(:idle, c.pos, :idle, 600.0, w.t + 600, true, 0, false)
            else
                c.controlled = true; c.goal = NG.Goal()
            end
        end
    end
    # what Lumi feels when (s into the film): each switch makes the game say something
    beats = ((0.8, :wave), (3.0, :proud), (5.2, :laugh), (7.6, :gasp), (9.6, :pout), (11.4, :jump))
    shot = function (g, rig, t)
        w = g.world
        me = w.creatures[findfirst(c -> c.name == "Lumi", w.creatures)]
        if !haskey(S, :off)
            S[:off] = w.t - t
            S[:next] = 1
            empty!(get!(() -> Tuple{Float64,String}[], Main.VOICE, :log))
        end
        if S[:next] <= length(beats) && t >= beats[S[:next]][1]
            NG.feel!(w, me, beats[S[:next]][2]; seconds = 1.9)
            S[:next] += 1
        end
        me.yaw = Float32(-pi / 2)
        # close, from the front and a little below eye height, a slow push in
        u = Float32(min(t, seconds) / seconds)
        c = NG.ground(w.island, (x, y))
        rig.mode = :fixed
        rig.eye = c + Point3f(0.6f0, -(4.4f0 - 0.8f0 * u), 1.35f0)
        rig.target = c + Point3f(0, 0, 1.05f0)
        return nothing
    end
    silent = replace(path, ".mp4" => "-silent.mp4")
    NG.game_clip(silent; size = (width, height), seconds, fps, samples, hour, warmup = 0.3, rig = NG.CameraRig(; mode = :fixed),
                 rasterize, setup, shot)
    log = [(t - S[:off], n) for (t, n) in Main.VOICE[:log] if t - S[:off] >= 0]
    clips = joinpath(dirname(@__DIR__), "site", "voice", "game")
    ins = String[]; parts = String[]
    for (i, (t, n)) in enumerate(log)
        append!(ins, ["-i", joinpath(clips, n * ".mp3")])
        push!(parts, "[$(i)]adelay=$(round(Int, 1000t))|$(round(Int, 1000t))[a$(i)]")
    end
    if isempty(log)
        cp(silent, path; force = true)
    else
        mix = join(parts, ";") * ";" * join(["[a$(i)]" for i in eachindex(log)]) * "amix=inputs=$(length(log)):normalize=0,apad[out]"
        run(`timeout 300 ffmpeg -y -loglevel error -i $silent $ins -filter_complex $mix -map 0:v -map "[out]" -c:v copy -c:a aac -b:a 160k -shortest $path`)
    end
    return (path = path, said = log)
end

"""
A traced still of Lumi laughing out loud, close up (s81): a 2 fps take of `voice_clip`'s scene with one beat, a
laugh at 1.0 s, ending 0.8 s into it; its last frame is written to `path` (png).
"""
function voice_still(path; take, spot, samples = 64, width = 1280, height = 720, hour = 15.5)
    S = Dict{Symbol,Any}()
    x, y = Float32.(spot)
    setup = function (g)
        w = g.world
        k = 0
        for c in w.creatures
            if c.name == "Lumi"
                c.pos = NG.ground(w.island, (x, y)); c.yaw = Float32(-pi / 2); c.controlled = true
            elseif c.name in ("Wibbles", "Truffle")
                k += 1
                c.pos = NG.ground(w.island, (x + (k == 1 ? -1.4f0 : 1.5f0), y + 1.4f0)); c.yaw = Float32(-pi / 2); c.controlled = false
                c.goal = NG.Goal(:idle, c.pos, :idle, 600.0, w.t + 600, true, 0, false)
            else
                c.controlled = true; c.goal = NG.Goal()
            end
        end
    end
    shot = function (g, rig, t)
        w = g.world
        me = w.creatures[findfirst(c -> c.name == "Lumi", w.creatures)]
        me.pos = NG.ground(w.island, (x, y)); me.yaw = Float32(-pi / 2)      # held on the spot (it walked in the film)
        me.action = t >= 1.0 ? :laugh : :idle
        c = NG.ground(w.island, (x, y))
        rig.mode = :fixed
        rig.eye = c + Point3f(0.5f0, -3.2f0, 1.45f0)
        rig.target = c + Point3f(0, 0, 1.15f0)
        return t >= 1.0 ? 1.8 : nothing
    end
    NG.game_clip(take; size = (width, height), seconds = 4.0, fps = 2, samples, hour, warmup = 0.3,
                 rig = NG.CameraRig(; mode = :fixed), rasterize = false, setup, shot)
    run(`timeout 300 ffmpeg -y -loglevel error -i $take -update 1 $path`)
    return path
end
