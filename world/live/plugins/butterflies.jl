# Butterflies over the golden flower field (meadow.jl FLOWER_FIELD, flowers from flowerfield.jl): by day a
# few pastel butterflies flutter from flower to flower, rest on one with slowly beating wings, and fly on.
# One instanced plot (two wings each), hidden at night.
# s42: anyone walking through the field startles them up and away, and when Lumi does it a playful
# critter nearby runs after one and pounces (a little jump where it just was).
const NG = NeverendingGame

const N_FLIES = 7
const WING = Vec3f(0.13, 0.1, 0.008)
const HIND = Vec3f(0.09, 0.07, 0.008)
const BODY = Vec3f(0.08, 0.018, 0.018)
# no yellow: over the golden field (s43) a yellow butterfly vanished; blues, lilac, white and coral stand out
const COLOURS = (RGBf(0.45, 0.62, 1.0), RGBf(0.98, 0.97, 0.92), RGBf(0.86, 0.6, 1.0), RGBf(1.0, 0.45, 0.38), RGBf(0.45, 0.85, 0.95))
const HIDE = Point3f(0, 0, -50)

isdefined(Main, :BUTTERFLY_PLOTS) || Core.eval(Main, :(const BUTTERFLY_PLOTS = Dict{Symbol,Any}()))
const BP = Main.BUTTERFLY_PLOTS

mutable struct Fly
    pos::Point3f
    target::Point3f
    rest::Float64       # seconds left resting on a flower (0: flying)
    yaw::Float32
    phase::Float32
    colour::RGBf
    fast::Float64       # seconds left of a startled, quick climb away
end

mutable struct Butterflies <: System
    flies::Vector{Fly}
    chased::Dict{Int32,Float64}   # critter id => sim time of its last chase (one every 25 s each)
end
Butterflies() = Butterflies(Fly[], Dict{Int32,Float64}())

const STARTLE = 1.1f0     # m: a walking creature this close sends a butterfly up
const CHASE_PULL = 7f0    # m: how far a critter sees Lumi scare them up
const REJOIN = Dict{Int32,Float64}()   # parade friend id => when it dashed off after a butterfly
:chase in NG.BUSY_GOALS || push!(NG.BUSY_GOALS, :chase)   # a chaser is not pulled into a chat

"Fly off to a flower further away, quick and climbing."
function startle!(f, w, fl, from)
    far = [p for p in fl if flat(p.pos, from) > 2.5f0]
    p = isempty(far) ? fl[rand(w.rng, 1:length(fl))] : far[rand(w.rng, 1:length(far))]
    f.target = perch(p); f.rest = 0.0; f.fast = 2.0
end

"A playful free critter near Lumi runs after butterfly `f` and pounces where it was."
function chase!(s, w, me, f)
    best = nothing; bd = CHASE_PULL
    for c in w.creatures
        (c.controlled || c.species == "Lumi" || c.action === :sleep || (NG.busy(c) && c.goal.kind !== :follow) || c.goal.kind === :sleep) && continue   # a parade friend may dash off too
        w.t - get(s.chased, c.id, -Inf) < 25 && continue
        d = flat(c.pos, f.pos)
        d < bd && (best = c; bd = d)
    end
    best === nothing && return
    any(c -> c.goal.kind === :chase, w.creatures) && return
    s.chased[best.id] = w.t
    best.goal.kind === :follow && (REJOIN[best.id] = w.t)   # a parade friend runs back into line afterwards
    best.goal = NG.Goal(:chase, NG.ground(w.island, (f.pos[1], f.pos[2])), :jump, 1.0, w.t + 8, false, 0, true)
    NG.say!(w, best, rand(w.rng, ("Butterflies!", "Ooh, wait for me!", "I'll catch one!")); duration = 2)
    emote(best.id, :note)
end
emote(id, kind) = isdefined(Main, :EMOTES) && haskey(Main.EMOTES, :emote) && Base.invokelatest(Main.EMOTES[:emote], id, kind)

NG.arrive_goal!(::Val{:chase}, c, w) = (rand(w.rng) < 0.6 && NG.say!(w, c, rand(w.rng, ("Almost!", "So quick!", "Hee hee!")); duration = 1.5); nothing)

flat(a, b) = hypot(a[1] - b[1], a[2] - b[2])

field_flowers(w) = [p for p in w.props if p.kind === :flower && get(p.data, "field", false) == true]
perch(p) = p.pos + Point3f(0, 0, 0.32f0 * p.scale)

function NG.start!(s::Butterflies, game)
    game.stage === nothing && return
    if !haskey(BP, :plot) || BP[:plot].parent !== game.stage.scene
        BP[:plot] = meshscatter!(game.stage.scene, [HIDE]; marker = NG.shape(:sphere), markersize = [Vec3f(0)],
                                 rotation = [Quaternionf(0, 0, 0, 1)], color = [RGBf(1, 1, 1)], name = :butterflies)
    end
    empty!(s.flies)
end

NG.stop!(s::Butterflies, game) = haskey(BP, :plot) && (Makie.update!(BP[:plot]; arg1 = [HIDE], markersize = [Vec3f(0)],
    rotation = [Quaternionf(0, 0, 0, 1)], color = [RGBf(1, 1, 1)]); nothing)

