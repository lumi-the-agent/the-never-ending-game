# Personal space: creatures never walk through each other, tree trunks, rocks or bushes.
# Every frame, overlapping pairs are pushed apart (each half the overlap, a creature the
# player steers is not pushed by others), and creatures are pushed out of solid props.
const NG = NeverendingGame

const SPACE = 1.0f0            # creatures keep at least SPACE * (r_a + r_b) between their centres
const SOLID = Dict(:tree => 0.35f0, :rock => 0.75f0, :bush => 0.65f0)   # footprint radius at scale 1
# The player squeezes through the leafy rim of a bush: a tree, a bush and a bush around Lumi made a pocket
# it could not leave with W/A/D (hide and seek, perfectionist-0046). Critters keep the whole bush.
const SQUEEZE = Dict(:bush => 0.35f0)
# and slips between two trunks a critter's width apart (0.45 of its radius against solids instead of 0.7)
body(c) = c.controlled ? 0.45f0 : 0.7f0

"""
A walker pushed out of a solid whose goal target lies within the solid's reach can never get there: it
stepped in and was pushed out every frame, and its position and heading flip-flopped for up to 12 s until
`unstick!` gave up (the human's vibrating sheep in first-flight.mp4, todo #402). It arrives at the edge
instead and does what it came for there (`until` set as on arrival, or the engine replaces the goal at once).
"""
function arrive_at_edge!(c, w, q, need)
    g = c.goal
    (c.controlled || g.arrived || g.kind in (:follow, :interact, :user)) && return
    hypot(g.target[1] - q[1], g.target[2] - q[2]) < need || return
    g.arrived = true
    g.until = w.t + g.duration
    return
end
held(c) = c.controlled || c.goal.kind === :giant
"Every (centre, radius) other plugins made solid (Main.EXTRA_SOLIDS, workshop.jl)."
extra_solids() = isdefined(Main, :EXTRA_SOLIDS) ? collect(Iterators.flatten(values(Main.EXTRA_SOLIDS))) : Tuple{Point2f,Float32}[]
footprint(c, kind) = c.controlled ? get(SQUEEZE, kind, get(SOLID, kind, 0.0f0)) : get(SOLID, kind, 0.0f0)

struct Separation <: System
    radii::Dict{String,Float32}
    progress::Dict{Int32,Tuple{UInt,Float32,Float64}}   # creature id => (its goal, the closest it got, when)
    side::Dict{Int32,Tuple{Float32,Float64,Point3f,Float64}}   # steered creature id => (slide side, last contact, progress mark and its time)
    backing::Dict{Int32,Float64}                                # steered creature id => backs out of a notch until
end
Separation() = Separation(Dict{String,Float32}(), Dict{Int32,Tuple{UInt,Float32,Float64}}(),
                          Dict{Int32,Tuple{Float32,Float64,Point3f,Float64}}(), Dict{Int32,Float64}())

"""
A creature the player steers into solids (bushes, trunks, rocks, the pond) slides along them instead
of running in place. The push out is radial, so W held straight at a bush, or into the notch between a
tree and a bush, stood still (perfectionist-0046: 48 s in the berry race, 45 s in hide and seek).
The step W loses goes along the rim of what it touches (the summed push), the way the heading leans;
head-on, towards the nearer open end (`open_side`), kept while in contact. Wedged (no progress for
0.5 s) it backs out for 0.7 s, away from what it touches and from where W pushes. Water flips the side.
"""
function slide_steered!(s::Separation, game, dt)
    w = game.world
    pond = (a = get(game.plugins, "areas", nothing); a !== nothing && isdefined(a.mod, :POND) ? (a.mod.POND, a.mod.POND_R) : nothing)
    for c in w.creatures
        (c.controlled && c.action in (:walk, :run)) || continue
        rc = radius(s, c)
        nx = 0.0f0; ny = 0.0f0
        for p in w.props
            r0 = footprint(c, p.kind)
            r0 == 0 && continue
            dx = c.pos[1] - p.pos[1]; dy = c.pos[2] - p.pos[2]
            d = sqrt(dx^2 + dy^2)
            d < r0 * p.scale + body(c) * rc + 0.12f0 && d > 1.0f-4 && (nx += dx / d; ny += dy / d)
        end
        if pond !== nothing
            dx = c.pos[1] - pond[1][1]; dy = c.pos[2] - pond[1][2]
            d = sqrt(dx^2 + dy^2)
            d < pond[2] + 0.15f0 + 0.6f0 * rc && d > 1.0f-4 && (nx += dx / d; ny += dy / d)
        end
        for (q, r) in extra_solids()          # the workbench and crates (s54): slide along them too
            dx = c.pos[1] - q[1]; dy = c.pos[2] - q[2]
            d = sqrt(dx^2 + dy^2)
            d < r + body(c) * rc + 0.12f0 && d > 1.0f-4 && (nx += dx / d; ny += dy / d)
        end
        hx, hy = cos(c.yaw), sin(c.yaw)
        n = sqrt(nx^2 + ny^2)
        side, since, ref, reft = get(s.side, c.id, (0.0f0, -Inf, c.pos, w.t))
        if n < 1.0f-3 || -(hx * nx + hy * ny) / n < 0.1f0      # free, or brushing past: nothing to do
            w.t - since > 1 && delete!(s.side, c.id)
            continue
        end
        nx /= n; ny /= n
        into = -(hx * nx + hy * ny)                # 1: walking straight into it
        tx, ty = -ny, nx                           # along the blockage's rim (one way)
        lean = hx * tx + hy * ty                   # how the heading leans along it
        if abs(lean) > 0.3f0
            side = sign(lean)                      # the way W already slides
        elseif side == 0 || w.t - since > 1
            side = open_side(s, game, c, hx, hy, tx, ty, pond, lean)   # head-on: the nearer open end
        end
        jammed = false
        if w.t - reft > 0.5
            jammed = hypot(c.pos[1] - ref[1], c.pos[2] - ref[2]) < 0.15f0
            ref, reft = c.pos, w.t
        end
        full = NG.species_of(c).speed * (c.action === :run ? 2.2f0 : 1.0f0) * Float32(dt)   # this frame's step forward
        # wedged in a notch: back out of it for a moment (faster than W walks in) while sliding
        back = jammed || get(s.backing, c.id, 0.0) > w.t ? 1.6f0 * full : 0.0f0
        jammed && (s.backing[c.id] = w.t + 0.7)
        along = full * (back > 0 ? 1.0f0 : into)
        bx, by = nx - hx, ny - hy                  # out: away from what it touches and from where W pushes
        b = max(sqrt(bx^2 + by^2), 1.0f-3)
        vx = side * tx * along + back * bx / b
        vy = side * ty * along + back * by / b
        if !nudge!(c, w, vx, vy)   # water on that side
            side = -side
            ref, reft = c.pos, w.t
        end
        s.side[c.id] = (side, w.t, ref, reft)
    end
    return
