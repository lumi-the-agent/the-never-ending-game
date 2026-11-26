# Areas: places to walk to. A dirt path runs from the meadow past the signpost and the cottage,
# along a little pond with lily pads and reeds, down to a wooden pier on the north beach.
# Static scenery: plots are made once per process (kept in Main, like firefly_catch.jl) because the
# traced scene cannot delete plots; trees, rocks and bushes standing on the path, pond or pier are
# removed from the world once.
isdefined(Main, :AREA_PLOTS) || Core.eval(Main, :(const AREA_PLOTS = Dict{Symbol,Any}()))

const NG = NeverendingGame
const AREA_VERSION = 10          # bump when the look changes: the plots are rebuilt
const POND = Point2f(-5.5, 10.5)
const POND_R = 2.3f0
const PIER_START = Point2f(-1.53, 17.39)       # on the beach where the ground is at deck height
const PIER_DIR = Vec2f(0.5, 0.866)
const PIER_LEN = 6.5f0
const PIER_DECK = 0.62f0                     # deck height above the sea, flat
const PATH_POINTS = Point2f[(1.0, -2.5), (-1.8, -1.2), (-5.4, -0.9), (-5.9, 2.0), (-4.6, 5.2), (-2.6, 8.0),
                            (-2.3, 11.2), (-2.0, 14.0), (-1.8, 16.4), PIER_START]
const PATH_WIDTH = 1.15f0

const DIRT = RGBf(0.62, 0.47, 0.31)
const DIRT_EDGE = RGBf(0.5, 0.5, 0.27)
const WOOD = (0.56, 0.38, 0.22)
const WOOD_DARK = (0.36, 0.24, 0.15)

"An area a creature (or the player) can walk to."
struct Area
    name::String
    pos::Point2f
    radius::Float32
end
const AREAS = [Area("Cottage clearing", Point2f(-7.0, 3.5), 4.0f0), Area("Lily pond", POND, POND_R + 1),
               Area("Old pier", PIER_START + PIER_DIR * (PIER_LEN / 2), PIER_LEN / 2 + 1), Area("Signpost meadow", Point2f(-4.0, -1.5), 3.0f0)]

H(w, x, y) = NG.terrain_height(w.island, x, y)

function catmull(ps::Vector{Point2f}, step::Real)
    out = Point2f[]
    q = [[ps[1]]; ps; [ps[end]]]
    for i in 2:(length(q) - 2)
        p0, p1, p2, p3 = q[i - 1], q[i], q[i + 1], q[i + 2]
        n = max(2, ceil(Int, norm(p2 - p1) / step))
        for k in 0:(n - 1)
            t = Float32(k / n)
            push!(out, 0.5f0 * ((2p1) + (-p0 + p2) * t + (2p0 - 5p1 + 4p2 - p3) * t^2 + (-p0 + 3p1 - 3p2 + p3) * t^3))
        end
    end
    push!(out, ps[end])
    return out
end

"The path as a strip draped on the terrain: 5 vertices across, dirt in the middle fading to grass at the edges."
function path_mesh(w, centre::Vector{Point2f})
    pts = Point3f[]; cols = RGBf[]; fs = GLTriangleFace[]
    across = (-1.0f0, -0.55f0, 0.0f0, 0.55f0, 1.0f0)
    for (i, c) in enumerate(centre)
        a = centre[max(i - 1, 1)]; b = centre[min(i + 1, end)]
        t = normalize(b - a); nrm = Vec2f(-t[2], t[1])
        wob = 1 + 0.18f0 * sin(1.7f0 * i) * cos(0.6f0 * i)
        for s in across
            p = c + nrm * (s * wob * PATH_WIDTH / 2)
            # the edges sink just under the grass: a strip floating 4 cm up threw a hard black line
            # along both sides in path tracing (perfectionist-0030)
            push!(pts, Point3f(p[1], p[2], H(w, p[1], p[2]) + 0.045f0 - 0.075f0 * s^2))
            n = 0.5f0 + 0.5f0 * sin(3.1f0 * p[1] + 2.3f0 * p[2])
            base = Makie.lerp_oklab(DIRT, RGBf(0.7, 0.56, 0.38), 0.4f0 * n)
            push!(cols, abs(s) == 1 ? DIRT_EDGE : base)
        end
    end
    m = length(across)
    for i in 1:(length(centre) - 1), j in 1:(m - 1)
        a = (i - 1) * m + j; b = i * m + j
        push!(fs, GLTriangleFace(a, b, b + 1)); push!(fs, GLTriangleFace(a, b + 1, a + 1))
    end
    return GeometryBasics.Mesh(pts, fs; normal = fill(Vec3f(0, 0, 1), length(pts))), cols
