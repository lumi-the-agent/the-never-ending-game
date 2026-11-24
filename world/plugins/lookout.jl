# The sunset lookout (Lumi's wish: "a lookout on the hill with a bench, where I can watch the sunset
# over the sea"): a wooden bench on the west rise beside the vegetable patch, facing the setting sun.
# Every evening Lumi walks there, sits down and watches the sky; one or two free friends nearby come
# and sit beside it, and they say a few quiet words. The follow camera frames them from the side with
# the sea and the low sun in the view (CAMERA_GROUPS). Goal :sunset is busy (nobody boops them away).
# The bench is a generated mesh once the worker has made it (checked every 20 s); planks until then.
isdefined(Main, :LOOKOUT) || Core.eval(Main, :(const LOOKOUT = Dict{Symbol,Any}()))

const NG = NeverendingGame
const L = Main.LOOKOUT
const BENCH_ASSET = ("20261124-004844-465-asset", 0.75f0)   # (asset id, height in m)
const SEAT = (-16.0f0, 9.0f0)                              # the bench (open ground, 4 m from the west shore)
const SUNWARD = Vec2f(-1, -0.45) / norm(Vec2f(-1, -0.45))    # where the sun sets (scenery.jl `sun` at daytime 0.75)
const SIDE = Vec2f(-SUNWARD[2], SUNWARD[1])                  # along the bench
const EVENING = (17.4, 19.9)                                 # hours: the walk out, the sitting, until dusk
const PLACES = (0.0f0, -0.75f0, 0.75f0)                      # Lumi in the middle, friends beside it
const SUNSET_WORDS = (
    ("Look, the sky is going pink.", "Ooh, pretty."),
    ("My favourite time of day.", "Mine too."),
    ("The sea is all gold now.", "Like honey!"),
    ("Shh... listen to the waves.", "*happy sigh*"),
)
const WOOD = RGBf(0.62, 0.42, 0.24)

hour(w) = 24 * NG.daytime(w)
emote(id, kind) = isdefined(Main, :EMOTES) && haskey(Main.EMOTES, :emote) && Base.invokelatest(Main.EMOTES[:emote], id, kind)
place_spot(w, k) = (p = Vec2f(SEAT...) + PLACES[k] * SIDE + 0.15f0 * SUNWARD; Point3f(p[1], p[2], NG.terrain_height(w.island, p[1], p[2])))
lumi_of(w) = (i = findfirst(c -> c.name == "Lumi", w.creatures); i === nothing ? nothing : w.creatures[i])
free_one(c) = !c.controlled && c.action !== :sleep && c.goal.kind ∉ NG.BUSY_GOALS && c.goal.kind ∉ (:follow, :interact)

"The generated bench and its scale, or nothing while the worker makes it."
function bench_model(game)
    haskey(L, :model) && return L[:model]
    id, h = BENCH_ASSET
    any(e -> e["id"] == id && isfile(get(e, "mesh", "")), NG.load_catalog(game.paths)) || return nothing
    model = NG.lifted_asset(game.paths, id)
    zs = [p[3] for p in GeometryBasics.coordinates(model.mesh)]
    L[:model] = (model, h / maximum(zs))
    return L[:model]
end

function clear_bench!()
    for p in get(L, :plots, Any[])
        delete!(p.parent, p)
    end
    L[:plots] = Any[]
end

"The bench: the generated model turned to face the sunset, or planks (seat, backrest, legs) until it exists."
function build_bench!(game)
    clear_bench!()
    sc = game.stage.scene
    is = game.world.island
    z = NG.terrain_height(is, SEAT...)
    c = Point3f(SEAT[1], SEAT[2], z)
    yaw = atan(SUNWARD[2], SUNWARD[1]) + Float32(pi / 2)       # model front (-y) towards the sun
    bm = bench_model(game)
    if bm === nothing
        q = NG.rot_z(yaw)
        box = GeometryBasics.normal_mesh(Rect3f(Vec3f(-0.5), Vec3f(1)))
        # local frame: x along the bench, -y towards the sun, z up
        parts = [(Point3f(0, 0, 0.42), Vec3f(1.9, 0.42, 0.07)),          # seat
                 (Point3f(0, 0.22, 0.72), Vec3f(1.9, 0.06, 0.32)),        # backrest
                 (Point3f(-0.8, -0.14, 0.2), Vec3f(0.08, 0.08, 0.42)), (Point3f(0.8, -0.14, 0.2), Vec3f(0.08, 0.08, 0.42)),
                 (Point3f(-0.8, 0.16, 0.36), Vec3f(0.08, 0.08, 0.72)), (Point3f(0.8, 0.16, 0.36), Vec3f(0.08, 0.08, 0.72))]
        push!(L[:plots], meshscatter!(sc, [c + q * p for (p, _) in parts]; marker = box, markersize = [s for (_, s) in parts],
            rotation = [q for _ in parts], color = WOOD, name = :lookout_bench))
    else
        model, s = bm
        push!(L[:plots], NG.asset_instances!(sc, model, [c]; rotation = [NG.rot_z(yaw)], markersize = Vec3f(s), name = :lookout_bench))
    end
    L[:built] = bm !== nothing
