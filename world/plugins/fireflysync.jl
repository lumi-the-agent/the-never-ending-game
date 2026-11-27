# Fireflies that learn your rhythm (s131). At night 300 fireflies hover over the pond meadow, each flashing on its
# own clock (pulse-coupled oscillators, physics/fireflies.jl: every flash a fly sees nudges its phase). Jumped in as
# Lumi, press F to flash your lantern. Flash on the field's own beat (about twice a second) and steadily, and the
# flies near you lock to it, their neighbours follow them, and the meadow flashes as one; flash too fast, too slow
# or unevenly and they ignore you. Lumi leads them by itself now and then when nobody plays.
using GeometryBasics, Makie
const NG = NeverendingGame

isdefined(Main, :FIREFLYSYNC) || Core.eval(Main, :(const FIREFLYSYNC = Dict{Symbol,Any}()))
const FY = Main.FIREFLYSYNC
const FYP = Module(:FireflyPhysicsLive)
Base.include(FYP, joinpath(@__DIR__, "..", "physics", "fireflies.jl"))

const FY_N = 300
const FY_SPOT = (-4f0, 13f0)
const FY_HIDE = Point3f(0, 0, -50)
const FY_SIZE = 0.075f0
const FY_AUTO_EVERY = 120.0     # seconds between Lumi's own lantern rounds
const FY_AUTO_LEN = 18.0
const FY_BEAT = 0.55            # Lumi's own beat

struct FireflySync <: System end

fy_glow(age) = age < 0.16f0 ? exp(-age / 0.05f0) : 0f0   # short flashes: once in step the meadow goes dark between beats

function fy_build!(game)
    w = game.world
    for k in (:plot, :lamp)                 # a reload: the old plots go (plot names must stay unique)
        haskey(FY, k) && FY[k].parent !== nothing && delete!(FY[k].parent, FY[k])
    end
    gr = (x, y) -> Float32(max(NG.ground(w.island, (x, y))[3], -0.05f0))
    FY[:sw] = FYP.ff_swarm(FY_SPOT, FY_N; spread = (8f0, 5f0), seed = 3, ground = gr)
    ball = GeometryBasics.normal_mesh(GeometryBasics.Tessellation(GeometryBasics.Sphere(Point3f(0), 1f0), 6))
    FY[:plot] = meshscatter!(game.stage.scene, fill(FY_HIDE, FY_N); marker = ball, markersize = zeros(Float32, FY_N),
        color = RGBf(0.8, 1.0, 0.35), shading = Makie.NoShading,
        material = NG.Hikari.Emission(color = (0.8, 1.0, 0.35), strength = 6.0), name = :fireflysync)
    FY[:lamp] = meshscatter!(game.stage.scene, [FY_HIDE]; marker = ball, markersize = [0f0],
        color = RGBf(1.0, 0.72, 0.35), shading = Makie.NoShading,
        material = NG.Hikari.Emission(color = (1.0, 0.72, 0.35), strength = 12.0), name = :fireflylamp)
    FY[:fdown] = false; FY[:lamp_t] = -10.0; FY[:auto_until] = 0.0; FY[:auto_next] = time() + 30.0
    FY[:auto_ph] = 0.0; FY[:synced] = false; FY[:order] = 0.0
end

function fy_hide!()
    Makie.update!(FY[:plot]; arg1 = fill(FY_HIDE, FY_N), markersize = zeros(Float32, FY_N))
    Makie.update!(FY[:lamp]; arg1 = [FY_HIDE], markersize = [0f0])
end

function NG.step!(::FireflySync, game, dt)
    game.stage === nothing && return
    # every reload includes physics/fireflies.jl into a NEW module: a swarm kept in Main.FIREFLYSYNC from the old one
    # has the old Swarm type and ff_step! has no method for it (s131: switched off after the first reload)
    (haskey(FY, :plot) && FY[:plot].parent === game.stage.scene && get(FY, :sw, nothing) isa FYP.Swarm) || fy_build!(game)
    NG.path_traced(game) && return          # moving glowing points leak area lights in the tracer
    get(FY, :off, false) && return            # a film with its own swarm (movies/fireflysync.jl) switches this one off
    w = game.world
    if NG.night_factor(w) < 0.35f0
        get(FY, :visible, true) && fy_hide!()
        FY[:visible] = false
        return
    end
    FY[:visible] = true
    me = NG.creature(w, "Lumi")
    me === nothing && return
    now = time()
    lamp = Point3f(me.pos) + Point3f(0.3f0, 0.1f0, 1.0f0)
    # the player's lantern: one flash per press of F
    fdown = Makie.Keyboard.f in game.keys_down
    fired = fdown && !FY[:fdown] && me.controlled
    FY[:fdown] = fdown
    # Lumi's own lantern round, on its beat, when nobody plays
    if !me.controlled
        if now > FY[:auto_next]
            FY[:auto_until] = now + FY_AUTO_LEN; FY[:auto_next] = now + FY_AUTO_EVERY
        end
        if now < FY[:auto_until]
            FY[:auto_ph] += min(dt, 0.1) / FY_BEAT
            FY[:auto_ph] >= 1 && (FY[:auto_ph] -= 1; fired = true)
        end
    end
    fired && (FY[:lamp_t] = now)
    sw = FY[:sw]
    FYP.ff_step!(sw, min(dt, 0.1); lantern = lamp, lantern_fired = fired)
    r = FYP.ff_order(sw)
    FY[:order] = 0.95 * FY[:order] + 0.05 * r
    # how the player knows it is working: Lumi says what the field does (with some slack so it does not chatter)
    if FY[:order] > 0.7 && !FY[:synced]
        FY[:synced] = true
        NG.emit!(w, :fireflies_synced)
        me.controlled && NG.say!(w, me, "They're blinking with me!"; duration = 2.5)
    elseif FY[:order] > 0.4 && !get(FY, :listening, false) && fired
        FY[:listening] = true
        me.controlled && NG.say!(w, me, "Some are listening... keep the beat!"; duration = 2.2)
    elseif FY[:order] < 0.3
        FY[:synced] = false; FY[:listening] = false
    end
    # flashing far off their beat: say so once a round
    if fired && me.controlled
        gap = now - get(FY, :prev_press, -10.0); FY[:prev_press] = now
        if gap < 0.3 && !get(FY, :toofast, false)
            FY[:toofast] = true; NG.say!(w, me, "Too fast, they can't follow!"; duration = 2.0)
        elseif 0.4 < gap < 0.8
            FY[:toofast] = false
        end
    end
    pos = fill(FY_HIDE, FY_N); ms = zeros(Float32, FY_N)
    for i in 1:FY_N
        b = fy_glow(sw.age[i])
        b > 0.02f0 || continue
        pos[i] = sw.pos[i]; ms[i] = FY_SIZE * sqrt(b)
    end
    Makie.update!(FY[:plot]; arg1 = pos, markersize = ms)
    la = fy_glow(Float32(now - FY[:lamp_t]) / 1.5f0)
    Makie.update!(FY[:lamp]; arg1 = [la > 0.02f0 ? lamp : FY_HIDE], markersize = [0.11f0 * sqrt(la)])
    return
end

NG.stop!(::FireflySync, game) = haskey(FY, :plot) && fy_hide!()

register!(FireflySync())
