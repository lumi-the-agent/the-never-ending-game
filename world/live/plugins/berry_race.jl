# Berry race: ripe berries grow on the bushes, and three hungry critters want them too.
# Steer Lumi (W/S walk, A/D turn, Shift runs) and pick more berries than the critters in 60 seconds.
# The critters each run for a berry, shout "Mine!" when they get it and grumble when Lumi is first.
# Every berry Lumi picks goes into the basket by the cottage, which fills up for good.
const NG = NeverendingGame

# best scores survive restarts (state/bests.json, shared by the mini games); a quiet copy never writes
bests_file(game) = joinpath(game.paths.state, "bests.json")
load_best(game, key, default) = (f = bests_file(game); isfile(f) ? Float64(get(NG.read_json(f), key, default)) : Float64(default))
function save_best!(game, key, v)
    game.dash === nothing && return
    # a UI test's round is not the player's best (tests put P[:best] back, not this file)
    game.tests !== nothing && NG.running(game.tests) && return
    f = bests_file(game)
    d = isfile(f) ? NG.read_json(f) : Dict{String,Any}()
    d[key] = v
    NG.write_json(f, d)
end
const N_BERRIES = 14
const RACE_TIME = 60.0
const N_RIVALS = 3
const PICK_RADIUS = 0.9f0        # Lumi (2D) to the berry's foot point
const PARK = Point3f(0, 0, -50)
const KEY_NAMES = ("W", "A", "S", "D", "Shift", "R")
const KEYS = (Makie.Keyboard.w, Makie.Keyboard.a, Makie.Keyboard.s, Makie.Keyboard.d, Makie.Keyboard.left_shift, Makie.Keyboard.r)
# the key bar sits in the bottom-left corner: in the middle it covered the rivals' name tags (tester s45)
const KEY_X = (0.045, 0.09, 0.135, 0.18, 0.24, 0.3)
const KEY_OFF = RGBAf(0.08, 0.09, 0.12, 0.72)
const KEY_ON = RGBAf(0.95, 0.4, 0.35, 0.95)
const BERRY_MAT = NG.Hikari.Plastic(color = (0.85, 0.06, 0.16), roughness = 0.12)
const BERRY_RED = RGBf(0.9, 0.1, 0.18)
const N_POPS = 10
const FULL = 2             # berries a critter eats on a first play (level 1) before it is full
const HEAD_START = 2.5       # s the critters wait after the player's first step
const WALK_UNTIL = 15.0      # s the critters walk before they hurry
const MAX_LEVEL = 4          # each win makes the critters hurry 4 s sooner next round (a reason to play twice, review #18)
level(game) = Int(get!(() -> round(Int, load_best(game, "berry_level", 1)), P, :level))
"Level 1 critters walk the whole race (a first play lost 6-8 with them hurrying after 15 s, s53); then 12, 9, 6 s."
walk_until(game) = level(game) == 1 ? RACE_TIME : WALK_UNTIL - 3.0 * (level(game) - 1)
"The player's head start: 2 s more on a first play (s54: one 5-9 loss in four)."
head_start(game) = HEAD_START + (level(game) == 1 ? 2.0 : 0.0)
"How long a critter munches a berry: long at level 1 so a first play is won (6-8 in 1 of 4 tester runs at 2 s, s53), 2 s at the top level."
munch(game) = 2.0 + 0.6 * (MAX_LEVEL - level(game))

const PLOTS_VERSION = 2
isdefined(Main, :BERRY_PLOTS) || Core.eval(Main, :(const BERRY_PLOTS = Dict{Symbol,Any}()))
const P = Main.BERRY_PLOTS

"One berry: where it hangs, the ground point you pick it from, and who got it (0 nobody, -1 Lumi, else a creature id)."
mutable struct Berry
    pos::Point3f
    foot::Point3f
    taken::Int32
end

mutable struct BerryRace <: MiniGame
    jump::NG.JumpIn
    berries::Vector{Berry}
    rivals::Vector{Int32}
    rival_score::Vector{Int}
    target::Vector{Int}           # the berry each rival runs for (0: none)
    state::Symbol                 # :ready, :playing, :over
    t::Float64
    t_state::Float64
    score::Int
    lumi::Int32
    pop_at::Point3f
    pop_t::Float64
    flash::Float64
end

function BerryRace(game)
    j = NG.JumpIn(game)
    BerryRace(j, Berry[], Int32[], Int[], Int[], :ready, 0.0, 0.0, 0, j.id, PARK, 99.0, 0.0)
end

NG.game_title(::Type{BerryRace}) = "Berry race (WASD)"
NG.game_description(::Type{BerryRace}) =
    "Three hungry critters race you to the berries on the bushes. Pick more than they do in $(Int(RACE_TIME)) seconds. W/S walk, A/D turn, Shift runs, R restarts."

