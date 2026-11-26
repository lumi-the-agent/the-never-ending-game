# The island on TV (session 112): a big old television stands on the meadow, and what it shows is the island itself.
# In a film (a quiet copy rendering frames) its screen shows the frame before, so when the camera looks at the
# television the screen shows the television showing the television, a tunnel of islands going down for ever.
# In the human's game it shows the last frame the island was filmed in (state/tv.png, written by the films), and
# friends wander over now and then, sit in front of it and point at themselves.
isdefined(Main, :TV) || Core.eval(Main, :(const TV = Dict{Symbol,Any}()))
const NG = NeverendingGame
const T = Main.TV

const SPOT = Point2f(18.0, -1.5)
const YAW = Float32(-pi / 2)          # the screen faces -y (the meadow towards the south shore)
const SW, SH = 1.55f0, 0.87f0         # screen size (16:9)
const LEGS = 0.35f0
const CAB = Vec3f(0.8, 2.3, 1.3)      # depth, width, height
const SCREEN_DY = -0.3f0              # the screen sits left of the knobs (seen from the front)
const LINES = ("That's ME on there!", "Why is there a telly in the telly?", "Wave! WAVE!", "It never ends...",
               "I look taller on TV.", "Move, I can't see me!")
const EVERY = (150.0, 300.0)          # s between invitations to watch
const WATCH = 70.0                    # s a friend watches

struct Telly <: System end

rot(p, yaw) = Point3f(p[1] * cos(yaw) - p[2] * sin(yaw), p[1] * sin(yaw) + p[2] * cos(yaw), p[3])
base(w) = NG.ground(w.island, (SPOT[1], SPOT[2]))
at(w, x, y, z) = base(w) + rot(Point3f(x, y, z), YAW)
seat(w, k) = (p = at(w, 3.2f0, -1.1f0 + 1.1f0 * k, 0f0); NG.ground(w.island, (p[1], p[2])))

"A box (size s along the TV's depth, width, height) centred at c, turned with the TV (flat normals)."
function box_mesh(c, s)
    h = Vec3f(s[1] / 2, s[2] / 2, s[3] / 2)
    pts = Point3f[]; ns = Vec3f[]; fs = GeometryBasics.GLTriangleFace[]
    X = Vec3f(1, 0, 0); Y = Vec3f(0, 1, 0); Z = Vec3f(0, 0, 1)
    for (n, u, v) in ((X, Y, Z), (-X, Z, Y), (Y, Z, X), (-Y, X, Z), (Z, X, Y), (-Z, Y, X))
        b = length(pts)
        for (a, bb) in ((-1f0, -1f0), (1f0, -1f0), (1f0, 1f0), (-1f0, 1f0))
            q = n .* h .+ a .* (u .* h) .+ bb .* (v .* h)
            push!(pts, c + rot(Point3f(q...), YAW)); push!(ns, Vec3f(rot(Point3f(n...), YAW)...))
        end
        push!(fs, GeometryBasics.GLTriangleFace(b + 1, b + 2, b + 3), GeometryBasics.GLTriangleFace(b + 1, b + 3, b + 4))
    end
    return GeometryBasics.Mesh(pts, fs; normal = ns)
end

function merged(ms)
    pts = Point3f[]; ns = Vec3f[]; fs = GeometryBasics.GLTriangleFace[]
    for m in ms
        o = length(pts)
        append!(pts, GeometryBasics.coordinates(m)); append!(ns, m.normal)
        append!(fs, [GeometryBasics.GLTriangleFace((GeometryBasics.value.(f) .+ o)...) for f in GeometryBasics.faces(m)])
    end
    return GeometryBasics.Mesh(pts, fs; normal = ns)
end

