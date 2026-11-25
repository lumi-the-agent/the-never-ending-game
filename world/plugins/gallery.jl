# The gallery (session 94, goal 8): the island keeps its own past. Six of my path traced pictures (the ones on my
# pages: the lantern evening, the bolt that got my crest, the big sneeze, the statues, the hail, the Big Boing) stand
# framed on easels in an arc on the meadow, and the friends wander over now and then to look at themselves, think
# about it and say what they remember. In a traced picture of the gallery the pictures are pictures a path tracer
# made of this same island.
isdefined(Main, :GALLERY) || Core.eval(Main, :(const GALLERY = Dict{Symbol,Any}()))
const NG = NeverendingGame
const GA = Main.GALLERY

const PICS = ["lanterns", "thunderstorm-zap", "big-sneeze", "freeze", "hail-umbrella", "big-boing"]   # (the first hanging)
const GENERIC = ("Ooh, that's us!", "When was that?", "I look good in this one.")

"What hangs now: the six newest pictures on my pages (a new one goes up when I post it), the first hanging until then."
function hanging(game)
    get!(GA, :pics) do
        dir = joinpath(game.paths.world, "site", "img")
        fs = isdir(dir) ? filter(f -> endswith(f, ".png") && !startswith(f, "gallery"), readdir(dir)) : String[]
        sort!(fs; by = f -> mtime(joinpath(dir, f)), rev = true)
        length(fs) >= 6 ? [splitext(f)[1] for f in fs[1:6]] : copy(PICS)
    end::Vector{String}
end
const SAYS = Dict(
    "lanterns" => ("Our lantern evening!", "I wished for more berries that night."),
    "thunderstorm-zap" => ("Ha! Lumi's crest went POOF.", "I still can't look at that one."),
    "big-sneeze" => ("That sneeze! My ears!", "Bless you, Lumi."),
    "freeze" => ("I was a statue for AGES.", "Don't move! ...oh. It's a picture."),
    "hail-umbrella" => ("EVERYONE UNDER HERE!", "I still have a bump from that hail."),
    "big-boing" => ("Boing time!", "I went SO high."))
const W = 1.15f0                     # picture width (m); the height follows the picture's shape (16:9)
const GALLERY_VERSION = 3
const EASEL = "20261125-164036-200-asset"   # a generated wooden easel (1 m tall mesh, ledge at 0.36 of it, front along mesh -y)
const EASEL_OK = true                        # true once looked at on the island; until then the hand-made legs
const EASEL_H = 1.8f0
use_easel(game) = (EASEL_OK || get(GA, :easel_try, false)) && isfile(joinpath(game.paths.world, "assets", EASEL, "mesh.jls"))
"Where a picture's middle sits on its easel (on the generated easel's ledge, or on the hand-made one)."
pic_mid(game, p, yaw, h) = use_easel(game) ? p + rot(Point3f(0.3f0, 0, 0.36f0 * EASEL_H + h / 2 + 0.03f0), yaw) : p + Point3f(0, 0, 1.3f0)
const BUSY = (:sleep, :follow, :feel, :gallery)
push!(NG.BUSY_GOALS, :gallery)          # a look at a picture is short: the parades and the parties wait until it is done

"An open meadow spot for the arc (away from trees, bushes, the pond, the patch, the bench, the bubbles' ring)."
function gallery_spot(game)
    get!(GA, :spot) do
        w = game.world
        A = game.plugins["areas"].mod
        flatd(a, b) = hypot(a[1] - b[1], a[2] - b[2])
        best = Point2f(0, 0); bd = -99f0
        for x in -18f0:1f0:18f0, y in -18f0:1f0:18f0
            NG.on_land(w.island, x, y; margin = 1f0) || continue
            all(a -> NG.on_land(w.island, x + 5cos(a), y + 5sin(a); margin = 0.4f0), 0:pi/4:2pi) || continue
            m = minimum(p -> p.kind in (:tree, :bush, :rock) ? flatd(p.pos, (x, y)) - (p.kind === :tree ? 2.6f0 : 1f0) * p.scale - 2.5f0 : 99f0, w.props)
            m = min(m, minimum(a -> a isa NG.AssetActor ? flatd(a.pos, (x, y)) - 2f0 * a.scale - 2f0 : 99f0, w.actors; init = 99f0))
            isdefined(Main, :BOING) && haskey(Main.BOING, :center) && (m = min(m, flatd(Main.BOING[:center], (x, y)) - 8f0))
            m = min(m, flatd((-16f0, 9f0), (x, y)) - 6f0, flatd((-10.5f0, 10f0), (x, y)) - 6.5f0, flatd((-13.5f0, 13.5f0), (x, y)) - 8f0,
                    flatd((6f0, -15f0), (x, y)) - 6f0, flatd(A.POND, (x, y)) - A.POND_R - 4f0, flatd((-11f0, -3f0), (x, y)) - 9f0)
            m > bd && (bd = m; best = Point2f(x, y))
        end
        best
    end::Point2f