end

"Sit down facing the sea: the goal that keeps one on the bench until dusk."
function sit_goal(w, k)
    until = w.t + 60.0
    NG.Goal(:sunset, place_spot(w, k), :sit, 1e5, until, false, 0, false)
end

"Evening: send a free Lumi to the bench and up to two free friends within 30 m beside it."
function gather!(w)
    me = lumi_of(w)
    (me === nothing || !free_one(me) || me.goal.kind === :sunset) && return false
    NG.leave_interactions!(w, me)
    me.goal = sit_goal(w, 1)
    sitters = [me.id]
    near = sort([c for c in w.creatures if c !== me && free_one(c) && norm(Vec2f(c.pos[1] - SEAT[1], c.pos[2] - SEAT[2])) < 30];
                by = c -> norm(Vec2f(c.pos[1] - SEAT[1], c.pos[2] - SEAT[2])))
    for (k, c) in zip(2:3, near)
        NG.leave_interactions!(w, c)
        c.goal = sit_goal(w, k)
        push!(sitters, c.id)
    end
    L[:sitters] = sitters; L[:seated] = Int32[]; L[:said] = 0; L[:next_word] = w.t + 6.0
    NG.say!(w, me, "Sunset time! Come sit with me."; duration = 2.5)
    NG.emit!(w, :sunset_lookout; who = join([NG.creature(w, id).name for id in sitters], ", "))
    return true
end

"Those still on their way or on the bench (anyone called away or steered drops out)."
on_bench(w) = filter(id -> (c = NG.creature(w, id); c !== nothing && !c.controlled && c.goal.kind === :sunset), get(L, :sitters, Int32[]))

function step_sitters!(w)
    ids = on_bench(w)
    L[:sitters] = ids
    isempty(ids) && return
    h = hour(w)
    over = !(EVENING[1] - 0.5 <= h <= EVENING[2])   # dusk, or a clock jump past the evening (11:00 on the bench, s53)
    for id in ids
        c = NG.creature(w, id)
        if over
            # dusk: up and off to bed. The goal is REPLACED: `until` alone left a friend still walking
            # there on :sunset (tests s51: "still on the bench at 20:00: Pickles")
            c.goal = NG.Goal(:idle, c.pos, :idle, 1.0, w.t + 1.0, true, 0, false)
            c.name == "Lumi" && h > EVENING[2] && NG.say!(w, c, "Good night, sea."; duration = 2.5)
            continue
        end
        c.goal.arrived || continue
        if !(id in get!(L, :seated, Int32[]))       # sits down: a little heart
            push!(L[:seated], id)
            emote(id, :heart)
        end
        c.goal.until = max(c.goal.until, w.t + 5.0)   # sitting until dusk
        c.action = :sit
        c.pos = c.goal.target                     # on the seat (a fern or a neighbour pushed Lumi 0.9 m off it, s52)
        c.yaw = atan(SUNWARD[2], SUNWARD[1]) - NG.species_of(c).heading
    end
    over && (L[:sitters] = Int32[]; return)
    # a few quiet words, Lumi first, the friend answers
    seated = [id for id in ids if NG.creature(w, id).goal.arrived]
    if length(seated) >= 2 && w.t >= get(L, :next_word, Inf) && L[:said] < length(SUNSET_WORDS)
        L[:said] += 1
        a, b = SUNSET_WORDS[L[:said]]
        me = lumi_of(w)
        first_one = me !== nothing && me.id in seated ? me : NG.creature(w, seated[1])
        other = NG.creature(w, first(filter(!=(first_one.id), seated)))
        NG.say!(w, first_one, a; duration = 3.0)
        L[:answer] = (other.id, b, w.t + 3.2)
        L[:next_word] = w.t + 14.0
    end
    ans = get(L, :answer, nothing)
    if ans !== nothing && w.t >= ans[3]
        c = NG.creature(w, ans[1])
        c !== nothing && c.goal.kind === :sunset && NG.say!(w, c, ans[2]; duration = 3.0)
        L[:answer] = nothing
    end
