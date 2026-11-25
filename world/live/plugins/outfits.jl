# Outfits: every critter wears its own thing, so two of a kind are told apart at a glance
# (the perfectionist: "two pigs and a sheep are hard to tell apart, nothing reads as a personality").
# Sir Sniffsalot has a top hat, Pinchy a party hat, Pickles a green scarf, Gloop a flower crown...
# Each piece sits on a posed body part (pose_parts!, the same pose the herd draws), so a hat
# bobs, squashes and leans with its wearer. One meshscatter per (shape, colour), instanced over the wearers.
const NG = NeverendingGame

isdefined(Main, :OUTFIT_PLOTS) || Core.eval(Main, :(const OUTFIT_PLOTS = Dict{Symbol,Any}()))
const OP = Main.OUTFIT_PLOTS
const OUTFIT_VERSION = 16

"A piece of an outfit: `shape` at `off` (metres, in the anchor part's frame), size `scale`, turned by `tilt`."
struct Piece
    shape::Symbol
    off::Vec3f
    scale::Vec3f
    tilt::Vec3f
    color::RGBf
    show::Symbol       # :always; :talk a mouth that opens and shuts while its wearer speaks; :happy cheeks that blush when it is happy
end
piece(shape, off, scale, color; tilt = (0, 0, 0), show = :always) = Piece(shape, Vec3f(off), Vec3f(scale), Vec3f(tilt), RGBf(color...), show)

"How big a piece is now: a talking mouth chatters (taller), happy cheeks appear (mood above 0.6)."
function shown_scale(p::Piece, talking, mood, t, seed)
    p.show === :always && return p.scale
    if p.show === :talk
        talking || return p.scale
        o = abs(sin(11f0 * t + 6seed))
        return Vec3f(p.scale[1], p.scale[2] * (1 - 0.25f0 * o), p.scale[3] * (1 + 2.6f0 * o))
    end
    return mood > 0.6f0 ? p.scale * min(1f0, (mood - 0.6f0) / 0.15f0) : Vec3f(0)
end

"Where an outfit sits: a body part and a point on it (unit coordinates of the part: (0,0,1) is its top)."
struct Outfit
    part::Symbol
    at::Vec3f
    pieces::Vector{Piece}
    size::Float32        # the whole outfit scaled (offsets and pieces)
end
Outfit(part, at, pieces; size = 1.3) = Outfit(part, Vec3f(at), pieces, Float32(size))

# ── the wardrobe ────────────────────────────────────────────────────────────
top_hat(c, band) = [piece(:cylinder, (0, 0, -0.02), (0.2, 0.2, 0.025), c), piece(:cylinder, (0, 0, -0.02), (0.125, 0.125, 0.24), c),
                    piece(:cylinder, (0, 0, 0.0), (0.13, 0.13, 0.05), band)]
party_hat(c, pom) = [piece(:cone, (0, 0, -0.03), (0.11, 0.11, 0.3), c), piece(:sphere, (0, 0, 0.27), (0.05, 0.05, 0.05), pom),
                     piece(:torus, (0, 0, 0.0), (0.105, 0.105, 0.06), pom)]
cap(c, brim) = [piece(:sphere, (0, 0, -0.02), (0.15, 0.15, 0.1), c), piece(:cylinder, (0.12, 0, -0.01), (0.11, 0.1, 0.018), brim),
                piece(:sphere, (0, 0, 0.08), (0.03, 0.03, 0.02), brim)]
beret(c) = [piece(:sphere, (0, 0, 0.0), (0.2, 0.19, 0.06), c; tilt = (0.3, 0, 0)), piece(:capsule, (0, -0.04, 0.05), (0.018, 0.018, 0.04), c)]
bow(c; s = 1.0) = [piece(:sphere, (0, 0.075s, 0.01), (0.05s, 0.085s, 0.06s), c; tilt = (0.5, 0, 0)),
                   piece(:sphere, (0, -0.075s, 0.01), (0.05s, 0.085s, 0.06s), c; tilt = (-0.5, 0, 0)),
                   piece(:sphere, (0, 0, 0.01), (0.04s, 0.04s, 0.04s), c)]