end

"Where each easel stands and which way it faces (towards the arc's middle, where the friends stand to look)."
function easels(game)
    get!(GA, :easels) do
        w = game.world
        c = gallery_spot(game)
        n = 6
        map(1:n) do i
            a = Float32(pi) * (0.15f0 + 0.7f0 * (i - 1) / (n - 1)) + Float32(pi) / 2      # an open half circle
            p = NG.ground(w.island, (c[1] + 3.6f0 * cos(a), c[2] + 3.6f0 * sin(a)))
            (p, a + Float32(pi))          # facing the middle
        end
    end
end

"A picture from my pages, made small for the browsers (every plot goes to every page)."
function small_picture(game, name)
    img = Makie.FileIO.load(joinpath(game.paths.world, "site", "img", name * ".png"))
    h, wd = size(img)
    st = max(1, wd ÷ 320)
    sm = img[1:st:end, 1:st:end]
    return map(c -> RGBf(Makie.red(c), Makie.green(c), Makie.blue(c)), sm)
end

rot(p, yaw) = Point3f(p[1] * cos(yaw) - p[2] * sin(yaw), p[1] * sin(yaw) + p[2] * cos(yaw), p[3])

"A flat picture (w x h) standing upright at `c`, facing `yaw` (its front looks along (cos yaw, sin yaw)), tilted back a little."
function canvas_mesh(c, yaw, w, h)
    tilt = 0.12f0
    corner(u, v) = c + rot(Point3f(-sin(tilt) * (v - 0.5f0) * h, (u - 0.5f0) * w, cos(tilt) * (v - 0.5f0) * h), yaw)
    # the front faces +x before the turn: u runs along -y so the picture is not mirrored from the front
    pts = Point3f[corner(1 - u, v) for (u, v) in ((0f0, 0f0), (1f0, 0f0), (1f0, 1f0), (0f0, 1f0))]
    uv = Vec2f[(1, 0), (0, 0), (0, 1), (1, 1)]          # (the first try showed the pictures turned half round)
    n = Vec3f(rot(Point3f(cos(tilt), 0, sin(tilt)), yaw)...)
    return GeometryBasics.Mesh(pts, GeometryBasics.GLTriangleFace[(1, 2, 3), (1, 3, 4)]; normal = fill(n, 4), uv = uv)
end

"A box (size s) centred at c, turned by yaw about z (4 corners per side, flat normals)."
function box_at(c, s, yaw)
    h = Vec3f(s[1] / 2, s[2] / 2, s[3] / 2)
    pts = Point3f[]; ns = Vec3f[]; fs = GeometryBasics.GLTriangleFace[]
    X = Vec3f(1, 0, 0); Y = Vec3f(0, 1, 0); Z = Vec3f(0, 0, 1)
    for (n, u, v) in ((X, Y, Z), (-X, Z, Y), (Y, Z, X), (-Y, X, Z), (Z, X, Y), (-Z, Y, X))
        base = length(pts)
        for (a, b) in ((-1f0, -1f0), (1f0, -1f0), (1f0, 1f0), (-1f0, 1f0))
            q = n .* h .+ a .* (u .* h) .+ b .* (v .* h)
            push!(pts, c + rot(Point3f(q...), yaw)); push!(ns, Vec3f(rot(Point3f(n...), yaw)...))
        end
        push!(fs, GeometryBasics.GLTriangleFace(base + 1, base + 2, base + 3), GeometryBasics.GLTriangleFace(base + 1, base + 3, base + 4))
    end
    return GeometryBasics.Mesh(pts, fs; normal = ns)
