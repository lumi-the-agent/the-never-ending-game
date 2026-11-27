# Lamplight: after sunset the stone lanterns and the cottage glow warm, and each throws a soft
# pool of orange light on the ground around it, so the night has warm places to walk to
# between the cool moonlit meadow (perfectionist-0024: "at least two warm light pools").
# Two plots: one mesh for all ground pools (vertex alpha fades to the rim), one meshscatter
# for the lamp flames. Both hidden by day.
isdefined(Main, :LAMPLIGHT) || Core.eval(Main, :(const LAMPLIGHT = Dict{Symbol,Any}()))

const NG = NeverendingGame
const LAMP_VERSION = 11   # s134 low-poly glow markers
const WARM = (1.0f0, 0.68f0, 0.32f0)
const FLAME = RGBf(1.0, 0.82, 0.45)
const WINDOW = RGBf(1.0, 0.9, 0.62)
# the cottage's round windows in its model (found from the blue glass texels): centre, outward normal
# a little lamp over the door (the door is left of the front window, on the same -y face; s41)
const DOOR_LAMP = Point3f(-0.24, -0.25, 0.47)
const COTTAGE_WINDOWS = ((Point3f(0.205, -0.215, 0.265), Vec3f(0, -1, 0)), (Point3f(0.195, 0.205, 0.265), Vec3f(0, 1, 0)))

# soft warm halos round every lit window and flame, so they read as lights from the overview camera
# (perfectionist s40: "cottage windows do not glow"): many thin shells with a low alpha (moon.jl: a
# few big ones show hard rings)
const HALO_SHELLS = 20
const HALO_ALPHA = 0.04f0

"Concentric shells of radius r0..r1 round `c` into the halo lists."
# a quiet copy (game_clip, game_still: path traced) gets no shells: every shell is an emissive sphere, an area
# light in the tracer, and 20 per light helped push a dusk clip out of GPU memory (s41)
const HALO_N = Ref(HALO_SHELLS)
function halo!(hpos, hsize, hcol, c, r0, r1)
    n = HALO_N[]
    n < 2 && return
    for k in 1:n
        push!(hpos, c); push!(hsize, Vec3f(r0 + (r1 - r0) * (k - 1) / (n - 1)))
        push!(hcol, RGBAf(1.0, 0.78, 0.45, HALO_ALPHA * min(3f0, HALO_SHELLS / n)))
    end
end

struct Lamplight <: System end

"Rebuild when the look changes or a lantern or the cottage moves or turns."
lamp_key(game) = (LAMP_VERSION, [(a.pos, a.yaw) for a in game.world.actors if a isa NG.AssetActor])

"The lanterns and the cottage among the placed assets: (position, yaw, scale, kind)."
function light_sources(game)
    cat = NG.load_catalog(NG.world_paths())
    prompt(id) = (i = findfirst(e -> e["id"] == id, cat); i === nothing ? "" : lowercase(get(cat[i], "prompt", "")))
    out = Tuple{Point3f,Float32,Float32,Symbol}[]
    for a in game.world.actors
        a isa NG.AssetActor || continue
        p = prompt(a.asset)
        kind = occursin("lantern", p) ? :lantern : occursin("cottage", p) ? :cottage : :none
        kind === :none || push!(out, (a.pos, a.yaw, a.scale, kind))
    end
    return out
end

"A disc lying on the terrain round `c`, warm in the middle and fading to nothing at radius `r`."
function pool!(pts, cols, faces, is, c, r, strength; falloff = 1.6f0)
    nr, na = 9, 36
    base = length(pts)
    for i in 0:nr, j in 0:(na - 1)
        rr = r * i / nr
        a = 2pi * j / na
        x = c[1] + rr * cos(a); y = c[2] + rr * sin(a)
        push!(pts, Point3f(x, y, NG.terrain_height(is, x, y) + 0.05f0))
        f = 1 - i / nr
        push!(cols, RGBAf(WARM..., strength * f^falloff))
    end
    idx(i, j) = base + i * na + mod(j, na) + 1
    for i in 0:(nr - 1), j in 0:(na - 1)
        push!(faces, GLTriangleFace(idx(i, j), idx(i + 1, j), idx(i + 1, j + 1)))
        push!(faces, GLTriangleFace(idx(i, j), idx(i + 1, j + 1), idx(i, j + 1)))
    end
end

