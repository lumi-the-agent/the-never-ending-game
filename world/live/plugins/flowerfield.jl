# The golden flower field south of the cottage (meadow.jl paints its colour): planted thick with flowers,
# once (they are world props, saved in world.json, so Lumi and the critters can pick them for gifts).
const NG = NeverendingGame
import Random

const FIELD_FLOWERS = 60   # s43: thicker, so the golden field reads from the overview

flat(a, b) = hypot(a[1] - b[1], a[2] - b[2])

function plant_field!(game)
    w = game.world
    m = get(game.plugins, "meadow", nothing)
    m === nothing && return 0
    c, r = m.mod.FLOWER_FIELD
    # the field moved (s42: from behind the pines to the open meadow in front of the overview): its old flowers go
    filter!(p -> !(p.kind === :flower && get(p.data, "field", false) == true && flat(p.pos, c) > r), w.props)
    have = count(p -> p.kind === :flower && get(p.data, "field", false) == true, w.props)
    have >= FIELD_FLOWERS && return 0      # tops a field up to FIELD_FLOWERS (s43: 34 -> 60)
    a = get(game.plugins, "areas", nothing)
    site = isdefined(Main, :CAIRN_STATE) ? get(Main.CAIRN_STATE, :site, nothing) : nothing
    hues = [Float64(p.data["hue"]) for p in w.props if p.kind === :flower && haskey(p.data, "hue")]
    isempty(hues) && (hues = [0.0, 0.12, 0.75, 0.92])
    rng = Random.Xoshiro(w.island.seed + 808)
    n = have
    for _ in 1:900
        n >= FIELD_FLOWERS && break
        ang = 2pi * rand(rng); d = 0.8f0 * r * sqrt(rand(rng, Float32))
        q = Point3f(c[1] + d * cos(ang), c[2] + d * sin(ang), 0)
        NG.on_land(w.island, q[1], q[2]; margin = 1.5f0) || continue
        a !== nothing && Base.invokelatest(a.mod.in_the_way, (pos = q, kind = :flower)) && continue
        site !== nothing && flat(site, q) < 2.8f0 && continue
        any(p -> p.kind !== :ball && flat(p.pos, q) < (p.kind === :flower ? 0.45f0 : p.kind === :tree ? 1.6f0 * p.scale : 0.9f0 * p.scale), w.props) && continue
        any(x -> x isa NG.AssetActor && flat(x.pos, q) < 0.8f0 * x.scale + 0.5f0, w.actors) && continue
        NG.add_prop!(w, :flower, (q[1], q[2]); scale = 1.0f0 + 0.4f0 * rand(rng, Float32), hue = rand(rng, hues), field = true)
        n += 1
    end
    return n - have
end

mutable struct FlowerField <: System
    done::Bool
end
FlowerField() = FlowerField(false)

# planted on the first frame (meadow and areas may load after this plugin)
function NG.step!(s::FlowerField, game, dt)
    s.done && return
    s.done = true
    game.dash === nothing && return      # a quiet copy (clip, still) shows what the live world saved
    n = plant_field!(game)
    n > 0 && @info "flowerfield: planted $n flowers"
end

register!(FlowerField())
