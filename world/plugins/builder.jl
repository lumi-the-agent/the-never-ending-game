# Lumi builds the island (the human, s46: "one should be able to watch how the figure places new items").
# - After a publish (`published!`, human's game only): the plots that arrived are hidden, Lumi walks to
#   each place with a crate over its head, kneels and works there, and the things appear as it finishes
#   (a little hop, a heart, a line). While the human steers Lumi, the nearest free critter carries.
# - Between publishes (human's game only): when a plugin in world/plugins was edited in the last minutes
#   and is not published yet, Lumi goes to where that plugin's things stand and tinkers there.
# The camera watches the builder (CAMERA_MOMENTS). Spots per plugin are remembered in state/builder.json.
const NG = NeverendingGame

isdefined(Main, :BUILDER) ||
    Core.eval(Main, :(const BUILDER = Dict{Symbol,Any}(:jobs => Any[], :job => nothing, :seen => Set{UInt}(),
                                                       :spots => Dict{String,Any}(), :plots => Dict{Symbol,Any}(),
                                                       :busy => nothing, :next_check => 0.0, :loaded => false)))
const B = Main.BUILDER
const HIDE = Point3f(0, 0, -50)
const WALK_LIMIT = 50.0      # s: a builder that cannot get there finishes where it stands
const WORK = 6.0             # s kneeling at the spot before the things appear
const TINKER = 18.0          # s tinkering between publishes
const RECENT = 12 * 60       # s: an unpublished plugin edited this recently is "being worked on"
const BUILD_GOALS = (:build, :tinker, :buildwatch)
const HELPERS = 2           # free friends nearby who come to watch a build and cheer at the end (Lumi's wish, s52)
const HELP_RANGE = 16f0     # m from the site

# what a plugin builds, in words for the speech bubble
const WORDS = Dict("dancecircle" => "the dance rings", "cairns" => "the cairn", "lamplight" => "the lanterns",
                   "flowerfield" => "the flower field", "flora" => "the flowers", "beach" => "the beach",
                   "meadow" => "the meadow", "berry_race" => "the berry race", "hideseek" => "hide and seek",
                   "firefly_catch" => "firefly catch", "ballplay" => "the ball game", "beds" => "the beds",
                   "outfits" => "everyone's outfits", "showers" => "the rain", "moon" => "the moon",
                   "stars" => "the stars", "clouds" => "the clouds", "areas" => "the paths",
                   "greetings" => "the parade", "builder" => "my workshop")
words(name) = get(WORDS, name, "the " * replace(name, "_" => " "))

spots_file(game) = joinpath(game.paths.state, "builder.json")
function load_spots!(game)
    B[:loaded] && return
    f = spots_file(game)
    isfile(f) && for (k, v) in NG.JSON.parse(read(f, String))
        B[:spots][k] = Point3f(v...)
    end
    B[:loaded] = true
end
save_spots(game) = game.dash === nothing ||
    write(spots_file(game), NG.JSON.json(Dict(k => collect(v) for (k, v) in B[:spots])))

live_game(game) = game.paths.instance === :live && game.dash !== nothing
lumi(w) = (i = findfirst(c -> c.name == "Lumi", w.creatures); i === nothing ? nothing : w.creatures[i])
flat(a, b) = hypot(a[1] - b[1], a[2] - b[2])

# ── the plots that arrive with a publish ─────────────────────────────────────

plot_ids(sc) = Set{UInt}(objectid(p) for p in sc.plots)

"Centre of a plot's bounding box when it is a thing on the island (not the sky, the sea or a hidden pool)."
function place_of(p, w)
    bb = Makie.boundingbox(p)
    o, d = Makie.origin(bb), Makie.widths(bb)
    all(isfinite, o) && all(isfinite, d) || return nothing
    maximum(d[1:2]) < 25 || return nothing                 # the whole island (terrain paint, sky): no one spot
    c = Point3f(o .+ d ./ 2)
    hypot(c[1], c[2]) < w.island.radius + 2 || return nothing
    return c
end

"A walkable spot beside `c` (on land, off solids), on the side `from` comes from."
function stand_spot(w, c, from)
    a = atan(from[2] - c[2], from[1] - c[1])
    for r in (1.3f0, 1.8f0, 2.5f0, 3.5f0), da in (0.0f0, 0.8f0, -0.8f0, 1.6f0, -1.6f0, 3.14f0)
        x, y = c[1] + r * cos(a + da), c[2] + r * sin(a + da)
        NG.on_land(w.island, x, y; margin = 0.15f0) || continue
        any(p -> p.kind in (:tree, :rock, :bush) &&
                 flat(p.pos, (x, y)) < get(NG.SOLID_FOOTPRINT, p.kind, 0.5f0) * p.scale + 0.5f0, w.props) && continue
        return NG.ground(w.island, (x, y))
    end
    return NG.ground(w.island, (c[1], c[2]))
