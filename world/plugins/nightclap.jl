# See by clapping, live (s130; project island-echo). At night Lumi claps now and then, and the island lights up
# where the sound lands: 1500 rays leave the clap in every direction and are marched through the island's terrain
# (the ground under them, one mirror bounce), each hit glows when the sound gets there, slowed 60 times, so a ring
# runs out over the grass and a second, fainter one comes back. Rays against trees and props come with the
# traced version (physics/echo.jl, the BVH of the whole stage; todo #622).
isdefined(Main, :NIGHTCLAP) || Core.eval(Main, :(const NIGHTCLAP = Dict{Symbol,Any}()))
const NG = NeverendingGame
const NC = Main.NIGHTCLAP
const NC_RAYS = 1500
const NC_SLOTS = 500
const NC_SIZE = 0.15f0        # m: 7 cm points read as pebbles/fireflies (perfectionist-0130)
const NC_HEAR = 30f0          # m: friends this close turn to the clap when the slowed sound reaches them
const NC_SLOW = 60f0          # the sound slowed 60 times
const NC_FADE = 0.35f0        # s a lit point glows
const NC_EVERY = 45.0         # real seconds between claps at night
const NC_HIDE = Point3f(0, 0, -50)
const NC_C = 343f0

struct NightClap <: System end

"March a ray through the terrain: the first point under the ground (bisected), or nothing within `far` m."
function nc_march(isl, o::Point3f, d::Vec3f; far = 40f0, step = 0.25f0)
    s = step
    while s < far
        p = o + s * d
        if p[3] < NG.terrain_height(isl, p[1], p[2])
            a, b = s - step, s
            for _ in 1:6
                m = (a + b) / 2; q = o + m * d
                q[3] < NG.terrain_height(isl, q[1], q[2]) ? (b = m) : (a = m)
            end
            return b
        end
        s += step
    end
    return nothing
end

function nc_normal(isl, x, y)
    e = 0.3f0
    hx = NG.terrain_height(isl, x + e, y) - NG.terrain_height(isl, x - e, y)
    hy = NG.terrain_height(isl, x, y + e) - NG.terrain_height(isl, x, y - e)
    n = Vec3f(-hx, -hy, 2e); n / sqrt(sum(abs2, n))
end

"Every place the clap at `src` reaches (first hit and one bounce), with the time the sound gets there."
function nc_hits(isl, src::Point3f)
    P = Point3f[]; T = Float32[]
    for i in 1:NC_RAYS
        z = 1f0 - 2f0 * rand(Float32); r = sqrt(max(0f0, 1f0 - z * z)); ph = 2f0 * Float32(pi) * rand(Float32)
        d = Vec3f(r * cos(ph), r * sin(ph), z)
        s = nc_march(isl, src, d)
        s === nothing && continue
        x = src + s * d
        push!(P, x); push!(T, s / NC_C)
        n = nc_normal(isl, x[1], x[2])
        d2 = d - 2f0 * sum(d .* n) * n
        s2 = nc_march(isl, x + 0.05f0 * n, d2)
        s2 === nothing && continue
        push!(P, x + 0.05f0 * n + s2 * d2); push!(T, (s + s2) / NC_C)
    end
    P, T
end

function nc_build!(game)
    NC[:plot] = meshscatter!(game.stage.scene, fill(NC_HIDE, NC_SLOTS);
        marker = GeometryBasics.normal_mesh(GeometryBasics.Tessellation(GeometryBasics.Sphere(Point3f(0), 1f0), 6)),
        markersize = zeros(Float32, NC_SLOTS), color = RGBf(1.0, 0.82, 0.45), shading = Makie.NoShading,
        material = NG.Hikari.Emission(color = (1.0, 0.82, 0.45), strength = 3.0), name = :nightclap)
    NC[:last] = time(); NC[:hits] = nothing
end

