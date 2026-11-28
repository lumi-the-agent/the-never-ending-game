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
    a = isdefined(Main, :BEACH) ? get(Main.BEACH, :anchor, nothing) : nothing   # the first dune grass spot (beach.jl)
    a === nothing && return nothing
    a + Point2f(-2.6f0, -2.2f0)
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
    # s167: bow north-west along the open beach (it pointed into the sea 5 m off); the island's wind comes from the
    # south-west, so the cart starts on a close reach with the sail to leeward (+x in the cart)
    yaw = 1.05f0
    c = c + 2.0f0 * Point2f(-sin(yaw), cos(yaw))       # s167: 2 m on, out of the hollow it sat in (16% grade under it)
    q, g = ly_attitude(game.world.island, c, yaw)
    tocart(v) = q * Vec3f(v)                            # cart frame -> world
    at(v) = Point3f(c[1], c[2], g) + tocart(v)
    plots = LY[:plots] = Any[]          # recorded as they are made: stop! clears a half-built cart too
    delete!(LY, :sand); delete!(LY, :sink); delete!(LY, :sandR)   # a new scene: the sand square is made again
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
    LY[:wheels] = plots[end]; LY[:qw] = qw              # s167: they turn about their axle (local z) as the cart rolls
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
    LY[:swingers] = Any[plots[end]]                      # boom and sail turn about the mast with the sheet
    LY[:mast] = at(mastb)
    # the sail, in world coordinates
    sm = ly_sail_mesh(Point3f(0, 0, 0))
    wp = [at(Vec3f(p) + mastb) for p in GeometryBasics.coordinates(sm)]
    sw = GeometryBasics.mesh(wp, GeometryBasics.faces(sm); normal = GeometryBasics.normals(wp, GeometryBasics.faces(sm)),
                             uv = GeometryBasics.texturecoordinates(sm))
    cloth = get!(ly_canvas, LY, :canvas_s166)            # versioned keys: LY outlives plugin reloads
    shine = get!(() -> ly_canvas_through(cloth), LY, :canvas_through_s166)
    push!(plots, mesh!(sc, sw; color = cloth, name = :landyacht_sail,
                       material = NG.Hikari.DiffuseTransmission(reflectance = map(c -> RGBf(0.75f0 * c.r, 0.75f0 * c.g, 0.75f0 * c.b), cloth), transmittance = shine)))
    push!(LY[:swingers], plots[end])
    LY[:key] = objectid(sc); LY[:pos] = Point3f(c[1], c[2], g); LY[:yaw] = yaw
    LY[:st] = (P = c, yaw = Float64(yaw), v = 0.0, sheet = Float64(LY_SHEET), d = 0.0)
    isdefined(Main, :EXTRA_SOLIDS) && (Main.EXTRA_SOLIDS["landyacht"] = [(c, 1.4f0)])
    true
end

function NG.step!(::LandYacht, game, dt)
    game.stage === nothing && return
    if get(LY, :key, nothing) == objectid(game.stage.scene)
        ly_sail!(game, dt)
        return
    end
    t = time(); t < get(LY, :tried, 0.0) + 5 && return
    LY[:tried] = t
    ly_build!(game)
    return
end

# ---- Sailing it (s167, idea 'Climb aboard and sail it', todo #767) --------------------------------------------------
# E by the cart in Jump in climbs aboard; W hauls the sheet in, S lets it out, A/D steer, Space hops off. The force
# is the 3D WaterLily box hugging the sail (physics/sailflow.jl serve!), in a process of its own on the GPU (Mantle's
# channels are single-writer per thread, s166), at the apparent wind the cart's own speed makes from the island's wind.
# Against it: the four wheels' rolling resistance in the sand (WheelSand.towed on firm sand, 69 N at 95 kg) and the
# slope. No lift table anywhere: a sheet hauled too tight stalls, let out too far the sail luffs.
using Distributed
const LY_MASS = 95.0                 # cart 80 kg + Lumi, kg
const LY_ROLL = 69.0                 # N, WheelSand.towed(:firm_sand, 95 kg / 4, r 0.35, b 0.10) x 4 (s166)
const LY_AREA = 4 * 1.2^2            # m^2: the box's sail is aspect 4 x chord^2
const LY_BASE = 1.6                  # wheelbase, m
const LY_WIND = 8.0                  # m/s at the wind system's strength 1 (0.5 .. 1.3 drifts: 4 .. 10 m/s)