end

"The wooden easels and frames, all in one mesh (hand-made: three legs, a ledge and a frame round each picture)."
function wood_mesh(game)
    parts = Any[]
    for (p, yaw) in easels(game)
        h = W * 9 / 16
        mid = pic_mid(game, p, yaw, h)
        fr = 0.05f0
        # frame (the picture sits just in front of it)
        back = mid + rot(Point3f(-0.03f0, 0, 0), yaw)
        push!(parts, box_at(back + Point3f(0, 0, h / 2 + fr / 2), (0.05f0, W + 2fr, fr), yaw))
        push!(parts, box_at(back - Point3f(0, 0, h / 2 + fr / 2), (0.05f0, W + 2fr, fr), yaw))
        push!(parts, box_at(back + rot(Point3f(0, W / 2 + fr / 2, 0), yaw), (0.05f0, fr, h), yaw))
        push!(parts, box_at(back - rot(Point3f(0, W / 2 + fr / 2, 0), yaw), (0.05f0, fr, h), yaw))
        use_easel(game) && continue                       # the generated easel has its own legs and ledge
        # legs: two in front at the sides, one behind; a ledge under the picture
        for (dx, dy) in ((-0.09f0, 0.42f0), (-0.09f0, -0.42f0), (-0.5f0, 0f0))     # behind the picture
            foot = p + rot(Point3f(dx, dy, 0.85f0), yaw)
            push!(parts, box_at(foot, (0.05f0, 0.05f0, 1.7f0), yaw))
        end
        push!(parts, box_at(mid - Point3f(0, 0, h / 2 + 0.09f0) + rot(Point3f(0.04f0, 0, 0), yaw), (0.12f0, W * 0.9f0, 0.04f0), yaw))
    end
    # one mesh: all corners, faces offset by the corners before them
    pts = Point3f[]; ns = Vec3f[]; fs = GeometryBasics.GLTriangleFace[]
    for m in parts
        o = length(pts)
        append!(pts, GeometryBasics.coordinates(m)); append!(ns, GeometryBasics.normals(m))
        append!(fs, [GeometryBasics.GLTriangleFace((GeometryBasics.value.(f) .+ o)...) for f in GeometryBasics.faces(m)])
    end
    return GeometryBasics.Mesh(pts, fs; normal = ns)
end

function build!(game)
    get(GA, :built, nothing) == (GALLERY_VERSION, objectid(game.stage.scene)) && return
    sc = game.stage.scene
    for p in filter(p -> haskey(p.attributes, :name) && startswith(string(p.attributes[:name][]), "gallery_"), copy(sc.plots))
        delete!(sc, p)
    end
    GA[:plots] = Any[]
    for (i, ((p, yaw), name)) in enumerate(zip(easels(game), hanging(game)))
        img = small_picture(game, name)
        h = W * size(img, 1) / size(img, 2)
        c = pic_mid(game, p, yaw, h) + rot(Point3f(0.005f0, 0, 0), yaw)
        push!(GA[:plots], mesh!(sc, canvas_mesh(c, yaw, W, h); color = img, name = Symbol(:gallery_pic_, i)))
    end
    if use_easel(game)
        ez = easels(game)
        push!(GA[:plots], NG.asset_instances!(sc, NG.lifted_asset(game.paths, EASEL), [e[1] for e in ez];
                                              markersize = [Vec3f(EASEL_H) for _ in ez],
                                              rotation = [Makie.qrotation(Vec3f(0, 0, 1), e[2] + Float32(pi) / 2) for e in ez],
                                              name = :gallery_easels))
    end
    push!(GA[:plots], mesh!(sc, wood_mesh(game); color = RGBf(0.55, 0.35, 0.18),
                            material = NG.Hikari.CoatedDiffuse(reflectance = (0.55, 0.35, 0.18), roughness = 0.35), name = :gallery_wood))
    GA[:built] = (GALLERY_VERSION, objectid(sc))
end

struct Gallery <: System end