end

"Which way (+1 left, -1 right of the heading) the blockage ends sooner: the first spot a step ahead clear of solids and water."
function open_side(s::Separation, game, c, hx, hy, lx, ly, pond, lean)
    w = game.world
    rc = radius(s, c)
    clear(x, y) = NG.on_land(w.island, x, y; margin = 0.1f0) &&
        (pond === nothing || hypot(x - pond[1][1], y - pond[1][2]) > pond[2] + 0.2f0 + 0.6f0 * rc) &&
        all(p -> (r0 = footprint(c, p.kind); r0 == 0 || hypot(x - p.pos[1], y - p.pos[2]) > r0 * p.scale + body(c) * rc + 0.1f0), w.props) &&
        all(((q, r),) -> hypot(x - q[1], y - q[2]) > r + body(c) * rc + 0.1f0, extra_solids())
    reach(sg) = something(findfirst(k -> clear(c.pos[1] + sg * lx * k + 0.9f0 * hx, c.pos[2] + sg * ly * k + 0.9f0 * hy), 0.25f0:0.25f0:8.0f0), 99)
    l, r = reach(1.0f0), reach(-1.0f0)
    return l < r ? 1.0f0 : r < l ? -1.0f0 : lean >= 0 ? 1.0f0 : -1.0f0
end

const STUCK_SECONDS = 12.0

"""
A creature walking to a goal it cannot reach (pushed back by a bush, a trunk or another creature)
gives up after STUCK_SECONDS without getting 0.25 m closer and picks something else to do.
Critters stood 'off to the berry bushes' for hours (perfectionist s36).
"""
function unstick!(s::Separation, w)
    for c in w.creatures
        g = c.goal
        if c.controlled || g.arrived || g.kind in (:follow, :interact, :user)
            delete!(s.progress, c.id)
            continue
        end
        d = hypot(g.target[1] - c.pos[1], g.target[2] - c.pos[2])
        key = objectid(g)
        old = get(s.progress, c.id, nothing)
        if old === nothing || old[1] != key || d < old[2] - 0.25f0
            s.progress[c.id] = (key, d, w.t)
        elseif w.t - old[3] > STUCK_SECONDS
            delete!(s.progress, c.id)
            # a dancer stuck on the way to its ring spot counts as there: the dancing ring places it itself
            # (s43: a new goal broke the whole parade party)
            g.kind === :circle ? (g.arrived = true; g.until = w.t + g.duration) : NG.choose_goal!(c, w)   # until set as on arrival, or the engine replaces the goal at once
        end
    end
end

radius(s::Separation, c) = get!(() -> NG.body_radius(NG.species_of(c)), s.radii, c.species)

