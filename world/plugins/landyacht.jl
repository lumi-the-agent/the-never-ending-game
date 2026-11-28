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

"""
Where the cart stands: on open sand between the first dune grass and the beach hut, a little seaward of both (s165:
the old spot, 5 m west of the grass, put the cart 1.5 m from the hut's middle, half inside it). Nothing before the
beach exists.
"""
function ly_spot(game)
    dg = isdefined(Main, :BEACH) ? get(get(Main.BEACH, :things, Dict()), :dunegrass, Point3f[]) : Point3f[]
    isempty(dg) && return nothing
    Point2f(dg[1][1], dg[1][2]) + Point2f(-2.6f0, -2.2f0)
end

"""
The cart's attitude on the sloping beach: yaw about z, then pitch (bow up) and roll from the ground under the four
wheels; returns the rotation and the height of the cart's origin (the mean ground under the wheels).
"""
function ly_attitude(is, c::Point2f, yaw)
    fwd = Vec2f(-sin(yaw), cos(yaw)); side = Vec2f(cos(yaw), sin(yaw))
    h(a, b) = NG.terrain_height(is, (c + a * fwd + b * side)...)
    half = 0.8f0; tr = LY_WIDE / 2 + 0.08f0
    hfl, hfr, hbl, hbr = h(half, -tr), h(half, tr), h(-half, -tr), h(-half, tr)
    pitch = asin(clamp(((hfl + hfr) - (hbl + hbr)) / 2 / (2half), -0.3f0, 0.3f0))
    roll = -asin(clamp(((hfr + hbr) - (hfl + hbl)) / 2 / (2tr), -0.3f0, 0.3f0))
    q = NG.rot_z(yaw) * Makie.qrotation(Vec3f(1, 0, 0), pitch) * Makie.qrotation(Vec3f(0, 1, 0), roll)
    q, (hfl + hfr + hbl + hbr) / 4
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

# The patch over the old tear, in metres on the sail (x along the chord from the luff, 1.2 m; y up, 2.8 m): a hand-cut
# square of newer canvas set 7 deg askew, its edge a little wavy, hemmed under 2 cm, sewn round with a row of stitches
# 1.2 cm in from the edge (9 mm stitches, 6 mm gaps), over a jagged tear. s166: the old patch was a flat rectangle with a
# dark outline and read as a window. Returns (; inside, hem, stitch, tear).
function ly_patch(u, v)
    x = u * LY_CHORD; y = v * LY_SAIL_H
    th = deg2rad(7f0); dx = x - 0.756f0; dy = y - 1.036f0
    lx = cos(th) * dx + sin(th) * dy; ly = -sin(th) * dx + cos(th) * dy
    hx = 0.14f0 + 0.004f0 * sin(23f0 * ly) + 0.002f0 * sin(61f0 * ly)
    hy = 0.16f0 + 0.004f0 * sin(19f0 * lx) + 0.002f0 * sin(53f0 * lx)
    ex = hx - abs(lx); ey = hy - abs(ly); e = min(ex, ey)
    inside = e > 0
    along = ex < ey ? ly : lx
    stitch = inside && abs(e - 0.012f0) < 0.0017f0 && mod(along + 1f0, 0.015f0) < 0.009f0
    yt = 0.018f0 * sin(38f0 * lx) + 0.008f0 * sin(97f0 * lx + 1f0)
    tear = inside && abs(lx) < 0.09f0 && abs(ly - yt) < 0.0022f0
    (; inside, hem = inside && e < 0.02f0, stitch, tear)
end


"""
Sailcloth: undyed canvas (cotton duck) in crosscut panels about 0.55 m deep sewn with double seams, a leather-brown
tape along luff, leech, foot and head, faint weave, and one patch sewn over an old tear (the big goal's patched sail).
Rows run up the sail (v), columns along the chord from the luff (u).
"""
function ly_canvas(; nv = 1024, nu = 512)
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
        pt = ly_patch(u, v)
        if pt.inside
            col = (0.89f0, 0.86f0, 0.77f0) .* (1f0 + rng_noise(c + 7, r + 3))  # newer, less sun-faded canvas
            pt.hem && (col = col .* 0.95f0)
            pt.tear && (col = col .* 0.93f0)
            pt.stitch && (col = (0.36f0, 0.27f0, 0.18f0))                    # tarred sail twine
        end
        (u < 0.03f0 || u > 0.975f0 || v < 0.018f0 || v > 0.985f0) && (col = (0.42f0, 0.3f0, 0.2f0) .* (1f0 + rng_noise(r, c)))
        img[r, c] = RGBf(col...)
    end
    img
