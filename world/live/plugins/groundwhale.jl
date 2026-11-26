# A whale swims through the ground (s124, project projects/whale-through-the-ground.md). At noon something
# big swims through the island as if the ground were sea. You never see it: the meadow heaves up in a long
# rolling bulge that travels across the island with a rippling wake behind it, and whoever stands on it rides
# up and down; the friends run to it and surf its front. Step 1: the terrain mesh heaves, creatures ride it.
# s125: whale-sized (it read as a mole), and the ground layers lying ON the terrain (the brown path, the
# workshop's sand yard) heave with it: before, it swam invisibly under them.
#   Main.GROUNDWHALE[:force] = true   swim now (films, tests); [:from], [:to] = (x, y) of its path
const NG = NeverendingGame
isdefined(Main, :GROUNDWHALE) || Core.eval(Main, :(const GROUNDWHALE = Dict{Symbol,Any}()))
const GW = Main.GROUNDWHALE

const GW_FROM_H = 12.0
const GW_TO_H = 12.5
const GW_PATH = ((-26f0, -9f0), (26f0, 7f0))   # across the island through the middle
const GW_SPEED = 1.6f0      # m/s
const GW_HIGH = 1.5f0       # m, the heave over its back
const GW_LONG = 5.0f0       # m, along its back
const GW_WIDE = 2.6f0       # m, across
const GW_REACH = 4f0        # the heave and wake end GW_REACH * GW_WIDE to the side
const GW_WAKE = 24f0        # m of rippling wake behind the head
const GW_LAYERS = (:terrain, :area_path, :workshop_ground)   # meshes that lie on the ground and heave
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
# typed: GW is a Dict{Symbol,Any}, and an untyped path made every heave call dynamic (11 ms a frame, s125)
gw_path() = (NTuple{2,Float32}(get(GW, :from, GW_PATH[1])), NTuple{2,Float32}(get(GW, :to, GW_PATH[2])))::NTuple{2,NTuple{2,Float32}}

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
    (u > 3 * GW_LONG || u < -GW_WAKE || abs(v) > GW_REACH * GW_WIDE) && return 0f0
    back = GW_HIGH * exp(-(u / GW_LONG)^2 - (v / GW_WIDE)^2)
    wake = u < 0 ? 0.22f0 * sin(1.1f0 * u - 4f0 * Float32(t)) * exp(u / 9f0) * exp(-(v / (1.6f0 * GW_WIDE))^2) *
                   (1 - exp(-(u / 3f0)^2)) : 0f0
    return back + wake
end

"""
One ground mesh the whale lifts: its flat vertices `p0`/`n0`, the moved copies `pts`/`nrm`, and `band`, the
vertices the heave can reach anywhere along the path, sorted by `u0` (how far along the path they lie), so each
frame touches only the window round the head (`lo:hi` into `band`).
"""
mutable struct GWLayer
    plot::Any
    p0::Vector{Point3f}
    n0::Vector{Vec3f}
    pts::Vector{Point3f}
    nrm::Vector{Vec3f}
    faces::Any
    band::Vector{Int}
    u0::Vector{Float32}
    lo::Int
    hi::Int
end

function gw_layer(pl)
    m = pl[1][]
    p0 = Point3f.(GeometryBasics.coordinates(m))
    faces = GeometryBasics.faces(m)
    n0 = hasproperty(m, :normal) ? Vec3f.(m.normal) : Vec3f.(GeometryBasics.normals(p0, faces))
    (ax, ay), (bx, by) = gw_path()
    L = hypot(bx - ax, by - ay)
    band = Int[]; u0 = Float32[]
    for (i, p) in enumerate(p0)
        u, v = gw_local(p[1], p[2], 0f0)
        if -3 * GW_LONG < u < L + GW_WAKE && abs(v) < GW_REACH * GW_WIDE
            push!(band, i); push!(u0, u)
        end
    end
    o = sortperm(u0)
    return GWLayer(pl, p0, n0, copy(p0), copy(n0), faces, band[o], u0[o], 1, 0)
end

function gw_build!(game)
    sc = game.stage.scene
    layers = GWLayer[]
    for name in GW_LAYERS
        i = findfirst(p -> haskey(p.attributes, :name) && p.attributes[:name][] == name, sc.plots)
        i === nothing || push!(layers, gw_layer(sc.plots[i]))
    end
    GW[:layers] = layers
    GW[:scene] = sc
end

"Put the vertices `band[r]` of a layer back flat."
function gw_restore!(ly::GWLayer, r)
    for k in r
        i = ly.band[k]
        ly.pts[i] = ly.p0[i]; ly.nrm[i] = ly.n0[i]
    end
end

"""
Lift the vertices near the head; their normals are the flat ground's tilted by the heave's slope, so no
normal_mesh over the whole terrain each frame (that took 33 ms).
"""
function gw_draw_layer!(ly::GWLayer, s, t)
    lo = searchsortedfirst(ly.u0, s - GW_WAKE)
    hi = searchsortedlast(ly.u0, s + 3 * GW_LONG)
    gw_restore!(ly, ly.lo:min(ly.hi, lo - 1))      # the wake's tail moved past these
    gw_restore!(ly, max(ly.lo, hi + 1):ly.hi)      # the whale started again from the beginning
    ly.lo, ly.hi = lo, hi
    e = 0.15f0
    for k in lo:hi
        i = ly.band[k]
        p = ly.p0[i]
        h = gw_heave(p[1], p[2], s, t)
        if h == 0f0
            ly.pts[i] = p; ly.nrm[i] = ly.n0[i]; continue
        end
        hx = (gw_heave(p[1] + e, p[2], s, t) - h) / e
        hy = (gw_heave(p[1], p[2] + e, s, t) - h) / e
        n = ly.n0[i]
        ly.pts[i] = Point3f(p[1], p[2], p[3] + h)
        ly.nrm[i] = normalize(Vec3f(n[1] - hx, n[2] - hy, n[3]))
    end
    lo <= hi && Makie.update!(ly.plot; arg1 = GeometryBasics.Mesh(ly.pts, ly.faces; normal = ly.nrm))
end

function gw_draw!(game, s, t)
    for ly in get(GW, :layers, GWLayer[])
        gw_draw_layer!(ly, s, t)
    end
end

function gw_flat!(game)
    for ly in get(GW, :layers, GWLayer[])
        ly.pts .= ly.p0; ly.nrm .= ly.n0
        ly.lo, ly.hi = 1, 0
        Makie.update!(ly.plot; arg1 = GeometryBasics.Mesh(ly.p0, ly.faces; normal = ly.n0))
    end
end

function gw_ride!(sys::GroundWhale, game, dt)
    w = game.world
    (ax, ay), (bx, by) = gw_path()
    L = hypot(bx - ax, by - ay)
    hx, hy = ax + (bx - ax) / L * sys.s, ay + (by - ay) / L * sys.s
    ahead = Point3f(hx + (bx - ax) / L * 2f0, hy + (by - ay) / L * 2f0, 0)
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
        if h > 0.6f0 && get(sys.said, c.id, -1e9) < w.t - 8
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
        c.goal.kind == :groundwhale && (c.goal = NG.Goal())   # the goal field cannot be nothing
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
    if sys.s > L + GW_WAKE
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
