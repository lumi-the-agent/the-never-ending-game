# See by clapping, live (s130; project island-echo). At night Lumi claps now and then, and the island lights up
# where the sound lands: 1500 rays leave the clap in every direction and are marched through the island's terrain
# (the ground under them, one mirror bounce), each hit glows when the sound gets there, slowed 60 times, so a ring
# runs out over the grass and a second, fainter one comes back. Rays against trees and props come with the
# traced version (physics/echo.jl, the BVH of the whole stage; todo #622).
isdefined(Main, :NIGHTCLAP) || Core.eval(Main, :(const NIGHTCLAP = Dict{Symbol,Any}()))
const NG = NeverendingGame
const NC = Main.NIGHTCLAP
const NC_RAYS = 1500
const NC_SLOTS = 400
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
    return
end

function NG.step!(::NightClap, game, dt)
    game.stage === nothing && return
    (haskey(NC, :plot) && NC[:plot].parent === game.stage.scene) || nc_build!(game)
    NG.path_traced(game) && return        # moving glowing points leak area lights in the tracer
    w = game.world; now = time()
    if NC[:hits] === nothing && ((NG.night_factor(w) > 0.35f0 && now - NC[:last] > NC_EVERY) || get(NC, :force, false))
        me = NG.creature(w, "Lumi")
        me === nothing && return
        NC[:force] = false
        P, T = nc_hits(w.island, Point3f(me.pos) + Point3f(0, 0, 1.2f0))
        NC[:hits] = (P, T, now); NC[:last] = now
    end
    NC[:hits] === nothing && return
    P, T, t0 = NC[:hits]
    t = Float32(now - t0)
    pos = fill(NC_HIDE, NC_SLOTS); ms = zeros(Float32, NC_SLOTS); n = 0
    for k in eachindex(P)
        age = t - NC_SLOW * T[k]
        (0f0 <= age < NC_FADE && n < NC_SLOTS) || continue
        n += 1; pos[n] = P[k]; ms[n] = 0.07f0 * sqrt(1f0 - age / NC_FADE)
    end
    Makie.update!(NC[:plot]; arg1 = pos, markersize = ms)
    t > NC_SLOW * maximum(T; init = 0f0) + NC_FADE && (NC[:hits] = nothing)
    return
end

NG.stop!(::NightClap, game) = haskey(NC, :plot) && (NC[:plot].visible[] = false)

register!(NightClap())
