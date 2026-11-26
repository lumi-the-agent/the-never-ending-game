# Reads what my friends wrote in pebbles (session 103, plugins/pebblewords.jl): a real text model (PP-OCRv6, dev/JuliaVision
# PPOCRRunner) looks at the picture of the pebbles from above and says what it reads; only that counts.
#   submit_job(:clip; path = image, script = "movies/ocr.jl", call = "read_pebbles")
using NeverendingGame, Makie
isdefined(Main, :OCRCACHE) || Core.eval(Main, :(const OCRCACHE = Dict{Symbol,Any}()))

function read_pebbles(path; kw...)
    dir = "/sim/Programmieren/SimGame/dev/JuliaVision/PPOCRRunner"
    dir in LOAD_PATH || push!(LOAD_PATH, dir)
    P = Base.require(Base.PkgId(Base.UUID("e16c7811-b8c1-4791-91d8-75b683fe5914"), "PPOCRRunner"))
    C = Main.OCRCACHE
    haskey(C, :model) || (C[:model] = Base.invokelatest(P.ppocr))
    img = permutedims(Makie.FileIO.load(path))                   # the model wants img[x, y]
    lines = Base.invokelatest(P.read_lines, C[:model], img)
    return (text = join([l.text for l in lines], " "), path = path)
end
