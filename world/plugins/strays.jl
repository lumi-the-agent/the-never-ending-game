# Strays swim home (s122, todo #587). On 26 Nov a ring launch threw Pickles 4.7 km up; it came down 2.1 km out at
# sea, and a gathering that meets at everyone's middle then walked the whole island 400 m out into the water.
# Nothing in the game may stay off the island: a friend standing in the sea past the shore swims straight home,
# faster the farther out it is, so a player sees a little head bobbing back over the waves, never a jump.
#   Main.STRAYS[:home]   last homecomings (name => metres swum)
const NG = NeverendingGame
isdefined(Main, :STRAYS) || Core.eval(Main, :(const STRAYS = Dict{Symbol,Any}()))
const S = Main.STRAYS

const SHORE = 34f0        # m from the middle: past it (the island is 24 m, the beach and shallows ~8 m more) a friend is out at sea
const BACK = 22.5f0       # m: swims (and wades up the beach) until here, then walks on its own again
const DRY = 0.15f0         # m: ground this high is out of the water
const SWIM_Z = -0.35f0    # the swim height: head and back above the waves
push!(NG.BUSY_GOALS, :swimhome)

mutable struct Strays <: System
    swimming::Dict{Int32,Float64}   # id => metres out when it started
end

# a friend in the air (an orbit ride, a throw, a balloon) is somebody else's business until it comes down
# and one standing in the shallows past the sand cannot walk out of the water on its own (s122: nine friends
# stood at 27 m for minutes), so it wades in too
stray(c, R) = !c.controlled && c.pos[3] < 3f0 &&
              (hypot(c.pos[1], c.pos[2]) > SHORE || (hypot(c.pos[1], c.pos[2]) > 0.5f0 * R && c.pos[3] < -0.1f0))

function NG.step!(s::Strays, game, dt)
    w = game.world
    dt = Float32(clamp(dt, 0.0, 0.1))
    for c in w.creatures
        r = hypot(c.pos[1], c.pos[2])
        if !haskey(s.swimming, c.id)
            stray(c, w.island.radius) || continue
            s.swimming[c.id] = r
            NG.say!(w, c, r > 100 ? "Wait for me-e-e!" : "Swimming home!"; duration = 3)
            NG.emit!(w, :stray_swim; who = c.name, metres = round(r; digits = 0))
        end
        # home = dry sand under its feet (the west shore is still under water at 22 m), or nearly the middle
        home = r <= 6f0 || (r <= BACK && NG.ground(w.island, (c.pos[1], c.pos[2]))[3] > DRY)
        if home || c.controlled || c.pos[3] >= 3f0
            home && NG.emit!(w, :stray_home; who = c.name, metres = round(s.swimming[c.id]; digits = 0))
            home && (get!(() -> Dict{String,Float64}(), S, :home)[c.name] = s.swimming[c.id])
            delete!(s.swimming, c.id)
            home && (c.pos = NG.ground(w.island, (c.pos[1], c.pos[2])))   # out of the water, onto the sand
            c.goal = NG.Goal(:idle, c.pos, :idle, 2.0, 0.0, false, 0, false)
            continue
        end
        # straight home, quick from far out (a dot on the horizon), calm near the beach
        speed = clamp(2.5f0 + 0.02f0 * (r - SHORE), 2.5f0, 12f0)
        step = speed * dt
        ux = -c.pos[1] / r; uy = -c.pos[2] / r
        x = c.pos[1] + ux * step; y = c.pos[2] + uy * step
        bob = 0.06f0 * sin(Float32(w.t) * 5f0 + c.seed * 6.283f0)
        c.pos = Point3f(x, y, max(SWIM_Z + bob, NG.ground(w.island, (x, y))[3]))
        c.yaw = atan(uy, ux) - NG.species_of(c).heading
        c.action = :swim
        c.goal = NG.Goal(:swimhome, Point3f(ux * BACK, uy * BACK, 0), :swim, 60.0, Inf, false, 0, true)
    end
    return
end

register!(Strays(Dict{Int32,Float64}()))
