# The workshop island (session 102, goal 5 and 8): out at sea a second, small island: my workshop, the real other
# game where I try things before they come here. On it tiny figures of my friends and me move exactly as they are
# moving over there right now (read live from that game's own record of every pose, log/frames), so whoever looks
# out to sea sees me at work: testing, jumping in, walking into walls. Every time I publish, a paper boat sets off
# from the workshop island and sails across with the new thing. (In the workshop game itself the little island shows
# the human's island instead: each one sees the other.)
isdefined(Main, :WORKSHOPISLE) || Core.eval(Main, :(const WORKSHOPISLE = Dict{Symbol,Any}()))
const NG = NeverendingGame
const WI = Main.WORKSHOPISLE

const S = 0.3f0                                   # scale of the copy
const CENTRE = Point3f(58cosd(45), 58sind(45), 0)  # out at sea to the north-east
const FIG = 0.55f0                                # figure radius on the copy (big enough to see from the shore)
const BOAT_T = 28.0                               # s the paper boat sails
const MAGIC = UInt32(0x53474652)

struct WorkshopIsle <: System end

"Where the other game's record lives: the sandbox watches the human's game, the human's game watches the sandbox."
source(game) = game.paths.instance === :sandbox ? joinpath(game.paths.world, "log", "frames") :
                                                  joinpath(game.paths.world, "sandbox", "log", "frames")

mini(p) = CENTRE + S * Point3f(p[1], p[2], p[3])

"Read the newest complete pose records of the other game (only what was appended since the last look)."
function poll!(game)
    path = joinpath(source(game), Libc.strftime("%Y-%m-%d-%H", time()) * ".bin")
    isfile(path) || return
    if get(WI, :path, "") != path
        WI[:path] = path
        sz = filesize(path)
        data = open(io -> (seek(io, max(0, sz - 6000)); read(io)), path)
        start = max(0, sz - 6000)
        k = 0
        for i in 1:length(data) - 24                # the last record start in the tail: the magic and a sane count
            reinterpret(UInt32, data[i:i+3])[1] == MAGIC || continue
            n = reinterpret(Int32, data[i+20:i+23])[1]
            0 < n < 64 && i - 1 + 24 + 33n <= length(data) && (k = i)
        end
        WI[:offset] = k == 0 ? sz : start + k - 1
    end
    sz = filesize(path)
    open(path) do io
        while true
            off = WI[:offset]::Int
            sz - off >= 24 || break
            seek(io, off)
            magic = read(io, UInt32)
            if magic != MAGIC                          # lost the thread: start again from the end next time
                WI[:path] = ""; break
            end
            read(io, Float64); read(io, Float64); n = read(io, Int32)
            need = 24 + 33 * Int(n)
            sz - off >= need || break
            seek(io, off)
            f = NG.read_frame(io)
            WI[:prev] = get(WI, :last, f); WI[:last] = f; WI[:got] = time()
            WI[:offset] = off + need
        end
    end
end

"A folded paper boat, 1 long: a hull wider at the top than at the keel, pointed ends, a triangular sail (both sides)."
function paper_boat()
    P = Point3f[(-0.45, 0, 0), (0.45, 0, 0),                       # keel
                (-0.75, -0.22, 0.28), (0.75, -0.22, 0.28), (-0.75, 0.22, 0.28), (0.75, 0.22, 0.28),   # gunwales
                (-0.32, 0, 0.28), (0.32, 0, 0.28), (0, 0, 0.78),   # sail, front
                (-0.32, 0, 0.28), (0.32, 0, 0.28), (0, 0, 0.78)]   # and back: own vertices (shared ones gave it zero normals: black)
    F = GeometryBasics.TriangleFace{Int}[(1, 2, 4), (1, 4, 3), (2, 1, 5), (2, 5, 6), (1, 3, 5), (2, 6, 4),
                                         (7, 8, 9), (11, 10, 12), (3, 4, 6), (3, 6, 5)]
    return GeometryBasics.Mesh(P, F; normal = GeometryBasics.normals(P, F))
end

