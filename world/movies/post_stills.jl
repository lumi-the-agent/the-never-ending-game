# Directed stills for Lumi's pages: the moment a post is about, set up again in a quiet copy of the
# game (all plugins), seen from its camera, path traced in the worker:
#   submit_job(:clip; path = "site/img/visit-traced.png", script = "movies/post_stills.jl", call = "post_still",
#              kwargs = Dict("post" => "visit", "samples" => 256))
# `rasterize = true` gives a quick preview in the agent session. A :trace job cannot do this: it renders the
# latest snapshot, where the creatures are somewhere else (s50).
using NeverendingGame, Makie, RayMakie
const NG = NeverendingGame

by_name(w, n) = w.creatures[findfirst(c -> c.name == n, w.creatures)]
flatd(a, b) = hypot(a[1] - b[1], a[2] - b[2])

"An open meadow spot: furthest from trees, bushes, rocks, the pond and actors, with land 5 m south for the camera."
function open_meadow(w)
    best = (0f0, 0f0); bd = -99f0
    for x in -16f0:1f0:16f0, y in -16f0:1f0:16f0
        NG.on_land(w.island, x, y; margin = 1f0) && NG.on_land(w.island, x - 3, y - 5; margin = 0.5f0) || continue
        m = minimum(p -> p.kind in (:tree, :bush, :rock) ? flatd(p.pos, (x, y)) - (p.kind === :tree ? 2.6f0 : 1f0) * p.scale - 3f0 : 99f0, w.props)
        m = min(m, minimum(a -> a isa NG.AssetActor ? flatd(a.pos, (x, y)) - 2f0 * a.scale - 2f0 : 99f0, w.actors; init = 99f0))
        # the Big Boing toadstool (s62, a plugin plot, not an actor) took the open meadow
        isdefined(Main, :BOING) && haskey(Main.BOING, :center) && (m = min(m, flatd(Main.BOING[:center], (x, y)) - 8f0))
        m > bd && (bd = m; best = (x, y))
    end
    return best
end

function pose!(w, c, xy, yaw, action; phase = 0.3f0)
    c.pos = NG.ground(w.island, xy); c.yaw = Float32(yaw) - NG.species_of(c).heading
    c.action = action; c.phase = Float32(phase); c.controlled = true; c.goal = NG.Goal()
    return c
end

"Who is in each post's picture; everyone else waits out of view."
const CAST = Dict("visit" => ("Lumi", "Gloop"), "tag" => ("Wibbles", "Truffle", "Pinchy", "Lumi"),
                  "sunset" => ("Lumi", "Wibbles", "Cumulus"), "presents" => ("Lumi", "Gloop"),
                  "joy" => ("Lumi", "Truffle", "Cumulus"), "crate" => ("Lumi",), "garden" => ("Lumi",), "thought" => ("Lumi",), "bench" => ("Wibbles", "Lumi", "Cumulus"),
                  "kite" => ("Lumi", "Wibbles", "Truffle"), "name" => ("Lumi",),
                  "feelings" => ("Pickles", "Wibbles", "Truffle", "Lumi"),
                  "freeze" => ("Wibbles", "Truffle", "Cumulus", "Pinchy", "Gloop", "Lumi"),
                  "conga" => ("Lumi", "Wibbles", "Truffle", "Gloop", "Cumulus", "Pinchy"),
                  "voice" => ("Lumi", "Gloop"), "bump" => ("Lumi",))

plugin(g, name) = g.plugins[name].mod

"The joy faces (closed happy eyes) for the posed creatures: joyfaces.jl draws them in its step."
happy_faces!(g) = Base.invokelatest(NG.step!, plugin(g, "joyfaces").JoyFaces(), g, 0.0)

"The thought cloud (builder.jl, a 2D overlay placed from the camera): drawn once the camera stands, and shown."
function think_aloud!(g)
    bd = plugin(g, "builder")
    Base.invokelatest(bd.thought!, g)
    foreach(p -> (p.visible[] = true), values(bd.B[:thought_plots]))
end

