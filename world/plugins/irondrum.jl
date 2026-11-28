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

const ID_SPOT = (4.85f0, -14.3f0)     # 0.6 m west of the motor bench's table
const ID_H = 0.62f0                   # the stand's top, the bench table's height
const ID_LOOK = 8
const ID_IRON = NG.Hikari.Principled(base_color = (0.40f0, 0.40f0, 0.42f0), metallic = 0.6f0, roughness = 0.45f0)   # soft iron, filed
const ID_FERRITE = NG.Hikari.Principled(base_color = (0.09f0, 0.09f0, 0.10f0), metallic = 0.0f0, roughness = 0.65f0)
# s173: the commutator spark: air breaking down at the brush's trailing edge (N2 lines, violet-blue) with a little
# copper vapour (green) once the break carries more than copper's minimum arc current (~0.43 A; the drum breaks ~0.6 A)
const ID_SPARK = NG.Hikari.Emission(color = (0.42f0, 0.55f0, 1.0f0), strength = 22f0, two_sided = true)
const ID_HIDE = Point3f(0, 0, -0.35)       # a spark not burning sits inside the oak block

struct IronDrum <: System end

cyl(a, b, r) = GeometryBasics.normal_mesh(Cylinder(Point3f(a...), Point3f(b...), Float32(r)))

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
    rings = TN.wave(q; type = :rings, scale = 55, distortion = 6, detail = 4).fac
    fine = TN.noise(p; scale = 300, detail = 3).fac
    base = (0.56, 0.40, 0.24)
    col = TN.color_ramp(rings, 0.0 => base, 0.6 => base .* 0.82, 1.0 => base .* 0.5)
    NG.Hikari.Principled(base_color = col, roughness = 0.55 + 0.2 * fine, normal = TN.bump(rings * 0.7 + fine * 0.3; distance = 0.0008),
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
    haskey(ID, :rot) && ID[:rot][1].parent === sc && get(ID, :look, 0) == ID_LOOK && return
    for p in copy(sc.plots)
        haskey(p.attributes, :name) && startswith(string(p.attributes[:name][]), "irondrum_") && delete!(sc, p)
    end
    ID[:gap] = Motor.iron_drum_bench().gap
    g = NG.ground(game.world.island, ID_SPOT)
    top = g[3] + ID_H
    oak = mo_wood(base = (0.56, 0.40, 0.24))
    stand = mesh!(sc, cyl((0, 0, -0.05f0 - ID_H), (0, 0, 0), 0.17); color = RGBf(0.56, 0.40, 0.24), material = id_oak_block(),
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
    push!(rot, mesh!(sc, cyl((-0.085, 0, 0), (0.105, 0, 0), 0.004); color = RGBf(0.40, 0.40, 0.42), material = ID_IRON, name = :irondrum_axle))
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
    ID[:sparks] = [mesh!(sc, GeometryBasics.normal_mesh(Sphere(Point3f(0), 0.0022f0)); color = RGBf(0.8, 0.88, 1.0),
                         material = ID_SPARK, name = Symbol("irondrum_spark", k)) for k in 1:2]
    for p in ID[:sparks]
        Makie.translate!(p, c + ID_HIDE)
    end
    ID[:c] = c
    ID[:game_w] = game.world
    id_pots!(sc, c)
    ID[:rot] = rot; ID[:look] = ID_LOOK
    ID[:b] = Motor.iron_drum_bench()
    old = get(ID, :st, nothing)
    ID[:st] = old isa Motor.State ? old : Motor.State(ID[:b]; θ0 = 0.3, on = false)
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
    Motor.step!(st, ID[:b], min(Float64(dt), 0.05))
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
spark at each brush's trailing edge, sized by its energy; a frame without a break leaves them dark. The log is emptied
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

function id_switch!(w, me, st, who)
    st.on = !st.on
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
