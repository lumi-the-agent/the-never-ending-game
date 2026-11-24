# ── The world: an island, its creatures and things ───────────────────────────

# ── terrain ──────────────────────────────────────────────────────────────────

hash01(i::Int, j::Int, seed::Int) = Float32(hash((i, j, seed)) % UInt32) / Float32(typemax(UInt32))
smoothstep(a, b, x) = (t = clamp((x - a) / (b - a), 0, 1); t * t * (3 - 2t))

function value_noise(x::Real, y::Real, seed::Int)
    i, j = floor(Int, x), floor(Int, y)
    fx, fy = Float32(x - i), Float32(y - j)
    sx, sy = fx * fx * (3 - 2fx), fy * fy * (3 - 2fy)
    a, b = hash01(i, j, seed), hash01(i + 1, j, seed)
    c, d = hash01(i, j + 1, seed), hash01(i + 1, j + 1, seed)
    return a + (b - a) * sx + (c - a) * sy + (a - b - c + d) * sx * sy
end

"Fractal value noise in 0…1."
function fbm(x::Real, y::Real, seed::Int; octaves::Int = 4)
    s = 0.0f0; amp = 1.0f0; norm = 0.0f0
    for o in 0:(octaves - 1)
        s += amp * value_noise(x * 2^o, y * 2^o, seed + 31o)
        norm += amp; amp /= 2
    end
    return s / norm
end

"An island shape. Water level is z = 0."
struct Island
    seed::Int
    radius::Float32
    height::Float32
end

function terrain_height(is::Island, x::Real, y::Real)
    a = atan(y, x)
    coast = 1 + 0.35f0 * (fbm(2cos(a) + 5, 2sin(a) + 5, is.seed) - 0.5f0)
    r = sqrt(x^2 + y^2) / (is.radius * coast)
    land = 1 - smoothstep(0.6f0, 1.0f0, r)
    hills = fbm(x / 16, y / 16, is.seed + 7)
    deep = smoothstep(0.9f0, 1.5f0, r)
    return Float32(is.height * land * (0.25f0 + hills^2) - 1.0f0 * (1 - land) - 0.6f0 * deep + 0.15f0)
end

ground(is::Island, p) = Point3f(p[1], p[2], max(terrain_height(is, p[1], p[2]), -0.3f0))
on_land(is::Island, x, y; margin = 0.25f0) = terrain_height(is, x, y) > margin

# ── creatures ────────────────────────────────────────────────────────────────

"Needs are satisfaction levels in 0…1 (1 = fully satisfied); they decay."
mutable struct Needs
    hunger::Float32
    energy::Float32
    fun::Float32
    social::Float32
end
Needs() = Needs(0.8f0, 0.9f0, 0.7f0, 0.6f0)

"Personality in 0…1."
struct Traits
    curiosity::Float32
    sociability::Float32
    playfulness::Float32
    laziness::Float32
end
Traits(rng::AbstractRNG) = Traits(rand(rng, Float32), rand(rng, Float32), rand(rng, Float32), rand(rng, Float32))

"""
What a creature is up to: walk to `target`, then do `action` for `duration`
seconds. `until` is set on arrival. `kind` names the goal for dispatch.
"""
mutable struct Goal
    kind::Symbol            # :wander :eat :sleep :play :social :dance :idle :interact :user …
    target::Point3f
    action::Symbol          # what to do once there
    duration::Float64
    until::Float64          # sim time the action ends (set on arrival)
    arrived::Bool
    partner::Int32          # creature or prop id, or 0
    run::Bool               # hurry
end
Goal() = Goal(:idle, Point3f(0), :idle, 0.0, 0.0, true, 0, false)

mutable struct Creature
    id::Int32
    name::String
    species::String
    pos::Point3f
    yaw::Float32
    action::Symbol
    phase::Float32
    mood::Float32
    extra::Float32
    seed::Float32
    needs::Needs
    traits::Traits
    goal::Goal
    controlled::Bool        # driven by the player (mini games, "jump in")
    memory::Vector{String}  # recent happenings, newest last
end

const MEMORY_LENGTH = 12

function remember!(c::Creature, t::Real, text::AbstractString)
    push!(c.memory, @sprintf("[%.0f] %s", t, text))
    length(c.memory) > MEMORY_LENGTH && popfirst!(c.memory)
    return c
end

# ── props ────────────────────────────────────────────────────────────────────

mutable struct Prop
    id::Int32
    kind::Symbol            # :tree :bush :rock :flower :ball :asset …
    pos::Point3f
    yaw::Float32
    scale::Float32
    data::Dict{String,Any}  # kind specific: berries left, asset path, colour …
end

# ── speech ───────────────────────────────────────────────────────────────────

struct Speech
    who::Int32
    text::String
    from::Float64
    until::Float64
end

# ── the world ────────────────────────────────────────────────────────────────

abstract type Interaction end