function ensure_plots!(game)
    get(P, :version, 0) == PLOTS_VERSION && return
    for k in collect(keys(P))
        k in (:version, :best, :total, :basket, :heap, :wild, :wild_pts) || delete!(P, k)   # :wild belongs to WildRace (start!), not to the mini game
    end
    scene = game.stage.scene
    P[:berries] = meshscatter!(scene, fill(PARK, N_BERRIES); marker = Sphere(Point3f(0), 1f0), markersize = 0.2f0,
        color = BERRY_RED, material = BERRY_MAT, visible = false)
    # a red marker ring floating over each bush that still has berries: you see them from across the island
    P[:marks] = meshscatter!(scene, fill(PARK, N_BERRIES); marker = Sphere(Point3f(0), 1f0), markersize = 0.11f0,
        color = RGBf(1, 0.35, 0.35), shading = Makie.NoShading, visible = false)
    P[:pops] = meshscatter!(scene, fill(PARK, N_POPS); marker = Sphere(Point3f(0), 1f0), markersize = 0.06f0,
        color = RGBf(1, 0.5, 0.5), shading = Makie.NoShading, visible = false)
    ov = game.stage.overlay
    P[:hud] = textlabel!(ov, Point2f(0.5, 0.93); space = :relative, text = " ", fontsize = 24,
        text_color = RGBf(1, 0.92, 0.85), background_color = RGBAf(0.08, 0.09, 0.12, 0.75),
        strokewidth = 0, padding = 10, cornerradius = 8, visible = false)
    P[:card] = textlabel!(ov, Point2f(0.5, 0.64); space = :relative, text = " ", fontsize = 22, justification = :center,
        text_color = RGBf(1, 0.97, 0.9), background_color = RGBAf(0.1, 0.06, 0.08, 0.86),
        strokewidth = 0, padding = 22, cornerradius = 14, visible = false)
    for (i, name) in enumerate(KEY_NAMES)
        P[Symbol(:key_, i)] = textlabel!(ov, Point2f(KEY_X[i], 0.05); space = :relative, text = name, fontsize = 17,
            text_color = RGBf(1, 1, 1), background_color = KEY_OFF, strokewidth = 0, padding = 9, cornerradius = 6,
            visible = false)
    end
    P[:version] = PLOTS_VERSION
end

const PLOT_KEYS = (:berries, :marks, :pops, :hud, :card, (Symbol(:key_, i) for i in 1:length(KEY_NAMES))...)
show_plots!(on::Bool) = foreach(k -> (P[k].visible[] = on), PLOT_KEYS)

start_text(m, game) = """Berry race$(level(game) == 1 ? "" : "  ·  Level $(level(game)): the critters hurry sooner!")
Ripe berries hang on the bushes,
and $(join(rival_names(m, game), ", ", " and ")) want them too!
Pick more than the critters in $(Int(RACE_TIME)) seconds:
walk into a bush to shake its berries loose.

W / S  walk      A / D  turn      Shift  run

Press W to start"""

rival_names(m, game) = [NG.creature(game.world, id).name for id in m.rivals]

flat(a, b) = norm(Vec2f(a[1] - b[1], a[2] - b[2]))

"Berries on the bushes: up to two per bush, on the side, each with the ground point in front of it."
function grow_berries(w; bushes = [p for p in w.props if p.kind === :bush], n = N_BERRIES, toward = nothing)
    out = Berry[]
    isempty(bushes) && return out
    k = 0
    while length(out) < n && k < 600
        k += 1
        b = bushes[mod1(k, length(bushes))]
        a = 2f0 * Float32(pi) * rand(w.rng, Float32)
        # the first berries hang on the side facing the start line: a short straight walk, never round the bush
        if toward !== nothing && length(out) < 3 && k <= 3 * length(bushes)
            a = atan(toward[2] - b.pos[2], toward[1] - b.pos[1]) + 0.7f0 * (2f0 * rand(w.rng, Float32) - 1f0)
        end
        dir = Vec2f(cos(a), sin(a))
        r = 0.62f0 * b.scale
        foot = b.pos[1:2] + (0.65f0 * b.scale + 0.5f0) * dir   # outside the bush (separation.jl pushes out of 0.65 * scale)
        NG.on_land(w.island, foot[1], foot[2]; margin = 0.4f0) || continue
        # out in the open: no tree crown over the spot (it hides Lumi from the camera) and no rock in the way
        any(p -> (p.kind === :tree && flat(p.pos, foot) < 2.6f0 * p.scale) || (p.kind === :rock && flat(p.pos, foot) < 0.75f0 * p.scale + 0.6f0), w.props) && continue
        any(o -> flat(o.pos, b.pos + Point3f(r * dir[1], r * dir[2], 0)) < 0.45f0, out) && continue
        h = NG.terrain_height(w.island, b.pos[1], b.pos[2])
        push!(out, Berry(Point3f(b.pos[1] + r * dir[1], b.pos[2] + r * dir[2], h + (0.45f0 + 0.35f0 * rand(w.rng, Float32)) * b.scale),
                         NG.ground(w.island, (foot[1], foot[2])), 0))
    end
    return out
end

function free_creature(o)
    # busy goals (a dance ring, a ball game, fishing: NG.BUSY_GOALS) are not interrupted for a race
    !(o.controlled || o.goal.kind in (:interact, :sleep, :answer, :follow) || o.goal.kind in NG.BUSY_GOALS || o.action === :sleep)
end

