# Chip a stone until it sings (s139, project knock-anything). A flat beach stone lies on two sticks on the meadow at
# (4, -14). Jumped in as Lumi, stand by it: R chips a flake off its top where Lumi's beak points, L knocks it. The
# stone is voxels; every chip takes real voxels away and its modes are solved again (physics/modes.jl: FinEtools hex
# FEM + Arpack, free-free, 0.5-1 s on a thread, never in the frame), so the note you hear is the stone's shape now:
# chips in the middle make it ring lower, chips at the ends higher (how marimba bars are tuned). The page plays it
# through knock.jl's synth (one decaying sine per mode).
using GeometryBasics, Makie, LinearAlgebra
isdefined(Main, :CHIPSTONE) || Core.eval(Main, :(const CHIPSTONE = Dict{Symbol,Any}()))
const NG = NeverendingGame
const CST = Main.CHIPSTONE
Base.include(@__MODULE__, joinpath(@__DIR__, "..", "physics", "modes.jl"))

const CS_SPOT = (4f0, -14f0)
const CS_H = 0.0075          # voxel, metres
const CS_LIFT = 0.06f0       # resting on two sticks of 3 cm radius
const CS_NEAR = 1.4f0        # Lumi within this of the stone's middle can chip and knock it
const CS_MAT = (E = 50e9, rho = 2700.0, nu = 0.25)

struct ChipStone <: System end

"A rounded flat stone, thinner towards its rim (voxels, 1 = stone); 42 x 11 x 4.5 cm."
function cs_stone_img(; L = 0.42, W = 0.11, T = 0.045)
    nx, ny, nz = ceil(Int, L / CS_H), ceil(Int, W / CS_H), ceil(Int, T / CS_H)
    img = zeros(Int, nx, ny, nz)
    for I in CartesianIndices(img)
        x, y, z = (Tuple(I) .- 0.5) .* CS_H .- (L / 2, W / 2, 0.0)
        r = abs(2x / L)^3.5 + abs(2y / W)^2.5
        r < 1 || continue
        z < T * (1 - 0.55r) && (img[I] = 1)
    end
    return img
end

"The solved stone's outer faces (FinEtools `meshboundary` of the hex mesh), smoothed a little: a pebble, not bricks."
function cs_mesh(fe, origin::Point3f; smooth = 3)
    FE = Modes.FinEtools
    conn = FE.connasarray(FE.meshboundary(fe.fes))
    used = unique(vec(conn)); remap = Dict(n => i for (i, n) in enumerate(used))
    pos = [origin + Point3f(fe.fens.xyz[n, 1], fe.fens.xyz[n, 2], fe.fens.xyz[n, 3]) for n in used]
    tris = GLTriangleFace[]
    for r in eachrow(conn)
        a, b, c, d = remap[r[1]], remap[r[2]], remap[r[3]], remap[r[4]]
        push!(tris, GLTriangleFace(a, b, c), GLTriangleFace(a, c, d))
    end
    nb = [Int[] for _ in pos]
    for f in tris, i in 1:3, j in 1:3
        i != j && push!(nb[f[i]], f[j])
    end
    for _ in 1:smooth
        pos = [Point3f(sum(pos[j] for j in nb[i]) / length(nb[i])) * 0.5f0 + pos[i] * 0.5f0 for i in eachindex(pos)]
    end
    n = zeros(Vec3f, length(pos))
    for f in tris
        a, b, c = pos[f[1]], pos[f[2]], pos[f[3]]
        fn = cross(b - a, c - a)
        n[f[1]] += fn; n[f[2]] += fn; n[f[3]] += fn
    end
    # meshboundary's faces may wind either way: point the normals away from the stone's middle
    mid = sum(pos) / length(pos)
    s = sum(dot(n[i], pos[i] - mid) for i in eachindex(pos)) < 0 ? -1f0 : 1f0
    s < 0 && (tris = [GLTriangleFace(f[1], f[3], f[2]) for f in tris])
    return GeometryBasics.Mesh(pos, tris; normal = [s * x / max(norm(x), 1f-12) for x in n])
end

cs_solve(img) = Modes.solve_voxels(img, CS_H; CS_MAT..., nev = 10, fixed = false)

function cs_drop_plots!(scene)
    for p in copy(scene.plots)
        haskey(p.attributes, :name) && p.attributes[:name][] in (:chipstone_stone, :chipstone_stick1, :chipstone_stick2) && delete!(scene, p)
    end
end