function ly_server_start!(alpha0)
    haskey(LY, :srv_task) && return
    LY[:srv_t0] = time(); LY[:force] = nothing
    LY[:srv_task] = @async Base.invokelatest() do
        pid = only(addprocs(1; exeflags = "--project=/sim/Programmieren/SimGame"))
        LY[:srv_pid] = pid
        # `nothing` back: the module SailFlow itself cannot travel to this process (s167: UndefVarError on the way back)
        Distributed.remotecall_eval(Main, pid, :(include("/sim/Programmieren/SimGame/world/physics/sailflow.jl"); nothing))
        # made ON the worker: a closure of this plugin's module (Plugin_landyacht) cannot be rebuilt there (s167)
        cmd, out = Distributed.remotecall_eval(Main, pid, quote
            using Distributed
            (RemoteChannel(() -> Channel{Any}(64)), RemoteChannel(() -> Channel{Any}(256)))
        end)
        LY[:srv_cmd] = cmd; LY[:srv_out] = out
        # an expression, not a closure: a closure of this plugin's module cannot be rebuilt in the worker
        LY[:srv_fut] = remotecall(Core.eval, pid, Main,
                                  :(Base.invokelatest(Main.SailFlow.serve!, $cmd, $out; alpha = $alpha0, warm = 2); nothing))
        :running
    end
end

function ly_server_stop!()
    cmd = pop!(LY, :srv_cmd, nothing); pid = pop!(LY, :srv_pid, nothing)
    delete!(LY, :srv_out); delete!(LY, :srv_fut); delete!(LY, :srv_task); LY[:force] = nothing
    cmd === nothing || put!(cmd, :stop)
    pid === nothing || (@async (sleep(1.0); rmprocs(pid)))     # never leave a GPU process behind
    return
end

"Errors in the sail server surface here (rule 8), once: the task or the remote loop failed."
function ly_server_check!()
    t = get(LY, :srv_task, nothing)
    if t !== nothing && istaskfailed(t)
        LY[:srv_error] = sprint(showerror, t.exception); ly_server_stop!(); fetch(t)
    end
    f = get(LY, :srv_fut, nothing)
    if f !== nothing && isready(f)
        LY[:srv_error] = sprint(show, fetch(f)); ly_server_stop!(); error("the sail server stopped: $(LY[:srv_error])")
    end
end

# ---- The wheels in the sand (s169, idea 'Bogged', project stuck, todo #773) ------------------------------------------
# The four wheels roll IN the beach's sand field (physics/stuck.jl: Bekker at every point of each rim on the ground the
# field really has, with its load history), not on a number: dry sand above the swash holds them with ~194 N, the wet
# band with ~69, a rut they made is easier the second time and a hole the cart stood in is harder to leave. Each wheel's
# soil is where it stands (meadow.jl beach_weight: within 0.9 m of the water line the sand is wet and firm). The square
# of sand under the cart is drawn, so the ruts and berms it makes stay where it went.
Base.include(@__MODULE__, joinpath(@__DIR__, "..", "physics", "wheelsand.jl"))
Base.include(@__MODULE__, joinpath(@__DIR__, "..", "physics", "sandfield.jl"))
Base.include(@__MODULE__, joinpath(@__DIR__, "..", "physics", "stuck.jl"))
const LY_SAND = 6.0                  # m, the square of sand that follows the cart (4 cm cells)
const LY_SAND_LIFT = 0.045f0         # the loose layer drawn above the terrain (s169: at 1.2 cm the 3 cm ruts showed the
                                     # green terrain under them); the cart sits on it, so its height adds this too

function ly_soil(game, x, y)
    m = game.plugins["meadow"].mod
    _, d = Base.invokelatest(m.beach_weight, game.world.island, Float32(x), Float32(y))
    d < 0.9f0 ? WheelSand.SOILS[:firm_sand] : WheelSand.SOILS[:dry_sand]
end

