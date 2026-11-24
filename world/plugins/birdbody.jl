# Lumi's own moves on its bird body (s59, engine bird.jl `Birdy`: a strut with the feet planted,
# fidgets while it waits, a droop when sad, a happy hop, a rocking stop). A game that started before that engine
# code built Lumi with the plain parts; this swaps the live herd's species once, so the moves
# arrive with `publish()` instead of the next restart. Nothing happens on an engine without `Birdy`.
const NG = NeverendingGame

struct BirdBody <: System end

const DONE = Ref(false)

"Lumi's last action and when it stopped walking."
const STOP = Dict{Symbol,Any}(:last => :idle, :at => -99.0)
const SETTLE = 1.2          # s the rocking after a stop lasts

function NG.step!(::BirdBody, game, dt)
    settle!(game.world)
    DONE[] && return
    (isdefined(NG, :Birdy) && game.stage !== nothing && haskey(game.stage.herds, "Lumi")) || return
    herd = game.stage.herds["Lumi"]
    DONE[] = true
    names = [p.name for p in herd.species[].parts]
    all(p -> p.motion isa NG.Birdy, herd.species[].parts) && (:crest in names || !isdefined(NG, :Wing)) && return
    sp = Base.invokelatest(NG.lumi)
    NG.register_species!(sp)
    if length(sp.parts) == length(names)
        herd.species = sp
    else          # s60: a body with more parts (the crest and wings on their own): a fresh herd, built by the next sync!
        delete!(game.stage.scene, herd)
        delete!(game.stage.herds, "Lumi")
    end
    return
end

"While Lumi stands idle right after walking, its `extra` says how fresh the stop is (1 → 0): bird.jl rocks it."
function settle!(w)
    b = findfirst(c -> c.species == "Lumi", w.creatures)
    b === nothing && return
    c = w.creatures[b]
    (STOP[:last] in (:walk, :run)) && c.action === :idle && (STOP[:at] = w.t)
    STOP[:last] = c.action
    age = w.t - STOP[:at]
    c.action === :idle && 0 <= age < SETTLE && (c.extra = Float32(1 - age / SETTLE))
    return
end

NG.stop!(::BirdBody, game) = (DONE[] = false; nothing)

register!(BirdBody())