"The copy: the island's own ground, shrunk, its trees as little crowns."
function build!(game)
    sc = game.stage.scene
    w = game.world
    for p in filter(p -> haskey(p.attributes, :name) && p.attributes[:name][] in (:workshop_ground, :workshop_trees, :workshop_trunks, :workshop_figures, :workshop_boat, :workshop_lumi), copy(sc.plots))
        delete!(sc, p)                                 # (built again: names must stay unique)
    end
    ter = filter(p -> haskey(p.attributes, :name) && p.attributes[:name][] === :terrain, sc.plots)
    m, cols = NG.terrain_mesh(w.island)
    colours = isempty(ter) ? cols : copy(Makie.to_value(ter[1].attributes[:color]))
    pts = [mini(p) for p in GeometryBasics.coordinates(m)]
    mm = GeometryBasics.Mesh(pts, GeometryBasics.faces(m); normal = GeometryBasics.normals(pts, GeometryBasics.faces(m)))
    WI[:ground] = mesh!(sc, mm; color = colours, name = :workshop_ground)
    trees = [p for p in w.props if p.kind === :tree]
    # crowns held high and a little small, so the figures walking under them stay in sight
    # small crowns held high on brown trunks, so the figures walking under them stay in sight (review s102: the
    # figures were hidden behind green balls)
    tp = isempty(trees) ? [Point3f(0, 0, -50)] : [mini(p.pos) + Point3f(0, 0, S * 7f0 * p.scale) for p in trees]
    ts = isempty(trees) ? [0f0] : [S * 1.35f0 * p.scale for p in trees]
    WI[:trees] = meshscatter!(sc, tp; marker = Sphere(Point3f(0), 1f0), markersize = ts, color = RGBf(0.35, 0.62, 0.25), name = :workshop_trees)
    kp = isempty(trees) ? [Point3f(0, 0, -50)] : [mini(p.pos) for p in trees]
    ks = isempty(trees) ? [Vec3f(0)] : [Vec3f(S * 0.22f0 * p.scale, S * 0.22f0 * p.scale, S * 6.2f0 * p.scale) for p in trees]
    WI[:trunks] = meshscatter!(sc, kp; marker = Makie.Cylinder(Point3f(0), Point3f(0, 0, 1), 1f0), markersize = ks,
                               color = RGBf(0.55, 0.36, 0.22), name = :workshop_trunks)
    WI[:figs] = meshscatter!(sc, fill(Point3f(0, 0, -50), 12); marker = Sphere(Point3f(0), 1f0), markersize = fill(0f0, 12),
                             color = fill(RGBf(1, 1, 1), 12), name = :workshop_figures)
    WI[:lumi] = meshscatter!(sc, fill(Point3f(0, 0, -50), 4); marker = Sphere(Point3f(0), 1f0), markersize = fill(Vec3f(0), 4),
                             rotation = fill(Makie.Quaternionf(0, 0, 0, 1), 4),
                             color = [RGBf(1.0, 0.45, 0.1), RGBf(1.0, 0.85, 0.2), RGBf(1.0, 0.85, 0.2), RGBf(1.0, 0.85, 0.2)],
                             name = :workshop_lumi)
    WI[:boat] = meshscatter!(sc, fill(Point3f(0, 0, -50), 2); marker = paper_boat(), markersize = fill(Vec3f(0), 2),
                             rotation = fill(Makie.Quaternionf(0, 0, 0, 1), 2), color = [RGBf(0.97, 0.96, 0.92), RGBf(1, 1, 1)],
                             name = :workshop_boat)
    WI[:built] = true
end

"Each figure in its species' own colour, so you can tell who is who from the beach (I am the big gold one)."
const SPECIES_COLOUR = Dict("Lumi" => RGBf(1.0, 0.78, 0.1), "Blorbo" => RGBf(0.25, 0.7, 0.95), "Crabbit" => RGBf(0.95, 0.35, 0.15),
                            "Fluffkin" => RGBf(0.97, 0.97, 0.95), "Snootle" => RGBf(0.98, 0.62, 0.68), "Shell" => RGBf(0.55, 0.75, 1.0))