"A scarf around a neck that runs along the body's x axis, with one end hanging down."
scarf(c, r) = [piece(:torus, (0, 0, 0), (r, 1.05r, 0.9r), c; tilt = (0, pi / 2, 0)),
               piece(:capsule, (0.02, 0.55r, -0.85r), (0.06, 0.035, 0.13), c; tilt = (0.3, 0, 0)),
               piece(:capsule, (0.04, 0.35r, -0.95r), (0.06, 0.035, 0.11), c; tilt = (-0.2, 0, 0))]
beanie(c, pom) = [piece(:sphere, (0, 0, -0.02), (0.17, 0.17, 0.13), c), piece(:torus, (0, 0, -0.03), (0.165, 0.165, 0.12), c),
                  piece(:sphere, (0, 0, 0.12), (0.055, 0.055, 0.055), pom)]
function flower_crown(r)
    ps = [piece(:torus, (0, 0, 0), (r, r, 0.12r), (0.35, 0.62, 0.25))]
    cols = ((1.0, 0.55, 0.7), (1.0, 0.86, 0.35), (0.98, 0.97, 0.95), (0.6, 0.7, 1.0))
    for k in 0:5
        a = 2pi * k / 6 + 0.3
        push!(ps, piece(:sphere, (r * cos(a), r * sin(a), 0.03), (0.045, 0.045, 0.035), cols[k % 4 + 1]))
    end
    return ps
end

const OUTFITS = Dict(
    "Sir Sniffsalot" => Outfit(:head, (-0.2, 0, 1.0), top_hat((0.16, 0.13, 0.16), (0.85, 0.2, 0.25))),
    "Truffle"        => Outfit(:head, (-0.1, 0, 0.95), beret((0.5, 0.3, 0.62))),
    "Pickles"        => Outfit(:head, (-0.7, 0, -0.2), scarf((0.36, 0.68, 0.3), 0.32); size = 1.0),
    "Cumulus"        => Outfit(:puff_top, (0.3, 0, 0.9), beanie((0.3, 0.52, 0.92), (0.98, 0.97, 0.95))),
    "Marshmallow"    => Outfit(:puff_top, (0.35, 0, 0.9), bow((0.98, 0.45, 0.62); s = 1.5)),
    "Pinchy"         => Outfit(:body, (-0.35, 0, 1.0), party_hat((0.25, 0.7, 0.85), (1.0, 0.85, 0.3))),
    "Hopscotch"      => Outfit(:body, (-0.2, 0, 0.95), cap((1.0, 0.82, 0.3), (0.3, 0.5, 0.9))),
    "Gloop"          => Outfit(:body, (-0.08, 0, 0.97), flower_crown(0.15)),
    "Wibbles"        => Outfit(:body, (0.1, 0.55, 0.8), bow((0.98, 0.58, 0.2); s = 1.5)),
)

"""
Where a friend's own outfit sits on a made-over body (makeover.jl cut the piglets, blobs and sheep into :body, legs
and tail: no :head or :puff_top, so their hats vanished from s74 to s81): on :body, at this point in units of the
species' height (forward, left, up). Scarves stay off (on top of a head they would float).
"""
const ON_NEW_BODY = Dict("Snootle" => (0.26f0, 0f0, 0.7f0), "Fluffkin" => (0.3f0, 0f0, 0.98f0), "Blorbo" => (0f0, 0f0, 1.0f0))   # on the head top (s82, profiled along the body)
const NO_FALLBACK = ()

"The top of a made-over body (its :body part's mesh, metres over the feet), measured once per species."
body_top(sp, j) = get!(get!(() -> Dict{String,Float32}(), OP, :tops), sp.name) do
    p = sp.parts[j]
    maximum(q -> q[3], GeometryBasics.coordinates(NG.shape(p.shape))) * Float32(p.scale[3]) + Float32(p.offset[3])