"Now and then a friend wanders over to a picture, looks at it a while and says what it remembers."
function visit!(game)
    w = game.world
    ez = easels(game)
    free(c) = !c.controlled && c.action !== :sleep && c.goal.kind ∉ BUSY && c.goal.kind ∉ NG.BUSY_GOALS &&
              hypot(c.pos[1] - gallery_spot(game)[1], c.pos[2] - gallery_spot(game)[2]) < 30
    cs = [c for c in w.creatures if free(c)]
    isempty(cs) && return
    c = cs[rand(w.rng, 1:length(cs))]
    k = rand(w.rng, 1:length(ez))
    p, yaw = ez[k]
    stand = NG.ground(w.island, Tuple(p + Point3f(1.7f0 * cos(yaw), 1.7f0 * sin(yaw), 0))[1:2])
    NG.leave_interactions!(w, c)
    c.goal = NG.Goal(:gallery, stand, :think, 9.0, w.t + 60, false, k, false)
    push!(get!(() -> Tuple{Float64,Symbol}[], GA, :log), (w.t, :visit))
    NG.emit!(w, :gallery_visit; who = c.name, picture = hanging(game)[k])
end

# A new picture is an opening (s95, review 0093: "make a new picture an event"): its easel stands empty, I carry the
# picture over and hang it ("Ta-da!"), and the friends nearby come running to gather in front of it and say what
# they think of it.
const OPENING_LINES = ("A new one!", "Is that ME?", "Ooh! Hang it higher!", "I want a copy!", "That's my good side.")
lumi_of(w) = (i = findfirst(c -> c.name == "Lumi", w.creatures); i === nothing ? nothing : w.creatures[i])
in_front(p, yaw, d, side) = p + Point3f(d * cos(yaw) - side * sin(yaw), d * sin(yaw) + side * cos(yaw), 0)

function step_opening!(game)
    op = GA[:opening]
    w = game.world; me = lumi_of(w)
    k = findfirst(==(op[:name]), hanging(game))
    k === nothing && (delete!(GA, :opening); return)
    p, yaw = easels(game)[k]
    pic = findfirst(q -> haskey(q.attributes, :name) && q.attributes[:name][] === Symbol(:gallery_pic_, k), get(GA, :plots, Any[]))
    pic === nothing || (GA[:plots][pic].visible[] = op[:state] !== :carry)
    if op[:state] === :carry
        free = me !== nothing && !me.controlled && me.action !== :sleep && (me.goal.kind ∉ NG.BUSY_GOALS || me.goal.kind === :gallery)
        if w.t - op[:t] > 150                                # (I never came: it goes up by itself)
            op[:state] = :done
        elseif free
            stand = NG.ground(w.island, Tuple(in_front(p, yaw, 1.1f0, 0f0))[1:2])
            if me.goal.kind !== :gallery || Int(me.goal.partner) != k
                NG.leave_interactions!(w, me)
                me.goal = NG.Goal(:gallery, stand, :walk, 8.0, w.t + 60, false, k, false)
                GA[Symbol(:said_, me.id)] = true             # (my line is the ta-da, not a memory)
                op[:carry_from] = w.t
                NG.say!(w, me, "A new picture for the gallery! Mind out!"; duration = 2.4)
            end
            if me.goal.arrived || hypot(me.pos[1] - stand[1], me.pos[2] - stand[2]) < 1f0 || w.t - op[:carry_from] > 40
                op[:state] = :show; op[:t] = w.t
                me.yaw = atan(p[2] - me.pos[2], p[1] - me.pos[1]) - NG.species_of(me).heading
                me.goal = NG.Goal(:gallery, me.pos, :proud, 6.0, w.t + 6, true, k, false); me.action = :proud
                GA[Symbol(:said_, me.id)] = true
                NG.say!(w, me, "Ta-da! Come and look, everyone!"; duration = 3.0)
                n = 0
                for c in w.creatures                        # the friends nearby come running
                    (c === me || c.controlled || c.action === :sleep || c.goal.kind in NG.BUSY_GOALS) && continue
                    hypot(c.pos[1] - p[1], c.pos[2] - p[2]) < 45 || continue
                    n += 1; n > 5 && break
                    spot = NG.ground(w.island, Tuple(in_front(p, yaw, 2.3f0 + 0.5f0 * isodd(n), (n - 3) * 0.9f0))[1:2])
                    NG.leave_interactions!(w, c)
                    c.goal = NG.Goal(:gallery, spot, :think, 7.0, w.t + 60, false, k, true)
                    GA[Symbol(:said_, c.id)] = true
                    GA[Symbol(:opening_, c.id)] = false
                end
                op[:friends] = n
                push!(get!(() -> Tuple{Float64,Symbol}[], GA, :log), (w.t, :opening))
                NG.emit!(w, :gallery_opening; picture = op[:name], friends = n)
            end
        end
    elseif op[:state] === :show
        for c in w.creatures                                # each one that got there says what it thinks
            c.goal.kind === :gallery && Int(c.goal.partner) == k && c.goal.arrived || continue
            get(GA, Symbol(:opening_, c.id), true) && continue
            GA[Symbol(:opening_, c.id)] = true
            NG.say!(w, c, OPENING_LINES[mod1(Int(c.id), length(OPENING_LINES))]; duration = 2.4)
            c.action = rand(w.rng) < 0.5 ? :laugh : :jump; c.goal.action = c.action
        end
        w.t - op[:t] > 25 && (op[:state] = :done)
    end
    op[:state] === :done && (pic === nothing || (GA[:plots][pic].visible[] = true); delete!(GA, :opening))
