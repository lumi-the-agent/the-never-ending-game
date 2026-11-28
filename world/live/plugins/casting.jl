# Casting lead in the beach sand (s170, project casting: idea 'Cast your own lead plates in the beach'). In Jump in on
# the sand, H stamps Lumi's foot into the damp sand; H again pours molten lead from the ladle into the print: it runs
# where the print runs, pools to a level, loses its heat into the sand and the air and freezes from the thin edges in
# (physics/casting.jl: virtual-pipe flow, lead's surface tension front, contact conduction, latent heat); the bright
# liquid dulls to grey where it has frozen. H once it has all frozen lifts the casting out and lays it beside the hole
# upside down: a lead copy of exactly the print, as far as the lead got before it froze.
isdefined(Main, :CASTING) || Core.eval(Main, :(const CASTING = Dict{Symbol,Any}()))   # not CAST: post_stills.jl has a CAST of characters (s171)
const CAST = Main.CASTING
const NG = NeverendingGame
using GeometryBasics, Makie
Base.include(@__MODULE__, joinpath(@__DIR__, "..", "physics", "casting.jl"))

const CT_N, CT_DX = 70, 0.01           # a 70 cm square of sand, 1 cm cells
# the patch is drawn over the terrain at CAST[:lift] and fades at its edge to CAST[:edge]: inside the yacht's square of
# sand (drawn 4.5 cm up) it sits on that sand, edge and all; elsewhere 3 cm up, fading into the terrain
ct_lift() = Float32(get(CAST, :lift, 0.03))
const CT_STAMP = 0.022                 # how deep a stamping foot goes in damp sand (m)
const CT_RATE = 25e-6                  # the ladle's stream (m3/s)
# lead is a bright mirror while liquid and skins dull mid-grey when it freezes. A fully metallic flat casting mirrors the
# sky dome, darker than sunlit sand (s171 tools/leadlook.jl, traced slab luminance: metal 1 rough .5 = 0.21, rough .8 =
# 0.30, grey card = 0.49); sand-cast lead is grain-rough with an oxide skin, so half metal half diffuse grey: 0.39 with a sheen
const LEAD_LIQ = NG.Hikari.Principled(base_color = (0.86f0, 0.87f0, 0.89f0), metallic = 1f0, roughness = 0.02f0)
const LEAD_SOL = NG.Hikari.Principled(base_color = (0.52f0, 0.53f0, 0.55f0), metallic = 0.5f0, roughness = 0.7f0)

struct CastingSys <: System end

function ct_clear!()
    for k in (:sandplot, :solidplot, :liquidplot, :streamplot, :castplot)
        p = get(CAST, k, nothing)
        p !== nothing && p.parent !== nothing && delete!(p.parent, p)
        delete!(CAST, k)
    end
    delete!(CAST, :pour); delete!(CAST, :viewkey); delete!(CAST, :backstep); CAST[:stage] = :none   # a new stamp: its own view
end

"Lumi's foot as a depth map (m) in the patch's cells: three toes forward, one back, a pad; `yaw` = which way it points."
function ct_foot(yaw)
    g = zeros(CT_N, CT_N); c = (CT_N + 1) / 2
    toes = ((0.0, 0.10), (0.5, 0.09), (-0.5, 0.09), (pi, 0.045))   # (angle off forward, length m)
    for j in 1:CT_N, i in 1:CT_N
        x = (i - c) * CT_DX; y = (j - c) * CT_DX
        u = x * cos(yaw) + y * sin(yaw); v = -x * sin(yaw) + y * cos(yaw)      # u forward, v across
        d = hypot(u, v) < 0.022 ? 1.0 : 0.0                                   # the pad
        for (a, L) in toes
            s = u * cos(a) + v * sin(a); w = -u * sin(a) + v * cos(a)
            (0 <= s <= L && abs(w) <= 0.009 * (1 - 0.4s / L)) && (d = max(d, 1 - 0.5 * (s / L)^2))
        end
        g[i, j] = -CT_STAMP * d
    end
    g
end

