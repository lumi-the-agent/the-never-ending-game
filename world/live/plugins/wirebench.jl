# Bend a copper wire (s144, project copper-wire). A 6 mm copper rod lies on a small board beside the tops board. Jumped
# in as Lumi, stand by it: HOLD 2 or 3 to bend it one way or the other where the wooden pin grips, TAP 4 to move the
# pin along the wire. physics/wire.jl decides what stays: each joint is elastic, then plastic past its yield moment;
# a spot bent before is harder, so the next bend goes beside it; let go and it springs back a little; bend one spot
# back and forth and it cracks (fatigue) and snaps. Nothing is animated: the shape is the joints' plastic angles.
using GeometryBasics, Makie, LinearAlgebra
isdefined(Main, :WIREBENCH) || Core.eval(Main, :(const WIREBENCH = Dict{Symbol,Any}()))
const NG = NeverendingGame
const WB = Main.WIREBENCH
Base.include(@__MODULE__, joinpath(@__DIR__, "..", "physics", "wire.jl"))

const WB_SPOT = (6.9f0, -12.6f0)
const WB_NEAR = 1.4f0
const WB_KEYS = (Makie.Keyboard._2, Makie.Keyboard._3, Makie.Keyboard._4)
const WB_RATE = deg2rad(70)          # how fast the beak turns the wire (rad/s)
const WB_VERSION = 5                 # bump when the state in WB changes shape (or the look: s145 slate board)

struct WireBench <: System end

wb_new() = Wire(n = 81, ds = 5e-3, d = 6e-3)    # a 40 cm, 6 mm copper rod (Lumi-sized; same physics)

function wb_ensure!(game)
    get(WB, :version, 0) == WB_VERSION && any(p -> haskey(p.attributes, :name) && p.attributes[:name][] === :wirebench_wire, game.stage.scene.plots) && return
    WB[:version] = WB_VERSION              # a reload that changes what WB holds rebuilds the bench (s144: :col_obs was missing)
    for p in copy(game.stage.scene.plots)
        haskey(p.attributes, :name) && p.attributes[:name][] in (:wirebench_board, :wirebench_wire, :wirebench_end, :wirebench_pin, :wirebench_scrap) && delete!(game.stage.scene, p)
    end
    g = NG.ground(game.world.island, WB_SPOT)
    top = Point3f(g[1], g[2], g[3] + 0.04f0)
    WB[:origin] = top - Point3f(0.2f0, 0.05f0, 0)
    w = wb_new(); WB[:w] = w; WB[:grip] = 30; WB[:snapped_at] = -1.0; WB[:loaded] = false
    board = GeometryBasics.normal_mesh(Rect3f(top - Point3f(0.3f0, 0.3f0, 0.04f0), Vec3f(0.6f0, 0.6f0, 0.04f0)))
    mesh!(game.stage.scene, board; color = RGBf(0.30, 0.34, 0.38), name = :wirebench_board,   # s145: slate, copper stands out
          material = NG.Hikari.Diffuse(color = (0.30, 0.34, 0.38), roughness = 0.7f0))
    WB[:wire_obs] = Observable(wire_tube(w, w.th, WB[:origin]))
    WB[:col_obs] = Observable([RGBf(c...) for c in wire_colors(w)])
    WB[:end_obs] = Observable(wire_tube(w, w.th, WB[:origin]; range = 1:2))
    mesh!(game.stage.scene, WB[:wire_obs]; color = WB[:col_obs], material = NG.Hikari.Copper(roughness = 0.18f0), name = :wirebench_wire)   # roughness 0 traced as a dark mirror
    mesh!(game.stage.scene, WB[:end_obs]; color = RGBf(0.85, 0.45, 0.3), material = NG.Hikari.Copper(roughness = 0.18f0), name = :wirebench_end, visible = false)
    pin = GeometryBasics.normal_mesh(Cylinder(Point3f(0), Point3f(0, 0, 0.03f0), 0.008f0))
    WB[:pin] = mesh!(game.stage.scene, pin; color = RGBf(0.7, 0.7, 0.72), name = :wirebench_pin,
                     material = NG.Hikari.Aluminum(roughness = 0.35f0))
    WB[:next_visit] = game.world.t + 45.0                # a friend comes soon after the bench is (re)built
    haskey(WB, :scrap) || (WB[:scrap] = Any[])
    WB[:scrap_obs] = Observable(wb_scrap_mesh(game))
    mesh!(game.stage.scene, WB[:scrap_obs]; color = RGBf(0.6, 0.35, 0.25), material = NG.Hikari.Copper(roughness = 0.3f0), name = :wirebench_scrap)
    wb_redraw!(game)
    return
end

