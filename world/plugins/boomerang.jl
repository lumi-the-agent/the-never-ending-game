# A boomerang that comes back (s136). Jumped in as Lumi, press O: Lumi throws a carved boomerang the way it faces,
# upright, tipped 15 degrees, spinning. Its flight is physics/boomerang.jl: every substep each bit of its two wings
# gets lift and drag from its own air speed (body speed + spin x radius - wind), the advancing wing lifts more, the
# spinning body precesses, and that bends the flight into a loop. Nothing steers it. If it comes back within reach
# Lumi catches it; otherwise it lands and lies there until Lumi picks it up (walk to it) or throws again.
# Thrown into the wind it loops tighter; over trees it does not care (it only meets the ground).
using GeometryBasics, Makie, LinearAlgebra
isdefined(Main, :BOOMERANG) || Core.eval(Main, :(const BOOMERANG = Dict{Symbol,Any}()))
const NG = NeverendingGame
const BG = Main.BOOMERANG
isdefined(Main, :BoomerangPhysics) || Core.eval(Main, :(module BoomerangPhysics end))
isdefined(Main.BoomerangPhysics, :boomerang_step!) || Base.include(Main.BoomerangPhysics, joinpath(@__DIR__, "..", "physics", "boomerang.jl"))
const BP = Main.BoomerangPhysics

const BG_HIDE = Point3f(0, 0, -50)
const BG_SUB = 24              # substeps per frame (dt ~1.4 ms at 30 fps; 120 rad/s spin turns 10 deg per substep)
const BG_REACH = 1.1f0         # m: a boomerang this close to Lumi's hand after 1.5 s of flight is caught

struct Boomerang <: System end

function bg_mesh(shape; thick = 0.012f0)
    pts = Point3f[]; fs = GLTriangleFace[]
    d1 = Vec3f(shape.s[1]); n = length(shape.p) ÷ 2
    elbow = Vec3f(shape.p[1]) - Float32(shape.ds / 2) * d1
    for d in (d1, Vec3f(shape.s[n + 1]))
        c = normalize(cross(Vec3f(0, 0, 1), d)) * Float32(shape.chord / 2)
        L = Float32(shape.arm)
        corners = [elbow - c, elbow + c, elbow + L * d + 0.75f0 * c, elbow + L * d - 0.75f0 * c]
        base = length(pts)
        for q in corners, z in (-thick / 2, thick / 2)
            push!(pts, Point3f(q + Vec3f(0, 0, z)))
        end
        b(i, top) = base + 2(i - 1) + (top ? 2 : 1)
        push!(fs, GLTriangleFace(b(1, true), b(2, true), b(3, true)), GLTriangleFace(b(1, true), b(3, true), b(4, true)))
        push!(fs, GLTriangleFace(b(1, false), b(3, false), b(2, false)), GLTriangleFace(b(1, false), b(4, false), b(3, false)))
        for i in 1:4
            j = mod1(i + 1, 4)
            push!(fs, GLTriangleFace(b(i, false), b(j, false), b(j, true)), GLTriangleFace(b(i, false), b(j, true), b(i, true)))
        end
    end
    GeometryBasics.normal_mesh(GeometryBasics.Mesh(pts, fs))
end

function bg_quat(m)
    tr_ = m[1, 1] + m[2, 2] + m[3, 3]
    if tr_ > 0
        s = 2sqrt(tr_ + 1); w = s / 4; x = (m[3, 2] - m[2, 3]) / s; y = (m[1, 3] - m[3, 1]) / s; z = (m[2, 1] - m[1, 2]) / s
    elseif m[1, 1] > m[2, 2] && m[1, 1] > m[3, 3]
        s = 2sqrt(1 + m[1, 1] - m[2, 2] - m[3, 3]); w = (m[3, 2] - m[2, 3]) / s; x = s / 4; y = (m[1, 2] + m[2, 1]) / s; z = (m[1, 3] + m[3, 1]) / s
    elseif m[2, 2] > m[3, 3]
        s = 2sqrt(1 + m[2, 2] - m[1, 1] - m[3, 3]); w = (m[1, 3] - m[3, 1]) / s; x = (m[1, 2] + m[2, 1]) / s; y = s / 4; z = (m[2, 3] + m[3, 2]) / s
    else
        s = 2sqrt(1 + m[3, 3] - m[1, 1] - m[2, 2]); w = (m[2, 1] - m[1, 2]) / s; x = (m[1, 3] + m[3, 1]) / s; y = (m[2, 3] + m[3, 2]) / s; z = s / 4
    end
    Makie.Quaternionf(x, y, z, w)
end

