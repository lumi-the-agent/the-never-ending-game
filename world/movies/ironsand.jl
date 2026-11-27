# Iron sand over a buried magnet stone (s149): black grains sprinkled on the beach, tapped, stand into the field of
# a stone hidden under the sand. Every grain position and direction is physics/ironsand.jl's (the stone's field from
# physics/em.jl plus every neighbour grain's dipole), one state per tap; between two states a grain hops the tap's
# flight. Nothing here places a grain.
using NeverendingGame, GeometryBasics, Makie, LinearAlgebra
const NG = NeverendingGame
Base.include(@__MODULE__, joinpath(@__DIR__, "..", "physics", "em.jl"))
Base.include(@__MODULE__, joinpath(@__DIR__, "..", "physics", "ironsand.jl"))

# the rotation that turns +z onto the unit vector d (d[3] >= 0 here)
function zto(d)
    x, y, z, w = -d[2], d[1], 0.0, 1.0 + d[3]
    n = sqrt(x^2 + y^2 + z^2 + w^2)
    Makie.Quaternionf(Float32(x / n), Float32(y / n), Float32(z / n), Float32(w / n))
end

"""States of the sand after 0..ntaps taps over a stone `depth` m down, its pole axis turned `yaw` about the vertical
(standing = true: north up)."""
function ironsand_states(; depth = 0.07, yaw = 0.5, standing = false, ntaps = 8, N = 3000, w = 0.42, seed = 11)
    IS = IronSand
    Rz = [cos(yaw) -sin(yaw) 0; sin(yaw) cos(yaw) 0; 0 0 1]
    Ry = [0.0 0 -1; 0 1 0; 1 0 0]                     # body x (the pole axis) turned to +z
    R = standing ? Rz * Ry : Rz
    S = IS.Sand([IS.stone(0.03, -0.02, depth; R)]; N, w, seed)
    # as sprinkled: every grain lies flat, any way round
    s = UInt32(seed + 99); rnd() = (s = s * UInt32(1664525) + UInt32(1013904223); s / typemax(UInt32))
    flat = [(cos(t), sin(t), 0.0) for t in (2pi * rnd() for _ in 1:N)]
    states = [(copy(S.pos), flat)]
    for _ in 1:ntaps
        IS.tap!(S)
        push!(states, (copy(S.pos), copy(S.dir)))
    end
    states, S
end

"""The film's setup(game) and shot(game, rig, t), apart so the sandbox can take them for a look."""
function ironsand_parts(; hold = 1.6, every = 0.85, flight = 0.14, spot = (-2.4f0, 18.8f0),
                        depth = 0.07, yaw = 0.5, standing = false, ntaps = 8, cam = (0.0f0, -0.36f0, 0.30f0))
    states, Sand = ironsand_states(; depth, yaw, standing, ntaps)
    N = length(states[1][1]); a = Float32(Sand.g.a)
    S = Dict{Symbol,Any}()
    setup = function (gm)
        for p in gm.stage.scene.plots
            haskey(p.attributes, :name) && p.attributes[:name][] in (:rain, :rainrings, :raincloud, :paperme, :paperme_card, :dayfall_tiles, :jelly_coat) && (p.visible[] = false)
        end
        isdefined(Main, :SHOWERS) && (Main.SHOWERS[:off] = true)
        w = gm.world
        g = NG.ground(w.island, spot)
        S[:C] = Point3f(g[1], g[2], g[3])
        S[:gz] = [Float32(NG.ground(w.island, (spot[1] + Float32(p[1]), spot[2] + Float32(p[2])))[3]) for st in states for p in st[1]]
        marker = GeometryBasics.normal_mesh(Cylinder(Point3f(0, 0, -2.6a), Point3f(0, 0, 2.6a), a))
        S[:plot] = meshscatter!(gm.stage.scene, fill(S[:C], N); marker, markersize = 1f0,
                                rotation = fill(Makie.Quaternionf(0, 0, 0, 1), N), color = RGBf(0.07, 0.07, 0.08),
                                material = NG.Hikari.Diffuse(color = (0.07, 0.07, 0.08), roughness = 0.45f0), name = :ironsand)
        for c in w.creatures
            hypot(c.pos[1] - spot[1], c.pos[2] - spot[2]) < 5 && (c.pos = NG.ground(w.island, (spot[1] + 12f0, spot[2] - 10f0)); c.goal = NG.Goal())
            c.name == "Lumi" && (c.controlled = true)
        end
    end
    shot = function (gm, rig, t)
        for p in gm.stage.scene.plots
            haskey(p.attributes, :name) && (p.attributes[:name][] in (:autumn_fall, :autumn_pile, :tops_live_board, :tops_live_top, :magnetstone_spikes) || startswith(string(p.attributes[:name][]), "paperpage_")) && (p.visible[] = false)
        end
        C = S[:C]
        # which tap we are in, and how far through its flight
        u = (t - hold) / every
        k = clamp(floor(Int, u), 0, ntaps - 1) + 1          # flying from state k to state k + 1
        s = u < 0 ? 0.0 : u >= ntaps ? 1.0 : clamp((u - floor(u)) * every / flight, 0.0, 1.0)
        u < 0 && (k = 1)
        (p0, d0) = states[k]; (p1, d1) = states[k+1]
        hop = Float32(0.004 * 4 * s * (1 - s))              # a tap throws the grains ~4 mm
        gz0 = view(S[:gz], (k - 1) * N + 1:k * N); gz1 = view(S[:gz], k * N + 1:(k + 1) * N)
        pos = Vector{Point3f}(undef, N); rot = Vector{Makie.Quaternionf}(undef, N)
        for i in 1:N
            x = (1 - s) * p0[i][1] + s * p1[i][1]; y = (1 - s) * p0[i][2] + s * p1[i][2]
            d = normalize([(1 - s) * d0[i][1] + s * d1[i][1], (1 - s) * d0[i][2] + s * d1[i][2], (1 - s) * d0[i][3] + s * d1[i][3]] .+ 1e-9)
            lift = Float32(2.6a * d[3])                     # a standing grain's centre is half its length up
            pos[i] = Point3f(C[1] + x, C[2] + y, (1 - s) * gz0[i] + s * gz1[i] + a + lift + hop)
            rot[i] = zto(d)
        end
        Makie.update!(S[:plot]; arg1 = pos, rotation = rot)
        rig.mode = :fixed
        rig.target = C + Point3f(0, 0, 0.01f0)
        rig.eye = C + Point3f(cam...)
        return nothing
    end
    setup, shot
end

function ironsand_clip(path; rasterize = false, samples = 24, width = 960, height = 540, fps = 24, seconds = 10.0,
                       hour = 15.8, depth = 0.07, yaw = 0.5, standing = false, ntaps = 8, kw...)
    setup, shot = ironsand_parts(; depth, yaw, standing, ntaps, kw...)
    res = NG.game_clip(path; size = (width, height), seconds, fps, samples, hour, warmup = 0.3, rasterize,
                       rig = NG.CameraRig(; mode = :fixed), setup, shot, fade = 0.3)
    return merge(res, (; path, depth, yaw, standing, ntaps))
end
