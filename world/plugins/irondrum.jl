# The iron drum motor (s172, project winch: the motor that will pull the cart). On its own oak stand beside the motor
# bench: the two ferrite stones of the big bench, and between them, 4 mm off their faces, a round soft iron drum
# (3.2 cm radius, 9 cm long, 2.3 kg) carrying TWO coils at right angles in its slots, a 4-segment copper commutator and
# brushes, running on six clay pots. Nothing here sets a speed: Motor.step! (physics/motor.jl, Build(drum = true))
# solves the coils' current against their back-EMF and the torque from the drum's field table, which
# physics/motor2d.jl solved as 2D magnetostatics with saturating iron (Ferrite.jl; round iron: no cogging, no dead
# spot), against the bearing's dry friction under the drum's own weight. It spins up from rest to ~6 rev/s.
using GeometryBasics, Makie, LinearAlgebra
isdefined(Main, :LOCAL_KEYS) || Core.eval(Main, :(const LOCAL_KEYS = Dict{String,Any}()))
isdefined(Main, :IRONDRUM) || Core.eval(Main, :(const IRONDRUM = Dict{Symbol,Any}()))
const NG = NeverendingGame
const ID = Main.IRONDRUM
Base.include(@__MODULE__, joinpath(@__DIR__, "..", "physics", "motor.jl"))
Base.include(@__MODULE__, joinpath(@__DIR__, "..", "physics", "motorlook.jl"))
Base.include(@__MODULE__, joinpath(@__DIR__, "..", "physics", "rope.jl"))

const ID_SPOT = (4.85f0, -14.3f0)     # 0.6 m west of the motor bench's table
const ID_H = 0.62f0                   # the stand's top, the bench table's height
const ID_LOOK = 14   # s176: the winch: an oak spindle on the axle, a hemp rope, a driftwood log
const ID_IRON = NG.Hikari.Principled(base_color = (0.40f0, 0.40f0, 0.42f0), metallic = 0.6f0, roughness = 0.45f0)   # soft iron, filed
const ID_FERRITE = NG.Hikari.Principled(base_color = (0.09f0, 0.09f0, 0.10f0), metallic = 0.0f0, roughness = 0.65f0)
# s173: the commutator spark: air breaking down at the brush's trailing edge (N2 lines, violet-blue) with a little
# copper vapour (green) once the break carries more than copper's minimum arc current (~0.43 A; the drum breaks ~0.6 A)
# s174: strength 22 clipped the core to white in the traced film and lit the copper round it orange; 6 keeps it blue
# s175: at strength 6 every channel clipped and the tone mapper drew the spark WHITE; air breaking down glows violet-blue
# (N2 second positive lines 337-400 nm). (0.42, 0.36, 1) x 2.6 still went white at dusk exposure (every channel clips):
# nearly pure blue-violet, so only blue clips and red/green stay under it (media/s175-spark-blue-test.png was white)
# x 3 STILL white (the dusk exposure multiplies several-fold: media/s175-brushes-blue2.png): dim at the source
# x 0.6 came out pale blue-WHITE = the plot's own color (0.8, 0.88, 1): the traced spark takes the PLOT colour. Both now
# blue-violet (ID_SPARK_RGB)
const ID_SPARK = NG.Hikari.Emission(color = (0.18f0, 0.14f0, 1.0f0), strength = 1.5f0, two_sided = true)
const ID_SPARK_RGB = RGBf(0.18, 0.14, 1.0)
const ID_HIDE = Point3f(0, 0, -0.35)       # a spark not burning sits inside the oak block

struct IronDrum <: System end

cyl(a, b, r) = GeometryBasics.normal_mesh(Cylinder(Point3f(a...), Point3f(b...), Float32(r)))
"A rounder cylinder (`n` sides): the default tessellation drew the 34 cm oak block as an octagon (s178 critic)."
cyl(a, b, r, n) = GeometryBasics.normal_mesh(GeometryBasics.Tessellation(Cylinder(Point3f(a...), Point3f(b...), Float32(r)), n))

"Several meshes as one (vertices and faces appended)."
function id_merge(ms)
    pts = Point3f[]; fs = GeometryBasics.TriangleFace{Int}[]
    for m in ms
        o = length(pts)
        append!(pts, Point3f.(GeometryBasics.coordinates(m)))
        append!(fs, [GeometryBasics.TriangleFace((Int.(GeometryBasics.value.(Tuple(f))) .+ o)...) for f in GeometryBasics.faces(m)])
    end
    GeometryBasics.normal_mesh(GeometryBasics.Mesh(pts, fs))
end

"""
One coil k (0 or 1) on the drum (rotor frame, axle x): a loop along the drum in its two slots, crossing the end faces.
s173: drawn as its windings, 4 turns side by side in 3 layers of 1 mm wire (the 80 turns of 0.35 mm wire bundled as
the eye sees them), not one rod.
"""
function id_coil(k)
    φ = k * pi / 2
    nrm = (cos(φ), sin(φ))                             # across the coil's plane
    tubes = Any[]
    for layer in 0:2, j in 0:3
        r = 0.0328 + 0.0019 * layer
        e = 0.047 + 0.007k + 0.0019 * layer             # the two coils cross the end faces one above the other
        d = 0.0021 * (j - 1.5)
        s1 = (r * sin(φ) + d * nrm[1], -r * cos(φ) + d * nrm[2]); s2 = (-r * sin(φ) + d * nrm[1], r * cos(φ) + d * nrm[2])
        pts = [Point3f(-e, s1...), Point3f(e, s1...), Point3f(e, s2...), Point3f(-e, s2...), Point3f(-e, s1...)]
        push!(tubes, mtube(pts, 0.00105f0; nring = 6))
    end
    id_merge(tubes)
