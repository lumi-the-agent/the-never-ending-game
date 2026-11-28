# The land yacht (s164, project landyacht, todo #763): the bare cart parked on the beach sand below the dune, a deck
# of sun-bleached driftwood planks on four oak board wheels, a driftwood mast, and the sail: the SAME 10% circular arc
# whose flow physics/sailflow.jl solves (chord 1.2 m, 2.8 m tall), in canvas. It stands still for now: the sail's force
# from the solved flow (sail_slices) and the wool telltales (physics/telltale.jl) come next, when slices and the 3D box
# agree (projects/landyacht.md s164).
using GeometryBasics, Makie
const NG = NeverendingGame
isdefined(Main, :LANDYACHT) || Core.eval(Main, :(const LANDYACHT = Dict{Symbol,Any}()))
const LY = Main.LANDYACHT

const LY_PLANK = "20261128-021035-918-asset"      # driftwood plank, 1.0 long along y, 0.36 wide, 0.17 thick
const LY_WHEEL = "20261128-021036-051-asset"      # oak board wheel, 1.0 across in x-y, 0.08 thick
const LY_LEN, LY_WIDE = 2.4f0, 1.25f0             # deck, m
const LY_WHEEL_D = 0.7f0
const LY_DECK_Z = LY_WHEEL_D / 2 + 0.06f0         # deck underside above the sand
const LY_CHORD, LY_SAIL_H, LY_FOOT = 1.2f0, 2.8f0, 0.55f0
const LY_CAMBER = 0.1f0
const LY_SHEET = deg2rad(18f0)                    # boom out from the centre line

struct LandYacht <: System end

"Where the cart stands: on the beach a few metres seaward of the first dune grass, or nothing before the beach exists."
function ly_spot(game)
    dg = isdefined(Main, :BEACH) ? get(get(Main.BEACH, :things, Dict()), :dunegrass, Point3f[]) : Point3f[]
    isempty(dg) && return nothing
    Point2f(dg[1][1], dg[1][2]) + Point2f(-5.0f0, 0.4f0)
end

"The sail as a two-sided sheet in cart coordinates (x across, y forward, z up): the arc, luff at the mast."
function ly_sail_mesh(mast::Point3f)
    hc = LY_CHORD / 2; f = LY_CAMBER * LY_CHORD; R = (hc^2 + f^2) / (2f); yc = f - R; phi = asin(hc / R)
    nu, nv = 24, 16
    pts = Point3f[]; uvs = Vec2f[]
    for j in 0:nv, i in 0:nu
        th = -phi + 2phi * i / nu
        px = R * sin(th); py = yc + R * cos(th)          # chord along px (luff at -hc), bulge along +py
        s = px + hc                                      # distance aft of the luff along the chord
        # aft is -y in the cart; the boom swings out by LY_SHEET towards +x, the bulge to leeward (+x side)
        y = -s * cos(LY_SHEET) - py * sin(LY_SHEET)
        x = s * sin(LY_SHEET) + py * cos(LY_SHEET)
        z = LY_FOOT + LY_SAIL_H * j / nv
        push!(pts, mast + Point3f(x, y, z)); push!(uvs, Vec2f(i / nu, j / nv))
    end
    fs = GLTriangleFace[]
    id(i, j) = j * (nu + 1) + i + 1
    for j in 0:nv-1, i in 0:nu-1
        push!(fs, GLTriangleFace(id(i, j), id(i + 1, j), id(i + 1, j + 1)), GLTriangleFace(id(i, j), id(i + 1, j + 1), id(i, j + 1)))
    end
    GeometryBasics.mesh(pts, fs; normal = GeometryBasics.normals(pts, fs), uv = uvs)
end

"""
Sailcloth: undyed canvas (cotton duck) in crosscut panels about 0.55 m deep sewn with double seams, a leather-brown
tape along luff, leech, foot and head, faint weave, and one patch sewn over an old tear (the big goal's patched sail).
Rows run up the sail (v), columns along the chord from the luff (u).
"""
function ly_canvas(; nv = 512, nu = 256)
    base = (0.84f0, 0.79f0, 0.67f0)
    img = Matrix{RGBf}(undef, nv, nu)
    rng_noise(i, j) = 0.025f0 * (sin(1.7f0 * i + 0.3f0 * j)^2 + cos(2.3f0 * j - 0.7f0 * i)^2 - 1)   # weave, no RNG
    panels = 5
    for r in 1:nv, c in 1:nu
        u = (c - 0.5f0) / nu; v = (r - 0.5f0) / nv
        k = clamp(floor(Int, v * panels), 0, panels - 1)
        tone = 1f0 + (isodd(k) ? 0.025f0 : -0.015f0) + rng_noise(r, c)
        col = base .* tone
        dv = abs(v * panels - round(v * panels))                     # distance to the nearest seam, in panels
        (0.004f0 < dv < 0.012f0 || 0.022f0 < dv < 0.03f0) && 0 < round(v * panels) < panels && (col = col .* 0.78f0)
        inpatch = 0.52f0 < u < 0.74f0 && 0.31f0 < v < 0.43f0
        if inpatch
            col = (0.76f0, 0.69f0, 0.55f0) .* (1f0 + rng_noise(c, r))
            e = min(u - 0.52f0, 0.74f0 - u, v - 0.31f0, 0.43f0 - v)
            e < 0.006f0 && (col = col .* 0.75f0)
        end
        (u < 0.03f0 || u > 0.975f0 || v < 0.018f0 || v > 0.985f0) && (col = (0.42f0, 0.3f0, 0.2f0) .* (1f0 + rng_noise(r, c)))
        img[r, c] = RGBf(col...)
    end
    img
