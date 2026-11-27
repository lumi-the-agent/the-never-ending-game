# Chip a stone until it sings (s139, project knock-anything): a flat beach stone lies on two sticks; Lumi knocks it,
# chips a flake off the middle of its top, knocks again. Every chip removes real voxels and the stone's modes are
# solved again (physics/modes.jl, free-free, FinEtools hex FEM + Arpack, checked against beam theory): thinning the
# middle drops the note, the way marimba bars are tuned. The sound is muxed in at true pitch.
#   submit_job(:clip; path, script = "movies/chipstone.jl", call = "chip_clip", kwargs = Dict(...))
using NeverendingGame, Makie, GeometryBasics, LinearAlgebra, Random
const NG = NeverendingGame
Base.include(@__MODULE__, joinpath(@__DIR__, "..", "physics", "modes.jl"))

const H = 0.0075        # voxel size, metres

"A rounded flat stone, thinner towards its rim (voxels, 1 = stone)."
function stone_img(; L = 0.42, W = 0.11, T = 0.045)
    nx, ny, nz = ceil(Int, L / H), ceil(Int, W / H), ceil(Int, T / H)
    img = zeros(Int, nx, ny, nz)
    for I in CartesianIndices(img)
        x, y, z = (Tuple(I) .- 0.5) .* H .- (L / 2, W / 2, 0.0)
        r = abs(2x / L)^3.5 + abs(2y / W)^2.5
        r < 1 || continue
        z < T * (1 - 0.55r) && (img[I] = 1)
    end
    return img
end

"Chip `k`: the top layer over a middle patch that widens each time (never the bottom two layers). Returns the cells taken."
function chip!(img, k)
    nx, ny, _ = size(img); c = (nx + 1) / 2
    gone = CartesianIndex{3}[]
    for i in 1:nx, j in 1:ny
        abs(i - c) <= 2 + 2k || continue
        ks = findlast(==(1), view(img, i, j, :))
        (ks === nothing || ks <= 2) && continue
        img[i, j, ks] = 0; push!(gone, CartesianIndex(i, j, ks))
    end
    return gone
end

"The voxels' outer faces as a mesh (shared corners), smoothed a little so the stone is a pebble, not bricks."
function voxel_mesh(img, origin::Point3f; smooth = 3)
    R = CartesianIndices(img)
    idx = Dict{NTuple{3,Int},Int}(); pos = Point3f[]; tris = GLTriangleFace[]
    vid(c) = get!(idx, c) do
        push!(pos, origin + Point3f(c[1] * H, c[2] * H, c[3] * H)); length(pos)
    end
    quads = ((CartesianIndex(1, 0, 0), ((1, 0, 0), (1, 1, 0), (1, 1, 1), (1, 0, 1))),
             (CartesianIndex(-1, 0, 0), ((0, 0, 0), (0, 0, 1), (0, 1, 1), (0, 1, 0))),
             (CartesianIndex(0, 1, 0), ((0, 1, 0), (0, 1, 1), (1, 1, 1), (1, 1, 0))),
             (CartesianIndex(0, -1, 0), ((0, 0, 0), (1, 0, 0), (1, 0, 1), (0, 0, 1))),
             (CartesianIndex(0, 0, 1), ((0, 0, 1), (1, 0, 1), (1, 1, 1), (0, 1, 1))),
             (CartesianIndex(0, 0, -1), ((0, 0, 0), (0, 1, 0), (1, 1, 0), (1, 0, 0))))
    for c in R
        img[c] == 1 || continue
        for (d, cs) in quads
            q = c + d
            (q in R && img[q] == 1) && continue
            v = [vid((c[1] - 1 + o[1], c[2] - 1 + o[2], c[3] - 1 + o[3])) for o in cs]
            push!(tris, GLTriangleFace(v[1], v[2], v[3]), GLTriangleFace(v[1], v[3], v[4]))
        end
    end
    nb = [Int[] for _ in pos]
    for f in tris, a in 1:3, b in 1:3
        a != b && push!(nb[f[a]], f[b])
    end
    for _ in 1:smooth
        pos = [Point3f(sum(pos[j] for j in nb[i]) / length(nb[i])) * 0.5f0 + pos[i] * 0.5f0 for i in eachindex(pos)]
    end
    return GeometryBasics.Mesh(pos, tris; normal = vertex_normals(pos, tris))
end

function vertex_normals(pos, tris)
    n = zeros(Vec3f, length(pos))
    for f in tris
        a, b, c = pos[f[1]], pos[f[2]], pos[f[3]]
        fn = cross(b - a, c - a)
        n[f[1]] += fn; n[f[2]] += fn; n[f[3]] += fn
    end
    return [x / max(norm(x), 1f-12) for x in n]