end

"""
One commutator segment of the 4-segment ring (rotor frame, axle along x): a sector of a copper sleeve from angle `a0`
to `a1` (measured from +y towards +z), outer radius `ro`, on the axle from x0 to x1.
"""
function id_segment(a0, a1; ro = 0.011f0, ri = 0.0055f0, x0 = 0.068f0, x1 = 0.088f0, n = 10)
    pts = Point3f[]; fs = GeometryBasics.TriangleFace{Int}[]
    ring(r, x) = [Point3f(x, r * cos(a), r * sin(a)) for a in range(a0, a1; length = n + 1)]
    loops = (ring(ro, x0), ring(ro, x1), ring(ri, x1), ring(ri, x0))
    for l in loops
        append!(pts, l)
    end
    m = n + 1
    for (u, v) in ((0, 1), (1, 2), (2, 3), (3, 0)), i in 1:n
        a = u * m + i; b = v * m + i
        push!(fs, GeometryBasics.TriangleFace(a, b, b + 1), GeometryBasics.TriangleFace(a, b + 1, a + 1))
    end
    for k in (0, n)                                     # the two cut faces at the gaps
        q = [l * m + k + 1 for l in 0:3]
        push!(fs, GeometryBasics.TriangleFace(q[1], q[2], q[3]), GeometryBasics.TriangleFace(q[1], q[3], q[4]))
    end
    GeometryBasics.normal_mesh(GeometryBasics.Mesh(pts, fs))
end

"""
s173: the oak chopping block's wood: growth rings about the block's own axis (object coordinates, z flattened so they
run down the log as a tree's rings do), distorted by 3D noise so the side shows streaky grain, darker late wood,
checks of a dry block; a waxed, worn top.
"""
function id_oak_block()
    TN = NG.Hikari.TextureNodes
    p = TN.texture_coordinate().object
    q = TN.mapping(p; scale = (1, 1, 0.08))
    # s174: scale 55 + distortion 6 drew ~9 wavy rings across the top: rippled sand when traced (perfectionist s172).
    # Oak grows 2-4 mm a year: ~260 rings a metre, nearly round (distortion 1.2)
    rings = TN.wave(q; type = :rings, scale = 260, distortion = 1.2, detail = 3).fac
    fine = TN.noise(p; scale = 300, detail = 3).fac
    base = (0.56, 0.40, 0.24)
    col = TN.color_ramp(rings, 0.0 => base, 0.6 => base .* 0.82, 1.0 => base .* 0.5)
    NG.Hikari.Principled(base_color = col, roughness = 0.55 + 0.2 * fine, normal = TN.bump(rings * 0.5 + fine * 0.5; distance = 0.0004),
                         coat_weight = 0.15, coat_roughness = 0.4)
end

"A solid of revolution about z from an (r, z) profile, at P (as motorbench.jl's mb_lathe)."
function id_lathe(prof, P; n = 36)
    verts = Point3f[]; fcs = GLTriangleFace[]; m = length(prof)
    for i in 1:m, k in 0:n-1
        φ = 2pi * k / n; r, z = prof[i]
        push!(verts, P + Point3f(r * cos(φ), r * sin(φ), z))
    end
    for i in 1:m-1, k in 0:n-1
        a = (i - 1) * n + k + 1; b = (i - 1) * n + mod(k + 1, n) + 1; c = i * n + k + 1; d = i * n + mod(k + 1, n) + 1
        push!(fcs, GLTriangleFace(a, b, c)); push!(fcs, GLTriangleFace(b, d, c))
    end
    GeometryBasics.normal_mesh(GeometryBasics.Mesh(verts, fcs))
end

"""
s174: a clay oil lamp on the block's north-east rim, by the commutator end: a small warm flame to see the motor by at
dusk (the s173 dusk film showed only dark blocks). The flame is an emissive drop, an area light in the tracer; it never
moves, so path tracing keeps one light for it.
"""
function id_lamp!(sc, c)
    lp = c + Point3f(0.125f0, 0.065f0, -0.045f0)                        # on the block's top
    dish = [(0.0, 0.0), (0.020, 0.0), (0.027, 0.008), (0.028, 0.014), (0.022, 0.017), (0.007, 0.015), (0.0045, 0.021),
            (0.0035, 0.021)]
    mesh!(sc, id_lathe(dish, lp); color = RGBf(0.62, 0.30, 0.18), material = id_clay(), name = :irondrum_lamp)
    flame = mesh!(sc, GeometryBasics.normal_mesh(Sphere(Point3f(0), 0.0045f0)); color = RGBf(1.0, 0.7, 0.35),
                  material = NG.Hikari.Emission(color = (1.0f0, 0.62f0, 0.28f0), strength = 14f0, two_sided = true),
                  name = :irondrum_lamp_flame)
    Makie.scale!(flame, 1f0, 1f0, 2.2f0)
    Makie.translate!(flame, lp + Point3f(0, 0, 0.031f0))
    nothing
end

"Fired clay, grainy and dry (as motorbench.jl's mb_clay at ~950 C)."
function id_clay()
    TN = NG.Hikari.TextureNodes
    n = TN.noise(TN.xyz(); scale = 160, detail = 4).fac
    base = (0.62, 0.31, 0.19)
    NG.Hikari.Principled(base_color = TN.color_ramp(n, 0.0 => base .* 0.8, 1.0 => base), roughness = 0.8 + 0.15 * n,
                         normal = TN.bump(n; distance = 0.0008))
end