end

pond_shape(a) = 1 + 0.08f0 * sin(3a) + 0.05f0 * cos(5a)

"The pond: a water disc at a level just over the ground inside it."
function pond_mesh(level, r; n = 48)
    pts = [Point3f(POND[1], POND[2], level)]
    for k in 1:n
        a = 2pi * k / n
        rr = r * pond_shape(a)
        push!(pts, Point3f(POND[1] + rr * cos(a), POND[2] + rr * sin(a), level))
    end
    fs = [GLTriangleFace(1, k + 1, mod(k, n) + 2) for k in 1:n]
    return GeometryBasics.Mesh(pts, fs; normal = fill(Vec3f(0, 0, 1), length(pts)))
end


const POND_DEPTH = 0.55f0     # m: how deep the dug pond is in the middle (s89)

"""
Dig the pond's basin into the drawn terrain (s89): inside the pond the terrain plot's points sink to a bowl
POND_DEPTH deep, so clear water has a floor to show. Only the picture: creatures still wade on the old ground
(splash.jl's walkway), up to their middles. meadow.jl paints the floor (Main.AREA_PLOTS[:pond]).
"""
function dig_pond!(scene, w, level)
    i = findfirst(p -> haskey(p.attributes, :name) && p.attributes[:name][] === :terrain, scene.plots)
    i === nothing && return
    m, _ = NG.terrain_mesh(w.island)
    pts = collect(GeometryBasics.coordinates(m)); fs = GeometryBasics.faces(m)
    for (k, q) in enumerate(pts)
        dx = q[1] - POND[1]; dy = q[2] - POND[2]
        rr = POND_R * pond_shape(atan(dy, dx))
        u = hypot(dx, dy) / rr
        u < 1.08f0 || continue
        bowl = level - 0.06f0 - POND_DEPTH * max(0f0, 1 - u^2)^0.6f0
        pts[k] = Point3f(q[1], q[2], min(q[3], bowl))
    end
    ns = fill(Vec3f(0), length(pts))
    for f in fs
        a, b, c = GeometryBasics.value(f[1]), GeometryBasics.value(f[2]), GeometryBasics.value(f[3])
        n = cross(pts[b] - pts[a], pts[c] - pts[a])
        ns[a] += n; ns[b] += n; ns[c] += n
    end
    ns = [norm(v) > 0 ? (v[3] < 0 ? -v : v) / norm(v) : Vec3f(0, 0, 1) for v in ns]
    Makie.update!(scene.plots[i]; arg1 = GeometryBasics.Mesh(pts, fs; normal = ns))
    Main.AREA_PLOTS[:pond] = (POND, POND_R, level)
end

"A sandy bank: a ring from just under the water's edge out to the ground around it."
function bank_mesh(w, level; n = 48, width = 0.8f0)
    pts = Point3f[]
    for k in 1:n
        a = 2pi * k / n
        ri = (POND_R - 0.15f0) * pond_shape(a); ro = (POND_R + width) * pond_shape(a)
        push!(pts, Point3f(POND[1] + ri * cos(a), POND[2] + ri * sin(a), level - 0.02f0))
        x, y = POND[1] + ro * cos(a), POND[2] + ro * sin(a)
        push!(pts, Point3f(x, y, H(w, x, y) + 0.03f0))
    end
    fs = GLTriangleFace[]
    for k in 0:(n - 1)
        i1 = 2k + 1; o1 = 2k + 2; i2 = mod(2k + 2, 2n) + 1; o2 = i2 + 1
        push!(fs, GLTriangleFace(i1, o1, o2)); push!(fs, GLTriangleFace(i1, o2, i2))
    end
    return GeometryBasics.Mesh(pts, fs; normal = fill(Vec3f(0, 0, 1), length(pts)))
end

