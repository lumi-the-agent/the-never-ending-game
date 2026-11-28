# Shell beach: the flat south shore is a sandy cove (painted by meadow.jl `beach_weight`) with its own
# things: bleached driftwood, pink and cream shells, coral starfish by the waterline and pale dune
# grass where the sand meets the meadow (generated assets, one instanced plot each). Critters come
# here by day to hunt for shells (`:beachcomb`) and to sunbathe on the warm sand (`:sunbathe`).
# Todo #87 / perfectionist s40: "the island is still one green hill ringed by a thin sand edge".
isdefined(Main, :BEACH) || Core.eval(Main, :(const BEACH = Dict{Symbol,Any}()))
using Serialization

const NG = NeverendingGame
const BEACH_VERSION = 9

"""
Ground Lumi has cleared of dune grass, as (xmin, xmax, ymin, ymax): the yard round the six clay pots, the drum's
oak block and the cart's plank road (cartcord.jl: x 0.65..4.35 on y -14.72) with room on its south side to stand
and watch (s178: one clump grew up through the planks, one stood through the drum's block, and two stood between
the film camera and the cart). Ten of the sixty clumps.
"""
const CLEARED = ((0.3f0, 5.1f0, -16.25f0, -14.2f0),)
cleared(q) = any(r -> r[1] <= q[1] <= r[2] && r[3] <= q[2] <= r[4], CLEARED)

# asset => (count, metres inland (min, max), longest side (m) min..max, texture gain)
const THINGS = (
    driftwood = ("20261123-135732-976-asset", 5, (1.4f0, 4.2f0), (1.3f0, 1.9f0), (1.35f0, 1.33f0, 1.35f0)),
    shells = ("20261123-135734-637-asset", 18, (0.7f0, 3.4f0), (0.22f0, 0.32f0), (1.3f0, 1.25f0, 1.2f0)),
    starfish = ("20261123-135736-240-asset", 12, (0.5f0, 2.4f0), (0.22f0, 0.3f0), (1.3f0, 1.2f0, 1.15f0)),
    dunegrass = ("20261123-135737-841-asset", 60, (3.2f0, 7.0f0), (0.45f0, 0.75f0), (1.35f0, 1.35f0, 1.15f0)))

meadow(game) = game.plugins["meadow"].mod
weight(game, x, y) = Base.invokelatest(meadow(game).beach_weight, game.world.island, x, y)

"Spots for `n` things on the cove, `lo..hi` m inland, away from rocks and each other (deterministic)."
function spots(game, n, (lo, hi), seed; taken = Point2f[])
    is = game.world.island
    m = meadow(game)
    rng = Random.Xoshiro(is.seed + seed)
    rocks = [p for p in game.world.props if p.kind === :rock]
    out = Point2f[]
    k = 0
    while length(out) < n && k < 20_000
        k += 1
        # a cove picked by its width
        ws = [c[2] for c in m.COVES]
        ci = something(findfirst(>=(rand(rng) * sum(ws)), cumsum(ws)), 1)
        ca, half, depth = m.COVES[ci]
        hi2 = min(hi, depth + 0.5f0)
        lo >= hi2 && continue
        a = Float32(ca + (2rand(rng) - 1) * 0.85 * half)
        rc = Base.invokelatest(m.coast_r, is, a)
        r = rc - (lo + (hi2 - lo) * rand(rng, Float32))
        q = Point2f(r * cos(a), r * sin(a))
        b, _ = weight(game, q[1], q[2])
        b > (lo > 3 ? 0.25f0 : 0.8f0) || continue
        any(p -> hypot(q[1] - p.pos[1], q[2] - p.pos[2]) < 1.0f0 * p.scale + 0.3f0, rocks) && continue
        any(t -> norm(t - q) < (lo > 3 ? 0.35f0 : 0.9f0), [out; taken]) && continue
        push!(out, q)
    end
    return out
end

"The asset's material, never metallic, its texture brightened per channel."
function bright(mat, gain)
    mat = copy(mat)
    mat["metallic"] = 0.0f0
    dm = copy(mat["diffuse map"])
    dm["image"] = map(c -> typeof(c)(min(1f0, Float32(Colors.red(c)) * gain[1]), min(1f0, Float32(Colors.green(c)) * gain[2]),
                                     min(1f0, Float32(Colors.blue(c)) * gain[3])), dm["image"])
    mat["diffuse map"] = dm
    return mat
end

