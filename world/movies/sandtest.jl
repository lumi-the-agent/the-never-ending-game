# A look test for physics/sandfield.jl (s160, todo #755): a 3 x 1.5 m patch of beach sand where a loaded cart wheel
# rolled off a plank into the soft sand: the plank's bed with dug-in ends, then the rut with berms. Drawn as a mesh
# over the terrain (fading to it at the edges) with a sand material, the plank as an oak board. For my eyes (media/),
# never a post: the question is whether 1 cm sand cells read as sand in the traced picture.
using NeverendingGame, Makie, GeometryBasics
const NG = NeverendingGame
include(joinpath(@__DIR__, "..", "physics", "wheelsand.jl")); include(joinpath(@__DIR__, "..", "physics", "sandfield.jl"))

"Run the plank and the rut into a fresh field; returns the field and the plank's last pose."
function sandtest_field(; nx = 300, ny = 150, dx = 0.01)
    s = WheelSand.SOILS[:dry_sand]
    f = SandField.Field(nx, ny, dx)
    href = Array(f.h)
    P = (; xc = 0.9, yc = 0.75, Lp = 1.0, bp = 0.2, m = 2.5)
    Wl = 3 * 200 * 9.81 / 4
    q = nothing
    for x in 0.5:0.02:1.3                    # the wheel rolls along the plank
        q = SandField.plank_rest(f, href, P, [(x, 0.75, Wl)]; soil = s, bekker = WheelSand.bekker)
        SandField.press!(f, q.under; bulb = 0.2); SandField.slump!(f, 6)
    end
    # packed sand does not spring back: the unloaded plank rests in its bed
    qrest = SandField.plank_rest(f, Array(f.h), P, Tuple{Float64,Float64,Float64}[]; soil = s, bekker = WheelSand.bekker)
    fill!(f.under, Inf32); SandField.slump!(f, 100)
    tw = WheelSand.wheel(s, Wl, 0.2, 0.05, 0.0)    # off the plank it bogs: sinks to its rim's depth
    for xc in 1.42:0.01:2.6
        U = SandField.wheel_under(f, xc, 0.75, 0.2, 0.05, -min(tw.z, 0.06))
        SandField.press!(f, U; bulb = 0.05); SandField.slump!(f, 8)
    end
    fill!(f.under, Inf32); SandField.slump!(f, 300)
    f, P, qrest
end

"The sand as a mesh at `o` (the patch's corner on the ground), sitting `lift` above the terrain, fading out at the edge."
function sand_mesh(f, island, o; lift = 0.012, fade = 0.12)
    h = Array(f.h); nx, ny = size(h); dx = f.dx
    pts = Point3f[]
    for j in 1:ny, i in 1:nx
        x = o[1] + (i - 0.5) * dx; y = o[2] + (j - 0.5) * dx
        e = min(i - 0.5, nx - i + 0.5, j - 0.5, ny - j + 0.5) * dx
        w = clamp(e / fade, 0, 1)
        g = NG.ground(island, (Float32(x), Float32(y)))[3]
        push!(pts, Point3f(x, y, g + w * (lift + h[i, j]) - (1 - w) * 0.01))
    end
    fs = GLTriangleFace[]
    idx(i, j) = (j - 1) * nx + i
    for j in 1:ny-1, i in 1:nx-1
        push!(fs, GLTriangleFace(idx(i, j), idx(i + 1, j), idx(i + 1, j + 1)))
        push!(fs, GLTriangleFace(idx(i, j), idx(i + 1, j + 1), idx(i, j + 1)))
    end
    GeometryBasics.mesh(pts, fs; normal = GeometryBasics.normals(pts, fs))
end

function sandtest(path; spot = nothing, samples = 32, size = (960, 540), hour = 16.5, rasterize = false)
    rig = NG.CameraRig(); rig.mode = :fixed
    setup = function (g)
        isl = g.world.island
        dg = isdefined(Main, :BEACH) ? get(get(Main.BEACH, :things, Dict()), :dunegrass, Point3f[]) : Point3f[]
        @info "sandtest: $(length(dg)) dune grass tufts"
        # the worker has no Main.BEACH (plugins' state lives in the live game): fall back to the first dune grass
        # tuft's place as the live game has it (s161), not (0, -30), which is in the sea and filmed from under the island
        c = spot !== nothing ? Point2f(spot...) : isempty(dg) ? Point2f(3.49f0 + 1.5f0, -15.90f0) : Point2f(dg[1][1], dg[1][2]) .+ Point2f(1.5, 0)
        o = (c[1] - 1.5f0, c[2] - 0.75f0)
        f, P, q = sandtest_field()
        sc = g.stage.scene
        mesh!(sc, sand_mesh(f, isl, o); color = RGBf(0.86, 0.76, 0.58), name = :sandtest_sand,
              material = NG.Hikari.Diffuse(color = (0.86, 0.76, 0.58), roughness = 1f0))
        pc = Point3f(o[1] + P.xc, o[2] + P.yc, NG.ground(isl, (Float32(o[1] + P.xc), Float32(o[2] + P.yc)))[3] + 0.012f0 + Float32(q.z))
        board = GeometryBasics.normal_mesh(Rect3f(Point3f(-P.Lp / 2, -P.bp / 2, 0), Vec3f(P.Lp, P.bp, 0.025)))
        p = mesh!(sc, board; color = RGBf(0.55, 0.42, 0.28), name = :sandtest_plank,
                  material = NG.Hikari.Diffuse(color = (0.55, 0.42, 0.28), roughness = 0.7f0))
        Makie.rotate!(p, Makie.qrotation(Vec3f(0, 1, 0), -deg2rad(Float32(q.pitch))))
        Makie.translate!(p, pc)
        rig.eye = Point3f(c[1] + 0.2f0, c[2] - 1.9f0, pc[3] + 0.9f0); rig.target = Point3f(c[1] + 0.1f0, c[2], pc[3] - 0.05f0)
        nothing
    end
    NG.game_clip(path; size, seconds = 0.5, fps = 4, samples, hour, warmup = 3, rig, rasterize, setup)
end
