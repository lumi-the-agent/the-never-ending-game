# Read the sand, find the stone (s149, passed idea, big goal "Sparks from stones"). A magnet stone lies buried under
# the north beach patch at (-2.4, 18.8), at a depth, a place and a pose nobody shows you. Jumped in as Lumi, stand at
# the patch: 9 sprinkles iron sand, 9 again taps the ground, and the grains stand and gather into the stone's field
# (physics/ironsand.jl: each grain an induced dipole in the stone's field from physics/em.jl and its neighbours'
# fields, friction until a tap frees it). Read the pattern, stand where you think it is and press 0 to dig: the stone
# comes up where it really was, and Lumi says how far off the dig was. Then a new stone is buried somewhere else.
using GeometryBasics, Makie, LinearAlgebra, Random
isdefined(Main, :LOCAL_CAMS) || Core.eval(Main, :(const LOCAL_CAMS = Dict{String,Any}()))
isdefined(Main, :IRONSAND) || Core.eval(Main, :(const IRONSAND = Dict{Symbol,Any}()))
const NG = NeverendingGame
const IR = Main.IRONSAND
Base.include(@__MODULE__, joinpath(@__DIR__, "..", "physics", "em.jl"))
Base.include(@__MODULE__, joinpath(@__DIR__, "..", "physics", "ironsand.jl"))

const IR_SPOT = (-2.4, 18.8)
const IR_W = 0.42                      # the patch, m
const IR_N = 1500
const IR_NEAR = 0.9
const IR_KEY = Makie.Keyboard._9
const IR_DIG = Makie.Keyboard._0
const IR_SUB = 20                      # substeps of one tap, one a frame
const IR_HIDE = Point3f(0, 0, -50)

struct IronSandToy <: System end

gz(w, x, y) = Float64(NG.ground(w.island, (Float32(x), Float32(y)))[3])

function zto(d)
    x, y, z, w = -d[2], d[1], 0.0, 1.0 + d[3]
    n = sqrt(x^2 + y^2 + z^2 + w^2)
    Makie.Quaternionf(Float32(x / n), Float32(y / n), Float32(z / n), Float32(w / n))
end

# a new stone, buried: its sand (the field grid) is built off the frame thread
function ir_bury!()
    rng = Random.MersenneTwister(round(Int, time() * 1000) % 100000)
    depth = 0.05 + 0.09rand(rng); yaw = 2pi * rand(rng); standing = rand(rng) < 0.35
    ox, oy = 0.12 * (2rand(rng) - 1), 0.12 * (2rand(rng) - 1)
    Rz = [cos(yaw) -sin(yaw) 0; sin(yaw) cos(yaw) 0; 0 0 1]
    R = standing ? Rz * [0.0 0 -1; 0 1 0; 1 0 0] : Rz
    IR[:truth] = (; ox, oy, depth, yaw, standing)
    IR[:sand] = nothing; IR[:sprinkled] = false; IR[:tap] = 0; IR[:dug] = nothing
    IR[:task] = Threads.@spawn IronSand.Sand([IronSand.stone(ox, oy, depth; R)]; N = IR_N, w = IR_W, seed = rand(rng, 1:10^6))
    IR[:R] = R
    return
end

function ir_ensure!(game)
    haskey(IR, :plots) && haskey(IR, :truth) && return
    for p in copy(game.stage.scene.plots)
        haskey(p.attributes, :name) && p.attributes[:name][] in (:ironsand_grains, :ironsand_stone) && delete!(game.stage.scene, p)
    end
    a = Float32(IronSand.Grain().a)
    marker = GeometryBasics.normal_mesh(Cylinder(Point3f(0, 0, -2.6a), Point3f(0, 0, 2.6a), a))
    pg = meshscatter!(game.stage.scene, fill(IR_HIDE, IR_N); marker, markersize = 1f0, rotation = fill(Makie.Quaternionf(0, 0, 0, 1), IR_N),
                      color = RGBf(0.07, 0.07, 0.08), name = :ironsand_grains,
                      material = NG.Hikari.Diffuse(color = (0.07, 0.07, 0.08), roughness = 0.45f0))
    h = (0.07f0, 0.055f0, 0.045f0)
    blk = GeometryBasics.normal_mesh(Rect3f(Point3f(-h[1], -h[2], -h[3]), Vec3f(2h[1], 2h[2], 2h[3])))
    ps = mesh!(game.stage.scene, blk; color = RGBf(0.16, 0.15, 0.17), name = :ironsand_stone, visible = false,
               material = NG.Hikari.Diffuse(color = (0.16, 0.15, 0.17), roughness = 0.7f0))
    IR[:plots] = (pg, ps)
    Main.LOCAL_KEYS["ironsand"] = g -> get(IR, :near, false) ? (get(IR, :sprinkled, false) ? "9 tap the sand   0 dig here" : "9 sprinkle iron sand") : nothing
    # the patch is 42 cm wide: the chase camera behind Lumi never sees it (and Lumi is taller than the patch is wide).
    # While Lumi is here, look from the sea side down onto the patch, Lumi behind it
    Main.LOCAL_CAMS["ironsand"] = g -> (get(IR, :near, false) && g.minigame isa NG.JumpIn) ?
        (Point3f(IR_SPOT[1] + 0.25, IR_SPOT[2] + 0.75, gz(g.world, IR_SPOT...) + 1.55), Point3f(IR_SPOT[1], IR_SPOT[2] - 0.12, gz(g.world, IR_SPOT...) + 0.05)) : nothing
    ir_bury!()
    return