end

clear_at(w, x, y) = NG.on_land(w.island, x, y; margin = 0.15f0) &&
    !any(p -> p.kind in (:tree, :rock, :bush) && flat(p.pos, (x, y)) < get(NG.SOLID_FOOTPRINT, p.kind, 0.5f0) * p.scale + 0.5f0, w.props)

"""
A builder walking in a straight line can wedge between two trunks (s52: Lumi walked on the spot
in a tree nook south of the cairn, was re-sent every 12 s and never built). No 0.3 m of progress
in 3 s: step out sideways or back to an open spot 2.5 m away, then head for the site again.
"""
function unstuck!(w, c, job)
    d, t = job[:progress]
    dn = flat(c.pos, job[:detour] ? c.goal.target : job[:spot])
    dn < d - 0.3f0 && (job[:progress] = (dn, w.t); return)
    w.t - t < 3 && return
    a = atan(job[:spot][2] - c.pos[2], job[:spot][1] - c.pos[1])
    for da in (1.57f0, -1.57f0, 2.36f0, -2.36f0, 3.14f0), r in (2.5f0, 1.6f0)
        x, y = c.pos[1] + r * cos(a + da), c.pos[2] + r * sin(a + da)
        clear_at(w, x, y) || continue
        # the line out must not run through a trunk either
        mx, my = c.pos[1] + 0.5f0r * cos(a + da), c.pos[2] + 0.5f0r * sin(a + da)
        clear_at(w, mx, my) || continue
        send!(c, w, :build, NG.ground(w.island, (x, y)), WORK)
        job[:detour] = true
        job[:progress] = (flat(c.pos, (x, y)), w.t)
        return
    end
    job[:progress] = (dn, w.t)
end

"Jobs for the arrived plugins: their new plots grouped by place (within 6 m), hidden until built."
function plan_jobs!(game, names)
    w, sc = game.world, game.stage.scene
    new = [p for p in sc.plots if !(objectid(p) in B[:seen])]
    groups = Any[]
    loose = Any[]
    for p in new
        c = place_of(p, w)
        if c === nothing
            push!(loose, p)
            continue
        end
        g = findfirst(g -> flat(g.centre, c) < 6, groups)
        g === nothing ? push!(groups, (; centre = c, plots = Any[p])) : push!(groups[g].plots, p)
    end
    label = join(words.(names[1:min(2, end)]), " and ")
    if isempty(groups)          # nothing new to place (changed behaviour): build at the plugin's remembered spot
        name = first(names)
        c = get(B[:spots], name, nothing)
        c === nothing && (me = lumi(w); c = me === nothing ? Point3f(0) : me.pos)
        push!(groups, (; centre = c, plots = Any[]))
    end
    sort!(groups; by = g -> -length(g.plots))
    for g in groups[4:end]                               # three places at most: the rest appear with the third
        append!(groups[3].plots, g.plots)
    end
    groups = groups[1:min(3, end)]
    append!(groups[end].plots, loose)
    for name in names
        B[:spots][name] = groups[1].centre
    end
    save_spots(game)
    for (i, g) in enumerate(groups)
        vis = [(p, p.visible[]) for p in g.plots]
        for (p, _) in vis
            p.visible = false
        end
        push!(B[:jobs], Dict{Symbol,Any}(:centre => g.centre, :plots => vis, :label => label, :last => i == length(groups),
                                          :who => 0, :since => game.world.t, :stage => :go))
    end
end

# ── who builds ───────────────────────────────────────────────────────────────

# Lumi gets up to build (it is the agent's work); the others are left asleep
# Lumi puts down any pastime of its own (fishing, a pebble, a butterfly chase: s48, the suite had Lumi fishing
# and a critter built instead); only a game it holds together with others (a dance ring, the rain party, a ball game) waits
const LUMI_KEEPS = (:circle, :rain, :fetch, :rally_wait)
usable(c) = c.name == "Lumi" ? (!c.controlled && c.goal.kind ∉ LUMI_KEEPS) :
            !c.controlled && c.action !== :sleep && c.goal.kind ∉ (:interact, :follow) &&
            (c.goal.kind in BUILD_GOALS || c.goal.kind ∉ NG.BUSY_GOALS)