function ly_sand_points!(pts, cs, ground)
    hr = Array(cs.f.h); nx, ny = size(hr); dx = cs.f.dx; fade = 0.3
    # drawn through a 3x3 binomial blur (the physics keeps its cells): s169, path traced, a rut on a diagonal heading
    # read as a row of dashes, the 4 cm cells' staircase
    h = similar(hr)
    @inbounds for j in 1:ny, i in 1:nx
        acc = 0f0; wsum = 0f0
        for b in -1:1, a in -1:1
            ii, jj = i + a, j + b
            (1 <= ii <= nx && 1 <= jj <= ny) || continue
            wt = (2f0 - abs(a)) * (2f0 - abs(b))
            acc += wt * hr[ii, jj]; wsum += wt
        end
        h[i, j] = acc / wsum
    end
    k = 0
    for j in 1:ny, i in 1:nx
        k += 1
        e = min(i - 0.5, nx - i + 0.5, j - 0.5, ny - j + 0.5) * dx
        w = Float32(clamp(e / fade, 0, 1))
        pts[k] = Point3f(cs.x0 + (i - 0.5) * dx, cs.y0 + (j - 0.5) * dx, ground[k] + w * (LY_SAND_LIFT + h[i, j]) - (1 - w) * 0.01f0)
    end
    pts
end

"""
A new square of sand centred on the cart. When the cart leaves the old one, the new square snaps to the old grid and
takes over every cell they share (surface, hard bed, compaction, load history) and the wheels' last settles: the ruts
behind the cart stay (s169: a fresh square wiped them 1.6 m before its edge).
"""
function ly_sand_new!(game, c)
    oldplot = get(LY, :sandplot, nothing)
    oldplot !== nothing && oldplot.parent !== nothing && delete!(oldplot.parent, oldplot)
    old = get(LY, :sand, nothing)
    cs = Stuck.CartSand(Float64(c[1]), Float64(c[2]); size = LY_SAND)
    n = size(cs.P, 1); dx = cs.f.dx; is = game.world.island
    if old !== nothing
        oi = round(Int, (cs.x0 - old.x0) / dx); oj = round(Int, (cs.y0 - old.y0) / dx)
        cs.x0 = old.x0 + oi * dx; cs.y0 = old.y0 + oj * dx
        for j in 1:n, i in 1:n
            io, jo = i + oi, j + oj
            (1 <= io <= n && 1 <= jo <= n) || continue
            cs.f.h[i, j] = old.f.h[io, jo]; cs.f.bed[i, j] = old.f.bed[io, jo]
            cs.f.comp[i, j] = old.f.comp[io, jo]; cs.P[i, j] = old.P[io, jo]
        end
        merge!(cs.last, old.last); cs.fallbacks = old.fallbacks
    end
    ground = [NG.terrain_height(is, Float32(cs.x0 + (i - 0.5) * dx), Float32(cs.y0 + (j - 0.5) * dx)) for j in 1:n for i in 1:n]
    pts = ly_sand_points!(Vector{Point3f}(undef, n^2), cs, ground)
    idx(i, j) = (j - 1) * n + i
    fs = GLTriangleFace[]
    for j in 1:n-1, i in 1:n-1
        push!(fs, GLTriangleFace(idx(i, j), idx(i + 1, j), idx(i + 1, j + 1)), GLTriangleFace(idx(i, j), idx(i + 1, j + 1), idx(i, j + 1)))
    end
    m = GeometryBasics.mesh(pts, fs; normal = GeometryBasics.normals(pts, fs))
    LY[:sandplot] = mesh!(game.stage.scene, m; color = RGBf(0.87, 0.77, 0.58), name = :landyacht_sand,
                          material = NG.Hikari.Diffuse(color = (0.87, 0.77, 0.58), roughness = 1f0))
    LY[:sand] = cs; LY[:sandground] = ground; LY[:sandfaces] = fs
    cs
end

"Redraw the square of sand from its field."
function ly_sand_draw!()
    cs = LY[:sand]; p = LY[:sandplot]
    pts = ly_sand_points!(Vector{Point3f}(undef, length(LY[:sandground])), cs, LY[:sandground])
    p[1][] = GeometryBasics.mesh(pts, LY[:sandfaces]; normal = GeometryBasics.normals(pts, LY[:sandfaces]))
