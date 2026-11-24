# Flower gifts: by day a critter wanders to a meadow flower, sniffs it, picks one and carries it
# (a little pink flower held up in front of it) to a friend, Lumi included: "For you!".
# The friend answers with hearts; both remember it. When you play Lumi, critters bring YOU flowers.
isdefined(Main, :GIFT_PLOTS) || Core.eval(Main, :(const GIFT_PLOTS = Dict{Symbol,Any}()))
using Serialization
const NG = NeverendingGame
const GP = Main.GIFT_PLOTS
const FLOWER_ID = "20261123-033456-088-asset"     # the pink meadow flower (plugins/flora.jl)
const GIFT_VERSION = 1

const CARRYING = Dict{Int32,Float64}()           # who carries a flower => since when
const SNIFF = ("Mmm, smells like honey!", "So pretty...", "*sniff sniff*", "This one is perfect.")
const GIVE = ("For you, %s!", "I picked this for you, %s!", "%s! Look what I found!", "A flower for %s!")
const THANKS = ("For me?!", "Aww, thank you!", "It's beautiful!", "I'll keep it forever!")

emote(id, kind) = isdefined(Main, :EMOTES) && haskey(Main.EMOTES, :emote) && Base.invokelatest(Main.EMOTES[:emote], id, kind)

for k in (:flowers, :gift)
    k in NG.GOAL_KINDS || push!(NG.GOAL_KINDS, k)
end

picked() = get!(Main.FLORA_PLOTS, :picked, Dict{Int32,Float64}())   # plugins/flora.jl hides these until they regrow
pick!(f, w) = (picked()[f.id] = w.t)
flowers(w) = (ps = picked(); [p for p in w.props if p.kind === :flower && !haskey(ps, p.id)])

NG.goal_score(::Val{:flowers}, c, w) = NG.is_night(w) || c.controlled || c.species == "Lumi" || haskey(CARRYING, c.id) ? 0.0 :
    0.1 + 0.25c.traits.curiosity + 0.15c.traits.sociability
NG.goal_score(::Val{:gift}, c, w) = haskey(CARRYING, c.id) && !c.controlled ? 4.0 : 0.0

function NG.start_goal(::Val{:flowers}, c, w)
    fs = filter(p -> hypot(p.pos[1] - c.pos[1], p.pos[2] - c.pos[2]) < 18, flowers(w))
    isempty(fs) && return nothing
    f = rand(w.rng, fs)
    # stand next to it, not on it
    d = Vec2f(c.pos[1] - f.pos[1], c.pos[2] - f.pos[2]); d = d / max(norm(d), 1f-3)
    spot = NG.ground(w.island, (f.pos[1] + 0.45f0 * d[1], f.pos[2] + 0.45f0 * d[2]))
    return NG.Goal(:flowers, spot, :eat, 3.5 + 2rand(w.rng), 0.0, false, f.id, false)
end

function NG.arrive_goal!(::Val{:flowers}, c, w)
    f = NG.prop(w, c.goal.partner)
    f === nothing || (c.yaw = atan(f.pos[2] - c.pos[2], f.pos[1] - c.pos[1]) - NG.species_of(c).heading)
    rand(w.rng) < 0.7 && NG.say!(w, c, rand(w.rng, SNIFF); duration = 2.2)
    emote(c.id, :heart)
end

# picked one: a friend gets it next (the gift goal wins the next choice)
function NG.finish_goal!(::Val{:flowers}, c, w)
    rand(w.rng) < 0.75 || return
    f = NG.prop(w, c.goal.partner)
    (f === nothing || haskey(picked(), f.id)) && return     # somebody was quicker
    pick!(f, w)
    CARRYING[c.id] = w.t
end

"The friend to give the flower to: awake and near, Lumi first when the player is Lumi."
function friend_for(c, w)
    best = nothing; bd = 25f0
    for o in w.creatures
        (o === c || o.action === :sleep || o.goal.kind === :sleep) && continue
        d = hypot(o.pos[1] - c.pos[1], o.pos[2] - c.pos[2]) - (o.controlled ? 15f0 : 0f0)
        d < bd && (best = o; bd = d)
    end
    return best
end

function NG.start_goal(::Val{:gift}, c, w)
    o = friend_for(c, w)
    o === nothing && (delete!(CARRYING, c.id); return nothing)
    NG.say!(w, c, "Where's $(o.name)?"; duration = 1.6)
    return NG.Goal(:gift, o.pos, :wave, 2.5, 0.0, false, o.id, false)
end

