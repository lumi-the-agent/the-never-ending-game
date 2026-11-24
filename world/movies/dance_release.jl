# "Dance by the lantern": the second film (goal 2, todo #184). A quiet copy of the game at dusk; four
# critters meet at a lantern dance spot and the camera cuts on what really happens: a wide push-in
# while they gather, a low orbit inside the ring once everyone dances, then a slow crane up and back
# to the glowing lantern and the dusk sky. Run in the agent session:
#   include("world/movies/dance_release.jl"); dance_movie("world/media/clips/x.mp4"; rasterize = true)
using NeverendingGame, Makie, LinearAlgebra
const NG = NeverendingGame

dflat(v) = normalize(Point3f(v[1], v[2], 0))
dlerp(a, b, k) = a + Float32(k) * (b - a)
dease(k) = (k = clamp(k, 0, 1); k * k * (3 - 2k))

function dance_movie(path; size = (1280, 720), samples = 64, hour = 18.7, rasterize = false, fps = 24, max_seconds = 24)
    st = Dict{Symbol,Any}(:phase => :wide, :tcut => 0.0)
    isdefined(Main, :EMOTES) && empty!(Main.EMOTES)
    function setup(g)
        Base.invokelatest(NG.step_systems!, g, 1 / 30)       # plugins start: lamps, dance spots
        w = g.world
        dc = only(g.plugins["dancecircle"].systems)
        spots = Base.invokelatest(g.plugins["dancecircle"].mod.dance_spots, g)
        isempty(spots) && error("no dance spot")
        ctr = spots[1]
        dir, _ = NG.sun(w)
        sd = dflat(dir)
        # the camera's side: the clearest lines of sight at 7 m and 4 m (trees and bushes stood in front, preview 1),
        # the low sun over its shoulder breaking ties
        # the spot's lantern goes BEHIND the ring as a glowing backdrop: in take 5 it stood in the foreground and hid the dancers
        acts = [a for a in w.actors if a isa NG.AssetActor]
        lan = isempty(acts) ? nothing : argmin(a -> hypot(a.pos[1] - ctr[1], a.pos[2] - ctr[2]), acts)
        ld = lan === nothing ? Point3f(0) : dflat(lan.pos - ctr)
        cost(v) = NG.obstruction(w, ctr + 7.0f0 * v + Point3f(0, 0, 2.4), ctr + Point3f(0, 0, 0.5)) +
                  NG.obstruction(w, ctr + 4.4f0 * v + Point3f(0, 0, 1.1), ctr + Point3f(0, 0, 0.5)) - 0.2f0 * dot(v, sd) +
                  1.5f0 * max(0f0, dot(v, ld))
        d = argmin(cost, [Point3f(cos(a), sin(a), 0) for a in range(0, 2pi; length = 13)[1:12]])
        side = Point3f(-d[2], d[1], 0)
        dancers = [c for c in w.creatures if c.species != "Lumi"][1:4]
        for (k, c) in enumerate(dancers)                      # they come in from the meadow, 3-4 m out
            a = Float32(2pi * k / 4) + 0.4f0
            c.pos = NG.ground(w.island, (ctr[1] + 3.6f0 * cos(a), ctr[2] + 3.6f0 * sin(a)))
            c.action = :idle
        end
        ok = Base.invokelatest(g.plugins["dancecircle"].mod.start_circle!, dc, g; spot = ctr, dancers = [c.id for c in dancers])
        ok || error("the dance circle did not start")
        st[:c], st[:d], st[:side], st[:dc] = Point3f(ctr), d, side, dc
    end
    function shot(g, rig, t)
        c, d, side, dc = st[:c], st[:d], st[:side], st[:dc]
        mid = c + Point3f(0, 0, 0.45)
        dancing = dc.active && dc.t0 > 0
        if st[:phase] === :wide && ((dancing && t > 5) || t > 9)
            st[:phase], st[:tcut] = :ring, t
        elseif st[:phase] === :ring && t - st[:tcut] > 8
            st[:phase], st[:tcut] = :crane, t
        end
        u = t - st[:tcut]
        if st[:phase] === :wide                       # establishing: the lantern, the meadow, critters arriving
            k = dease(u / 9)
            rig.eye = c + dlerp(7.5f0, 6.0f0, k) * d + Point3f(0, 0, dlerp(2.8f0, 2.0f0, k))
            rig.target = mid
        elseif st[:phase] === :ring                   # above the dancers, slowly circling: the ring reads as a circle
            a = -0.25f0 + 0.06f0 * Float32(u)         # (s43: from 1.1 m, take 6 showed critters scattered round a lantern)
            v = cos(a) * d + sin(a) * side
            rig.eye = c + 5.2f0 * v + Point3f(0, 0, 2.4)
            rig.target = mid
        else                                          # crane up and back: the ring, the lantern glow, the dusk sky
            k = dease(u / 7)
            rig.eye = c + dlerp(4.6f0, 7.0f0, k) * d + Point3f(0, 0, dlerp(1.2f0, 3.6f0, k))
            rig.target = dlerp(mid, c + Point3f(0, 0, 1.2) - 2.0f0 * d, 0.5f0 * k)
        end
        st[:phase] === :crane && u > 7.5 && return t
        return t > max_seconds - 0.5 ? Float64(max_seconds) : nothing
    end
    rig = NG.CameraRig(mode = :fixed)
    return NG.game_clip(path; size, samples, hour, rasterize, fps, seconds = max_seconds, warmup = 1.0,
                        rig, setup, shot, fade = 0.8)
end