"Open meadow ground a few steps from the biggest group of bushes (never the pier), and the bush it faces."
function start_spot(w)
    bushes = [p for p in w.props if p.kind === :bush]
    isempty(bushes) && return nothing
    blocked(q) = any(p -> (p.kind === :tree && flat(p.pos, q) < 2.6f0 * p.scale) ||
                          (p.kind in (:rock, :bush) && flat(p.pos, q) < 0.75f0 * p.scale + 0.8f0), w.props) ||
                 any(a -> a isa NG.AssetActor && flat(a.pos, q) < 0.6f0 * a.scale + 0.8f0, w.actors)
    crowd(b) = count(o -> flat(o.pos, b.pos) < 9f0, bushes)
    for b in sort(bushes; by = b -> -crowd(b)), r in (2.4f0, 3.2f0, 4.0f0), k in 0:11
        a = Float32(2pi * k / 12)
        d = 0.65f0 * b.scale + r
        q = NG.ground(w.island, (b.pos[1] + d * cos(a), b.pos[2] + d * sin(a)))
        NG.on_land(w.island, q[1], q[2]; margin = 1.5f0) && NG.walkway_height(q[1], q[2]) === nothing && !blocked(q) && return (q, b)
    end
    return nothing
end

"The race starts on a start line in the meadow: Lumi faces the nearest bush, the rivals stand beside it."
function line_up!(m, w, c)
    s = start_spot(w)
    s === nothing && return NG.face_open!(w, c)
    q, b = s
    c.pos = q
    c.yaw = atan(b.pos[2] - q[2], b.pos[1] - q[1])
    for (k, id) in enumerate(m.rivals)
        o = NG.creature(w, id)
        side = (k - 2) * 1.3f0   # left, behind, right
        back = k == 2 ? 1.6f0 : 0.6f0
        p = NG.ground(w.island, (q[1] - back * cos(c.yaw) - side * sin(c.yaw), q[2] - back * sin(c.yaw) + side * cos(c.yaw)))
        NG.on_land(w.island, p[1], p[2]; margin = 0.4f0) || continue
        o.pos = p
        o.yaw = c.yaw - NG.species_of(o).heading
    end
    return c
end

function reset!(m::BerryRace, game)
    w = game.world
    c = NG.creature(w, m.lumi)
    # the rivals: the three nearest awake critters
    others = [o for o in w.creatures if o !== c && free_creature(o)]
    sort!(others; by = o -> flat(o.pos, c.pos))
    # at night most critters sleep: the smell of berries wakes the nearest sleepers
    sleepers = [o for o in w.creatures if o !== c && !o.controlled && o.goal.kind !== :interact && !free_creature(o)]
    sort!(sleepers; by = o -> flat(o.pos, c.pos))
    for o in first(sleepers, max(0, N_RIVALS - length(others)))
        o.action = :idle
        NG.say!(w, o, rand(w.rng, ("Huh? Berries?!", "*yawn* ...berries?", "I'm up, I'm up!")); duration = 2.0)
        push!(others, o)
    end
    old = m.rivals
    m.rivals = [o.id for o in first(others, N_RIVALS)]
    for id in old   # R picks rivals anew: the ones left out are free again
        id in m.rivals && continue
        o = NG.creature(w, id)
        o.goal.kind in (:race, :wait, :cheer, :full) && NG.choose_goal!(o, w)
    end
    line_up!(m, w, c)
    # the nearest bushes get the first berries: three of them a few steps from the start line
    m.berries = grow_berries(w; bushes = sort([p for p in w.props if p.kind === :bush]; by = b -> flat(b.pos, c.pos)), toward = c.pos)
    # the three berries nearest the start line are the player's first picks: the critters leave them while they only walk
    P[:reserved] = first(sortperm([flat(b.foot, c.pos) for b in m.berries]), 3)
    m.rival_score = zeros(Int, length(m.rivals))
    m.target = zeros(Int, length(m.rivals))
    m.state = :ready; m.t = 0.0; m.t_state = 0.0; m.score = 0; m.pop_t = 99.0; m.flash = 0.0
    # they wait on the start line, looking eager
    for id in m.rivals
        o = NG.creature(w, id)
        NG.leave_interactions!(w, o)
        o.goal = NG.Goal(:wait, o.pos, :jump, 1e6, 0.0, false, 0, true)
    end
    Makie.update!(P[:card]; text = start_text(m, game))
    P[:card].visible[] = true
end

function NG.start!(m::BerryRace, game)
    NG.start!(m.jump, game)
    ensure_plots!(game)
    show_plots!(true)
    reset!(m, game)
    chase_camera!(game, NG.creature(game.world, m.lumi), 0.0; snap = true, low = true)
end

"Show or hide the creatures' name tags and speech (only when it changes: no update every frame)."
function name_tags!(game, on::Bool)
    l = game.stage.labels
    l === nothing || l.visible[] == on || (l.visible[] = on)
end

firefly(game) = game.plugins["firefly_catch"].mod

"""
A high chase camera: behind Lumi and well above the tree crowns, looking down a little ahead,
so W still goes "into" the screen and the bushes around are in view (the low firefly view hid
Lumi under the big pines and crowns).
"""
function chase_camera!(game, c, dt; snap = false, low = false)
    a = c.yaw + NG.species_of(c).heading
    fwd = Point3f(cos(a), sin(a), 0)
    # `low`: the start card's view, a friendly low look over Lumi's shoulder at the field, Lumi and
    # the rivals in the lower third under the card (tester s44: "looking steeply down at the start
    # line"); W rises to the high chase view
    target = c.pos + 1.5f0 * fwd + Point3f(0, 0, low ? 0.9f0 : 0.4f0)
    eye = c.pos - (low ? 5.5f0 : 4.5f0) * fwd + Point3f(0, 0, low ? 4.8f0 : 8.5f0)
    k = snap ? 1f0 : Float32(1 - exp(-3dt / 0.5))
    game.rig.mode = :fixed
    game.rig.eye += k * (eye - game.rig.eye)
    game.rig.target += k * (target - game.rig.target)