# `body_radius` is the keep-away distance Separation holds between two creatures (1.2-1.6 m each):
# a carrier stops at their sum, so the hand-over check must allow that much (a fixed 2.5 m failed every
# gift between big bodies, s58; a closer stop is never reached, Separation pushes back)
"How close a carrier comes to hand its flower over."
hand_over(c, o) = NG.body_radius(NG.species_of(c)) + NG.body_radius(NG.species_of(o)) + 0.2f0

function NG.arrive_goal!(::Val{:gift}, c, w)
    delete!(CARRYING, c.id)
    o = NG.creature(w, c.goal.partner)
    # within reach = where the carrier was sent (step!: both body radii + 0.2 in front of the friend) plus
    # slack. A fixed 2.5 m was less than that stop for big bodies (a crab to a fluffkin: 2.9 m), so every
    # such gift ended "I'll just put it here" (s58 suite)
    reach = o === nothing ? 0f0 : hand_over(c, o) + 0.7f0
    if o === nothing || hypot(o.pos[1] - c.pos[1], o.pos[2] - c.pos[2]) > max(2.5f0, reach) || o.action === :sleep
        NG.say!(w, c, "Oh... I'll just put it here."; duration = 2)
        return
    end
    give!(c, o, w)
end

"`c` gives its flower to `o`: words, hearts, memories, and `o` thanks it a moment later."
function give!(c, o, w)
    delete!(CARRYING, c.id)
    c.yaw = atan(o.pos[2] - c.pos[2], o.pos[1] - c.pos[1]) - NG.species_of(c).heading
    NG.say!(w, c, replace(rand(w.rng, GIVE), "%s" => o.name); duration = 2.4)
    emote(c.id, :heart); emote(o.id, :heart)
    c.mood = min(1f0, c.mood + 0.15f0); o.mood = min(1f0, o.mood + 0.25f0)
    o.needs.social = min(1f0, o.needs.social + 0.3f0)
    NG.remember!(c, w.t, "gave $(o.name) a flower"); NG.remember!(o, w.t, "got a flower from $(c.name)")
    NG.emit!(w, :flower_gift; who = c.name, to = o.name)
    THANK[o.id] = (w.t + 1.2, c.id)          # the friend answers a moment later
end

const THANK = Dict{Int32,Tuple{Float64,Int32}}()
const E_USED = Ref(-1.0)       # sim time of the last E press this plugin used (greetings.jl then does not wave too)

"""
Whether Lumi's E press now is (or was, this frame) a flower pick or gift, so the wave
in greetings.jl stays out of it: one key, one thing (a press used to pick a flower AND wave,
and the thanks then turned the new follower back into an answer).
"""
function uses_e(w, me)
    E_USED[] == w.t && return true
    if haskey(CARRYING, me.id)
        return any(o -> o !== me && !o.controlled && o.action !== :sleep &&
            hypot(o.pos[1] - me.pos[1], o.pos[2] - me.pos[2]) - NG.body_radius(NG.species_of(o)) < 2.8f0, w.creatures)
    end
    ps = picked()
    return any(p -> p.kind === :flower && !haskey(ps, p.id) && hypot(p.pos[1] - me.pos[1], p.pos[2] - me.pos[2]) < 1.1f0, w.props)
end

mutable struct FlowerGift <: System
    last_action::Symbol        # Lumi's action last frame: E (:wave) acts once per press
end
FlowerGift() = FlowerGift(:idle)

"""
The player's Lumi: E next to a meadow flower picks it, E next to a critter (carrying one) gives it.
Returns true when E did something here.
"""
function lumi_flower!(s::FlowerGift, w, me)
    a = me.action; pressed = a === :wave && s.last_action !== :wave; s.last_action = a
    (pressed && me.controlled) || return false
    if haskey(CARRYING, me.id)
        best = nothing; bd = 2.8f0
        for o in w.creatures
            (o === me || o.controlled || o.action === :sleep) && continue
            d = hypot(o.pos[1] - me.pos[1], o.pos[2] - me.pos[2]) - NG.body_radius(NG.species_of(o))
            d < bd && (best = o; bd = d)
        end
        best === nothing && return false
        give!(me, best, w)
        E_USED[] = w.t
        return true
    end
    ps = picked()
    i = findfirst(p -> p.kind === :flower && !haskey(ps, p.id) && hypot(p.pos[1] - me.pos[1], p.pos[2] - me.pos[2]) < 1.1f0, w.props)
    i === nothing && return false
    pick!(w.props[i], w)
    CARRYING[me.id] = w.t
    E_USED[] = w.t
    NG.say!(w, me, rand(w.rng, ("Ooh, a pretty one!", "Who would like this?", "For a friend!")); duration = 2)
    emote(me.id, :note)
    return true
end