function build_lamps!(game)
    # none in a quiet copy: the tracer ignores the shells' alpha and drew each halo as a solid yellow disc the size of a
    # critter (dance take 4, s42); the flames' Emission lights the ground there for real
    HALO_N[] = game.dash === nothing ? 0 : HALO_SHELLS
    for k in (:pools, :flames, :windows, :halos)
        haskey(Main.LAMPLIGHT, k) && delete!(Main.LAMPLIGHT[k].parent, Main.LAMPLIGHT[k])
    end
    is = game.world.island
    pts = Point3f[]; cols = RGBAf[]; faces = GLTriangleFace[]
    fpos = Point3f[]; fsize = Vec3f[]
    wpos = Point3f[]; wsize = Vec3f[]; wrot = Makie.Quaternionf[]; wcol = RGBf[]
    hpos = Point3f[]; hsize = Vec3f[]; hcol = RGBAf[]
    for (pos, yaw, s, kind) in light_sources(game)
        if kind === :lantern
            # the lantern mesh is ~1 m tall, its light box at ~0.62 m, a bit off the origin
            off = Point3f(0.14f0 * s * cos(yaw) - 0.14f0 * s * sin(yaw), 0.14f0 * s * sin(yaw) + 0.14f0 * s * cos(yaw), 0.6f0 * s)
            push!(fpos, pos + off); push!(fsize, Vec3f(0.11f0 * s))
            halo!(hpos, hsize, hcol, pos + off, 0.13f0 * s, 0.6f0 * s)
            pool!(pts, cols, faces, is, pos + off, 4.0f0 * s, 0.8f0)
        else
            pool!(pts, cols, faces, is, pos, 2.0f0 * s, 0.75f0; falloff = 0.8f0)   # door side unknown: all round
            q0 = NG.rot_z(yaw)
            lamp = pos + q0 * (DOOR_LAMP * s)
            push!(fpos, lamp); push!(fsize, Vec3f(0.035f0 * s))
            halo!(hpos, hsize, hcol, lamp, 0.04f0 * s, 0.2f0 * s)
            pool!(pts, cols, faces, is, pos + q0 * (Point3f(-0.24, -0.75, 0) * s), 1.0f0 * s, 0.6f0)   # warm light on the doorstep
            for (c, n) in COTTAGE_WINDOWS     # lit windows: a warm pane just outside the glass
                q = NG.rot_z(yaw)
                push!(wpos, pos + q * ((c + 0.012f0 * n) * s)); push!(wsize, Vec3f(0.068f0, 0.008f0, 0.055f0) * s); push!(wrot, q); push!(wcol, WINDOW)
                halo!(hpos, hsize, hcol, pos + q * ((c + 0.09f0 * n) * s), 0.05f0 * s, 0.24f0 * s)
                # the window's wooden cross in front of the light
                for bar in (Vec3f(0.068f0, 0.01f0, 0.007f0), Vec3f(0.007f0, 0.01f0, 0.055f0))
                    push!(wpos, pos + q * ((c + 0.02f0 * n) * s)); push!(wsize, bar * s); push!(wrot, q); push!(wcol, RGBf(0.28, 0.15, 0.07))
                end
            end
        end
    end
    sc = game.stage.scene
    m = GeometryBasics.Mesh(pts, faces)
    Main.LAMPLIGHT[:pools] = mesh!(sc, m; color = cols, shading = Makie.NoShading, transparency = true,
        visible = false, name = :lamplight_pools)
    isempty(fpos) && (push!(fpos, Point3f(0, 0, -50)); push!(fsize, Vec3f(0.01)))   # the raster cannot draw an empty meshscatter
    Main.LAMPLIGHT[:flames] = meshscatter!(sc, fpos; marker = NG.shape(:glowdot), markersize = fsize, color = FLAME,
        shading = Makie.NoShading, material = NG.Hikari.Emission(color = (1.0, 0.8, 0.45), strength = 6.0),
        visible = false, name = :lamplight_flames)
    isempty(wpos) && (push!(wpos, Point3f(0, 0, -50)); push!(wsize, Vec3f(0.01)); push!(wrot, Makie.Quaternionf(0, 0, 0, 1)); push!(wcol, WINDOW))
    Main.LAMPLIGHT[:windows] = meshscatter!(sc, wpos; marker = NG.shape(:glowball), markersize = wsize, rotation = wrot, color = wcol,
        shading = Makie.NoShading, material = NG.Hikari.Emission(color = (1.0, 0.78, 0.38), strength = 5.0),
        visible = false, name = :lamplight_windows)
    isempty(hpos) && (push!(hpos, Point3f(0, 0, -50)); push!(hsize, Vec3f(0.01)); push!(hcol, RGBAf(1, 1, 1, 0)))
    Main.LAMPLIGHT[:halos] = meshscatter!(sc, hpos; marker = NG.shape(:glowball), markersize = hsize, color = hcol,
        shading = Makie.NoShading, transparency = true, material = NG.Hikari.Emission(color = (1.0, 0.72, 0.36), strength = 0.4),
        visible = false, name = :lamplight_halos)
    Main.LAMPLIGHT[:key] = lamp_key(game)
end

function NG.start!(::Lamplight, game)
    game.stage === nothing && return
    build_lamps!(game)
    return
end

function NG.step!(::Lamplight, game, dt)
    game.stage === nothing && return
    get(Main.LAMPLIGHT, :key, nothing) == lamp_key(game) || build_lamps!(game)
    # lit from the golden hour on (sun under ~19 degrees), not only deep in the night: at 18:36 the live island was a
    # flat blue-grey evening with every lamp still dark (review s107)
    on = NG.night_factor(game.world) > 0.3f0 || NG.sun(game.world)[1][3] < 0.33f0 || get(Main.LAMPLIGHT, :force, false)
    for k in (:pools, :flames, :windows, :halos)
        p = Main.LAMPLIGHT[k]
        p.visible[] == on || (p.visible[] = on)
    end
    return
end

function NG.stop!(::Lamplight, game)
    for k in (:pools, :flames, :windows, :halos)
        haskey(Main.LAMPLIGHT, k) && (Main.LAMPLIGHT[k].visible[] = false)
    end
end

register!(Lamplight())
