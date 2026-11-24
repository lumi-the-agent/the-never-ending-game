# The watering can (wish: "a watering can that leaves a little shine on the flowers I water"):
# while Lumi waters its patch (garden.jl goal :tend, arrived at the gate) it faces the rows, lifts the
# can from beside the gate, and a stream of drops arcs from the spout onto the nearest row. Where
# the water fell the plants keep a little shine: gold-white glints that twinkle for a minute, then fade.
# Two meshscatters (drops, glints), one instance each hidden while unused (the raster cannot draw an
# empty meshscatter); the can plot of garden.jl is only translated, never rebuilt.
isdefined(Main, :WATERING) || Core.eval(Main, :(const WATERING = Dict{Symbol,Any}()))

const NG = NeverendingGame
const WT = Main.WATERING
const N_DROPS = 28
const N_GLINTS = 30
const SHINE_TIME = 60.0          # s the glints twinkle after a watering
const DROP = RGBAf(0.62, 0.84, 1.0, 0.9)
const GLINT = RGBf(1.0, 0.95, 0.7)

struct Watering <: System end

lumi(w) = (i = findfirst(c -> c.name == "Lumi", w.creatures); i === nothing ? nothing : w.creatures[i])
garden(game) = game.plugins["garden"].mod
watering(me) = me !== nothing && !me.controlled && me.goal.kind === :tend && me.goal.arrived &&
    !get(Main.GARDEN, :detour, false)

"Where the drops land: spots along the front row (the one nearest the gate)."
function row_spots(game)
    gm = garden(game)
    (cx, cy) = gm.SPOT
    is = game.world.island
    y = cy + gm.ROWS[1]
    [Point3f(x, y, NG.terrain_height(is, x, y) + 0.05f0) for x in range(cx - 0.6f0 * gm.W_HALF, cx + 0.6f0 * gm.W_HALF; length = 7)]
end

function build!(game)
    sc = game.stage.scene
    foreach(p -> p.parent === sc && delete!(sc, p), values(get(WT, :plots, Dict())))
    hide = [Point3f(0, 0, -50)]
    WT[:plots] = Dict{Symbol,Any}(
        :drops => meshscatter!(sc, hide; marker = NG.shape(:sphere), markersize = Vec3f(0), color = DROP,
                               transparency = true, name = :watering_drops),
        :glints => meshscatter!(sc, hide; marker = NG.shape(:sphere), markersize = Vec3f(0), color = GLINT,
                                shading = NoShading, name = :watering_glints))
    WT[:scene] = objectid(sc)
    WT[:shown] = (false, false)
    WT[:can_at] = nothing
end

function NG.start!(::Watering, game)
    game.stage === nothing && return
    build!(game)
    WT[:shine_until] = -Inf
    WT[:spots] = Point3f[]
    return
end

"Turns Lumi to the rows and gives the spout's position (in front of it, at hand height)."
function hold_can!(game, me)
    gm = garden(game)
    (cx, cy) = gm.SPOT
    a = atan(cy + gm.ROWS[1] - me.pos[2], cx - me.pos[1])
    me.yaw = a - NG.species_of(me).heading
    f = Vec3f(cos(a), sin(a), 0)
    side = Vec3f(-f[2], f[1], 0)
    hand = Point3f(me.pos) + 0.26f0 * f - 0.3f0 * side + Vec3f(0, 0, 0.18f0)   # at the right arm nub
    return hand, f
end

"""Moves garden.jl's can plot so its base sits at `p`, tipped forward by `tilt` radians about the
horizontal `axis` (pouring), or home again with `nothing`. Makie draws T + R * x, so a can tipped
round its own base needs T = p - R * home."""
function move_can!(p; tilt = 0.0f0, axis = Vec3f(1, 0, 0))
    cans = get(Main.GARDEN, :can, nothing)
    (cans === nothing || isempty(cans)) && return
    # a rebuilt can plot (garden.jl) starts untransformed
    get(WT, :can_obj, nothing) === objectid(cans[1]) || (WT[:can_obj] = objectid(cans[1]); WT[:can_at] = nothing)
    home = get(WT, :can_home_pos, nothing)      # the can's spot by the gate, as garden.jl places it
    home === nothing && return
    q = Makie.qrotation(axis, Float32(p === nothing ? 0 : tilt))
    T = p === nothing ? Vec3f(0) : Vec3f(p) - Vec3f(q * Vec3f(home))
    key = (T, q)
    WT[:can_at] == key && return
    foreach(c -> (Makie.rotate!(c, q); translate!(c, T)), cans)
    WT[:can_at] = key
