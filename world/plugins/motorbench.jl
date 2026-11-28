# The motor bench (s154, project motor, physics/motor.jl): Lumi's motor sits on a board south of the tops board, wired
# to a chain of clay-pot cells (s159, physics/potcell.jl; sea-water cells were ~1000x too weak). Since s157 it is a drum: three coils across a wooden drum, joined in a ring, on a 3-segment
# copper ring (Motor.drum_film), so it starts by itself from any angle. Jumped in as Lumi beside it: 7 touches or lifts
# the last wire (the switch), 8 and 9 turn the first or the second stone round (both round: it runs backwards; one:
# the fields cancel and it stops). Nothing here sets a torque: Motor.step! solves the coils' circuit (which segments
# the brushes touch, each coil's resistance, inductance and back-EMF) and turns the rotor by I dl x B in the stones' field.
# s157: wood with grain, copper (physics/motorlook.jl mo_wood). s158: lumpy magnet stones (the same mesh em.jl
# magnetises, Motor.stator_shapes) painted red on the north end, each coil one wound bundle bending round the axle;
# copper with a cuprite skin (motorlook.jl mo_copper). Editing only physics/*.jl does not reload this plugin: touch it.
using GeometryBasics, Makie, LinearAlgebra
isdefined(Main, :LOCAL_KEYS) || Core.eval(Main, :(const LOCAL_KEYS = Dict{String,Any}()))
isdefined(Main, :MOTORBENCH) || Core.eval(Main, :(const MOTORBENCH = Dict{Symbol,Any}()))
const NG = NeverendingGame
const MB = Main.MOTORBENCH
Base.include(@__MODULE__, joinpath(@__DIR__, "..", "physics", "motor.jl"))
Base.include(@__MODULE__, joinpath(@__DIR__, "..", "physics", "motorlook.jl"))

Base.include(@__MODULE__, joinpath(@__DIR__, "..", "physics", "potcell.jl"))

const MB_SPOT = (5.6f0, -14.3f0)
const MB_NEAR = 0.9f0     # s159: was 1.8, overlapped the levitron board (6.0,-12.1, 1.3 m) where 7 and 8 also act
const MB_LOOK = 6      # bump when the drawing changes (s158: chipped stones, bundles, cuprite copper; s159: clay pots)
const MB_SWITCH = Makie.Keyboard._7
const MB_STONE1 = Makie.Keyboard._8
const MB_STONE2 = Makie.Keyboard._9
const MB_POTS = Makie.Keyboard._0
const MB_NPOTS = 6
const MB_TABLE_H = 0.62f0   # oak work table under the bench (s159)

struct MotorBench <: System end

# s159: the cells are clay pots (physics/potcell.jl): a kiln-fired porous pot of blue copper salt with a copper strip,
# standing in a dish of sea water with an iron bar. Each frame the pots in the chain (series, 0 adds the next one, after
# six back to one) set the motor's emf and resistance (Nernst, wall resistance from the firing, polarisation at the
# current that flows), and Faraday's law takes copper out of the blue and iron off the bar for the charge that passed.
function mb_pots!()
    haskey(MB, :pots) && MB[:pots] isa Vector{PotCell.Pot} && length(MB[:pots]) == MB_NPOTS || (MB[:pots] = [PotCell.Pot(; Tfire = 930.0 + 15k) for k in 1:MB_NPOTS])
    get!(MB, :npots, MB_NPOTS)        # MB outlives reloads: pots of an older PotCell module are rebuilt above
end

function mb_cells!(st)
    pots = MB[:pots]; n = MB[:npots]; I = max(abs(st.Ibrush), 0.02)
    lin = [PotCell.linear(pots[k], I) for k in 1:n]
    st.E = sum(first, lin); st.Rs = sum(last, lin)
    return
end

function mb_build!(flip)
    MB[:flip] = flip
    MB[:b] = Motor.drum_film(; flip)
    old = get(MB, :st, nothing)
    MB[:st] = old isa Motor.DrumState ? Motor.DrumState(MB[:b]; θ0 = old.θ, ω0 = old.ω, on = old.on) :
              Motor.DrumState(MB[:b]; θ0 = pi / 2, on = false)
    mb_pots!(); mb_cells!(MB[:st])
    return
end

