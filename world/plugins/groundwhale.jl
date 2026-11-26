# A whale swims through the ground (s124, project projects/whale-through-the-ground.md). At noon something
# big swims through the island as if the ground were sea. You never see it: the meadow heaves up in a long
# rolling bulge that travels across the island with a rippling wake behind it, and whoever stands on it rides
# up and down; the friends run to it and surf its front. Step 1: the terrain mesh heaves, creatures ride it.
#   Main.GROUNDWHALE[:force] = true   swim now (films, tests); [:from], [:to] = (x, y) of its path
const NG = NeverendingGame
isdefined(Main, :GROUNDWHALE) || Core.eval(Main, :(const GROUNDWHALE = Dict{Symbol,Any}()))
const GW = Main.GROUNDWHALE

const GW_FROM_H = 12.0
const GW_TO_H = 12.5
const GW_PATH = ((-26f0, -9f0), (26f0, 7f0))   # across the island through the middle
const GW_SPEED = 1.6f0      # m/s
const GW_HIGH = 1.1f0       # m, the heave over its back
const GW_LONG = 2.8f0       # m, along its back
const GW_WIDE = 1.7f0       # m, across
const GW_SURFERS = 4
const GW_LINES = ("The ground is MOVING!", "Surf's up!", "Whoa whoa whoa", "Something's under there!",
                  "It went under me!", "Again! Again!", "Hold on to the grass!")
push!(NG.BUSY_GOALS, :groundwhale)

mutable struct GroundWhale <: System
    on::Bool
    day::Int
    s::Float32                       # how far along its path the head is, m
    said::Dict{Int32,Float64}
end

gw_hour(w) = 24 * NG.daytime(w)
gw_path() = (get(GW, :from, GW_PATH[1]), get(GW, :to, GW_PATH[2]))

"Along-track and across-track coordinates of (x, y) relative to the whale's head at `s` metres along its path."
function gw_local(x, y, s)
    (ax, ay), (bx, by) = gw_path()
    L = hypot(bx - ax, by - ay)
    dx, dy = (bx - ax) / L, (by - ay) / L
    hx, hy = ax + dx * s, ay + dy * s
    rx, ry = x - hx, y - hy
    return rx * dx + ry * dy, -rx * dy + ry * dx
end

"How far the ground at (x, y) is lifted: the heave over the whale's back and the rippling wake behind it."
function gw_heave(x, y, s, t)
    u, v = gw_local(x, y, s)
    (u > 3 * GW_LONG || u < -24f0 || abs(v) > 5 * GW_WIDE) && return 0f0
    back = GW_HIGH * exp(-(u / GW_LONG)^2 - (v / GW_WIDE)^2)
    wake = u < 0 ? 0.16f0 * sin(1.6f0 * u - 5f0 * Float32(t)) * exp(u / 9f0) * exp(-(v / (2.2f0 * GW_WIDE))^2) *
                   (1 - exp(-(u / 2f0)^2)) : 0f0
    return back + wake
end

function gw_build!(game)
    sc = game.stage.scene
    i = findfirst(p -> haskey(p.attributes, :name) && p.attributes[:name][] == :terrain, sc.plots)
    i === nothing && return
    pl = sc.plots[i]
    m = pl[1][]
    GW[:plot] = pl
    p0 = copy(GeometryBasics.coordinates(m))
    GW[:p0] = p0
    GW[:faces] = GeometryBasics.faces(m)
    GW[:n0] = hasproperty(m, :normal) ? Vec3f.(m.normal) : Vec3f.(GeometryBasics.normals(p0, GW[:faces]))
    GW[:pts] = copy(p0); GW[:nrm] = copy(GW[:n0])
    # vertices the heave can reach anywhere along its path
    (ax, ay), (bx, by) = gw_path()
    L = hypot(bx - ax, by - ay)
    GW[:band] = [i for (i, p) in enumerate(p0) if (u = gw_local(p[1], p[2], 0f0); -3f0 < u[1] < L + 3f0 && abs(u[2]) < 5 * GW_WIDE)]
    GW[:scene] = sc
end