function make_area_plots!(scene, w)
    plots = Any[]
    centre = catmull(PATH_POINTS, 0.3f0)
    m, cols = path_mesh(w, centre)
    push!(plots, mesh!(scene, m; color = cols, material = NG.Hikari.Diffuse(color = (1, 1, 1)), name = :area_path))
    # pebbles along both edges
    rng = Xoshiro(7)
    peb = Point3f[]; psz = Vec3f[]
    for (i, c) in enumerate(centre)
        rand(rng) < 0.18 || continue
        t = normalize(centre[min(i + 1, end)] - centre[max(i - 1, 1)]); nrm = Vec2f(-t[2], t[1])
        p = c + nrm * (rand(rng, (-1, 1)) * (PATH_WIDTH / 2 + 0.1f0 + 0.15f0 * rand(rng, Float32)))
        push!(peb, Point3f(p[1], p[2], H(w, p[1], p[2]) + 0.03f0)); push!(psz, Vec3f(0.08, 0.065, 0.04) * (0.7f0 + 0.6f0 * rand(rng, Float32)))
    end
    push!(plots, meshscatter!(scene, peb; marker = NG.shape(:sphere), markersize = psz, color = RGBf(0.72, 0.7, 0.66),
                              material = NG.Hikari.Diffuse(color = (0.72, 0.7, 0.66)), name = :area_pebbles))
    # pond: water, a sandy bank, stones, lily pads and reeds
    inside = [H(w, POND[1] + r * cos(a), POND[2] + r * sin(a)) for r in 0:0.2:POND_R * 1.15 for a in range(0, 2pi; length = 37)]
    level = Float32(maximum(inside) + 0.03)
    push!(plots, mesh!(scene, bank_mesh(w, level); color = RGBf(0.8, 0.72, 0.52), material = NG.Hikari.Diffuse(color = (0.8, 0.72, 0.52)),
                       name = :area_pond_bank))
    # real water (s89, the human: "why on earth is the pond not water?"): clear glass at water's index over a dug
    # basin (dig_pond!), like the sea; `color` is what the browser draws
    dig_pond!(scene, w, level)
    push!(plots, mesh!(scene, pond_mesh(level, POND_R); color = RGBAf(0.6, 0.87, 0.9, 1.0),
                       # the raster tints by the glass colour (s91: (0.9, 0.98, 0.95) read grey live, review s89/s90): blue water
                       # live, near-clear in traced copies, where the sky and the sandy floor give the colour
                       material = NG.Hikari.MediumInterface(NG.Hikari.Glass(color = get(Main.AREA_PLOTS, :live, false) ? (0.4, 0.72, 0.95) : (0.9, 0.98, 0.95),
                                                                            ior = 1.33, roughness = 0.01);
                                                            # s110 (#535): water that absorbs red first, so the deep middle reads darker teal
                                                            # than the sandy bank and the sky's reflection stands out on it
                                                            inside = NG.Hikari.HomogeneousMedium(σ_a = NG.Hikari.RGBSpectrum(0.9f0, 0.35f0, 0.22f0),
                                                                                                 σ_s = NG.Hikari.RGBSpectrum(0.02f0)),
                                                            shadows = 1.33),   # sun through the surface: a lit floor (s89: plain glass shadowed it navy)
                       name = :area_pond))
    st = Point3f[]; ssz = Vec3f[]
    for k in 1:22
        a = 2pi * k / 22 + 0.1f0 * randn(rng, Float32)
        r = POND_R + 0.6f0 + 0.25f0 * rand(rng, Float32)
        x, y = POND[1] + r * cos(a), POND[2] + r * sin(a)
        push!(st, Point3f(x, y, H(w, x, y) + 0.04f0)); push!(ssz, Vec3f(0.24, 0.2, 0.13) * (0.6f0 + 0.6f0 * rand(rng, Float32)))
    end
    push!(plots, meshscatter!(scene, st; marker = NG.shape(:sphere), markersize = ssz, color = RGBf(0.62, 0.6, 0.56),
                              material = NG.Hikari.Diffuse(color = (0.62, 0.6, 0.56)), name = :area_pond_stones))
    lily = [Point3f(POND[1] + r * cos(a), POND[2] + r * sin(a), level + 0.012f0)
            for (r, a) in ((0.9, 0.4), (1.4, 1.1), (0.6, 2.6), (1.5, 3.4), (1.1, 4.6), (1.6, 5.5), (0.4, 5.9))]
    push!(plots, meshscatter!(scene, lily; marker = NG.shape(:cylinder), markersize = Vec3f(0.28, 0.28, 0.015),
                              color = RGBf(0.3, 0.6, 0.22), material = NG.Hikari.Diffuse(color = (0.3, 0.6, 0.22)), name = :area_lilies))
    # their stems, down to the dug floor: what you see through clear water
    stems = [Point3f(p[1] + 0.03f0, p[2], level - POND_DEPTH * 0.95f0) for p in lily]
    push!(plots, meshscatter!(scene, stems; marker = NG.shape(:cylinder), markersize = Vec3f(0.018, 0.018, POND_DEPTH * 0.95f0),
                              color = RGBf(0.28, 0.5, 0.2), material = NG.Hikari.Diffuse(color = (0.28, 0.5, 0.2)), name = :area_lily_stems))
    push!(plots, meshscatter!(scene, [p + Point3f(0.08, 0.05, 0.02) for p in lily[1:2:end]]; marker = NG.shape(:sphere),
                              markersize = Vec3f(0.09, 0.09, 0.06), color = RGBf(0.98, 0.72, 0.85),
                              material = NG.Hikari.Plastic(color = (0.98, 0.72, 0.85), roughness = 0.4), name = :area_lily_flowers))
    reeds = Point3f[]; rsz = Vec3f[]
    for k in 1:40
        a = 1.6f0 + 1.6f0 * rand(rng, Float32) + (k > 20 ? 2.6f0 : 0f0)
        r = POND_R - 0.15f0 + 0.3f0 * rand(rng, Float32)
        x, y = POND[1] + r * cos(a), POND[2] + r * sin(a)
        push!(reeds, Point3f(x, y, level - 0.05f0)); push!(rsz, Vec3f(0.025, 0.025, 0.55f0 + 0.5f0 * rand(rng, Float32)))
    end
    push!(plots, meshscatter!(scene, reeds; marker = NG.shape(:cylinder), markersize = rsz, color = RGBf(0.42, 0.55, 0.22),
                              material = NG.Hikari.Diffuse(color = (0.42, 0.55, 0.22)), name = :area_reeds))
    push!(plots, meshscatter!(scene, [p + Point3f(0, 0, s[3]) for (p, s) in zip(reeds[1:3:end], rsz[1:3:end])];
                              marker = NG.shape(:cylinder), markersize = Vec3f(0.05, 0.05, 0.16), color = RGBf(0.45, 0.3, 0.18),
                              material = NG.Hikari.Diffuse(color = (0.45, 0.3, 0.18)), name = :area_cattails))
    # pier: planks on posts, from the beach out over the sea
    d3 = Vec3f(PIER_DIR[1], PIER_DIR[2], 0); side = Vec3f(-PIER_DIR[2], PIER_DIR[1], 0)
    yaw = atan(PIER_DIR[2], PIER_DIR[1])
    planks = Point3f[]; prot = Any[]; pz = Vec3f[]
    s = 0.0f0
    while s < PIER_LEN
        c = Point3f(PIER_START[1], PIER_START[2], 0) + d3 * s
        z = PIER_DECK
        push!(planks, c + Point3f(0, 0, z)); push!(prot, NG.rot_z(yaw + 0.03f0 * randn(rng, Float32)))
        push!(pz, Vec3f(0.24, 1.5f0 + 0.08f0 * rand(rng, Float32), 0.07))
        s += 0.3f0
    end
    push!(plots, meshscatter!(scene, planks; marker = Rect3f(Vec3f(-0.5, -0.5, -0.5), Vec3f(1)), markersize = pz, rotation = prot,
                              color = RGBf(WOOD...), material = NG.Hikari.Diffuse(color = WOOD), name = :area_pier_planks))
    posts = Point3f[]
    for s in 0.6f0:1.45f0:PIER_LEN, o in (-0.8f0, 0.8f0)
        c = Point3f(PIER_START[1], PIER_START[2], 0) + d3 * s + side * o
        push!(posts, c + Point3f(0, 0, -1.2))
    end
    push!(plots, meshscatter!(scene, posts; marker = NG.shape(:cylinder), markersize = Vec3f(0.1, 0.1, 2.1f0),
                              color = RGBf(WOOD_DARK...), material = NG.Hikari.Diffuse(color = WOOD_DARK), name = :area_pier_posts))
    return plots
