# s182 (project plante): Plante's jar beside the drum's six pots. Two lead sheets stand in dilute acid in a glass jar,
# wired to the pots' two ends; physics/plante.jl forms them while the island runs (CHEMISTRY seconds per game second):
# the current splits at each plate between its solid reaction and splitting water by their own kinetics. What you see
# is what it solves: bubbles leave each plate at its gas rate (O2 off the positive, H2 off the negative, real bubble
# size and rise), the positive's oxide spreads brown patch by patch with its formed PbO2, a reduced plate goes matte
# grey with spongy lead. Lumi swaps the leads every chemistry hour; jumped in as Lumi, J by the jar swaps them now.
using GeometryBasics, Makie, LinearAlgebra, Random
isdefined(Main, :PLANTE) || Core.eval(Main, :(const PLANTE = Dict{Symbol,Any}()))
isdefined(Main, :LOCAL_KEYS) || Core.eval(Main, :(const LOCAL_KEYS = Dict{String,Any}()))
const NG = NeverendingGame
const PL = Main.PLANTE
Base.include(@__MODULE__, joinpath(@__DIR__, "..", "physics", "plante.jl"))
Base.include(@__MODULE__, joinpath(@__DIR__, "..", "physics", "motorlook.jl"))

const PL_SPOT = (4.62f0, -15.06f0)    # south of the drum's pot row (pots at y -14.70, x 4.35 + 0.28 k)
const PL_JAR = (r = 0.075f0, h = 0.21f0, acid = 0.175f0, wall = 0.004f0)
const PL_PLATE = (w = 0.08f0, h = 0.15f0, t = 0.002f0, gap = 0.032f0, z0 = 0.015f0)   # plate centres at y = +-gap
const PL_AREA = 2 * 0.08 * 0.15        # m2 each plate, both faces
const PL_SWAP = Makie.Keyboard.j
const PL_NAMES = (:plante_jar, :plante_acid, :plante_leadA, :plante_leadB, :plante_oxA, :plante_oxB, :plante_spA,
                  :plante_spB, :plante_bubbles, :plante_cord1, :plante_cord2, :plante_lugA, :plante_lugB)
const PL_NX, PL_NZ = 8, 12             # the plate faces in patches: oxide grows patch by patch
const PL_BUB = 0.75e-3                 # bubble radius (m): 1.5 mm across, as off lead in acid
const PL_RISE = 0.18                   # m/s, a 1.5 mm bubble's terminal rise in water

struct PlanteJar <: System end

pl_kin() = Plante.Kin()
pl_lead() = NG.Hikari.Principled(base_color = (0.56, 0.57, 0.60), metallic = 0.85, roughness = 0.42)
pl_oxide() = NG.Hikari.Principled(base_color = (0.20, 0.10, 0.055), roughness = 0.85)
pl_sponge() = NG.Hikari.Principled(base_color = (0.30, 0.31, 0.33), metallic = 0.2, roughness = 0.95)

"A patch's turn: oxide reaches the edges first (the current crowds there), then the face, unevenly."
function pl_thresholds(seed)
    rng = MersenneTwister(seed)
    [0.55 * rand(rng) + 0.45 * (1 - 2min(i - 0.5, PL_NX + 0.5 - i) / PL_NX) * 0.5 +
     0.45 * (1 - 2min(k - 0.5, PL_NZ + 0.5 - k) / PL_NZ) * 0.5 for i in 1:PL_NX, k in 1:PL_NZ]
end

"The patches of plate (centre c) whose threshold is under `share`, as thin quads 0.3 mm proud of both faces."
function pl_patches(c, thr, share)
    pts = Point3f[]; fcs = GLTriangleFace[]
    W, H, T = PL_PLATE.w, PL_PLATE.h, PL_PLATE.t / 2 + 0.0003f0
    for i in 1:PL_NX, k in 1:PL_NZ
        thr[i, k] < share || continue
        x0 = -W / 2 + W * (i - 1) / PL_NX; x1 = x0 + W / PL_NX
        z0 = H * (k - 1) / PL_NZ; z1 = z0 + H / PL_NZ
        for s in (-1, 1)
            o = length(pts)
            append!(pts, [c + Point3f(x0, s * T, z0), c + Point3f(x1, s * T, z0), c + Point3f(x1, s * T, z1), c + Point3f(x0, s * T, z1)])
            push!(fcs, GLTriangleFace(o + 1, o + 2, o + 3), GLTriangleFace(o + 1, o + 3, o + 4))
        end
    end
    # nothing grown yet: a 1 mm triangle hidden inside the sheet (the path tracer refuses a mesh without area)
    isempty(pts) && (pts = [c + Point3f(0, 0, 0.05f0), c + Point3f(0.001f0, 0, 0.05f0), c + Point3f(0, 0, 0.051f0)]; fcs = [GLTriangleFace(1, 2, 3)])
    GeometryBasics.normal_mesh(GeometryBasics.Mesh(pts, fcs))