end

"Top-middle node of a mode set (where Lumi knocks)."
function knock_node(m)
    cx = (maximum(m.xyz[:, 1]) + minimum(m.xyz[:, 1])) / 2; cy = (maximum(m.xyz[:, 2]) + minimum(m.xyz[:, 2])) / 2
    best = 0; bz = -Inf
    for q in 1:size(m.xyz, 1)
        abs(m.xyz[q, 1] - cx) < 1.5H && abs(m.xyz[q, 2] - cy) < 1.5H && m.xyz[q, 3] > bz && (best = q; bz = m.xyz[q, 3])
    end
    return best
end

function chip_clip(path; rasterize = false, samples = 16, width = 960, height = 540, fps = 24, seconds = 8.0,
                   hour = 16.4, spot = (4f0, -14f0), chips_at = (1.4, 3.0, 4.6, 6.2), knock_after = 0.5, first_knock = 0.4,
                   E = 50e9, rho = 2700.0)
    img = stone_img()
    seq = [copy(img)]; gone = Vector{Vector{CartesianIndex{3}}}()
    for k in 1:length(chips_at)
        push!(gone, chip!(img, k)); push!(seq, copy(img))
    end
    ms = [first(Modes.solve_voxels(s, H; E, rho, nu = 0.25, nev = 10, fixed = false)) for s in seq]
    knocks = vcat(first_knock, [t + knock_after for t in chips_at])
    nx, ny, nz = size(img)
    S = Dict{Symbol,Any}()
    setup = function (g)
        for p in g.stage.scene.plots
            haskey(p.attributes, :name) && p.attributes[:name][] in (:rain, :rainrings, :raincloud, :paperme, :paperme_card, :dayfall_tiles, :jelly_coat) && (p.visible[] = false)
        end
        isdefined(Main, :SHOWERS) && (Main.SHOWERS[:off] = true)
        w = g.world
        base = NG.ground(w.island, spot)
        lift = 0.06f0                                   # resting on two sticks of 3 cm radius
        origin = Point3f(base[1] - nx * H / 2, base[2] - ny * H / 2, base[3] + lift - 0.004f0)
        S[:meshes] = [voxel_mesh(s, origin) for s in seq]
        obs = Observable(S[:meshes][1])
        mesh!(g.stage.scene, obs; color = RGBf(0.50, 0.49, 0.47), name = :chip_stone)
        S[:obs] = obs
        # the two sticks under the stone's nodes (0.224 L from each end)
        L = nx * H
        for sx in (-1, 1)
            x = base[1] + sx * (L / 2 - 0.224f0 * L)
            mesh!(g.stage.scene, Cylinder(Point3f(x, base[2] - 0.12f0, base[3] + 0.03f0), Point3f(x, base[2] + 0.12f0, base[3] + 0.03f0), 0.03f0);
                  color = RGBf(0.42, 0.28, 0.16), name = Symbol(:chip_stick, sx > 0 ? 1 : 2))
        end
        # the flakes: each chip's cells fly off with a kick and fall under gravity onto the grass
        rng = Xoshiro(139)
        S[:flakes] = [[(Point3f(origin + Point3f((c[1] - 0.5) * H, (c[2] - 0.5) * H, (c[3] - 0.5) * H)),
                        Vec3f(0.18f0 * randn(rng), 0.18f0 * randn(rng), 0.5f0 + 0.4f0 * rand(rng))) for c in gc[1:6:end]] for gc in gone]
        S[:flake_obs] = Observable(Point3f[Point3f(0, 0, -50)])
        meshscatter!(g.stage.scene, S[:flake_obs]; marker = Rect3f(Vec3f(-0.5), Vec3f(1)), markersize = Vec3f(0.009, 0.007, 0.004),
                     color = RGBf(0.56, 0.55, 0.52), name = :chip_flakes)
        S[:base] = base; S[:k] = 0
        S[:top] = Point3f(base[1], base[2], base[3] + lift + 0.045f0)
        S[:peb] = Observable(Point3f(base[1] + 0.05f0, base[2] - 0.02f0, base[3] + lift + 0.25f0))
        meshscatter!(g.stage.scene, map(p -> [p], S[:peb]); marker = Sphere(Point3f(0), 1f0), markersize = Vec3f(0.028, 0.022, 0.018),
                     color = RGBf(0.30, 0.29, 0.28), name = :chip_pebble)
        me = NG.creature(w, "Lumi")
        me.pos = NG.ground(w.island, (spot[1] + 0.25f0, spot[2] + 0.75f0)); me.controlled = true; me.goal = NG.Goal(); me.action = :idle
        me.yaw = Float32(atan(-0.75f0, -0.25f0)) - NG.species_of(me).heading
        for c in w.creatures
            c === me && continue
            hypot(c.pos[1] - spot[1], c.pos[2] - spot[2]) < 10 && (c.pos = NG.ground(w.island, (spot[1] + 14f0, spot[2] - 9f0)); c.goal = NG.Goal())
        end
    end
    shot = function (g, rig, t)
        w = g.world; me = NG.creature(w, "Lumi"); me.controlled = true
        for p in g.stage.scene.plots      # the autumn plugin makes its leaves after setup: hide them every frame
            haskey(p.attributes, :name) && (p.attributes[:name][] in (:autumn_fall, :autumn_pile) || startswith(string(p.attributes[:name][]), "paperpage_")) && (p.visible[] = false)
        end
        k = count(<=(t), chips_at)
        if k != S[:k]
            S[:k] = k; S[:obs][] = S[:meshes][k+1]
        end
        b = S[:base]
        pts = Point3f[Point3f(0, 0, -50)]
        for (j, t0) in enumerate(chips_at)
            t < t0 && continue
            s = Float32(t - t0)
            for (p0, v) in S[:flakes][j]
                p = p0 + v * s + Vec3f(0, 0, -4.905f0 * s^2)
                p = Point3f(p[1], p[2], max(p[3], b[3] + 0.003f0))
                if p[3] <= b[3] + 0.003f0     # landed: stays where it hit the grass
                    tl = (v[3] + sqrt(v[3]^2 + 2 * 9.81f0 * max(p0[3] - b[3], 0f0))) / 9.81f0
                    p = Point3f(p0[1] + v[1] * tl, p0[2] + v[2] * tl, b[3] + 0.003f0)
                end
                push!(pts, p)
            end
        end
        S[:flake_obs][] = pts
        # the pebble: lifted 20 cm, it falls onto the stone's middle at each chip and knock (free fall from 20 cm: 0.2 s)
        hits = sort(vcat(knocks, collect(chips_at)))
        z = 0.20f0
        for th in hits
            if th - 0.2 <= t < th
                z = 0.20f0 - 4.905f0 * Float32(t - (th - 0.2))^2
            elseif th <= t < th + 0.45
                z = 0.20f0 * Float32((t - th) / 0.45)
            end
        end
        tp = S[:top]
        S[:peb][] = Point3f(tp[1] + 0.01f0, tp[2] - 0.01f0, tp[3] + 0.018f0 + max(z, 0f0))
        me.action = any(t0 -> 0 <= t0 - t < 0.25, vcat(knocks, collect(chips_at))) ? :wave : :idle
        rig.mode = :fixed
        rig.eye = Point3f(b[1] + 0.12f0, b[2] - 0.58f0, b[3] + 0.42f0)
        rig.target = Point3f(b[1] + 0.02f0, b[2] + 0.06f0, b[3] + 0.10f0)
        return nothing
    end
    r = NG.game_clip(path * ".silent.mp4"; size = (width, height), seconds, fps, samples, hour, warmup = 0.3, rasterize,
                     rig = NG.CameraRig(; mode = :fixed), setup, shot, fade = 0.3)
    sr = 44100; y = zeros(round(Int, seconds * sr)); rng = Xoshiro(7)
    for (j, t0) in enumerate(knocks)
        m = ms[j]; q = knock_node(m)
        z = Modes.knock(m, m.xyz[q, :], [0.0, 0.0, -1.0]; seconds = 1.2)
        i0 = round(Int, t0 * sr) + 1; n = min(length(z), length(y) - i0 + 1)
        y[i0:i0+n-1] .+= 0.8 .* z[1:n]
    end
    for t0 in chips_at              # the chip itself: a short crack
        i0 = round(Int, t0 * sr) + 1; n = round(Int, 0.02sr)
        y[i0:i0+n-1] .+= 0.35 .* randn(rng, n) .* exp.(-(0:n-1) ./ (0.004sr))
    end
    wav = Modes.write_wav(path * ".wav", y ./ max(1.0, maximum(abs, y)))
    run(`ffmpeg -loglevel error -y -i $(path * ".silent.mp4") -i $wav -c:v copy -c:a aac -b:a 128k -shortest $path`)
    rm(path * ".silent.mp4"); rm(wav)
    return merge(r, (; path, freqs = [m.freqs[7] for m in ms]))
end
