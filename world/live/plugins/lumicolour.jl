# Lumi's own yellow in the live picture (session 83, perfectionist s82: "a golden-yellow bird when path traced, a
# dark brown owl-like bird in the raster a few seconds later"). The raster and the browsers draw Lumi with copies
# of its feather texture (bird.jl `skin`/`plain`), and the raster's light darkens that orange-gold into ochre and
# rust. This lifts those copies towards a warm yellow, green most (orange to yellow), the painted face's feathers
# too (its whites and blacks stay), and leaves the path traced material alone. It follows the herd when something rebuilds it (a publish, the giant).
isdefined(Main, :LUMI_COLOUR) || Core.eval(Main, :(const LUMI_COLOUR = Dict{Symbol,Any}()))
const NG = NeverendingGame
const LC = Main.LUMI_COLOUR

const GAIN = (1.22f0, 1.52f0, 1.25f0)      # red, green, blue: the mean texel (0.76, 0.57, 0.10) becomes (0.93, 0.87, 0.13)

struct LumiColour <: System end

lift(c) = Makie.RGBA{Float32}(min(1f0, Makie.red(c) * GAIN[1]), min(1f0, Makie.green(c) * GAIN[2]),
                              min(1f0, Makie.blue(c) * GAIN[3]), Makie.alpha(c))

"A plot's texture copy lifted, once (the originals kept by objectid so nothing is lifted twice)."
function lift_plot!(p)
    c = p.color[]
    c isa AbstractMatrix || return
    orig = get!(() -> Dict{UInt,Any}(), LC, :orig)
    haskey(orig, objectid(c)) && return           # already a lifted copy
    lifted = map(lift, c)
    orig[objectid(lifted)] = c
    p.color = lifted
end

"Lumi's little one (egg.jl) is drawn with Lumi's own parts: the same yellow (looked for every 2 s)."
function chicks!(game)
    time() - get(LC, :chicks_at, 0.0) < 2 && return
    LC[:chicks_at] = time()
    done = get!(() -> Set{UInt}(), LC, :chicks)
    for p in game.stage.scene.plots
        haskey(p.attributes, :name) || continue
        n = string(p.attributes[:name][])
        (startswith(n, "chick_") && n != "chick_peep") || continue
        objectid(p) in done && continue
        push!(done, objectid(p))
        lift_plot!(p)
    end
end

function NG.step!(::LumiColour, game, dt)
    game.stage === nothing && return
    chicks!(game)
    h = get(game.stage.herds, "Lumi", nothing)
    h === nothing && return
    key = (objectid(h), GAIN)
    get(LC, :done, nothing) == key && return
    for (i, p) in enumerate(h.plots)
        c = p.color[]
        c isa AbstractMatrix || continue
        orig = get!(() -> Dict{UInt,Any}(), LC, :orig)
        base = get!(orig, objectid(c), c)      # never lift a lifted copy twice
        lifted = map(lift, base)
        orig[objectid(lifted)] = base
        p.color = lifted
    end
    LC[:done] = key
end

NG.start!(::LumiColour, game) = (delete!(LC, :done); nothing)

register!(LumiColour())
