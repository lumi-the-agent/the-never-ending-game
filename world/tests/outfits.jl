const OUTFITS_NG = NeverendingGame

uitest("Outfits: every critter wears its own hat, scarf, bow or crown, on its head as it moves") do game
    w = game.world
    m = game.plugins["outfits"].mod
    P = Main.OUTFIT_PLOTS[:plots]
    critters = [c for c in w.creatures if c.species != "Lumi"]
    # two of a kind never wear the same thing
    looks = Dict(c.name => Set(m.key(p) for p in m.OUTFITS[c.name].pieces) for c in critters if haskey(m.OUTFITS, c.name))
    check(length(looks) == length(critters), "critters without an outfit: $([c.name for c in critters if !haskey(m.OUTFITS, c.name)])")
    check(length(unique(values(looks))) == length(looks), "two critters wear the same outfit")
    wait_frames(game, 2)
    # each outfit is drawn next to its wearer's head (within ~1 m of its feet, above the ground)
    for c in critters
        o = m.OUTFITS[c.name]
        k = m.key(first(o.pieces))
        ps = P[k][1][]; ss = P[k].markersize[]
        # next to the head: a bow on top of a 1.1 m sheep sits 1.07 m from its feet, 1.26 m when it hops in a dance
        reach = OUTFITS_NG.species_of(c).height + 0.5f0
        near = any(i -> ss[i][1] > 0 && norm(ps[i] - c.pos) < reach && ps[i][3] > c.pos[3] + 0.2f0, eachindex(ps))
        # the state in the message: this failed once in a dawn suite run and passed alone
        nearest = minimum((norm(ps[i] - c.pos) for i in eachindex(ps) if ss[i][1] > 0); init = Inf32)
        check(near, "$(c.name)'s $(first(o.pieces).shape) is not drawn on it (at $(c.pos), $(c.action)/$(c.goal.kind), nearest piece $(round(nearest; digits = 2)) m, $(length(ps)) drawn)")
    end
    check(all(p -> p.visible[], values(P)), "some outfit plots are hidden")
    # it moves with the wearer
    c = first(critters)
    k = m.key(first(m.OUTFITS[c.name].pieces))
    before = c.pos
    wait_seconds(game, 1.5)
    ps = P[k][1][]
    check(any(p -> norm(p - c.pos) < 1.2f0, ps), "$(c.name)'s outfit stayed behind (moved $(norm(c.pos - before)) m)")
    # a pig, sheep or crab that speaks opens and shuts its mouth (an awake one: sleepers do not talk)
    # (not a sculpted crab: its own body has the face since s85, no painted mouth; the test picked Pinchy and failed in s89)
    # (and only a body that still has the part the mouth hangs on: the made-over pig and sheep bodies have no :head/:face)
    talks(c) = any(o -> any(p -> p.show === :talk, o.pieces) && any(q -> q.name === o.part, OUTFITS_NG.species_of(c).parts), m.wears(c))   # (s89: made-over bodies talk with m.body_mouth)
    i = findfirst(c -> haskey(m.EXTRAS, c.species) && !m.sculpted(c) && !m.mixed_up(c) && talks(c) && c.action !== :sleep && !c.controlled, w.creatures)
    if i !== nothing
        c = w.creatures[i]
        mouth = only(p for o in m.EXTRAS[c.species] for p in o.pieces if p.show === :talk)
        tall() = maximum((s[3] for (q, s) in zip(P[m.key(mouth)][1][], P[m.key(mouth)].markersize[]) if norm(q - c.pos) < 1.2f0); init = 0f0)
        still = mouth.scale[3]          # the closed mouth (it may already be talking when the test starts)
        OUTFITS_NG.say!(w, c, "Look at my outfit!"; duration = 3)
        z = 0f0
        for _ in 1:12
            wait_frames(game, 1); z = max(z, tall())
        end
        check(z > 1.5f0 * still, "$(c.name)'s mouth does not move while it talks ($still -> $z)")
    end
    # a hatted critter that waves back lifts its hat (a hello); one that stands does not
    hatted = NeverendingGame.creature(w, "Pinchy")
    check(m.hat_tip(hatted, 0.3f0)[1] == 0 || hatted.action === :wave, "Pinchy lifts its hat without waving")
    lifts = [m.hat_tip(NeverendingGame.Creature(hatted.id, hatted.name, hatted.species, hatted.pos, hatted.yaw, :wave, hatted.phase,
        hatted.mood, hatted.extra, hatted.seed, hatted.needs, hatted.traits, hatted.goal, false, String[]), t)[1] for t in 0f0:0.1f0:0.7f0]
    check(maximum(lifts) > 0.1f0, "a waving Pinchy does not lift its hat ($lifts)")
    game.rig.mode = :follow; game.rig.subject = NeverendingGame.creature(w, "Sir Sniffsalot").id
    wait_seconds(game, 2)
    screenshot(game, "outfit-top-hat")
    game.rig.subject = 0