end
"""
Where a hat sits on a made-over body: forward/left as in `fb` (units of the body's top), and down on the mesh's real
surface right under that point (s82: one height fraction for the whole species floated the sheep's beanie 0.18 m
over its head and sank the pig's beret into its back).
"""
hat_spot(sp, j, fb) = get!(get!(() -> Dict{Any,Vec3f}(), OP, :spots), (sp.name, j, fb, 2)) do
    top = body_top(sp, j)
    p = sp.parts[j]
    x, y = fb[1] * top, fb[2] * top
    sc = Vec3f(p.scale...)
    zs = Float32[]
    for v in GeometryBasics.coordinates(NG.shape(p.shape))
        q = sc .* Vec3f(v...)
        hypot(q[1] - x, q[2] - y) < 0.08f0 && push!(zs, q[3])
    end
    Vec3f(x, y, isempty(zs) ? fb[3] * top : maximum(zs) - 0.02f0)
end

"Own spots for outfits that do not sit on top (a scarf goes round the neck)."
const ON_NEW_BODY_NAME = Dict("Pickles" => (0.24f0, 0f0, 0.55f0))

# every one of a species: a face that reads from the follow camera (the pigs, sheep and crabs had no mouth)
const EXTRAS = Dict(
    # pigs: a smile under the snout and two nostrils on its end
    "Snootle" => [Outfit(:head, (0.78, 0, -0.5), [piece(:sphere, (0, 0, 0), (0.03, 0.075, 0.022), (0.45, 0.12, 0.2); show = :talk)]; size = 1.0),
                  Outfit(:head, (0.72, 0, -0.15), [piece(:sphere, (-0.02, 0.15, 0), (0.025, 0.055, 0.035), (1.0, 0.42, 0.5); show = :happy),
                                                   piece(:sphere, (-0.02, -0.15, 0), (0.025, 0.055, 0.035), (1.0, 0.42, 0.5); show = :happy)]; size = 1.0),
                  Outfit(:snoot, (0, 0, 1.0), [piece(:sphere, (0, 0.025, 0), (0.018, 0.012, 0.012), (0.55, 0.2, 0.28)),
                                                piece(:sphere, (0, -0.025, 0), (0.018, 0.012, 0.012), (0.55, 0.2, 0.28))]; size = 1.0),
                  # pointy ear tips that stand up out of the round head: a pig from behind, not a pink egg (perfectionist s36)
                  Outfit(:head, (-0.1, 0, 0.78), [piece(:cone, (0, 0.19, -0.03), (0.08, 0.06, 0.18), (0.95, 0.5, 0.58); tilt = (-0.8, 0.2, 0)),
                                                   piece(:cone, (0, -0.19, -0.03), (0.08, 0.06, 0.18), (0.95, 0.5, 0.58); tilt = (0.8, 0.2, 0))]; size = 1.0)],
    # sheep: a pink nose and a little mouth on the dark face
    "Fluffkin" => [Outfit(:face, (0.92, 0, -0.15), [piece(:sphere, (0, 0, 0), (0.03, 0.045, 0.03), (0.95, 0.6, 0.65)),
                                                    piece(:sphere, (-0.01, 0, -0.06), (0.02, 0.04, 0.012), (0.95, 0.85, 0.85); show = :talk)]; size = 1.0),
                  # curled ram horns on both sides of the head: a sheep, not a cloud, from any side
                  Outfit(:face, (-0.3, 0, 0.55), [piece(:torus, (0, 0.3, 0.06), (0.11, 0.11, 0.11), (0.92, 0.8, 0.6); tilt = (1.57, 0, 0)),
                                                   piece(:torus, (0, -0.3, 0.06), (0.11, 0.11, 0.11), (0.92, 0.8, 0.6); tilt = (1.57, 0, 0))]; size = 1.0)],
    # crabs: a wide grin on the front of the shell and pale spots on its back (it read as a flat red blob)
    "Crabbit" => [Outfit(:body, (0.93, 0, 0.1), [piece(:sphere, (0, 0, 0), (0.03, 0.12, 0.025), (0.35, 0.08, 0.1); show = :talk)]; size = 1.0),
                  Outfit(:body, (0.85, 0, 0.35), [piece(:sphere, (0, 0.22, 0), (0.025, 0.05, 0.03), (1.0, 0.6, 0.6); show = :happy),
                                                  piece(:sphere, (0, -0.22, 0), (0.025, 0.05, 0.03), (1.0, 0.6, 0.6); show = :happy)]; size = 1.0),
                  Outfit(:body, (0, 0, 0.92), [piece(:sphere, (0.05, 0.2, 0), (0.07, 0.07, 0.025), (1.0, 0.85, 0.7)),
                                               piece(:sphere, (-0.08, -0.17, 0.01), (0.055, 0.055, 0.02), (1.0, 0.85, 0.7)),
                                               piece(:sphere, (-0.15, 0.08, 0.0), (0.045, 0.045, 0.02), (1.0, 0.85, 0.7))]; size = 1.0),
                  # claws up: an arm rises from each claw ball to a big open pincer, a V that reads from the side
                  # (the claws sat low at body height: from the side the crab was a red blob, #134)
                  Outfit(:claw, (0.3, 0, 0.5), [piece(:capsule, (0, 0, 0.1), (0.032, 0.032, 0.05), (0.95, 0.42, 0.28)),
                                                piece(:sphere, (0, 0, 0.2), (0.075, 0.055, 0.07), (0.95, 0.42, 0.28)),
                                                piece(:sphere, (0.04, 0, 0.29), (0.035, 0.04, 0.09), (0.95, 0.42, 0.28); tilt = (0, 0.35, 0)),
                                                piece(:sphere, (-0.04, 0, 0.29), (0.035, 0.04, 0.09), (0.95, 0.42, 0.28); tilt = (0, -0.35, 0)),
                                                piece(:sphere, (0.07, 0, 0.37), (0.02, 0.025, 0.025), (0.99, 0.8, 0.7)),
                                                piece(:sphere, (-0.07, 0, 0.37), (0.02, 0.025, 0.025), (0.99, 0.8, 0.7))]; size = 1.0)],
)

