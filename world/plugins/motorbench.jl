# The motor bench (s154, project motor, physics/motor.jl): Lumi's motor sits on a board south of the tops board, wired
# to six sea-water cells. Since s157 it is a drum: three coils across a wooden drum, joined in a ring, on a 3-segment
# copper ring (Motor.drum_film), so it starts by itself from any angle. Jumped in as Lumi beside it: 7 touches or lifts
# the last wire (the switch), 8 and 9 turn the first or the second stone round (both round: it runs backwards; one:
# the fields cancel and it stops). Nothing here sets a torque: Motor.step! solves the coils' circuit (which segments
# the brushes touch, each coil's resistance, inductance and back-EMF) and turns the rotor by I dl x B in the stones' field.
# s157: wood with grain, iron-grey stones, copper (physics/motorlook.jl mo_wood, mo_iron).
using GeometryBasics, Makie, LinearAlgebra
isdefined(Main, :LOCAL_KEYS) || Core.eval(Main, :(const LOCAL_KEYS = Dict{String,Any}()))
isdefined(Main, :MOTORBENCH) || Core.eval(Main, :(const MOTORBENCH = Dict{Symbol,Any}()))
const NG = NeverendingGame
const MB = Main.MOTORBENCH
Base.include(@__MODULE__, joinpath(@__DIR__, "..", "physics", "motor.jl"))
Base.include(@__MODULE__, joinpath(@__DIR__, "..", "physics", "motorlook.jl"))

const MB_SPOT = (5.6f0, -14.3f0)
const MB_NEAR = 1.8f0
const MB_SWITCH = Makie.Keyboard._7
const MB_STONE1 = Makie.Keyboard._8
const MB_STONE2 = Makie.Keyboard._9

struct MotorBench <: System end

function mb_build!(flip)
    MB[:flip] = flip
    MB[:b] = Motor.drum_film(; flip)
    old = get(MB, :st, nothing)
    MB[:st] = old isa Motor.DrumState ? Motor.DrumState(MB[:b]; θ0 = old.θ, ω0 = old.ω, on = old.on) :
              Motor.DrumState(MB[:b]; θ0 = pi / 2, on = false)
    return
end

function mb_marks!(sc)
    for p in copy(sc.plots)
        haskey(p.attributes, :name) && startswith(string(p.attributes[:name][]), "motorbench_mark") && delete!(sc, p)
    end
    A = MB[:A]
    for (k, m) in enumerate(MB[:b].magnets)          # a red north face on each stone, where its magnetisation points
        y0 = Float32(m.pos[2]); north = MB[:flip][k] ? y0 - 0.001f0 : y0 + 0.036f0
        c = A + Point3f(0, north, 0)
        mesh!(sc, GeometryBasics.normal_mesh(Cylinder(c, c + Point3f(0, 0.002f0, 0), 0.034f0)); color = RGBf(0.7, 0.12, 0.1),
              name = Symbol("motorbench_mark", k), material = NG.Hikari.Diffuse(color = (0.7, 0.12, 0.1), roughness = 0.6f0))
    end
end

function mb_ensure!(game)
    haskey(MB, :rot) && MB[:rot][1].parent === game.stage.scene && MB[:st] isa Motor.DrumState && return
    sc = game.stage.scene
    for p in copy(sc.plots)
        haskey(p.attributes, :name) && startswith(string(p.attributes[:name][]), "motorbench_") && delete!(sc, p)
    end
    get(MB, :st, nothing) isa Motor.DrumState || delete!(MB, :st)
    mb_build!(get(MB, :flip, (false, false)))
    g = NG.ground(game.world.island, MB_SPOT)
    look = motor_plots!(sc, MB[:b], Point3f(g[1], g[2], g[3] + 0.03f0); prefix = "motorbench_")
    MB[:A] = look.A; MB[:rot] = look.rot
    mb_marks!(sc)
    Main.LOCAL_KEYS["motorbench"] = gm -> get(MB, :near, false) ? "7 touch / lift the last wire   8 / 9 turn a stone round" : nothing
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
        end
    end
    Motor.step!(st, MB[:b], min(Float64(dt), 0.05))
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
