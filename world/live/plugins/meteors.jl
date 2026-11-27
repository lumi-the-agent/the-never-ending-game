# Shooting stars (s133): at night, every 25-70 s, a meteor streaks across the sky dome and burns out. Its light
# follows a meteor's light curve: it brightens as it sinks into thicker air and ablates faster, peaks about two thirds
# along, and is gone (b ~ sin(pi (t/T)^1.5)). A glowing head with a fading train of 28 points behind it. Friends who
# are awake turn to where it fell and make a wish. Main.METEORS[:force] = true sends one now.
isdefined(Main, :METEORS) || Core.eval(Main, :(const METEORS = Dict{Symbol,Any}()))
const NG = NeverendingGame
const MT = Main.METEORS
const MT_N = 28            # points in the train
const MT_LAG = 0.014       # s between train points
const MT_WISHES = ("A shooting star! Quick, wish!", "I wish for more berries.", "Did you see that?!",
                   "I wished for snow.", "Ooh! Make a wish!", "I wish everyone could fly.", "There! It fell over the sea!")

mutable struct Meteors <: System
    next::Float64
    t0::Float64
    dur::Float64
    a::Float32; e::Float32; da::Float32; de::Float32
    on::Bool
end

function mt_build!(game)
    haskey(MT, :plot) && MT[:plot].parent !== nothing && delete!(MT[:plot].parent, MT[:plot])
    MT[:plot] = meshscatter!(game.stage.scene, fill(Point3f(0, 0, -500), MT_N); marker = NG.shape(:sphere),
        markersize = fill(0.01f0, MT_N), color = RGBf(1.0, 0.95, 0.85), shading = Makie.NoShading,
        material = NG.Hikari.Emission(color = (1.0, 0.95, 0.85), strength = 6.0), visible = false, name = :meteor_train)
    MT[:scene] = game.stage.scene
end

mt_point(R, a, e) = Point3f(R * cos(e) * cos(a), R * cos(e) * sin(a), R * sin(e))

function mt_launch!(sys::Meteors, w)
    sys.a = haskey(MT, :az) ? Float32(pop!(MT, :az)) : Float32(2pi * rand()); sys.e = Float32(deg2rad(40 + 30rand()))
    sys.da = Float32((rand(Bool) ? 1 : -1) * deg2rad(12 + 18rand()))     # across the sky
    sys.de = Float32(-deg2rad(10 + 14rand()))                            # and down
    sys.dur = 0.7 + 0.6rand(); sys.t0 = w.t; sys.on = true
    MT[:plot].visible[] = true
    # friends who are awake look to where it falls; one or two make a wish
    fall = sys.a + sys.da
    seen = 0
    for c in NG.Random.shuffle(w.creatures)
        (c.action === :sleep || c.controlled) && continue
        c.yaw = NG.wrap_angle(Float32(fall))
        seen < 2 && rand() < 0.7 && (NG.say!(w, c, rand(MT_WISHES)); seen += 1)
    end
    NG.emit!(w, :meteor_seen; watchers = seen)
end

function NG.step!(sys::Meteors, game, dt)
    game.stage === nothing && return
    (haskey(MT, :plot) && get(MT, :scene, nothing) === game.stage.scene) || mt_build!(game)
    w = game.world
    p = MT[:plot]
    if NG.path_traced(game)                    # moving glowing points would leak lights in the tracer
        p.visible[] && (p.visible[] = false)
        return
    end
    night = NG.night_factor(w) > 0.6f0
    if !sys.on
        if get(MT, :force, false) || (night && w.t >= sys.next)
            MT[:force] = false
            mt_launch!(sys, w)
        else
            night || (sys.next = max(sys.next, w.t + 20))
            return
        end
    end
    R = 3.6f0 * w.island.radius
    t = w.t - sys.t0
    if t > sys.dur + MT_N * MT_LAG
        sys.on = false; p.visible[] = false
        sys.next = w.t + 25 + 45rand()
        return
    end
    pos = Vector{Point3f}(undef, MT_N); sz = Vector{Float32}(undef, MT_N)
    for k in 1:MT_N
        tk = t - (k - 1) * MT_LAG
        u = clamp(tk / sys.dur, 0.0, 1.0)
        b = (0 < tk < sys.dur) ? Float32(sin(pi * u^1.5)) : 0f0        # the light curve
        pos[k] = mt_point(R, sys.a + sys.da * Float32(u), sys.e + sys.de * Float32(u))
        sz[k] = R * 0.0042f0 * b * (1 - (k - 1) / MT_N)^1.3f0            # the train thins and fades behind the head
    end
    Makie.update!(p; arg1 = pos, markersize = sz)
end

function NG.stop!(sys::Meteors, game)
    haskey(MT, :plot) && (MT[:plot].visible[] = false)
end

register!(Meteors(0.0, 0.0, 1.0, 0f0, 0f0, 0f0, 0f0, false))
