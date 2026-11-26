# Matting me out of a film (session 108): SAM 2 marks me on one frame, MatAnyone carries a soft alpha matte through
# every frame, and the frames become a see-through VP9 webm that my pages lay over their text.
#   submit_job(:clip; path = ".../site/films/x.webm", script = "movies/matte.jl", call = "matte_clip",
#              kwargs = Dict("film" => ".../take.mp4", "clicks" => [[0.6, 0.55]], "seed_frame" => 1))
using NeverendingGame, Makie
const NG = NeverendingGame
const C = Makie.Colors

"A JuliaVision runner from its checkout (the game's Project.toml is read only; its deps are in the Manifest)."
function runner(name, uuid)
    p = joinpath("/sim/Programmieren/SimGame/dev/JuliaVision", name)
    p in LOAD_PATH || push!(LOAD_PATH, p)
    return Base.require(Base.PkgId(Base.UUID(uuid), name))
end

function matte_clip(path; film, clicks = [[0.5, 0.6]], seed_frame = 1, hflip = true, fps = 24, track = nothing)
    SAM = runner("SAM2Runner", "3f5b1e8a-9d42-4c7e-b16a-2c9d0e4f7a51")
    MA = runner("MatAnyoneRunner", "7c4d9e15-2b83-4f6a-a0d7-3e1b8f5c9a24")
    src = mktempdir(); out = mktempdir()
    run(`ffmpeg -loglevel error -i $film $src/f%04d.png`)
    files = sort(filter(endswith(".png"), readdir(src)))
    frames = [permutedims(C.RGB{C.N0f8}.(Makie.FileIO.load(joinpath(src, f)))) for f in files]    # (W, H): x first
    pts = [(Float64(c[1]), Float64(c[2])) for c in clicks]
    seed = Base.invokelatest(getglobal(SAM, :segment), frames[seed_frame], pts)
    prop = Base.invokelatest(getglobal(MA, :matanyonepropagator))
    alpha = Base.invokelatest(prop, frames, Dict(seed_frame => seed))                               # (W, H, n) UInt8
    W, H = size(frames[1])
    # the propagated matte picked up the cottage and the signpost as I passed in front of them: keep only what SAM 2
    # finds as ME on each frame (a click where I am, `track(k)` -> (x, y) normalized), grown by a few pixels
    if track !== nothing
        r = 6
        for k in eachindex(frames)
            pts = track(k)
            m = Base.invokelatest(getglobal(SAM, :segment), frames[k], pts)
            keep = falses(W, H)
            if count(>(127), m) > 2500
                for I in findall(>(127), m), dx in -r:r, dy in -r:r
                    x, y = I[1] + dx, I[2] + dy
                    (1 <= x <= W && 1 <= y <= H) && (keep[x, y] = true)
                end
            else
                # SAM missed me on this frame (a click beside a thin turning body): keep MatAnyone's matte in a band
                # round where I walk, so I never blink out (the s108 second and third mattes flickered)
                cx = pts[1][1] * W
                for x in max(1, round(Int, cx - 0.085W)):min(W, round(Int, cx + 0.085W))
                    keep[x, :] .= true
                end
            end
            a = view(alpha, :, :, k)
            a[.!keep] .= 0x00
        end
    end
    for k in eachindex(frames)
        f = frames[k]
        img = [C.RGBA{C.N0f8}(f[x, y].r, f[x, y].g, f[x, y].b, reinterpret(C.N0f8, alpha[x, y, k])) for y in 1:H, x in 1:W]
        Makie.FileIO.save(joinpath(out, "a" * lpad(k, 4, '0') * ".png"), img)
    end
    vf = hflip ? "hflip,format=yuva420p" : "format=yuva420p"
    run(`ffmpeg -loglevel error -y -framerate $fps -i $out/a%04d.png -vf $vf -c:v libvpx-vp9 -pix_fmt yuva420p -b:v 1500k -auto-alt-ref 0 -an $path`)
    cover = sum(Float64, alpha) / (255 * length(alpha))
    return (path = path, frames = length(frames), seed_pixels = count(>(127), seed), coverage = round(cover; digits = 3))
end

"The walk in movies/pagewalk.jl: where I am on frame k (24 fps), from (0.875, 0.32) walking left to 0.33 in 3.6 s."
function pagewalk_track(k)
    x = 0.875 - 0.545 * min((k - 1) / 24 / 3.6, 1.0)
    # several points on me (one click on a waving wing gave only the wing; sitting I am lower)
    return [(x, 0.30), (x, 0.40), (x + 0.015, 0.35)]
end

matte_pagewalk(path; kw...) = matte_clip(path; track = pagewalk_track, kw...)
