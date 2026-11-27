# Stars: a dome of small bright points over the island that comes out at night.
# The sky model has no stars, so they are tiny emissive spheres far away; hidden by day.
isdefined(Main, :STARS) || Core.eval(Main, :(const STARS = Dict{Symbol,Any}()))

const NG = NeverendingGame
const STARS_VERSION = 3   # s134 low-poly glow markers
const N_STARS = 420

struct Stars <: System end

function build_stars!(game)
    haskey(Main.STARS, :plot) && delete!(Main.STARS[:plot].parent, Main.STARS[:plot])
    rng = NG.Random.MersenneTwister(7)
    R = 4 * game.world.island.radius
    pts = Point3f[]; sz = Float32[]
    while length(pts) < N_STARS
        a = 2pi * rand(rng); e = asin(rand(rng))          # uniform over the upper half sphere
        e < 0.18 && continue                               # not in the haze at the horizon
        push!(pts, Point3f(R * cos(e) * cos(a), R * cos(e) * sin(a), R * sin(e)))
        push!(sz, R * (0.0016f0 + 0.0026f0 * rand(rng)^3))  # a few bright ones, many small
    end
    Main.STARS[:plot] = meshscatter!(game.stage.scene, pts; marker = NG.shape(:glowdot), markersize = sz,
        color = RGBf(1, 0.97, 0.88), shading = Makie.NoShading, material = NG.Hikari.Emission(color = (1.0, 0.97, 0.88), strength = 4.0),
        visible = false, name = :night_stars)
    Main.STARS[:key] = STARS_VERSION
end

function NG.start!(::Stars, game)
    game.stage === nothing && return
    get(Main.STARS, :key, nothing) == STARS_VERSION && Main.STARS[:plot].parent === game.stage.scene || build_stars!(game)
    return
end

function NG.step!(::Stars, game, dt)
    game.stage === nothing && return
    # only once the sun is down: at 18:22 the night factor passed 0.5 with the sun a hand above the sea
    # and stars hung in a bright sky (perfectionist-0052)
    on = NG.night_factor(game.world) > 0.5f0 && !(12 < 24 * NG.daytime(game.world) < 20.4)   # the sunset sun (sunset.jl) sets at 19.9
    p = Main.STARS[:plot]
    p.visible[] == on || (p.visible[] = on)
    return
end

NG.stop!(::Stars, game) = haskey(Main.STARS, :plot) && (Main.STARS[:plot].visible[] = false)

register!(Stars())