"Lumi, or (when the human steers Lumi or a mini game runs) the nearest free critter."
function builder_for(game, at)
    w = game.world
    me = lumi(w)
    me !== nothing && game.minigame === nothing && usable(me) && return me
    best, d = nothing, Inf32
    for c in w.creatures
        c.name == "Lumi" && continue
        usable(c) || continue
        dd = flat(c.pos, at)
        dd < d && ((best, d) = (c, dd))
    end
    return best
end

function send!(c, w, kind, target, seconds)
    NG.leave_interactions!(w, c)
    c.goal = NG.Goal(kind, target, :eat, seconds, w.t + WALK_LIMIT, false, 0, false)
end

function reveal!(game, job)
    for (p, v) in job[:plots]
        p.visible = v
    end
    empty!(job[:plots])
end

function step_job!(game, job)
    w = game.world
    c = job[:who] == 0 ? nothing : NG.creature(w, job[:who])
    # a builder stuck in a nook loses its walk to unstick! (12 s without progress) and was sent again and again,
    # with `since` reset each time: the build never ended (s49, the suite's "stage go, Lumi build idle")
    started = get!(job, :started, w.t)
    if w.t - started > WALK_LIMIT + 2WORK
        c === nothing ? reveal!(game, job) : finish!(game, job, c)
        return true
    end
    if c === nothing || c.controlled || c.goal.kind !== :build
        if job[:stage] === :work && c !== nothing && c.goal.kind !== :build
            return finish!(game, job, c)                  # the work time ran out: done
        end
        c !== nothing && c.goal.kind === :build && (c.goal = NG.Goal())   # taken over by the player: someone else carries
        c = builder_for(game, job[:centre])
        if c === nothing                                  # nobody free: it appears by itself after a while
            w.t - job[:since] > 8 && (reveal!(game, job); return true)
            return false
        end
        job[:who] = c.id
        job[:stage] = :go
        job[:since] = w.t
        job[:spot] = stand_spot(w, job[:centre], c.pos); job[:detour] = false
        job[:progress] = (flat(c.pos, job[:spot]), w.t)
        send!(c, w, :build, job[:spot], WORK)
        haskey(job, :helpers) || call_helpers!(game, job, c)   # friends set off with planks too (Lumi's wish)
        NG.say!(w, c, rand(w.rng, ("Coming! Something new!", "Ooh, new things to put up!", "Off to build!")); duration = 2.5)
    end
    if job[:stage] === :go && c.goal.arrived && get(job, :detour, false)
        # round the trees: now on to the site
        job[:detour] = false; job[:progress] = (flat(c.pos, job[:spot]), w.t)
        send!(c, w, :build, job[:spot], WORK)
    elseif job[:stage] === :go && !c.goal.arrived && haskey(job, :spot)
        unstuck!(w, c, job)
    end
    if job[:stage] === :go && c.goal.arrived && !get(job, :detour, false)
        job[:stage] = :work
        c.yaw = atan(job[:centre][2] - c.pos[2], job[:centre][1] - c.pos[1]) - NG.species_of(c).heading
        emote(c.id, :note)
        job[:work_at] = w.t
    elseif job[:stage] === :go && w.t - job[:since] > WALK_LIMIT
        return finish!(game, job, c)                      # could not get there: it appears anyway
    end
    for id in get(job, :helpers, Int32[])          # the friends who came to watch face the site
        h = NG.creature(w, id)
        h !== nothing && h.goal.kind === :buildwatch && h.goal.arrived &&
            (h.yaw = atan(job[:centre][2] - h.pos[2], job[:centre][1] - h.pos[1]) - NG.species_of(h).heading)
    end
    # friends still on their way: a few more seconds of work, so they see it appear (at most 7 s more)
    if job[:stage] === :work && w.t - get(job, :work_at, w.t) < WORK + 7 &&
       any(id -> (h = NG.creature(w, id); h !== nothing && h.goal.kind === :buildwatch && !h.goal.arrived), get(job, :helpers, Int32[]))
        c.goal.until = max(c.goal.until, w.t + 1.0)
    end
    job[:stage] === :work && w.t >= c.goal.until - 0.3 && return finish!(game, job, c)
    return false
end

free_friend(c) = !c.controlled && c.name != "Lumi" && c.action !== :sleep && c.goal.kind ∉ NG.BUSY_GOALS && c.goal.kind ∉ (:follow, :interact)