end

"Trees, rocks and bushes standing where the path, pond or pier now are."
function in_the_way(p)
    q = Point2f(p.pos[1], p.pos[2])
    r = p.kind === :tree ? 1.3f0 : p.kind === :flower ? 0.6f0 : 0.9f0
    norm(q - POND) < POND_R + 0.6f0 + r && return true
    t = dot(q - PIER_START, PIER_DIR)
    -1 < t < PIER_LEN && abs(dot(q - PIER_START, Vec2f(-PIER_DIR[2], PIER_DIR[1]))) < 1 + r && return true
    return any(c -> norm(q - c) < PATH_WIDTH / 2 + r, PATH_COARSE)
end

const PATH_COARSE = catmull(PATH_POINTS, 0.5f0)

struct Areas <: System end

function NeverendingGame.start!(s::Areas, game)
    w = game.world
    n = length(w.props)
    filter!(p -> p.kind === :ball || !in_the_way(p), w.props)
    length(w.props) < n && NG.log_event!(game.log, w.t, :areas_built; cleared = n - length(w.props), areas = [a.name for a in AREAS])
    NG.WALKWAYS["pier"] = pier_height
    game.stage === nothing && return
    plots = get(Main.AREA_PLOTS, :plots, nothing)
    if plots === nothing || first(plots).parent !== game.stage.scene || get(Main.AREA_PLOTS, :version, 0) != AREA_VERSION
        # a new look: the old plots go (deleting works in the raster, which the game runs in while plugins reload)
        plots === nothing || foreach(p -> delete!(p.parent, p), plots)
        Main.AREA_PLOTS[:live] = game.dash !== nothing      # (the pond's glass: blue live, clear in traced copies)
        Main.AREA_PLOTS[:plots] = make_area_plots!(game.stage.scene, w)
        Main.AREA_PLOTS[:version] = AREA_VERSION
    else
        foreach(p -> p.visible[] = true, plots)
    end
    return