"Move `c` by (dx, dy) if the new spot is ground or a walkway (the pier); false when it cannot move there."
function nudge!(c, w, dx, dy)
    x, y = c.pos[1] + dx, c.pos[2] + dy
    hw = NG.walkway_height(x, y)
    if hw !== nothing
        c.pos = Point3f(x, y, max(hw, NG.terrain_height(w.island, x, y)))
    elseif NG.on_land(w.island, x, y; margin = 0.1f0)
        c.pos = NG.ground(w.island, (x, y))
    else
        return false
    end
    return true
end

"Moving `c` by (dx, dy) would put it inside a tree, rock or bush footprint."
function walled(s::Separation, w, c, dx, dy)
    x, y = c.pos[1] + dx, c.pos[2] + dy
    for p in w.props
        r0 = footprint(c, p.kind)
        r0 == 0 && continue
        need = r0 * p.scale + body(c) * radius(s, c)
        (x - p.pos[1])^2 + (y - p.pos[2])^2 < need^2 && return true
    end
    return false
end

NeverendingGame.start!(s::Separation, game) = (merge!(NG.SOLID_FOOTPRINT, SOLID); nothing)   # the engine turns a player's creature away from them (face_open!)

function NeverendingGame.step!(s::Separation, game, dt)
    w = game.world
    cs = w.creatures
    for i in eachindex(cs), j in (i + 1):length(cs)
        a = cs[i]; b = cs[j]
        dx = b.pos[1] - a.pos[1]; dy = b.pos[2] - a.pos[2]
        need = SPACE * (radius(s, a) + radius(s, b))
        d2 = dx^2 + dy^2
        d2 >= need^2 && continue
        d = sqrt(d2)
        ux, uy = d > 1.0f-4 ? (dx / d, dy / d) : (cos(a.seed * 7), sin(a.seed * 7))
        push = need - d
        # a steered creature, and a giant Lumi with its riders (giant.jl: a 0.2 m push grew 5x on the giant), are not pushed
        fa = held(a) ? 0.0f0 : held(b) ? 1.0f0 : 0.5f0
        held(a) && held(b) && continue
        # one at the shore cannot step back: the other takes the whole push (they stayed 0.74 m apart, s36 suite)
        # nor can one with a trunk or bush at its back (s53: Gloop and Wibbles 0.79 m apart by a tree, the
        # solid pushed the one back in every frame): the side with room takes the push
        oka = fa == 0 || (!walled(s, w, a, -ux * push * fa, -uy * push * fa) && nudge!(a, w, -ux * push * fa, -uy * push * fa))
        okb = fa == 1 || (!walled(s, w, b, ux * push * (1 - fa), uy * push * (1 - fa)) && nudge!(b, w, ux * push * (1 - fa), uy * push * (1 - fa)))
        oka || held(b) || nudge!(b, w, ux * push * fa, uy * push * fa)
        okb || held(a) || nudge!(a, w, -ux * push * (1 - fa), -uy * push * (1 - fa))
    end
    for c in cs, p in w.props
        r0 = footprint(c, p.kind)
        r0 == 0 && continue
        dx = c.pos[1] - p.pos[1]; dy = c.pos[2] - p.pos[2]
        need = r0 * p.scale + body(c) * radius(s, c)
        d2 = dx^2 + dy^2
        d2 >= need^2 && continue
        d = sqrt(d2)
        ux, uy = d > 1.0f-4 ? (dx / d, dy / d) : (1.0f0, 0.0f0)
        nudge!(c, w, ux * (need - d), uy * (need - d))
        arrive_at_edge!(c, w, p.pos, need)
    end
    # solid things other plugins put down without a prop (the workbench and crates, workshop.jl): (centre, radius)
    if isdefined(Main, :EXTRA_SOLIDS)
        for list in values(Main.EXTRA_SOLIDS), (q, r) in list, c in cs
            dx = c.pos[1] - q[1]; dy = c.pos[2] - q[2]
            need = r + body(c) * radius(s, c)
            d2 = dx^2 + dy^2
            d2 >= need^2 && continue
            d = sqrt(d2)
            ux, uy = d > 1.0f-4 ? (dx / d, dy / d) : (1.0f0, 0.0f0)
            nudge!(c, w, ux * (need - d), uy * (need - d))
        end
    end
    # the lily pond (areas.jl) is water: nobody walks into it (Lumi chatted standing on a lily pad, s40)
    a = get(game.plugins, "areas", nothing)
    if a !== nothing && isdefined(a.mod, :POND)
        pc, pr = a.mod.POND, a.mod.POND_R
        for c in cs
            dx = c.pos[1] - pc[1]; dy = c.pos[2] - pc[2]
            need = pr + 0.1f0 + 0.6f0 * radius(s, c)
            d2 = dx^2 + dy^2
            d2 >= need^2 && continue
            d = sqrt(d2)
            ux, uy = d > 1.0f-4 ? (dx / d, dy / d) : (1.0f0, 0.0f0)
            nudge!(c, w, ux * (need - d), uy * (need - d))
            end
    end
    slide_steered!(s, game, dt)
    unstick!(s, w)
    return
end

register!(Separation())
