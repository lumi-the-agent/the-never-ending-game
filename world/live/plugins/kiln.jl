# The first fired jug (s141, project pottery). A 14 cm jug stands on the meadow at (4, -16.5), by the chip stone:
# lines cut in its clay, dipped in a celadon glaze, fired. Its colour is not painted: physics/glaze.jl flows the
# molten glaze over the cut body (surface tension fills the cuts, gravity drains it, it breaks thin off the
# pinched ring) on a thread when the game starts (~20 s on the CPU, never in the frame), and the colour of every
# point is Beer-Lambert through the thickness it ended with, under a clear glass coat in the path tracer.
# Next: the wheel where you shape and cut your own, and the kiln you fire it in.
using GeometryBasics, Makie, LinearAlgebra
isdefined(Main, :KILN) || Core.eval(Main, :(const KILN = Dict{Symbol,Any}()))
const NG = NeverendingGame
const KLN = Main.KILN
Base.include(@__MODULE__, joinpath(@__DIR__, "..", "physics", "jug.jl"))

const KILN_SPOT = (4f0, -16.5f0)
KLN[:scene] = nothing        # a reload draws the jug again (new mesh or colours), the firing is kept

struct KilnJug <: System end

function kiln_drop_plots!(scene)
    for p in copy(scene.plots)
        haskey(p.attributes, :name) && p.attributes[:name][] === :kiln_jug && delete!(scene, p)
    end
end

function NG.step!(::KilnJug, game, dt)
    scene = game.stage.scene
    if get(KLN, :scene, nothing) !== scene          # first frame, or the stage was rebuilt
        kiln_drop_plots!(scene)
        KLN[:scene] = scene; KLN[:plotted] = false
        haskey(KLN, :fired) || haskey(KLN, :task) || (KLN[:task] = Threads.@spawn fire_jug())
    end
    t = get(KLN, :task, nothing)
    if t !== nothing && istaskdone(t)
        KLN[:fired] = fetch(t)                       # a failed firing throws here: the plugin error shows it
        delete!(KLN, :task)
    end
    if !KLN[:plotted] && haskey(KLN, :fired)
        b, h = coarsen(KLN[:fired]..., 3, 2)         # 233 x 145 points: the cut lines (1.6 mm) still show
        base = NG.ground(game.world.island, KILN_SPOT)
        m, cols = jug_mesh(b, h, Point3f(base[1], base[2], base[3] - 0.002f0); dz = 2 * JL)
        mesh!(scene, m; color = cols, name = :kiln_jug,
              material = NG.Hikari.CoatedDiffuse(roughness = 0.03, ior = 1.52, thickness = 0.0004))
        KLN[:plotted] = true
        NG.emit!(game.world, :jug_fired; glaze_mm = (minimum(h[:, 7:end]) * 1e3, maximum(h) * 1e3))
    end
    return
end

register!(KilnJug())