end

"A low front view of Lumi, eye 4.2 m ahead and 1.6 m up; Lumi sits in the lower third under the card."
function end_camera!(game, c, dt)
    fwd = get!(P, :end_dir) do                     # fixed at the end: a dancing Lumi spins, the camera must not
        a = c.yaw + NG.species_of(c).heading
        Point3f(cos(a), sin(a), 0)
    end
    eye = c.pos + 4.2f0 * fwd + Point3f(0, 0, 1.6f0)
    target = c.pos + Point3f(0, 0, 1.5f0)
    k = Float32(1 - exp(-3dt / 0.8))
    game.rig.mode = :fixed
    game.rig.eye += k * (eye - game.rig.eye)
    game.rig.target += k * (target - game.rig.target)
end

"""
The nearest berry nobody has and nobody else runs for, from `p`. While the critters only walk
(the first `WALK_UNTIL` s) they are polite: a berry Lumi stands nearer to is Lumi's, so a
first-time player is never sniped at the bush right in front of them.
"""
function pick_target(m, p, me; lumi = nothing, polite = false)
    best, bi = Inf32, 0
    for (i, b) in enumerate(m.berries)
        b.taken == 0 || continue
        any(k -> k != me && m.target[k] == i, eachindex(m.target)) && continue
        polite && (i in get(P, :reserved, Int[]) || (lumi !== nothing && flat(b.foot, lumi) < flat(b.foot, p))) && continue
        d = flat(b.foot, p)
        d < best && ((best, bi) = (d, i))
    end
    return bi
end

function burst!(m, at)
    m.pop_at = at; m.pop_t = 0.0
end

function NG.input!(m::BerryRace, game, ev)
    ev.action == Makie.Keyboard.press || return
    if ev.key == Makie.Keyboard.r
        reset!(m, game)
    elseif m.state === :ready && ev.key in (Makie.Keyboard.w, Makie.Keyboard.s, Makie.Keyboard.a, Makie.Keyboard.d, Makie.Keyboard.up)
        m.state = :playing; m.t_state = 0.0
        P[:card].visible[] = false
        w = game.world
        for id in m.rivals
            NG.say!(w, NG.creature(w, id), rand(w.rng, ("Berries!", "Mine, all mine!", "Race you!", "Yum!")); duration = 1.5)
        end
    end
end

function step_rivals!(m, game, dt)
    w = game.world
    m.t < head_start(game) && return       # the player gets a head start
    hurry = m.t > walk_until(game)        # and the critters only walk at first
    sp = NG.creature(w, m.lumi).pos
    for (k, id) in enumerate(m.rivals)
        o = NG.creature(w, id)
        i = m.target[k]
        # a first play: each critter is full after FULL berries and sits down munching (s54: one critter took 4-5
        # and the player lost 5-9), so 3 critters take at most 6 of the 14
        if level(game) == 1 && get(m.rival_score, k, 0) >= FULL
            if o.goal.kind !== :full
                i != 0 && (m.target[k] = 0)
                (o.goal.kind === :cheer && w.t < o.goal.until) && continue   # finishes munching first
                o.goal = NG.Goal(:full, o.pos, :sit, 1e6, 0.0, false, 0, false)
                NG.say!(w, o, rand(w.rng, ("I'm full!", "So full... *burp*", "No more for me!")); duration = 1.8)
            end
            continue
        end
        if i != 0 && m.berries[i].taken != 0
            m.berries[i].taken == -1 && NG.say!(w, o, rand(w.rng, ("Aww!", "Hey, that was mine!", "Too slow...", "No fair!")); duration = 1.5)
            i = m.target[k] = 0
        end
        # polite at first: Lumi clearly heads for this one, find another
        if i != 0 && !hurry && flat(m.berries[i].foot, sp) + 1f0 < flat(m.berries[i].foot, o.pos)
            i = m.target[k] = 0
            o.goal = NG.Goal(:wait, o.pos, :idle, 1e6, 0.0, false, 0, false)
        end
        if i != 0 && flat(o.pos, m.berries[i].foot) < 0.45f0 + NG.body_radius(NG.species_of(o))
            b = m.berries[i]
            b.taken = id
            m.rival_score[k] += 1
            burst!(m, b.pos)
            NG.say!(w, o, rand(w.rng, ("Mine!", "Nom!", "Got one!", "Yummy!")); duration = 1.4)
            NG.emit!(w, :berry_eaten; who = o.name)
            o.goal = NG.Goal(:cheer, o.pos, :eat, munch(game), w.t + munch(game), true, 0, false)   # munching, then the next one
            i = m.target[k] = 0
        end
        # a hop finished or nothing to do: run for the nearest free berry (critters only walk fast, Lumi can run)
        if i == 0 && (o.goal.kind !== :cheer || w.t >= o.goal.until)
            j = pick_target(m, o.pos, k; lumi = sp, polite = !hurry)
            # nothing polite left: walk to the nearest berry that is not one of the player's first three
            # instead of sitting it out (perfectionist-0052: 4-0 with 56 s left, the rivals never contested)
            if j == 0 && !hurry
                best = Inf32
                for (i, b) in enumerate(m.berries)
                    (b.taken != 0 || i in get(P, :reserved, Int[]) || any(q -> q != k && m.target[q] == i, eachindex(m.target))) && continue
                    d = flat(b.foot, o.pos)
                    d < best && ((best, j) = (d, i))
                end
            end
            m.target[k] = j
            j != 0 && (o.goal = NG.Goal(:race, m.berries[j].foot, :idle, 1e6, 0.0, false, 0, hurry))
            j == 0 && (o.goal = NG.Goal(:wait, o.pos, :sit, 1e6, 0.0, false, 0, false))
        elseif i != 0 && (o.goal.kind !== :race || o.goal.run != hurry)
            o.goal = NG.Goal(:race, m.berries[i].foot, :idle, 1e6, 0.0, false, 0, hurry)
        end
    end
