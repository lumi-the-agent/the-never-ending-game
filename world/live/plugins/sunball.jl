# Football with the sun (s122). Once a day at noon the sun comes loose, drops onto the meadow as a glowing
# ball a metre across, and for an island hour and a half it is the island's only light. The friends chase
# it and kick it about; every kick swings every shadow, and a ball kicked far off leaves the camera's side in
# dusk. As Lumi (jump in) you kick it by running into it. At 13:30 it floats back up into the sky.
# Live raster: the sky dims (NG.SUN_DIM via showers.jl) and the sun light is aimed from the ball, low over the
# grass, at most once a second (aiming re-bakes the sky). Traced (films, game.dash === nothing): the ball is an Emission
# sphere, a real area light rolling over the island.
#   Main.SUNBALL[:force] = true   start now and keep going (films, tests); [:pos], [:vel], [:strength]
const NG = NeverendingGame
isdefined(Main, :SUNBALL) || Core.eval(Main, :(const SUNBALL = Dict{Symbol,Any}()))
const SB = Main.SUNBALL

const FROM_H = 12.0
const TO_H = 13.5
const RAD = 0.5f0              # m, the ball
const DROP_Z = 30f0            # m, where it falls from
const FRICTION = 0.9f0         # 1/s, rolling on grass
const SLOPE_G = 6f0            # m/s² per unit of slope: it rolls downhill
const KICK_COOL = 1.2          # s between two kicks of one friend
const CHASERS = 5
const WARM = RGBf(1.0, 0.86, 0.55)
const LINES = ("The SUN fell down!", "It's warm!", "Kick it to me!", "Mine! MINE!", "Not into the sea!",
               "Ow, hot toes!", "Goooal!", "Who turned the sky off?")
push!(NG.BUSY_GOALS, :sunball)

mutable struct SunBall <: System
    on::Bool
    day::Int
    t0::Float64
    pos::Point3f
    vel::Vec3f
    kicked::Dict{Int32,Float64}
    light_t::Float64
    leaving::Float64         # sim time it started to float up, or -1
end

hour_of(w) = 24 * NG.daytime(w)

"The ground as it is drawn: the terrain plus the dunes of spoken sand (wordsand.jl)."
function floor_at(game, x, y)
    w = game.world
    z = NG.ground(w.island, (x, y))[3]
    ws = get(game.plugins, "wordsand", nothing)
    if ws !== nothing && isdefined(Main, :WORDSAND) && haskey(Main.WORDSAND, :H)
        z += Base.invokelatest(ws.mod.sand_at, Main.WORDSAND[:H], Float32(x), Float32(y))
    end
    return max(Float32(z), -0.25f0)
end

trunks(w) = [(Point2f(p.pos[1], p.pos[2]), 0.2f0 * p.scale + RAD) for p in w.props if p.kind === :tree]

function build!(game)
    for k in (:plot, :halo)
        haskey(SB, k) && SB[k] isa Makie.AbstractPlot && (delete!(SB[k].parent, SB[k]); delete!(SB, k))
    end
    sc = game.stage.scene
    m = GeometryBasics.normal_mesh(GeometryBasics.Tessellation(Makie.Sphere(Point3f(0), RAD), 10))   # few triangles: each is an area light in the tracer
    if game.dash === nothing
        SB[:plot] = mesh!(sc, m; color = WARM, visible = get(SB, :force, false), name = :sunball,
                          material = NG.Hikari.Emission(color = (WARM.r, WARM.g, WARM.b), strength = get(SB, :strength, 30.0)))
    else
        SB[:plot] = mesh!(sc, m; color = RGBf(1.0, 0.95, 0.7), shading = Makie.NoShading, visible = false, name = :sunball)
        # the raster has no glow: a soft warm halo round the ball so it reads as a light from across the island
        SB[:halo] = mesh!(sc, GeometryBasics.normal_mesh(GeometryBasics.Tessellation(Makie.Sphere(Point3f(0), 3.2f0 * RAD), 16));
                          color = RGBAf(1.0, 0.8, 0.45, 0.22), shading = Makie.NoShading, transparency = true,
                          visible = false, name = :sunball_halo)
    end
    SB[:scene] = sc
end

function NG.start!(s::SunBall, game)
    game.stage === nothing && return
    build!(game)
end

function start_match!(s::SunBall, game)
    w = game.world
    s.on = true; s.t0 = w.t; s.day = floor(Int, w.t / w.day_length); s.leaving = -1.0
    x, y = -9.5f0 + 3f0 * (rand(w.rng) - 0.5f0), -0.5f0 + 3f0 * (rand(w.rng) - 0.5f0)   # the open meadow on the west side (no prop within 4.5 m)
    s.pos = Point3f(x, y, get(SB, :force, false) ? floor_at(game, x, y) + RAD : DROP_Z)
    s.vel = Vec3f(0)
    empty!(s.kicked)
    SB[:dim] = 0.1f0                                 # showers.jl owns NG.SUN_DIM and takes this in
    NG.emit!(w, :sun_fell; x = round(x; digits = 1), y = round(y; digits = 1))
    cs = [c for c in w.creatures if c.action != :sleep && !c.controlled]
    for (k, c) in enumerate(cs[1:min(3, end)])
        NG.say!(w, c, LINES[mod1(k + rand(w.rng, 1:8), length(LINES))]; duration = 3)
    end