end

"How much of a plate's face reads brown (PbO2) and grey (spongy lead): a few um of either covers lead completely."
pl_shares(p) = (1 - exp(-p.d * p.x / 0.6e-6), 1 - exp(-p.d * (1 - p.x) / 0.6e-6))

function pl_lathe(prof, c; n = 48)
    pts = Point3f[]; fcs = GLTriangleFace[]; m = length(prof)
    for j in 0:n-1, (r, z) in prof
        a = 2pi * j / n
        push!(pts, c + Point3f(r * cos(a), r * sin(a), z))
    end
    for j in 0:n-1, i in 1:m-1
        a = j * m + i; b = mod(j + 1, n) * m + i
        push!(fcs, GLTriangleFace(a, b, b + 1), GLTriangleFace(a, b + 1, a + 1))
    end
    GeometryBasics.normal_mesh(GeometryBasics.Mesh(pts, fcs))
end

function pl_cords(swapped)
    P = PL[:P]; pots = PL[:pots]
    lug(s) = P + Point3f(0, s * PL_PLATE.gap, PL_JAR.h + 0.03f0)
    a, b = swapped ? (pots[2], pots[1]) : (pots[1], pots[2])        # plate A to the pots' + end unless swapped
    sag(p, q; d = 0.06f0) = [p + t * (q - p) - Point3f(0, 0, d * 4t * (1 - t)) for t in range(0, 1; length = 18)]
    (mtube(sag(lug(-1), a), 0.0018f0; nring = 8), mtube(sag(lug(1), b), 0.0018f0; nring = 8))
end

