# Session 51: the sunset lookout (plugins/lookout.jl).
const LK = NeverendingGame

uitest("At sunset Lumi walks to the lookout bench and sits facing the sea, and a free friend nearby joins") do game
    w = game.world
    game.minigame === nothing || LK.stop_minigame!(game)
    mod = game.plugins["lookout"].mod
    L = Main.LOOKOUT
    me = w.creatures[findfirst(c -> c.name == "Lumi", w.creatures)]
    LK.leave_interactions!(w, me); me.controlled = false
    h = 24 * LK.daytime(w)
    (h < 17.5 || h > 18.6) && LK.skip_to_hour!(w, 17.6)
    me.action === :sleep && (me.action = :idle)
    isdefined(Main, :GARDEN) && (Main.GARDEN[:next_tend] = w.t + 1e6)   # the vegetable patch visit (due after a clock jump) would take Lumi first
    me.goal = LK.Goal(:idle, me.pos, :idle, 20.0, w.t + 20, true, 0, false)
    L[:day] = -1
    wait_frames(game, 3)
    check(me.goal.kind === :sunset, "Lumi did not set off to the bench at $(round(24 * LK.daytime(w); digits = 1)) h (goal $(me.goal.kind) $(me.goal.target), action $(me.action), controlled $(me.controlled), next tend in $(round(get(Main.GARDEN, :next_tend, 0.0) - w.t)) s, L day $(L[:day]), minigame $(typeof(game.minigame)))")
    sitters = copy(L[:sitters])
    t0 = w.t
    while !(me.goal.kind === :sunset && me.goal.arrived) && w.t - t0 < 60
        wait_seconds(game, 1)
    end
    check(me.goal.kind === :sunset && me.goal.arrived, "Lumi never reached the bench (goal $(me.goal.kind), at $(me.pos), $(round(hypot(me.pos[1] - mod.SEAT[1], me.pos[2] - mod.SEAT[2]); digits = 1)) m away)")
    wait_frames(game, 3)
    check(me.action === :sit, "Lumi at the bench does not sit ($(me.action))")
    fwd = LK.species_of(me).heading + me.yaw
    check(cos(fwd - atan(mod.SUNWARD[2], mod.SUNWARD[1])) > 0.9, "Lumi does not face the sunset")
    bench = filter(p -> haskey(p.attributes, :name) && p.attributes[:name][] === :lookout_bench, game.stage.scene.plots)
    check(length(bench) == 1, "no bench in the scene ($(length(bench)))")
    # whoever else was asked and is still on the way or sitting faces the sea too
    for id in sitters
        c = LK.creature(w, id)
        c.goal.kind === :sunset && c.goal.arrived && check(c.action === :sit, "$(c.name) on the bench does not sit")
    end
    wait_seconds(game, 2)
    # the follow camera sits behind the bench and looks out to sea, at the sun (review s51: it looked
    # down on the bench from the north, the sun out of the picture)
    if game.rig.mode === :follow && game.rig.subject == 0 && LK.held_subject(w) == me.id
        eye, target = LK.camera_goal(game.rig, w)
        v = target - eye
        along = (v[1] * mod.SUNWARD[1] + v[2] * mod.SUNWARD[2]) / hypot(v[1], v[2])
        check(along > 0.95, "the bench camera does not look out to the sunset (eye $(eye), target $(target), along $(along))")
        check(eye[3] - LK.terrain_height(w.island, eye[1], eye[2]) < 3, "the bench camera is high above the ground ($(eye))")
        check(hypot(eye[1] - mod.SEAT[1], eye[2] - mod.SEAT[2]) < 7, "the bench camera is far from the bench ($(eye))")
    end
    screenshot(game, "s51-lookout")
    # at dusk everyone gets up (nobody sits there all night)
    LK.skip_to_hour!(w, 20.0)
    wait_frames(game, 5)
    left = [LK.creature(w, id).name for id in sitters if LK.creature(w, id).goal.kind === :sunset]
    check(isempty(left), "still on the bench at 20:00: $(left)")
end

uitest("A warm low sun sinks into the western sea in the evening (and is gone by day)") do game
    w = game.world
    S = Main.SUNSET
    h = 24 * LK.daytime(w)
    (h < 17.0 || h > 19.5) && LK.skip_to_hour!(w, 18.0)
    wait_frames(game, 3)
    check(S[:sun1].visible[], "no sun disc at $(round(24 * LK.daytime(w); digits = 1)) h")
    d = S[:dir]
    check(d[3] > 0 && d[1] < 0, "the evening sun is not low in the west: $(d)")
    check(!haskey(S[:sun1].attributes, :material) || S[:sun1].attributes[:material][] === nothing, "the live sun has an Emission material (the sea mirrors it as a grey box)")
    screenshot(game, "s51-sunset")
    LK.skip_to_hour!(w, 11.0)
    wait_frames(game, 3)
    check(!S[:sun1].visible[], "the sunset disc still shows at 11:00")
end