function NG.start!(::NightClap, game)
    game.stage === nothing && return
    (haskey(NC, :plot) && NC[:plot].parent === game.stage.scene) || nc_build!(game)
    NC[:plot].visible[] = true          # stop! (a reload) hid it; the old plot is kept (s131: the ring was invisible)
    return
end

function NG.step!(::NightClap, game, dt)
    game.stage === nothing && return
    (haskey(NC, :plot) && NC[:plot].parent === game.stage.scene) || nc_build!(game)
    NG.path_traced(game) && return        # moving glowing points leak area lights in the tracer
    w = game.world; now = time()
    me = NG.creature(w, "Lumi")
    me === nothing && return
    # the player claps with N (jumped in, at night)
    ndown = Makie.Keyboard.n in game.keys_down
    pressed = ndown && !get(NC, :ndown, false) && me.controlled
    NC[:ndown] = ndown
    dark = NG.night_factor(w) > 0.35f0
    pressed && !dark && NG.say!(w, me, "Too bright to see a sound. Wait for the night!"; duration = 2.5)
    if NC[:hits] === nothing && ((dark && (pressed || (!me.controlled && now - NC[:last] > NC_EVERY))) || get(NC, :force, false))
        NC[:force] = false
        src = Point3f(me.pos) + Point3f(0, 0, 1.2f0)
        P, T = nc_hits(w.island, src)
        NC[:hits] = (P, T, now); NC[:last] = now
        # who hears it: each friend turns when the (slowed) sound reaches it, the way the ring does
        NC[:ears] = [(c.id, NC_SLOW * hypot(c.pos[1] - src[1], c.pos[2] - src[2]) / NC_C, Float32(c.yaw), false)
                     for c in w.creatures if c !== me && hypot(c.pos[1] - src[1], c.pos[2] - src[2]) < NC_HEAR]
        NC[:src] = src
        NG.emit!(w, :clap_seen)
    end
    NC[:hits] === nothing && return
    P, T, t0 = NC[:hits]
    t = Float32(now - t0)
    pos = fill(NC_HIDE, NC_SLOTS); ms = zeros(Float32, NC_SLOTS); n = 0
    for k in eachindex(P)
        age = t - NC_SLOW * T[k]
        (0f0 <= age < NC_FADE && n < NC_SLOTS) || continue
        n += 1; pos[n] = P[k]; ms[n] = NC_SIZE * sqrt(1f0 - age / NC_FADE)
    end
    Makie.update!(NC[:plot]; arg1 = pos, markersize = ms)
    nc_turn!(w, t)
    t > NC_SLOW * maximum(T; init = 0f0) + NC_FADE && (NC[:hits] = nothing)
    return
end

const NC_HUH = ("Huh?", "Who's there?", "!", "Was that a clap?", "Over here!")

"Friends turn their heads to the clap over 0.4 s once its (slowed) sound reaches them, and some answer."
function nc_turn!(w, t)
    ears = get(NC, :ears, nothing)
    ears === nothing && return
    src = NC[:src]
    for (k, (id, ta, yaw0, said)) in enumerate(ears)
        t < ta && continue
        c = findfirst(x -> x.id == id, w.creatures)
        c === nothing && continue
        c = w.creatures[c]
        u = min(1f0, (t - ta) / 0.4f0)
        u >= 1f0 && t - ta > 1.5f0 && continue
        want = atan(src[2] - c.pos[2], src[1] - c.pos[1]) - NG.species_of(c).heading
        dy = rem2pi(want - yaw0, RoundNearest)
        c.yaw = yaw0 + dy * (3u^2 - 2u^3)               # smooth turn, no one-frame snap
        if !said && k % 2 == 1
            NG.say!(w, c, NC_HUH[mod1(k, length(NC_HUH))]; duration = 1.8)
            ears[k] = (id, ta, yaw0, true)
        end
    end
end

NG.stop!(::NightClap, game) = haskey(NC, :plot) && (NC[:plot].visible[] = false)

register!(NightClap())