end
function NeverendingGame.stop!(::Areas, game)
    foreach(p -> p.visible[] = false, get(Main.AREA_PLOTS, :plots, Any[]))
    foreach(p -> p.visible[] = false, values(get(Main.AREA_PLOTS, :fishing, Dict())))
    delete!(NG.WALKWAYS, "pier")
end

# ── life at the pier and the pond ─────────────────────────────────────────────
# Creatures walk the path out onto the pier and fish (a rod, a line, a bobbing float;
# sometimes a fish leaps out of the sea into their arms), or splash about at the pond edge.

pier_point(s, o) = PIER_START + PIER_DIR * s + Vec2f(-PIER_DIR[2], PIER_DIR[1]) * o

function pier_height(x, y)
    q = Point2f(x, y) - PIER_START
    s = dot(q, PIER_DIR); o = dot(q, Vec2f(-PIER_DIR[2], PIER_DIR[1]))
    return (-0.4f0 < s < PIER_LEN + 0.1f0 && abs(o) < 0.72f0) ? PIER_DECK + 0.035f0 : nothing
end

# spot 1 moved in from (5.9, -0.4): the pier-end lantern stands there and a fisher sat inside it (s41)
const FISH_SPOTS = [(5.15f0, -0.5f0), (5.9f0, 0.4f0), (4.4f0, -0.55f0), (4.4f0, 0.55f0)]
const CATCHES = Dict{Int32,Tuple{Float64,Point3f}}()   # who => (time, where the float was) of the last catch

for k in (:fish, :splash)
    k in NG.GOAL_KINDS || push!(NG.GOAL_KINDS, k)
end
push!(NG.BUSY_GOALS, :fish)   # a fisher is not pulled away for a chat

fishers(w) = count(c -> c.goal.kind === :fish, w.creatures)   # at most one per spot
NG.goal_score(::Val{:fish}, c, w) = NG.is_night(w) || c.controlled || fishers(w) >= length(FISH_SPOTS) ? 0.0 :
    0.12 + 0.25c.traits.curiosity + 0.2c.traits.laziness
