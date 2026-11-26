# Glass rain (s123). Once a day at three in the afternoon one shower over the west meadow falls as glass:
# every drop is a little glass lens a hand across, and under it on the grass sits a bright spot of sun it
# focuses. The friends chase the spots like cats after a light, pounce, miss, and chase the next; the drops
# land, lie in the grass as marbles for a few seconds and are gone.
# Traced (films, game.dash === nothing): the drops are Hikari Glass (each shows the island upside down), the
# spots are small Emission discs, real lights on the grass. Live raster: pale see-through drops, bright spots.
#   Main.GLASSRAIN[:force] = true   rain now and keep going (films, tests); [:spot] = (x, y) where it rains
const NG = NeverendingGame
isdefined(Main, :GLASSRAIN) || Core.eval(Main, :(const GLASSRAIN = Dict{Symbol,Any}()))
const GR = Main.GLASSRAIN

const FROM_H = 15.0
const TO_H = 15.5
const N = 90                   # drops at a time
const DROP_R = 0.065f0         # m
const AREA = 4.5f0             # m, radius of the shower
const TOP = 10f0               # m above the grass where drops start
const FALL = 4.0f0             # m/s: glass drops sink slowly, a game's rain you can follow
const LIE = 4.0                # s a landed drop lies in the grass
const CHASERS = 5
const SPOT = (-9.5f0, -0.5f0)  # the open west meadow (nothing within 4.5 m)
const DOT = RGBf(1.0, 0.96, 0.78)
"Emission strength of the traced spots: a lens's sun on the grass, brighter than the lit grass round it."
const SPOT_GLOW = 6f0
const LINES = ("The rain is GLASS!", "Got it! ...no.", "It's on my nose!", "Hot spot! Hot spot!", "Stay STILL!",
               "Another one!", "It tickles!", "Mine!")
const HIDE = Point3f(0, 0, -50)
push!(NG.BUSY_GOALS, :glassrain)

mutable struct Drop
    pos::Point3f
    vz::Float32
    landed::Float64            # sim time it came to rest, or -1 while falling
    gone::Bool
end

mutable struct GlassRain <: System
    on::Bool
    ending::Bool
    day::Int
    pounced::Dict{Int32,Float64}
    drops::Vector{Drop}
end

hour_of(w) = 24 * NG.daytime(w)
spot() = get(GR, :spot, SPOT)

function rain_spawn!(d::Drop, game; anywhere = false)
    rng = game.world.rng
    cx, cy = Float32.(spot())
    r = AREA * sqrt(rand(rng, Float32)); a = 2f0 * Float32(pi) * rand(rng, Float32)
    x, y = cx + r * cos(a), cy + r * sin(a)
    g = NG.ground(game.world.island, (x, y))[3]
    d.pos = Point3f(x, y, g + (anywhere ? 0.5f0 + TOP * rand(rng, Float32) : TOP))
    d.vz = -FALL * (0.8f0 + 0.4f0 * rand(rng, Float32))
    d.landed = -1.0; d.gone = false
end

function rain_build!(game)
    for k in (:drops_plot, :dots_plot)
        haskey(GR, k) && GR[k] isa Makie.AbstractPlot && GR[k].parent !== nothing && delete!(GR[k].parent, GR[k])
        delete!(GR, k)
    end
    sc = game.stage.scene
    for p in filter(p -> haskey(p.attributes, :name) && p.attributes[:name][] in (:glassrain_drops, :glassrain_dots), sc.plots)
        delete!(sc, p)
    end
    hide = fill(HIDE, N)
    tiny = fill(Vec3f(1f-3), N)          # never zero: a zero-area emissive disc is a light with an infinite pdf
    quiet = game.dash === nothing
    ball = GeometryBasics.normal_mesh(GeometryBasics.Tessellation(Makie.Sphere(Point3f(0), 1f0), quiet ? 24 : 10))
    GR[:drops_plot] = quiet ?
        meshscatter!(sc, hide; marker = ball, markersize = tiny, color = RGBf(0.92, 0.97, 1.0),
                     material = NG.Hikari.Glass(ior = 1.5), name = :glassrain_drops) :
        meshscatter!(sc, hide; marker = ball, markersize = tiny, color = RGBAf(0.82, 0.93, 1.0, 0.5),
                     transparency = true, name = :glassrain_drops)
    disc = GeometryBasics.normal_mesh(GeometryBasics.Tessellation(Makie.Cylinder(Point3f(0), Point3f(0, 0, 0.01f0), 1f0), 48))   # round, not hexagons (s123 live-2)
    GR[:dots_plot] = quiet ?
        # Traced: the spots glow (Emission). s123 films failed with that because RayMakie pushed every moved
        # emitter's lights anew (half a million after 60 frames); s124 fixed it to reuse the slots (push_reused!).
        meshscatter!(sc, hide; marker = disc, markersize = tiny, color = DOT, name = :glassrain_dots,
                     material = NG.Hikari.Emission(color = DOT, strength = SPOT_GLOW, two_sided = false)) :
        meshscatter!(sc, hide; marker = disc, markersize = tiny, color = DOT, shading = Makie.NoShading, name = :glassrain_dots)
    GR[:scene] = sc