end

function ir_draw!(w)
    S = IR[:sand]; pg = IR[:plots][1]
    if S === nothing || !IR[:sprinkled]
        Makie.update!(pg; arg1 = fill(IR_HIDE, IR_N)); return
    end
    a = S.g.a; k = IR[:tap]
    hop = k > 0 ? 0.004 * 4 * (k / IR_SUB) * (1 - k / IR_SUB) : 0.0      # the tap throws the grains ~4 mm
    dirs = IR[:flat] === nothing ? S.dir : IR[:flat]
    pos = Vector{Point3f}(undef, IR_N); rot = Vector{Makie.Quaternionf}(undef, IR_N)
    for i in 1:IR_N
        p = S.pos[i]; d = dirs[i]
        x = IR_SPOT[1] + p[1]; y = IR_SPOT[2] + p[2]
        pos[i] = Point3f(x, y, gz(w, x, y) + a + 2.6a * d[3] + hop)
        rot[i] = zto(d)
    end
    Makie.update!(pg; arg1 = pos, rotation = rot)
end

function NG.step!(::IronSandToy, game, dt)
    game.stage === nothing && return
    me = NG.creature(game.world, "Lumi")
    me === nothing && return
    ir_ensure!(game)
    w = game.world
    if IR[:sand] === nothing && istaskdone(IR[:task])
        IR[:sand] = fetch(IR[:task])                    # a failed build throws here, on purpose
    end
    free = game.minigame === nothing || game.minigame isa NG.JumpIn
    near = me.controlled && free && hypot(me.pos[1] - IR_SPOT[1], me.pos[2] - IR_SPOT[2]) < IR_NEAR
    IR[:near] = near
    S = IR[:sand]
    t0 = time_ns()
    down = IR_KEY in game.keys_down
    if near && down && !get(IR, :down, false) && S !== nothing && IR[:dug] === nothing && IR[:tap] == 0
        if !IR[:sprinkled]
            IR[:sprinkled] = true
            IR[:flat] = [(cos(t), sin(t), 0.0) for t in 2pi .* rand(IR_N)]   # as they land: flat, any way round
            NG.say!(w, me, "Iron sand! Now a little tap..."; duration = 1.6)
            NG.emit!(w, :ironsand_sprinkle)
        else
            IR[:tap] = 1
            NG.emit!(w, :ironsand_tap)
        end
    end
    IR[:down] = down
    if S !== nothing && IR[:tap] > 0
        IronSand.substep!(S)
        IR[:tap] += 1
        if IR[:tap] > IR_SUB
            IronSand.orient!(S); IR[:flat] = nothing; IR[:tap] = 0
        end
    end
    dig = IR_DIG in game.keys_down
    if near && dig && !get(IR, :digdown, false) && IR[:dug] === nothing && get(IR, :sprinkled, false)
        tr = IR[:truth]
        bx = me.pos[1] + 0.3cos(me.yaw) - IR_SPOT[1]; by = me.pos[2] + 0.3sin(me.yaw) - IR_SPOT[2]
        off = hypot(bx - tr.ox, by - tr.oy)
        IR[:dug] = time()
        ps = IR[:plots][2]
        x = IR_SPOT[1] + tr.ox; y = IR_SPOT[2] + tr.oy
        q = Makie.qrotation(Vec3f(0, 0, 1), Float32(tr.yaw))                # the stone as it lay: pole axis turned by yaw,
        tr.standing && (q = q * Makie.qrotation(Vec3f(0, 1, 0), -Float32(pi / 2)))   # and stood up on end
        Makie.rotate!(ps, q)
        Makie.translate!(ps, Vec3f(x, y, gz(w, x, y) + (tr.standing ? 0.07 : 0.045)))
        ps.visible[] = true
        cm = round(Int, 100off); dcm = round(Int, 100tr.depth)
        NG.say!(w, me, off < 0.06 ? "Found it! $(dcm) cm down, $(tr.standing ? "standing up" : "lying on its side")." :
                                     "Not here... it was $(cm) cm off, $(dcm) cm down."; duration = 3.0)
        NG.emit!(w, off < 0.06 ? :ironsand_found : :ironsand_missed)
        NG.feel!(w, me, off < 0.06 ? :proud : :gasp)
    end
    IR[:digdown] = dig
    if IR[:dug] !== nothing && time() - IR[:dug] > 6.0
        IR[:plots][2].visible[] = false
        ir_bury!()
    end
    ir_draw!(w)
    IR[:ms] = (time_ns() - t0) / 1e6
    return
end

function NG.stop!(::IronSandToy, game)
    game.stage === nothing && return
    for p in copy(game.stage.scene.plots)
        haskey(p.attributes, :name) && p.attributes[:name][] in (:ironsand_grains, :ironsand_stone) && delete!(game.stage.scene, p)
    end
    delete!(IR, :plots)
end

register!(IronSandToy())