mutable struct World
    t::Float64              # sim seconds since the world began
    day_length::Float64     # sim seconds per day
    seed::Int
    rng::Xoshiro
    island::Island
    creatures::Vector{Creature}
    props::Vector{Prop}
    speech::Vector{Speech}
    interactions::Vector{Interaction}
    next_id::Int32
    events::Vector{Pair{Symbol,Dict{String,Any}}}   # drained into the event log by the game loop
    actors::Vector{Actor}                           # things plugins added (see interfaces.jl)
    dormant::Vector{Dict{String,Any}}               # saved actors whose plugin is not loaded
end

"Queue an event for the log (the world itself never touches files)."
emit!(w::World, kind::Symbol; data...) =
    (push!(w.events, kind => Dict{String,Any}(String(k) => v for (k, v) in data)); nothing)

new_id!(w::World) = (id = w.next_id; w.next_id += 1; id)

# `nothing` when there is no such creature: plugins check `me === nothing`, and the old index error
# switched off ball play and flower gifts in the human's game while Lumi was being renamed (s61)
creature(w::World, id::Integer) = (i = findfirst(c -> c.id == id, w.creatures); i === nothing ? nothing : w.creatures[i])
creature(w::World, name::AbstractString) = (i = findfirst(c -> c.name == name, w.creatures); i === nothing ? nothing : w.creatures[i])
prop(w::World, id::Integer) = w.props[findfirst(p -> p.id == id, w.props)]

"Seconds per in-game day: 18000 s (5 h; ≤ 30 game minutes per 5 real minutes from 7 to 16 h). With 1440 s every mini game round slid into night (perfectionist-0046)."
const DAY_LENGTH = 18000.0
"The clock runs faster at night and slower at midday: `daytime = p + DAY_WARP sin(2πp) / 2π` of the linear phase p (night ≈ 1/3 of the day)."
const DAY_WARP = 0.7

"The linear phase of the day in 0…1 (0 = midnight): `w.t` advances it evenly."
day_phase(w::World) = mod(w.t / w.day_length + 0.3, 1.0)
warp_day(p) = mod(p + DAY_WARP * sinpi(2p) / 2pi, 1.0)
"The phase whose warped time of day is `d` (inverse of `warp_day`, bisection on the monotonic warp)."
function unwarp_day(d::Real)
    d = mod(d, 1.0)
    lo, hi = 0.0, 1.0
    for _ in 1:50
        mid = (lo + hi) / 2
        (mid + DAY_WARP * sinpi(2mid) / 2pi < d) ? (lo = mid) : (hi = mid)
    end
    return (lo + hi) / 2
end

"Time of day in 0…1 (0 = midnight, 0.5 = noon)."
daytime(w::World) = warp_day(day_phase(w))

"Move the clock FORWARD to `hour` (0…24) of the day (never back: plugins keep deadlines in `w.t`)."
skip_to_hour!(w::World, hour::Real) =
    (w.t += mod(unwarp_day(hour / 24) - day_phase(w), 1.0) * w.day_length; w)

"Change the day's length keeping the time of day; `w.t` only moves forward."
function set_day_length!(w::World, len::Real)
    w.day_length == len && return w
    p = day_phase(w)
    w.day_length = Float64(len)
    w.t += mod(p - day_phase(w), 1.0) * w.day_length
    return w
end
is_night(w::World) = (d = daytime(w); d < 0.22 || d > 0.85)

function random_land_point(w::World; tries::Int = 200, rmax = w.island.radius)
    for _ in 1:tries
        x, y = (2rand(w.rng, Float32) - 1) * rmax, (2rand(w.rng, Float32) - 1) * rmax
        on_land(w.island, x, y; margin = 0.35f0) && return ground(w.island, (x, y))
    end
    return ground(w.island, (0, 0))
end

function spawn!(w::World, species::AbstractString, name::AbstractString; pos = random_land_point(w),
                traits = Traits(w.rng))
    haskey(SPECIES, species) || error("unknown species $species; known: $(join(keys(SPECIES), ", "))")
    c = Creature(new_id!(w), name, species, ground(w.island, pos), 2pi * rand(w.rng, Float32), :idle, 0.0f0,
                 0.3f0, 0.0f0, rand(w.rng, Float32), Needs(), traits, Goal(), false, String[])
    push!(w.creatures, c)
    return c
end

function add_prop!(w::World, kind::Symbol, pos; yaw = 2pi * rand(w.rng, Float32), scale = 1.0f0, data...)
    p = Prop(new_id!(w), kind, ground(w.island, pos), Float32(yaw), Float32(scale),
             Dict{String,Any}(String(k) => v for (k, v) in data))
    push!(w.props, p)
    return p
end

const STARTER_NAMES = Dict(
    "Snootle" => ["Truffle", "Pickles", "Sir Sniffsalot"],
    "Fluffkin" => ["Cumulus", "Marshmallow"],
    "Blorbo" => ["Gloop", "Wibbles"],
    "Crabbit" => ["Pinchy", "Hopscotch"],
)