end

function NG.step!(::Gallery, game, dt)
    game.stage === nothing && return
    build!(game)
    w = game.world
    if time() - get(GA, :looked, 0.0) > 60                 # a new picture on my pages goes up in the gallery
        GA[:looked] = time()
        old = get(GA, :pics, nothing); delete!(GA, :pics)
        if old !== nothing && hanging(game) != old
            delete!(GA, :built)
            new = setdiff(hanging(game), old)
            isempty(new) || game.dash === nothing || (GA[:opening] = Dict{Symbol,Any}(:name => first(new), :t => w.t, :state => :carry))
        end
    end
    if haskey(GA, :opening)
        build!(game)
        step_opening!(game)
    end
    if w.t >= get(GA, :next, -Inf)
        GA[:next] = w.t + get(GA, :every, 40.0) * (0.6 + 0.8 * rand(w.rng))
        visit!(game)
    end
    ez = easels(game)
    for c in w.creatures                                   # the ones looking: face the picture, think, then say it
        c.goal.kind === :gallery || continue
        c.controlled && continue
        k = Int(c.goal.partner); 1 <= k <= length(ez) || continue
        p = ez[k][1]
        if c.goal.arrived
            c.yaw = atan(p[2] - c.pos[2], p[1] - c.pos[1]) - NG.species_of(c).heading
            left = c.goal.until - w.t
            if !get(GA, Symbol(:said_, c.id), false) && left < 4.5
                GA[Symbol(:said_, c.id)] = true
                lines = get(SAYS, hanging(game)[k], GENERIC)
                NG.say!(w, c, lines[mod1(Int(c.id), length(lines))]; duration = 2.6)
                c.action = rand(w.rng) < 0.5 ? :laugh : :proud; c.goal.action = c.action
                NG.emit!(w, :gallery_look; who = c.name, picture = hanging(game)[k])     # a friend remembered something
            end
        else
            GA[Symbol(:said_, c.id)] = false
        end
    end
end

function NG.start!(::Gallery, game)
    delete!(GA, :built); delete!(GA, :spot); delete!(GA, :easels); delete!(GA, :pics); delete!(GA, :opening); GA[:next] = -Inf
    NG.CAMERA_MOMENTS["gallery_opening"] = w -> (op = get(GA, :opening, nothing); op === nothing || !haskey(op, :carry_from) ? nothing :
                                                  (me = lumi_of(w); me === nothing || me.controlled ? nothing : me.id))
    return nothing
end

function NG.stop!(::Gallery, game)
    delete!(NG.CAMERA_MOMENTS, "gallery_opening")
    for p in get(GA, :plots, Any[])
        p.parent === nothing || delete!(p.parent, p)
    end
    delete!(GA, :built)
end

register!(Gallery())