end

function NG.step!(::Watering, game, dt)
    game.stage === nothing && return
    haskey(game.plugins, "garden") && haskey(Main.GARDEN, :can) || return
    objectid(game.stage.scene) == get(WT, :scene, nothing) || build!(game)
    w = game.world
    gm = garden(game)
    (cx, cy) = gm.SPOT
    is = w.island
    hx, hy = cx + 0.75f0, cy - gm.D_HALF - 0.5f0
    WT[:can_home_pos] = Point3f(hx, hy, NG.terrain_height(is, hx, hy))
    me = lumi(w)
    P = WT[:plots]
    t = Float32(w.t)
    if watering(me)
        hand, f = hold_can!(game, me)
        # tipped towards the rows, rocking a little as it pours
        side = Vec3f(-f[2], f[1], 0)
        move_can!(hand - Vec3f(0, 0, 0.05f0); tilt = 0.5f0 + 0.08f0 * sin(4.0f0 * t), axis = side)
        spots = row_spots(game)
        WT[:spots] = spots
        WT[:shine_until] = w.t + SHINE_TIME
        # a stream: each drop runs from the spout to a spot on the row in 0.7 s, staggered
        spout = hand + 0.16f0 * f + Vec3f(0, 0, 0.08f0)
        ps = Point3f[]
        for i in 1:N_DROPS
            s = mod(t / 0.7f0 + i / N_DROPS, 1.0f0)
            k = mod1(i + 3 * floor(Int, t / 0.7f0 + i / N_DROPS), length(spots))
            q = spots[mod1(k, length(spots))]
            p = spout + s * (q - spout)
            push!(ps, p + Vec3f(0, 0, 0.5f0 * s * (1 - s)))
        end
        P[:drops][1] = ps
        P[:drops].markersize = Vec3f(0.018f0, 0.018f0, 0.03f0)
        WT[:shown] = (true, WT[:shown][2])
    else
        move_can!(nothing)
        if WT[:shown][1]
            P[:drops][1] = [Point3f(0, 0, -50)]; P[:drops].markersize = Vec3f(0)
            WT[:shown] = (false, WT[:shown][2])
        end
    end
    # the shine: glints over the watered row, each twinkling on its own beat, fading out at the end
    left = WT[:shine_until] - w.t
    if left > 0 && !isempty(WT[:spots])
        fade = Float32(min(1.0, left / 15.0))
        spots = WT[:spots]
        ps = Point3f[]; ms = Vec3f[]
        for i in 1:N_GLINTS
            q = spots[mod1(i, length(spots))]
            ph = 2.399f0 * i
            off = Vec3f(0.22f0 * cos(ph), 0.12f0 * sin(1.7f0 * ph), 0.12f0 + 0.18f0 * mod(0.61f0 * i, 1.0f0))
            tw = 0.35f0 + 0.65f0 * max(0.0f0, sin(3.1f0 * t + ph))^3
            push!(ps, q + off); push!(ms, Vec3f(0.04f0 * tw * fade))
        end
        P[:glints][1] = ps
        P[:glints].markersize = ms
        WT[:shown] = (WT[:shown][1], true)
    elseif WT[:shown][2]
        P[:glints][1] = [Point3f(0, 0, -50)]; P[:glints].markersize = Vec3f(0)
        WT[:shown] = (WT[:shown][1], false)
    end
    return
end

function NG.stop!(::Watering, game)
    game.stage === nothing && return
    move_can!(nothing)
    sc = game.stage.scene
    foreach(p -> p.parent === sc && delete!(sc, p), values(get(WT, :plots, Dict())))
    empty!(get(WT, :plots, Dict()))
    delete!(WT, :scene)
end

register!(Watering())