"""
Lumi's wish "my friends help me build": up to `HELPERS` free friends within `HELP_RANGE` set off
with the builder, each with a plank over its head (`planks!`), come over, stand round the site facing it, and cheer with a jump and a heart when the
thing appears (`cheer_helpers!`).
"""
function call_helpers!(game, job, builder)
    w = game.world
    ctr = job[:centre]
    near = sort([c for c in w.creatures if c !== builder && free_friend(c) && flat(c.pos, ctr) < HELP_RANGE]; by = c -> flat(c.pos, ctr))
    job[:helpers] = Int32[]
    for (k, c) in enumerate(Iterators.take(near, HELPERS))
        # on either side of the builder, so the camera behind it sees them too
        a = atan(job[:spot][2] - ctr[2], job[:spot][1] - ctr[1]) + (k == 1 ? 1.2f0 : -1.2f0)
        from = Point3f(ctr[1] + 3cos(a), ctr[2] + 3sin(a), ctr[3])
        NG.leave_interactions!(w, c)
        c.goal = NG.Goal(:buildwatch, stand_spot(w, ctr, from), :idle, WORK + 6, w.t + WALK_LIMIT, false, 0, false)
        push!(job[:helpers], c.id)
        k == 1 && NG.say!(w, c, rand(w.rng, ("Ooh, what are you making?", "Can I watch?", "Something new!")); duration = 2.5)
    end
    isempty(job[:helpers]) || NG.emit!(w, :build_helpers; who = join([NG.creature(w, id).name for id in job[:helpers]], ", "))
end

function cheer_helpers!(game, job)
    w = game.world
    for (k, id) in enumerate(get(job, :helpers, Int32[]))
        c = NG.creature(w, id)
        (c === nothing || c.controlled || c.goal.kind !== :buildwatch) && continue
        c.goal = NG.Goal(:answer, c.pos, :jump, 1.2, w.t + 1.2, true, 0, false)
        emote(id, k == 1 ? :heart : :note)
        k == 1 && NG.say!(w, c, rand(w.rng, ("Yay! It's lovely!", "Wooow!", "Hooray, Lumi!")); duration = 2.5)
    end
    job[:helpers] = Int32[]
end

emote(id, kind) = isdefined(Main, :EMOTES) && haskey(Main.EMOTES, :emote) && Base.invokelatest(Main.EMOTES[:emote], id, kind)

function finish!(game, job, c)
    w = game.world
    reveal!(game, job)
    cheer_helpers!(game, job)
    emote(c.id, :heart)
    job[:last] && NG.say!(w, c, "Ta-da! " * uppercasefirst(job[:label]) * "!"; duration = 3.5)
    NG.remember!(c, w.t, "built " * job[:label])
    # proud of it: wings out, chin up (todo #325; was a 1.2 s hop)
    c.goal.kind === :build && (c.goal = NG.Goal(:answer, c.pos, :proud, 2.5, w.t + 2.5, true, 0, false))
    B[:crate_who] = 0
    d = B[:plots]
    haskey(d, :crate) && Makie.update!(d[:crate]; arg1 = [HIDE], markersize = [Vec3f(0)])
    haskey(d, :carry) && (delete!(game.stage.scene, d[:carry]); delete!(d, :carry))   # it stands there now, full size
    B[:watch] = (c.id, w.t + 5.0)
    B[:puff] = (job[:centre], w.t)
    return true
end

# ── between publishes: tinkering at what the agent is working on ─────────────

"The plugin edited most recently in world/plugins and not yet published (nothing when none in the last minutes)."
function being_worked_on(game)
    src = NG.working_plugins(game.paths)
    best, t = nothing, time() - RECENT
    for f in NG.plugin_files(src)
        m = mtime(joinpath(src, f))
        m > t || continue
        live = joinpath(game.paths.plugins, f)
        isfile(live) && read(live, String) == read(joinpath(src, f), String) && continue
        (best, t) = (first(splitext(f)), m)
    end
    return best
end