# Lumi tastes the chain the way Volta and Sulzer tested a pile: both ends on a wet tongue. The current through it is the
# pots' real emf over their resistance plus the tongue's (~8 kOhm wet); a tongue feels ~0.1 mA as sour, ~1 mA as a bite.
const MB_TONGUE_R = 8000.0
function mb_taste!(w, me)
    n = MB[:npots]; lin = [PotCell.linear(MB[:pots][k], 1e-4) for k in 1:n]
    mA = 1e3 * sum(first, lin) / (sum(last, lin) + MB_TONGUE_R)
    msg = mA > 0.5 ? "Zzzt! $n pots bite my tongue!" : mA > 0.25 ? "$n pots... sour, a tingle!" : "$n pot$(n == 1 ? "" : "s"): only a little sour."
    NG.say!(w, me, msg; duration = 2.5)
    NG.emit!(w, :taste_cell; who = me.name, pots = n, mA = round(mA, digits = 2))
    return mA
end

"A solid of revolution about z from a closed (r, z) profile (outer wall up, inner wall down), at P."
function mb_lathe(prof, P; n = 40)
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

"Fired clay: orange-red when fired low, browner and denser when fired hot; grainy and dry."
function mb_clay(Tfire)
    TN = NG.Hikari.TextureNodes
    n = TN.noise(TN.xyz(); scale = 160, detail = 4).fac
    f = clamp((Tfire - 900) / 300, 0, 1)
    base = (0.66 - 0.2 * f, 0.33 - 0.1 * f, 0.20 - 0.06 * f)
    NG.Hikari.Principled(base_color = TN.color_ramp(n, 0.0 => base .* 0.8, 1.0 => base), roughness = 0.8 + 0.15 * n,
                         normal = TN.bump(n; distance = 0.0008))
end

"Where pot k stands: in a row beside the bench, past the brushes' wires."
mb_potpos(game, A, k) = (xy = (A[1] + 0.12f0 + 0.2f0 * (k - 1), A[2] + 0.62f0); g = NG.ground(game.world.island, xy); Point3f(g[1], g[2], g[3]))

function mb_pot_plots!(game)
    sc = game.stage.scene; A = MB[:A]
    for p in copy(sc.plots)
        haskey(p.attributes, :name) && startswith(string(p.attributes[:name][]), "motorbench_pot") && delete!(sc, p)
    end
    copper = mo_copper(); iron = mo_iron()
    for (k, pot) in enumerate(MB[:pots])
        P = mb_potpos(game, A, k); nm(s) = Symbol("motorbench_pot", k, "_", s)
        dish = [(0.0, 0.0), (0.085, 0.0), (0.092, 0.035), (0.088, 0.038), (0.080, 0.006), (0.0, 0.006)]
        mesh!(sc, mb_lathe(dish, P); color = RGBf(0.55, 0.27, 0.16), material = mb_clay(1000.0), name = nm("dish"))
        mesh!(sc, mb_lathe([(0.0, 0.0), (0.082, 0.0)], P + Point3f(0, 0, 0.03f0)); color = RGBf(0.18, 0.26, 0.26), name = nm("brine"),
              material = NG.Hikari.Principled(base_color = (0.10, 0.17, 0.17), roughness = 0.04, coat_weight = 1.0, coat_roughness = 0.02))
        r = Float32(pot.r); w = Float32(pot.wall); h = 0.13f0
        wall = [(0.0, 0.006), (r - 0.004, 0.006), (r, 0.03), (r + 0.003, 0.08), (r - 0.002, h), (r - w, h), (r - w + 0.003, 0.08),
                (r - w, 0.03), (r - w - 0.004, 0.014), (0.0, 0.014)]
        mesh!(sc, mb_lathe(wall, P); color = RGBf(0.62, 0.30, 0.18), material = mb_clay(pot.Tfire), name = nm("pot"))
        b = Float32(PotCell.blueness(pot))
        mesh!(sc, mb_lathe([(0.0, 0.0), (r - w + 0.001, 0.0)], P + Point3f(0, 0, 0.125f0)); color = RGBf(0.05, 0.25 * b + 0.1, 0.7 * b + 0.2),
              name = nm("blue"), material = NG.Hikari.Principled(base_color = (0.03, 0.18 * b + 0.05, 0.55 * b + 0.1), roughness = 0.03,
                                                                coat_weight = 1.0, coat_roughness = 0.02))
        mesh!(sc, GeometryBasics.normal_mesh(Rect3f(P + Point3f(-0.012f0, -0.002f0, 0.03f0), Vec3f(0.024f0, 0.003f0, 0.14f0)));
              color = RGBf(0.86, 0.46, 0.24), material = copper, name = nm("copper"))
        bar = P + Point3f(0.0f0, -r - 0.022f0, 0.006f0)
        mesh!(sc, GeometryBasics.normal_mesh(Cylinder(bar, bar + Point3f(0.0f0, -0.012f0, 0.15f0), 0.006f0));
              color = RGBf(0.3, 0.3, 0.31), material = iron, name = nm("iron"))
    end
    mb_cords!(game)
