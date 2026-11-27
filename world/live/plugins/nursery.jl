# Breeding a new friend (session 113): in a little pen on the meadow I breed a creature that never existed. Each
# generation is four little ones with mixed-up parts taken from my friends' bodies (a pig's body on crab claws, a
# jelly on sheep legs...). My friends come by the pen now and then and hug the little ones they like: each friend
# likes the parts of its own kind a bit more, and has a taste of its own. When the generation is over, only the two
# most hugged have the next four, their parts mixed and now and then one changed. Over days the island's own taste
# shapes a new kind, and when one little one is hugged by four different friends, it is let out onto the meadow.
isdefined(Main, :NURSERY) || Core.eval(Main, :(const NURSERY = Dict{Symbol,Any}()))
const NG = NeverendingGame
const N = Main.NURSERY

const PEN = Point2f(12.5, -7.0)
const PEN_R = 2.0f0
const KINDS = ("Snootle", "Crabbit", "Blorbo", "Fluffkin")
const NB = 4                       # little ones in the pen
const GEN_SECS = 420.0             # a generation lasts this long (live)
const VISIT_EVERY = (40.0, 90.0)   # s between friends' visits
const HIDDEN = Point3f(0, 0, -60)
const AWW = ("Aww!", "This one!", "Come here, you.", "So squishy!", "I'll take this one.", "Hello, tiny.")
const ICK = ("Hmm. Not that one.", "Why does it have claws?", "Too many legs.")

struct Nursery <: System end

state_file(game) = joinpath(game.paths.state, "nursery.json")
legs_of(sp) = [p.name for p in NG.SPECIES[sp].parts if startswith(string(p.name), "leg") || startswith(string(p.name), "foot")]
extras_of(sp) = [p.name for p in NG.SPECIES[sp].parts if !(p.name === :body) && !(p.name in legs_of(sp))]

"A little one's genes: whose body, whose legs, whose extras (claws, tail), how big."
new_genes(rng) = Dict{String,Any}("body" => rand(rng, KINDS), "legs" => rand(rng, KINDS), "extra" => rand(rng, KINDS),
                                  "size" => 0.42 + 0.14 * rand(rng))

function child(rng, a, b)
    g = Dict{String,Any}()
    for k in ("body", "legs", "extra")
        g[k] = rand(rng) < 0.5 ? a[k] : b[k]
        rand(rng) < 0.15 && (g[k] = rand(rng, KINDS))            # now and then a part changes
    end
    g["size"] = clamp((a["size"] + b["size"]) / 2 + 0.06 * (rand(rng) - 0.5), 0.36, 0.62)
    return g
end

name_of(g) = string(g["body"][1:3], "-", g["legs"][1:2], g["extra"][1:2])
describe(g) = "$(g["body"]) body, $(g["legs"]) legs, $(g["extra"]) bits"

function fresh_generation!(game; parents = nothing)
    w = game.world
    gen = get(N, :gen, 0) + 1
    N[:gen] = gen
    babies = Any[]
    for k in 1:NB
        g = parents === nothing ? new_genes(w.rng) : child(w.rng, parents[1], parents[2])
        a = 2pi * (k - 0.5) / NB
        push!(babies, Dict{String,Any}("genes" => g, "hugs" => 0, "huggers" => String[],
                                       "pos" => [PEN[1] + 0.9 * cos(a), PEN[2] + 0.9 * sin(a)], "yaw" => rand(w.rng) * 2pi))
    end
    N[:babies] = babies
    N[:gen_t0] = w.t
    N[:visited] = Set{String}()
    NG.emit!(w, :nursery_generation; gen, kinds = join([name_of(b["genes"]) for b in babies], " "))
    save!(game)
end

function save!(game)
    game.dash === nothing && return                  # quiet copies (films) keep nothing
    d = Dict("gen" => N[:gen], "babies" => N[:babies], "released" => get(N, :released, Any[]), "history" => get(N, :history, Any[]))
    open(io -> NG.JSON.print(io, d, 1), state_file(game), "w")
end

function load!(game)
    f = state_file(game)
    if game.dash !== nothing && isfile(f)
        d = NG.JSON.parsefile(f)
        N[:gen] = d["gen"]; N[:babies] = d["babies"]; N[:released] = d["released"]; N[:history] = d["history"]
        N[:gen_t0] = game.world.t
    else
        N[:gen] = 0; N[:released] = Any[]; N[:history] = Any[]
        fresh_generation!(game)
    end
end

# ---- drawing: one instanced plot per part of every friend kind; a little one shows only the parts its genes pick