"""
s173: the drum's OWN six clay pots (Motor.iron_drum_bench's cells: 0.78 V, 0.5 Ohm each), in a row on the sand south of
its block: each a fired pot of blue copper salt with a copper strip, in a dish of sea water with an iron bar; copper
cords join each pot's copper to the next one's iron (series) and the two ends climb the block to the brushes.
"""
function id_pots!(sc, c)
    copper = mo_copper(); iron = mo_iron(); clay = id_clay()
    r = 0.055f0; w = 0.008f0; h = 0.13f0
    P = [NG.ground(ID[:game_w].island, (ID_SPOT[1] - 0.5f0 + 0.2f0 * (k - 1), ID_SPOT[2] - 0.40f0)) for k in 1:6]
    P = [Point3f(p[1], p[2], p[3]) for p in P]
    for (k, p) in enumerate(P)
        nm(x) = Symbol("irondrum_pot", k, "_", x)
        dish = [(0.0, 0.0), (0.085, 0.0), (0.092, 0.035), (0.088, 0.038), (0.080, 0.006), (0.0, 0.006)]
        mesh!(sc, id_lathe(dish, p); color = RGBf(0.55, 0.27, 0.16), material = clay, name = nm("dish"))
        mesh!(sc, id_lathe([(0.0, 0.0), (0.082, 0.0)], p + Point3f(0, 0, 0.03f0)); color = RGBf(0.18, 0.26, 0.26), name = nm("brine"),
              material = NG.Hikari.Principled(base_color = (0.10, 0.17, 0.17), roughness = 0.04, coat_weight = 1.0, coat_roughness = 0.02))
        wall = [(0.0, 0.006), (r - 0.004, 0.006), (r, 0.03), (r + 0.003, 0.08), (r - 0.002, h), (r - w, h), (r - w + 0.003, 0.08),
                (r - w, 0.03), (r - w - 0.004, 0.014), (0.0, 0.014)]
        mesh!(sc, id_lathe(wall, p); color = RGBf(0.62, 0.30, 0.18), material = clay, name = nm("pot"))
        mesh!(sc, id_lathe([(0.0, 0.0), (r - w + 0.001, 0.0)], p + Point3f(0, 0, 0.125f0)); color = RGBf(0.05, 0.3, 0.8), name = nm("blue"),
              material = NG.Hikari.Principled(base_color = (0.03, 0.2, 0.62), roughness = 0.03, coat_weight = 1.0, coat_roughness = 0.02))
        mesh!(sc, GeometryBasics.normal_mesh(Rect3f(p + Point3f(-0.012f0, -0.002f0, 0.03f0), Vec3f(0.024f0, 0.003f0, 0.14f0)));
              color = RGBf(0.86, 0.46, 0.24), material = copper, name = nm("copper"))
        bar = p + Point3f(0.0f0, -r - 0.022f0, 0.006f0)
        mesh!(sc, GeometryBasics.normal_mesh(Cylinder(bar, bar + Point3f(0.0f0, -0.012f0, 0.15f0), 0.006f0));
              color = RGBf(0.3, 0.3, 0.31), material = iron, name = nm("iron"))
    end
    cu(k) = P[k] + Point3f(0, 0, 0.17f0)
    fe(k) = P[k] + Point3f(0.0f0, -r - 0.034f0, 0.155f0)
    sag(a, b; d = 0.05f0) = [a + t * (b - a) - Point3f(0, 0, d * 4t * (1 - t)) for t in range(0, 1; length = 14)]
    segs = [sag(fe(k), cu(k + 1)) for k in 1:5]
    # the chain's ends: pot 1's copper (+) to the top brush, pot 6's iron (-) to the bottom one, over the block's east rim
    gx = ID_SPOT[1]; gy = ID_SPOT[2]; top = c[3] - 0.045f0
    for (k, (from, dz, dy)) in enumerate(((cu(1), 0.032f0, 0.006f0), (fe(6), -0.032f0, -0.006f0)))
        brush = c + Point3f(0.08f0, dy, dz)
        rim = Point3f(gx + 0.175f0, gy + dy, top + 0.004f0)
        foot = Point3f(gx + 0.18f0, gy - 0.05f0 + dy, NG.ground(ID[:game_w].island, (gx + 0.18f0, gy - 0.05f0))[3] + 0.01f0)
        path = [[brush, brush + Point3f(0.03f0, 0, 0.0f0)]; sag(brush + Point3f(0.03f0, 0, 0), rim; d = -0.01f0)[2:end];
                [Point3f(rim[1] + 0.012f0, rim[2], rim[3] - 0.05f0), foot]; sag(foot, from; d = -0.04f0)[2:end]]
        push!(segs, path)
    end
    for (i, sg) in enumerate(segs)
        mesh!(sc, mtube(sg, 0.0016f0); color = RGBf(0.78, 0.42, 0.22), material = copper, name = Symbol("irondrum_cord", i))
    end
end