"""
The image's soft shadow became a flat plate under the driftwood and the shells (a dark square on the
sand): drop the flat faces at the very bottom of the mesh.
"""
function trim_plate(mm; frac = 0.04f0)
    m = mm.mesh
    ps = GeometryBasics.coordinates(m)
    zs = [p[3] for p in ps]
    zmin, zmax = extrema(zs)
    lim = zmin + frac * (zmax - zmin)
    flat(f) = (n = cross(ps[f[2]] - ps[f[1]], ps[f[3]] - ps[f[1]]); norm(n) == 0 || abs(n[3]) > 0.9f0 * norm(n))
    keep = [f for f in GeometryBasics.faces(m) if !(all(zs[i] < lim for i in f) && flat(f))]
    return GeometryBasics.MetaMesh(GeometryBasics.Mesh(keep; GeometryBasics.vertex_attributes(m)...), mm.meta)
end

ready(game) = all(t -> isfile(joinpath(game.paths.world, "assets", t[1], "mesh.jls")), THINGS)

"Trees, bushes and flowers that stood where the sand is now go (once; the world saves without them)."
function clear_cove!(game)
    w = game.world
    n = length(w.props)
    filter!(p -> !(p.kind in (:tree, :bush, :flower)) || first(weight(game, p.pos[1], p.pos[2])) < 0.3f0, w.props)
    length(w.props) < n && NG.log_event!(game.log, w.t, :beach_cleared; cleared = n - length(w.props))
end

function build!(game)
    sc = game.stage.scene
    foreach(p -> p.parent === sc && delete!(sc, p), get(Main.BEACH, :plots, Any[]))
    plots = Any[]
    things = Dict{Symbol,Vector{Point3f}}()
    taken = Point2f[]
    for (j, (name, (id, n, band, len, gain))) in enumerate(pairs(THINGS))
        mm = trim_plate(Serialization.deserialize(joinpath(game.paths.world, "assets", id, "mesh.jls")))
        model = NG.AssetModel(mm; material = bright(only(values(mm[:materials])), gain))
        ps = GeometryBasics.coordinates(model.mesh)
        ext = maximum(maximum(p[i] for p in ps) - minimum(p[i] for p in ps) for i in 1:3)
        qs = spots(game, n, band, 900 + 37j; taken = name === :dunegrass ? Point2f[] : taken)
        name === :dunegrass || append!(taken, qs)
        # the land yacht and the beach prints stand relative to the FIRST clump: keep that spot when it is cleared
        name === :dunegrass && !isempty(qs) && (Main.BEACH[:anchor] = Point2f(qs[1][1], qs[1][2]))
        rng = Random.Xoshiro(17j)
        rot = [NG.rot_z(2f0pi * rand(rng, Float32)) for _ in qs]     # drawn for every spot, so the clumps that stay
        scl = [Vec3f((len[1] + (len[2] - len[1]) * rand(rng, Float32)) / ext) for _ in qs]   # keep their turn and size
        keep = name === :dunegrass ? findall(!cleared, qs) : eachindex(qs)
        pos = [Point3f(q[1], q[2], NG.terrain_height(game.world.island, q[1], q[2]) - 0.02f0) for q in qs[keep]]
        things[name] = pos
        push!(plots, NG.asset_instances!(sc, model, pos; rotation = rot[keep], markersize = scl[keep], name = Symbol("beach_", name)))
    end
    Main.BEACH[:plots] = plots
    Main.BEACH[:things] = things
    Main.BEACH[:key] = (BEACH_VERSION, objectid(sc))
end

struct Beach <: System end

"meadow.jl paints the sand and knows the cove's shape (plugins load in name order: it may come after this one)."
meadow_ready(game) = haskey(game.plugins, "meadow") && game.plugins["meadow"].mod !== nothing &&
    isdefined(game.plugins["meadow"].mod, :beach_weight)

NG.start!(::Beach, game) = delete!(Main.BEACH, :cleared)

function NG.step!(::Beach, game, dt)
    meadow_ready(game) || return
    get(Main.BEACH, :cleared, nothing) === game.world || (clear_cove!(game); Main.BEACH[:cleared] = game.world)
    game.stage === nothing && return
    get(Main.BEACH, :key, nothing) == (BEACH_VERSION, objectid(game.stage.scene)) || (ready(game) && build!(game))
    return
end