end

"""
The camera: from behind the bench over the sitters' heads, out to the sea and the low sun.
`group_view` looks across the line through the two farthest points (first → second, turned left):
two points 1.6 m to either side of the bench, `+SIDE` first, make it look along `SUNWARD`.
"""
function lookout_group(w)
    ids = filter(id -> NG.creature(w, id).goal.arrived, on_bench(w))
    isempty(ids) && return nothing
    me = lumi_of(w)
    subj = me !== nothing && me.id in ids ? me.id : ids[1]
    # a narrow pair (3.2 m apart): group_view backs off 1.15 m per metre of spread, and at 6 m the eye
    # sat 10 m back among the trees, so it turned round to a clear view from the north, looking
    # down on the bench with the sun out of the picture (review s51, tester s51)
    c = Vec2f(SEAT...) + 1.0f0 * SUNWARD
    z = NG.terrain_height(w.island, SEAT...)
    l, r = c + 1.6f0 * SIDE, c - 1.6f0 * SIDE
    pts = Point3f[Point3f(l[1], l[2], z + 0.8f0), Point3f(r[1], r[2], z + 0.8f0)]
    append!(pts, [NG.creature(w, id).pos for id in ids])
    # a point up over the sea lifts the look point off the grass into the evening sky (closer than l to r)
    s = c + 1.0f0 * SUNWARD
    push!(pts, Point3f(s[1], s[2], z + 3.5f0))
    return (subj, pts, bench_view(w))
end

"""
The view over the sitters' heads (3rd element of the CAMERA_GROUPS answer: group_view alone backed
off among the trees and turned round to the north, looking down on the bench, review s51): 4.5 m
behind the bench, 1.9 m up, looking out along `SUNWARD` a little down, so the horizon, the low
sun and its path on the sea fill the upper half and the three on the bench the lower.
"""
function bench_view(w)
    S = Vec2f(SEAT...)
    e = S - 4.5f0 * SUNWARD
    t = S + 10f0 * SUNWARD
    ez = NG.terrain_height(w.island, e[1], e[2]) + 1.9f0
    return (Point3f(e[1], e[2], ez), Point3f(t[1], t[2], ez - 1.6f0))
end

function lookout_moment(w)
    ids = filter(id -> NG.creature(w, id).goal.arrived, on_bench(w))
    isempty(ids) && return nothing
    me = lumi_of(w)
    return me !== nothing && me.id in ids ? me.id : ids[1]
end

struct Lookout <: System end

function NG.start!(::Lookout, game)
    game.stage === nothing && return
    :sunset in NG.BUSY_GOALS || push!(NG.BUSY_GOALS, :sunset)
    # after a reload the ones already out on the bench stay in the list (and get up at dusk)
    L[:sitters] = [c.id for c in game.world.creatures if c.goal.kind === :sunset]; L[:answer] = nothing; L[:check] = 0.0
    L[:said] = 0
    delete!(L, :model)
    build_bench!(game)
    NG.CAMERA_GROUPS["lookout"] = lookout_group
    NG.CAMERA_MOMENTS["lookout"] = lookout_moment
    return
end

function NG.step!(::Lookout, game, dt)
    game.stage === nothing && return
    w = game.world
    L[:check] += dt
    if L[:check] > 20
        L[:check] = 0.0
        get(L, :built, false) || (bench_model(game) === nothing || build_bench!(game))
    end
    day = floor(Int, w.t / w.day_length)
    h = hour(w)
    if EVENING[1] <= h < EVENING[2] - 0.5 && get(L, :day, -1) != day && game.minigame === nothing
        gather!(w) && (L[:day] = day)
    end
    step_sitters!(w)
end

function NG.stop!(::Lookout, game)
    delete!(NG.CAMERA_GROUPS, "lookout"); delete!(NG.CAMERA_MOMENTS, "lookout")
    for id in on_bench(game.world)               # nobody is left sitting on a bench that is gone
        c = NG.creature(game.world, id)
        c.goal = NG.Goal(:idle, c.pos, :idle, 1.0, game.world.t + 1.0, true, 0, false); c.action = :idle
    end
    L[:sitters] = Int32[]
    clear_bench!()
end

register!(Lookout())