end

"Copper cords: each pot's copper strip to the next pot's iron bar (series), the chain's ends to the bench's two wires."
function mb_cords!(game)
    sc = game.stage.scene; A = MB[:A]
    for p in copy(sc.plots)
        haskey(p.attributes, :name) && startswith(string(p.attributes[:name][]), "motorbench_cord") && delete!(sc, p)
    end
    cu(k) = mb_potpos(game, A, k) + Point3f(0, 0, 0.17f0)
    fe(k) = (P = mb_potpos(game, A, k); r = Float32(MB[:pots][k].r); P + Point3f(0.0f0, -r - 0.034f0, 0.155f0))
    sag(a, b) = [a + t * (b - a) - Point3f(0, 0, 0.05f0 * 4t * (1 - t)) for t in range(0, 1; length = 14)]
    b = MB[:b]; xr = 0.075f0 + 0.018f0
    ends = [Point3f(A[1] + xr + 0.09f0, A[2] + (k == 1 ? 0.03f0 : -0.03f0) + (k == 1 ? 0.28f0 : 0.22f0), A[3] - 0.095f0) for k in 1:2]
    n = MB[:npots]
    segs = [sag(ends[1], cu(1)); [sag(fe(k), cu(k + 1)) for k in 1:n-1]; [sag(fe(n), ends[2])]]
    for (i, s) in enumerate(segs)
        mesh!(sc, mtube(s, 0.0014f0); color = RGBf(0.78, 0.42, 0.22), material = mo_copper(), name = Symbol("motorbench_cord", i))
    end
end

function mb_marks!(sc)
    for p in copy(sc.plots)
        haskey(p.attributes, :name) && startswith(string(p.attributes[:name][]), "motorbench_mark") && delete!(sc, p)
    end
    A = MB[:A]
    for (k, (_, sh)) in enumerate(mo_stones(MB[:b], A))   # red ochre on each stone's north end (where it is magnetised to)
        mesh!(sc, mo_paint(sh, A, !MB[:flip][k]); color = RGBf(0.62, 0.14, 0.08),
              name = Symbol("motorbench_mark", k), material = NG.Hikari.Diffuse(color = (0.62, 0.14, 0.08), roughness = 0.8f0))
    end
end

function mb_ensure!(game)
    haskey(MB, :rot) && MB[:rot][1].parent === game.stage.scene && MB[:st] isa Motor.DrumState &&
        get(MB, :look, 0) == MB_LOOK && get(MB, :pots, nothing) isa Vector{PotCell.Pot} && return      # MB outlives reloads: a new look needs MB_LOOK bumped
    sc = game.stage.scene
    for p in copy(sc.plots)
        haskey(p.attributes, :name) && startswith(string(p.attributes[:name][]), "motorbench_") && delete!(sc, p)
    end
    get(MB, :st, nothing) isa Motor.DrumState || delete!(MB, :st)
    mb_build!(get(MB, :flip, (false, false)))
    g = NG.ground(game.world.island, MB_SPOT)
    # s159 (review #743: 'a slab on bare sand'): the bench stands on an oak work table at Lumi's beak height
    top = g[3] + MB_TABLE_H
    oak = mo_wood(base = (0.56, 0.40, 0.24))
    mesh!(sc, GeometryBasics.normal_mesh(Rect3f(Point3f(g[1] - 0.30f0, g[2] - 0.24f0, top - 0.045f0), Vec3f(0.62f0, 0.50f0, 0.045f0)));
          color = RGBf(0.56, 0.40, 0.24), material = oak, name = :motorbench_table_top)
    for (k, (dx, dy)) in enumerate(((-0.26f0, -0.2f0), (0.28f0, -0.2f0), (-0.26f0, 0.2f0), (0.28f0, 0.2f0)))
        gl = NG.ground(game.world.island, (g[1] + dx, g[2] + dy))
        mesh!(sc, GeometryBasics.normal_mesh(Cylinder(Point3f(g[1] + dx, g[2] + dy, gl[3] - 0.05f0), Point3f(g[1] + dx, g[2] + dy, top - 0.045f0), 0.024f0));
              color = RGBf(0.5, 0.35, 0.2), material = oak, name = Symbol("motorbench_table_leg", k))
    end
    look = motor_plots!(sc, MB[:b], Point3f(g[1], g[2], top + 0.03f0); prefix = "motorbench_")
    MB[:A] = look.A; MB[:rot] = look.rot; MB[:look] = MB_LOOK
    mb_marks!(sc)
    mb_pot_plots!(game)
    Main.LOCAL_KEYS["motorbench"] = gm -> get(MB, :near, false) ?
        "7 touch / lift the last wire   8 / 9 turn a stone round   0 add a clay pot ($(MB[:npots]) in the chain)" : nothing
    return
