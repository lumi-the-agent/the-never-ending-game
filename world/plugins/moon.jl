# Moon: a big soft full moon with a glow that crosses the northern sky at night,
# rising in the west after dusk and setting in the east before dawn.
# The sky model has no moon, so it is an unlit disc of spheres far out; hidden by day.
isdefined(Main, :MOON) || Core.eval(Main, :(const MOON = Dict{Symbol,Any}()))

const NG = NeverendingGame
const MOON_VERSION = 3
const MOON_COLOR = RGBf(1.0, 0.96, 0.84)
# moon disc, then halo shells that stack into a soft glow: (radius as a part of the moon's distance, colour)
const MOON_LAYERS = [(0.028f0, RGBAf(1.0, 0.97, 0.86, 1.0));
                     [(0.029f0 + 0.0042f0 * k^1.15f0, RGBAf(0.82, 0.88, 1.0, 0.05)) for k in 1:10]]
const MOON_KEYS = [Symbol(:moon, k) for k in eachindex(MOON_LAYERS)]

struct Moon <: System end

"Where the moon stands for the time of day: unit vector from the island to the moon."
function moon_dir(w)
    d = NG.daytime(w)                       # 0 midnight, 0.25 sunrise, 0.75 sunset
    f = mod(d + 0.25, 1.0)                  # 0 at sunset, 0.5 at sunrise
    s = clamp(f / 0.5, 0.0, 1.0)            # 0..1 across the night
    az = pi * (1 - s)                       # west (-x) .. north (+y) .. east (+x)
    elev = 0.2 + 0.35 * sin(pi * s)         # low at the ends of the night, ~32° at midnight
    return normalize(Vec3f(cos(az) * cos(elev), 0.9 * sin(az) * cos(elev) + 0.25, sin(elev)))
end

function build_moon!(game)
    for k in collect(keys(Main.MOON))
        Main.MOON[k] isa Makie.AbstractPlot || continue
        delete!(Main.MOON[k].parent, Main.MOON[k]); delete!(Main.MOON, k)
    end
    sc = game.stage.scene
    for (k, (r, col)) in zip(MOON_KEYS, MOON_LAYERS)
        Main.MOON[k] = mesh!(sc, Sphere(Point3f(0), 1.0f0); color = col, shading = Makie.NoShading,
            transparency = col.alpha < 1, material = NG.Hikari.Emission(color = (col.r, col.g, col.b), strength = k === :moon1 ? 6.0 : 0.6),
            visible = false, name = k)
        Main.MOON[Symbol(k, :_r)] = r
    end
    Main.MOON[:key] = MOON_VERSION
    Main.MOON[:dir] = Vec3f(0)
end

function NG.start!(::Moon, game)
    game.stage === nothing && return
    get(Main.MOON, :key, nothing) == MOON_VERSION && Main.MOON[:moon1].parent === game.stage.scene || build_moon!(game)
    return
end

function NG.step!(::Moon, game, dt)
    game.stage === nothing && return
    w = game.world
    on = NG.night_factor(w) > 0.4f0 || get(Main.MOON, :force, false)
    if Main.MOON[:moon1].visible[] != on
        for k in MOON_KEYS
            Main.MOON[k].visible[] = on
        end
    end
    on || return
    dir = moon_dir(w)
    dot(dir, Main.MOON[:dir]) > cosd(0.2f0) && return     # move only when it moved visibly
    D = 3.6f0 * w.island.radius
    for k in MOON_KEYS
        p = Main.MOON[k]
        translate!(p, Vec3f(D * dir))
        scale!(p, Vec3f(D * Main.MOON[Symbol(k, :_r)]))
    end
    Main.MOON[:dir] = dir
    return
end

function NG.stop!(::Moon, game)
    for k in MOON_KEYS
        haskey(Main.MOON, k) && (Main.MOON[k].visible[] = false)
    end
end

register!(Moon())
