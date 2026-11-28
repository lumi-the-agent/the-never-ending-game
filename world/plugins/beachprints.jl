# Tracks that stay (s160, wish 'A road the friends and I laid ourselves', project cart): a 3 x 3 m patch of loose
# beach sand (physics/sandfield.jl) on the dune. Every creature that walks over it presses a footprint by Bekker's law
# for its weight (dry sand, physics/wheelsand.jl): the packed sand stays down, the rest is pushed into a rim, and the rim
# slides back to the sand's 33 deg angle of repose. The prints stay until someone treads them out.
using GeometryBasics, Makie
isdefined(Main, :BEACHPRINTS) || Core.eval(Main, :(const BEACHPRINTS = Dict{Symbol,Any}()))
const NG = NeverendingGame
const BP = Main.BEACHPRINTS
Base.include(@__MODULE__, joinpath(@__DIR__, "..", "physics", "wheelsand.jl"))
Base.include(@__MODULE__, joinpath(@__DIR__, "..", "physics", "sandfield.jl"))

const BP_N = 150                 # cells a side
const BP_DX = 0.02               # m
const BP_LIFT = 0.012            # the loose layer above the terrain
const BP_FOOT = (0.13, 0.09)     # footprint, m (long, wide)
const BP_MASS = 150.0            # kg, a pony-sized friend (todo #745: real masses), on two feet at a step

struct BeachPrints <: System end

function bp_spot()
    a = isdefined(Main, :BEACH) ? get(Main.BEACH, :anchor, nothing) : nothing   # the first dune grass spot (beach.jl)
    a === nothing && return nothing
    a + Point2f(1.6f0, 0f0)
end

function bp_points!(pts, f, isl, o)
    h = Array(f.h); nx, ny = size(h); fade = 0.15
    k = 0
    for j in 1:ny, i in 1:nx
        k += 1
        x = o[1] + (i - 0.5f0) * f.dx; y = o[2] + (j - 0.5f0) * f.dx
        e = min(i - 0.5, nx - i + 0.5, j - 0.5, ny - j + 0.5) * f.dx
        w = Float32(clamp(e / fade, 0, 1))
        g = BP[:ground][k]
        pts[k] = Point3f(x, y, g + w * (BP_LIFT + h[i, j]) - (1 - w) * 0.01f0)
    end
    pts
end

function bp_ensure!(game)
    haskey(BP, :plot) && BP[:plot].parent === game.stage.scene && return true
    c = bp_spot(); c === nothing && return false
    isl = game.world.island
    o = (c[1] - BP_N * BP_DX / 2, c[2] - BP_N * BP_DX / 2)
    f = get(BP, :f, nothing)
    f isa SandField.Field || (f = SandField.Field(BP_N, BP_N, BP_DX))
    BP[:f] = f; BP[:o] = o
    BP[:ground] = [NG.ground(isl, (Float32(o[1] + (i - 0.5) * BP_DX), Float32(o[2] + (j - 0.5) * BP_DX)))[3] for j in 1:BP_N for i in 1:BP_N]
    pts = bp_points!(Vector{Point3f}(undef, BP_N^2), f, isl, o)
    fs = GLTriangleFace[]
    idx(i, j) = (j - 1) * BP_N + i
    for j in 1:BP_N-1, i in 1:BP_N-1
        push!(fs, GLTriangleFace(idx(i, j), idx(i + 1, j), idx(i + 1, j + 1)), GLTriangleFace(idx(i, j), idx(i + 1, j + 1), idx(i, j + 1)))
    end
    BP[:faces] = fs
    m = GeometryBasics.mesh(pts, fs; normal = GeometryBasics.normals(pts, fs))
    BP[:plot] = mesh!(game.stage.scene, m; color = RGBf(0.87, 0.77, 0.58), name = :beachprints_sand,
                      material = NG.Hikari.Diffuse(color = (0.87, 0.77, 0.58), roughness = 1f0))
    BP[:last] = Dict{String,Point2f}(); BP[:side] = Dict{String,Int}(); BP[:settle] = 0
    true