end

# Digging (R by the yacht in Jump in, s169): one scoop of Lumi's beak takes the sand from a 13 cm patch in front of it
# (at most 4 cm deep, never below the hard bed) and drops THE SAME VOLUME in a heap behind it; the field then slumps to
# its angle of repose. Packed sand dug away takes its load history with it, and the heap is loose. Nothing here knows
# about wheels: a scoop in front of a wheel makes the ramp it rolls out on because the wheel then meets lower sand
# (s168: a ramp from the hole's floor over 40 cm: breakout 297 -> 42 N), a scoop anywhere else just makes a hole.
const LY_SCOOP_R, LY_SCOOP_D = 0.13, 0.04

function ly_dig!(game, st, lumi)
    cs = get(LY, :sand, nothing); cs === nothing && return false
    f = cs.f; dx = f.dx; n = size(f.h, 1)
    a = lumi.yaw + NG.species_of(lumi).heading
    fx, fy = cos(a), sin(a)
    s = (lumi.pos[1] + 0.35 * fx, lumi.pos[2] + 0.35 * fy)          # where the beak goes in
    # flung to the right, a little back (s169: straight behind, digging at a rear wheel heaped it under the cart)
    t = (lumi.pos[1] + 0.5 * fy - 0.1 * fx, lumi.pos[2] - 0.5 * fx - 0.1 * fy)
    cell(x, y) = (round(Int, (x - cs.x0) / dx + 0.5), round(Int, (y - cs.y0) / dx + 0.5))
    inside(i, j) = 1 <= i <= n && 1 <= j <= n
    is_, js_ = cell(s...); inside(is_, js_) || return false
    k = ceil(Int, LY_SCOOP_R / dx) + 1
    vol = 0.0
    for i in is_-k:is_+k, j in js_-k:js_+k
        inside(i, j) || continue
        d = hypot((i - is_) * dx, (j - js_) * dx); d < LY_SCOOP_R || continue
        dz = min(LY_SCOOP_D * (1 - (d / LY_SCOOP_R)^2), max(f.h[i, j] - f.bed[i, j], 0f0))
        f.h[i, j] -= dz; vol += dz * dx^2
        cs.P[i, j] = max(cs.P[i, j] - Float32(dz), 0f0)               # the packed layer goes with the scoop
        f.comp[i, j] = max(f.comp[i, j] - Float32(dz), 0f0)
    end
    vol > 0 || return false
    it, jt = cell(t...); R2 = 1.5 * LY_SCOOP_R; kt = ceil(Int, R2 / dx) + 1
    wsum = 0.0
    for i in it-kt:it+kt, j in jt-kt:jt+kt
        inside(i, j) && (d = hypot((i - it) * dx, (j - jt) * dx); d < R2) && (wsum += 1 - (d / R2)^2)
    end
    for i in it-kt:it+kt, j in jt-kt:jt+kt                        # the same volume, heaped (loose: no load history)
        inside(i, j) || continue
        d = hypot((i - it) * dx, (j - jt) * dx); d < R2 || continue
        add = Float32(vol * (1 - (d / R2)^2) / wsum / dx^2)
        f.h[i, j] += add; cs.P[i, j] = max(cs.P[i, j] - add, 0f0)
    end
    Stuck.slump!(cs, 6)
    # the wheels meet the new ground: settle them where they stand (the standing pull back changes with the ramp)
    ly_sand!(game, st, false)
    NG.log_event!(game.log, game.world.t, :yacht_dig; litres = round(1000vol, digits = 2), R = round(LY[:sandR], digits = 0))
    true
end