function id_ensure!(game)
    sc = game.stage.scene
    # (a reload re-includes motor.jl: a build and state of the old module's types are made again)
    haskey(ID, :rot) && ID[:rot][1].parent === sc && get(ID, :look, 0) == ID_LOOK && get(ID, :b, nothing) isa Motor.Build &&
        get(ID, :st, nothing) isa Motor.State && return
    for p in copy(sc.plots)
        haskey(p.attributes, :name) && startswith(string(p.attributes[:name][]), "irondrum_") && delete!(sc, p)
    end
    ID[:gap] = Motor.iron_drum_bench().gap
    g = NG.ground(game.world.island, ID_SPOT)
    top = g[3] + ID_H
    oak = mo_wood(base = (0.56, 0.40, 0.24))
    stand = mesh!(sc, cyl((0, 0, -0.05f0 - ID_H), (0, 0, 0), 0.17, 64); color = RGBf(0.56, 0.40, 0.24), material = id_oak_block(),
                  name = :irondrum_stand)               # a round oak chopping block, drawn about its own axis (its rings)
    Makie.translate!(stand, Point3f(g[1], g[2], top))
    c = Point3f(g[1], g[2], top + 0.045f0)              # the axle's middle
    for (k, sgn) in enumerate((1f0, -1f0))              # the two ferrite stones either side, magnetised along y
        # s173: the stones as the chipped beach stones the field was solved for (Motor.rough_stone), not flat discs
        sh = Motor.stator_shapes(; R = 0.036, H = 0.036, gap = 0.072, rough = true)[sgn > 0 ? 2 : 1]
        vs = [c + Point3f((sh.Rm * collect(v) .+ collect(sh.pos))...) for v in sh.v]
        mesh!(sc, GeometryBasics.normal_mesh(GeometryBasics.Mesh(vs, [GeometryBasics.TriangleFace(f...) for f in sh.f]));
              color = RGBf(0.13, 0.12, 0.12), material = mo_stone(), name = Symbol("irondrum_stone", k))
        mesh!(sc, GeometryBasics.normal_mesh(Rect3f(c + Point3f(-0.03f0, sgn > 0 ? 0.04f0 : -0.07f0, -0.045f0), Vec3f(0.06f0, 0.03f0, 0.004f0)));
              color = RGBf(0.5, 0.35, 0.2), material = oak, name = Symbol("irondrum_chock", k))
    end
    for (k, x) in enumerate((-0.075f0, 0.10f0))         # oak bearing posts
        mesh!(sc, GeometryBasics.normal_mesh(Rect3f(c + Point3f(x - 0.008f0, -0.012f0, -0.045f0), Vec3f(0.016f0, 0.024f0, 0.05f0)));
              color = RGBf(0.5, 0.35, 0.2), material = oak, name = Symbol("irondrum_post", k))
    end
    for (k, sgn) in enumerate((1f0, -1f0))              # copper brushes pressing on the commutator from above and below
        mesh!(sc, GeometryBasics.normal_mesh(Rect3f(c + Point3f(0.074f0, -0.004f0, sgn > 0 ? 0.012f0 : -0.03f0), Vec3f(0.012f0, 0.008f0, 0.018f0)));
              color = RGBf(0.78, 0.42, 0.22), material = mo_copper(), name = Symbol("irondrum_brush", k))
    end
    rot = Any[]
    push!(rot, mesh!(sc, cyl((-0.045, 0, 0), (0.045, 0, 0), 0.032); color = RGBf(0.40, 0.40, 0.42), material = ID_IRON, name = :irondrum_drum))
    push!(rot, mesh!(sc, cyl((-0.15, 0, 0), (0.105, 0, 0), 0.004); color = RGBf(0.40, 0.40, 0.42), material = ID_IRON, name = :irondrum_axle))
    # s176 (idea 'Gear it down'): an oak pinion of 6 cogs on the axle's west end drives the winch's big wheel (6:1)
    push!(rot, mesh!(sc, id_cog(ID_PINION_R, ID_PINION_N, -0.131, -0.119); color = RGBf(0.45, 0.31, 0.18), material = oak,
                     name = :irondrum_pinion))
    # the commutator: 4 copper segments, their 20 deg gaps at the coils' neutral (every quarter turn of θ, where
    # Motor.drum_open breaks the circuit); the brushes are 8 deg wide, so both leave their segments together and spark
    half = Float32((pi / 2 - ID[:gap]) / 2)
    for k in 0:3
        a = Float32(pi / 4 + k * pi / 2)
        push!(rot, mesh!(sc, id_segment(a - half, a + half); color = RGBf(0.78, 0.42, 0.22), material = mo_copper(),
                         name = Symbol("irondrum_seg", k)))
    end
    push!(rot, mesh!(sc, cyl((0.067, 0, 0), (0.089, 0, 0), 0.0058); color = RGBf(0.25, 0.18, 0.10), material = oak,
                     name = :irondrum_hub))            # the wooden hub the segments sit on (insulating them from the axle)
    for k in 0:1
        push!(rot, mesh!(sc, id_coil(k); color = RGBf(0.78, 0.42, 0.22), material = mo_copper(), name = Symbol("irondrum_coil", k)))
    end
    for p in rot
        Makie.translate!(p, c)
    end
    ID[:sparks] = [mesh!(sc, GeometryBasics.normal_mesh(Sphere(Point3f(0), 0.0022f0)); color = ID_SPARK_RGB,
                         material = ID_SPARK, name = Symbol("irondrum_spark", k)) for k in 1:2]
    for p in ID[:sparks]
        Makie.translate!(p, c + ID_HIDE)
    end
    ID[:c] = c
    ID[:game_w] = game.world
    id_pots!(sc, c)
    id_lamp!(sc, c)
    ID[:rot] = rot; ID[:look] = ID_LOOK
    ID[:b] = Motor.iron_drum_bench()
    old = get(ID, :st, nothing)
    ID[:st] = old isa Motor.State ? old : Motor.State(ID[:b]; θ0 = 0.3, on = false)
    id_winch!(sc, c, game.world)                       # after the state: drawing the rope asks whether it runs
    Main.LOCAL_KEYS["irondrum"] = gm -> get(ID, :near, false) ? "K switch the iron drum motor on / off" : nothing
end

const ID_KEY = Makie.Keyboard.k
const ID_NEAR = 0.8f0