function tinker!(game)
    w = game.world
    me = lumi(w)
    me === nothing && return
    if B[:busy] !== nothing          # keep at it while the spot is reached and the work goes on
        me.goal.kind === :tinker && return
        # one round is over: look again soon, so Lumi works on without starting back to bed in between (s46)
        me.goal.kind === :build || (B[:next_check] = min(B[:next_check], w.t + 1))
        B[:last_busy] = B[:busy]
        B[:busy] = nothing
    end
    w.t < B[:next_check] && return
    B[:next_check] = w.t + 25
    game.minigame === nothing && usable(me) && me.goal.kind ∉ BUILD_GOALS || return
    name = being_worked_on(game)
    name === nothing && (B[:last_busy] = nothing; return)
    # where it works: the plugin's place, else one spot near Lumi kept for the plugin (not saved)
    # (s54: with no place of its own yet, the work happens at the workbench by the cottage, workshop.jl)
    bench = haskey(B[:spots], name) || !isdefined(Main, :WORKSHOP) ? nothing : get(Main.WORKSHOP, :spot, nothing)
    if bench !== nothing
        (q, a) = bench
        send!(me, w, :tinker, NG.ground(w.island, (q[1] + 0.95f0 * cos(a), q[2] + 0.95f0 * sin(a))), TINKER)
    else
        c = get!(B[:spots], name, me.pos + Point3f(2cos(me.seed * 9), 2sin(me.seed * 9), 0))
        send!(me, w, :tinker, stand_spot(w, c, me.pos), TINKER)
    end
    again = get(B, :last_busy, nothing) == name
    # a new piece of work: say what it is and let the camera look (the moment); later rounds go on quietly
    again && w.t - get(B, :said, -Inf) < 120 || (NG.say!(w, me, "Working on " * words(name) * "…"; duration = 3); B[:said] = w.t)
    B[:first_round] = !again
    B[:busy] = name
end

# ── the crate over the builder's head ────────────────────────────────────────

const CRATE_ASSET = "20261123-193127-127-asset"   # "a small cute wooden crate with a rope handle"
const PLANK = RGBf(0.66, 0.46, 0.27)

"The helpers' planks: one box per helper over its head while it walks to the site and watches."
function planks!(game)
    d = B[:plots]
    if !haskey(d, :planks)
        box = NG.GeometryBasics.normal_mesh(Rect3f(Vec3f(-0.5), Vec3f(1)))
        # one hidden instance always (the raster cannot draw an empty meshscatter)
        d[:planks] = meshscatter!(game.stage.scene, [HIDE]; marker = box, markersize = [Vec3f(0)],
                                  rotation = [Quaternionf(0, 0, 0, 1)], color = PLANK, name = :builder_planks)
        B[:planks_n] = 0
    end
    w = game.world
    job = B[:job]
    ids = job === nothing || job[:stage] === :done ? Int32[] : get(job, :helpers, Int32[])
    cs = [NG.creature(w, id) for id in ids]
    cs = [c for c in cs if c !== nothing && c.goal.kind === :buildwatch]
    isempty(cs) && B[:planks_n] == 0 && return
    B[:planks_n] = length(cs)
    if isempty(cs)
        Makie.update!(d[:planks]; arg1 = [HIDE], markersize = [Vec3f(0)], rotation = [Quaternionf(0, 0, 0, 1)])
        return
    end
    pts = [c.pos + Point3f(0, 0, 0.95f0 * NG.species_of(c).height + 0.05f0 + 0.03f0 * sin(Float32(8w.t) + c.id)) for c in cs]
    rots = [Makie.qrotation(Vec3f(0, 0, 1), c.yaw + NG.species_of(c).heading) for c in cs]
    Makie.update!(d[:planks]; arg1 = pts, markersize = [Vec3f(0.16, 0.9, 0.05) for _ in cs], rotation = rots)
end

function crate!(game)
    d = B[:plots]
    if !haskey(d, :crate)
        # the generated toy crate (s48; before, a brown box)
        model = NG.load_asset(game.paths, CRATE_ASSET)
        ps = NG.GeometryBasics.coordinates(model.mesh)
        B[:crate_scale] = 0.38f0 / maximum(maximum(p[i] for p in ps) - minimum(p[i] for p in ps) for i in 1:3)
        d[:crate] = NG.asset_instances!(game.stage.scene, model, [HIDE]; markersize = [Vec3f(0)],
                                        rotation = [Quaternionf(0, 0, 0, 1)], name = :builder_crate)
    end
    w = game.world
    job = B[:job]
    c = job === nothing || job[:stage] !== :go || job[:who] == 0 ? nothing : NG.creature(w, job[:who])
    who = c === nothing ? 0 : c.id
    who == 0 && get(B, :crate_who, 0) == 0 && return
    B[:crate_who] = who
    if c === nothing
        Makie.update!(d[:crate]; arg1 = [HIDE], markersize = [Vec3f(0)])
        haskey(d, :carry) && (delete!(game.stage.scene, d[:carry]); delete!(d, :carry))
    else
        sp = NG.species_of(c)
        a, r = c.yaw + sp.heading, NG.body_radius(sp)
        q = Makie.qrotation(Vec3f(0, 0, 1), a + Float32(pi / 2))     # its long side across the arms
        # held in front at belly height like a box in both arms (riding over the leaf it looked like it floated, s56)
        at = c.pos + Point3f((r + 0.1f0) * cos(a), (r + 0.1f0) * sin(a), 0.4f0r + 0.02f0 * sin(Float32(8w.t)))
        Makie.update!(d[:crate]; arg1 = [at], markersize = [Vec3f(B[:crate_scale])], rotation = [q])
        haskey(d, :carry) || carry_copy!(game, job)
        haskey(d, :carry) && Makie.update!(d[:carry]; arg1 = [at + Point3f(0, 0, 0.3f0)], rotation = [q])
    end