"Settle the four wheels in the sand (pressing ruts while `moving`); returns the sand's total pull back (N) and how deep the axles sit."
function ly_sand!(game, st, moving)
    c = st.P
    cs = get(LY, :sand, nothing)
    fresh = false
    if cs === nothing || max(abs(c[1] - cs.x0 - LY_SAND / 2), abs(c[2] - cs.y0 - LY_SAND / 2)) > LY_SAND / 2 - 1.4
        fresh = cs === nothing                           # the very first square: the cart first stands in it
        cs = ly_sand_new!(game, c)
        fresh && (moving = false)
    end
    fwd = (-sin(st.yaw), cos(st.yaw)); side = (cos(st.yaw), sin(st.yaw))
    tr = LY_WIDE / 2 + 0.08
    wheels = [(c[1] + a * fwd[1] + s * side[1], c[2] + a * fwd[2] + s * side[2]) for a in (0.8, -0.8) for s in (tr, -tr)]
    cs.soil = ly_soil(game, c[1], c[2])
    soils = [ly_soil(game, x, y) for (x, y) in wheels]  # each wheel where it stands: one in the wet band, one in dry sand
    # s169: the first settle meets fresh sand (48.5 N a wheel) and presses the holes; every later one finds the wheel in
    # its own hole (~34 N). Settled once only, any dig anywhere re-settled all four and cut the hold by 30%: settle twice.
    fresh && Stuck.cart_step!(cs, wheels, fwd, LY_MASS * 9.81 / 4, false; r = LY_WHEEL_D / 2, soils)
    sts = Stuck.cart_step!(cs, wheels, fwd, LY_MASS * 9.81 / 4, moving; r = LY_WHEEL_D / 2, soils)
    Stuck.slump!(cs, 2)
    ly_sand_draw!()
    R = sum(s.R for s in sts)
    sink = sum(s.zc for s in sts) / 4 - LY_WHEEL_D / 2  # the axles' height over the fresh sand minus the radius
    LY[:sandR] = R; LY[:sink] = sink
    R, sink
end

# A friend called to push (Q by the yacht in Jump in): it runs to the stern and leans on it. It pushes only as hard as
# the sand under its own hooves holds (WheelSand.foot: shear under its weight + the ridge of sand each hoof shoves up,
# s168: a 60 kg pony ~357 N in dry sand), so a friend in dry sand moves a stuck cart only if that beats what the wheels'
# sand holds. todo #745 gives every creature its real mass; until then a pony-sized 60 kg.
const LY_FRIEND = 60.0
const LY_HOOF = 0.07                 # m, a hoof's side
const LY_FRIEND_RUN = 2.5            # m/s, the fastest a pony-sized friend pushes (its push is gone at that speed)