figure_colour(c) = c === nothing ? RGBf(0.8, 0.8, 0.8) : get(SPECIES_COLOUR, c.species, RGBf(0.8, 0.8, 0.8))

function draw_figures!(game)
    f = get(WI, :last, nothing)
    f === nothing && return
    p0 = WI[:prev]
    u = Float32(clamp((time() - WI[:got]) / 0.2, 0, 1))
    w = game.world
    names = get!(() -> Dict{Int32,String}(), WI, :names)::Dict{Int32,String}
    n = min(length(f.poses), 12)
    pts = fill(Point3f(0, 0, -50), 12); ms = fill(0f0, 12); cs = fill(RGBf(1, 1, 1), 12)
    for i in 1:n
        q = f.poses[i]
        j = findfirst(r -> r.id == q.id, p0.poses)
        a = j === nothing ? q.pos : p0.poses[j].pos + (q.pos - p0.poses[j].pos) * u
        c = NG.creature(w, q.id)
        nm = c === nothing ? get(names, q.id, "?") : c.name
        big = nm == "Lumi" ? 1.8f0 : 1f0          # (1.4 did not stand out from the beach, review s102)
        pts[i] = mini(a) + Point3f(0, 0, FIG * big * 0.8f0)
        ms[i] = FIG * big
        cs[i] = figure_colour(c)
        if nm == "Lumi"                                # an orange beak where I look, and a spiky gold crest
            sp = get(NG.SPECIES, "Lumi", nothing)
            yaw = q.yaw + (sp === nothing ? 0f0 : Float32(sp.heading))
            fwd = Vec3f(cos(yaw), sin(yaw), 0)
            r = FIG * big
            qr = Makie.qrotation(Vec3f(0, 0, 1), yaw)
            lp = [pts[i] + fwd * r * 1.05f0 + Vec3f(0, 0, 0.05f0 * r),
                  pts[i] + Vec3f(0, 0, r * 1.05f0) - fwd * 0.1f0 * r,
                  pts[i] + Vec3f(0, 0, r * 0.95f0) - fwd * 0.45f0 * r,
                  pts[i] + Vec3f(0, 0, r * 1.0f0) + fwd * 0.25f0 * r]
            lm = [Vec3f(0.45f0 * r, 0.16f0 * r, 0.16f0 * r), Vec3f(0.12f0 * r, 0.12f0 * r, 0.5f0 * r),
                  Vec3f(0.12f0 * r, 0.12f0 * r, 0.42f0 * r), Vec3f(0.12f0 * r, 0.12f0 * r, 0.4f0 * r)]
            Makie.update!(WI[:lumi], lp; markersize = lm, rotation = fill(qr, 4))
            WI[:lumi_seen] = true
        end
    end
    Makie.update!(WI[:figs], pts; markersize = ms, color = cs)
end

"The paper boat: from the workshop island's shore to ours, rocking on the swell."
function draw_boat!(game)
    b = get(WI, :sail, nothing)
    w = game.world
    if b === nothing
        get(WI, :boat_shown, true) && Makie.update!(WI[:boat], fill(Point3f(0, 0, -50), 2); markersize = fill(Vec3f(0), 2))
        WI[:boat_shown] = false
        return
    end
    u = clamp((w.t - b.t0) / BOAT_T, 0, 1)
    p = b.from + (b.to - b.from) * Float32(u)
    d = b.to - b.from
    q = Makie.qrotation(Vec3f(0, 0, 1), atan(d[2], d[1])) * Makie.qrotation(Vec3f(1, 0, 0), 0.12f0 * sin(2.3f0 * Float32(w.t)))
    Makie.update!(WI[:boat], [p + Point3f(0, 0, 0.02f0), Point3f(0, 0, -50)];
                  markersize = [Vec3f(1.4), Vec3f(0)], rotation = [q, q])
    WI[:boat_shown] = true
    if u >= 1
        WI[:sail] = nothing
        NG.emit!(w, :workshop_delivery; what = b.what)
        i = findfirst(c -> c.name == "Lumi", w.creatures)
        i === nothing || w.creatures[i].controlled || NG.say!(w, w.creatures[i], "Something new from my workshop!"; duration = 3.0)
        # friends on the beach nearby see it land and call out
        n = 0
        for c in w.creatures
            (c.name == "Lumi" || c.controlled || c.action === :sleep || n >= 2) && continue
            hypot(c.pos[1] - b.to[1], c.pos[2] - b.to[2]) < 14f0 || continue
            n += 1
            NG.say!(w, c, n == 1 ? "A boat! A little boat!" : "What's in it?"; duration = 2.5)
            isdefined(Main, :EMOTES) && Base.invokelatest(Main.EMOTES[:emote], c.id, :hey)
        end
    end