function NG.step!(::IronDrum, game, dt)
    game.stage === nothing && return
    id_ensure!(game)
    ID[:game] = game
    st = ID[:st]; w = game.world
    me = NG.creature(w, "Lumi")
    if me !== nothing
        free = game.minigame === nothing || game.minigame isa NG.JumpIn
        near = me.controlled && free && hypot(me.pos[1] - ID_SPOT[1], me.pos[2] - ID_SPOT[2]) < ID_NEAR
        ID[:near] = near
        down = ID_KEY in game.keys_down; was = get(ID, :kdown, false); ID[:kdown] = down
        if near && down && !was
            id_switch!(w, me, st, "player")
        end
        # when nobody plays it, Lumi walks over now and then and pecks the drum motor's wire itself
        if !me.controlled
            g = me.goal
            spot = NG.ground(w.island, (ID_SPOT[1] - 0.3f0, ID_SPOT[2]))
            if w.t > get(ID, :next_visit, 20.0) && !(g.kind in (:sleep, :motor, :drum, :flight, :conga))
                me.goal = NG.Goal(:drum, spot, :eat, 2.5, 0.0, false, 0, false)
                ID[:next_visit] = w.t + 200.0; ID[:pecked] = false
            elseif !get(ID, :pecked, true) && g.kind in (:wander, :idle)     # a visit pending (a chat took Lumi away): back to it
                me.goal = NG.Goal(:drum, spot, :eat, 2.5, 0.0, false, 0, false)
            elseif g.kind === :drum && g.arrived && !get(ID, :pecked, true)
                ID[:pecked] = true
                id_switch!(w, me, st, "Lumi")
            end
        end
        if st.on && !get(ID, :told, false) && st.ω / 2pi > 4.5
            ID[:told] = true
            NG.say!(w, me, "Iron drum: $(round(st.ω / 2pi, digits = 1)) turns a second on six clay pots!"; duration = 3.0)
            NG.emit!(w, :drum_spun_up; rev_s = st.ω / 2pi, amps = maximum(abs, st.I))
        end
    end
    id_friend_visit!(w, st)
    h = min(Float64(dt), 0.05)
    θ0 = st.θ
    rd = id_rdrum()
    Motor.step!(st, ID[:b], h; τload = ID[:T] * rd / ID_GEAR)    # the rope's pull, through the drum and gear
    reel = (st.θ - θ0) / ID_GEAR * rd
    ID[:Lw] += reel
    ID[:T] = Rope.step!(ID[:rope], ID[:load], h; reel)
    id_rope_draw!(w)
    for p in ID[:wheel]
        Makie.rotate!(p, Vec3f(1, 0, 0), Float32(-st.θ / ID_GEAR))
    end
    r1 = Float32(id_rdrum()); Makie.scale!(ID[:coil], Vec3f(1, r1, r1))
    for p in ID[:rot]
        Makie.rotate!(p, Vec3f(1, 0, 0), Float32(st.θ))
    end
    id_sparks!(w, st)
    return
end

"""
The drum's own sound in every open page (through the voice plugin's sessions): two clips synthesised from this motor's
simulation (s172): drum-on = spin-up from rest on six pots, drum-off = coasting down from full speed; the pitch is the
torque ripple at 4 commutator handovers a turn, each handover a click as loud as the current it breaks, brush hiss
growing with speed (site/voice/game/drum-*.wav).
"""
function id_sound!(game, name)
    vp = get(game.plugins, "voice", nothing)
    (vp === nothing || isempty(vp.systems)) && return
    VM = parentmodule(typeof(only(vp.systems)))
    url = "/lumi/voice/game/" * name * ".wav"
    for s in VM.sessions!(game)
        NG.Bonito.evaljs(s, NG.Bonito.js"""
            const a = new Audio($(url)); a.volume = 0.9;
            a.play().catch(e => console.log('drum sound:', e.name));
        """)
    end
end

"""
The sparks of this frame: every break the motor logged since the last frame (st.sparks, 1/2 L I^2 each) lights a
spark at each brush's trailing edge, sized by its energy (s175: L_circuit 8 mH from the converged field solve ->
~1.3 mJ a break, was 0.6 at the 4 mH guess); a frame without a break leaves them dark. The log is emptied
here, so it never grows.
"""
function id_sparks!(w, st)
    E = sum(last, st.sparks; init = 0.0)
    empty!(st.sparks)
    c = ID[:c]
    for (k, p) in enumerate(ID[:sparks])
        if E > 1e-6
            sgn = k == 1 ? 1f0 : -1f0          # brush 1 on top, 2 below
            # the segment slides away under the brush's trailing edge: -y on top, +y below, for a forward spin
            ty = -sgn * Float32(sign(st.ω == 0 ? 1.0 : st.ω)) * 0.0042f0
            jit = 0.0012f0 * (2rand(Float32) - 1)
            Makie.translate!(p, c + Point3f(0.074f0 + 0.012f0 * rand(Float32), ty + jit, sgn * 0.0108f0))
            Makie.scale!(p, Float32(clamp(sqrt(E / 6e-4), 0.5, 1.6)))
        else
            Makie.translate!(p, c + ID_HIDE)
        end
    end
    if E > 1e-6 && !get(ID, :spark_told, false)
        ID[:spark_told] = true
        NG.emit!(w, :commutator_spark; mJ = 1e3 * E)
    end
    E > 1e-6 || (st.on || (ID[:spark_told] = false))
end

