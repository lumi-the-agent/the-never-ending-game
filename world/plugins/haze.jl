# Distance haze: far trees and hills fade a little towards the sky's horizon colour (aerial perspective),
# so the island has depth at noon (perfectionist-0052, lighting high: "the far trees are as saturated as
# the near grass"). The work is in the RayMakie raster shader (`aerial_haze`, overlay/mesh.jl, s53);
# this plugin only sets its density. A game whose renderer predates s53 has no RASTER_HAZE: nothing happens.
const NG = NeverendingGame
const DENSITY = 0.025f0     # per metre past the first 6 m; at most 55% sky

struct Haze <: System end

has_haze() = isdefined(NG.RayMakie, :RASTER_HAZE)

NG.start!(::Haze, game) = (has_haze() && (NG.RayMakie.RASTER_HAZE[] = DENSITY); nothing)

function NG.step!(::Haze, game, dt)
    has_haze() || return
    NG.RayMakie.RASTER_HAZE[] == DENSITY || (NG.RayMakie.RASTER_HAZE[] = DENSITY)
    return
end

NG.stop!(::Haze, game) = (has_haze() && (NG.RayMakie.RASTER_HAZE[] = 0f0); nothing)

register!(Haze())