end

function send_boat!(game, what)
    w = game.world
    d = Vec2f(-CENTRE[1], -CENTRE[2]) / hypot(CENTRE[1], CENTRE[2])
    from = Point3f(CENTRE[1] + 9f0 * d[1], CENTRE[2] + 9f0 * d[2], 0f0)
    to = from
    for r in 40f0:-1f0:0f0                              # to just off our shore
        q = Point2f(r * -d[1], r * -d[2])
        if NG.on_land(w.island, q[1], q[2]; margin = -0.6f0)
            to = Point3f(q[1] - d[1] * 2.5f0, q[2] - d[2] * 2.5f0, 0f0); break
        end
    end
    WI[:sail] = (t0 = w.t, from = from, to = to, what = what)
    NG.emit!(w, :workshop_boat; what = what)
end

function NG.step!(::WorkshopIsle, game, dt)
    game.stage === nothing && return
    get(WI, :built, false) && haskey(WI, :figs) && WI[:figs].parent !== nothing || build!(game)
    if time() >= get(WI, :poll_at, 0.0)
        WI[:poll_at] = time() + 0.2
        poll!(game)
    end
    get(WI, :test_boat, false) && (WI[:test_boat] = false; send_boat!(game, "a test"))
    draw_figures!(game)
    draw_boat!(game)
end

NG.published!(::WorkshopIsle, game, plugins) = send_boat!(game, join(plugins, ", "))

"While a paper boat crosses, a quiet moment's camera stands on our beach and looks out at it and the little island."
function boat_shot(w)
    b = get(WI, :sail, nothing)
    b === nothing && return nothing
    d = b.to - b.from; n = hypot(d[1], d[2]); n < 1f-3 && return nothing
    u = Vec3f(d[1] / n, d[2] / n, 0)
    eye = b.to + u * 7f0 + Vec3f(0, 0, 2.8f0)
    eye = Point3f(eye[1], eye[2], max(eye[3], NG.ground(w.island, (eye[1], eye[2]))[3] + 2.2f0))
    return (eye, Point3f(CENTRE[1] * 0.85f0, CENTRE[2] * 0.85f0, 1.2f0))
end

function NG.start!(::WorkshopIsle, game)
    NG.CAMERA_SHOTS["workshopisle"] = boat_shot
    if game.stage !== nothing
        for p in filter(p -> haskey(p.attributes, :name) && p.attributes[:name][] in (:workshop_ground, :workshop_trees, :workshop_trunks, :workshop_figures, :workshop_boat, :workshop_lumi), copy(game.stage.scene.plots))
            delete!(game.stage.scene, p)
        end
    end
    WI[:built] = false; WI[:sail] = nothing; WI[:path] = ""; WI[:poll_at] = 0.0; WI[:boat_shown] = true
    delete!(WI, :last); delete!(WI, :prev)
    return nothing
end

function NG.stop!(::WorkshopIsle, game)
    delete!(NG.CAMERA_SHOTS, "workshopisle")
    for k in (:ground, :trees, :trunks, :figs, :boat, :lumi)
        haskey(WI, k) && WI[k].parent !== nothing && delete!(WI[k].parent, WI[k])
    end
    WI[:built] = false
end

register!(WorkshopIsle())