end

"""
A small copy of the actual new thing standing on the crate: the first new plot that is a generated asset
(a meshscatter whose marker is a mesh with a texture), at 0.3 m. Other new things ride in the crate.
"""
function carry_copy!(game, job)
    get(job, :no_copy, false) && return
    job[:no_copy] = true
    for (p, _) in job[:plots]
        p isa Makie.MeshScatter || continue
        m = p.marker[]
        col = p.color[]
        (m isa NG.GeometryBasics.Mesh && col isa AbstractMatrix) || continue
        ps = NG.GeometryBasics.coordinates(m)
        k = 0.3f0 / maximum(maximum(v[i] for v in ps) - minimum(v[i] for v in ps) for i in 1:3)
        kw = haskey(p.attributes, :material) ? (; material = p.material[]) : (;)
        B[:plots][:carry] = meshscatter!(game.stage.scene, [HIDE]; marker = m, color = col, markersize = [Vec3f(k)],
                                         rotation = [Quaternionf(0, 0, 0, 1)], name = :builder_carry, kw...)
        return
    end
end

# ── a puff of golden sparkles where the things appear ───────────────────────

const N_SPARK = 16
const PUFF_TIME = 1.4
function puff!(game)
    d = B[:plots]
    if !haskey(d, :puff)
        d[:puff] = meshscatter!(game.stage.scene, fill(HIDE, N_SPARK); marker = NG.shape(:sphere), markersize = 0.0f0,
                                color = RGBf(1.0, 0.85, 0.4), shading = Makie.NoShading,
                                material = NG.Hikari.Emission(color = (1.0, 0.85, 0.4), strength = 2.0), name = :builder_puff)
    end
    pf = get(B, :puff, nothing)
    pf === nothing && return
    at, t0 = pf
    k = Float32((game.world.t - t0) / PUFF_TIME)
    if k >= 1
        Makie.update!(d[:puff]; arg1 = fill(HIDE, N_SPARK), markersize = 0.0f0)
        B[:puff] = nothing
        return
    end
    pts = [at + Point3f((0.4f0 + 1.6f0k) * cos(2pi * i / N_SPARK), (0.4f0 + 1.6f0k) * sin(2pi * i / N_SPARK),
                        0.3f0 + 1.4f0k * (1 + 0.4f0 * sin(3i)) - 0.8f0k^2) for i in 1:N_SPARK]
    Makie.update!(d[:puff]; arg1 = pts, markersize = 0.09f0 * (1 - k))
end

# ── the system ───────────────────────────────────────────────────────────────

struct Builder <: System end

# ── the thought bubble: what Lumi (the agent) is on right now ──────────────
# The todo marked doing in state/todos.json, in a few words, in a cloud over Lumi's head (goal 4, s48).

const THOUGHT_EVERY = 20.0   # s between reads of the todo list
const CREAM = RGBAf(1.0, 0.97, 0.88, 0.96)
const INK = RGBAf(0.2, 0.15, 0.1, 1)

"A todo title in a few words: the part before a colon, dash or bracket, at most six words."
function few_words(title)
    t = strip(first(split(title, r":| — | - |\(|;|,")))
    ws = split(t)
    out = join(ws[1:min(end, 6)], " ")
    length(ws) > 6 && (out *= "…")
    occursin(DEV_WORDS, out) && return "Tinkering in my workshop…"
    return uppercasefirst(out)
end

"What Lumi said it is making, cut to a cloud's worth: up to the first comma or colon, six words (s53: a whole sentence spanned the view)."
function short_thought(text)
    ws = split(strip(first(split(text, r":| — | - |;|,|\."))))
    isempty(ws) && return text
    out = join(ws[1:min(end, 6)], " ")
    length(ws) > 6 && (out *= "…")
    return uppercasefirst(out)
end