"A fresh island with Lumi, a few neighbours, trees, berry bushes, rocks and flowers."
function new_world(; seed::Int = 1, radius = 24.0f0, day_length = DAY_LENGTH)
    rng = Xoshiro(seed)
    w = World(0.0, day_length, seed, rng, Island(seed, radius, 3.0f0), Creature[], Prop[], Speech[],
              Interaction[], 1, Pair{Symbol,Dict{String,Any}}[], Actor[], Dict{String,Any}[])
    spawn!(w, "Lumi", "Lumi"; pos = (0, 0))
    for (sp, names) in sort!(collect(STARTER_NAMES)), n in names
        spawn!(w, sp, n)
    end
    for _ in 1:40
        add_prop!(w, :tree, random_land_point(w); scale = 0.7f0 + 0.6f0 * rand(rng, Float32))
    end
    for _ in 1:14
        add_prop!(w, :bush, random_land_point(w; rmax = 0.7radius); berries = 6)
    end
    for _ in 1:30
        add_prop!(w, :rock, random_land_point(w); scale = 0.3f0 + 0.8f0 * rand(rng, Float32))
    end
    for _ in 1:160
        add_prop!(w, :flower, random_land_point(w); scale = 0.7f0 + 0.6f0 * rand(rng, Float32),
                  hue = rand(rng, [0.0, 0.12, 0.6, 0.8, 0.95]))
    end
    add_prop!(w, :ball, ground(w.island, (2.5, 1.5)); scale = 1.0f0)
    return w
end

# ── snapshots ────────────────────────────────────────────────────────────────

pdict(p::Point3f) = [p[1], p[2], p[3]]

function snapshot(w::World)
    cdict(c) = Dict("id" => c.id, "name" => c.name, "species" => c.species, "pos" => pdict(c.pos), "yaw" => c.yaw,
                    "action" => String(c.action), "phase" => c.phase, "mood" => c.mood, "extra" => c.extra,
                    "seed" => c.seed, "needs" => [c.needs.hunger, c.needs.energy, c.needs.fun, c.needs.social],
                    "traits" => [c.traits.curiosity, c.traits.sociability, c.traits.playfulness, c.traits.laziness],
                    "memory" => c.memory)
    return Dict{String,Any}("t" => w.t, "day_length" => w.day_length, "seed" => w.seed, "next_id" => w.next_id,
                            "island" => Dict("seed" => w.island.seed, "radius" => w.island.radius, "height" => w.island.height),
                            "actions" => String.(ACTION_CODES),
                            "creatures" => [cdict(c) for c in w.creatures],
                            "props" => [Dict("id" => p.id, "kind" => String(p.kind), "pos" => pdict(p.pos), "yaw" => p.yaw,
                                             "scale" => p.scale, "data" => p.data) for p in w.props],
                            "actors" => vcat([actor_dict(a) for a in w.actors], w.dormant))
end

function world_from_snapshot(d::AbstractDict)
    is = d["island"]
    w = World(Float64(d["t"]), Float64(d["day_length"]), Int(d["seed"]), Xoshiro(Int(d["seed"]) + round(Int, d["t"])),
              Island(Int(is["seed"]), Float32(is["radius"]), Float32(is["height"])), Creature[], Prop[], Speech[],
              Interaction[], Int32(d["next_id"]), Pair{Symbol,Dict{String,Any}}[], Actor[],
              Dict{String,Any}[get(d, "actors", [])...])
    foreach(register_action! ∘ Symbol, d["actions"])
    for c in d["creatures"]
        n, tr = Float32.(c["needs"]), Float32.(c["traits"])
        push!(w.creatures, Creature(Int32(c["id"]), c["name"], c["species"], Point3f(c["pos"]...), Float32(c["yaw"]),
                                    Symbol(c["action"]), Float32(c["phase"]), Float32(c["mood"]), Float32(c["extra"]),
                                    Float32(c["seed"]), Needs(n...), Traits(tr...), Goal(), false, String.(c["memory"])))
    end
    for p in d["props"]
        push!(w.props, Prop(Int32(p["id"]), Symbol(p["kind"]), Point3f(p["pos"]...), Float32(p["yaw"]), Float32(p["scale"]),
                            Dict{String,Any}(p["data"])))
    end
    return w
end

"""
The caretaker's name: Sprout (the bean) until s60, then briefly Dandy, now Lumi (the human chose it).
A world saved before that, or a game still running with an old name, gets the new name and species here.
"""
function rename_hero!(w::World; from = ("Sprout", "Dandy"), to = "Lumi")
    n = 0
    for c in w.creatures
        c.species in from && (c.species = to; n += 1)
        c.name in from && (c.name = to)
        for f in from
            replace!(m -> replace(m, f => to), c.memory)
        end
    end
    return n
end

save_snapshot(path::AbstractString, w::World) = write_json(path, snapshot(w))
load_snapshot(path::AbstractString) = (w = world_from_snapshot(read_json(path)); rename_hero!(w); w)

"The pose record of every creature, as the frame log stores it."
frame_record(w::World) = FrameRecord(w.t, time(),
    [PoseRecord(c.id, c.pos, c.yaw, action_code(c.action), c.phase, c.mood, c.extra) for c in w.creatures])