end

"""
The light the canvas lets through, for the path tracer (s165): one layer of cotton duck passes about a quarter of
the light, warmed (the blue scattered out most); where cloth lies doubled (the seam overlaps, the patch) it passes
a quarter of that again, so against the sun the panels glow and the seams and the patch stand out dark; the
leather tape passes nothing.
"""
function ly_canvas_through(cloth::Matrix{RGBf})
    nv, nu = size(cloth)
    one = (0.30f0, 0.25f0, 0.17f0)
    out = Matrix{RGBf}(undef, nv, nu)
    panels = 5
    for r in 1:nv, c in 1:nu
        u = (c - 0.5f0) / nu; v = (r - 0.5f0) / nv
        dv = abs(v * panels - round(v * panels))
        layers = 1
        dv < 0.03f0 && 0 < round(v * panels) < panels && (layers = 2)        # the double seam's overlap
        pt = ly_patch(u, v)
        pt.inside && (layers += pt.tear ? 0 : 1)       # the patch over the sail; where the sail is torn, the patch alone
        pt.hem && (layers += 1)                        # the hem turned under
        pt.stitch && (layers += 2)                     # twine passes almost nothing
        tape = u < 0.03f0 || u > 0.975f0 || v < 0.018f0 || v > 0.985f0
        k = tape ? 0f0 : 0.27f0^(layers - 1)
        g = 1f0 + 4f0 * (ly_lum(cloth[r, c]) - 0.75f0)                   # the weave's thin and thick threads
        out[r, c] = RGBf((one .* (k * g))...)
    end
    out
end
ly_lum(c::RGBf) = 0.2126f0 * c.r + 0.7152f0 * c.g + 0.0722f0 * c.b

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
    yaw = Float32(pi / 2) + 0.15f0                      # bow pointing west along the beach, a little up it
    q, g = ly_attitude(game.world.island, c, yaw)
    tocart(v) = q * Vec3f(v)                            # cart frame -> world
    at(v) = Point3f(c[1], c[2], g) + tocart(v)
    plots = LY[:plots] = Any[]          # recorded as they are made: stop! clears a half-built cart too
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
    # the boom: a spar along the sail's foot from the mast to the clew, swung out by the sheet angle (s165: without it
    # the sail read as a banner hung on a pole)
    bd = Vec3f(sin(LY_SHEET), -cos(LY_SHEET), 0)
    bl = LY_CHORD + 0.12f0
    qb = q * Makie.qrotation(Vec3f(0, 0, 1), Float32(pi) + LY_SHEET)
    push!(plots, NG.asset_instances!(sc, m.plank, [at(mastb + bd * (bl / 2 - 0.04f0) + Vec3f(0, 0, LY_FOOT - 0.045f0))];
                                     rotation = [qb], markersize = [Vec3f(0.075f0 / 0.36f0, bl, 0.075f0 / 0.17f0)],
                                     name = :landyacht_boom))
    # the sail, in world coordinates
    sm = ly_sail_mesh(Point3f(0, 0, 0))
    wp = [at(Vec3f(p) + mastb) for p in GeometryBasics.coordinates(sm)]
    sw = GeometryBasics.mesh(wp, GeometryBasics.faces(sm); normal = GeometryBasics.normals(wp, GeometryBasics.faces(sm)),
                             uv = GeometryBasics.texturecoordinates(sm))
    cloth = get!(ly_canvas, LY, :canvas_s166)            # versioned keys: LY outlives plugin reloads
    shine = get!(() -> ly_canvas_through(cloth), LY, :canvas_through_s166)
    push!(plots, mesh!(sc, sw; color = cloth, name = :landyacht_sail,
                       material = NG.Hikari.DiffuseTransmission(reflectance = map(c -> RGBf(0.75f0 * c.r, 0.75f0 * c.g, 0.75f0 * c.b), cloth), transmittance = shine)))
    LY[:key] = objectid(sc); LY[:pos] = Point3f(c[1], c[2], g); LY[:yaw] = yaw
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
    # a cart half built by an older copy of this plugin (it kept its plots only once all were made)
    if game.stage !== nothing
        sc = game.stage.scene
        for p in filter(p -> startswith(string(p.attributes[:name][]), "landyacht_"), copy(sc.plots))
            delete!(sc, p)
        end
    end
    delete!(LY, :plots); delete!(LY, :key); delete!(LY, :tried)
    isdefined(Main, :EXTRA_SOLIDS) && delete!(Main.EXTRA_SOLIDS, "landyacht")
    return
end

register!(LandYacht())