"Plots and the first solve, once (again after a restart: plot names are unique, old ones go first)."
function cs_ensure!(game)
    haskey(CST, :scene) && CST[:scene] === game.stage.scene && return
    w = game.world
    img = get!(cs_stone_img, CST, :img)
    nx, ny, _ = size(img)
    base = NG.ground(w.island, CS_SPOT)
    CST[:base] = base
    CST[:origin] = Point3f(base[1] - nx * CS_H / 2, base[2] - ny * CS_H / 2, base[3] + CS_LIFT - 0.004f0)
    scene = game.stage.scene
    cs_drop_plots!(scene)
    # the stone's mesh and modes come from a solve on a thread (the first one compiles FinEtools: 13 s in the frame)
    # (the plot is made when that mesh exists: a stand-in mesh without normals broke the first update)
    CST[:obs] = nothing
    CST[:task] = Threads.@spawn cs_solve(copy(img)); CST[:quiet] = true
    L = nx * CS_H
    for (i, sx) in enumerate((-1, 1))
        x = base[1] + sx * (L / 2 - 0.224f0 * L)    # under the stone's nodes, where a free bar rests
        mesh!(scene, Cylinder(Point3f(x, base[2] - 0.12f0, base[3] + 0.03f0), Point3f(x, base[2] + 0.12f0, base[3] + 0.03f0), 0.03f0);
              color = RGBf(0.42, 0.28, 0.16), name = Symbol(:chipstone_stick, i))
    end
    CST[:scene] = scene
    return
end

"Where along the stone Lumi's beak points: the voxel column index, or nothing when Lumi is not at the stone."
function cs_aim(game, me)
    b = CST[:base]
    hypot(me.pos[1] - b[1], me.pos[2] - b[2]) < CS_NEAR || return nothing
    yaw = me.yaw + NG.species_of(me).heading
    p = (me.pos[1] + 0.45f0 * cos(yaw), me.pos[2] + 0.45f0 * sin(yaw))
    nx = size(CST[:img], 1)
    return clamp(round(Int, (p[1] - b[1]) / CS_H + (nx + 1) / 2), 1, nx)
end

"Take the top layer off 3 columns around `i` (never the bottom two layers). Number of voxels taken."
function cs_chip!(img, i)
    nx, ny, _ = size(img); n = 0
    for ii in max(1, i - 1):min(nx, i + 1), j in 1:ny
        ks = findlast(==(1), view(img, ii, j, :))
        (ks === nothing || ks <= 2) && continue
        img[ii, j, ks] = 0; n += 1
    end
    return n
end

"Knock the stone in the middle of its top, straight down, through knock.jl's page synth."
function cs_knock!(game, me)
    m = CST[:modes]
    cx = (maximum(m.xyz[:, 1]) + minimum(m.xyz[:, 1])) / 2; cy = (maximum(m.xyz[:, 2]) + minimum(m.xyz[:, 2])) / 2
    q = argmax([abs(m.xyz[r, 1] - cx) < 1.5CS_H && abs(m.xyz[r, 2] - cy) < 1.5CS_H ? m.xyz[r, 3] : -Inf for r in 1:size(m.xyz, 1)])
    kn = game.plugins["knock"].mod
    parts = Base.invokelatest(kn.kn_partials, m, q, (0.0, 0.0, -1.0), 1.0)
    Base.invokelatest(kn.kn_play!, game, parts)
    low = isempty(parts) ? 0.0 : parts[1][1]
    CST[:last] = (; hz = low, voxels = sum(CST[:img]), t = game.world.t)
    me.action = :wave
    NG.say!(game.world, me, "Tink! $(round(Int, low)) Hz."; duration = 1.6)
    NG.emit!(game.world, :stone_knock; hz = round(low; digits = 1), voxels = sum(CST[:img]))
end

function NG.step!(::ChipStone, game, dt)
    game.stage === nothing && return
    me = NG.creature(game.world, "Lumi")
    me === nothing && return
    cs_ensure!(game)
    t = get(CST, :task, nothing)
    if t !== nothing && istaskdone(t)
        m, fe = fetch(t)                      # a failed solve throws here: the plugin error shows it
        CST[:task] = nothing; CST[:modes] = m
        msh = cs_mesh(fe, CST[:origin])
        if CST[:obs] === nothing
            CST[:obs] = Observable(msh)
            mesh!(game.stage.scene, CST[:obs]; color = RGBf(0.50, 0.49, 0.47), name = :chipstone_stone)
        else
            CST[:obs][] = msh
        end
        pop!(CST, :quiet, false) || cs_knock!(game, me)    # the new note right after a chip (not after the first solve)
    end
    # the menu's Jump in runs as a mini game (game.minigame isa JumpIn): the stone must answer there too (review 0139)
    free = game.minigame === nothing || game.minigame isa NG.JumpIn
    aim = me.controlled && free ? cs_aim(game, me) : nothing
    CST[:near] = aim !== nothing              # knock.jl leaves L to us while Lumi is at the stone
    rdown = Makie.Keyboard.r in game.keys_down
    ldown = Makie.Keyboard.l in game.keys_down
    if aim !== nothing && get(CST, :task, nothing) === nothing
        if rdown && !get(CST, :rdown, false)
            if cs_chip!(CST[:img], aim) == 0
                NG.say!(game.world, me, "Nothing left to chip there."; duration = 1.4)
            else
                me.action = :wave
                CST[:task] = Threads.@spawn cs_solve(copy(CST[:img]))
                NG.emit!(game.world, :stone_chip; column = aim)
            end
        elseif ldown && !get(CST, :ldown, false) && haskey(CST, :modes)
            cs_knock!(game, me)
        end
    end
    CST[:rdown] = rdown; CST[:ldown] = ldown
    return
end

register!(ChipStone())