function pl_ensure!(game)
    haskey(PL, :jar) && return
    delete!(PL, :keyA); delete!(PL, :keyB)
    sc = game.stage.scene
    for p in copy(sc.plots)
        haskey(p.attributes, :name) && p.attributes[:name][] in PL_NAMES && delete!(sc, p)
    end
    w = game.world
    g = NG.ground(w.island, PL_SPOT); P = Point3f(g[1], g[2], g[3] - 0.01f0)
    PL[:P] = P
    top(x, y) = (q = NG.ground(w.island, (x, y)); Point3f(q[1], q[2], q[3] + 0.25f0))
    PL[:pots] = (top(4.35f0, -14.70f0), top(4.35f0 + 5 * 0.28f0, -14.70f0))   # pot 1's copper (+), pot 6's iron (-)
    J = PL_JAR
    jar = [(0.0, 0.0), (J.r, 0.0), (J.r + 0.003, 0.01), (J.r + 0.003, J.h), (J.r - J.wall, J.h), (J.r - J.wall, J.wall), (0.0, J.wall)]
    PL[:jar] = mesh!(sc, pl_lathe(jar, P); color = RGBAf(0.85, 0.93, 0.9, 0.25), name = :plante_jar,
                     material = NG.Hikari.Glass(color = (0.93, 0.98, 0.95), ior = 1.5, roughness = 0.0))
    mesh!(sc, pl_lathe([(0.0, 0.0), (J.r - J.wall - 0.0005, 0.0)], P + Point3f(0, 0, J.acid)); color = RGBAf(0.9, 0.95, 0.95, 0.3),
          name = :plante_acid, material = NG.Hikari.Glass(color = (0.97, 0.99, 0.97), ior = 1.37, roughness = 0.0))
    for (s, L) in ((-1, :A), (1, :B))
        c = P + Point3f(0, s * PL_PLATE.gap, PL_PLATE.z0)
        sheet = Rect3f(c + Point3f(-PL_PLATE.w / 2, -PL_PLATE.t / 2, 0), Vec3f(PL_PLATE.w, PL_PLATE.t, PL_PLATE.h))
        lug = Rect3f(c + Point3f(-0.006, -PL_PLATE.t / 2, PL_PLATE.h), Vec3f(0.012, PL_PLATE.t, PL_JAR.h + 0.03f0 - PL_PLATE.h - PL_PLATE.z0 + 0.005f0))
        mesh!(sc, GeometryBasics.normal_mesh(sheet); color = RGBf(0.56, 0.57, 0.6), material = pl_lead(), name = Symbol("plante_lead", L))
        mesh!(sc, GeometryBasics.normal_mesh(lug); color = RGBf(0.56, 0.57, 0.6), material = pl_lead(), name = Symbol("plante_lug", L))
        PL[Symbol("c", L)] = c
        PL[Symbol("thr", L)] = pl_thresholds(L === :A ? 18 : 59)
        PL[Symbol("ox", L)] = Observable(pl_patches(c, PL[Symbol("thr", L)], 0.0))
        PL[Symbol("sp", L)] = Observable(pl_patches(c, PL[Symbol("thr", L)], 0.0))
        mesh!(sc, PL[Symbol("sp", L)]; color = RGBf(0.3, 0.31, 0.33), material = pl_sponge(), name = Symbol("plante_sp", L))
        mesh!(sc, PL[Symbol("ox", L)]; color = RGBf(0.2, 0.1, 0.055), material = pl_oxide(), name = Symbol("plante_ox", L))
    end
    PL[:bub] = Observable([P + Point3f(0, 0, 0.05f0)])
    meshscatter!(sc, PL[:bub]; markersize = Float32(PL_BUB), color = RGBAf(0.95, 0.98, 1.0, 0.6), name = :plante_bubbles,
                 material = NG.Hikari.Glass(color = (1.0, 1.0, 1.0), ior = 1.33, roughness = 0.0))
    PL[:swapped] = false
    c1, c2 = pl_cords(false)
    PL[:cord1] = Observable(c1); PL[:cord2] = Observable(c2)
    for (k, o) in enumerate((PL[:cord1], PL[:cord2]))
        mesh!(sc, o; color = RGBf(0.78, 0.42, 0.22), material = mo_copper(), name = Symbol("plante_cord", k))
    end
    # the chemistry: plate A starts as the positive; a short start so a fresh island shows formed plates
    get!(PL, :chem_rate, 120.0)       # chemistry seconds per game second (1 game min = 2 h at 60: set by films)
    get!(PL, :swap_every, 3600.0)     # Lumi swaps the leads every chemistry hour
    get!(PL, :pre, [(1.0, 1), (1.0, -1), (1.0, 1)])
    r = Plante.form(schedule = PL[:pre], area = PL_AREA, dt = 10.0)
    PL[:A] = r.A; PL[:B] = r.B; PL[:pol] = r.pol[end]; PL[:since] = 0.0; PL[:swaps] = length(PL[:pre]) - 1
    PL[:O2] = r.O2[end]; PL[:H2] = r.H2[end]; PL[:I] = r.I[end]; PL[:V] = r.V[end]; PL[:acc] = 0.0
    PL[:bubbles] = Tuple{Point3f, Float64}[]                       # position, wobble phase
    pl_shades!()
    Main.LOCAL_KEYS["plante"] = g -> get(PL, :near, false) ?
        "J swap the leads   ($(round(PL[:I]; digits = 2)) A, $(round(PL[:V]; digits = 2)) V, holds $(round(1000Plante.capacity((; A = PL[:A], B = PL[:B], pol = [PL[:pol]], area = PL_AREA)); digits = 0)) mA h)" : nothing
    return
end

function pl_shades!()
    for L in (:A, :B)
        o, s = pl_shares(PL[L])
        thr = PL[Symbol("thr", L)]; c = PL[Symbol("c", L)]
        key = (round(Int, 96o), round(Int, 96s))
        get(PL, Symbol("key", L), nothing) == key && continue
        PL[Symbol("key", L)] = key
        PL[Symbol("ox", L)][] = pl_patches(c, thr, o)
        PL[Symbol("sp", L)][] = pl_patches(c, 1 .- thr, s * (1 - o))   # spongy grey where no oxide is
    end