end

function NG.start!(s::GlassRain, game)
    game.stage === nothing && return
    rain_build!(game)
end

function start_rain!(s::GlassRain, game)
    w = game.world
    s.on = true; s.ending = false; s.day = floor(Int, w.t / w.day_length)
    empty!(s.pounced)
    s.drops = [Drop(HIDE, 0f0, -1.0, true) for _ in 1:N]
    foreach(d -> rain_spawn!(d, game; anywhere = true), s.drops)
    cx, cy = spot()
    NG.emit!(w, :glassrain_start; x = round(cx; digits = 1), y = round(cy; digits = 1))
    cs = [c for c in w.creatures if c.action != :sleep && !c.controlled]
    isempty(cs) || NG.say!(w, cs[rand(w.rng, 1:length(cs))], LINES[1]; duration = 3)
end

function end_rain!(s::GlassRain, game)
    s.on = false
    for c in game.world.creatures
        c.goal.kind === :glassrain && (c.goal = NG.Goal(:idle, c.pos, :idle, 2.0, 0.0, false, 0, false))
    end
    GR[:dots] = Point3f[]
    rain_draw!(s, game)
    NG.emit!(game.world, :glassrain_end)
end

"Drops sink, bounce once off the grass, lie there a moment as marbles, and start again at the top."
function rain_fall!(s::GlassRain, game, dt)
    w = game.world
    for d in s.drops
        d.gone && continue
        if d.landed < 0
            z = d.pos[3] + d.vz * dt
            d.vz = max(d.vz - 9.8f0 * dt, -FALL * 1.2f0)          # quickly at its slow terminal speed
            g = NG.ground(w.island, (d.pos[1], d.pos[2]))[3] + DROP_R
            if z <= g
                if d.vz < -1.5f0
                    d.vz = -0.3f0 * d.vz                          # a small glassy hop
                else
                    d.landed = w.t + 3.0 * rand(w.rng)          # lie a random while: the shower never falls in waves
                end
                z = g
            end
            d.pos = Point3f(d.pos[1], d.pos[2], z)
        elseif w.t - d.landed > LIE
            s.ending ? (d.gone = true) : rain_spawn!(d, game)
        end
    end
end

"Where each falling drop throws its focused spot of sun: along the sun's ray down to the grass."
function rain_dots(s::GlassRain, game)
    w = game.world
    sd = NG.sun(w)[1]
    sz = max(sd[3], 0.25f0)
    out = Point3f[]; sizes = Float32[]
    for d in s.drops
        (d.gone || d.landed >= 0) && continue
        g = NG.ground(w.island, (d.pos[1], d.pos[2]))[3]
        hh = d.pos[3] - g
        hh > 0.2f0 || continue
        x, y = d.pos[1] - sd[1] * hh / sz, d.pos[2] - sd[2] * hh / sz
        push!(out, Point3f(x, y, NG.ground(w.island, (x, y))[3] + 0.015f0))
        push!(sizes, 0.035f0 + 0.05f0 * clamp(hh / TOP, 0f0, 1f0))      # high drops throw a wider, softer spot
    end
    return out, sizes