function NG.stop!(::Beach, game)
    game.stage === nothing && return
    foreach(p -> p.visible[] = false, get(Main.BEACH, :plots, Any[]))
    delete!(Main.BEACH, :key)
end

# ── critters on the beach ───────────────────────────────────────────────────

emote(id, kind) = isdefined(Main, :EMOTES) && haskey(Main.EMOTES, :emote) && Base.invokelatest(Main.EMOTES[:emote], id, kind)

for k in (:beachcomb, :sunbathe)
    k in NG.GOAL_KINDS || push!(NG.GOAL_KINDS, k)
end

on_beach(w, k) = count(c -> c.goal.kind === k, w.creatures)
finds() = vcat(get(get(Main.BEACH, :things, Dict()), :shells, Point3f[]), get(get(Main.BEACH, :things, Dict()), :starfish, Point3f[]))
dunes() = get(get(Main.BEACH, :things, Dict()), :dunegrass, Point3f[])

NG.goal_score(::Val{:beachcomb}, c, w) = NG.is_night(w) || c.controlled || isempty(finds()) || on_beach(w, :beachcomb) >= 2 ? 0.0 :
    0.15 + 0.35c.traits.curiosity
# only in full daylight (Pickles sunbathed at 19:59, s41)
NG.goal_score(::Val{:sunbathe}, c, w) = NG.night_factor(w) > 0.05f0 || c.controlled || isempty(dunes()) || on_beach(w, :sunbathe) >= 2 ? 0.0 :
    0.08 + 0.35c.traits.laziness

"A find nobody else is looking at; partner = its index (shells first, then starfish)."
function NG.start_goal(::Val{:beachcomb}, c, w)
    fs = finds()
    taken = Set(cr.goal.partner for cr in w.creatures if cr.goal.kind === :beachcomb && cr !== c)
    free = [i for i in eachindex(fs) if !(i in taken)]
    isempty(free) && return nothing
    i = rand(w.rng, free)
    f = fs[i]
    a = 2pi * rand(w.rng)
    t = NG.ground(w.island, (f[1] + 0.45f0 * cos(a), f[2] + 0.45f0 * sin(a)))
    return NG.Goal(:beachcomb, t, :eat, 6.0 + 5rand(w.rng), 0.0, false, Int32(i), false)
end

function NG.arrive_goal!(::Val{:beachcomb}, c, w)
    fs = finds()
    i = c.goal.partner
    i in eachindex(fs) || return
    f = fs[i]
    c.yaw = atan(f[2] - c.pos[2], f[1] - c.pos[1])
    star = i > length(get(Main.BEACH[:things], :shells, Point3f[]))
    NG.say!(w, c, rand(w.rng, star ? ["a starfish! hello, little star", "it's waving at me!", "a sea star!"] :
                                     ["ooh, a shell!", "this one's pink!", "I can hear the sea in it", "a curly one!"]))
    emote(c.id, star ? :heart : :what)
    NG.emit!(w, :beachcomb; who = c.name, find = star ? "starfish" : "shell")
end

function NG.finish_goal!(::Val{:beachcomb}, c, w)
    c.needs.fun = min(1.0f0, c.needs.fun + 0.25f0)
    NG.remember!(c, w.t, "found treasures on the beach")
end

"A warm spot in the dune grass, facing the sea."
function NG.start_goal(::Val{:sunbathe}, c, w)
    ds = dunes()
    isempty(ds) && return nothing
    d = ds[rand(w.rng, eachindex(ds))]
    # a little seaward of the grass, on open sand
    dir = normalize(Vec2f(d[1], d[2]))
    q = Point2f(d[1], d[2]) + dir * (0.9f0 + 0.8f0 * rand(w.rng, Float32))
    return NG.Goal(:sunbathe, NG.ground(w.island, q), :sit, 14.0 + 12rand(w.rng), 0.0, false, 0, false)
end

function NG.arrive_goal!(::Val{:sunbathe}, c, w)
    c.yaw = atan(c.pos[2], c.pos[1])     # out to sea
    NG.say!(w, c, rand(w.rng, ["warm sand, warm toes", "ahh, sunshine", "listen to the waves...", "best spot on the island"]))
    emote(c.id, :note)
    NG.emit!(w, :sunbathe; who = c.name)
end

function NG.finish_goal!(::Val{:sunbathe}, c, w)
    c.needs.energy = min(1.0f0, c.needs.energy + 0.15f0)
    NG.remember!(c, w.t, "sunbathed on the beach")
end

register!(Beach())
