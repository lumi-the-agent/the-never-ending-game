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
    # s167: bow north-west along the open beach (it pointed into the sea 5 m off); the island's wind comes from the
    # south-west, so the cart starts on a close reach with the sail to leeward (+x in the cart)
    yaw = 1.05f0
    c = c + 2.0f0 * Point2f(-sin(yaw), cos(yaw))       # s167: 2 m on, out of the hollow it sat in (16% grade under it)
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

"Move every plot of the cart to centre `st.P`, heading `st.yaw`; boom and sail also turn about the mast by the sheet."
function ly_place!(game, st)
    c0 = Vec3f(LY[:pos]); is = game.world.island
    z = NG.terrain_height(is, st.P[1], st.P[2])
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
        NG.say!(w, lumi, "Rigging the sail... (W haul in, S let out, A/D steer, Space hop off)"; duration = 6.0)
        NG.log_event!(game.log, w.t, :yacht_board)
    end
    LY[:e_was] = e_now
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
    if !aboard && st.v == 0
        isdefined(Main, :EXTRA_SOLIDS) && !haskey(Main.EXTRA_SOLIDS, "landyacht") && (Main.EXTRA_SOLIDS["landyacht"] = [(st.P, 1.4f0)])
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
    push = drive - grade
    v = st.v
    net = push - (v > 1e-3 ? LY_ROLL : clamp(push, -LY_ROLL, LY_ROLL))      # the sand holds it still until the push beats it
    v = max(v + net / LY_MASS * dt, 0.0)
    nx, ny = st.P[1] + v * dt * fwd[1], st.P[2] + v * dt * fwd[2]
    if !NG.on_land(is, nx, ny; margin = 0.8f0)                 # the wet edge: the wheels dig in and it stops
        v = 0.0; nx, ny = st.P[1], st.P[2]
    end
    yaw = st.yaw + v * tan(steer) / LY_BASE * dt
    LY[:st] = st = (P = Point2f(nx, ny), yaw = yaw, v = v, sheet = sheet, d = st.d + v * dt)
    LY[:last] = (; t = w.t, v, U, beta = rad2deg(beta), alpha = rad2deg(alpha), drive, aback,
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
    isdefined(Main, :EXTRA_SOLIDS) && delete!(Main.EXTRA_SOLIDS, "landyacht")
    return
end

register!(LandYacht())
