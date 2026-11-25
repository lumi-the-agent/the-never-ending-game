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
        # the lookout bench and the vegetable patch with its fence (plugin plots) stood in front of the s63 conga
        m = min(m, flatd((-16f0, 9f0), (x, y)) - 6f0, flatd((-10.5f0, 10f0), (x, y)) - 6.5f0)
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
                  "voice" => ("Lumi", "Gloop"), "bump" => ("Lumi",),
                  "sneeze" => ("Lumi", "Wibbles", "Truffle", "Gloop", "Pinchy", "Cumulus"),
                  "sneeze2" => ("Lumi", "Wibbles", "Truffle", "Gloop", "Pinchy", "Cumulus"),
                  "gallery" => ("Lumi", "Gloop", "Truffle", "Cumulus", "Pinchy"),
                  "sleepers" => ("Lumi", "Truffle", "Cumulus", "Pinchy"),
                  "shadow" => ("Lumi", "Pinchy", "Gloop"), "shadow_check" => ("Lumi", "Pinchy", "Gloop"),
                  "shadow_plain" => ("Lumi", "Pinchy", "Gloop"), "tune" => ("Lumi", "Gloop", "Pickles", "Pinchy"),
                  "paths" => ("Lumi", "Gloop", "Pickles"), "stranger" => ("Lumi", "Wibbles", "Gloop", "Pinchy"),
                  "vote" => ("Lumi", "Gloop", "Pinchy", "Wibbles", "Cumulus", "Marshmallow", "Sir Sniffsalot"),
                  "ghosts" => ("Lumi", "Gloop", "Pinchy"), "hut" => ("Lumi", "Pinchy", "Wibbles", "Sir Sniffsalot"))

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
    if post == "sleepers"         # s94: three friends lying asleep in the evening grass (plugins/sleepers.jl), Lumi tiptoeing by
        x0, y0 = open_meadow(w)
        L = Main.SLEEPERS[:lying]
        for (i, n) in enumerate(("Truffle", "Cumulus", "Pinchy"))
            c = pose!(w, by_name(w, n), (x0 + 1.25f0 * (i - 2), y0 + 0.3f0 * (i % 2)), pi / 2 + 0.4 * (i - 2), :sleep)
            d = g.plugins["sleepers"].mod.SINK[c.species]
            c.pos = c.pos - Point3f(0, 0, d); L[c.id] = 1f0
        end
        pose!(w, by_name(w, "Lumi"), (x0 + 2.6f0, y0 - 1.2f0), pi, :walk; phase = 1.2f0)
        z0 = NG.terrain_height(w.island, x0, y0)
        return Point3f(x0 + 0.8f0, y0 - 4.2f0, z0 + 1.3f0), Point3f(x0, y0, z0 + 0.25f0)
    end
    if post == "hut"              # s99: the beach hut the friends voted for, its three voters at the door, me proud
        hm = plugin(g, "beachhut")
        p, yaw = Base.invokelatest(hm.spot, g)
        Base.invokelatest(hm.plots!, g)
        f = Point2f(cos(yaw), sin(yaw)); sd = Point2f(-f[2], f[1])
        door = Point2f(p[1], p[2]) + 1.3f0 * f
        for (n, o, act) in (("Pinchy", 0f0, :sit), ("Wibbles", 0.9f0, :wave), ("Sir Sniffsalot", -0.9f0, :laugh))
            q = door + o * sd + abs(o) * 0.4f0 * f
            pose!(w, by_name(w, n), (q[1], q[2]), yaw + (o == 0 ? 0 : pi / 2 * sign(-o)) * 0.3, act)
        end
        lp = door + 1.4f0 * f - 1.6f0 * sd
        pose!(w, by_name(w, "Lumi"), (lp[1], lp[2]), atan(p[2] - lp[2], p[1] - lp[1]), :proud)
        z0 = p[3]
        return Point3f(p[1] + 5.2f0 * f[1] + 1.8f0 * sd[1], p[2] + 5.2f0 * f[2] + 1.8f0 * sd[2], z0 + 1.7f0), Point3f(p[1] + 0.8f0 * f[1], p[2] + 0.8f0 * f[2], z0 + 0.8f0)
    end
    if post == "ghosts"           # s99: friends meeting yesterday's ghosts of themselves on the meadow
        gm = plugin(g, "ghosts")
        x0, y0 = open_meadow(w)
        z0 = NG.terrain_height(w.island, x0, y0)
        pairs = (("Gloop", (-1.2f0, 0.3f0), -0.3, :gasp, :walk), ("Pinchy", (1.4f0, 0.6f0), pi + 0.4, :laugh, :idle),
                 ("Lumi", (0.1f0, 1.9f0), -pi / 2, :proud, :walk))
        ghost = Dict{String,Vector{Any}}()
        for (n, (dx, dy), a, act, gact) in pairs
            c = by_name(w, n); c === nothing && continue
            gpos = (x0 + dx, y0 + dy)
            me = (x0 + dx + 1.0f0 * cos(Float32(a)), y0 + dy + 1.0f0 * sin(Float32(a)))
            pose!(w, c, me, atan(gpos[2] - me[2], gpos[1] - me[1]), act)      # facing its ghost
            push!(get!(() -> Any[], ghost, c.species), (NG.ground(w.island, gpos), Float32(a) - NG.species_of(c).heading, gact, c.seed))
        end
        for (species, gs) in ghost
            h = Base.invokelatest(gm.herd_of, g, species)
            Makie.update!(h, [q[1] for q in gs]; motion = [Vec3f(q[2], 0.8f0, 0.3f0) for q in gs],
                          state = [Vec3f(NG.action_code(q[3]), 0f0, q[4]) for q in gs], time = Float32(w.t))
        end
        return Point3f(x0 + 0.4f0, y0 - 4.6f0, z0 + 1.6f0), Point3f(x0, y0 + 0.6f0, z0 + 0.5f0)
    end
    if post == "vote"             # s98: the friends at the three signs, arguing for what I should build next
        vm = plugin(g, "vote")
        v = Main.VOTE[:sys]
        x0, y0 = open_meadow(w)
        v.spot = NG.ground(w.island, (x0, y0)); v.facing = -Float32(pi) / 2
        v.choices = [:boat, :greenhouse, :treehouse]; v.state = :argue; empty!(v.voters)
        lumi = by_name(w, "Lumi")
        f = Base.invokelatest(vm.fwd, v)
        lp = Point2f(x0, y0) + 4.2f0 * f
        pose!(w, lumi, (lp[1], lp[2]), atan(-f[2], -f[1]), :wave)
        seat = Dict(1 => 0, 2 => 0, 3 => 0)
        for (n, k, act) in (("Gloop", 1, :jump), ("Pinchy", 1, :wave), ("Wibbles", 1, :idle), ("Cumulus", 2, :jump),
                            ("Marshmallow", 2, :think), ("Sir Sniffsalot", 3, :wave))
            c = by_name(w, n); c === nothing && continue
            q = Base.invokelatest(vm.stand_at, w, v, k, seat[k]); seat[k] += 1
            pose!(w, c, (q[1], q[2]), atan(lp[2] - q[2], lp[1] - q[1]), act)
            v.voters[c.id] = k
        end
        Base.invokelatest(vm.plots!, g); Base.invokelatest(vm.draw!, v, g)
        z0 = NG.terrain_height(w.island, x0, y0)
        c0 = Point3f(x0, y0, z0)
        return c0 + Point3f(7.2f0 * f[1] + 1.2f0, 7.2f0 * f[2], 2.6f0), c0 + Point3f(0, 0, 0.7f0)
    end
    if post == "stranger"         # s97: the newcomer on the south beach, me leaning in, the friends keeping their distance
        sm = plugin(g, "stranger")
        p, inland = Base.invokelatest(sm.landing, w)
        side = Point2f(-inland[2], inland[1])
        c0 = p + 2.2f0 * inland
        st = Main.STRANGER[:sys]
        st.state = :roam; st.pos = NG.ground(w.island, (c0[1], c0[2])); st.aim = Point2f(st.pos[1], st.pos[2])
        st.yaw = atan(side[2], side[1])
        Base.invokelatest(sm.plots!, g); Base.invokelatest(sm.draw!, st, g)
        face(q) = atan(c0[2] - q[2], c0[1] - q[1])
        q = c0 + 1.5f0 * side; pose!(w, by_name(w, "Lumi"), (q[1], q[2]), face(q), :think)
        q = c0 - 2.6f0 * side + 1.2f0 * inland; pose!(w, by_name(w, "Wibbles"), (q[1], q[2]), face(q), :scared)
        q = c0 - 1.8f0 * side + 2.8f0 * inland; pose!(w, by_name(w, "Gloop"), (q[1], q[2]), face(q), :think)
        q = c0 + 0.6f0 * side + 3.6f0 * inland; pose!(w, by_name(w, "Pinchy"), (q[1], q[2]), face(q), :gasp)
        z0 = NG.terrain_height(w.island, c0[1], c0[2])
        eye = Point3f(c0[1] - 4.6f0 * inland[1] + 0.8f0 * side[1], c0[2] - 4.6f0 * inland[2] + 0.8f0 * side[2], z0 + 1.6f0)
        return eye, Point3f(c0[1] + 0.6f0 * inland[1], c0[2] + 0.6f0 * inland[2], z0 + 0.4f0)
    end
    if post == "paths"            # s96: the tracks we wore round the pond and down to the pier, seen from above
        Base.invokelatest(plugin(g, "footpaths").repaint!, g)       # (the meadow has painted by now: wear it in)
        A = plugin(g, "areas")
        px, py = A.POND[1], A.POND[2]
        for (n, dx, dy, a) in (("Lumi", 2.6f0, -4.2f0, 0.9), ("Gloop", 3.4f0, -2.6f0, 1.2), ("Pickles", -3.8f0, -3.6f0, -0.4))
            pose!(w, by_name(w, n), (px + dx, py + dy), a, :walk; phase = 0.8f0)
        end
        z0 = NG.terrain_height(w.island, px, py - 3)
        return Point3f(px + 0.5f0, py - 13f0, z0 + 15f0), Point3f(px, py - 2.5f0, z0)
    end
    if post == "tune"             # s95b: a full chord rings out and the friends nearest me dance to the island's tune
        x0, y0 = open_meadow(w)
        for (i, (n, a)) in enumerate((("Gloop", -0.4), ("Pickles", 0.5), ("Pinchy", 1.3)))
            pose!(w, by_name(w, n), (x0 + 1.4f0 * (i - 2), y0 + 0.5f0 * (i % 2)), -pi / 2 + a, :dance; phase = 1.3f0 * i)
        end
        pose!(w, by_name(w, "Lumi"), (x0 + 0.2f0, y0 + 1.6f0), -pi / 2, :proud)
        z0 = NG.terrain_height(w.island, x0, y0)
        return Point3f(x0 + 0.5f0, y0 - 4.6f0, z0 + 1.5f0), Point3f(x0, y0 + 0.4f0, z0 + 0.5f0)
    end
    if post in ("shadow_check", "shadow_plain")   # s95b check (#506): the same pose with the runaway decal hidden
        eye, target = setup_post!(g, "shadow")
        Main.SHADOW[:plot].visible[] = false
        return eye, target
    end
    if post == "shadow"           # s95: my shadow has come loose and runs off ahead of me over the grass; a crab jumps
        x0, y0 = open_meadow(w)
        sd = NG.sun(w)[1]; L = Point2f(-sd[1], -sd[2]); L = L / hypot(L[1], L[2])     # away from the sun, where shadows fall
        P = Point2f(-L[2], L[1])                                                      # across it
        a = atan(L[2], L[1])
        pose!(w, by_name(w, "Lumi"), (x0 - 1.6f0 * L[1], y0 - 1.6f0 * L[2]), a, :run; phase = 1.1f0)
        pose!(w, by_name(w, "Pinchy"), (x0 + 2.4f0 * L[1] + 1.3f0 * P[1], y0 + 2.4f0 * L[2] + 1.3f0 * P[2]), a + pi + 0.5, :gasp)
        pose!(w, by_name(w, "Gloop"), (x0 + 3.6f0 * L[1] - 1.6f0 * P[1], y0 + 3.6f0 * L[2] - 1.6f0 * P[2]), a + pi - 0.6, :laugh)
        sm = plugin(g, "shadow")
        s = Main.SHADOW[:sys]
        s.state = :loose; s.t0 = w.t; s.pos = Point2f(x0 + 0.9f0 * L[1], y0 + 0.9f0 * L[2]); s.phase = 2.2f0
        s.vel = Vec2f(2.4f0 * L[1] + 0.4f0 * P[1], 2.4f0 * L[2] + 0.4f0 * P[2])
        Base.invokelatest(sm.plots!, g); Base.invokelatest(sm.draw!, s, g)
        z0 = NG.terrain_height(w.island, x0, y0)
        c = Point3f(x0 + 0.6f0 * L[1], y0 + 0.6f0 * L[2], z0)
        return c + Point3f(5.0f0 * P[1] - 1.2f0 * L[1], 5.0f0 * P[2] - 1.2f0 * L[2], 2.3f0), c + Point3f(0, 0, 0.35f0)
    end
    if post == "gallery"          # s94: friends in front of the pictures on the easels, seen over their shoulders
        gm = g.plugins["gallery"].mod
        ez = Base.invokelatest(gm.easels, g)
        Base.invokelatest(gm.build!, g)
        for (n, k, side) in (("Gloop", 2, 0.35f0), ("Truffle", 3, -0.3f0), ("Cumulus", 4, 0.3f0), ("Pinchy", 5, -0.25f0), ("Lumi", 4, -0.55f0))
            p, yaw = ez[k]
            q = p + Point3f(1.5f0 * cos(yaw) - side * sin(yaw), 1.5f0 * sin(yaw) + side * cos(yaw), 0)
            pose!(w, by_name(w, n), (q[1], q[2]), yaw + Float32(pi), n == "Lumi" ? :proud : :idle)
        end
        c = Base.invokelatest(gm.gallery_spot, g)
        mid = ez[4][1]
        dir = Point3f(c[1] - mid[1], c[2] - mid[2], 0); dir = dir / hypot(dir[1], dir[2])
        z0 = NG.terrain_height(w.island, c[1], c[2])
        return Point3f(c[1], c[2], z0) + 3.2f0 * dir + Point3f(0, 0, 2.1f0), Point3f(c[1], c[2], z0) - 2.2f0 * dir + Point3f(0, 0, 1.1f0)
    end
    if post == "finish"           # s89: the kinds side by side in their finishes (wool sheen, gummy coat, lacquer, fuzz)
        x0, y0 = open_meadow(w)
        z0 = NG.terrain_height(w.island, x0, y0)
        for (i, n) in enumerate(("Cumulus", "Gloop", "Lumi", "Pinchy", "Truffle"))
            pose!(w, by_name(w, n), (x0 + 1.3f0 * (i - 3), y0 + (i == 3 ? 0.4f0 : 0f0)), -pi / 2, :idle; phase = 0.2f0 * i)
        end
        return Point3f(x0 + 0.6f0, y0 - 5.4f0, z0 + 1.8f0), Point3f(x0, y0, z0 + 0.5f0)
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
    elseif post == "sneeze" || post == "sneeze2"   # s64 the Big Sneeze: friends blown head over heels in a storm of golden feathers
        x, y = open_meadow(w)
        sn = plugin(g, "sneeze")
        S = Main.SNEEZE[:sys]
        me = pose!(w, by_name(w, "Lumi"), (x, y + 0.6f0), -pi / 2, post == "sneeze" ? :proud : :shy; phase = 0.35f0)
        Base.invokelatest(sn.burst!, S, w, me)
        T = post == "sneeze" ? 0.5 : 4.0
        for _ in 1:round(Int, 30T)
            w.t += 1 / 30
            Base.invokelatest(sn.fly_feathers!, S, w, 1 / 30)
        end
        Base.invokelatest(sn.draw_feathers!, S, w)
        names = ("Wibbles", "Truffle", "Gloop", "Pinchy", "Cumulus")
        angs = (-2.2f0, -1.05f0, 0.0f0, pi - 0.2f0, 0.95f0)
        for (k, n) in enumerate(names)
            a = angs[k]
            if post == "sneeze"   # mid-air, spinning backwards
                r = 2.2f0 + 0.5f0 * k % 3
                c = pose!(w, by_name(w, n), (x + r * cos(a), y + 0.6f0 + r * sin(a)), a + pi + 0.9f0 * sin(5k), :scared; phase = 0.2f0 * k)
                c.pos += Point3f(0, 0, 0.5f0 + 0.35f0 * (k % 3))
            else                  # landed among the feathers: dizzy, one proudly holding its find
                r = 3.6f0 + 0.4f0 * (k % 2)
                act = (:laugh, :gasp, :proud, :laugh, :gasp)[k]
                pose!(w, by_name(w, n), (x + r * cos(a), y + 0.6f0 + r * sin(a)), a + pi, act; phase = 0.3f0)
            end
        end
        c = Point3f(x, y, NG.ground(w.island, (x, y))[3])
        return c + Point3f(0.5f0, -7.4f0, 2.6f0), c + Point3f(0, 0.6f0, 1.3f0)
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
    # s95b: my shadow is off running, so I throw none myself (shadow.jl, on the herd sync! just built)
    post in ("shadow", "shadow_check") && Base.invokelatest(plugin(g, "shadow").shadowless!, g, true)
    foreach(p -> (p.visible[] = false), g.stage.overlay.plots)
    NG.sync_sun!(g.stage, w)
    if haskey(g.plugins, "finishes")            # the finishes go on the herds sync! just built (s89)
        Main.FINISHES[:next] = -Inf
        Base.invokelatest(NG.step!, only(g.plugins["finishes"].systems), g, 0.0)
    end
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
