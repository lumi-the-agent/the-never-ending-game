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
const ID_LOOK = 3
const ID_IRON = NG.Hikari.Principled(base_color = (0.40f0, 0.40f0, 0.42f0), metallic = 0.6f0, roughness = 0.45f0)   # soft iron, filed
const ID_FERRITE = NG.Hikari.Principled(base_color = (0.09f0, 0.09f0, 0.10f0), metallic = 0.0f0, roughness = 0.65f0)

struct IronDrum <: System end

cyl(a, b, r) = GeometryBasics.normal_mesh(Cylinder(Point3f(a...), Point3f(b...), Float32(r)))

"One coil k (0 or 1) on the drum: a loop along the drum in its two slots, crossing the end faces (rotor frame, axle x)."
function id_coil(k)
    φ = k * pi / 2; r = 0.0335
    s1 = (r * sin(φ), -r * cos(φ)); s2 = (-s1[1], -s1[2])
    e = 0.047 + 0.007k                                  # the two coils cross the end faces one above the other
    pts = [Point3f(-e, s1...), Point3f(e, s1...), Point3f(e, s2...), Point3f(-e, s2...), Point3f(-e, s1...)]
    mtube(pts, 0.0035f0)
end

function id_ensure!(game)
    sc = game.stage.scene
    haskey(ID, :rot) && ID[:rot][1].parent === sc && get(ID, :look, 0) == ID_LOOK && return
    for p in copy(sc.plots)
        haskey(p.attributes, :name) && startswith(string(p.attributes[:name][]), "irondrum_") && delete!(sc, p)
    end
    g = NG.ground(game.world.island, ID_SPOT)
    top = g[3] + ID_H
    oak = mo_wood(base = (0.56, 0.40, 0.24))
    mesh!(sc, cyl((g[1], g[2], g[3] - 0.05f0), (g[1], g[2], top), 0.17); color = RGBf(0.56, 0.40, 0.24), material = oak,
          name = :irondrum_stand)                       # a round oak chopping block
    c = Point3f(g[1], g[2], top + 0.045f0)              # the axle's middle
    for (k, sgn) in enumerate((1f0, -1f0))              # the two ferrite stones either side, magnetised along y
        mesh!(sc, cyl(c + Point3f(0, sgn * 0.036f0, 0), c + Point3f(0, sgn * 0.072f0, 0), 0.036); color = RGBf(0.09, 0.09, 0.10),
              material = ID_FERRITE, name = Symbol("irondrum_stone", k))
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
    push!(rot, mesh!(sc, cyl((0.068, 0, 0), (0.088, 0, 0), 0.011); color = RGBf(0.78, 0.42, 0.22), material = mo_copper(), name = :irondrum_ring))
    for k in 0:1
        push!(rot, mesh!(sc, id_coil(k); color = RGBf(0.78, 0.42, 0.22), material = mo_copper(), name = Symbol("irondrum_coil", k)))
    end
    for p in rot
        Makie.translate!(p, c)
    end
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
        if st.on && !get(ID, :told, false) && st.ω / 2pi > 5.0
            ID[:told] = true
            NG.say!(w, me, "Iron drum: $(round(st.ω / 2pi, digits = 1)) turns a second on six clay pots!"; duration = 3.0)
            NG.emit!(w, :drum_spun_up; rev_s = st.ω / 2pi, amps = st.I)
        end
    end
    Motor.step!(st, ID[:b], min(Float64(dt), 0.05))
    for p in ID[:rot]
        Makie.rotate!(p, Vec3f(1, 0, 0), Float32(st.θ))
    end
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
