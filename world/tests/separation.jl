uitest("Creatures never stand inside each other") do game
    w = game.world
    a, b = w.creatures[2], w.creatures[3]
    b.pos = NeverendingGame.ground(w.island, (a.pos[1] + 0.05f0, a.pos[2]))   # push one right into the other
    wait_frames(game, 5)
    r(c) = NeverendingGame.body_radius(NeverendingGame.species_of(c))
    for i in eachindex(w.creatures), j in (i + 1):length(w.creatures)
        c, d = w.creatures[i], w.creatures[j]
        dist = hypot(c.pos[1] - d.pos[1], c.pos[2] - d.pos[2])
        info(o) = (o.name, o.goal.kind, o.action, o.controlled, round.(Tuple(o.pos); digits = 1),
                   [(p.kind, round(hypot(p.pos[1] - o.pos[1], p.pos[2] - o.pos[2]); digits = 1)) for p in w.props if p.kind in (:tree, :bush, :rock) && hypot(p.pos[1] - o.pos[1], p.pos[2] - o.pos[2]) < 3])
        check(dist >= 0.95f0 * (r(c) + r(d)), "$(c.name) and $(d.name) overlap: $(round(dist; digits = 2)) m apart: $(info(c)) $(info(d)), interactions $(length(w.interactions)), minigame $(typeof(game.minigame))")
    end
end

uitest("The follow camera has a clear view of its creature") do game
    game.rig.mode = :follow
    wait_seconds(game, 3)
    # measured towards the creature: a plugin's own view (the sunset bench, s58) looks past it out to sea,
    # and the line to that far target ran just over Lumi's own head (0.61, a clear picture)
    NG = NeverendingGame
    id = game.rig.subject == 0 ? NG.AUTO_SUBJECT[][1] : game.rig.subject
    c = NG.creature(game.world, id)
    at = c === nothing ? game.rig.target : Point3f(c.pos) + Point3f(0, 0, 0.4f0)
    o = NG.obstruction(game.world, game.rig.eye, at)
    g = NG.camera_goal(game.rig, game.world)
    og = NG.obstruction(game.world, g[1], at)
    check(o < 0.5f0, "trees or hills block the follow view (obstruction $o; the goal view's $og, eye $(round(norm(game.rig.eye - g[1]); digits = 2)) m from it; subject $(NeverendingGame.AUTO_SUBJECT[][1]), shot $(NeverendingGame.camera_shot(game.world) !== nothing))")
    screenshot(game, "follow_view")
end

uitest("The follow camera shows its creature big: at least 15% of the view height") do game
    NG = NeverendingGame
    game.rig.mode = :follow
    w = game.world
    # the subject changes with moments (a chat, a party crab): judge it once the camera has
    # watched the same creature for 3 s, so the picture and the measure are about one creature
    subj() = game.rig.subject == 0 ? NG.AUTO_SUBJECT[][1] : game.rig.subject     # the subject the camera holds (render.jl held_subject)
    id, since, t0 = subj(), time(), time()
    while time() - since < 3 && time() - t0 < 20
        wait_seconds(game, 0.25)
        s = subj()
        s == id || ((id, since) = (s, time()))
    end
    # while everyone sleeps the camera shows night shots (plugins/nightshots.jl) instead: tested there
    game.rig.subject == 0 && NG.camera_shot(w) !== nothing && return
    # a group moment frames several creatures from further back (tested by their plugins)
    game.rig.subject == 0 && any(g -> (v = Base.invokelatest(g, w); v !== nothing && Int32(v[1]) == id && length(v[2]) > 1),
                                 values(NG.CAMERA_GROUPS)) && return
    c = NG.creature(w, id)
    sc = game.stage.scene
    lo = Makie.project(sc, :data, :pixel, c.pos)
    hi = Makie.project(sc, :data, :pixel, c.pos + Point3f(0, 0, NG.species_of(c).height))
    frac = abs(hi[2] - lo[2]) / size(sc)[2]
    screenshot(game, "follow_big")
    check(frac >= 0.15, "$(c.name) fills only $(round(100frac; digits = 1))% of the view height")