"The screen: a quad on the cabinet's front, the picture the right way round from the front."
function screen_mesh(w)
    c = at(w, CAB[1] / 2 + 0.03f0, SCREEN_DY, LEGS + CAB[3] / 2 + 0.02f0)
    corner(u, v) = c + rot(Point3f(0, (u - 0.5f0) * SW, (v - 0.5f0) * SH), YAW)
    pts = Point3f[corner(1 - u, v) for (u, v) in ((0f0, 0f0), (1f0, 0f0), (1f0, 1f0), (0f0, 1f0))]
    uv = Vec2f[(1, 0), (0, 0), (0, 1), (1, 1)]
    n = Vec3f(rot(Point3f(1, 0, 0), YAW)...)
    return GeometryBasics.Mesh(pts, GeometryBasics.GLTriangleFace[(1, 2, 3), (1, 3, 4)]; normal = fill(n, 4), uv = uv)
end

"A picture made small for the screen (every plot goes to every browser): at most 240 px wide."
function small(img)
    h, wd = size(img)
    st = max(1, wd ÷ 240)
    return map(c -> RGBf(Makie.red(c), Makie.green(c), Makie.blue(c)), img[1:st:end, 1:st:end])
end

snow(rng) = [RGBf(v, v, v * 1.05f0) for v in 0.25f0 .+ 0.6f0 .* rand(rng, Float32, 54, 96)]

function build!(game)
    sc = game.stage.scene
    w = game.world
    for p in filter(p -> haskey(p.attributes, :name) && startswith(string(p.attributes[:name][]), "tv_"), copy(sc.plots))
        delete!(sc, p)
    end
    zc = LEGS + CAB[3] / 2
    cab = box_mesh(at(w, 0f0, 0f0, zc), CAB)
    legs = [box_mesh(at(w, sx * (CAB[1] / 2 - 0.1f0), sy * (CAB[2] / 2 - 0.15f0), LEGS / 2), Vec3f(0.09, 0.09, LEGS))
            for sx in (-1f0, 1f0), sy in (-1f0, 1f0)]
    # traced: lacquered wood (a clear coat that catches the sky), brass knobs, aluminium ears
    # (s114, review #545: matte everywhere before)
    T[:wood] = mesh!(sc, merged(vcat([cab], vec(legs))); color = RGBf(0.50, 0.30, 0.16), name = :tv_wood,
                     material = NG.Hikari.CoatedDiffuse(reflectance = (0.40, 0.21, 0.09), roughness = 0.04))
    bezel = box_mesh(at(w, CAB[1] / 2 + 0.005f0, SCREEN_DY, zc + 0.02f0), Vec3f(0.02, SW + 0.14f0, SH + 0.14f0))
    panel = box_mesh(at(w, CAB[1] / 2 + 0.005f0, 0.85f0, zc), Vec3f(0.02, 0.42, CAB[3] - 0.2f0))
    T[:bezel] = mesh!(sc, merged([bezel, panel]); color = RGBf(0.16, 0.15, 0.14), name = :tv_bezel,
                      material = NG.Hikari.CoatedDiffuse(reflectance = (0.05, 0.045, 0.04), roughness = 0.15))
    knobs = [at(w, CAB[1] / 2 + 0.04f0, 0.85f0, zc + dz) for dz in (0.3f0, 0f0)]
    T[:knobs] = meshscatter!(sc, knobs; marker = Sphere(Point3f(0), 1f0), markersize = 0.08f0, color = RGBf(0.85, 0.7, 0.35),
                             material = NG.Hikari.Brass(roughness = 0.12), name = :tv_knobs)
    # two rabbit-ear antennae from the top
    top = at(w, 0f0, 0.2f0, LEGS + CAB[3])
    T[:ears] = meshscatter!(sc, [top, top]; marker = GeometryBasics.Cylinder(Point3f(0), Point3f(0, 0, 1), 1f0),
                            markersize = Vec3f(0.025, 0.025, 1.1), color = RGBf(0.7, 0.7, 0.72), material = NG.Hikari.Aluminum(roughness = 0.08),
                            rotation = [Makie.qrotation(Vec3f(rot(Point3f(1, 0, 0), YAW)...), a) for a in (0.5f0, -0.5f0)],
                            name = :tv_ears)
    # live the screen glows (its picture at full colour in shade and at night); traced copies keep a lit surface
    # (a moving textured Emission would pile up area lights: the OOM lesson)
    T[:screen] = game.dash === nothing ? mesh!(sc, screen_mesh(w); color = snow(w.rng), name = :tv_screen) :
                 mesh!(sc, screen_mesh(w); color = snow(w.rng), shading = Makie.NoShading, name = :tv_screen)
    # (no glass pane in front of the picture: tried s114, a Glass box blocks the sun's direct light to the
    # screen, so traced the picture came out dark and full of speckles; a coat on the screen itself is next)
    T[:shown] = :snow
    T[:built] = true