NG.goal_score(::Val{:splash}, c, w) = NG.is_night(w) ? 0.0 : (1 - c.needs.fun) * (0.2 + 0.6c.traits.playfulness)

# partner 0: on the way to the pier; partner = spot index: walking out to the spot
function NG.start_goal(::Val{:fish}, c, w)
    taken = Set(abs(cr.goal.partner) for cr in w.creatures if cr.goal.kind === :fish && cr !== c)
    spot = findfirst(i -> !(i in taken), eachindex(FISH_SPOTS))
    spot === nothing && return nothing
    root = PIER_START - PIER_DIR * 0.6f0
    return NG.Goal(:fish, NG.ground(w.island, root), :sit, 16.0 + 14rand(w.rng), 0.0, false, -Int32(spot), false)
end

function NG.arrive_goal!(::Val{:fish}, c, w)
    g = c.goal
    if g.partner < 0     # at the start of the pier: now walk out to the spot
        spot = -g.partner
        g.partner = spot
        s, o = FISH_SPOTS[spot]
        p = pier_point(s, o)
        g.target = Point3f(p[1], p[2], PIER_DECK)
        g.arrived = false
        c.action = :walk
        return
    end
    c.yaw = atan(PIER_DIR[2], PIER_DIR[1]) + (FISH_SPOTS[g.partner][2] > 0 ? 0.5f0 : -0.5f0)
    rand(w.rng) < 0.6 && NG.say!(w, c, rand(w.rng, ["gone fishing", "shh, the fish are listening", "today's the day!", "a quiet spot..."]))
    NG.emit!(w, :fishing; who = c.name)
end

function NG.finish_goal!(::Val{:fish}, c, w)
    if rand(w.rng) < 0.55
        CATCHES[c.id] = (w.t, bobber_pos(c, w.t))
        NG.say!(w, c, rand(w.rng, ["a fish!!", "got one!", "look how shiny!", "wriggly!"]); duration = 3.0)
        NG.remember!(c, w.t, "caught a fish at the pier")
        c.needs.fun = min(1.0f0, c.needs.fun + 0.4f0)
        NG.emit!(w, :caught_fish; who = c.name)
    else
        NG.say!(w, c, rand(w.rng, ["not even a nibble", "they're shy today", "next time, fish"]))
        NG.emit!(w, :no_fish; who = c.name)
    end
end

function NG.start_goal(::Val{:splash}, c, w)
    a = Float32(2pi * rand(w.rng))
    edge = POND + Vec2f(cos(a), sin(a)) * (POND_R * pond_shape(a) - 0.25f0)
    return NG.Goal(:splash, NG.ground(w.island, edge), :jump, 5.0 + 3rand(w.rng), 0.0, false, 0, true)
end

function NG.arrive_goal!(::Val{:splash}, c, w)
    c.yaw = atan(POND[2] - c.pos[2], POND[1] - c.pos[1])
    NG.say!(w, c, rand(w.rng, ["splish splash!", "cold cold cold!", "wheee, puddle!", "*splash*"]))
    NG.emit!(w, :splash; who = c.name)
end

function NG.finish_goal!(::Val{:splash}, c, w)
    c.needs.fun = min(1.0f0, c.needs.fun + 0.3f0)
    NG.remember!(c, w.t, "splashed in the pond")
end

"Where the float bobs: 2.6 m out in front of a fisher, on the sea."
function bobber_pos(c, t)
    d = Vec2f(cos(c.yaw), sin(c.yaw))
    p = Point2f(c.pos[1], c.pos[2]) + 2.6f0 * d
    return Point3f(p[1], p[2], 0.02f0 + 0.03f0 * sin(Float32(3t) + c.seed) - (sin(Float32(0.7t) + 3c.seed) > 0.93 ? 0.08f0 : 0f0))
end

zrot(dir) = Makie.rotation_between(Vec3f(0, 0, 1), normalize(Vec3f(dir)))