"The friend's push on the stern this frame (N, along the cart's heading); walks it over first, then keeps it there."
function ly_pusher!(game, st, dt)
    p = get(LY, :pusher, nothing); p === nothing && return 0.0
    w = game.world
    i = findfirst(c -> c.id == p.id, w.creatures)
    if i === nothing || w.t > p.until
        i === nothing || NG.say!(w, w.creatures[i], "Phew!"; duration = 2.0)
        delete!(LY, :pusher); return 0.0
    end
    c = w.creatures[i]
    fwd = (-sin(st.yaw), cos(st.yaw)); back = LY_LEN / 2 + 0.4
    stern = NG.ground(w.island, (Float32(st.P[1] - back * fwd[1]), Float32(st.P[2] - back * fwd[2])))
    gap = hypot(c.pos[1] - stern[1], c.pos[2] - stern[2])
    if !p.leaning
        c.goal = NG.Goal(:yacht_push, stern, :idle, 2.0, w.t + 2.0, false, 0, true)   # runs over
        # the stern is just outside the cart's solid disc: let the friend through once it is close
        gap < 2.5 && isdefined(Main, :EXTRA_SOLIDS) && delete!(Main.EXTRA_SOLIDS, "landyacht")
        if w.t < p.detour_until                          # stepping round whatever blocked it
            c.goal = NG.Goal(:yacht_push, p.detour, :idle, 2.0, w.t + 2.0, false, 0, true)
            return 0.0
        end
        if gap < p.best - 0.2                            # getting there
            LY[:pusher] = p = merge(p, (best = gap, best_t = w.t))
        elseif w.t - p.best_t > 1.5 && p.tries < 3       # s169: friends from the north ran on the spot against a tree
            ux, uy = (stern[1] - c.pos[1]) / gap, (stern[2] - c.pos[2]) / gap
            sgn = isodd(p.tries) ? -1f0 : 1f0
            dp = NG.ground(w.island, (Float32(c.pos[1] - 3sgn * uy + ux), Float32(c.pos[2] + 3sgn * ux + uy)))
            LY[:pusher] = p = merge(p, (detour = dp, detour_until = w.t + 1.5, tries = p.tries + 1, best = Inf, best_t = w.t + 1.5))
            return 0.0
        elseif w.t - p.best_t > 4.0                      # s169: Pinchy ran on the spot behind the hut for 15 s
            NG.say!(w, c, "I can't get round to it!"; duration = 3.0)
            delete!(LY, :pusher); return 0.0
        end
        gap < 0.5 || return 0.0
        LY[:pusher] = p = merge(p, (leaning = true, until = w.t + 9.0))
        NG.say!(w, c, "Hnnngh!"; duration = 2.5)
    end
    # leaning on the stern it goes where the stern goes: closes in at most 3 m/s (never jumps), then stays on it
    # (s169: only closing in, it trailed 0.6-0.8 m and the push came and went, the cart pulsing 0.1 <-> 1.2 m/s)
    c.goal = NG.Goal(:yacht_push, stern, :idle, 1.0, w.t + 1.0, true, 0, false)
    # the cart's solid disc (1.4 m) stood where it last stopped and shoved the friend off the stern (s169)
    isdefined(Main, :EXTRA_SOLIDS) && delete!(Main.EXTRA_SOLIDS, "landyacht")
    stepv = gap < 0.12 ? 1.0 : min(gap, 3.0 * dt) / max(gap, 1e-6)
    c.pos = Point3f(c.pos[1] + stepv * (stern[1] - c.pos[1]), c.pos[2] + stepv * (stern[2] - c.pos[2]), stern[3])
    c.yaw = Float32(atan(fwd[2], fwd[1])) - NG.species_of(c).heading
    c.action = st.v > 0.05 ? :walk : :idle
    gap < 0.3 || return 0.0
    # its grip caps the push, and so does how fast it can move its legs: a pusher's force falls to nothing at its
    # running speed (s169: grip alone ran the cart to 3.9 m/s, 15 m in 9 s; now it settles at a walk, ~1.1 m/s in dry sand)
    grip = 2 * WheelSand.foot(ly_soil(game, stern[1], stern[2]), LY_FRIEND * 9.81 / 2, LY_HOOF, LY_HOOF, Inf).Fmax
    grip * max(0.0, 1 - st.v / LY_FRIEND_RUN)
end

"Q by the parked yacht in Jump in: the nearest friend comes to push."
function ly_call_friend!(game, st, lumi)
    w = game.world
    best = nothing; bd = 25.0
    for c in w.creatures
        (c.controlled || c.id == lumi.id) && continue
        d = hypot(c.pos[1] - st.P[1], c.pos[2] - st.P[2])
        d < bd && (best = c; bd = d)
    end
    best === nothing && return NG.say!(w, lumi, "Nobody near enough to help..."; duration = 3.0)
    LY[:pusher] = (id = best.id, until = w.t + 25.0, leaning = false, best = Inf, best_t = w.t,
                   tries = 0, detour = Point3f(0), detour_until = 0.0)
    NG.say!(w, lumi, "$(best.name), can you give it a shove?"; duration = 3.0)
    NG.log_event!(game.log, w.t, :yacht_push_call; friend = best.name)
end

"Move every plot of the cart to centre `st.P`, heading `st.yaw`; boom and sail also turn about the mast by the sheet."
function ly_place!(game, st)
    c0 = Vec3f(LY[:pos]); is = game.world.island
    z = NG.terrain_height(is, st.P[1], st.P[2]) + (haskey(LY, :sink) ? LY_SAND_LIFT + Float32(LY[:sink]) : 0f0)
    Rz = NG.rot_z(Float32(st.yaw - LY[:yaw]))
    Pn = Vec3f(st.P[1], st.P[2], z)
    Rs = NG.rot_z(Float32(st.sheet - LY_SHEET)); m = Vec3f(LY[:mast])
    for p in LY[:plots]
        if any(s -> s === p, LY[:swingers])
            Makie.rotate!(p, Rz * Rs); Makie.translate!(p, Rz * (m - Rs * m - c0) + Pn)
        else
            Makie.rotate!(p, Rz); Makie.translate!(p, Pn - Rz * c0)
        end
    end
    Pn