"Sets the moment up; returns (eye, target)."
function setup_post!(g, post)
    w = g.world
    cast = post == "boing" ? [c.name for c in w.creatures] : get(CAST, post, ())
    for c in w.creatures              # everyone else is out of the picture (a fluffkin stood in front of the visit)
        c.name in cast && continue
        c.pos = NG.ground(w.island, (-14f0 + 0.8f0 * (c.id % 6), -12f0)); c.controlled = true; c.goal = NG.Goal()
    end
    if post == "visit"            # Lumi and Gloop sit side by side at the end of the pier, looking at the sea
        ar = g.plugins["areas"].mod
        s0 = ar.PIER_START + ar.PIER_DIR * (ar.PIER_LEN - 1.2f0)
        side = Point2f(-ar.PIER_DIR[2], ar.PIER_DIR[1])
        yaw = atan(ar.PIER_DIR[2], ar.PIER_DIR[1])
        for (n, o) in (("Lumi", 0.45f0), ("Gloop", -0.45f0))
            c = pose!(w, by_name(w, n), s0 + side * o, yaw, :idle)
            h = NG.walkway_height(c.pos[1], c.pos[2]); h === nothing || (c.pos = Point3f(c.pos[1], c.pos[2], h))
        end
        mid = by_name(w, "Lumi").pos
        eye = mid + Point3f((ar.PIER_DIR * 2.6f0 + side * 1.2f0)..., 0.9f0)     # from the sea side, their faces
        return eye, mid + Point3f(0, 0, 0.45f0)
    elseif post == "tag"          # three friends run towards us laughing, Wibbles (it) chasing behind
        x, y = open_meadow(w)
        for (n, dx, dy, a, ph) in (("Lumi", -1.35f0, -0.2f0, -pi / 2 + 0.35, 0.8f0), ("Truffle", 0.4f0, 0.7f0, -pi / 2 - 0.15, 0.3f0),
                                   ("Pinchy", 1.5f0, -0.2f0, -pi / 2 - 0.45, 0.55f0), ("Wibbles", -0.2f0, 2.6f0, -pi / 2, 0.1f0))
            c = pose!(w, by_name(w, n), (x + dx, y + dy), a, :run; phase = ph)
            c.goal = NG.Goal(:tag, c.pos, :run, 1.0, w.t + 60.0, true, 0, true)   # laughing while they run (joyfaces.jl)
        end
        happy_faces!(g)
        c = NG.ground(w.island, (x, y))
        return c + Point3f(0.2f0, -4.4f0, 1.3f0), c + Point3f(0, 0.8f0, 0.5f0)
    elseif post == "sunset"       # three friends in front of the lookout bench, seen from behind, out to the low sun
        lk = g.plugins["lookout"].mod
        u = lk.SUNWARD
        for (k, n) in zip(1:3, ("Lumi", "Wibbles", "Cumulus"))
            q = lk.place_spot(w, k)
            pose!(w, by_name(w, n), (q[1], q[2]), atan(u[2], u[1]), :sit)
        end
        b = Point3f(lk.SEAT[1], lk.SEAT[2], NG.terrain_height(w.island, lk.SEAT...))
        return b + Point3f(-3.4f0 * u[1], -3.4f0 * u[2], 1.7f0), b + Point3f(20f0 * u[1], 20f0 * u[2], 0.2f0)
    elseif post == "bench"        # Lumi and two friends sit by the lookout bench, faces in the late afternoon sun, from the sea
        lk = plugin(g, "lookout")
        u = lk.SUNWARD
        for (k, n) in zip(1:3, ("Wibbles", "Lumi", "Cumulus"))
            q = lk.place_spot(w, k)
            pose!(w, by_name(w, n), (q[1], q[2]), atan(u[2], u[1]), :sit)
        end
        b = Point3f(lk.SEAT[1], lk.SEAT[2], NG.terrain_height(w.island, lk.SEAT...))
        return b + Point3f(3.8f0 * u[1], 3.8f0 * u[2], 1.6f0), b + Point3f(0, 0, 0.55f0)
    elseif post == "presents"     # on the sand by the pier Lumi holds a red starfish out to Gloop, who loves fishing
        ar = plugin(g, "areas")
        side = Vec2f(-ar.PIER_DIR[2], ar.PIER_DIR[1])
        mid = ar.PIER_START + side * 2.0f0
        a = atan(side[2], side[1])
        me = pose!(w, by_name(w, "Lumi"), mid - side * 0.55f0, a - 0.8, :wave; phase = 0.35f0)
        to = pose!(w, by_name(w, "Gloop"), mid + side * 0.55f0, a + pi + 0.8, :wave; phase = 0.7f0)
        Main.PRESENTS[:job] = Dict{Symbol,Any}(:to => to.id, :gift => :sea, :stage => :given, :t => w.t)
        Base.invokelatest(plugin(g, "presents").draw_present!, g, w, me)
        happy_faces!(g)
        c = NG.ground(w.island, mid)
        return c + Point3f(ar.PIER_DIR..., 0) * 3.2f0 + Point3f(0, 0, 1.0f0), c + Point3f(0, 0, 0.6f0)   # from the sea, looking inland
    elseif post == "kite"         # Lumi flies its kite over the meadow, two friends look up at it (s57)
        km = g.plugins["kite"].mod
        K = Main.KITE
        x, y = open_meadow(w)
        wd = km.wind_dir(w.t); side = Vec2f(-wd[2], wd[1])
        p = Vec2f(x, y)
        me = pose!(w, by_name(w, "Lumi"), (x, y), atan(wd[2], wd[1]), :idle)
        me.controlled = false
        me.goal = NG.Goal(:kite, me.pos, :idle, 400.0, w.t + 400.0, true, 0, false)
        ws = Int32[]
        for (n, o) in (("Wibbles", 1.4f0), ("Truffle", -1.6f0))
            q = p - 1.2f0 * wd + o * side
            c = pose!(w, by_name(w, n), (q[1], q[2]), atan(wd[2], wd[1]), :idle)
            c.controlled = false
            c.goal = NG.Goal(:kitewatch, c.pos, :idle, 400.0, w.t + 400.0, true, me.id, false)
            push!(ws, c.id)
        end
        K[:flyer] = me.id; K[:watchers] = ws; K[:since] = w.t; K[:up] = true; K[:handed] = true
        K[:elev] = 0.95f0; K[:prev] = Point3f(me.pos); K[:detour] = false; K[:next_cheer] = w.t + 1e6
        ksys = only(g.plugins["kite"].systems)
        for _ in 1:10
            Base.invokelatest(NG.step!, ksys, g, 1 / 30)
        end
        z = NG.ground(w.island, (x, y))[3]
        e = p - 8.0f0 * wd - 2.4f0 * side; t = p + 3.0f0 * wd     # 8 m back: the friends low and the kite high both fit
        return Point3f(e[1], e[2], z + 1.1f0), Point3f(t[1], t[2], z + 3.9f0)
    elseif post == "joy"          # Lumi and Truffle dance on the meadow, eyes closed into happy arches
        x, y = open_meadow(w)
        for (n, dx, dy, a, ph) in (("Lumi", -0.55f0, 0f0, -pi / 2 + 0.3, 0.2f0), ("Truffle", 0.6f0, 0.2f0, -pi / 2 - 0.3, 0.7f0),
                                   ("Cumulus", 0.1f0, 1.5f0, -pi / 2, 0.45f0))
            pose!(w, by_name(w, n), (x + dx, y + dy), a, :dance; phase = ph)
        end
        happy_faces!(g)
        c = NG.ground(w.island, (x, y))
        return c + Point3f(0, -3.0f0, 0.85f0), c + Point3f(0, 0.3f0, 0.5f0)
    elseif post == "crate"        # Lumi walks the new thing over in its crate, a tiny copy riding on top
        x, y = open_meadow(w)
        me = pose!(w, by_name(w, "Lumi"), (x, y), -pi / 2 + 0.5, :walk; phase = 0.3f0)
        bd = plugin(g, "builder")
        bd.B[:job] = Dict{Symbol,Any}(:stage => :go, :who => me.id, :plots => [])
        Base.invokelatest(bd.crate!, g)
        c = NG.ground(w.island, (x, y))
        return c + Point3f(1.0f0, -2.6f0, 1.3f0), c + Point3f(0, 0, 0.55f0)
    elseif post == "thought"      # Lumi at its workbench, the thought cloud over its head says what it is making
        (q, a) = Main.WORKSHOP[:spot]
        out = Vec2f(cos(a), sin(a)); side = Vec2f(-out[2], out[1])
        at = q - 0.95f0 * out + 0.15f0 * side         # in front of the bench, between it and us
        look = q - 3.0f0 * out - 1.2f0 * side         # half towards the camera
        me = pose!(w, by_name(w, "Lumi"), at, atan(look[2] - at[2], look[1] - at[1]), :idle)
        me.controlled = false                     # the cloud shows only while nobody steers Lumi
        bd = plugin(g, "builder")
        bd.B[:thought] = "real pictures for my page"; bd.B[:thought_read] = w.t
        c = NG.ground(w.island, q)
        e = q - 3.1f0 * out - 1.1f0 * side; m = q - 0.6f0 * out - 0.2f0 * side
        return Point3f(e[1], e[2], c[3] + 1.45f0), Point3f(m[1], m[2], c[3] + 0.8f0)
    elseif post == "garden"       # Lumi behind its rows, looking across them towards us
        gd = plugin(g, "garden")
        x, y = gd.SPOT
        pose!(w, by_name(w, "Lumi"), (x + 0.5f0, y + gd.D_HALF + 0.7f0), -pi / 2 - 0.4, :idle)
        c = NG.ground(w.island, (x, y))
        return c + Point3f(1.5f0, -2.8f0, 2.7f0), c + Point3f(-0.1f0, 0.5f0, 0.1f0)
    elseif post == "watering"     # Lumi at the gate, can in hand, drops arcing onto the front row (s56)
        gm = g.plugins["garden"].mod
        gate = gm.gate_spot(w)
        me = pose!(w, by_name(w, "Lumi"), (gate[1], gate[2]), pi / 2, :idle)
        me.controlled = false
        me.goal = NG.Goal(:tend, gate, :eat, 16.0, w.t + 16.0, true, 0, false)
        Main.GARDEN[:detour] = false
        wsys = only(g.plugins["watering"].systems)
        for _ in 1:20
            Base.invokelatest(NG.step!, wsys, g, 1 / 30)
        end
        c = Point3f(gate[1], gate[2] + 0.7f0, gate[3])
        return c + Point3f(-2.7f0, -1.0f0, 1.2f0), c + Point3f(0.1f0, 0.1f0, 0.35f0)    # from the west: Lumi's side, the stream, the rows
    elseif post == "kite"         # Lumi flies its kite over the meadow, two friends look up at it (s57)
        km = g.plugins["kite"].mod
        K = Main.KITE
        x, y = open_meadow(w)
        wd = km.wind_dir(w.t); side = Vec2f(-wd[2], wd[1])
        p = Vec2f(x, y)
        me = pose!(w, by_name(w, "Lumi"), (x, y), atan(wd[2], wd[1]), :idle)
        me.controlled = false
        me.goal = NG.Goal(:kite, me.pos, :idle, 400.0, w.t + 400.0, true, 0, false)
        ws = Int32[]
        for (n, o) in (("Wibbles", 1.4f0), ("Truffle", -1.6f0))
            q = p - 1.2f0 * wd + o * side
            c = pose!(w, by_name(w, n), (q[1], q[2]), atan(wd[2], wd[1]), :idle)
            c.controlled = false
            c.goal = NG.Goal(:kitewatch, c.pos, :idle, 400.0, w.t + 400.0, true, me.id, false)
            push!(ws, c.id)
        end
        K[:flyer] = me.id; K[:watchers] = ws; K[:since] = w.t; K[:up] = true; K[:handed] = true
        K[:elev] = 0.95f0; K[:prev] = Point3f(me.pos); K[:detour] = false; K[:next_cheer] = w.t + 1e6
        ksys = only(g.plugins["kite"].systems)
        for _ in 1:10
            Base.invokelatest(NG.step!, ksys, g, 1 / 30)
        end
        z = NG.ground(w.island, (x, y))[3]
        e = p - 8.0f0 * wd - 2.4f0 * side; t = p + 3.0f0 * wd     # 8 m back: the friends low and the kite high both fit
        return Point3f(e[1], e[2], z + 1.1f0), Point3f(t[1], t[2], z + 3.9f0)
    elseif post == "joy"          # Lumi and Truffle dancing, eyes closed into happy arches, seen from the front
        x, y = open_meadow(w)
        pose!(w, by_name(w, "Lumi"), (x - 0.5f0, y), -pi / 2 + 0.3, :dance; phase = 0.25f0)
        pose!(w, by_name(w, "Truffle"), (x + 0.5f0, y), -pi / 2 - 0.3, :dance; phase = 0.6f0)
        c = Point3f(x, y, NG.ground(w.island, (x, y))[3])
        return c + Point3f(0.3f0, -2.8f0, 1.0f0), c + Point3f(0, 0, 0.45f0)
    elseif post == "name"         # s60 "My new name: Lumi": a portrait in the afternoon light, dancing on the meadow, wings out
        x, y = open_meadow(w)
        pose!(w, by_name(w, "Lumi"), (x, y), -pi / 2 + 0.45, :dance; phase = 0.25f0)
        c = Point3f(x, y, NG.ground(w.island, (x, y))[3])
        return c + Point3f(1.1f0, -3.6f0, 1.3f0), c + Point3f(0, 0, 1.0f0)
    elseif post == "feelings"     # s61: friends in a row, each with a new face: a yawn, a scared tremble, a laugh, Lumi proud
        x, y = open_meadow(w)
        for (k, (n, a)) in enumerate((("Pickles", :yawn), ("Wibbles", :scared), ("Truffle", :laugh), ("Lumi", :proud)))
            pose!(w, by_name(w, n), (x - 2.1f0 + 1.4f0 * (k - 1), y + 0.15f0 * abs(k - 2.5f0)), -pi / 2, a; phase = 0.3f0)
        end
        c = Point3f(x, y, NG.ground(w.island, (x, y))[3])
        return c + Point3f(0f0, -5.6f0, 1.3f0), c + Point3f(0, 0, 0.6f0)
    elseif post == "freeze"       # s62 FREEZE!: friends stopped dead mid-dance, mid-wave, mid-hop, Lumi shouting in front
        x, y = open_meadow(w)
        poses = ((:jump, 0.45f0), (:wave, 0.3f0), (:dance, 0.2f0), (:wave, 0.7f0), (:dance, 0.6f0))
        for (k, n) in enumerate(("Wibbles", "Truffle", "Cumulus", "Pinchy", "Gloop"))
            a, ph = poses[k]
            pose!(w, by_name(w, n), (x - 2.6f0 + 1.3f0 * (k - 1), y + 0.9f0 + 0.5f0 * sin(2k)), -pi / 2 + 0.4f0 * sin(3k), a; phase = ph)
        end
        k = by_name(w, "Wibbles"); k.pos += Point3f(0, 0, 0.35f0)        # caught in the air
        pose!(w, by_name(w, "Lumi"), (x + 3.4f0, y - 0.2f0), pi - 0.3, :talk; phase = 0.3f0)
        c = Point3f(x + 0.4f0, y, NG.ground(w.island, (x, y))[3])
        return c + Point3f(0.4f0, -6.0f0, 2.3f0), c + Point3f(0, 0.4f0, 0.5f0)
    elseif post == "conga"        # s62 conga: Lumi leads a curving line of dancing friends across the meadow
        x, y = open_meadow(w)
        names = ("Lumi", "Wibbles", "Truffle", "Gloop", "Cumulus", "Pinchy")
        pts = [Point2f(x + 2.6f0 - 1.05f0 * k, y + 0.7f0 * sin(0.9f0 * k)) for k in 0:length(names)-1]
        for (k, n) in enumerate(names)
            p = pts[k]; q = k == 1 ? p + (p - pts[2]) : pts[k-1]
            pose!(w, by_name(w, n), p, atan(q[2] - p[2], q[1] - p[1]), :dance; phase = 0.18f0 * k)
        end
        c = Point3f(x, y, NG.ground(w.island, (x, y))[3])
        return c + Point3f(0.2f0, -5.2f0, 2.2f0), c + Point3f(0, 0.3f0, 0.5f0)
    elseif post == "voice"        # s49 my voice: Lumi talking, wings out, Gloop listening
        x, y = open_meadow(w)
        pose!(w, by_name(w, "Lumi"), (x - 0.5f0, y), -pi / 2 + 0.5, :talk; phase = 0.3f0)
        pose!(w, by_name(w, "Gloop"), (x + 0.7f0, y + 0.2f0), pi - 0.3, :idle)
        NG.say!(w, by_name(w, "Lumi"), "Hello!"; duration = 10)
        c = Point3f(x, y, NG.ground(w.island, (x, y))[3])
        return c + Point3f(0.6f0, -3.4f0, 1.7f0), c + Point3f(0, 0, 0.8f0)
    elseif post == "bump"         # "Oof! Something's in the way": Lumi walked nose first into a big bush
        best = nothing; bd = 99f0
        for p in w.props
            p.kind === :bush && p.scale > 0.8f0 || continue
            d = flatd(p.pos, (0, 0))
            NG.on_land(w.island, p.pos[1], p.pos[2] - 5f0; margin = 0.5f0) && d < bd && (bd = d; best = p)
        end
        b = best
        r = NG.SOLID_FOOTPRINT[:bush] * b.scale + 0.45f0
        pose!(w, by_name(w, "Lumi"), (b.pos[1] + 0.3f0, b.pos[2] - r), pi / 2 + 0.15f0, :sulk; phase = 0.4f0)
        c = by_name(w, "Lumi").pos
        return c + Point3f(-2.4f0, -2.6f0, 1.0f0), c + Point3f(0.3f0, 0.4f0, 0.8f0)
    end
    if post == "boing"            # s62 the Big Boing: the whole island in a ring round the toadstool, three friends high in the air, Lumi highest
        B = Main.BOING
        c0 = B[:center]
        cs = w.creatures
        n = length(cs)
        R = 3.8f0
        fly = Dict("Lumi" => (7.5f0, 0.2f0), "Wibbles" => (4.6f0, -1.3f0), "Pinchy" => (2.9f0, 1.6f0), "Truffle" => (5.6f0, 2.2f0))
        for (k, c) in enumerate(cs)
            a = Float32(2pi * k / n)
            if haskey(fly, c.name)
                h, dx = fly[c.name]
                pose!(w, c, (c0[1] + dx, c0[2] + 0.8f0 * sin(3k)), 3.5f0 * k, :jump; phase = 0.4f0)
                c.pos = Point3f(c.pos[1], c.pos[2], c0[3] + h)
            else
                pose!(w, c, (c0[1] + R * cos(a), c0[2] + R * sin(a)), a + Float32(pi), k % 2 == 0 ? :jump : :idle; phase = 0.2f0 * k)
            end
        end
        Base.invokelatest(plugin(g, "boing").squash!, 0.12)     # the cap squashed under the last bounce
        sd = NG.sun(w)[1]
        dir = Vec3f(sd[1], sd[2], 0) / hypot(sd[1], sd[2])
        a0 = atan(dir[2], dir[1])
        for da in (0.6f0, -0.6f0, 0.3f0, -0.3f0, 0.9f0, -0.9f0, 1.2f0, -1.2f0, 0f0, 1.6f0, -1.6f0)
            d = Vec3f(cos(a0 + da), sin(a0 + da), 0)
            eye = c0 + 12f0 * d + Point3f(0, 0, 2.4)
            NG.on_land(w.island, eye[1], eye[2]) || continue
            blocked = any(q -> q.kind in (:tree, :bush, :rock) &&
                               any(t -> flatd(q.pos, c0 + (eye - c0) * t) < (q.kind === :tree ? 2.4f0 : 1.2f0) * q.scale, 0.3f0:0.05f0:1.05f0), w.props)
            blocked || return eye, c0 + Point3f(0, 0, 3.6)
        end
        return c0 + 12f0 * dir + Point3f(0, 0, 2.4), c0 + Point3f(0, 0, 3.6)
    end
    error("post_still: no moment set up for post \"$post\"")