function bg_build!(game)
    haskey(BG, :plot) && BG[:plot].parent !== nothing && delete!(BG[:plot].parent, BG[:plot])
    BG[:shape] = BP.boomerang_shape()
    BG[:plot] = meshscatter!(game.stage.scene, [BG_HIDE]; marker = bg_mesh(BG[:shape]), markersize = 1f0,
        rotation = [Makie.Quaternionf(0, 0, 0, 1)], color = RGBf(0.66, 0.38, 0.17),
        material = NG.Hikari.Plastic(color = (0.66, 0.38, 0.17), roughness = 0.3), name = :boomerang_wood)
    BG[:fly] = nothing; BG[:rest] = nothing; BG[:odown] = false
end

bg_hand(me) = BP.V3(me.pos[1], me.pos[2], me.pos[3] + 0.9)

"The island's breeze (plugins/wind.jl: a direction and a strength ~0.5-1.3, here x 1 m/s: light air)."
function bg_wind(w)
    isdefined(Main, :WIND) && haskey(Main.WIND, :now) || return BP.V3(0, 0, 0)
    d, strength = Base.invokelatest(Main.WIND[:now], w.t)
    return 1.0 * strength * BP.V3(d[1], d[2], 0)   # light air: the loop drifts downwind ~ wind x 4 s
end

function bg_throw!(w, me)
    heading = Float64(me.yaw + NG.species_of(me).heading)
    BG[:fly] = (body = BP.boomerang_release(BG[:shape]; at = bg_hand(me), heading, speed = 20.0 + 3rand(),
                                            spin = 115.0 + 10rand(), layover = 15.0, aim = 2.0), t = 0.0, far = 0.0)
    BG[:rest] = nothing
    NG.say!(w, me, rand(("Come back to me!", "Wheee... and back!", "Watch it turn!")); duration = 1.6)
    NG.emit!(w, :boomerang_throw)
end

function bg_step!(w, me, dt)
    s = BG[:fly]
    s === nothing && return
    b = s.body
    h = dt / BG_SUB
    wv = bg_wind(w)
    for _ in 1:BG_SUB
        BP.boomerang_step!(b, h; wind = wv)
    end
    t = s.t + dt
    hand = bg_hand(me)
    d = hypot(b.x[1] - hand[1], b.x[2] - hand[2])
    BG[:fly] = (body = b, t, far = max(s.far, d))
    if t > 1.5 && d < BG_REACH && abs(b.x[3] - hand[3]) < 1.4
        BG[:fly] = nothing; BG[:last] = (:caught, round(t, digits = 2), round(s.far, digits = 1))
        me.action = :wave
        NG.say!(w, me, rand(("Caught it!", "Got it! It came BACK!", "Ha! Right to me.")); duration = 2.0)
        NG.emit!(w, :boomerang_caught; far = round(s.far, digits = 1), seconds = round(t, digits = 1))
        return
    end
    terr = NG.terrain_height(w.island, b.x[1], b.x[2])
    land = max(terr, 0f0)                                # the sea's surface is z = 0; wood floats
    if b.x[3] <= land + 0.02 || t > 12
        BG[:fly] = nothing; BG[:last] = (:landed, round(t, digits = 2), round(s.far, digits = 1), round(d, digits = 1))
        BG[:rest] = (Point3f(b.x[1], b.x[2], land + 0.01f0), BP.M3(BP.I3))   # lies flat where it came down
        NG.say!(w, me, terr < 0 ? "Splash. It's in the sea." :
                       s.far > 10 ? "The breeze pushed it $(round(Int, d)) m off. Throw it with the wind!" :
                       "It landed $(round(Int, d)) m away."; duration = 2.4)
        NG.emit!(w, :boomerang_landed; far = round(s.far, digits = 1))
    end
end

function NG.step!(::Boomerang, game, dt)
    game.stage === nothing && return
    (haskey(BG, :plot) && BG[:plot].parent === game.stage.scene) || bg_build!(game)
    w = game.world
    me = NG.creature(w, "Lumi")
    me === nothing && return
    odown = Makie.Keyboard.o in game.keys_down
    odown && !BG[:odown] && me.controlled && BG[:fly] === nothing && bg_throw!(w, me)
    BG[:odown] = odown
    NG.path_traced(game) || bg_step!(w, me, min(Float64(dt), 0.05))
    r = BG[:rest]
    if r !== nothing && hypot(r[1][1] - me.pos[1], r[1][2] - me.pos[2]) < 0.8   # walked to it: picked up
        BG[:rest] = nothing
        NG.say!(w, me, "Got my boomerang back."; duration = 1.5)
    end
    fly = BG[:fly]
    if fly !== nothing
        Makie.update!(BG[:plot]; arg1 = [Point3f(fly.body.x)], rotation = [bg_quat(fly.body.R)])
    elseif r !== nothing
        Makie.update!(BG[:plot]; arg1 = [r[1]], rotation = [bg_quat(r[2])])
    else
        Makie.update!(BG[:plot]; arg1 = [BG_HIDE], rotation = [Makie.Quaternionf(0, 0, 0, 1)])
    end
    return
end

register!(Boomerang())