key(p::Piece) = (p.shape, p.color)

# hats come off for a hello: a waving (greeted) critter lifts its hat and tilts it back, then it settles again
const TIPS = Set(["Sir Sniffsalot", "Truffle", "Cumulus", "Pinchy", "Hopscotch", "Gloop"])
"How far `c` lifts its hat now (metres) and how much it tilts it back (radians)."
function hat_tip(c, t)
    if c.action === :dance && c.name != "Pickles"     # dancing: hats and bows hop and sway to the beat (not the scarf)
        k = sin(7f0 * t + 6c.seed)
        return (0.06f0 * abs(k), 0.25f0 * k)
    end
    (c.action === :wave && c.name in TIPS) || return (0f0, 0f0)
    k = abs(sin(4.5f0 * t + 6c.seed))
    return (0.16f0 * k, 0.45f0 * k)
end
"What `c` wears: its own outfit and its species' face details."
wears(c) = (o = get(OUTFITS, c.name, nothing); x = get(EXTRAS, c.species, Outfit[]); o === nothing ? x : [o; x])

# ── drawing ─────────────────────────────────────────────────────────────────
struct Outfits <: System end

function build_outfits!(game)
    for p in get(OP, :plots, Dict())
        delete!(p[2].parent, p[2])
    end
    # plots left by a build that failed half way (names are unique in a scene)
    for p in filter(p -> startswith(string(p.name[]), "outfit_"), copy(game.stage.scene.plots))
        delete!(game.stage.scene, p)
    end
    plots = Dict{Tuple{Symbol,RGBf},Any}()
    for o in [collect(values(OUTFITS)); reduce(vcat, values(EXTRAS))], p in o.pieces
        haskey(plots, key(p)) && continue
        c = p.color
        plots[key(p)] = meshscatter!(game.stage.scene, [Point3f(0, 0, -50)]; marker = NG.shape(p.shape), markersize = [Vec3f(0)],
            rotation = [Makie.Quaternionf(0, 0, 0, 1)], color = c,
            material = NG.Hikari.Plastic(color = (red(c), green(c), blue(c)), roughness = 0.55), name = Symbol(:outfit_, p.shape, :_, length(plots) + 1))
    end
    OP[:plots] = plots
    OP[:key] = (OUTFIT_VERSION, game.stage.scene)
    return plots
