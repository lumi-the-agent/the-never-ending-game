const SPECIES_NG = NeverendingGame

uitest("Piglets and crabbits stand on real legs that stride when they walk") do game
    NG = SPECIES_NG
    for (name, nlegs) in (("Snootle", 2), ("Crabbit", 3))
        sp = NG.SPECIES[name]
        h = get(game.stage.herds, name, nothing)
        check(h === nothing || h.species[] === sp, "the $name herd draws an old body")
        body = only(filter(p -> p.name === :body, sp.parts))
        legs = filter(p -> p.motion isa NG.Step, sp.parts)
        check(length(legs) == nlegs && all(p -> p.mirror, legs), "$name has $(length(legs)) leg parts, want $nlegs mirrored")
        # the body sits up off the ground: its underside is above the legs' feet by a leg's length
        under = body.offset[3] - body.scale[3]
        check(under > 0.15f0, "$name's body hangs at $(under) m: stub feet again")
        check(all(p -> p.scale[3] >= 0.1f0, legs), "$name's legs are stubs: $([p.scale[3] for p in legs])")
    end
    # a walking piglet's legs are in a different place 0.3 s later
    w = game.world
    c = first(filter(c -> c.species == "Snootle" && !c.controlled, w.creatures))
    sp = NG.SPECIES["Snootle"]
    pose(c) = (out = [(Point3f[], NG.Makie.Quaternionf[], Vec3f[]) for _ in sp.parts];
               NG.pose_parts!(out, sp, c.pos, c.yaw, :walk, c.phase, c.mood, c.extra, c.seed, Float32(w.t)); out)
    a = pose(c)
    c2 = deepcopy(c); c2.phase += 0.3f0 * sp.speed * sp.stride
    b = pose(c2)
    legs = findall(p -> p.motion isa NG.Step, sp.parts)
    moved = maximum(maximum(sqrt(sum(abs2, a[i][1][k] - b[i][1][k])) for k in eachindex(a[i][1])) for i in legs)
    check(moved > 0.03f0, "the legs do not move with the walk (max $(moved) m)")
end