# Words a player should never read over Lumi's head (review s48: "Builder mirrors the real work").
const DEV_WORDS = r"(?i)\b(builder|todo|test|tests|fix|bug|plugin|engine|review|raster|gpu|frame|camera|render|ui|panel|suite|flaky|session|verdict|evidence|path trac\w*|memory|method)\b"

"""
What Lumi says it is making (`think!`, the last three hours), else the doing todo's few words,
or nothing (read every THOUGHT_EVERY s). The todo titles are the agent's words and said nothing to a
player ("Builder mirrors the real work", the human 2026-11-23: "it doesn't say what?").
"""
function current_thought(game)
    w = game.world
    w.t < get(B, :thought_read, -Inf) + THOUGHT_EVERY && return get(B, :thought, nothing)
    B[:thought_read] = w.t
    f = NG.thought_file(game.paths)
    if isfile(f)
        t = NG.read_json(f)
        time() - t["unix"] < 3 * 3600 && return (B[:thought] = short_thought(string(t["text"])))
    end
    path = NG.todo_path(game)
    B[:thought] = nothing
    isfile(path) || return nothing
    doing = filter(t -> t.status === :doing, NG.load_todos(path))
    isempty(doing) || (B[:thought] = few_words(last(doing).title))
    return B[:thought]
end

"The cloud (an ellipse and three trailing puffs) and its text in the 2D overlay."
function thought_plots!(game)
    T = get!(B, :thought_plots) do
        ov = game.stage.overlay
        far = [Point2f(-500, -500) for _ in 1:4]
        Dict{Symbol,Any}(
            :cloud => scatter!(ov, far; marker = Circle, markersize = [Vec2f(10) for _ in 1:4], color = CREAM,
                               strokewidth = 2, strokecolor = RGBAf(0.35, 0.28, 0.2, 0.9), name = :thought_cloud),
            :text => text!(ov, Point2f(-500, -500); text = " ", fontsize = 15, font = :italic, color = INK,
                           align = (:center, :center), name = :thought_text))
    end
    return T
end

function thought!(game)
    st = game.stage
    (st === nothing || st.overlay === nothing) && return
    T = thought_plots!(game)
    w = game.world
    me = lumi(w)
    # while Lumi speaks its line stands where the cloud would be: the thought waits (s49, the line covered the cloud)
    speaking = me !== nothing && any(s -> s.who == me.id && s.until > w.t, w.speech)
    pastime = me === nothing || !isdefined(Main, :LUMI_DOING) ? nothing : get(Main.LUMI_DOING, me.goal.kind, nothing)
    # the work ("carrying paint pots...") only over a Lumi at work or between things: over a chat, a meal or a
    # dance it said what Lumi was NOT doing (perfectionist s67: "Conducting the island choir" while it ate)
    working = me !== nothing && me.goal.kind in (:build, :tinker, :wander, :idle)
    txt = me === nothing || me.controlled || game.minigame !== nothing || me.action === :sleep || speaking ? nothing :
          pastime !== nothing ? pastime : working ? current_thought(game) : nothing
    # busy with a pastime of its own (the kite): the cloud says that, not the work (tester s57: "Making a
    # kite…" hung over Lumi while the kite was already up). Plugins fill `Main.LUMI_DOING[kind]`.
    px = txt === nothing ? nothing : NG.on_screen(st.scene, NG.head_point(w, me))
    if px === nothing
        get(B, :thought_shown, false) || return
        Makie.update!(T[:cloud]; arg1 = [Point2f(-500, -500) for _ in 1:4])
        Makie.update!(T[:text]; arg1 = Point2f(-500, -500))
        B[:thought_shown] = false
        return
    end
    wd = 8.2f0 * length(txt) + 34
    vw, top = Makie.widths(Makie.viewport(st.overlay)[])
    # up and to the right, clear of the name tag over the head; kept inside the view (a long thought
    # ran off the right edge, and a head near the top sent the cloud beside it: s51 suite, s52 shots)
    cx(x) = clamp(x, wd / 2 + 8, max(wd / 2 + 8, vw - wd / 2 - 8))
    c = Point2f(cx(px[1] + wd / 2 + 6), px[2] + 104)
    pts = [px + Point2f(8, 14), px + Point2f(18, 36), px + Point2f(30, 62), c]
    if c[2] + 24 > top     # a head near the top: lower, still above the name tag
        c = Point2f(cx(px[1] + wd / 2 + 6), px[2] + 66)
        pts = [px + Point2f(8, 10), px + Point2f(16, 22), px + Point2f(26, 36), c]
    end
    if c[2] + 24 > top     # no room above at all: beside the head
        c = Point2f(cx(px[1] + wd / 2 + 70), px[2] + 10)
        pts = [px + Point2f(30, 14), px + Point2f(44, 12), px + Point2f(58, 11), c]
    end
    sizes = [Vec2f(7), Vec2f(11), Vec2f(15), Vec2f(wd, 40)]
    Makie.update!(T[:cloud]; arg1 = pts, markersize = sizes)
    Makie.update!(T[:text]; arg1 = c, text = txt)
    B[:thought_shown] = true