end

function ly_models(game)
    haskey(LY, :models) && return LY[:models]
    cat = NG.load_catalog(game.paths)
    all(id -> any(e -> e["id"] == id && isfile(get(e, "mesh", "")), cat), (LY_PLANK, LY_WHEEL)) || return nothing
    LY[:models] = (plank = NG.lifted_asset(game.paths, LY_PLANK), wheel = NG.lifted_asset(game.paths, LY_WHEEL))
end

function ly_build!(game)
    sc = game.stage.scene
    c = ly_spot(game); c === nothing && return false
    m = ly_models(game); m === nothing && return false
    yaw = 0.9f0                                         # bow pointing along the beach
    q = NG.rot_z(yaw)
    is = game.world.island
    g = NG.terrain_height(is, c[1], c[2])
    tocart(v) = q * Vec3f(v)                            # cart frame -> world
    at(v) = Point3f(c[1], c[2], g) + tocart(v)
    plots = Any[]
    # deck: five planks side by side, 5 cm thick
    n = 5; w = LY_WIDE / n
    deck = [at(Vec3f(-LY_WIDE / 2 + (k - 0.5f0) * w, 0, LY_DECK_Z)) for k in 1:n]
    push!(plots, NG.asset_instances!(sc, m.plank, deck; rotation = [q for _ in deck],
                                     markersize = [Vec3f(w / 0.36f0, LY_LEN, 0.05f0 / 0.17f0) for _ in deck], name = :landyacht_deck))
    # wheels: discs turned so their axle runs across the cart
    qw = q * Makie.qrotation(Vec3f(0, 1, 0), Float32(pi / 2))
    wheels = [at(Vec3f(sx * (LY_WIDE / 2 + 0.08f0), sy * 0.8f0, LY_WHEEL_D / 2)) for sx in (-1, 1) for sy in (-1, 1)]
    push!(plots, NG.asset_instances!(sc, m.wheel, wheels; rotation = [qw for _ in wheels],
                                     markersize = [Vec3f(LY_WHEEL_D, LY_WHEEL_D, 0.1f0 / 0.08f0) for _ in wheels], name = :landyacht_wheels))
    # mast: a plank stood on end at the front third
    mastb = Vec3f(0, 0.55f0, LY_DECK_Z + 0.05f0)
    qm = q * Makie.qrotation(Vec3f(1, 0, 0), Float32(pi / 2))
    mh = LY_FOOT + LY_SAIL_H + 0.25f0
    push!(plots, NG.asset_instances!(sc, m.plank, [at(mastb + Vec3f(0, 0, mh / 2))]; rotation = [qm],
                                     markersize = [Vec3f(0.11f0 / 0.36f0, mh, 0.11f0 / 0.17f0)], name = :landyacht_mast))
    # the sail, in world coordinates
    sm = ly_sail_mesh(Point3f(0, 0, 0))
    wp = [at(Vec3f(p) + mastb) for p in GeometryBasics.coordinates(sm)]
    sw = GeometryBasics.mesh(wp, GeometryBasics.faces(sm); normal = GeometryBasics.normals(wp, GeometryBasics.faces(sm)),
                             uv = GeometryBasics.texturecoordinates(sm))
    cloth = get!(ly_canvas, LY, :canvas)
    push!(plots, mesh!(sc, sw; color = cloth, name = :landyacht_sail,
                       material = NG.Hikari.Diffuse(color = cloth, roughness = 1f0)))
    LY[:plots] = plots; LY[:key] = objectid(sc); LY[:pos] = Point3f(c[1], c[2], g); LY[:yaw] = yaw
    isdefined(Main, :EXTRA_SOLIDS) && (Main.EXTRA_SOLIDS["landyacht"] = [(c, 1.4f0)])
    true
end

function NG.step!(::LandYacht, game, dt)
    game.stage === nothing && return
    get(LY, :key, nothing) == objectid(game.stage.scene) && return
    t = time(); t < get(LY, :tried, 0.0) + 5 && return
    LY[:tried] = t
    ly_build!(game)
    return
end

function NG.stop!(::LandYacht, game)
    for p in get(LY, :plots, Any[])
        p.parent !== nothing && delete!(p.parent, p)
    end
    delete!(LY, :plots); delete!(LY, :key); delete!(LY, :tried)
    isdefined(Main, :EXTRA_SOLIDS) && delete!(Main.EXTRA_SOLIDS, "landyacht")
    return
end

register!(LandYacht())