# ---- the winch (s176, project winch): oak spindle -> hemp rope (physics/rope.jl) -> a driftwood log on the sand ----
# s176 'Gear it down': motor -> 6-cog pinion -> 36-cog wheel (6:1) -> a 20 mm oak drum the rope PILES UP on
# (Rope.wound_radius: r^2 = r0^2 + d^2 L / (pi W)); pull = torque x ratio / r, reel = turn / ratio x r. Tested out of
# the game (rope_check.jl haul_fill): 6:1 brings the 0.88 kg log 2 m in ~10 s, 3:1 stalls at 1.36 m as the drum fills.
const ID_GEAR = 6.0
const ID_PINION_N = 6; const ID_PINION_R = 0.012; const ID_WHEEL_R = 0.072
const ID_CS = Point3f(0, 0.075, 0.038)          # the countershaft's axis from the motor axle's middle (84 mm apart)
const ID_DRUM_X = (-0.115, -0.06)               # the rope drum's flanges along the countershaft
const ID_DRUM_R0 = 0.02; const ID_DRUM_W = 0.055; const ID_ROPE_D = 0.009; const ID_LW0 = 0.3
const ID_RX = -0.0875f0                         # the rope's line (x from the axle's middle): the drum's middle
id_rdrum() = Rope.wound_radius(ID_DRUM_R0, ID_ROPE_D, ID_DRUM_W, ID[:Lw])

"A wooden cog wheel about x between x0 and x1: a disc of radius r with n square cogs standing out 5 mm."
function id_cog(r, n, x0, x1)
    ms = Any[cyl((x0, 0, 0), (x1, 0, 0), r - 0.003)]
    for k in 0:n-1
        φ = 2pi * k / n
        box = GeometryBasics.normal_mesh(Rect3f(Point3f(x0, -0.0025, r - 0.004), Vec3f(x1 - x0, 0.005, 0.009)))
        R = [1 0 0; 0 cos(φ) -sin(φ); 0 sin(φ) cos(φ)]
        vs = [Point3f((R * collect(p))...) for p in GeometryBasics.coordinates(box)]
        push!(ms, GeometryBasics.Mesh(vs, GeometryBasics.faces(box)))
    end
    id_merge(ms)
end

"A ring about x between x0 and x1 from radius ri to ro: outer, inner and both faces with their own vertices (sharp edges)."
function id_ring(ri, ro, x0, x1; n = 72)
    pts = Point3f[]; fs = GeometryBasics.TriangleFace{Int}[]
    yz(r, k) = (r * cos(2pi * k / n), r * sin(2pi * k / n))
    function band!(a, b)                    # a, b: (x, r) of the band's two edges, swept round
        o = length(pts)
        for k in 0:n
            push!(pts, Point3f(a[1], yz(a[2], k)...), Point3f(b[1], yz(b[2], k)...))
        end
        for k in 0:n-1
            i = o + 2k + 1
            push!(fs, GeometryBasics.TriangleFace(i, i + 3, i + 1), GeometryBasics.TriangleFace(i, i + 2, i + 3))   # outward
        end
    end
    band!((x0, ro), (x1, ro)); band!((x1, ri), (x0, ri)); band!((x1, ro), (x1, ri)); band!((x0, ri), (x0, ro))
    GeometryBasics.normal_mesh(GeometryBasics.Mesh(pts, fs))
end

"A box about the x axis turned by φ (its y,z rotated): x0..x1 along the axle, y0..y1 across, z0..z1 out from it."
function id_rbox(x0, x1, y0, y1, z0, z1, φ)
    box = GeometryBasics.normal_mesh(Rect3f(Point3f(x0, y0, z0), Vec3f(x1 - x0, y1 - y0, z1 - z0)))
    R = [1 0 0; 0 cos(φ) -sin(φ); 0 sin(φ) cos(φ)]
    GeometryBasics.Mesh([Point3f((R * collect(p))...) for p in GeometryBasics.coordinates(box)], GeometryBasics.faces(box))
end

"""
s177: the big wheel built as a millwright builds one: an oak rim, four arms through a hub, and n hornbeam cogs set in
mortises through the rim (standing 5 mm out, as id_cog's). Returns (frame, cogs): you see THROUGH it, so its turn shows.
"""
function id_spurwheel(r, n, x0, x1)
    ro = r - 0.003; ri = r - 0.015
    fr = Any[id_ring(ri, ro, x0, x1), id_ring(0.004, 0.013, x0 - 0.003, x1 + 0.003; n = 24)]
    for φ in (0.0, pi / 2, pi, 3pi / 2)       # arms: from the hub into the rim, a little thinner than it
        push!(fr, id_rbox(x0 + 0.0015, x1 - 0.0015, -0.004, 0.004, 0.011, ri + 0.004, φ + pi / 4))
    end
    cogs = Any[id_rbox(x0, x1, -0.0026, 0.0026, ri + 0.003, r + 0.005, 2pi * k / n) for k in 0:n-1]
    id_merge(fr), id_merge(cogs)
end
const ID_LOG_S = 2.3               # where the log lies, metres out along the rope from the block's foot
const ID_LOG_R = 0.04f0; const ID_LOG_L = 0.32f0
const ID_LOG_M = 0.88               # driftwood (~550 kg/m3), 4 cm x 32 cm
const ID_HEMP = NG.Hikari.Principled(base_color = (0.50, 0.40, 0.26), roughness = 0.92f0)

"The rope's foot on the sand north of the block (local s = 0), and the ground's height s metres further on."
id_foot(c) = Point3f(c[1] + ID_RX, c[2] + 0.20f0, 0)
id_gz(w, c, s) = NG.ground(w.island, (c[1] + ID_RX, c[2] + 0.20f0 + Float32(s)))[3]