ct_pt(i, j, o, ter, z) = Point3f(o[1] + (i - (CT_N + 1) / 2) * CT_DX, o[2] + (j - (CT_N + 1) / 2) * CT_DX, ter[i, j] + ct_lift() + z)

function ct_grid_mesh(o, ter, zf)
    idx(i, j) = (j - 1) * CT_N + i
    pts = [ct_pt(i, j, o, ter, zf(i, j)) for j in 1:CT_N for i in 1:CT_N]
    fs = GLTriangleFace[]
    for j in 1:CT_N-1, i in 1:CT_N-1
        push!(fs, GLTriangleFace(idx(i, j), idx(i + 1, j), idx(i + 1, j + 1)), GLTriangleFace(idx(i, j), idx(i + 1, j + 1), idx(i, j + 1)))
    end
    GeometryBasics.mesh(pts, fs; normal = GeometryBasics.normals(pts, fs))
end

"The drawn sand over the terrain at cell (i, j): fades down into the terrain at the patch's edge."
function ct_sand_z(ground, i, j)
    e = min(i - 0.5, CT_N - i + 0.5, j - 0.5, CT_N - j + 0.5) * CT_DX
    w = clamp(e / 0.06, 0, 1)
    w * ground[i, j] + (1 - w) * (get(CAST, :edge, -0.01) - ct_lift())
end
ct_sand_mesh(o, ter, ground) = ct_grid_mesh(o, ter, (i, j) -> ct_sand_z(ground, i, j))

# the lead's surfaces dive just under the sand where there is none, so the sand hides their edges
ct_solid_z(p) = (i, j) -> p.ds[i, j] > 2e-4 ? p.ground[i, j] + p.ds[i, j] : ct_sand_z(p.ground, i, j) - 0.003
ct_liquid_z(p) = (i, j) -> p.dl[i, j] > 2e-4 ? p.ground[i, j] + p.ds[i, j] + p.dl[i, j] : min(p.ground[i, j] + p.ds[i, j], ct_sand_z(p.ground, i, j)) - 0.002

function ct_stamp!(game, lumi)
    ct_clear!()
    is = game.world.island; sc = game.stage.scene
    CAST[:scene] = sc                                             # the view looks through its plots (ct_boxes_in_view)
    yaw = lumi.yaw + NG.species_of(lumi).heading
    o = (lumi.pos[1] + 0.35 * cos(yaw), lumi.pos[2] + 0.35 * sin(yaw))
    ter = [NG.terrain_height(is, Float32(o[1] + (i - (CT_N + 1) / 2) * CT_DX), Float32(o[2] + (j - (CT_N + 1) / 2) * CT_DX)) for i in 1:CT_N, j in 1:CT_N]
    ground = ct_foot(yaw)
    ys = isdefined(Main, :LANDYACHT) ? get(Main.LANDYACHT, :sand, nothing) : nothing
    half = CT_N * CT_DX / 2 + 0.05
    on_yacht_sand = ys !== nothing && ys.x0 + half < o[1] < ys.x0 + 6.0 - half && ys.y0 + half < o[2] < ys.y0 + 6.0 - half
    CAST[:lift], CAST[:edge] = on_yacht_sand ? (0.046, 0.046) : (0.03, -0.01)
    p = Casting.Pour(ground, CT_DX)
    CAST[:pour] = p; CAST[:o] = o; CAST[:ter] = ter; CAST[:yaw] = yaw
    CAST[:backstep] = game.world.t + 3.0                          # step back off the print (ct_backstep!)
    CAST[:volume] = -sum(ground) * CT_DX^2 * 1.03                    # the print's volume, and a little over
    CAST[:sandplot] = mesh!(sc, ct_sand_mesh(o, ter, ground); color = RGBf(0.87, 0.77, 0.58), name = :cast_sand,     # the yacht's sand, so they meet without a seam
                            material = NG.Hikari.Diffuse(color = (0.87, 0.77, 0.58), roughness = 1f0))
    CAST[:solidplot] = mesh!(sc, ct_grid_mesh(o, ter, ct_solid_z(p)); color = RGBf(0.46, 0.47, 0.49), name = :cast_solid, material = LEAD_SOL)
    CAST[:liquidplot] = mesh!(sc, ct_grid_mesh(o, ter, ct_liquid_z(p)); color = RGBf(0.80, 0.81, 0.84), name = :cast_liquid, material = LEAD_LIQ)
    CAST[:stage] = :print
    NG.say!(game.world, lumi, "Stamp! Now H to pour the lead in"; duration = 4.0)
    NG.log_event!(game.log, game.world.t, :cast_stamp; cm3 = round(1e6 * CAST[:volume], digits = 1))