function build!(game)
    sc = game.stage.scene
    for p in filter(p -> haskey(p.attributes, :name) && startswith(string(p.attributes[:name][]), "nursery_"), copy(sc.plots))
        delete!(sc, p)
    end
    plots = Dict{Tuple{String,Symbol},Any}()
    n = 2 * (NB + 4)                 # two slots per little one: a mirrored part has a left and a right copy
    for kind in KINDS, part in NG.SPECIES[kind].parts
        uv = NG.paints(part.motion) ? (; uv_transform = fill(Makie.Mat{2,3,Float32}(1, 0, 0, 1, 0, 0), n)) : (;)
        plots[(kind, part.name)] = meshscatter!(sc, fill(HIDDEN, n); marker = NG.shape(part.shape), material = part.material,
                                                markersize = fill(Vec3f(0), n), rotation = fill(Makie.Quaternionf(0, 0, 0, 1), n),
                                                uv..., part.attributes..., name = Symbol(:nursery_, kind, :_, part.name))
    end
    N[:plots] = plots
    # the pen: a ring of posts with two rails
    g0 = NG.ground(game.world.island, (PEN[1], PEN[2]))
    posts = Point3f[]; rails = Point3f[]; rs = Vec3f[]; rr = Makie.Quaternionf[]
    m = 14
    for k in 0:m-1
        a = 2pi * k / m; b = 2pi * (k + 1) / m
        p = NG.ground(game.world.island, (Float32(PEN[1] + PEN_R * cos(a)), Float32(PEN[2] + PEN_R * sin(a))))
        q = NG.ground(game.world.island, (Float32(PEN[1] + PEN_R * cos(b)), Float32(PEN[2] + PEN_R * sin(b))))
        push!(posts, p)
        d = q - p; L = hypot(d[1], d[2], d[3])
        for h in (0.25f0, 0.5f0)
            push!(rails, p + Point3f(0, 0, h)); push!(rs, Vec3f(0.035, 0.035, L))
            push!(rr, Makie.rotation_between(Vec3f(0, 0, 1), Vec3f(d / L)))
        end
    end
    N[:posts] = meshscatter!(sc, posts; marker = GeometryBasics.Cylinder(Point3f(0), Point3f(0, 0, 1), 1f0),
                             markersize = Vec3f(0.05, 0.05, 0.62), color = RGBf(0.62, 0.43, 0.25), name = :nursery_posts)
    N[:rails] = meshscatter!(sc, rails; marker = GeometryBasics.Cylinder(Point3f(0), Point3f(0, 0, 1), 1f0),
                             markersize = rs, rotation = rr, color = RGBf(0.70, 0.50, 0.30), name = :nursery_rails)
    N[:hearts] = meshscatter!(sc, fill(HIDDEN, NB); marker = Sphere(Point3f(0), 1f0), markersize = fill(Vec3f(0), NB),
                              color = RGBf(1.0, 0.35, 0.5), shading = Makie.NoShading, name = :nursery_hearts)
    N[:built] = true
end

"Every little one (and the released ones) posed with the parts its genes pick."
function draw!(game)
    w = game.world
    plots = N[:plots]
    n = 2 * (NB + 4)
    acc = Dict(k => (fill(HIDDEN, n), fill(Makie.Quaternionf(0, 0, 0, 1), n), fill(Vec3f(0), n),
                     fill(Makie.Mat{2,3,Float32}(1, 0, 0, 1, 0, 0), n)) for k in keys(plots))
    items = Any[]
    for b in N[:babies]; push!(items, b); end
    for r in get(N, :released, Any[])[max(1, end - 3):end]; push!(items, r); end
    for (i, b) in enumerate(items)
        2i > n && break
        g = b["genes"]; s = Float32(g["size"])
        p = NG.ground(w.island, (Float32(b["pos"][1]), Float32(b["pos"][2])))
        moving = get(b, "moving", false)
        for kind in unique([g["body"], g["legs"], g["extra"]])
            sp = NG.SPECIES[kind]
            out = [(Point3f[], Makie.Quaternionf[], Vec3f[], Makie.Mat{2,3,Float32}[]) for _ in sp.parts]
            NG.pose_parts!(out, sp, p, Float32(b["yaw"]) - sp.heading, moving ? :walk : :idle, Float32(w.t * 6 + i), 0.8f0, 0f0,
                           Float32(i), NG.anim_time(w))
            for (j, part) in enumerate(sp.parts)
                want = part.name === :body ? g["body"] == kind :
                       part.name in legs_of(kind) ? g["legs"] == kind : g["extra"] == kind
                want || continue
                o = out[j]
                isempty(o[1]) && continue
                a = acc[(kind, part.name)]
                for m in 1:min(2, length(o[1]))
                    slot = 2i - 2 + m
                    a[1][slot] = p + s * (o[1][m] - p); a[2][slot] = o[2][m]; a[3][slot] = s * o[3][m]
                    length(o[4]) >= m && (a[4][slot] = o[4][m])
                end
            end
        end
    end
    for (k, pl) in plots
        a = acc[k]
        part = NG.SPECIES[k[1]].parts[findfirst(p -> p.name === k[2], NG.SPECIES[k[1]].parts)]
        if NG.paints(part.motion)
            Makie.update!(pl; arg1 = a[1], rotation = a[2], markersize = a[3], uv_transform = a[4])
        else
            Makie.update!(pl; arg1 = a[1], rotation = a[2], markersize = a[3])
        end
    end
    # little hearts over the hugged ones for a moment
    hp = fill(HIDDEN, NB); hs = fill(Vec3f(0), NB)
    for (i, b) in enumerate(N[:babies])
        el = w.t - get(b, "hugged_at", -Inf)
        el < 2.5 || continue
        p = NG.ground(w.island, (Float32(b["pos"][1]), Float32(b["pos"][2])))
        hp[i] = p + Point3f(0, 0, 0.8 + 0.35 * el); hs[i] = Vec3f(0.14f0 * (1 - el / 3))
    end
    Makie.update!(N[:hearts]; arg1 = hp, markersize = hs)