function id_winch_reset!()
    c = ID[:c]; w = ID[:game_w]
    grade = (id_gz(w, c, ID_LOG_S) - id_gz(w, c, 0.0)) / ID_LOG_S
    ID[:rope] = Rope.Tether((0.0, 0.0, 0.0), (ID_LOG_S, 0.0, 0.0); n = 12, slack = 1.04)
    ID[:load] = Rope.Load(; m = ID_LOG_M, mu = 0.5, x = (ID_LOG_S, 0.0, 0.0), grade)
    ID[:T] = 0.0
    ID[:Lw] = ID_LW0                                   # a few turns already on the drum
    ID[:redraw] = true                                 # the log and rope are drawn where they now lie, even at rest
end

function id_winch!(sc, c, w)
    # a reload re-includes rope.jl (new types): rope and load made by the old module are made again
    get(ID, :rope, nothing) isa Rope.Tether && get(ID, :load, nothing) isa Rope.Load && haskey(ID, :Lw) || id_winch_reset!()
    ID[:rope_obs] = Observable(id_rope_mesh(w))
    mesh!(sc, ID[:rope_obs]; color = RGBf(0.50, 0.40, 0.26), material = ID_HEMP, name = :irondrum_rope)
    # sea-bleached driftwood: silver-grey, dry, the grain open (pale, rough, no bark)
    # (s176: a lumpy procedural branch read as a grey rubber sausage; the sawn round log reads as wood when traced)
    # the countershaft north of the motor: big cog wheel, iron shaft, oak rope drum with flanges, the rope coil on it
    cs = c + ID_CS
    oak = mo_wood(base = (0.56, 0.40, 0.24))
    # s178: the turning parts carry their grain with them (moving = true: object space), or a turning wheel's grain
    # stands still in the world and the turn does not read
    oakm = mo_wood(moving = true, base = (0.56, 0.40, 0.24))
    wheel = Any[]
    frame, cogs = id_spurwheel(ID_WHEEL_R, round(Int, ID_PINION_N * ID_GEAR), -0.131, -0.119)
    push!(wheel, mesh!(sc, frame; color = RGBf(0.5, 0.35, 0.2), material = oakm, name = :irondrum_wheel))
    # hornbeam: the millwright's pale, hard cog wood, near cream; mo_wood's grain darkens its base to 0.45-0.8x, so the
    # base is set pale (s178 critic: at (0.70, 0.60, 0.44) the cogs traced the same dull brown as the oak rim)
    push!(wheel, mesh!(sc, cogs; color = RGBf(0.86, 0.80, 0.66), material = mo_wood(moving = true, base = (0.95, 0.89, 0.75)),
                       name = :irondrum_cogs))
    push!(wheel, mesh!(sc, cyl((-0.16, 0, 0), (-0.05, 0, 0), 0.004); color = RGBf(0.40, 0.40, 0.42), material = ID_IRON,
                       name = :irondrum_cshaft))
    push!(wheel, mesh!(sc, cyl((ID_DRUM_X[1], 0, 0), (ID_DRUM_X[2], 0, 0), ID_DRUM_R0); color = RGBf(0.5, 0.35, 0.2),
                       material = oakm, name = :irondrum_rdrum))
    for (k, x) in enumerate(ID_DRUM_X)
        push!(wheel, mesh!(sc, cyl((x - 0.003, 0, 0), (x + 0.003, 0, 0), 0.038); color = RGBf(0.45, 0.31, 0.18), material = oak,
                           name = Symbol("irondrum_rflange", k)))
    end
    push!(wheel, mesh!(sc, GeometryBasics.normal_mesh(Rect3f(Point3f(-0.112, -0.003, -0.05), Vec3f(0.004, 0.006, 0.1)));
                       color = RGBf(0.35, 0.24, 0.14), material = oak, name = :irondrum_rpeg))   # a peg: the turn shows
    for p in wheel
        Makie.translate!(p, cs)
    end
    ID[:wheel] = wheel
    coil = mesh!(sc, cyl((ID_DRUM_X[1] + 0.004, 0, 0), (ID_DRUM_X[2] - 0.004, 0, 0), 1.0); color = RGBf(0.50, 0.40, 0.26),
                 material = ID_HEMP, name = :irondrum_rcoil)          # unit radius, scaled to the wound radius
    Makie.translate!(coil, cs)
    ID[:coil] = coil
    top = c[3] - 0.045f0
    mesh!(sc, GeometryBasics.normal_mesh(Rect3f(Point3f(c[1] - 0.168f0, cs[2] - 0.009f0, top), Vec3f(0.018f0, 0.018f0, cs[3] - top + 0.01f0)));
          color = RGBf(0.5, 0.35, 0.2), material = oak, name = :irondrum_cpost)   # the countershaft's oak post
    lg = mesh!(sc, cyl((-ID_LOG_L / 2, 0, 0), (ID_LOG_L / 2, 0, 0), ID_LOG_R); color = RGBf(0.70, 0.62, 0.52),
               material = mo_wood(moving = true, base = (0.72, 0.64, 0.54)), name = :irondrum_log)
    ID[:log] = lg
    id_rope_draw!(w; force = true)
end

"The rope as drawn: off the spindle's top, over the block's north rim, down its side, then the simulated particles."
function id_rope_pts(w)
    c = ID[:c]; F = id_foot(c); top = c[3] - 0.045f0
    rd = Float32(id_rdrum())                       # off the drum's underside (it turns backwards to the motor: reels in)
    lead = [c + ID_CS + Point3f(ID_RX, 0, -rd), c + ID_CS + Point3f(ID_RX, 0.03f0, -rd - 0.004f0),
            Point3f(c[1] + ID_RX, c[2] + 0.172f0, top + 0.004f0), Point3f(c[1] + ID_RX, c[2] + 0.182f0, top - 0.03f0)]
    pts = [Point3f(F[1] + Float32(x[2]), F[2] + Float32(x[1]), id_gz(w, c, x[1]) + Float32(x[3]) + 0.004f0) for x in ID[:rope].x]
    pts[1] = Point3f(pts[1][1], pts[1][2], pts[1][3] + 0.01f0)
    vcat(lead, pts)