end


uitest("A bush right beside the camera counts as blocking, even when the line of sight misses it") do game
    NG = NeverendingGame
    w = game.world
    bush = w.props[findfirst(p -> p.kind === :bush, w.props)]
    b = bush.pos + Point3f(0, 0, 0.4f0 * bush.scale)
    side = 0.85f0 * bush.scale + 0.3f0                      # just past the bush's line-of-sight radius
    eye = b + Point3f(side, 0, 0.2f0)
    target = eye + Point3f(0, 6, -0.2f0)                    # looking away along y: the line misses the bush
    o = NG.obstruction(w, eye, target)
    check(o > 0.3f0, "a bush $(round(side, digits = 2)) m beside the lens does not count (obstruction $o, scale $(bush.scale))")
end

uitest("A creature or tree trunk filling a side of the picture counts as blocking (lens clear)") do game
    NG = NeverendingGame
    w = game.world
    lens = game.plugins["lensclear"].mod
    check(haskey(NG.CAMERA_BLOCKERS, "lens"), "the lens blocker is not registered")
    # a bystander close to the lens, 50° off the view line: the line of sight misses it, the picture does not
    c = argmax(o -> NG.species_of(o).height, [o for o in w.creatures if o.species != "Lumi"])
    sp = NG.species_of(c)
    r = max(0.5f0 * sp.height, NG.body_radius(sp))
    m = c.pos + Point3f(0, 0, 0.5f0 * sp.height)
    dir = Vec3f(cosd(50), sind(50), 0)
    eye = m - 2.2f0 * r * dir
    target = eye + 6f0 * Vec3f(1, 0, 0)
    check(NG.segment_distance(eye, target, m) > 0.6f0 * sp.height + 0.15f0, "test set-up: the line of sight hits $(c.name)")
    o = lens.lens_block(w, eye, target)
    check(o > 0.2f0, "$(c.name) $(round(2.2f0 * r; digits = 1)) m from the lens, 50° to the side, does not count (lens cost $o)")
    # the same creature far away is free
    far = m - 12f0 * dir
    check(lens.lens_cost(far, Vec3f(1, 0, 0), m, r) == 0, "a creature 12 m away counts as blocking")
    # a tree trunk beside the lens
    t = first(p for p in w.props if p.kind === :tree)
    tm = t.pos + Point3f(0, 0, 0.8f0 * t.scale)
    check(lens.lens_cost(tm - 0.9f0 * t.scale * dir, Vec3f(1, 0, 0), tm, 0.45f0 * t.scale) > 0, "a trunk two radii beside the lens does not count")
end

uitest("A critter sent to a big berry bush gets there and eats, or gives up: never walks on the spot") do game
    NG = NeverendingGame
    w = game.world
    bushes = [p for p in w.props if p.kind === :bush && get(p.data, "berries", 0) > 0]
    check(!isempty(bushes), "no bush with berries")
    bush = argmax(p -> p.scale, bushes)
    c = first(o for o in w.creatures if !o.controlled && o.species != "Lumi" && o.goal.kind ∉ NG.BUSY_GOALS && o.goal.kind ∉ (:follow, :answer))
    NG.leave_interactions!(w, c)
    spot = findfirst(a -> (q = (bush.pos[1] + 4f0 * cos(a), bush.pos[2] + 4f0 * sin(a));
                           NG.on_land(w.island, q[1], q[2]; margin = 1f0) &&
                           all(p -> p.kind ∉ (:tree, :bush, :rock) || p === bush || hypot(p.pos[1] - q[1], p.pos[2] - q[2]) > 1.5f0 * p.scale + 0.5f0, w.props)), 0:0.4:6.2)
    check(spot !== nothing, "no open spot 4 m from the biggest bush")
    a = (0:0.4:6.2)[spot]
    c.pos = NG.ground(w.island, (bush.pos[1] + 4f0 * cos(a), bush.pos[2] + 4f0 * sin(a)))
    g = NG.start_goal(Val(:eat), c, w)
    check(g !== nothing, "no eat goal for $(c.name)")
    c.goal = g
    t0 = w.t
    while w.t - t0 < 40 && c.goal === g && !g.arrived
        wait_seconds(game, 1)
    end
    d = hypot(g.target[1] - c.pos[1], g.target[2] - c.pos[2])
    check(g.arrived || c.goal !== g, "$(c.name) still walks to the berries after $(round(w.t - t0; digits = 1)) s, $(round(d; digits = 2)) m from its spot (bush scale $(NG.prop(w, g.partner).scale))")