end

# ── the reward: every berry Lumi picks goes into the basket by the cottage and stays ──
const BASKET = Point3f(-8.6, 2.6, 0)          # in front of the cottage, next to the path
const HEAP_MAX = 60
const BASKET_ASSET = "20261123-003412-747-asset"   # a wicker basket full of berries (generated)
const BASKET_SCALE = 0.8f0
const RIM = 0.5f0                                  # the basket's rim height at scale 1 (the heap starts there)
berry_file(game) = joinpath(game.paths.state, "berries.json")
berry_total(game) = isfile(berry_file(game)) ? Int(NG.read_json(berry_file(game))["picked"]) : 0
save_berries!(game, n) = NG.write_json(berry_file(game), Dict("picked" => n))

"The berries in the heap, bottom up: rings that get smaller, so the heap grows into a dome."
function heap_points(w, n)
    base = NG.ground(w.island, (BASKET[1], BASKET[2]))
    pts = Point3f[]
    layer = 0
    while length(pts) < HEAP_MAX
        r = 0.3f0 - 0.06f0 * layer
        k = max(1, round(Int, 2pi * max(r, 0.01f0) / 0.13f0))
        r <= 0.02f0 && (r = 0f0; k = 1)
        for j in 1:k
            a = 2pi * j / k + 0.6layer
            push!(pts, base + Point3f(r * cos(a), r * sin(a), RIM * BASKET_SCALE + 0.09f0 * layer))
            length(pts) == HEAP_MAX && break
        end
        layer += 1
    end
    return [i <= n ? p : PARK for (i, p) in enumerate(pts)]
end

"The basket heap by the cottage, filled from state/berries.json."
struct BerryBasket <: System end

function NG.start!(s::BerryBasket, game)
    game.stage === nothing && return
    haskey(P, :heap) && return
    P[:total] = berry_total(game)
    P[:heap] = meshscatter!(game.stage.scene, heap_points(game.world, P[:total]); marker = Sphere(Point3f(0), 1f0),
        markersize = 0.07f0, color = BERRY_RED, material = BERRY_MAT)
end

function NG.step!(s::BerryBasket, game, dt)
    haskey(P, :heap) || return
    n = P[:total]
    get(P, :heap_n, -1) == n && return
    P[:heap_n] = n
    # the basket itself comes to the cottage with the first berry (an asset actor, saved with the world)
    if n > 0 && !any(a -> a isa NG.AssetActor && a.asset == BASKET_ASSET, game.world.actors)
        NG.place_asset(game, BASKET_ASSET, BASKET; yaw = 0.4, scale = BASKET_SCALE)
    end
    Makie.update!(P[:heap]; arg1 = heap_points(game.world, n))
end
NG.stop!(s::BerryBasket, game) = nothing