function flower_plot!(game)
    get(GP, :version, 0) == GIFT_VERSION && haskey(GP, :plot) && GP[:plot].parent === game.stage.scene && return GP[:plot]
    haskey(GP, :plot) && delete!(GP[:plot].parent, GP[:plot])
    mm = Serialization.deserialize(joinpath(game.paths.world, "assets", FLOWER_ID, "mesh.jls"))
    mat = copy(only(values(mm[:materials]))); mat["metallic"] = 0f0
    model = NG.AssetModel(mm; material = mat)
    zs = [q[3] for q in GeometryBasics.coordinates(model.mesh)]
    GP[:h] = maximum(zs) - minimum(zs)
    # one hidden copy: the raster cannot draw an empty meshscatter
    GP[:plot] = NG.asset_instances!(game.stage.scene, model, [Point3f(0, 0, -50)]; markersize = [Vec3f(0)], name = :flower_gifts)
    GP[:version] = GIFT_VERSION
    GP[:n] = -1
    return GP[:plot]
end

"The camera moment: a carrier close to its friend (the gift is about to happen), then the thanks."
function watch_gift(w)
    for (id, _) in THANK
        return id
    end
    for c in w.creatures
        (haskey(CARRYING, c.id) && c.goal.kind === :gift) || continue
        o = NG.creature(w, c.goal.partner)
        o !== nothing && hypot(o.pos[1] - c.pos[1], o.pos[2] - c.pos[2]) < 7 && return c.id
    end
    return nothing
end

function NG.start!(::FlowerGift, game)
    NG.CAMERA_MOMENTS["flowergift"] = watch_gift
    game.stage === nothing && return
    flower_plot!(game).visible[] = true
end

function NG.stop!(::FlowerGift, game)
    delete!(NG.CAMERA_MOMENTS, "flowergift")
    haskey(GP, :plot) && (GP[:plot].visible[] = false)
end

function NG.step!(s::FlowerGift, game, dt)
    w = game.world
    me = NG.creature(w, "Lumi")
    me === nothing || lumi_flower!(s, w, me)
    # answers to gifts
    for (id, (t, from)) in collect(THANK)
        w.t < t && continue
        delete!(THANK, id)
        o = NG.creature(w, id)
        (o === nothing || o.controlled) && continue
        NG.say!(w, o, rand(w.rng, THANKS); duration = 2.2)
        emote(o.id, :heart)
        o.controlled || o.goal.kind in NG.BUSY_GOALS || o.goal.kind === :follow || (o.goal = NG.Goal(:answer, o.pos, :jump, 1.5, w.t + 1.5, true, 0, false); o.action = :jump)
    end
    # a carrier that gave up (another goal took over) drops its flower
    for id in collect(keys(CARRYING))
        c = NG.creature(w, id)
        # the player's Lumi keeps its flower while you play; a critter drops it after a minute
        (c === nothing || (c.species == "Lumi" ? !c.controlled : c.controlled || w.t - CARRYING[id] > 60)) && delete!(CARRYING, id)
    end
    # the friend may walk on (Lumi when you play it): the carrier heads for a spot just in front of it
    for c in w.creatures
        g = c.goal
        (g.kind === :gift && !g.arrived) || continue
        o = NG.creature(w, g.partner)
        o === nothing && continue
        d = Vec2f(c.pos[1] - o.pos[1], c.pos[2] - o.pos[2]); l = norm(d)
        stop = hand_over(c, o)
        g.target = l <= stop ? c.pos : NG.ground(w.island, (o.pos[1] + stop * d[1] / l, o.pos[2] + stop * d[2] / l))
        g.run = l > 6
    end
    game.stage === nothing && return
    plot = flower_plot!(game)
    pos = Point3f[]; rot = Makie.Quaternionf[]
    for c in w.creatures
        haskey(CARRYING, c.id) || continue
        h = NG.species_of(c).heading
        a = c.yaw + h
        r = NG.body_radius(NG.species_of(c))
        # Lumi holds it up at its side: the chase camera looks from behind, a flower in front was hidden
        b, k, z = c.controlled ? (a - 1.2f0, 0.95f0, 1.15f0) : (a, 0.75f0, 0.8f0)
        push!(pos, c.pos + Point3f(k * r * cos(b), k * r * sin(b), z * r))
        push!(rot, NG.rot_z(a))
    end
    n = length(pos)
    s = Vec3f(0.5f0 / GP[:h])      # bigger than a meadow flower: it must read in the follow view
    if n == 0
        GP[:n] == 0 && return
        Makie.update!(plot; arg1 = [Point3f(0, 0, -50)], rotation = [Makie.Quaternionf(0, 0, 0, 1)], markersize = [Vec3f(0)])
    else
        Makie.update!(plot; arg1 = pos, rotation = rot, markersize = fill(s, n))
    end
    GP[:n] = n
end

register!(FlowerGift())
