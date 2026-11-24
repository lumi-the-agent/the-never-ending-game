# Browser night: WGLMakie has no sky model, so in the browser the night was a black void over a
# day-bright island (flat AmbientLight). This fades the scene's background (the browser's sky) and
# the ambient fill with the time of day. RayMakie lights with its sun and sky and ignores both.
const NG = NeverendingGame

const SKY_DAY = RGBf(0.56, 0.74, 0.92)
const SKY_NIGHT = RGBf(0.05, 0.08, 0.17)
const AMB_DAY = RGBf(0.34, 0.37, 0.45)       # the engine's fill (scenery.jl stage_lights)
const AMB_NIGHT = RGBf(0.11, 0.13, 0.24)

mutable struct BrowserNight <: System
    nf::Float32           # night factor last applied (-1: never)
end
BrowserNight() = BrowserNight(-1f0)

mixc(a, b, t) = RGBf(a.r + (b.r - a.r) * t, a.g + (b.g - a.g) * t, a.b + (b.b - a.b) * t)

function NG.step!(s::BrowserNight, game, dt)
    game.stage === nothing && return
    nf = NG.night_factor(game.world)
    abs(nf - s.nf) < 0.02f0 && return          # dusk and dawn take minutes: a few updates each
    sc = game.stage.scene
    sc.clear[] || (sc.clear[] = true)          # the browser paints the background only then (RayMakie draws its sky anyway)
    sc.backgroundcolor[] = RGBAf(mixc(SKY_DAY, SKY_NIGHT, nf), 1)
    Makie.set_ambient_light!(sc, mixc(AMB_DAY, AMB_NIGHT, nf))
    s.nf = nf
    return
end

register!(BrowserNight())