end

"""
After the stamp Lumi steps BACK off its print, still facing it (s171: drawn 1.8 m tall and 1.3 m long, its belly and
beak hung over the print, no camera could see it): it walks backwards at a slow step with its gait run in reverse (legs
step back, no slide), the player's keys held off (NG.HELD) until it stands 1 m from the print or 3 s pass.
"""
function ct_backstep!(game, lumi, dt)
    st = get(CAST, :backstep, nothing)
    st === nothing && return
    w = game.world; o = CAST[:o]
    if hypot(lumi.pos[1] - o[1], lumi.pos[2] - o[2]) >= 1.0 || w.t > st
        delete!(CAST, :backstep); lumi.action = :idle
        return
    end
    NG.HELD[Int(lumi.id)] = w.t + 0.15
    sp = NG.species_of(lumi)
    step = Float32(0.45 * sp.speed * dt)                          # a careful backward step: under half its walk
    dx, dy = lumi.pos[1] - o[1], lumi.pos[2] - o[2]; L = max(hypot(dx, dy), 1e-3)
    nx, ny = lumi.pos[1] + step * dx / L, lumi.pos[2] + step * dy / L   # straight away from the print, facing it
    NG.on_land(w.island, nx, ny; margin = 0.1f0) || (delete!(CAST, :backstep); return)
    lumi.pos = NG.ground(w.island, (nx, ny))
    lumi.phase -= min(sp.stride * max(step, 0.15f0 * Float32(dt)), NG.GAIT_MAX * Float32(dt))
    lumi.action = :walk; lumi.extra = 0f0
end

"The pour's cell: the print's heel pad (the deepest point, the middle of the patch)."
ct_src() = ((CT_N + 1) ÷ 2, (CT_N + 1) ÷ 2)

function ct_pour_step!(game, dt)
    p = CAST[:pour]
    n = clamp(round(Int, dt / 1e-3), 1, 60)                     # 1 ms steps (the front moves ~30 cm/s on 1 cm cells)
    for _ in 1:n
        r = p.poured < CAST[:volume] ? CT_RATE : 0.0
        Casting.step!(p, 1e-3; src = ct_src(), rate = r, Tpour = 400.0, sand = Casting.SANDS[:damp])
    end
    o, ter = CAST[:o], CAST[:ter]
    CAST[:solidplot][1][] = ct_grid_mesh(o, ter, ct_solid_z(p))
    CAST[:liquidplot][1][] = ct_grid_mesh(o, ter, ct_liquid_z(p))
    pouring = p.poured < CAST[:volume]
    sp = get(CAST, :streamplot, nothing)
    if pouring && sp === nothing
        s = ct_src(); base = ct_pt(s..., o, ter, p.ground[s...])
        CAST[:streamplot] = mesh!(game.stage.scene, GeometryBasics.normal_mesh(Cylinder(base, base + Point3f(0, 0, 0.45f0), 0.004f0));
                                  color = RGBf(0.80, 0.81, 0.84), material = LEAD_LIQ, name = :cast_stream)
    elseif !pouring && sp !== nothing
        delete!(sp.parent, sp); delete!(CAST, :streamplot)
    end
    if !pouring && all(<(1e-7), p.dl)
        CAST[:stage] = :cast
        c = CAST[:result] = Casting.casting(p)
        NG.log_event!(game.log, game.world.t, :cast_frozen; g = round(1000c.kg, digits = 0), cells = c.cells, s = round(p.t, digits = 1))
    end
