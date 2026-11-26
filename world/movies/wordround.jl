# A word goes round (session 111, plugins/wordround.jl): four of us in a row on the meadow; a new word comes to me,
# the friend beside me overhears it, passes it on, the next one mishears it, and the misheard one goes on down the
# row. What everyone says comes from the plugin's own log of the take, as subtitles under the picture.
#   submit_job(:clip; path, script = "movies/wordround.jl", call = "wordround_clip", kwargs = Dict(...))
using NeverendingGame, Makie
const NG = NeverendingGame

function wordround_clip(path; rasterize = true, samples = 24, width = 854, height = 480, fps = 24, seconds = 14.0, hour = 9.5,
                        centre = (18.0, -4.0), cast = ["Gloop", "Truffle", "Pinchy"])
    S = Dict{Symbol,Any}()
    take = replace(path, r"\.mp4$" => "-take.mp4")
    shot = function (g, rig, t)
        w = g.world
        if !haskey(S, :go)
            S[:go] = true
            WR = Main.WORDROUND
            WR[:film] = true; WR[:round] = nothing
            names = vcat(["Lumi"], cast)
            row = Dict(n => k for (k, n) in enumerate(names))
            for c in w.creatures
                k = get(row, c.name, 0)
                if k == 0       # everyone else far off, out of earshot
                    p = NG.ground(w.island, (Float32(centre[1] - 40), Float32(centre[2] + 30 + c.id)))
                    c.pos = p; c.goal = NG.Goal(:idle, p, :idle, 60.0, w.t + 60, true, 0, false)
                    continue
                end
                x = Float32(centre[1] + (k - 2.5) * 1.75)
                p = NG.ground(w.island, (x, Float32(centre[2])))
                c.pos = p; c.action = :idle
                c.yaw = Float32(-pi / 2) - NG.species_of(c).heading     # facing the camera, a little
                c.goal = NG.Goal(:wordhear, p, :idle, 30.0, w.t + 30, true, 0, false)    # stay in the row
            end
            S[:t0] = w.t - t
            Base.invokelatest(g.plugins["wordround"].mod.begin_round!, g)
            S[:cast] = names
        end
        for c in w.creatures      # the row stays a row: anyone a pastime takes comes back to its place
            c.name in S[:cast] || continue
            c.goal.kind in (:wordhear, :wordtell) || (c.goal = NG.Goal(:wordhear, c.pos, :idle, 30.0, w.t + 30, true, 0, false))
        end
        c = NG.ground(w.island, (Float32(centre[1]), Float32(centre[2])))
        eye = Point3f(centre[1] + 0.4, centre[2] - 6.0, c[3] + 1.9)
        tg = Point3f(centre[1], centre[2], c[3] + 0.75)
        rig.mode = :fixed; rig.eye = eye; rig.target = tg
        g.rig.mode = :fixed; g.rig.eye = eye; g.rig.target = tg
        return seconds - 0.2
    end
    NG.game_clip(take; size = (width, height), seconds, fps, samples, hour, warmup = 1.0, rig = NG.CameraRig(; mode = :fixed),
                 rasterize, setup = g -> (Main.WORDROUND[:film] = true; nothing), shot)
    # subtitles from what was really said in this take
    r = Main.WORDROUND[:round]
    said = r === nothing ? Any[] : r[:said]
    t0 = r === nothing ? 0.0 : r[:t0] - S[:t0]
    dir = mktempdir()
    inputs = String[]; chain = String[]; last = "[0:v]"
    lines = [(t = s.t + t0, who = s.who, text = s.text) for s in said]
    for (k, s) in enumerate(lines)
        a = max(s.t, 0.0); b = k < length(lines) ? lines[k + 1].t : seconds
        png = joinpath(dir, "l$k.png")
        pt = round(Int, height / 20)
        txt = s.who * ":  " * s.text
        run(`magick -size $(width)x70 xc:none -font /usr/share/fonts/truetype/DejaVuSans-Bold.ttf -pointsize $pt -gravity center
             -stroke '#1a1410' -strokewidth $(max(2, pt ÷ 6)) -annotate +0+0 $txt -stroke none -fill '#fff4d6'
             -annotate +0+0 $txt PNG32:$png`)
        push!(inputs, "-i", png)
        out = "[v$k]"
        push!(chain, "$(last)[$(k):v]overlay=0:$(height - 86):enable='between(t,$(round(a; digits = 2)),$(round(b; digits = 2)))'$out")
        last = out
    end
    if isempty(chain)
        cp(take, path; force = true)
    else
        run(`ffmpeg -y -loglevel error -i $take $inputs -filter_complex $(join(chain, ";")) -map $last -c:v libx264 -pix_fmt yuv420p -crf 18 -t $seconds $path`)
    end
    k = r === nothing ? nothing : r[:knows]
    return (path = path, lines = [s.who * ": " * s.text for s in lines],
            knows = string(k),
            tree = r === nothing ? "" : string(r[:tree]))
end