end

"The friends chase the nearest spot of light and pounce on it."
function rain_chase!(s::GlassRain, game, ds)
    w = game.world
    cx, cy = Float32.(spot())
    chasing = count(c -> c.goal.kind === :glassrain, w.creatures)
    for c in w.creatures
        c.controlled && continue
        if c.goal.kind === :glassrain
            if s.ending && isempty(ds)
                c.goal = NG.Goal(:idle, c.pos, :idle, 2.0, 0.0, false, 0, false); continue
            end
            isempty(ds) && continue
            bd, k = findmin(p -> hypot(p[1] - c.pos[1], p[2] - c.pos[2]), ds)
            if bd < 0.45f0 && w.t - get(s.pounced, c.id, -Inf) > 1.0
                s.pounced[c.id] = w.t
                NG.emit!(w, :glass_pounce; who = c.name)
                rand(w.rng) < 0.3 && NG.say!(w, c, LINES[rand(w.rng, 2:length(LINES))]; duration = 2)
                c.goal = NG.Goal(:idle, c.pos, :jump, 0.7, 0.0, false, 0, false)
            else
                c.goal.target = Point3f(ds[k][1], ds[k][2], 0)
                c.goal.arrived = false; c.goal.until = Inf
            end
        elseif !s.ending && chasing < CHASERS && c.action != :sleep && !NG.busy(c) &&
               w.t - get(s.pounced, c.id, -Inf) > 1.0 && rand(w.rng) < 0.03
            c.goal = NG.Goal(:glassrain, Point3f(cx, cy, 0), :play, 1.0, Inf, false, 0, true)
            chasing += 1
        end
    end
end

function rain_draw!(s::GlassRain, game)
    game.stage === nothing && return
    haskey(GR, :drops_plot) || return
    on = s.on
    pos = [on && !d.gone ? d.pos : HIDE for d in s.drops]
    sz = [on && !d.gone ? Vec3f(DROP_R) : Vec3f(1f-3) for d in s.drops]
    length(pos) == N || (pos = fill(HIDE, N); sz = fill(Vec3f(1f-3), N))
    Makie.update!(GR[:drops_plot]; arg1 = pos, markersize = sz)
    ds = get(GR, :dots, Point3f[]); dz = get(GR, :dot_sizes, Float32[])
    dp = fill(HIDE, N); dm = fill(Vec3f(1f-3), N)
    big = game.dash === nothing ? 1f0 : 1.8f0        # the raster has no glow: bigger spots so they read live
    for k in 1:min(N, length(ds))
        dp[k] = ds[k]; dm[k] = Vec3f(big * dz[k], big * dz[k], 1f0)
    end
    Makie.update!(GR[:dots_plot]; arg1 = dp, markersize = dm)
end

function NG.step!(s::GlassRain, game, dt)
    w = game.world
    GR[:sys] = s
    game.stage === nothing || get(GR, :scene, nothing) === game.stage.scene || rain_build!(game)
    force = get(GR, :force, false)
    if !s.on
        h = hour_of(w)
        day = floor(Int, w.t / w.day_length)
        (force || (FROM_H <= h < TO_H && day != s.day && game.minigame === nothing)) || return
        start_rain!(s, game)
    end
    s.ending = !force && !(FROM_H <= hour_of(w) < TO_H)
    dt = Float32(clamp(dt, 0.0, 0.05))
    dt <= 0 && return
    rain_fall!(s, game, dt)
    ds, dz = rain_dots(s, game)
    GR[:dots] = ds; GR[:dot_sizes] = dz
    rain_chase!(s, game, ds)
    if s.ending && all(d -> d.gone, s.drops)
        end_rain!(s, game); return
    end
    rain_draw!(s, game)
    return
end

function NG.stop!(s::GlassRain, game)
    s.on && end_rain!(s, game)
    for k in (:drops_plot, :dots_plot)
        haskey(GR, k) && GR[k] isa Makie.AbstractPlot && GR[k].parent !== nothing && delete!(GR[k].parent, GR[k])
        delete!(GR, k)
    end
end

register!(GlassRain(false, false, -1, Dict{Int32,Float64}(), Drop[]))