function NG.step!(s::Butterflies, game, dt)
    haskey(BP, :plot) || return
    w = game.world
    fl = field_flowers(w)
    if NG.is_night(w) || isempty(fl)
        isempty(s.flies) && return
        empty!(s.flies)
        return NG.stop!(s, game)
    end
    if isempty(s.flies)
        for k in 1:N_FLIES
            p = fl[rand(w.rng, 1:length(fl))]
            push!(s.flies, Fly(perch(p) + Point3f(0, 0, 0.6), perch(p), 0.0, 0f0, Float32(2pi * rand(w.rng)), COLOURS[mod1(k, length(COLOURS))], 0.0))
        end
    end
    t = Float32(w.t)
    for c in w.creatures          # walkers startle the butterflies near them
        c.action in (:walk, :run) || continue
        for f in s.flies
            f.fast <= 0 && flat(c.pos, f.pos) < STARTLE && f.pos[3] - c.pos[3] < 1.2f0 || continue
            startle!(f, w, fl, c.pos)
        end
    end
    # a butterfly flying up right by the player's Lumi (its own steps, a friend's, a passer-by's) sends a
    # playful critter after it (s43: only Lumi's own startles counted, and the friend beside it always came first)
    for me in w.creatures
        me.controlled && me.action in (:walk, :run) || continue
        for f in s.flies
            f.fast > 0 && flat(me.pos, f.pos) < 3f0 && (chase!(s, w, me, f); break)
        end
    end
    for c in w.creatures          # a chaser keeps running at its butterfly's path
        c.goal.kind === :chase && !c.goal.arrived || continue
        if w.t - get(s.chased, c.id, w.t) > 7     # they always get away: a last pounce, then back to its day
            c.goal.target = c.pos
        else
            f = argmin(f -> flat(f.pos, c.pos), s.flies)
            c.goal.target = NG.ground(w.island, (f.pos[1], f.pos[2]))
        end
    end
    rejoin!(game, w)
    pos = Point3f[]; sz = Vec3f[]; rot = Quaternionf[]; col = RGBf[]
    for f in s.flies
        if f.rest > 0
            f.rest -= dt
            f.pos = f.target
            flap = 0.35f0 + 0.35f0 * sin(2.2f0 * t + f.phase)          # resting: wings open and close slowly
            if f.rest <= 0
                p = fl[rand(w.rng, 1:length(fl))]
                f.target = perch(p)
            end
        else
            d = f.target - f.pos
            dist = norm(d)
            if dist < 0.08f0
                f.rest = 2.0 + 5rand(w.rng); f.fast = 0.0   # landed: calm again, and a walker can scare it up anew
            else
                f.fast -= dt
                step = min(dist, Float32((f.fast > 0 ? 2.4 : 0.9) * dt))
                f.fast > 0 && (f.pos += Point3f(0, 0, Float32(0.5dt)))   # climbs as it flees
                f.yaw = atan(d[2], d[1])
                bob = 0.12f0 * sin(7f0 * t + f.phase) * min(1f0, dist)   # a fluttering, up-and-down flight
                f.pos = f.pos + step * d / dist + Point3f(0.25f0 * sin(3t + f.phase) * Float32(dt), 0, bob * Float32(dt) * 4)
            end
            flap = 0.9f0 * abs(sin(14f0 * t + f.phase))
        end
        qy = NG.rot_z(f.yaw)
        for side in (1f0, -1f0)   # a fore wing and a smaller, darker hind wing on each side: a butterfly, not a disc
            q = qy * Makie.qrotation(Vec3f(1, 0, 0), side * flap)
            push!(pos, f.pos + q * Vec3f(0.03f0, side * 0.085f0, 0)); push!(sz, WING); push!(rot, q); push!(col, f.colour)
            push!(pos, f.pos + q * Vec3f(-0.06f0, side * 0.06f0, 0)); push!(sz, HIND); push!(rot, q * NG.rot_z(side * 0.5f0))
            push!(col, RGBf(0.8f0 * f.colour.r, 0.8f0 * f.colour.g, 0.8f0 * f.colour.b))
        end
        push!(pos, f.pos); push!(sz, BODY); push!(rot, qy); push!(col, RGBf(0.18, 0.12, 0.1))
    end
    Makie.update!(BP[:plot]; arg1 = pos, markersize = sz, rotation = rot, color = col)
    return
end

register!(Butterflies())

"A parade friend back from its butterfly chase falls in behind Lumi again (when Lumi still leads)."
function rejoin!(game, w)
    isempty(REJOIN) && return
    for (id, t0) in collect(REJOIN)
        i = findfirst(c -> c.id == id, w.creatures)
        c = i === nothing ? nothing : w.creatures[i]
        if c === nothing || w.t - t0 > 30
            delete!(REJOIN, id)
        elseif c.goal.kind !== :chase || c.goal.arrived
            delete!(REJOIN, id)
            me = findfirst(x -> x.controlled && x.species == "Lumi", w.creatures)
            (me === nothing || (c.goal.kind !== :chase && c.goal.kind in NG.BUSY_GOALS) || c.action === :sleep) && continue   # :chase is busy too
            haskey(game.plugins, "greetings") || continue
            g = game.plugins["greetings"]
            Base.invokelatest(g.mod.join_parade!, only(g.systems), w, w.creatures[me], c, rand(w.rng, ("Wait for me!", "Back in line!", "It got away!")))
        end
    end
end
