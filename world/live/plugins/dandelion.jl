# Dandelion clocks (s136). Jumped in as Lumi, press I: Lumi blows a dandelion clock and its 48 seeds fly. Each seed
# is a 0.6 mg body under a feathery parachute (pappus): it falls at ~0.3 m/s in still air, so its drag time is
# tiny (tau = v_t / g ~ 0.03 s) and it rides whatever air it is in: the island's breeze (plugins/wind.jl), plus
# slow eddies that lift some seeds high and drop others. The blow gives them a puff out of Lumi's beak; after that
# only gravity and the air move them. A seed that touches the ground stays where it landed for a while.
using GeometryBasics, Makie, Random
isdefined(Main, :DANDELION) || Core.eval(Main, :(const DANDELION = Dict{Symbol,Any}()))
const NG = NeverendingGame
const DD = Main.DANDELION

const DD_HIDE = Point3f(0, 0, -50)
const DD_N = 144            # seeds alive at most (three clocks)
const DD_PER = 48           # seeds on one clock
const DD_VT = 0.3f0         # terminal fall speed in still air, m/s (dandelion pappus, Cummins et al. 2018: ~0.3-0.4)
const DD_TAU = DD_VT / 9.81f0
const DD_REST = 25f0        # seconds a landed seed stays

struct Dandelion <: System end

function dd_build!(game)
    haskey(DD, :plot) && DD[:plot].parent !== nothing && delete!(DD[:plot].parent, DD[:plot])
    DD[:plot] = meshscatter!(game.stage.scene, fill(DD_HIDE, DD_N); marker = NG.shape(:glowdot), markersize = fill(0f0, DD_N),
        color = RGBf(0.97, 0.96, 0.92), material = NG.Hikari.Diffuse(color = (0.97, 0.96, 0.92)), name = :dandelion_seeds)
    DD[:pos] = fill(DD_HIDE, DD_N); DD[:vel] = fill(Vec3f(0), DD_N); DD[:age] = fill(-1f0, DD_N)
    DD[:landed] = fill(false, DD_N); DD[:phase] = rand(Float32, DD_N) .* 100f0; DD[:next] = 1; DD[:idown] = false
end

"The island's breeze where a seed is, plus slow eddies (smooth in space and time) that carry seeds up and down."
function dd_air(w, p, ph, t)
    base = if isdefined(Main, :WIND) && haskey(Main.WIND, :now)
        d, s = Base.invokelatest(Main.WIND[:now], w.t)
        1.6f0 * Float32(s) * Vec3f(d[1], d[2], 0)
    else
        Vec3f(0.8f0, 0.3f0, 0)
    end
    e = Vec3f(0.5f0 * sin(0.9f0 * p[2] + 0.7f0 * t + ph), 0.5f0 * sin(0.8f0 * p[1] - 0.6f0 * t + 1.3f0 * ph),
              0.75f0 * sin(0.5f0 * p[1] + 0.6f0 * p[2] + 0.9f0 * t + ph))   # s136 first try: 0.45 brought all 48 down within ~3 s
    return base + e
end

function dd_blow!(w, me)
    yaw = me.yaw + NG.species_of(me).heading
    f = Vec3f(cos(yaw), sin(yaw), 0)
    head = Point3f(me.pos) + 0.45f0 * f + Point3f(0, 0, 1.15f0)
    for _ in 1:DD_PER
        k = DD[:next]; DD[:next] = mod1(k + 1, DD_N)
        u = normalize(Vec3f(randn(Float32), randn(Float32), randn(Float32)))
        DD[:pos][k] = head + 0.05f0 * u
        DD[:vel][k] = (1.5f0 + 1.5f0 * rand(Float32)) * normalize(f + 0.6f0 * u) + Vec3f(0, 0, 0.4f0)   # the puff
        DD[:age][k] = 0f0; DD[:landed][k] = false
    end
    NG.say!(w, me, rand(("Make a wish!", "Fffffff...", "Fly, little seeds!")); duration = 1.8)
    NG.emit!(w, :dandelion_blown)
end

function NG.step!(::Dandelion, game, dt)
    game.stage === nothing && return
    (haskey(DD, :plot) && DD[:plot].parent === game.stage.scene) || dd_build!(game)
    w = game.world
    me = NG.creature(w, "Lumi")
    me === nothing && return
    idown = Makie.Keyboard.i in game.keys_down
    idown && !DD[:idown] && me.controlled && dd_blow!(w, me)
    DD[:idown] = idown
    any(>=(0f0), DD[:age]) || return
    h = Float32(min(dt, 0.05)) / 4
    t = Float32(NG.anim_time(w))
    pos, vel, age, landed, ph = DD[:pos], DD[:vel], DD[:age], DD[:landed], DD[:phase]
    ms = fill(0f0, DD_N)
    for k in 1:DD_N
        age[k] < 0 && continue
        if !landed[k]
            p, v = pos[k], vel[k]
            for _ in 1:4   # linear drag towards the air's velocity (implicit, so the short tau is stable), gravity
                air = dd_air(w, p, ph[k], t)
                v = (v + (h / DD_TAU) * (air - Vec3f(0, 0, DD_VT))) / (1 + h / DD_TAU)
                p = p + h * v
            end
            g = max(NG.terrain_height(w.island, p[1], p[2]), 0f0)
            if p[3] <= g + 0.01f0
                p = Point3f(p[1], p[2], g + 0.01f0); landed[k] = true; age[k] = 0f0
            end
            pos[k], vel[k] = p, v
        end
        age[k] += Float32(dt)
        if (landed[k] && age[k] > DD_REST) || age[k] > 90f0
            age[k] = -1f0; pos[k] = DD_HIDE
            continue
        end
        ms[k] = landed[k] ? 0.018f0 * clamp((DD_REST - age[k]) / 3f0, 0f0, 1f0) : 0.025f0
    end
    Makie.update!(DD[:plot]; arg1 = copy(pos), markersize = ms)
    return
end

register!(Dandelion())