function NG.step!(m::BerryRace, game, dt)
    w = game.world
    name_tags!(game, m.state !== :ready)   # the start card covers the middle of the view: no name tags under it
    c = NG.creature(w, m.lumi)
    m.state === :playing ? NG.step!(m.jump, game, dt) : (c.action = :idle)
    m.t_state += dt
    # the end: turn round to face Lumi and the cheering (or sulking) critters, low, so their faces read
    # under the end card (perfectionist-0046: the end card's top-down view hid every face)
    m.state === :over && m.t_state > 1.0 ? end_camera!(game, c, dt) : chase_camera!(game, c, dt; low = m.state === :ready)
    m.state === :playing && (m.t += dt)
    for (i, k) in enumerate(KEYS)
        P[Symbol(:key_, i)].background_color[] = k in game.keys_down ? KEY_ON : KEY_OFF
    end
    if m.state === :playing
        # walking into a bush shakes it: every berry on it drops for Lumi (W at a bush always pays off)
        reach = NG.body_radius(NG.species_of(c)) + 0.3f0
        touched = [p for p in w.props if p.kind === :bush && flat(p.pos, c.pos) < 0.65f0 * p.scale + reach]
        on_touched(b) = any(p -> flat(p.pos, b.pos) < 0.7f0 * p.scale, touched)
        for b in m.berries
            if b.taken == 0 && (flat(c.pos, b.foot) < PICK_RADIUS || on_touched(b))
                b.taken = -1
                m.score += 1
                burst!(m, b.pos); m.flash = 1.0
                NG.say!(w, c, rand(w.rng, ("Got one!", "Yum!", "Mine!", "Juicy!")); duration = 1.2)
                NG.emit!(w, :berry_picked; who = c.name, score = m.score)
            end
        end
        step_rivals!(m, game, dt)
    end
    bob = 0.03f0 * sin(Float32(3w.t))
    pos = [b.taken == 0 ? b.pos + Point3f(0, 0, bob) : PARK for b in m.berries]
    Makie.update!(P[:berries]; arg1 = pos, markersize = 0.21f0 + 0.03f0 * sin(Float32(5w.t)))
    # a small light over far berries, so you can find them
    Makie.update!(P[:marks]; arg1 = [b.taken == 0 && flat(b.pos, c.pos) > 5 ? b.pos + Point3f(0, 0, 0.9f0 + 0.15f0 * sin(Float32(2w.t) + i)) : PARK
                                     for (i, b) in enumerate(m.berries)])
    m.pop_t += dt
    if m.pop_t < 0.6
        s = Float32(m.pop_t)
        Makie.update!(P[:pops]; arg1 = [m.pop_at + Point3f(1.2f0 * s * cos(2pi * k / N_POPS), 1.2f0 * s * sin(2pi * k / N_POPS), 1.6f0 * s - 3f0 * s^2) for k in 1:N_POPS],
                      markersize = 0.07f0 * (1 - s / 0.6f0) + 0.01f0)
    elseif m.pop_t - dt < 0.6
        Makie.update!(P[:pops]; arg1 = fill(PARK, N_POPS))
    end
    m.flash = max(0.0, m.flash - dt)
    left = max(0.0, RACE_TIME - m.t)
    theirs = sum(m.rival_score; init = 0)
    if m.state === :playing && (left <= 0 || all(b -> b.taken != 0, m.berries))
        finish!(m, game, c, theirs)
    end
    names = rival_names(m, game)
    msg = if m.state === :ready
        "Press W to start"
    elseif m.state === :over
        m.score > theirs ? "You win! $(m.score) to $theirs" : m.score == theirs ? "A tie: $(m.score) each" : "The critters win: $theirs to $(m.score)"
    else
        rest = [b for b in m.berries if b.taken == 0]
        near = isempty(rest) ? "" : (b = rest[argmin([flat(b.foot, c.pos) for b in rest])];
                                     @sprintf("  ·  berry %.0f m %s", flat(b.foot, c.pos), Base.invokelatest(firefly(game).direction_word, c, b.pos)))
        @sprintf("You %d  ·  Critters %d  ·  %2.0f s%s", m.score, theirs, left, near)
    end
    Makie.update!(P[:hud]; text = msg)
    # the start card says "Press W to start" itself: no second prompt above it (tester s44)
    (m.state !== :ready) == P[:hud].visible[] || (P[:hud].visible[] = m.state !== :ready)
    P[:hud].text_color[] = m.flash > 0 ? RGBf(0.55, 1, 0.55) : RGBf(1, 0.92, 0.85)
    m.state === :over && m.score > theirs && (c.action = :dance)
end


function finish!(m, game, c, theirs)
    w = game.world
    m.state = :over; m.t_state = 0.0
    delete!(P, :end_dir)
    won = m.score > theirs
    best = get!(() -> round(Int, load_best(game, "berry_race", 0)), P, :best)
    newbest = m.score > best
    newbest && (P[:best] = m.score; save_best!(game, "berry_race", m.score))
    P[:total] = get(P, :total, 0) + m.score
    save_berries!(game, P[:total])
    names = rival_names(m, game)
    basket = m.score == 0 ? "" : "\n$(m.score == 1 ? "Your berry goes" : "Your $(m.score) berries go") to the basket by the cottage\n($(P[:total]) in it now)."
    head = won ? "You win, $(m.score) berries to $(theirs)!" : m.score == theirs ? "A tie, $(m.score) berries each!" : "$(join(names, ", ", " and ")) win, $(theirs) berries to $(m.score)!"
    lv = level(game)
    won && lv < MAX_LEVEL && (P[:level] = lv + 1; save_best!(game, "berry_level", lv + 1))
    up = !won ? "" : lv < MAX_LEVEL ? "\nNext round: level $(lv + 1), the critters hurry sooner!" : "\nTop level: the berry champion!"
    tip = won ? (newbest ? "A new best: $(m.score) berries!" : "Your best: $best berries") :
        "Tip: hold Shift to run,\ngo for berries the critters are not after" * (best > 0 ? "\nYour best: $best berries" : "")
    Makie.update!(P[:card]; text = "$head\n$tip$up$basket\n\nPress R to play again")
    P[:card].visible[] = true
    won && (c.action = :dance)
    for (k, id) in enumerate(m.rivals)
        o = NG.creature(w, id)
        o.yaw = atan(c.pos[2] - o.pos[2], c.pos[1] - o.pos[1])
        o.goal = won ? NG.Goal(:answer, o.pos, :sit, 3.0, w.t + 3.0, true, 0, false) :
                       NG.Goal(:answer, o.pos, :jump, 3.0, w.t + 3.0, true, 0, false)
        NG.say!(w, o, won ? rand(w.rng, ("Well played!", "Next time...", "So fast!", "Hmpf.")) :
                            rand(w.rng, ("Ha! We won!", "Berries for us!", "Burp.", "Yay!")); duration = 2.5)
    end
