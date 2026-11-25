# Beds: critters bed down at the edge of a tree's crown, facing out over the meadow, instead of
# against the trunk where the crown hides them (the engine's :sleep goal walks to the nearest tree's
# foot). A sleeper you can see makes the night: the night shots frame it in front of the cottage,
# the pond or the pier (perfectionist s33: the night camera showed empty sky and crowns).
const NG = NeverendingGame

const CROWN = 2.3f0          # crown radius per tree scale: the bed lies just outside it
const KEEP_CLEAR = 1.0f0     # metres from bushes, rocks, actors and the other beds

mutable struct Beds <: System
    done::Dict{Int32,Any}    # creature id => the sleep goal already moved (the same object)
    faced::Set{Int32}        # sleepers turned to face out
    yawns::Dict{Int32,Float64}   # sleepers yawning before they nod off => until (w.t)
end
Beds() = Beds(Dict{Int32,Any}(), Set{Int32}(), Dict{Int32,Float64}())
const YAWN = 2.6             # s: a big yawn at the bed before the eyes close (todo #325)

"A bed spot by `tree`, out of every crown and clear of things, near the side facing `from`; or nothing."
function bed_spot(w, tree, from, taken)
    a0 = Float32(atan(from[2] - tree.pos[2], from[1] - tree.pos[1]))
    for r in (CROWN * tree.scale + 0.5f0, CROWN * tree.scale + 1.4f0), da in (0f0, 0.5f0, -0.5f0, 1f0, -1f0, 1.5f0, -1.5f0, 2.1f0, -2.1f0, 2.7f0, -2.7f0, 3.14f0)
        a = a0 + da
        p = Point2f(tree.pos[1] + r * cos(a), tree.pos[2] + r * sin(a))
        NG.on_land(w.island, p[1], p[2]; margin = 2f0) || continue
        ok = true
        for q in w.props
            d = hypot(q.pos[1] - p[1], q.pos[2] - p[2])
            q.kind === :tree && d < CROWN * q.scale + 0.3f0 && (ok = false; break)
            q.kind in (:bush, :rock) && d < KEEP_CLEAR + 0.5f0 * q.scale && (ok = false; break)
        end
        ok || continue
        any(x -> x isa NG.AssetActor && hypot(x.pos[1] - p[1], x.pos[2] - p[2]) < KEEP_CLEAR + 0.4f0 * x.scale, w.actors) && continue
        any(t -> hypot(t[1] - p[1], t[2] - p[2]) < 1.6f0, taken) && continue
        return NG.ground(w.island, (p[1], p[2])), a
    end
    return nothing
end

"""
Daytime naps one at a time (perfectionist s85: at 13:25 five of ten friends were asleep and the island looked dead
when a visitor is most likely to come). Between 10:00 and 16:00 only the most tired sleeper keeps napping; the
others wake up a little rested (energy to 0.65) and go back to their day. Night sleep is untouched.
"""
function one_nap!(w)
    h = 24 * NG.daytime(w)
    10 <= h < 16 || return
    w.t - get(NAP, :at, -Inf) < 3 && return
    NAP[:at] = w.t
    sleepers = [c for c in w.creatures if c.goal.kind === :sleep && !c.controlled && c.name != "Lumi"]
    length(sleepers) <= 1 && return
    sort!(sleepers; by = c -> c.needs.energy)
    for c in sleepers[2:end]
        c.needs.energy = max(c.needs.energy, 0.65f0)
        NG.choose_goal!(c, w)
        NG.emit!(w, :nap_woken; who = c.name)
    end
end
const NAP = Dict{Symbol,Float64}()

function NG.step!(s::Beds, game, dt)
    w = game.world
    one_nap!(w)
    for c in w.creatures
        g = c.goal
        if g.kind !== :sleep || c.controlled
            delete!(s.done, c.id); delete!(s.faced, c.id); delete!(s.yawns, c.id)
            continue
        end
        # the yawn is over (or a reload forgot it: never yawn all night): now sleep
        if g.action === :yawn && (!haskey(s.yawns, c.id) || w.t >= s.yawns[c.id])
            g.action = :sleep
            delete!(s.yawns, c.id)
        end
        if get(s.done, c.id, nothing) !== g && !g.arrived
            s.done[c.id] = g; delete!(s.faced, c.id)
            tree, d = NG.nearest(p -> p.kind === :tree, w.props, g.target)
            (tree === nothing || d > 3f0) && continue          # not a tree bed (slept where it stood)
            taken = [o.goal.target for o in w.creatures if o !== c && o.goal.kind === :sleep]
            # the nearest tree first; one in a grove has no clear edge: then the next trees within 15 m
            trees = sort!([p for p in w.props if p.kind === :tree && hypot(p.pos[1] - c.pos[1], p.pos[2] - c.pos[2]) < 15f0];
                          by = p -> (p !== tree, hypot(p.pos[1] - c.pos[1], p.pos[2] - c.pos[2])))
            for t in trees
                spot = bed_spot(w, t, c.pos, taken)
                spot === nothing || (g.target = spot[1]; break)
            end
        elseif g.arrived && c.action === :sleep && !(c.id in s.faced) && get(s.done, c.id, nothing) === g
            # face out over the meadow, away from the trunk
            tree, _ = NG.nearest(p -> p.kind === :tree, w.props, c.pos)
            tree === nothing || (c.yaw = Float32(atan(c.pos[2] - tree.pos[2], c.pos[1] - tree.pos[1])) - NG.species_of(c).heading)
            push!(s.faced, c.id)
            # a big yawn first (only at night: a nap by day just drops off)
            if NG.is_night(w)
                g.action = :yawn
                s.yawns[c.id] = w.t + YAWN
                g.until += YAWN
                spread_yawn!(w, c, 1)
            end
        end
    end
    catch_yawns!(w)
    return
end

# ---------------------------------------------------------------- yawns are catching (s71, a wish)

isdefined(Main, :YAWNS) || Core.eval(Main, :(const YAWNS = Dict{Int32,Tuple{Float64,Int}}()))
const Y = Main.YAWNS          # creature id => (when it catches the yawn, how many yawns away from the first)
const YAWN_REACH = 7f0

can_catch(c) = !c.controlled && c.action !== :sleep && c.action !== :yawn && c.goal.kind ∉ NG.BUSY_GOALS

"Awake friends near `c` catch its yawn a moment later."
function spread_yawn!(w, c, depth)
    for f in w.creatures
        (f.id == c.id || haskey(Y, f.id) || !can_catch(f)) && continue
        hypot(f.pos[1] - c.pos[1], f.pos[2] - c.pos[2]) < YAWN_REACH || continue
        Y[f.id] = (w.t + 0.6 + rand(w.rng), depth)
    end
end

function catch_yawns!(w)
    isempty(Y) && return
    for (id, (t, depth)) in collect(Y)
        w.t < t && continue
        delete!(Y, id)
        f = NG.creature(w, id)
        (f === nothing || !can_catch(f)) && continue
        NG.feel!(w, f, :yawn; seconds = 2.4) || continue
        rand(w.rng) < 0.4 && NG.say!(w, f, rand(w.rng, ("*yaaawn*", "mmh... *yawn*", "oh no, now I'm yawning")); duration = 1.6)
        NG.emit!(w, :yawn_caught; who = f.name, depth = depth)
        depth < 2 && rand(w.rng) < 0.5 && spread_yawn!(w, f, depth + 1)
    end
end

register!(Beds())