end

"Lift the casting out and lay it upside down on the sand beside the print: its upper side is now the print's floor."
function ct_lift!(game, lumi)
    p = CAST[:pour]; o, ter = CAST[:o], CAST[:ter]
    top = maximum(p.ground[k] + p.ds[k] for k in eachindex(p.ds) if p.ds[k] > 2e-4)
    off = 24                                                     # cells to the side, clear of the hole
    m = ct_grid_mesh(o, ter, (i, j) -> begin
        si, sj = CT_N + 1 - i, j - off                           # flipped over about the patch's middle line
        z0 = ct_sand_z(p.ground, i, j)
        (1 <= sj <= CT_N && p.ds[si, sj] > 2e-4) ? z0 + (top - p.ground[si, sj]) : z0 - 0.004
    end)
    CAST[:castplot] = mesh!(game.stage.scene, m; color = RGBf(0.46, 0.47, 0.49), material = LEAD_SOL, name = :cast_piece)
    CAST[:solidplot].visible[] = false
    sp = get(CAST, :streamplot, nothing)                         # (a lift mid-pour) the ladle's stream stops
    sp !== nothing && (delete!(sp.parent, sp); delete!(CAST, :streamplot))
    c = Casting.casting(p)
    NG.say!(game.world, lumi, "A lead foot! $(round(Int, 1000c.kg)) grams of it"; duration = 5.0)
    NG.log_event!(game.log, game.world.t, :cast_lift; g = round(1000c.kg, digits = 0))
    CAST[:stage] = :lifted
end

"""
Anything DRAWN between the eye and 80% of the way to the target: every plot of the stage's scene whose world bounding
box the line passes through (plugin scenery the engine's `obstruction` does not know: s171 a board on a post in front
of the cast). Plots wider than 6 m (terrain, sea, scattered grass) and the cast's own are skipped.
"""
function ct_boxes_in_view(eye, target)
    sc = get(CAST, :scene, nothing)
    sc === nothing && return 0f0
    own = Set(objectid(CAST[k]) for k in (:sandplot, :solidplot, :liquidplot, :streamplot, :castplot) if haskey(CAST, k))
    o = 0f0
    for p in sc.plots
        objectid(p) in own && continue
        bb = Makie.boundingbox(p)
        (all(isfinite, minimum(bb)) && all(isfinite, maximum(bb))) || continue
        wd = widths(bb)
        max(wd[1], wd[2]) > 6 && continue
        lo = minimum(bb) .- 0.05f0; hi = maximum(bb) .+ 0.05f0
        for s in 0.05f0:0.075f0:0.8f0
            q = eye + s * (target - eye)
            all(lo .<= q .<= hi) && (o += 1f0; break)
        end
    end
    return o
end