end

NG.finished(m::BerryRace) = m.state === :over && m.t_state > 60

function NG.stop!(m::BerryRace, game)
    name_tags!(game, true)
    w = game.world
    for id in m.rivals   # set the critters free again
        o = NG.creature(w, id)
        o.goal.kind in (:race, :wait, :cheer, :full) && NG.choose_goal!(o, w)
    end
    if get(P, :version, 0) == PLOTS_VERSION
        foreach(k -> Makie.update!(P[k]; arg1 = fill(PARK, length(P[k][1][]))), (:berries, :marks, :pops))
        show_plots!(false)
    end
    NG.stop!(m.jump, game)
    game.rig.mode = :follow
end

# ── Wild races: now and then berries ripen on a bush and the critters close by race each other for them ──
const WILD_MAX = 4
const WILD_GAP = (90.0, 200.0)       # seconds between races (sim time)
const WILD_TIMEOUT = 45.0

mutable struct WildRace <: System
    berries::Vector{Berry}
    racers::Vector{Int32}
    score::Vector{Int}
    moved::Vector{Tuple{Point3f,Float64}}   # each racer's last spot and when it was there (a stuck racer goes around)
    detours::Vector{Int}
    active::Bool
    t0::Float64
    next_t::Float64
end
WildRace() = WildRace(Berry[], Int32[], Int[], Tuple{Point3f,Float64}[], Int[], false, 0.0, 0.0)

# the camera, while nobody steers it, watches the race: the racer in front, then the winner's dance
const WATCH = Ref((Int32(0), 0.0))     # (creature id, until sim time)
function watch_race(w)
    id, until = WATCH[]
    id != 0 && w.t < until && any(c -> c.id == id, w.creatures) ? id : nothing
end

function NG.start!(s::WildRace, game)
    game.stage === nothing && return
    s.next_t = game.world.t + 40.0
    haskey(P, :wild) && return
    P[:wild] = meshscatter!(game.stage.scene, fill(PARK, WILD_MAX); marker = Sphere(Point3f(0), 1f0), markersize = 0.2f0,
        color = BERRY_RED, material = BERRY_MAT)
end

"Land all the way from `a` to `b` (no pond or bay in between), sampled every half metre."
function land_path(w, a, b)
    n = max(2, ceil(Int, 2flat(a, b)))
    all(k -> (q = a + (k / n) * (b - a); NG.on_land(w.island, q[1], q[2]; margin = 0.3f0)), 0:n)
end

"Ripen berries on a bush in the open with two or three awake critters near it, and send them racing. False when there is none."
function start_wild!(s::WildRace, game)
    w = game.world
    lumi = NG.creature(w, "Lumi")
    # a near bush first; when the free critters stand together far from every bush (after a dance), a farther one (s32)
    for reach in (18f0, 32f0), bush in sort([p for p in w.props if p.kind === :bush]; by = _ -> rand(w.rng))
        near = [o for o in w.creatures if o !== lumi && free_creature(o) && 1.5f0 < flat(o.pos, bush.pos) < reach && land_path(w, o.pos, bush.pos)]
        length(near) >= 2 || continue
        bs = grow_berries(w; bushes = [bush], n = WILD_MAX)
        length(bs) >= 2 || continue
        sort!(near; by = o -> flat(o.pos, bush.pos))
        s.berries = bs
        s.racers = [o.id for o in first(near, 3)]
        s.score = zeros(Int, length(s.racers))
        s.moved = [(NG.creature(w, id).pos, w.t) for id in s.racers]
        s.detours = zeros(Int, length(s.racers))
        s.active = true; s.t0 = w.t
        for id in s.racers
            o = NG.creature(w, id)
            o.goal = NG.Goal(:race, bs[argmin([flat(b.foot, o.pos) for b in bs])].foot, :idle, 1e6, 0.0, false, 0, true)
            NG.say!(w, o, rand(w.rng, ("Berries!", "Ooh, ripe ones!", "Race you!", "Mine, mine!")); duration = 2.0)
        end
        WATCH[] = (s.racers[1], w.t + 2.0)
        NG.emit!(w, :berry_race_wild; who = join([NG.creature(w, id).name for id in s.racers], ", "))
        return true
    end
    return false
end

"The race is over: the one with the most berries dances, the others sulk, the berries go."
function end_wild!(s::WildRace, game; quiet = false)
    w = game.world
    best = maximum(s.score; init = 0)
    for (k, id) in enumerate(s.racers)
        o = NG.creature(w, id)
        o.goal.kind in (:race, :cheer, :sulk, :detour) || continue
        if quiet
            NG.choose_goal!(o, w)
        elseif s.score[k] == best && best > 0
            o.goal = NG.Goal(:dance, o.pos, :dance, 5.0, w.t + 5.0, true, 0, false)
            NG.say!(w, o, best == 1 ? "Ha! I got one!" : "I win! $(best) berries!"; duration = 2.5)
            WATCH[] = (o.id, w.t + 5.0)
            NG.emit!(w, :berry_race_won; who = o.name, berries = best)
        else
            o.goal = NG.Goal(:sulk, o.pos, :pout, 3.0, w.t + 3.0, true, 0, false)
            NG.say!(w, o, rand(w.rng, ("Aww...", "Next time!", "So fast!", "Hmpf.")); duration = 2.0)
        end
    end
    quiet && (WATCH[] = (Int32(0), 0.0))
    s.active = false
    s.berries = Berry[]
    s.next_t = w.t + WILD_GAP[1] + (WILD_GAP[2] - WILD_GAP[1]) * rand(w.rng)