end

# what the bubble says for Lumi's everyday goals (s68: with the work shown only while Lumi works, the bubble
# says what Lumi really does). A plugin's own line for its goal (kite, paint fight) wins.
const EVERYDAY = Dict(:eat => "Mmm, snack time", :fish => "Come on, little fish...", :beachcomb => "Looking for shiny shells",
    :sunbathe => "Warming my feathers", :tag => "You can't catch me!", :present => "A present for a friend",
    :present_get => "A present for a friend", :conga => "Conga! Conga!", :flight => "Today I FLY!",
    :boing => "BOING!", :boing_walk => "To the Big Boing!", :choir => "Conducting the island choir",
    :pebble => "One more stone for the cairn", :dance => "Dancing!", :circle => "Dancing in the ring!",
    :rain => "Splashing in the rain")

function NG.start!(::Builder, game)
    isdefined(Main, :LUMI_DOING) || Core.eval(Main, :(const LUMI_DOING = Dict{Symbol,String}()))
    for (k, v) in EVERYDAY
        haskey(Main.LUMI_DOING, k) || (Main.LUMI_DOING[k] = v)
    end
    # the plots belong to one scene: another game in this process (the worker's quiet copy for each job) draws its own
    if get(B, :scene, nothing) !== game.stage.scene
        empty!(B[:plots]); delete!(B, :thought_plots)
        B[:scene] = game.stage.scene
    end
    load_spots!(game)
    union!(NG.BUSY_GOALS, BUILD_GOALS)
    B[:seen] = plot_ids(game.stage.scene)
    NG.CAMERA_MOMENTS["builder"] = w -> begin
        j = B[:job]
        j !== nothing && j[:who] != 0 && return j[:who]
        wt = get(B, :watch, (0, 0.0))                    # the finished build stays in view for a few seconds
        w.t < wt[2] && return wt[1]
        me = B[:busy] === nothing ? nothing : lumi(w)  # the first seconds of a tinker at the work spot
        me !== nothing && get(B, :first_round, false) && me.goal.kind === :tinker && me.goal.arrived && w.t < me.goal.until - TINKER + 6 && return me.id
        nothing
    end
end

function NG.published!(::Builder, game, plugins)
    names = [String(n) for n in plugins]
    isempty(names) && return
    plan_jobs!(game, names)
    B[:seen] = plot_ids(game.stage.scene)
end

"Call it in the sandbox to try what the human's game does on a publish (`publish` is refused there)."
try_publish!(game, names) = Base.invokelatest(NG.published!, only(game.plugins["builder"].systems), game, names)

function NG.step!(::Builder, game, dt)
    if B[:job] === nothing && !isempty(B[:jobs])
        B[:job] = popfirst!(B[:jobs])
        B[:job][:since] = game.world.t
    end
    if B[:job] !== nothing && step_job!(game, B[:job])
        B[:job] = nothing
    end
    B[:job] === nothing && isempty(B[:jobs]) && live_game(game) && tinker!(game)
    crate!(game)
    planks!(game)
    thought!(game)
    NG.path_traced(game) || puff!(game)     # moving glow plots leak area lights in path tracing (AGENTS.md)
    length(game.stage.scene.plots) == length(B[:seen]) || (B[:seen] = plot_ids(game.stage.scene))
end

function NG.stop!(::Builder, game)
    delete!(NG.CAMERA_MOMENTS, "builder")
    B[:job] === nothing || reveal!(game, B[:job])
    foreach(j -> reveal!(game, j), B[:jobs])
    empty!(B[:jobs]); B[:job] = nothing
    for p in values(B[:plots])
        delete!(game.stage.scene, p)
    end
    empty!(B[:plots])
    T = pop!(B, :thought_plots, nothing)
    T === nothing || foreach(p -> delete!(p.parent, p), values(T))
    B[:thought_read] = -Inf; B[:thought_shown] = false
    setdiff!(NG.BUSY_GOALS, BUILD_GOALS)
end

register!(Builder())