end

function end_match!(s::SunBall, game)
    s.on = false
    SB[:dim] = 1f0
    haskey(SB, :plot) && (SB[:plot].visible[] = false)
    haskey(SB, :halo) && (SB[:halo].visible[] = false)
    for c in game.world.creatures
        c.goal.kind === :sunball && (c.goal = NG.Goal(:idle, c.pos, :idle, 2.0, 0.0, false, 0, false))
    end
    game.stage === nothing || game.dash === nothing || restore_sun!(game)
    NG.emit!(game.world, :sun_back)
end

function NG.step!(s::SunBall, game, dt)
    w = game.world
    SB[:sys] = s
    game.stage === nothing || get(SB, :scene, nothing) === game.stage.scene || build!(game)
    force = get(SB, :force, false)
    if !s.on
        h = hour_of(w)
        day = floor(Int, w.t / w.day_length)
        (force || (FROM_H <= h < TO_H && day != s.day && game.minigame === nothing)) || return
        start_match!(s, game)
    end
    if s.leaving < 0 && !force && !(FROM_H <= hour_of(w) < TO_H + 0.05)
        s.leaving = w.t
        NG.say!(w, w.creatures[1], "Bye, sun! Same time tomorrow!"; duration = 3)
    end
    dt = Float32(clamp(dt, 0.0, 0.05))
    dt <= 0 && return
    roll!(s, game, dt)
    s.leaving < 0 && play!(s, game)
    if s.leaving >= 0 && s.pos[3] > DROP_Z
        end_match!(s, game); return
    end
    SB[:pos] = s.pos; SB[:vel] = s.vel
    if game.stage !== nothing && haskey(SB, :plot)
        p = SB[:plot]
        p.visible[] || (p.visible[] = true)
        Makie.translate!(p, s.pos[1], s.pos[2], s.pos[3])
        if haskey(SB, :halo)
            SB[:halo].visible[] || (SB[:halo].visible[] = true)
            Makie.translate!(SB[:halo], s.pos[1], s.pos[2], s.pos[3])
        end
        game.dash === nothing || (w.t - s.light_t > 1.0 && aim_light!(s, game) && (s.light_t = w.t))
    end
    return
end

"The ball: falls, bounces, rolls downhill, slows on the grass, glances off trunks, is washed back from the sea."
function roll!(s::SunBall, game, dt)
    w = game.world
    p = s.pos; v = s.vel
    if s.leaving >= 0                                # floating home to the sky
        s.pos = Point3f(p[1], p[2], p[3] + dt * min(8f0, 0.5f0 + 2f0 * Float32(w.t - s.leaving)))
        return
    end
    g = floor_at(game, p[1], p[2]) + RAD
    if p[3] > g + 0.01f0                             # in the air
        v = v + Vec3f(0, 0, -9.8f0 * dt)
    else
        e = 0.3f0                                    # the slope under it
        sx = (floor_at(game, p[1] + e, p[2]) - floor_at(game, p[1] - e, p[2])) / 2e
        sy = (floor_at(game, p[1], p[2] + e) - floor_at(game, p[1], p[2] - e)) / 2e
        v = Vec3f(v[1] - SLOPE_G * sx * dt, v[2] - SLOPE_G * sy * dt, v[3])
        v = Vec3f(v[1] * exp(-FRICTION * dt), v[2] * exp(-FRICTION * dt), v[3])
    end
    q = p + v * dt
    gq = floor_at(game, q[1], q[2]) + RAD
    if q[3] < gq                                     # landed or rolling: bounce a little, then stick to the ground
        vz = v[3] < -2f0 ? -0.45f0 * v[3] : 0f0
        v[3] < -6f0 && NG.emit!(w, :sun_bounce; speed = round(-v[3]; digits = 1))
        q = Point3f(q[1], q[2], gq); v = Vec3f(v[1], v[2], vz)
    end
    for (t, r) in trunks(w)                          # glance off the trees
        d = Vec2f(q[1] - t[1], q[2] - t[2]); nd = norm(d)
        if nd < r && nd > 1f-4
            n = d / nd
            q = Point3f(t[1] + n[1] * r, t[2] + n[2] * r, q[3])
            vn = v[1] * n[1] + v[2] * n[2]
            vn < 0 && (v = Vec3f(v[1] - 1.6f0 * vn * n[1], v[2] - 1.6f0 * vn * n[2], v[3]))
        end
    end
    R = Float32(w.island.radius)
    rq = hypot(q[1], q[2])
    if rq > R + 1f0                                  # in the sea: the waves push it back to the beach
        v = Vec3f(v[1] - 3f0 * q[1] / rq * dt, v[2] - 3f0 * q[2] / rq * dt, v[3])
        rq > R + 6f0 && (q = Point3f(q[1] * (R + 6f0) / rq, q[2] * (R + 6f0) / rq, q[3]))
    end
    s.pos = q; s.vel = v