end

function NG.start!(::Outfits, game)
    game.stage === nothing && return
    get(OP, :key, nothing) == (OUTFIT_VERSION, game.stage.scene) || build_outfits!(game)
    foreach(p -> p.visible[] = true, values(OP[:plots]))
end

NG.stop!(::Outfits, game) = haskey(OP, :plots) && foreach(p -> p.visible[] = false, values(OP[:plots]))

function NG.step!(::Outfits, game, dt)
    game.stage === nothing && return
    get(OP, :key, nothing) == (OUTFIT_VERSION, game.stage.scene) || build_outfits!(game)
    w = game.world
    t = Float32(w.t)
    talking = Set(b.who for b in w.speech if b.until > w.t)
    inst = Dict(k => (Point3f[], Makie.Quaternionf[], Vec3f[]) for k in keys(OP[:plots]))
    for c in w.creatures
        os = wears(c)
        isempty(os) && continue
        sp = NG.species_of(c)
        out = [(Point3f[], Makie.Quaternionf[], Vec3f[]) for _ in sp.parts]
        NG.pose_parts!(out, sp, c.pos, NG.drawn_yaw(c), c.action, c.phase, c.mood, c.extra, c.seed, t)
        lift, back = hat_tip(c, t)
        for o in os
            tip = (lift > 0 || back != 0) && haskey(OUTFITS, c.name) && o === OUTFITS[c.name]
            j = findfirst(p -> p.name === o.part, sp.parts)
            at = o.at
            if j === nothing                     # a made-over body: the friend's own outfit goes on :body
                own = haskey(OUTFITS, c.name) && o === OUTFITS[c.name] && c.name ∉ NO_FALLBACK
                fb = get(ON_NEW_BODY_NAME, c.name, get(ON_NEW_BODY, sp.name, nothing))
                (own && fb !== nothing) || continue
                j = findfirst(p -> p.name === :body, sp.parts)
                j === nothing && continue
                at = c.name in keys(ON_NEW_BODY_NAME) ? Vec3f(fb...) * body_top(sp, j) : hat_spot(sp, j, fb)
            end
            for i in eachindex(out[j][1])        # both sides of a mirrored part (the crab's claws)
                P, q, s = out[j][1][i], out[j][2][i], out[j][3][i]
                anchor = P + q * (j == findfirst(p -> p.name === o.part, sp.parts) ? s .* at : at)
                tip && (anchor += Point3f(0, 0, lift); q = q * NG.euler(Vec3f(0, -back, 0)))
                k = o.size
                for p in o.pieces
                    ps, rs, ss = inst[key(p)]
                    push!(ps, anchor + q * (k * p.off)); push!(rs, q * NG.euler(p.tilt)); push!(ss, k * shown_scale(p, c.id in talking, c.mood, t, c.seed))
                end
            end
        end
    end
    for (k, (ps, rs, ss)) in inst
        isempty(ps) && (ps = [Point3f(0, 0, -50)]; rs = [Makie.Quaternionf(0, 0, 0, 1)]; ss = [Vec3f(0)])
        Makie.update!(OP[:plots][k]; arg1 = ps, rotation = rs, markersize = ss)
    end
end

register!(Outfits())