end
id_rope_mesh(w) = mtube(id_rope_pts(w), 0.0045f0; nring = 7)   # a 9 mm hauling line

function id_rope_draw!(w; force = false)
    ld = ID[:load]
    moving = force || get(ID, :redraw, false) || ID[:st].on || ld.v[1] != 0
    moving || return
    ID[:redraw] = false
    ID[:rope_obs][] = id_rope_mesh(w)
    c = ID[:c]; F = id_foot(c); s = ld.x[1]
    Makie.translate!(ID[:log], Point3f(F[1], F[2] + Float32(s) + ID_LOG_R, id_gz(w, c, s) + ID_LOG_R))
    # a new happening: the drum hauled something on its rope (once a run, after the first 20 cm)
    if ID[:st].on && !get(ID, :haul_told, true) && get(ID, :haul_from, s) - s > 0.2
        ID[:haul_told] = true
        NG.emit!(w, :winch_haul; what = "driftwood log", kg = ID_LOG_M, metres = get(ID, :haul_from, s) - s, pull_N = ID[:T])
    end
end

const ID_IDLE_KINDS = (:wander, :idle, :sit, :play, :social, :dance, :rain, :sunbathe, :splash)
push!(NG.BUSY_GOALS, :drum)     # s177: on the way to the motor, a starfish to show off no longer pulls a friend away

"""
s176: the friends try the winch too. Every few minutes, while the drum stands idle, the
nearest friend who is up and wandering walks over and pulls the switch, watches the log come in on the rope, and
switches it off once the log is at the block (or after a while if it stalls).
"""
function id_friend_visit!(w, st)
    if !st.on && w.t > get(ID, :friend_next, w.t + 60.0)
        ID[:friend_next] = w.t + 180.0
        spot = NG.ground(w.island, (ID_SPOT[1] + 0.3f0, ID_SPOT[2] + 0.35f0))
        best = nothing; bd = 60.0
        for cr in w.creatures
            # s177: in the human's game nobody was ever just wandering (all fishing, in the rain, sunbathing): a friend
            # at any pastime may leave it for the motor; never one asleep, at work (NG.busy) or in another plugin's job
            (cr.name == "Lumi" || NG.busy(cr) || !(cr.goal.kind in ID_IDLE_KINDS)) && continue
            d = hypot(cr.pos[1] - ID_SPOT[1], cr.pos[2] - ID_SPOT[2])
            d < bd && (best = cr; bd = d)
        end
        best === nothing && (ID[:friend_next] = w.t + 45.0)      # nobody free: look again soon
        if best !== nothing
            best.goal = NG.Goal(:drum, spot, :eat, 2.5, 0.0, false, 0, false)
            ID[:friend] = best.name; ID[:friend_on] = false
            NG.say!(w, best, "What does Lumi's motor do?"; duration = 2.5)
        end
    end
    haskey(ID, :friend) || (ID[:friend_next] = get(ID, :friend_next, w.t + 60.0); return)
    cr = NG.creature(w, ID[:friend])
    cr === nothing && (delete!(ID, :friend); return)
    if !ID[:friend_on] && cr.goal.kind === :drum && cr.goal.arrived
        ID[:friend_on] = true; ID[:friend_t] = w.t
        st.on || id_switch!(w, cr, st, cr.name)
        NG.emit!(w, :friend_ran_winch; who = cr.name)
    elseif ID[:friend_on] && st.on && (ID[:load].x[1] < 0.45 || w.t - ID[:friend_t] > 40.0)
        id_switch!(w, cr, st, cr.name)
        NG.say!(w, cr, ID[:load].x[1] < 0.45 ? "It pulled the whole log in!" : "It got stuck!"; duration = 3.0)
        delete!(ID, :friend)
        cr.goal.kind === :drum && (cr.goal = NG.Goal(:wander, cr.pos, :idle, 1.0, 0.0, false, 0, false))
    elseif !ID[:friend_on] && !(cr.goal.kind === :drum)
        delete!(ID, :friend)                           # it got distracted on the way: ask someone else soon
        ID[:friend_next] = min(get(ID, :friend_next, w.t + 60.0), w.t + 60.0)
    end
end

function id_switch!(w, me, st, who)
    st.on = !st.on
    # switched on with the log already at the block: it was walked back out along the rope first (paid out by hand)
    st.on && ID[:load].x[1] < 0.7 && id_winch_reset!()
    st.on && (ID[:haul_from] = ID[:load].x[1]; ID[:haul_told] = false)
    haskey(ID, :game) && id_sound!(ID[:game], st.on ? "drum-on" : "drum-off")
    ID[:told] = false
    NG.say!(w, me, st.on ? "Iron drum, on!" : "Off. Listen to it coast."; duration = 2.5)
    NG.emit!(w, :drum_switch; who, on = st.on, rev_s = st.ω / 2pi)
end

function NG.stop!(::IronDrum, game)
    game.stage === nothing && return
    for p in copy(game.stage.scene.plots)
        haskey(p.attributes, :name) && startswith(string(p.attributes[:name][]), "irondrum_") && delete!(game.stage.scene, p)
    end
    delete!(ID, :rot)
end

register!(IronDrum())