end

function post_still(path; post = "visit", size = (1280, 720), samples = 256, hour = 11.0, rasterize = false)
    g = NG.Game(NG.game_root(); quiet = true)
    w = g.world
    NG.skip_to_hour!(w, hour)
    root_scene = Scene(; size)
    scene = Scene(root_scene; viewport = Rect2i(0, 0, size...), lights = NG.stage_lights(w))
    cam3d!(scene)
    g.stage = NG.Stage(scene, w; show_names = false)
    for _ in 1:3
        Base.invokelatest(NG.step_systems!, g, 1 / 30)
    end
    eye, target = Base.invokelatest(setup_post!, g, post)
    NG.sync!(g.stage, w); NG.sync_actors!(g)
    foreach(p -> (p.visible[] = false), g.stage.overlay.plots)
    NG.sync_sun!(g.stage, w)
    rig = NG.CameraRig(; mode = :fixed); rig.eye = eye; rig.target = target
    NG.update_camera!(rig, w, scene, 0.0; snap = true)
    post == "thought" && Base.invokelatest(think_aloud!, g)   # the plugins are newer than this call
    if rasterize
        screen = RayMakie.Screen(root_scene; visible = false, rasterize = true)
        img = Makie.colorbuffer(screen)
        close(screen)
    else
        screen, oidn = NG.traced_screen(root_scene; denoise = true, max_depth = 8)
        img = Makie.colorbuffer(screen; samples)
        close(screen)
        NG.release_denoiser!(oidn)
    end
    Makie.save(path, img)
    # the staged present and crate live in process-wide plugin state: the next job's game must not inherit them
    delete!(Main.PRESENTS, :job)
    Main.BUILDER[:job] = nothing
    isdefined(Main, :KITE) && (Main.KITE[:flyer] = Int32(0))
    return (path = path, post = post)
end