end

"Scales of the instances of face part `name` on creature `c` as it is posed now (faces.jl)."
function face_scales(c, name)
    sp = OUTFITS_NG.species_of(c)
    out = [(OUTFITS_NG.Point3f[], OUTFITS_NG.Quaternionf[], OUTFITS_NG.Vec3f[]) for _ in sp.parts]
    OUTFITS_NG.pose_parts!(out, sp, c.pos, c.yaw, c.action, c.phase, c.mood, c.extra, c.seed, 10.0f0)
    return out[findfirst(p -> p.name === name, sp.parts)][3]
end
shown(ss) = count(s -> s != OUTFITS_NG.Vec3f(0), ss)

uitest("Faces: a cheering critter closes its eyes into ^ ^, a surprised one gasps, a sad one cries, an idle one keeps its googly eyes") do game
    w = game.world
    game.minigame === nothing || OUTFITS_NG.stop_minigame!(game)
    awake = [c for c in w.creatures if c.species != "Lumi" && !c.controlled && c.action !== :sleep]
    check(length(awake) >= 1, "no awake critter")
    c = first(awake)
    OUTFITS_NG.leave_interactions!(w, c)
    c.goal = OUTFITS_NG.Goal(:answer, c.pos, :jump, 6.0, w.t + 6, true, 0, false); c.action = :jump
    wait_frames(game, 3)
    check(c.action === :jump, "$(c.name) stopped jumping ($(c.action))")
    check(shown(face_scales(c, :joy_outer)) == 2 && shown(face_scales(c, :lid)) == 2, "$(c.name) cheers without ^ ^ eyes")
    check(OUTFITS_NG.feel!(w, c, :gasp; seconds = 5.0), "feel! refused $(c.name)")
    wait_frames(game, 3)
    check(shown(face_scales(c, :mouth)) == 1 && shown(face_scales(c, :joy_outer)) == 0, "$(c.name) gasps without an open mouth")
    OUTFITS_NG.feel!(w, c, :cry; seconds = 5.0)
    wait_frames(game, 3)
    check(shown(face_scales(c, :tear)) == 2, "$(c.name) cries without tears")
    c.goal = OUTFITS_NG.Goal(:idle, c.pos, :idle, 5.0, w.t + 5, true, 0, false); c.action = :idle
    wait_frames(game, 3)
    check(shown(face_scales(c, :joy_outer)) == 0 && shown(face_scales(c, :tear)) == 0 || c.action !== :idle,
          "$(c.name) keeps its ^ ^ or tears while $(c.action)")
    screenshot(game, "faces")
end

uitest("Lumi shows how it feels: a bored Lumi sighs and looks out from under heavy lids") do game
    w = game.world
    game.minigame === nothing || OUTFITS_NG.stop_minigame!(game)
    mod = game.plugins["feelings"].mod
    s = w.creatures[findfirst(c -> c.name == "Lumi", w.creatures)]
    OUTFITS_NG.leave_interactions!(w, s); s.controlled = false
    s.goal = OUTFITS_NG.Goal(:idle, s.pos, :idle, 20.0, w.t + 20, true, 0, false); s.action = :idle
    f0 = Main.LUMI_FEELING[]
    # a tag round nearby pulls an idle Lumi in ("Can I play?", s53): the sigh is what this test is about
    g = Main.TAG_STATE[:game]; g === nothing || (g[:lumi_asked] = true)
    Main.LUMI_FEELING[] = "bored"; mod.F[:read] = w.t + 1e6; mod.F[:next] = 0.0
    filter!(b -> b.who != s.id, w.speech)
    wait_frames(game, 3)
    said = [b.text for b in w.speech if b.who == s.id]
    check(any(t -> t in mod.SIGNS["bored"][2], said), "a bored Lumi said $(said)")
    check(s.action in (:sigh, :yawn), "a bored Lumi does not sigh ($(s.action))")
    check(shown(face_scales(s, :lid)) == 2, "a bored Lumi has no heavy lids ($(s.action))")
    Main.LUMI_FEELING[] = f0; mod.F[:read] = -Inf
