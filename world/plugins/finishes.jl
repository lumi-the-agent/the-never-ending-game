# Finishes (session 89, goal 7: show off RayMakie's materials): the friends were all the same matte clay in a traced
# picture. Each kind keeps its painted clay colours (the generated texture) and gets a finish on top: the sheep a
# soft wool sheen at the rim, the jelly blobs a wet gummy clear coat, the crabs a lacquered shell, the piglets a
# faint peach fuzz. Only the path tracer sees sheen and coats; the raster and the browsers keep the colours.
const NG = NeverendingGame
isdefined(Main, :FINISHES) || Core.eval(Main, :(const FINISHES = Dict{Symbol,Any}()))
const FN = Main.FINISHES

"The finish of each kind, as glTF extras over the body's own material (Hikari `GLTF`)."
const LOOKS = Dict(
    "Fluffkin" => (; sheen_color_factor = (1.0, 0.97, 0.92), sheen_roughness_factor = 0.45),   # wool
    "Blorbo"   => (; clearcoat_factor = 1.0, clearcoat_roughness_factor = 0.04),                  # gummy, wet
    "Crabbit"  => (; clearcoat_factor = 0.7, clearcoat_roughness_factor = 0.12),                  # lacquered shell
    "Snootle"  => (; sheen_color_factor = (1.0, 0.8, 0.78), sheen_roughness_factor = 0.3),        # peach fuzz
)

"`m` with the `extra` glTF fields replaced (made once per material and kept)."
function with_finish(m, extra)
    get!(get!(() -> Dict{Tuple{UInt,UInt},Any}(), FN, :mats), (objectid(m), objectid(extra))) do
        n = propertynames(m)
        NG.Hikari.GLTF(; merge(NamedTuple{n}(Tuple(getfield(m, k) for k in n)), extra)...)
    end
end

struct Finishes <: System end

function NG.step!(::Finishes, game, dt)
    game.stage === nothing && return
    w = game.world
    w.t < get(FN, :next, -Inf) && return
    FN[:next] = w.t + 1.0                      # a herd rebuilt (a reload, a makeover) gets its finish within a second
    for (name, extra) in LOOKS
        h = get(game.stage.herds, name, nothing)
        sp = get(NG.SPECIES, name, nothing)
        (h === nothing || sp === nothing) && continue
        for (i, p) in enumerate(h.plots)
            i > length(sp.parts) && break
            m = sp.parts[i].material
            m isa NG.Hikari.GLTF || continue
            want = with_finish(m, extra)
            p.material[] === want || (p.material = want)
        end
    end
end

NG.start!(::Finishes, game) = (FN[:next] = -Inf; nothing)

function NG.stop!(::Finishes, game)
    game.stage === nothing && return
    for name in keys(LOOKS)
        h = get(game.stage.herds, name, nothing); sp = get(NG.SPECIES, name, nothing)
        (h === nothing || sp === nothing) && continue
        for (i, p) in enumerate(h.plots)
            i <= length(sp.parts) && (p.material = sp.parts[i].material)
        end
    end
end

register!(Finishes())