end

# ---- the little ones toddle about inside the pen

function toddle!(w, dt)
    for b in N[:babies]
        t = get(b, "next_turn", 0.0)
        if w.t >= t
            b["next_turn"] = w.t + 1.5 + 3 * rand(w.rng)
            b["moving"] = rand(w.rng) < 0.6
            b["yaw"] = Float64(b["yaw"]) + (rand(w.rng) - 0.5) * 2.5
        end
        get(b, "moving", false) || continue
        x = b["pos"][1] + cos(b["yaw"]) * 0.35 * dt; y = b["pos"][2] + sin(b["yaw"]) * 0.35 * dt
        if hypot(x - PEN[1], y - PEN[2]) > PEN_R - 0.45
            b["yaw"] = atan(PEN[2] - b["pos"][2], PEN[1] - b["pos"][1])      # turn back from the fence
        else
            b["pos"] = [x, y]
        end
    end
    for r in get(N, :released, Any[])           # the released ones wander the meadow round the pen
        t = get(r, "next_turn", 0.0)
        if w.t >= t
            r["next_turn"] = w.t + 2 + 4 * rand(w.rng); r["moving"] = rand(w.rng) < 0.7
            r["yaw"] = Float64(r["yaw"]) + (rand(w.rng) - 0.5) * 2.0
        end
        get(r, "moving", false) || continue
        x = r["pos"][1] + cos(r["yaw"]) * 0.5 * dt; y = r["pos"][2] + sin(r["yaw"]) * 0.5 * dt
        d = hypot(x - PEN[1], y - PEN[2])
        if d < PEN_R + 0.5 || d > 9 || !NG.on_land(w.island, Float32(x), Float32(y); margin = 0.3)
            r["yaw"] = Float64(r["yaw"]) + pi
        else
            r["pos"] = [x, y]
        end
    end
end

# ---- friends visit and hug

"How much `c` likes a little one: parts of its own kind, plus a taste of its own (fixed per friend and part kind)."
function liking(c, g)
    own = (g["body"] == c.species) + (g["legs"] == c.species) + (g["extra"] == c.species)
    taste(k) = mod(hash((c.name, k)) % 1000, 1000) / 1000
    return 0.9 * own + taste(g["body"]) + 0.6 * taste(g["legs"]) + 0.6 * taste(g["extra"]) + 0.3 * g["size"]
end