end

const RACE_GOALS = (:race, :detour, :cheer, :sulk)

function NG.step!(s::WildRace, game, dt)
    haskey(P, :wild) || return
    w = game.world
    NG.CAMERA_FOCUS[] === watch_race || (NG.CAMERA_FOCUS[] = watch_race)
    if game.minigame isa BerryRace
        s.active && end_wild!(s, game; quiet = true)
    elseif !s.active
        w.t >= s.next_t && !NG.is_night(w) && !start_wild!(s, game) && (s.next_t = w.t + 20.0)   # berries ripen by day
    else
        for (k, id) in enumerate(s.racers)
            o = NG.creature(w, id)
            (o.controlled || o.action === :sleep) && continue
            # one taken away (a rain shower, a wave, a dance ring) has left the race: do not pull it back
            # (s38: a racer in the rain was dragged back to the bush, won and danced off the shower)
            o.goal.kind in RACE_GOALS || continue
            o.goal.kind === :sulk && continue          # gave up
            o.goal.kind === :cheer && w.t < o.goal.until && continue
            if flat(o.pos, s.moved[k][1]) > 0.3f0
                s.moved[k] = (o.pos, w.t)
            elseif w.t - s.moved[k][2] > 1.5             # stuck behind something: step sideways, three times, then give up
                s.detours[k] += 1
                if s.detours[k] > 3
                    o.goal = NG.Goal(:sulk, o.pos, :pout, 4.0, w.t + 4.0, true, 0, false)
                    NG.say!(w, o, rand(w.rng, ("I can't get there!", "Too far for me...", "Fine, keep them!")); duration = 2.0)
                    continue
                end
                a = o.yaw + (isodd(s.detours[k]) ? 1.6f0 : -1.6f0)
                side = NG.ground(w.island, (o.pos[1] + 2.5f0 * cos(a), o.pos[2] + 2.5f0 * sin(a)))
                o.goal = NG.Goal(:detour, side, :idle, 0.0, w.t + 1.5, false, 0, true)
                s.moved[k] = (o.pos, w.t + 1.5)
                continue
            end
            o.goal.kind === :detour && !o.goal.arrived && w.t < o.goal.until && continue
            rest = [i for i in eachindex(s.berries) if s.berries[i].taken == 0]
            isempty(rest) && break
            i = rest[argmin([flat(s.berries[i].foot, o.pos) for i in rest])]
            b = s.berries[i]
            if flat(o.pos, b.foot) < 0.45f0 + NG.body_radius(NG.species_of(o))
                b.taken = id
                s.score[k] += 1
                NG.say!(w, o, rand(w.rng, ("Mine!", "Nom!", "Got one!", "Yummy!")); duration = 1.4)
                o.goal = NG.Goal(:cheer, o.pos, :eat, 1.5, w.t + 1.5, true, 0, false)
                s.moved[k] = (o.pos, w.t + 1.5)           # munching is not being stuck
            elseif o.goal.kind !== :race || o.goal.target != b.foot
                o.goal = NG.Goal(:race, b.foot, :idle, 1e6, 0.0, false, 0, true)
            end
        end
        # watch the one closest to a berry that is left
        rest = [b for b in s.berries if b.taken == 0]
        racing = [id for id in s.racers if NG.creature(w, id).goal.kind in RACE_GOALS]
        if !isempty(rest) && !isempty(racing)
            d(id) = minimum(b -> flat(NG.creature(w, id).pos, b.foot), rest)
            WATCH[] = (racing[argmin(map(d, racing))], w.t + 2.0)
        end
        left = !any(id -> (o = NG.creature(w, id); o !== nothing && o.goal.kind in RACE_GOALS), s.racers)
        (left || all(b -> b.taken != 0, s.berries) || w.t - s.t0 > WILD_TIMEOUT) && end_wild!(s, game)
    end
    pts = fill(PARK, WILD_MAX)
    for (i, b) in enumerate(s.berries)
        b.taken == 0 && (pts[i] = b.pos + Point3f(0, 0, 0.03f0 * sin(Float32(3w.t) + i)))
    end
    get(P, :wild_pts, nothing) == pts || (P[:wild_pts] = pts; Makie.update!(P[:wild]; arg1 = pts))
end

function NG.stop!(s::WildRace, game)
    s.active && end_wild!(s, game; quiet = true)
    NG.CAMERA_FOCUS[] === watch_race && (NG.CAMERA_FOCUS[] = nothing)
    haskey(P, :wild) && Makie.update!(P[:wild]; arg1 = fill(PARK, WILD_MAX))
end

register!(BerryRace)
register!(WildRace())
register!(BerryBasket())