end

# Bekker plate sinkage for one foot carrying half the friend's weight
function bp_sink()
    s = WheelSand.SOILS[:dry_sand]; b = BP_FOOT[2]
    p = BP_MASS * 9.81 / 2 / (pi / 4 * BP_FOOT[1] * BP_FOOT[2])
    (p / (s.kc / b + s.kphi))^(1 / s.n)
end

function bp_press!(f, o, pos, yaw, side)
    nx, ny = size(f.h)
    cx = pos[1] - sin(yaw) * 0.07f0 * side; cy = pos[2] + cos(yaw) * 0.07f0 * side
    z = -Float32(bp_sink())
    U = fill(Inf32, nx, ny); h = Array(f.h)
    a, b = BP_FOOT ./ 2
    for j in 1:ny, i in 1:nx
        x = o[1] + (i - 0.5) * f.dx - cx; y = o[2] + (j - 0.5) * f.dx - cy
        u = x * cos(yaw) + y * sin(yaw); v = -x * sin(yaw) + y * cos(yaw)
        (u / a)^2 + (v / b)^2 <= 1 && (U[i, j] = min(z, h[i, j]))
    end
    any(isfinite, U) || return false
    SandField.press!(f, U; bulb = BP_FOOT[2])
    fill!(f.under, Inf32)
    true
end

function NG.step!(::BeachPrints, game, dt)
    game.stage === nothing && return
    bp_ensure!(game) || return
    f = BP[:f]; o = BP[:o]; L = BP_N * BP_DX
    changed = false
    for c in game.world.creatures
        p = Point2f(c.pos[1], c.pos[2])
        (o[1] + 0.1 < p[1] < o[1] + L - 0.1 && o[2] + 0.1 < p[2] < o[2] + L - 0.1) || continue
        last = get(BP[:last], c.name, Point2f(Inf, Inf))
        d = hypot((p .- last)...)
        d > 0.3f0 || continue
        side = get(BP[:side], c.name, 1); BP[:side][c.name] = -side
        BP[:last][c.name] = p
        pressed = bp_press!(f, o, p, Float32(c.yaw), side)
        changed |= pressed
        if pressed && d > 1.0f0                     # first print of a crossing: the island notices
            NG.emit!(game.world, :footprint; who = c.name, depth_mm = round(1000 * bp_sink(), digits = 1))
            c.name == "Lumi" && !c.controlled && NG.say!(game.world, c, rand(("Squish!", "My feet stay in the sand!", "Look, my tracks!")); duration = 2.0)
        end
    end
    # Lumi crosses its sand now and then, when nobody plays it and it isn't busy, to see its own tracks
    me = NG.creature(game.world, "Lumi")
    if me !== nothing && !me.controlled && game.world.t > get(BP, :next_walk, game.world.t + 20.0 - 1.0) &&
       !(me.goal.kind in (:sleep, :motor, :flight, :conga, :prints))
        far = rand(Bool)
        spot = NG.ground(game.world.island, (Float32(o[1] + (far ? L - 0.3 : 0.3)), Float32(o[2] + L * (0.3 + 0.4rand()))))
        me.goal = NG.Goal(:prints, spot, :idle, 1.5, 0.0, false, 0, false)
        BP[:next_walk] = game.world.t + 180.0
    end
    haskey(BP, :next_walk) || (BP[:next_walk] = game.world.t + 20.0)
    changed && (BP[:settle] = 6)
    if BP[:settle] > 0
        SandField.slump!(f, 6); BP[:settle] -= 1
        pts = bp_points!(Vector{Point3f}(undef, BP_N^2), f, game.world.island, o)
        BP[:plot][1][] = GeometryBasics.mesh(pts, BP[:faces]; normal = GeometryBasics.normals(pts, BP[:faces]))
    end
    return
end

function NG.stop!(::BeachPrints, game)
    game.stage === nothing && return
    haskey(BP, :plot) && delete!(game.stage.scene, BP[:plot])
    delete!(BP, :plot)
end

register!(BeachPrints())