function visits!(game)
    w = game.world
    film = get(N, :film, false)
    haskey(N, :next_visit) || (N[:next_visit] = w.t + (film ? 1.0 : 30.0))
    # a visitor at the fence picks its favourite and hugs it
    for c in w.creatures
        c.goal.kind === :nursery || continue
        d = hypot(c.pos[1] - PEN[1], c.pos[2] - PEN[2])
        if d < PEN_R + 1.0 && !get(get(N, :hugged_by, Dict{Int32,Bool}()), c.id, true)
            babies = N[:babies]
            best = argmax(b -> liking(c, b["genes"]), babies)
            best["hugs"] += 1; best["hugged_at"] = w.t
            c.name in best["huggers"] || push!(best["huggers"], c.name)
            N[:hugged_by][c.id] = true
            want = Float32(atan(best["pos"][2] - c.pos[2], best["pos"][1] - c.pos[1])) - NG.species_of(c).heading
            c.yaw = c.yaw + NG.wrap_angle(want - c.yaw) * 0.5f0
            NG.say!(w, c, rand(w.rng) < 0.85 ? rand(w.rng, AWW) : rand(w.rng, ICK); duration = 3.0)
            isdefined(Main, :EMOTES) && Base.invokelatest(Main.EMOTES[:emote], c.id, :heart)
            NG.emit!(w, :nursery_hug; who = c.name, baby = name_of(best["genes"]), gen = N[:gen])
            c.goal = NG.Goal(:nursery, c.pos, :idle, 4.0, w.t + 4, true, 0, false)
            save!(game)
        end
    end
    w.t >= N[:next_visit] || return
    N[:next_visit] = w.t + (film ? 2.2 : VISIT_EVERY[1] + (VISIT_EVERY[2] - VISIT_EVERY[1]) * rand(w.rng))
    free = [c for c in w.creatures if !c.controlled && c.species in KINDS && c.action !== :sleep && c.goal.kind !== :nursery &&
            (!(c.goal.kind in NG.BUSY_GOALS) || c.goal.kind in (:fish, :pebble, :feel, :gallery, :cloudwatch)) && c.goal.kind !== :follow]
    isempty(free) && (N[:next_visit] = w.t + 10; return)
    # someone who has not been this generation, one of the nearest few (the nearest alone was the same sheep every time)
    seen = get!(N, :visited, Set{String}())
    fresh = filter(c -> !(c.name in seen), free)
    pool = isempty(fresh) ? free : fresh
    sort!(pool; by = c -> hypot(c.pos[1] - PEN[1], c.pos[2] - PEN[2]))
    c = pool[rand(w.rng, 1:min(3, length(pool)))]
    push!(seen, c.name)
    a = atan(c.pos[2] - PEN[2], c.pos[1] - PEN[1])
    spot = NG.ground(w.island, (Float32(PEN[1] + (PEN_R + 0.6) * cos(a)), Float32(PEN[2] + (PEN_R + 0.6) * sin(a))))
    get!(N, :hugged_by, Dict{Int32,Bool}())[c.id] = false
    c.goal = NG.Goal(:nursery, spot, :idle, 30.0, w.t + 40, false, 0, false)
    NG.emit!(w, :nursery_visit; who = c.name)
end

"End of a generation: the two most hugged have the next four; one hugged by four friends goes free."
function next_generation!(game)
    w = game.world
    babies = N[:babies]
    order = sort(babies; by = b -> -b["hugs"])
    push!(N[:history], Dict("gen" => N[:gen], "kids" => [Dict("genes" => b["genes"], "hugs" => b["hugs"]) for b in babies]))
    star = order[1]
    if length(star["huggers"]) >= 4 || get(N, :force_release, false)
        N[:force_release] = false
        r = Dict{String,Any}("genes" => star["genes"], "pos" => [PEN[1] + PEN_R + 1.2, PEN[2]], "yaw" => 0.0, "gen" => N[:gen])
        push!(N[:released], r)
        NG.emit!(w, :nursery_released; baby = name_of(star["genes"]), gen = N[:gen], huggers = join(star["huggers"], ", "))
    end
    me = findfirst(c -> c.species == "Lumi", w.creatures)
    me === nothing || w.creatures[me].action === :sleep ||
        NG.say!(w, w.creatures[me], "Generation $(N[:gen] + 1)! Look at their $(lowercase(order[1]["genes"]["extra"] == "Crabbit" ? "claws" : "faces"))!"; duration = 3.5)
    fresh_generation!(game; parents = (order[1]["genes"], order[2]["genes"]))
end

function NG.step!(::Nursery, game, dt)
    game.stage === nothing && return
    (get(N, :built, false) && haskey(N, :posts) && N[:posts].parent !== nothing) || build!(game)
    haskey(N, :babies) || load!(game)
    w = game.world
    toddle!(w, dt)
    visits!(game)
    gen_len = get(N, :film, false) ? get(N, :film_gen, 9.0) : GEN_SECS
    w.t - N[:gen_t0] > gen_len && next_generation!(game)
    # 17 part plots go to every browser on each change: draw the little ones 12 times a second, films every frame
    if get(N, :film, false) || w.t - get(N, :drawn, -Inf) >= 1 / 12
        N[:drawn] = w.t
        draw!(game)
    end
    return nothing
end

function NG.start!(::Nursery, game)
    N[:built] = false; delete!(N, :babies); delete!(N, :next_visit); N[:hugged_by] = Dict{Int32,Bool}(); N[:drawn] = -Inf
    get!(N, :film, false)
    push!(NG.BUSY_GOALS, :nursery)
    isdefined(Main, :LUMI_DOING) && (Main.LUMI_DOING[:nursery] = "Visiting the little ones")
    return nothing
end

function NG.stop!(::Nursery, game)
    sc = game.stage === nothing ? nothing : game.stage.scene
    sc === nothing || foreach(p -> delete!(sc, p), filter(p -> haskey(p.attributes, :name) && startswith(string(p.attributes[:name][]), "nursery_"), copy(sc.plots)))
    for c in game.world.creatures
        c.goal.kind === :nursery && (c.goal = NG.Goal(:idle, c.pos, :idle, 1.0, game.world.t + 1, true, 0, false))
    end
    N[:built] = false
end

register!(Nursery())