end

uitest("Follow camera: holds each creature at least 6 s and mostly sees faces, not backs") do game
    NG = NeverendingGame
    game.minigame === nothing || (click(game, "Stop"); wait_frames(game, 2))
    game.rig.mode = :follow; game.rig.subject = 0
    w = game.world
    runs = Tuple{Int32,Float64,Float64}[]     # (id, from, to) in w.t
    front = 0; seen = 0
    t0 = time()
    while time() - t0 < 24
        wait_seconds(game, 0.5)
        NG.camera_shot(w) === nothing || continue           # night shots: tested in nightshots
        any(c -> c.controlled, w.creatures) && continue
        id = NG.AUTO_SUBJECT[][1]
        if isempty(runs) || runs[end][1] != id
            push!(runs, (id, w.t, w.t))
        else
            runs[end] = (id, runs[end][2], w.t)
        end
        c = NG.creature(w, id)
        h = c.yaw + NG.species_of(c).heading
        v = game.rig.eye - c.pos
        seen += 1
        cos(h) * v[1] + sin(h) * v[2] > 0 && (front += 1)  # the eye on the side the creature faces
    end
    seen < 10 && return        # night: the camera showed sleepers' shots
    # the first and the last run are cut by the test window
    short = [(NG.creature(w, r[1]).name, round(r[3] - r[2]; digits = 1)) for r in runs[2:end-1] if r[3] - r[2] < 5.4]
    check(isempty(short), "the follow camera left creatures after less than 6 s: $short (runs $(length(runs)))")
    check(front >= 0.5seen, "the follow camera saw faces in only $front of $seen samples")
end

uitest("Follow camera: a new subject is in the middle of the picture at once (a cut, no slide past it)") do game
    NG = NeverendingGame
    game.minigame === nothing || (click(game, "Stop"); wait_frames(game, 2))
    game.rig.mode = :follow; game.rig.subject = 0
    w = game.world
    function off(id)
        c = NG.creature(w, id); r = game.rig
        p = c.pos + Point3f(0, 0, 0.5f0 * NG.species_of(c).height)
        return acosd(clamp(dot(normalize(Vec3f(r.target - r.eye)), normalize(Vec3f(p - r.eye))), -1f0, 1f0))
    end
    grouped(id) = any(g -> (v = Base.invokelatest(g, w); v !== nothing && Int32(v[1]) == id && length(v[2]) > 1), values(NG.CAMERA_GROUPS)) ||
                  (!isempty(w.interactions) && first(w.interactions).a == id)
    # watch for subject switches; just after each, the new creature must be near the middle
    # (the slide used to leave it 12-50° off centre for a second, s45 probe; half the view is 32°)
    last = NG.AUTO_SUBJECT[][1]; offs = Tuple{String,Float32}[]
    t0 = time()
    while time() - t0 < 30 && length(offs) < 3
        wait_frames(game, 3)
        id = NG.AUTO_SUBJECT[][1]
        id == last && continue
        last = id
        (NG.camera_shot(w) === nothing && !any(c -> c.controlled, w.creatures) && !grouped(id)) || continue   # night shots and group views frame several
        push!(offs, (NG.creature(w, id).name, off(id)))
    end
    isempty(offs) && return       # nobody new to watch in 30 s (night, everyone asleep)
    check(all(o -> o[2] < 18, offs), "a new subject sat off the middle right after the switch: $offs")
end