"""
Only the ground near the path moves (`:band`, the vertices within reach of the heave); their normals are the
flat ground's tilted by the heave's slope, so no normal_mesh over the whole terrain each frame (that took 33 ms).
"""
function gw_draw!(game, s, t)
    haskey(GW, :plot) || return
    p0 = GW[:p0]; n0 = GW[:n0]; pts = GW[:pts]; nrm = GW[:nrm]
    for i in GW[:band]
        p = p0[i]
        h = gw_heave(p[1], p[2], s, t)
        if h == 0f0
            pts[i] = p; nrm[i] = n0[i]; continue
        end
        e = 0.15f0
        hx = (gw_heave(p[1] + e, p[2], s, t) - h) / e
        hy = (gw_heave(p[1], p[2] + e, s, t) - h) / e
        pts[i] = Point3f(p[1], p[2], p[3] + h)
        nrm[i] = normalize(Vec3f(n0[i][1] - hx, n0[i][2] - hy, n0[i][3]))
    end
    Makie.update!(GW[:plot]; arg1 = GeometryBasics.Mesh(pts, GW[:faces]; normal = nrm))
end

function gw_flat!(game)
    haskey(GW, :plot) || return
    GW[:pts] .= GW[:p0]; GW[:nrm] .= GW[:n0]
    Makie.update!(GW[:plot]; arg1 = GeometryBasics.Mesh(GW[:p0], GW[:faces]; normal = GW[:n0]))
end

function gw_ride!(sys::GroundWhale, game, dt)
    w = game.world
    (ax, ay), (bx, by) = gw_path()
    L = hypot(bx - ax, by - ay)
    hx, hy = ax + (bx - ax) / L * sys.s, ay + (by - ay) / L * sys.s
    ahead = Point3f(hx + (bx - ax) / L * 1.2f0, hy + (by - ay) / L * 1.2f0, 0)
    friends = sort([c for c in w.creatures if c.name != "Lumi"]; by = c -> hypot(c.pos[1] - hx, c.pos[2] - hy))
    for (k, c) in enumerate(friends)
        if k <= GW_SURFERS
            c.goal = NG.Goal(:groundwhale, ahead, :play, 1.0, Inf, false, 0, true)
        end
        h = gw_heave(c.pos[1], c.pos[2], sys.s, w.t)
        h > 0.02f0 || continue
        # sliding down the front of the heave: pushed along with the whale
        u, _ = gw_local(c.pos[1], c.pos[2], sys.s)
        push = u > 0 ? 0.9f0 * GW_SPEED * dt : 0f0
        x, y = c.pos[1] + (bx - ax) / L * push, c.pos[2] + (by - ay) / L * push
        c.pos = Point3f(x, y, NG.terrain_height(w.island, x, y) + gw_heave(x, y, sys.s, w.t))
        if h > 0.5f0 && get(sys.said, c.id, -1e9) < w.t - 8
            sys.said[c.id] = w.t
            NG.say!(w, c, rand(w.rng, GW_LINES))
            NG.emit!(w, :whale_ride; who = c.name)
        end
    end
end

function gw_end!(sys::GroundWhale, game)
    sys.on = false
    gw_flat!(game)
    for c in game.world.creatures
        c.goal !== nothing && c.goal.kind == :groundwhale && (c.goal = nothing)
    end
end

function NG.start!(sys::GroundWhale, game)
    game.stage === nothing || gw_build!(game)
end

function NG.step!(sys::GroundWhale, game, dt)
    w = game.world
    GW[:sys] = sys
    game.stage === nothing || get(GW, :scene, nothing) === game.stage.scene || gw_build!(game)
    force = get(GW, :force, false)
    if !sys.on
        day = floor(Int, w.t / w.day_length)
        (force || (GW_FROM_H <= gw_hour(w) < GW_TO_H && day != sys.day && game.minigame === nothing)) || return
        sys.on = true; sys.day = day; sys.s = 0f0
        empty!(sys.said)
    end
    dt = Float32(clamp(dt, 0.0, 0.05))
    dt <= 0 && return
    (ax, ay), (bx, by) = gw_path()
    L = hypot(bx - ax, by - ay)
    sys.s += GW_SPEED * dt
    if sys.s > L + 20
        force ? (sys.s = 0f0) : (gw_end!(sys, game); return)
    end
    gw_ride!(sys, game, dt)
    gw_draw!(game, sys.s, w.t)
    return
end

function NG.stop!(sys::GroundWhale, game)
    sys.on && gw_end!(sys, game)
end

register!(GroundWhale(false, -1, 0f0, Dict{Int32,Float64}()))