end

"The friends chase the sun and kick it; anybody running into it (Lumi as the player too) kicks it."
function play!(s::SunBall, game)
    w = game.world
    b = s.pos
    chasing = count(c -> c.goal.kind === :sunball, w.creatures)
    for c in w.creatures
        d = Vec2f(b[1] - c.pos[1], b[2] - c.pos[2]); nd = norm(d)
        if nd < RAD + 1.0f0 && b[3] < floor_at(game, b[1], b[2]) + RAD + 0.6f0 && w.t - get(s.kicked, c.id, -Inf) > KICK_COOL
            a = atan(d[2], d[1]) + (c.controlled ? 0f0 : 0.6f0 * (rand(w.rng, Float32) - 0.5f0))
            sp = c.controlled ? 6.5f0 : 3.5f0 + 3f0 * rand(w.rng, Float32)
            s.vel = Vec3f(sp * cos(a), sp * sin(a), 1.2f0 + 1.5f0 * rand(w.rng, Float32))
            s.pos = Point3f(b[1], b[2], b[3] + 0.02f0)
            s.kicked[c.id] = w.t
            NG.emit!(w, :sun_kick; who = c.name, speed = round(sp; digits = 1))
            rand(w.rng) < 0.35 && NG.say!(w, c, LINES[rand(w.rng, 3:8)]; duration = 2)
            c.controlled || (c.goal = NG.Goal(:idle, c.pos, :jump, 0.8, 0.0, false, 0, false))
            continue
        end
        c.controlled && continue
        if c.goal.kind === :sunball
            c.goal.target = Point3f(b[1], b[2], 0)
            c.goal.arrived = false; c.goal.until = Inf     # the ball moves: never 'there' for long
        elseif chasing < CHASERS && c.action != :sleep && !NG.busy(c) && w.t - get(s.kicked, c.id, -Inf) > 2.5 &&
               rand(w.rng) < 0.02
            c.goal = NG.Goal(:sunball, Point3f(b[1], b[2], 0), :play, 1.0, Inf, false, 0, true)
            chasing += 1
        end
    end
end

"""
Live raster: the scene's one light (the sun and sky) is aimed from the ball, low over the grass, dimmer the
farther the ball is from what the camera looks at. A traced scene cannot get a light of its own later, and every
new aim re-bakes the sky (35 ms), so it is re-aimed at most once a second and only when it turned 6° or more.
"""
function aim_light!(s::SunBall, game; now = false)
    st = game.stage
    w = game.world
    sub = game.rig.mode === :follow ? NG.creature(w, game.rig.subject) : nothing
    C = sub === nothing ? Point3f(0, 0, 1) : sub.pos
    d = Vec2f(s.pos[1] - C[1], s.pos[2] - C[2]); dist = norm(d)
    el = dist < 0.5f0 ? 1.2f0 : max(0.14f0, atan(2.0f0, dist))
    h = dist < 0.5f0 ? Vec2f(1, 0) : d / dist
    dir = normalize(Vec3f(h[1] * cos(el), h[2] * cos(el), sin(el)))
    sea = hypot(s.pos[1], s.pos[2]) > w.island.radius + 1
    inten = Float32(get(SB, :power, 2.6) / (1 + (dist / 10)^2) + 0.15)
    last = get(SB, :aim, (Vec3f(0, 0, 1), 0f0))
    now || dot(dir, last[1]) < cosd(6f0) || abs(inten - last[2]) > 0.2f0 || return false
    Makie.set_light!(st.scene, 1; direction = dir, intensity = inten, color = sea ? RGBf(0.55, 0.8, 1.0) : WARM)
    SB[:aim] = (dir, inten)
    # the engine's sync_sun! re-aims only when the real sun moved 1° from st.sun_dir: keep that the real sun
    st.sun_dir, st.sun_intensity = NG.sun(w)
    return true
end

function restore_sun!(game)
    st = game.stage
    dir, inten = NG.sun(game.world)
    Makie.set_light!(st.scene, 1; direction = dir, intensity = inten, color = NG.sun_color(game.world))
    st.sun_dir = dir; st.sun_intensity = inten
    delete!(SB, :aim)
end

function NG.stop!(s::SunBall, game)
    s.on && end_match!(s, game)
    for k in (:plot, :halo)
        haskey(SB, k) && SB[k] isa Makie.AbstractPlot && (delete!(SB[k].parent, SB[k]); delete!(SB, k))
    end
end

register!(SunBall(false, -1, 0.0, Point3f(0), Vec3f(0), Dict{Int32,Float64}(), -Inf, -1.0))