end

function ly_sail!(game, dt)
    ly_server_check!()
    w = game.world; st = LY[:st]; k = game.keys_down; K = Makie.Keyboard
    me = findfirst(c -> c.controlled, w.creatures)
    lumi = me === nothing ? nothing : w.creatures[me]
    playing = lumi !== nothing && game.minigame isa NG.JumpIn
    aboard = get(LY, :aboard, false)
    # climb aboard: E within 2.2 m of the cart's middle
    e_now = K.e in k
    if playing && !aboard && e_now && !get(LY, :e_was, false) && hypot(lumi.pos[1] - st.P[1], lumi.pos[2] - st.P[2]) < 2.2
        LY[:aboard] = aboard = true
        isdefined(Main, :EXTRA_SOLIDS) && delete!(Main.EXTRA_SOLIDS, "landyacht")
        NG.say!(w, lumi, "Rigging the sail... (W haul in, S let out, A/D steer, Space hop off; stuck in soft sand? Q calls a friend to push, R by a wheel digs)"; duration = 7.0)
        NG.log_event!(game.log, w.t, :yacht_board)
    end
    LY[:e_was] = e_now
    q_now = K.q in k
    if playing && q_now && !get(LY, :q_was, false) && !haskey(LY, :pusher) &&
       hypot(lumi.pos[1] - st.P[1], lumi.pos[2] - st.P[2]) < 3.0
        ly_call_friend!(game, st, lumi)
    end
    LY[:q_was] = q_now
    r_now = K.r in k                                            # R by the yacht: one scoop of the beak
    if playing && !aboard && r_now && !get(LY, :r_was, false) && hypot(lumi.pos[1] - st.P[1], lumi.pos[2] - st.P[2]) < 3.0
        if ly_dig!(game, st, lumi)
            lumi.action = :eat; NG.HELD[Int(lumi.id)] = w.t + 0.5    # head down in the sand for the scoop
        end
    end
    LY[:r_was] = r_now
    shove = ly_pusher!(game, st, dt)
    if aboard && (!playing || K.space in k)                   # hop off (or the player left Jump in)
        LY[:aboard] = aboard = false
        ly_server_stop!()
        if lumi !== nothing
            side = Vec2f(cos(st.yaw), sin(st.yaw))
            lumi.pos = NG.ground(w.island, (st.P[1] - 1.6f0 * side[1], st.P[2] - 1.6f0 * side[2]))
            lumi.action = :jump
        end
        NG.log_event!(game.log, w.t, :yacht_leave; d = round(st.d, digits = 1))
    end
    if !aboard && st.v == 0 && shove == 0
        isdefined(Main, :EXTRA_SOLIDS) && (Main.EXTRA_SOLIDS["landyacht"] = [(st.P, 1.4f0)])   # where it stands now
        haskey(LY, :sand) || (ly_sand!(game, st, false); ly_place!(game, st))   # parked: the wheels settle into the sand
        return
    end
    # the newest force from the flow (none while the box warms up: the cart waits, as it would for a rigged sail)
    out = get(LY, :srv_out, nothing)
    if out !== nothing
        while isready(out); LY[:force] = take!(out); end
    end
    f = aboard ? get(LY, :force, nothing) : nothing
    sheet = clamp(st.sheet + dt * 0.25 * ((aboard && K.s in k) - (aboard && K.w in k)), deg2rad(2), deg2rad(85))
    steer = aboard ? 0.35 * ((K.a in k) - (K.d in k)) : 0.0
    d, strength = Base.invokelatest(Main.WIND[:now], w.t)
    Wv = LY_WIND * strength .* (Float64(d[1]), Float64(d[2]))
    fwd = (-sin(st.yaw), cos(st.yaw)); side = (cos(st.yaw), sin(st.yaw))
    Va = Wv .- st.v .* fwd; U = max(hypot(Va...), 1e-6)
    from = .-Va ./ U
    beta = acos(clamp(from[1] * fwd[1] + from[2] * fwd[2], -1, 1))   # where the apparent wind comes from, off the bow
    aback = from[1] * side[1] + from[2] * side[2] > 0               # from the sail's side: it is pressed back
    alpha = aback ? 0.0 : beta - sheet
    # the box warms at the angle the sail really has (s167: warmed at 15 deg, a 'stalled' start crept 5 m in 3 s)
    aboard && !haskey(LY, :srv_task) && ly_server_start!(clamp(alpha, 0.0, deg2rad(90)))
    drive = 0.0
    if f !== nothing
        cmd = LY[:srv_cmd]
        if abs(alpha - get(LY, :sent, 99.0)) > deg2rad(0.3) || time() - get(LY, :sent_t, 0.0) > 0.5
            put!(cmd, (clamp(alpha, 0.0, deg2rad(90)), U / 1.2)); LY[:sent] = alpha; LY[:sent_t] = time()
        end
        q = 0.5 * 1.2 * U^2 * LY_AREA
        drive = alpha <= 0 ? 0.0 : q * (f.CL * sin(beta) - f.CD * cos(beta))    # luffing: the cloth flaps, no drive
    end
    # the slope along the heading: rolling uphill costs m g sin(grade)
    is = w.island
    hb = NG.terrain_height(is, st.P[1] - 0.8 * fwd[1], st.P[2] - 0.8 * fwd[2])     # under the back and front axles
    hf = NG.terrain_height(is, st.P[1] + 0.8 * fwd[1], st.P[2] + 0.8 * fwd[2])
    grade = LY_MASS * 9.81 * (hf - hb) / LY_BASE
    push = drive - grade + shove
    v = st.v
    # the sand's pull back: rolling, the wheels settle in the field every frame (ruts, berms, the soil they stand on);
    # standing, what the holes they sit in hold (s168: 297 N to break out of the friends' holes, 194 rolling in dry sand)
    roll = v > 1e-3 ? first(ly_sand!(game, st, true)) : get(LY, :sandR, LY_ROLL)
    net = push - (v > 1e-3 ? roll : clamp(push, -roll, roll))      # the sand holds it still until the push beats it
    v = max(v + net / LY_MASS * dt, 0.0)
    nx, ny = st.P[1] + v * dt * fwd[1], st.P[2] + v * dt * fwd[2]
    if !NG.on_land(is, nx, ny; margin = 0.8f0)                 # the wet edge: the wheels dig in and it stops
        v = 0.0; nx, ny = st.P[1], st.P[2]
    end
    yaw = st.yaw + v * tan(steer) / LY_BASE * dt
    LY[:st] = st = (P = Point2f(nx, ny), yaw = yaw, v = v, sheet = sheet, d = st.d + v * dt)
    LY[:last] = (; t = w.t, v, U, beta = rad2deg(beta), alpha = rad2deg(alpha), drive, aback, shove, roll,
                 CL = f === nothing ? NaN : f.CL, CD = f === nothing ? NaN : f.CD, d = st.d)
    Pn = ly_place!(game, st)
    if v > 0                                                  # the wheels roll: turned by the distance over the radius
        qs = LY[:qw] * Makie.qrotation(Vec3f(0, 0, 1), Float32(-st.d / (LY_WHEEL_D / 2)))
        Makie.update!(LY[:wheels]; rotation = fill(qs, 4))
    end
    if aboard && lumi !== nothing
        NG.HELD[Int(lumi.id)] = w.t + 0.3                     # Jump in's walking keys are the cart's now
        off = NG.rot_z(Float32(yaw)) * Vec3f(-0.3f0, -0.55f0, LY_DECK_Z + 0.06f0)
        lumi.pos = Point3f(Pn + off)
        lumi.yaw = Float32(yaw + pi / 2) - NG.species_of(lumi).heading
        lumi.action = :sit
    end
    return
end

function NG.stop!(::LandYacht, game)
    ly_server_stop!(); delete!(LY, :aboard)
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
    sp = pop!(LY, :sandplot, nothing); sp !== nothing && sp.parent !== nothing && delete!(sp.parent, sp)
    delete!(LY, :pusher)
    delete!(LY, :sand); delete!(LY, :sink); delete!(LY, :sandR)   # its CartSand type is this copy of the plugin's
    isdefined(Main, :EXTRA_SOLIDS) && delete!(Main.EXTRA_SOLIDS, "landyacht")
    return
end

register!(LandYacht())