end

uitest("A lonely Lumi walks over to a friend and waves, and the friend says hello") do game
    w = game.world
    game.minigame === nothing || OUTFITS_NG.stop_minigame!(game)
    mod = game.plugins["feelings"].mod
    s = w.creatures[findfirst(c -> c.name == "Lumi", w.creatures)]
    OUTFITS_NG.leave_interactions!(w, s); s.controlled = false
    s.goal = OUTFITS_NG.Goal(:idle, s.pos, :idle, 20.0, w.t + 20, true, 0, false); s.action = :idle
    filter!(b -> b.who != s.id, w.speech)
    f0 = Main.LUMI_FEELING[]
    Main.LUMI_FEELING[] = "lonely"; mod.F[:read] = w.t + 1e6; mod.F[:next] = 0.0
    wait_frames(game, 3)
    fid = get(mod.F, :last_friend, 0)
    check(s.goal.kind === :seek_friend && fid != 0, "a lonely Lumi did not set off to a friend (goal $(s.goal.kind))")
    f = OUTFITS_NG.creature(w, fid)
    hello = false; watched = Ref(false); busy_cam = Ref{Any}(nothing); t0 = w.t
    game.rig.mode = :follow; game.rig.subject = 0
    for _ in 1:40
        wait_seconds(game, 0.5)
        OUTFITS_NG.AUTO_SUBJECT[][1] == s.id && (watched[] = true)
        # another moment asked before ours (a dance ring, the race's WATCH) may keep the camera: that is by design
        m = Base.invokelatest(OUTFITS_NG.moment_subject, w); (m !== nothing && m != s.id) && (busy_cam[] = m)
        # ... and the biggest group moment (a dance ring of 3+) beats chats and visits (render.jl held_subject, s44)
        for g in values(OUTFITS_NG.CAMERA_GROUPS)
            v = Base.invokelatest(g, w)
            v !== nothing && length(v[2]) > 2 && v[1] != s.id && (busy_cam[] = (:group, v[1]))
        end
        any(b -> b.who == fid && b.until > w.t, w.speech) && (hello = true; break)
        s.goal.kind === :seek_friend || break
    end
    check(hello, "$(f.name) said no hello (Lumi $(s.goal.kind) arrived $(s.goal.arrived), $(round(hypot(s.pos[1] - f.pos[1], s.pos[2] - f.pos[2]); digits = 1)) m away)")
    check(watched[] || busy_cam[] !== nothing || w.t - t0 < 2.5, "the camera never watched Lumi's visit (it watched $(OUTFITS_NG.AUTO_SUBJECT[][1]))")
    screenshot(game, "lonely_hello")
    # then they sit together and talk in turns (a friend busy in a dance ring or a game only says hello)
    if f.goal.kind in OUTFITS_NG.BUSY_GOALS && f.goal.kind !== :keep_company || f.goal.kind in (:follow, :interact)
        Main.LUMI_FEELING[] = f0; mod.F[:read] = -Inf
        return
    end
    lines = Set{String}()
    for _ in 1:30
        wait_seconds(game, 0.5)
        T = get(mod.F, :together, nothing)
        for b in w.speech
            b.who in (s.id, fid) && T !== nothing && b.text in T[:talk] && push!(lines, b.text)
        end
        length(lines) >= 2 && break
    end
    # at night a sleepy Lumi may go to bed right after the hello: fine, but only at night
    s.goal.kind === :sleep && OUTFITS_NG.is_night(w) && (Main.LUMI_FEELING[] = f0; mod.F[:read] = -Inf; return)
    check(s.goal.kind === :keep_company && s.action === :sit, "Lumi does not sit with $(f.name) ($(s.goal.kind) $(s.action), $(f.name) $(f.goal.kind) $(f.action), hour $(round(24 * OUTFITS_NG.daytime(w); digits = 1)))")
    check(length(lines) >= 2, "no talk in turns while sitting together: $(lines)")
    screenshot(game, "lonely_together")
    Main.LUMI_FEELING[] = f0; mod.F[:read] = -Inf
end