end

"What the screen shows now: in a film the frame before; in the game the last frame the island was filmed in."
function picture!(game)
    w = game.world
    if game.dash === nothing
        f = NG.LAST_FRAME[]
        if f === nothing
            # before the first frame: the last broadcast, so every new picture holds the one before it
            last = joinpath(game.paths.state, "tv.png")
            get(T, :frame, 0) === :last || (T[:screen].color = isfile(last) ? small(Makie.FileIO.load(last)) : snow(w.rng))
            T[:frame] = :last
        elseif f !== get(T, :frame, nothing)
            T[:frame] = f
            T[:screen].color = small(f)
        end
        return
    end
    w.t - get(T, :looked, -Inf) > 10 || return
    T[:looked] = w.t
    f = joinpath(game.paths.state, "tv.png")
    isfile(f) || return
    m = mtime(f)
    m == get(T, :mtime, 0.0) && return
    T[:mtime] = m
    T[:screen].color = small(Makie.FileIO.load(f))
    T[:shown] = :picture
end

const CAST_EVERY = 1200.0             # s between broadcasts in the human's game
const BORED_LINES = ("It's just us. Again.", "Nothing on but the island.", "Change the channel. Oh wait.",
                     "I've seen this one.", "Ooh, a TV in the TV. Again.")
party_free(w) = !isdefined(Main, :LUMI_PARTY) || w.t >= get(Main.LUMI_PARTY, :until, -Inf)
claim_party!(w, secs) = isdefined(Main, :LUMI_PARTY) && (Main.LUMI_PARTY[:until] = max(get(Main.LUMI_PARTY, :until, -Inf), w.t + secs))

"When I am bored I slump in front of the television for a minute, and it shows us. Again."
function bored_telly!(game)
    w = game.world
    w.t >= get(T, :bored_at, w.t + 1) || (haskey(T, :bored_at) || (T[:bored_at] = w.t + 60); return)
    T[:bored_at] = w.t + 20
    feeling = isdefined(Main, :LUMI_FEELING) ? string(Main.LUMI_FEELING[]) : "content"
    (feeling == "bored" || get(T, :force_bored, false)) || return
    i = findfirst(c -> c.species == "Lumi", w.creatures)
    i === nothing && return
    me = w.creatures[i]
    ok = !me.controlled && me.action !== :sleep && game.minigame === nothing && party_free(w) && T[:screen].visible[] &&
         (!(me.goal.kind in NG.BUSY_GOALS) || me.goal.kind in (:fish, :pebble, :feel, :gallery, :cloudwatch))
    (ok || get(T, :force_bored, false)) || return
    T[:force_bored] = false
    T[:bored_at] = w.t + 360 + 240 * rand(w.rng)
    claim_party!(w, WATCH + 20)
    me.goal = NG.Goal(:tvwatch, seat(w, 1), :sit, WATCH, w.t + WATCH + 40, false, 0, false)
    NG.emit!(w, :tv_bored)
end