function fishing_plots!(scene)
    d = get!(Main.AREA_PLOTS, :fishing) do
        Dict{Symbol,Any}(
            :rods => meshscatter!(scene, [Point3f(0, 0, -50)]; marker = NG.shape(:cylinder), markersize = [Vec3f(1f-3)], rotation = [Quaternionf(0, 0, 0, 1)],
                                  color = RGBf(0.45, 0.3, 0.16), material = NG.Hikari.Diffuse(color = (0.45, 0.3, 0.16)), name = :area_rods),
            :lines => meshscatter!(scene, [Point3f(0, 0, -50)]; marker = NG.shape(:cylinder), markersize = [Vec3f(1f-3)], rotation = [Quaternionf(0, 0, 0, 1)],
                                   color = RGBf(0.95, 0.95, 0.9), material = NG.Hikari.Diffuse(color = (0.95, 0.95, 0.9)), name = :area_lines),
            :floats => meshscatter!(scene, [Point3f(0, 0, -50)]; marker = NG.shape(:sphere), markersize = 0.07f0, color = RGBf(0.95, 0.2, 0.15),
                                    material = NG.Hikari.Plastic(color = (0.95, 0.2, 0.15), roughness = 0.2), name = :area_floats),
            :fish => meshscatter!(scene, [Point3f(0, 0, -50)]; marker = NG.shape(:sphere), markersize = Vec3f(0.2, 0.08, 0.1), rotation = [Quaternionf(0, 0, 0, 1)],
                                  color = RGBf(1.0, 0.6, 0.15), material = NG.Hikari.Plastic(color = (1.0, 0.6, 0.15), roughness = 0.15), name = :area_fish))
    end
    foreach(p -> p.visible[] = true, values(d))
    return d
end

function NeverendingGame.step!(::Areas, game, dt)
    game.stage === nothing && return
    w = game.world
    d = fishing_plots!(game.stage.scene)
    rods = Point3f[]; rs = Vec3f[]; rr = Quaternionf[]
    lines = Point3f[]; ls = Vec3f[]; lr = Quaternionf[]
    floats = Point3f[]
    for c in w.creatures
        g = c.goal
        g.kind === :fish && g.arrived && g.partner > 0 || continue
        fwd = Vec3f(cos(c.yaw), sin(c.yaw), 0)
        base = c.pos + Vec3f(0, 0, 0.35f0) + 0.15f0 * fwd
        dir = normalize(fwd + Vec3f(0, 0, 1.1f0))
        tip = base + 1.2f0 * dir
        push!(rods, base); push!(rs, Vec3f(0.025, 0.025, 1.2)); push!(rr, zrot(dir))
        b = bobber_pos(c, w.t)
        push!(lines, b); push!(ls, Vec3f(0.006, 0.006, norm(tip - b))); push!(lr, zrot(tip - b))
        push!(floats, b)
    end
    fish = Point3f[]; fr = Quaternionf[]
    for (id, (t0, from)) in CATCHES
        u = Float32(w.t - t0) / 1.2f0
        i = findfirst(cr -> cr.id == id, w.creatures)
        (i === nothing || u > 1) && continue
        c = w.creatures[i]
        to = c.pos + Vec3f(0, 0, 0.6f0)
        p = from + (to - from) * u + Vec3f(0, 0, 1.6f0 * 4u * (1 - u))
        push!(fish, p); push!(fr, Makie.rotation_between(Vec3f(1, 0, 0), normalize(Vec3f(to - from) + Vec3f(0, 0, 6.4f0 * (1 - 2u)))))
    end
    filter!(kv -> w.t - first(last(kv)) < 1.5, CATCHES)
    # RayMakie's raster cannot draw an empty meshscatter (instanced_bounds reduces over nothing):
    # an idle plot keeps one tiny instance deep under the seabed
    hide = Point3f(0, 0, -50)
    isempty(rods) && (push!(rods, hide); push!(rs, Vec3f(1f-3)); push!(rr, Quaternionf(0, 0, 0, 1)))
    isempty(lines) && (push!(lines, hide); push!(ls, Vec3f(1f-3)); push!(lr, Quaternionf(0, 0, 0, 1)))
    isempty(floats) && push!(floats, hide)
    isempty(fish) && (push!(fish, hide); push!(fr, Quaternionf(0, 0, 0, 1)))
    Makie.update!(d[:rods]; arg1 = rods, markersize = rs, rotation = rr)
    Makie.update!(d[:lines]; arg1 = lines, markersize = ls, rotation = lr)
    Makie.update!(d[:floats]; arg1 = floats)
    Makie.update!(d[:fish]; arg1 = fish, rotation = fr)
    return
end
register!(Areas())