"Every snapped wire stays: its two pieces, bent as they broke, lie on a pile beside the board (this run of the game)."
function wb_scrap_mesh(game)
    V = Point3f[]; F = TriangleFace{Int}[]; N = Vec3f[]
    pieces = get(WB, :scrap, Any[])
    isempty(pieces) && (pieces = Any[(wb_new().th, 1, 2, Point3f(WB[:origin] + Point3f(0.5f0, 0.1f0, -0.035f0)), 0.0f0)])   # a stub, hidden under the board's edge
    for (th, r0, r1, pos, yaw) in pieces
        m = wire_tube(wb_new(), th, Point3f(0); range = r0:r1)
        R = Makie.qrotation(Vec3f(0, 0, 1), yaw)
        o = length(V)
        append!(V, [Point3f(pos + R * Vec3f(v)) for v in GeometryBasics.coordinates(m)])
        append!(N, [Vec3f(R * Vec3f(n)) for n in GeometryBasics.normals(m)])
        append!(F, [TriangleFace(f[1] + o, f[2] + o, f[3] + o) for f in GeometryBasics.faces(m)])
    end
    return GeometryBasics.Mesh(V, F; normal = N)
end

function wb_redraw!(game)
    w = WB[:w]
    WB[:wire_obs][] = wire_tube(w, w.th, WB[:origin]; cut = w.broken == 0 ? w.n : w.broken)   # same vertex count
    WB[:col_obs][] = [RGBf(c...) for c in wire_colors(w)]
    w.broken == 0 || (WB[:end_obs][] = wire_tube(w, w.th, WB[:origin] + Point3f(0.03f0, -0.03f0, 0); range = w.broken+1:w.n))   # the broken end lies apart
    P = shape(w; angles = w.th)
    g = WB[:grip]
    Makie.translate!(WB[:pin], WB[:origin] + Vec3f(P[g][1], P[g][2], 0) + Vec3f(0, 0, 0))
    return
end

function NG.step!(::WireBench, game, dt)
    game.stage === nothing && return
    me = NG.creature(game.world, "Lumi")
    me === nothing && return
    wb_ensure!(game)
    w = WB[:w]; world = game.world
    if w.broken != 0
        if WB[:snapped_at] < 0
            WB[:snapped_at] = world.t
            for p in game.stage.scene.plots
                haskey(p.attributes, :name) && p.attributes[:name][] === :wirebench_end && (p.visible[] = true)
            end
            wb_redraw!(game)
            v = wb_visitor(world)
            if v === nothing
                NG.say!(world, me, "Snap! I bent it there once too often."; duration = 2.5)
            else
                if get(WB, :sleepwalk, false)
                    NG.say!(world, v, "Zzz... snap... zzz"; duration = 2.5); NG.choose_goal!(v, world)   # back to bed
                else
                    NG.say!(world, v, rand(world.rng, WB_OOPS); duration = 2.5)
                    v.action = :laugh; v.goal = NG.Goal(:wirebench, v.pos, :laugh, 3.0, world.t + 3, true, 0, false)
                end
                WB[:visitor] = 0; WB[:next_visit] = world.t + WB_GAP[1] + rand(world.rng) * (WB_GAP[2] - WB_GAP[1])
            end
            NG.emit!(world, :wire_snap; joint = w.broken, by = v === nothing ? "Lumi" : v.name)
        elseif world.t - WB[:snapped_at] > 4.0
            rng = world.rng; o = WB[:origin]
            for (r0, r1) in ((1, w.broken), (w.broken + 1, w.n))
                r1 - r0 < 2 && continue
                g = NG.ground(world.island, (o[1] + 0.5f0 + 0.15f0 * rand(rng, Float32), o[2] - 0.15f0 + 0.3f0 * rand(rng, Float32)))
                push!(WB[:scrap], (copy(w.th), r0, r1, Point3f(g[1], g[2], g[3] + 0.004f0 * length(WB[:scrap])), Float32(2pi * rand(rng))))
            end
            length(WB[:scrap]) > 40 && deleteat!(WB[:scrap], 1:2)
            WB[:scrap_obs][] = wb_scrap_mesh(game)
            WB[:w] = wb_new(); WB[:snapped_at] = -1.0; WB[:loaded] = false
            for p in game.stage.scene.plots
                haskey(p.attributes, :name) && p.attributes[:name][] === :wirebench_end && (p.visible[] = false)
            end
            wb_redraw!(game)
            NG.say!(world, me, "A fresh piece from the coil."; duration = 1.5)
        end
        return
    end
    wb_visit!(game, w, dt) && return
    free = game.minigame === nothing || game.minigame isa NG.JumpIn
    c = WB[:origin]
    near = me.controlled && free && hypot(me.pos[1] - (c[1] + 0.2f0), me.pos[2] - c[2]) < WB_NEAR
    left = WB_KEYS[1] in game.keys_down; right = WB_KEYS[2] in game.keys_down; move = WB_KEYS[3] in game.keys_down
    if near && move && !get(WB, :move_down, false)
        WB[:grip] = WB[:grip] + 6 > w.n - 4 ? 6 : WB[:grip] + 6
        WB[:loaded] && (release!(w); WB[:loaded] = false)
        wb_redraw!(game)
    end
    WB[:move_down] = move
    if near && (left ⊻ right)
        g = WB[:grip]
        bend!(w, g - 2, g + 2, (left ? 1 : -1) * WB_RATE * dt; steps = 1)
        WB[:loaded] = true
        me.action = :wave
        wb_redraw!(game)
    elseif WB[:loaded]
        release!(w); WB[:loaded] = false      # let go: the elastic part springs back
        wb_redraw!(game)
        NG.emit!(world, :wire_bend; grip = WB[:grip])
    end
    return
