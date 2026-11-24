const BM_NG = NeverendingGame

# Lumi's own moves (s59, engine bird.jl `Birdy`): the feet stay on the ground while it struts,
# the upper body fidgets while it waits, and the live herd draws them.
uitest("Lumi the bird struts with its feet on the ground and fidgets while it waits") do game
    sp = game.stage.herds["Lumi"].species[]
    check(all(p -> p.motion isa BM_NG.Birdy, sp.parts), "the live Lumi parts are not Birdy: $([typeof(p.motion) for p in sp.parts])")
    legs = findall(p -> p.name in (:leg_l, :leg_r), sp.parts)
    body = findfirst(p -> p.name === :body, sp.parts)
    foot(o, j) = o[j][1][1][3] + minimum(q -> (o[j][2][1] * (o[j][3][1] .* q))[3], BM_NG.GeometryBasics.coordinates(BM_NG.SHAPES[sp.parts[j].shape]))
    pose(a, ph, t; mood = 0f0) = BM_NG.pose_parts!([(Point3f[], Makie.Quaternionf[], Vec3f[], Any[]) for _ in sp.parts],
                                                     sp, Point3f(0), 0f0, a, ph, mood, 0.3f0, 0.37f0, t)
    # walking: the lowest foot point stays within 3 cm of the ground over a whole stride
    lows = [minimum(foot(pose(:walk, ph, 0f0), j) for j in legs) for ph in 0f0:0.2f0:6.3f0]
    check(maximum(abs, lows) < 0.03f0, "the feet leave the ground while walking: lowest foot z $(extrema(lows))")
    # the upper body pumps forward and back with the steps
    tilt(o) = (q = o[body][2][1]; 2 * atan(sqrt(q.data[1]^2 + q.data[2]^2 + q.data[3]^2), q.data[4]))
    pumps = [tilt(pose(:walk, ph, 0f0)) for ph in 0f0:0.2f0:3.2f0]
    check(maximum(pumps) - minimum(pumps) > 0.1f0, "no strut: body tilt range $(extrema(pumps))")
    # waiting: within 14 s it fidgets (the body turns by more than 0.2 rad at some point)
    moves = [tilt(pose(:idle, 0f0, t)) for t in 0f0:0.25f0:14f0]
    check(maximum(moves) > 0.2f0, "no fidget in 14 s of waiting: max tilt $(maximum(moves))")
    # a fresh stop (extra 1 → 0, plugins/birdbody.jl) rocks the body over the hips, back and forth
    rock = [BM_NG.bird_upper(BM_NG.PoseCtx(:idle, 0f0, 0f0, Float32(e), 0.5f0, 3.5f0, 1f0))[1].data[2] for e in 1:-0.1:0]
    check(maximum(rock) > 0.08f0 && minimum(rock) < -0.03f0, "no rocking after a stop: $(rock)")
    check(isdefined(game.plugins["birdbody"].mod, :settle!), "birdbody plugin without settle!")
    # live: the sandbox's Lumi is drawn by a herd of Birdy parts and the frame keeps going
    wait_seconds(game, 2)
    screenshot(game, "birdmoves")
end

# Lumi's crest and wings (s60, engine bird.jl `Crest`, `Wing`): own parts of the live body; the crest
# flops after a stop and hangs when Lumi is low, the wings spread wide when it is proud.
uitest("Lumi's crest flops after a stop and its wings spread when it is proud") do game
    sp = game.stage.herds["Lumi"].species[]
    names = [p.name for p in sp.parts]
    check(all(in(names), (:crest, :wing_l, :wing_r)), "the live Lumi has no crest or wings of its own: $names")
    ang(m, ctx) = (q = BM_NG.animate(m, ctx)[2]; 2 * atan(sqrt(q.data[1]^2 + q.data[2]^2 + q.data[3]^2), abs(q.data[4])))
    inner(n) = sp.parts[findfirst(==(n), names)].motion.inner
    ctx(a; mood = 0f0, extra = 0f0, t = 3.5f0) = BM_NG.PoseCtx(a, 0.4f0, mood, extra, 0.37f0, t, 1f0)
    flop = [ang(inner(:crest), ctx(:idle; extra = Float32(e))) for e in 0.95:-0.05:0.05]
    check(maximum(flop) > 0.2f0, "the crest does not flop after a stop: $(round.(flop; digits = 2))")
    check(ang(inner(:crest), ctx(:idle; mood = -0.9f0)) > 0.4f0, "the crest does not hang when Lumi is low")
    # standing still between fidgets (a preen lifts the left wing on purpose)
    still = first(t for t in 0f0:0.25f0:14f0 if BM_NG.fidget(ctx(:idle; t))[1] == 0)
    for w in (:wing_l, :wing_r)
        check(ang(inner(w), ctx(:proud)) > 0.8f0, "the $w does not spread when proud: $(ang(inner(w), ctx(:proud)))")
        check(ang(inner(w), ctx(:idle; t = still)) < 0.1f0, "the $w is not folded while Lumi stands (t $still): $(ang(inner(w), ctx(:idle; t = still)))")
    end
    wait_seconds(game, 2)
    screenshot(game, "crestwings")
end

# Name tags (s59, scenery.jl `tag_spots`): every tag stands right above its own creature's head,
# never pushed sideways onto a bush or another creature (perfectionist-0058).
uitest("Name tags stand right above their own creatures' heads") do game
    ok = 0
    for k in 1:4
        wait_seconds(game, 3)
        l = game.stage.labels
        offs, heads = l.attributes[:arg1][], l.attributes[:arg2][]
        check(length(offs) == length(heads), "tags and heads differ: $(length(offs)) vs $(length(heads))")
        for (o, h) in zip(offs, heads)
            check(o[1] == 0 && 0 < o[2] < 120, "a tag is not above its head: offset $o from head $h (all $offs)")
        end
        isempty(offs) || (ok += 1; check(offs[1] == Vec2f(0, 14), "the nearest creature's tag moved: $(offs[1])"))
    end
    check(ok > 0, "no creature had a tag in 12 s")
    screenshot(game, "nametags")
end