"""
Now and then the human's game asks the worker for a new picture of the island from the camera the human is looking
through (movies/tv.jl `tv_still`), when no other job waits: the television then shows what you saw a minute ago.
"""
function broadcast!(game)
    game.paths.instance === :live || return
    w = game.world
    haskey(T, :next_cast) || (T[:next_cast] = w.t + 120)
    w.t >= T[:next_cast] || return
    T[:next_cast] = w.t + CAST_EVERY
    dir = joinpath(game.paths.world, "jobs")
    recent = sort(filter(f -> endswith(f, ".json"), readdir(dir)))
    for f in recent[max(1, end - 15):end]
        occursin(r"\"status\": \"(queued|running)\"", read(joinpath(dir, f), String)) && return    # the worker is busy
    end
    e = game.rig.eye; tg = game.rig.target
    NG.submit_job(:clip; path = joinpath(game.paths.state, "tv-cast.mp4"), script = "movies/tv.jl", call = "tv_still",
                  kwargs = Dict("eye" => Float64[e[1], e[2], e[3]], "target" => Float64[tg[1], tg[2], tg[3]]))
    NG.emit!(w, :tv_broadcast)
end

function NG.step!(::Telly, game, dt)
    game.stage === nothing && return
    (get(T, :built, false) && haskey(T, :screen) && T[:screen].parent !== nothing) || build!(game)
    picture!(game)
    game.dash === nothing && return
    broadcast!(game)
    bored_telly!(game)
    w = game.world
    # now and then a few friends come over to watch
    if w.t >= get(T, :next, w.t + 1) && game.minigame === nothing && T[:screen].visible[]   # (hidden while it is being built)
        T[:next] = w.t + EVERY[1] + (EVERY[2] - EVERY[1]) * rand(w.rng)
        free = [c for c in w.creatures if !c.controlled && c.species != "Lumi" && c.action !== :sleep &&
                (!(c.goal.kind in NG.BUSY_GOALS) || c.goal.kind in (:fish, :pebble, :gallery, :cloudwatch, :feel)) &&
                c.goal.kind !== :follow]
        sort!(free; by = c -> hypot(c.pos[1] - SPOT[1], c.pos[2] - SPOT[2]))
        for (k, c) in enumerate(free[1:min(3, end)])
            c.goal = NG.Goal(:tvwatch, seat(w, k - 1), :sit, WATCH, w.t + WATCH + 40, false, 0, false)
        end
        isempty(free) || NG.emit!(w, :tv_watch; who = join([c.name for c in free[1:min(3, end)]], ", "))
    end
    haskey(T, :next) || (T[:next] = w.t + 30)
    for c in w.creatures
        c.goal.kind === :tvwatch && c.goal.arrived || continue
        want = Float32(atan(SPOT[2] - c.pos[2], SPOT[1] - c.pos[1])) - NG.species_of(c).heading
        c.yaw = c.yaw + NG.wrap_angle(want - c.yaw) * 0.1f0
        lines = c.species == "Lumi" ? BORED_LINES : LINES
        rand(w.rng) < dt / 12 && NG.say!(w, c, lines[rand(w.rng, 1:length(lines))]; duration = 3.0)
    end
    return nothing
end

function NG.start!(::Telly, game)
    isdefined(Main, :LUMI_DOING) && (Main.LUMI_DOING[:tvwatch] = "Watching TV. It's us. Again.")
    push!(NG.BUSY_GOALS, :tvwatch)      # a feeling, a chat or a boop doesn't pull a watcher off the seat
    T[:built] = false; delete!(T, :next); delete!(T, :frame); T[:mtime] = 0.0; T[:looked] = -Inf
    return nothing
end

function NG.stop!(::Telly, game)
    sc = game.stage === nothing ? nothing : game.stage.scene
    sc === nothing || foreach(p -> delete!(sc, p), filter(p -> haskey(p.attributes, :name) && startswith(string(p.attributes[:name][]), "tv_"), copy(sc.plots)))
    T[:built] = false
end

register!(Telly())