"""
Jump in's view while Lumi casts (s171: the chase camera framed the swing and the motor bench, the print was not in
the picture): low from the side across the print, Lumi at the edge, from the side with more open ground around the eye.
"""
function ct_view(w)
    (get(CAST, :stage, :none) == :none || !haskey(CAST, :o)) && return nothing
    me = findfirst(c -> c.controlled, w.creatures)
    me === nothing && return nothing
    lumi = w.creatures[me]; o = CAST[:o]
    dx, dy = o[1] - lumi.pos[1], o[2] - lumi.pos[2]; L = hypot(dx, dy)
    L > 2.5 && return nothing                                    # walked off: the chase camera again
    ux, uy = L > 1e-3 ? (dx / L, dy / L) : (1.0, 0.0)
    gz = NG.ground(w.island, (Float32(o[1]), Float32(o[2])))[3]
    # from beyond the print and to the side, looking back across it at Lumi: the print in front, Lumi's face behind
    # (s171 first try from Lumi's side: its legs filled the frame and hid the print)
    tx, ty = o[1] - 0.3dx, o[2] - 0.3dy
    target = Point3f(tx, ty, gz + 0.3f0)
    # the eye: 12 directions round the print, the least obstructed by anything the cameras know (terrain, trees,
    # bushes, creatures, plugin scenery: the second s171 try had a plank and a post in front), ties to 'beyond the
    # print, looking back at Lumi'; found once per stamp and Lumi position, not every frame
    key = (o, round(lumi.pos[1], digits = 1), round(lumi.pos[2], digits = 1))
    if get(CAST, :viewkey, nothing) != key
        base = atan(uy, ux); best = nothing; bo = Inf32
        for k in 0:11
            a = base + 2pi * k / 12
            ex, ey = o[1] + 2.2cos(a), o[2] + 2.2sin(a)
            ez = max(gz + 1.4f0, NG.ground(w.island, (Float32(ex), Float32(ey)))[3] + 1.0f0)   # over grass tufts and boards the cameras do not know (s171)
            eye = Point3f(ex, ey, ez)
            # Lumi itself stands 35 cm from the print and hid it from the sea side (s171): its body counts too
            m = lumi.pos + Point3f(0, 0, 0.5f0 * NG.species_of(lumi).height)
            pz = Point3f(o[1], o[2], gz)
            lb = 4f0 * max(0f0, 0.45f0 - NG.segment_distance(eye, pz, m))
            ob = Float32(NG.obstruction(w, eye, target)) + ct_boxes_in_view(eye, target) + lb +
                 0.05f0 * abs(Float32(mod(a - base - 0.7 + pi, 2pi) - pi))
            ob < bo && (bo = ob; best = eye)
        end
        CAST[:viewkey] = key; CAST[:vieweye] = best
    end
    pts = [lumi.pos, Point3f(o[1], o[2], gz)]
    return (lumi.id, pts, (CAST[:vieweye], target))
end

function NG.start!(::CastingSys, game)
    ct_clear!()
    NG.CAMERA_GROUPS["casting"] = ct_view
    nothing
end

function NG.step!(::CastingSys, game, dt)
    game.stage === nothing && return
    w = game.world
    me = findfirst(c -> c.controlled, w.creatures)
    lumi = me === nothing ? nothing : w.creatures[me]
    playing = lumi !== nothing && game.minigame isa NG.JumpIn
    h_now = Makie.Keyboard.h in game.keys_down
    if playing && h_now && !get(CAST, :h_was, false)
        st = get(CAST, :stage, :none)
        near = haskey(CAST, :o) && hypot(lumi.pos[1] - CAST[:o][1], lumi.pos[2] - CAST[:o][2]) < 1.5
        bw, dc = Base.invokelatest(game.plugins["meadow"].mod.beach_weight, w.island, lumi.pos[1], lumi.pos[2])
        # sand where meadow.jl DRAWS sand: the cove, or the engine's beach band below 0.36 m (s171: 'dc < 9' let Lumi
        # stamp on lawn up to 9 m inland; both s170 post takes put the print on grass)
        ys = isdefined(Main, :LANDYACHT) ? get(Main.LANDYACHT, :sand, nothing) : nothing   # the yacht's drawn sand square
        on_ys = ys !== nothing && ys.x0 < lumi.pos[1] < ys.x0 + 6.0 && ys.y0 < lumi.pos[2] < ys.y0 + 6.0
        sandy = bw > 0.5 || on_ys || NG.ground(w.island, (lumi.pos[1], lumi.pos[2]))[3] < 0.36f0
        if (st == :none || st == :lifted || !near) && st != :pouring
            sandy ? ct_stamp!(game, lumi) : NG.say!(w, lumi, "I need sand for a mould (the beach)"; duration = 3.0)
        elseif st == :print
            CAST[:stage] = :pouring
            NG.log_event!(game.log, w.t, :cast_pour)
        elseif st == :cast
            ct_lift!(game, lumi)
        end
    end
    CAST[:h_was] = h_now
    playing && ct_backstep!(game, lumi, dt)
    get(CAST, :stage, :none) == :pouring && ct_pour_step!(game, dt)
    return
end

NG.stop!(::CastingSys, game) = (ct_clear!(); delete!(NG.CAMERA_GROUPS, "casting"); nothing)

register!(CastingSys())