end

function NG.step!(::MotorBench, game, dt)
    game.stage === nothing && return
    me = NG.creature(game.world, "Lumi")
    me === nothing && return
    mb_ensure!(game)
    w = game.world; A = MB[:A]; st = MB[:st]
    free = game.minigame === nothing || game.minigame isa NG.JumpIn
    near = me.controlled && free && hypot(me.pos[1] - A[1], me.pos[2] - A[2]) < MB_NEAR
    MB[:near] = near
    pressed(k) = (s = Symbol("key_", Int(k)); d = k in game.keys_down; was = get(MB, s, false); MB[s] = d; d && !was)
    if near && pressed(MB_SWITCH)
        st.on = !st.on
        NG.say!(w, me, st.on ? "Wire on!" : "And off."; duration = 2.0)
        NG.emit!(w, :motor_switch; on = st.on, rev_s = st.ω / 2pi)
    end
    for (k, key) in enumerate((MB_STONE1, MB_STONE2))
        if near && pressed(key)
            fl = MB[:flip]; fl = k == 1 ? (!fl[1], fl[2]) : (fl[1], !fl[2])
            mb_build!(fl); st = MB[:st]
            mb_marks!(game.stage.scene)
            NG.say!(w, me, fl[1] == fl[2] ? "Both the same way again." : "Now they push against each other."; duration = 2.5)
            NG.emit!(w, :motor_stone; flip = fl)
        end
    end
    # Lumi tinkers on its own: every few minutes, when nobody plays it and it isn't asleep, it walks to the ring end of
    # the bench and pecks the last wire (the :eat action lowers the beak): on if it was off, off if it was running.
    if !me.controlled
        g = me.goal
        if w.t > get(MB, :next_visit, 0.0) && !(g.kind in (:sleep, :motor, :flight, :conga))
            spot = NG.ground(w.island, (A[1] + 0.42f0, A[2]))
            me.goal = NG.Goal(:motor, spot, :eat, 2.5, 0.0, false, 0, false)
            MB[:next_visit] = w.t + 240.0
            MB[:pecked] = false
        elseif !get(MB, :pecked, true) && g.kind in (:wander, :idle)       # a visit pending: back to the bench
            me.goal = NG.Goal(:motor, NG.ground(w.island, (A[1] + 0.42f0, A[2])), :eat, 2.5, 0.0, false, 0, false)
        elseif g.kind === :motor && g.arrived && !get(MB, :pecked, true)
            MB[:pecked] = true
            st.on = !st.on
            NG.say!(w, me, st.on ? "Off you go, little motor!" : "Rest now."; duration = 2.5)
            NG.emit!(w, :motor_switch; who = "Lumi", on = st.on, rev_s = st.ω / 2pi)
            MB[:taste_at] = w.t + 3.0                 # then it touches the chain's two ends to its tongue
        end
    end
    if near && pressed(MB_POTS)
        MB[:npots] = MB[:npots] % MB_NPOTS + 1
        mb_cords!(game)
        NG.emit!(w, :motor_pots; n = MB[:npots])
        mb_taste!(w, me)
    end
    if haskey(MB, :taste_at) && w.t > MB[:taste_at] && !me.controlled
        delete!(MB, :taste_at); mb_taste!(w, me)
    end
    mb_cells!(st)
    h = min(Float64(dt), 0.05)
    Motor.step!(st, MB[:b], h)
    if st.on                              # the charge that passed: copper out of the blue, iron off the bar
        for k in 1:MB[:npots]
            PotCell.run!(MB[:pots][k], abs(st.Ibrush), h)
        end
    end
    motor_pose!(MB[:rot], A, st.θ)
    return
end

function NG.stop!(::MotorBench, game)
    game.stage === nothing && return
    for p in copy(game.stage.scene.plots)
        haskey(p.attributes, :name) && startswith(string(p.attributes[:name][]), "motorbench_") && delete!(game.stage.scene, p)
    end
    delete!(MB, :rot)
end

register!(MotorBench())