end

# A friend comes by now and then, picks up the wire and fiddles it back and forth with the same physics, until the
# worked spot tires and snaps (s144). It leaves after WB_FIDDLE seconds if it holds.
const WB_GAP = (400.0, 900.0)        # sim seconds between two visits
const WB_FIDDLE = 30.0
const WB_HALF = 0.9                  # seconds per bend one way
const WB_HELLO = ("Ooh, a wire!", "Is this bendy?", "What does this do?", "Lumi won't mind...")
const WB_OOPS = ("Oops! It broke!", "Uh oh. Snap!", "I didn't do it!", "It just... came apart!")
push!(NG.BUSY_GOALS, :wirebench)

wb_visitor(world) = (id = get(WB, :visitor, 0); id == 0 ? nothing : findfirst(c -> c.id == id, world.creatures) |> (i -> i === nothing ? nothing : world.creatures[i]))

"The visiting friend's turn: walk over, fiddle the wire, leave. Returns true while it has the wire."
function wb_visit!(game, w, dt)
    world = game.world
    o = WB[:origin]; spot = Point3f(o[1] + 0.2f0, o[2] - 0.55f0, 0)
    v = wb_visitor(world)
    if v === nothing
        haskey(WB, :next_visit) || (WB[:next_visit] = world.t + WB_GAP[1])
        world.t < WB[:next_visit] && return false
        any(c -> c.controlled && hypot(c.pos[1] - spot[1], c.pos[2] - spot[2]) < 3, world.creatures) && (WB[:next_visit] = world.t + 60; return false)
        cand = [c for c in world.creatures if !c.controlled && c.action !== :sleep && c.goal.kind ∉ NG.BUSY_GOALS &&
                hypot(c.pos[1] - spot[1], c.pos[2] - spot[2]) < 40]
        sleep = isempty(cand)                      # night: someone gets up in its sleep and fiddles with eyes shut
        sleep && (cand = [c for c in world.creatures if !c.controlled && c.action === :sleep && hypot(c.pos[1] - spot[1], c.pos[2] - spot[2]) < 40])
        isempty(cand) && (WB[:next_visit] = world.t + 60; return false)
        v = cand[rand(world.rng, 1:length(cand))]
        WB[:visitor] = v.id; WB[:fiddle_t0] = -1.0; WB[:sleepwalk] = sleep
        sleep && (v.action = :idle; NG.say!(world, v, "Zzz... mmh... wire..."; duration = 2.5); NG.emit!(world, :sleepwalk; who = v.name))
        v.goal = NG.Goal(:wirebench, NG.ground(world.island, (spot[1], spot[2])), :idle, WB_FIDDLE + 20, world.t + WB_FIDDLE + 60, false, 0, false)
        return false
    end
    if v.controlled || v.goal.kind !== :wirebench || (v.action === :sleep && !get(WB, :sleepwalk, false))
        WB[:visitor] = 0; WB[:next_visit] = world.t + 120; return false
    end
    hypot(v.pos[1] - spot[1], v.pos[2] - spot[2]) > 0.7 && return false
    if WB[:fiddle_t0] < 0
        WB[:fiddle_t0] = world.t; WB[:grip] = rand(world.rng, 12:w.n-12); WB[:half] = 0
        NG.say!(world, v, get(WB, :sleepwalk, false) ? "Zzz... bendy... zzz" : rand(world.rng, WB_HELLO); duration = 2.0)
        wb_redraw!(game)
    end
    ph = world.t - WB[:fiddle_t0]
    if ph > WB_FIDDLE
        release!(w); WB[:loaded] = false; wb_redraw!(game)
        NG.say!(world, v, "Tough one."; duration = 1.5)
        WB[:visitor] = 0; WB[:next_visit] = world.t + WB_GAP[1] + rand(world.rng) * (WB_GAP[2] - WB_GAP[1])
        NG.choose_goal!(v, world)
        return false
    end
    half = floor(Int, ph / WB_HALF)
    if half != WB[:half]                 # the hand lets go between two bends: springback
        release!(w); WB[:half] = half
    end
    g = WB[:grip]
    bend!(w, g - 2, g + 2, (iseven(half) ? 1 : -1) * WB_RATE * 1.3 * dt; steps = 1)
    WB[:loaded] = true
    v.action = :wave
    wb_redraw!(game)
    return true
end

register!(WireBench())
