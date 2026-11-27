# Knock on anything (s138): Lumi knocks the stone lantern three times and it sways in the shape of each note it sings.
# The shapes and pitches are physics/modes.jl's (FinEtools hex FEM of the lantern's own voxels, Arpack). The motion
# is slowed 100x and exaggerated so an eye can follow it; the sound is muxed in at true pitch, one knock per sway.
#   submit_job(:clip; path, script = "movies/knock.jl", call = "knock_clip", kwargs = Dict(...))
using NeverendingGame, Makie, GeometryBasics, Serialization, LinearAlgebra
const NG = NeverendingGame
Base.include(@__MODULE__, joinpath(@__DIR__, "..", "physics", "modes.jl"))

const LANTERN_ID = "20261122-195434-518-asset"

"Per mesh vertex, the FE node it follows (nearest node on the voxel grid)."
function follow_nodes(model_pos, m::Modes.ModeSet, voxel, lo, sc)
    key(x, y, z) = (round(Int, x / voxel), round(Int, y / voxel), round(Int, z / voxel))
    grid = Dict(key(m.xyz[q, 1], m.xyz[q, 2], m.xyz[q, 3]) => q for q in 1:size(m.xyz, 1))
    nodes = Vector{Int}(undef, length(model_pos))
    for (i, p) in enumerate(model_pos)
        x, y, z = (p[1] - lo[1]) * sc, (p[2] - lo[2]) * sc, p[3] * sc
        k = key(x, y, z)
        q = get(grid, k, 0)
        if q == 0           # outside the solid voxels: nearest node
            q = argmin([(m.xyz[r, 1] - x)^2 + (m.xyz[r, 2] - y)^2 + (m.xyz[r, 3] - z)^2 for r in 1:size(m.xyz, 1)])
            grid[k] = q
        end
        nodes[i] = q
    end
    return nodes
end

function knock_clip(path; rasterize = false, samples = 20, width = 960, height = 540, fps = 24, seconds = 7.5,
                    hour = 16.4, spot = (4f0, -14f0), knocks = (0.9, 3.1, 5.3), modes = (1, 2, 3), slow = 100.0,
                    amp = 0.13, tau = 1.1, size_m = 1.6)
    mesh = deserialize(joinpath(@__DIR__, "..", "assets", LANTERN_ID, "mesh.jls"))
    ms, fe = Modes.solve(mesh; height = size_m, n = 16, E = 30e9, rho = 2500.0)
    pts = coordinates(mesh.mesh)
    lo = Vec3f(minimum(p[1] for p in pts), minimum(p[2] for p in pts), minimum(p[3] for p in pts))
    S = Dict{Symbol,Any}()
    setup = function (g)
        for p in g.stage.scene.plots
            haskey(p.attributes, :name) && p.attributes[:name][] in (:rain, :rainrings, :raincloud, :paperme, :paperme_card, :dayfall_tiles, :jelly_coat) && (p.visible[] = false)
        end
        isdefined(Main, :SHOWERS) && (Main.SHOWERS[:off] = true)
        w = g.world
        model = NG.load_asset(g.paths, LANTERN_ID)
        base = NG.ground(w.island, spot)
        sc = Float32(ms.scale)
        rest = [Point3f(sc * p[1], sc * p[2], sc * p[3]) + Vec3f(base[1], base[2], base[3] - 0.02f0) for p in coordinates(model.mesh)]
        nodes = follow_nodes(coordinates(model.mesh), ms, fe.voxel, lo, sc)
        # each mode scaled so its largest node swing is 1 m (times amp)
        U = [begin
                 φ = reshape(ms.shapes[:, k], 3, :)
                 φ ./= maximum(sqrt.(sum(abs2, φ; dims = 1)))
                 [Vec3f(φ[1, q], φ[2, q], φ[3, q]) for q in nodes]
             end for k in modes]
        obs = Observable(GeometryBasics.Mesh(copy(rest), faces(model.mesh); normal = model.mesh.normal, uv = model.mesh.uv))
        mesh!(g.stage.scene, obs; color = model.color, material = model.material, name = :knock_lantern)
        S[:obs] = obs; S[:rest] = rest; S[:U] = U; S[:faces] = faces(model.mesh); S[:base] = base; S[:m] = model.mesh
        me = NG.creature(w, "Lumi")
        me.pos = NG.ground(w.island, (spot[1] + 0.95f0, spot[2] + 0.15f0)); me.controlled = true; me.goal = NG.Goal(); me.action = :idle
        me.yaw = Float32(atan(-0.15f0, -0.95f0)) - NG.species_of(me).heading
        for c in w.creatures
            c === me && continue
            hypot(c.pos[1] - spot[1], c.pos[2] - spot[2]) < 10 && (c.pos = NG.ground(w.island, (spot[1] + 14f0, spot[2] - 9f0)); c.goal = NG.Goal())
        end
    end
    shot = function (g, rig, t)
        w = g.world; me = NG.creature(w, "Lumi"); me.controlled = true
        d = zeros(Vec3f, length(S[:rest]))
        for (j, t0) in enumerate(knocks)
            t < t0 && continue
            k = modes[j]; s = t - t0
            a = Float32(amp * cos(2π * ms.freqs[k] / slow * s) * exp(-s / tau))
            d .+= a .* S[:U][j]
        end
        # the wing swings in just before each knock
        me.action = any(t0 -> 0 <= t0 - t < 0.25, knocks) ? :wave : :idle
        S[:obs][] = GeometryBasics.Mesh(S[:rest] .+ d, S[:faces]; normal = S[:m].normal, uv = S[:m].uv)
        b = S[:base]
        rig.mode = :fixed
        rig.eye = Point3f(b[1] - 0.75f0, b[2] - 3.5f0, b[3] + 1.1f0)
        rig.target = Point3f(b[1] + 0.35f0, b[2], b[3] + 0.8f0)
        return nothing
    end
    r = NG.game_clip(path * ".silent.mp4"; size = (width, height), seconds, fps, samples, hour, warmup = 0.3, rasterize,
                     rig = NG.CameraRig(; mode = :fixed), setup, shot, fade = 0.3)
    # the knocks at true pitch, each where its sway starts
    sr = 44100; y = zeros(round(Int, seconds * sr))
    for (j, t0) in enumerate(knocks)
        top = maximum(ms.xyz[:, 3])
        q = argmax([abs(ms.xyz[i, 3] - 0.75top) < 0.07 ? abs(ms.xyz[i, 1]) + abs(ms.xyz[i, 2]) : -1.0 for i in 1:size(ms.xyz, 1)])
        dir = reshape(ms.shapes[:, modes[j]], 3, :)[:, q]
        z = Modes.knock(ms, ms.xyz[q, :], dir ./ max(norm(dir), 1e-12); seconds = 1.6)
        i0 = round(Int, t0 * sr) + 1
        n = min(length(z), length(y) - i0 + 1)
        y[i0:i0+n-1] .+= 0.8 .* z[1:n]
    end
    wav = Modes.write_wav(path * ".wav", y ./ max(1.0, maximum(abs, y)))
    run(`ffmpeg -loglevel error -y -i $(path * ".silent.mp4") -i $wav -c:v copy -c:a aac -b:a 128k -shortest $path`)
    rm(path * ".silent.mp4"); rm(wav)
    return merge(r, (; path, freqs = ms.freqs[collect(modes)]))
end
