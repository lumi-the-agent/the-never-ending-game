# Wind you can see (session 72, a wish): the grass tufts, the flowers and the dune grass lean with the wind,
# and gusts roll across the island in waves, so the whole meadow sways together. The wind turns slowly over
# the day and blows harder now and then.
const NG = NeverendingGame
isdefined(Main, :WIND) || Core.eval(Main, :(const WIND = Dict{Symbol,Any}()))
const W = Main.WIND

const PLOTS = (:grass_tufts, :flora_flower_1, :flora_flower_2, :flora_flower_3, :flora_flower_4, :beach_dunegrass)
const RATE = 1 / 15          # s between two updates (the browser gets every one)

struct Wind <: System end

function find_plots!(game)
    W[:plots] = Dict{Symbol,Any}()
    for p in game.stage.scene.plots
        haskey(p.attributes, :name) || continue
        n = p.attributes[:name][]
        n in PLOTS || continue
        r = p.attributes[:rotation][]
        ps = p.attributes[:positions][]
        base = r isa AbstractVector ? collect(r) : fill(r, length(ps))
        W[:plots][n] = (plot = p, base = base, pos = collect(Point3f.(ps)))
    end
end

"Where the wind blows (unit, flat) and how hard (0.5 .. 1.3), both drifting slowly with the island clock."
function wind_now(t)
    a = Float32(0.6 + 0.35 * sin(t / 900))
    strength = Float32(0.9 + 0.4 * sin(t / 170) * sin(t / 53))
    return Vec2f(cos(a), sin(a)), strength
end

function NG.step!(::Wind, game, dt)
    game.stage === nothing && return
    w = game.world
    w.t - get(W, :last, -Inf) < RATE && return
    W[:last] = w.t
    any(e -> e.plot.parent === nothing, values(get(W, :plots, Dict()))) && find_plots!(game)   # flora rebuilt its plots
    isempty(get(W, :plots, Dict())) && find_plots!(game)
    d, strength = wind_now(w.t)
    axis = Vec3f(-d[2], d[1], 0)          # tilting about it leans the tops downwind
    t = Float32(w.t)
    for (name, e) in W[:plots]
        length(e.base) == length(e.pos) || continue
        rot = map(eachindex(e.pos)) do i
            p = e.pos[i]
            # a gust is a wave rolling downwind; between gusts everything leans a little
            g = 0.5f0 + 0.5f0 * sin(0.3f0 * (p[1] * d[1] + p[2] * d[2]) - 1.2f0 * t + 0.3f0 * sin(0.7f0 * p[1] - 0.5f0 * p[2]))
            # s73: a gust bends a plant ~25-30 deg (was ~16): the review's still showed no wind at all
            ang = strength * (0.06f0 + 0.42f0 * g^3) + 0.06f0 * sin(5f0 * t + 1.3f0 * i)
            Makie.qrotation(axis, ang) * e.base[i]
        end
        Makie.update!(e.plot; rotation = rot)
    end
end

function NG.start!(::Wind, game)
    W[:now] = wind_now          # other plugins (the kite) ask the same wind: Base.invokelatest(Main.WIND[:now], t)
    game.stage === nothing || find_plots!(game)
    nothing
end

function NG.stop!(::Wind, game)
    for (_, e) in get(W, :plots, Dict())
        e.plot.parent === nothing || length(e.base) != length(e.pos) || Makie.update!(e.plot; rotation = e.base)
    end
end

register!(Wind())