end

"Advance the chemistry by `secs` (one step at the source/cell current), as physics/plante.jl form does."
function pl_chem!(secs)
    k = pl_kin()
    pos, neg = PL[:pol] > 0 ? (PL[:A], PL[:B]) : (PL[:B], PL[:A])
    r = Plante.form(schedule = [(secs / 3600, 1)], area = PL_AREA, dt = secs, k = k, plates = (pos, neg))
    PL[:O2] = r.O2[end]; PL[:H2] = r.H2[end]; PL[:I] = r.I[end]; PL[:V] = r.V[end]
    PL[:opos] = PL[:O2]; PL[:hneg] = PL[:H2]
end

function pl_swap!(game)
    PL[:pol] = -PL[:pol]; PL[:since] = 0.0; PL[:swaps] += 1
    (PL[:pol] > 0 ? PL[:A] : PL[:B]).film = 0.0
    PL[:swapped] = PL[:pol] < 0
    c1, c2 = pl_cords(PL[:swapped]); PL[:cord1][] = c1; PL[:cord2][] = c2
    NG.log_event!(game.log, game.world.t, :plante_swap; swaps = PL[:swaps], held_mAh = round(1000Plante.capacity((; A = PL[:A], B = PL[:B], pol = [PL[:pol]], area = PL_AREA)); digits = 1))
end

function NG.step!(::PlanteJar, game, dt)
    game.stage === nothing && return
    pl_ensure!(game)
    w = game.world
    me = NG.creature(w, "Lumi")
    free = game.minigame === nothing || game.minigame isa NG.JumpIn
    P = PL[:P]
    PL[:near] = me !== nothing && me.controlled && free && hypot(me.pos[1] - P[1], me.pos[2] - P[2]) < 1.0
    down = PL_SWAP in game.keys_down
    PL[:near] && down && !get(PL, :down, false) && pl_swap!(game)
    PL[:down] = down
    secs = dt * PL[:chem_rate]
    PL[:acc] += secs; PL[:since] += secs
    if PL[:acc] >= 20.0                                  # the chemistry in 20 s steps (it moves slowly)
        pl_chem!(PL[:acc]); PL[:acc] = 0.0; pl_shades!()
    end
    PL[:since] >= PL[:swap_every] && !PL[:near] && pl_swap!(game)
    # bubbles: born on the plate faces at the solved gas rates, rising at their terminal speed in real time
    vb = 4 / 3 * pi * PL_BUB^3
    rate(n) = n * 0.0245 / vb                            # mol/s of gas -> bubbles a second (24.5 L/mol)
    B = PL[:bubbles]
    pos_c, neg_c = PL[:pol] > 0 ? (PL[:cA], PL[:cB]) : (PL[:cB], PL[:cA])
    for (c, n) in ((pos_c, PL[:O2]), (neg_c, PL[:H2]))
        m = rate(n) * dt
        born = floor(Int, m) + (rand() < m - floor(m) ? 1 : 0)
        for _ in 1:min(born, 40)
            s = rand((-1, 1))
            push!(B, (c + Point3f((rand() - 0.5f0) * PL_PLATE.w, s * (PL_PLATE.t / 2 + Float32(PL_BUB)), rand() * PL_PLATE.h), 2pi * rand()))
        end
    end
    top = P[3] + PL_JAR.acid - Float32(PL_BUB)
    for i in eachindex(B)
        p, ph = B[i]
        B[i] = (p + Point3f(0.004f0 * cos(ph + 9p[3]) * dt, 0.004f0 * sin(ph + 7p[3]) * dt, PL_RISE * dt), ph)
    end
    filter!(b -> b[1][3] < top, B)
    length(B) > 600 && deleteat!(B, 1:length(B) - 600)
    PL[:bub][] = isempty(B) ? [P + Point3f(0, 0, -0.05f0)] : first.(B)
    return
end

function NG.stop!(::PlanteJar, game)
    delete!(Main.LOCAL_KEYS, "plante")
    game.stage === nothing && return
    for p in copy(game.stage.scene.plots)
        haskey(p.attributes, :name) && p.attributes[:name][] in PL_NAMES && delete!(game.stage.scene, p)
    end
    delete!(PL, :jar)
end

register!(PlanteJar())
