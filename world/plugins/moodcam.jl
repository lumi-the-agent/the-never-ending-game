# The camera has a mood (session 107, goal 8): the camera that watches my island feels what I feel (the host's
# real measure of me, read by feelings.jl). Bored, it gets distracted: every half minute or so it drifts away from
# whoever it was watching to stare at a flower or out at the sea for a while, then sighs back. Lonely, it pulls far
# back and low, so whoever it watches stands small in a big empty island. Happy or proud, it bounces in close.
# It only ever takes the follow camera (never your own free camera, never a mini game), and it glides: the follow
# camera's own easing carries every change.
isdefined(Main, :MOODCAM) || Core.eval(Main, :(const MOODCAM = Dict{Symbol,Any}()))
const NG = NeverendingGame
const MC = Main.MOODCAM

struct MoodCam <: System end

feeling() = string(get(MC, :feeling_override, isdefined(Main, :LUMI_FEELING) ? Main.LUMI_FEELING[] : "content"))

"What the camera finds prettier than us right now: a flower near the subject, or the sea beyond the nearest shore."
function distraction(w, c)
    p = c.pos
    flowers = [q.pos for q in w.props if q.kind === :flower && 2.5f0 < hypot(q.pos[1] - p[1], q.pos[2] - p[2]) < 9f0 &&
               all(t -> t.kind !== :tree || hypot(t.pos[1] - q.pos[1], t.pos[2] - q.pos[2]) > 2.5f0 * t.scale, w.props)]
    if !isempty(flowers) && rand(w.rng) < 0.6
        f = flowers[rand(w.rng, 1:length(flowers))]
        d = Vec3f(f[1] - p[1], f[2] - p[2], 0); d = d / max(hypot(d[1], d[2]), 1f-3)
        eye = Point3f(f + Vec3f(0, 0, 0.25f0) - d * 1.5f0 + Vec3f(-d[2], d[1], 0) * 0.5f0 + Vec3f(0, 0, 0.45f0))
        return (:flower, eye, Point3f(f + Vec3f(0, 0, 0.3f0)))
    end
    # the sea: the way to the nearest shore, staring past it at the horizon
    best = nothing
    for a in 0:15:345, r in 4f0:2f0:30f0
        q = (p[1] + r * cosd(a), p[2] + r * sind(a))
        if !NG.on_land(w.island, q[1], q[2]; margin = 0.05)
            (best === nothing || r < best[1]) && (best = (r, a))
            break
        end
    end
    best === nothing && return nothing
    a = best[2]; d = Vec3f(cosd(a), sind(a), 0)
    eye = Point3f(p + Vec3f(0, 0, 1.7f0) - d * 0.8f0)
    return (:sea, eye, Point3f(p + d * 60f0 + Vec3f(0, 0, 0.6f0 - p[3])))
end

"Whom the follow camera watches now (no player, no mini game, its own pick)."
function watched(game)
    game.rig.mode === :follow && game.rig.subject == 0 || return nothing
    (game.minigame === nothing && !any(c -> c.controlled && c.species == "Lumi", game.world.creatures)) || return nothing
    id = NG.AUTO_SUBJECT[][1]
    return NG.creature(game.world, id)
end

"The camera's view for the subject while it is in a mood, or nothing to leave the camera be."
function mood_view(game)
    w = game.world
    c = watched(game); c === nothing && return nothing
    f = feeling()
    st = get(MC, :state, :attend)
    if f == "bored"
        if st === :attend && w.t >= get(MC, :until, 0.0)
            d = distraction(w, c)
            if d === nothing
                MC[:until] = w.t + 10
            else
                MC[:state] = :drift; MC[:until] = w.t + 7 + 4rand(w.rng); MC[:view] = d; MC[:who] = c.id
                NG.emit!(w, :moodcam_drift; to = string(d[1]), from = c.name)
            end
        elseif st === :drift && w.t >= MC[:until]          # (the follow camera switching subjects does not end it: it keeps staring)
            MC[:state] = :attend; MC[:until] = w.t + 25 + 20rand(w.rng)     # (14-24 s had it staring 40% of the time)
            NG.emit!(w, :moodcam_back; to = c.name)
        end
        get(MC, :state, :attend) === :drift || return nothing
        _, eye, tg = MC[:view]
        return (c.id, [c.pos, tg], (eye, tg))
    elseif f == "lonely"
        # far back and low: one small figure in a big island, from the side with the clearest line (picked once for
        # 10 s per subject, so it does not swing about; a fixed side had rocks and logs filling the foreground)
        tg = Point3f(c.pos + Vec3f(0, 0, 0.7f0))
        lv = get(MC, :lonely, nothing)
        if lv === nothing || lv[1] != c.id || w.t > lv[3]
            best = (Inf, 0f0)
            for a in 0f0:Float32(pi / 4):Float32(7pi / 4)
                e = Point3f(c.pos + Vec3f(cos(a), sin(a), 0) * 11f0 + Vec3f(0, 0, 1.6f0))
                g = NG.ground(w.island, (e[1], e[2]))
                e = Point3f(e[1], e[2], max(e[3], g[3] + 1.2f0))
                o = NG.obstruction(w, e, tg)
                o < best[1] && (best = (o, a))
            end
            MC[:lonely] = lv = (c.id, best[2], w.t + 10)
        end
        away = Vec3f(cos(lv[2]), sin(lv[2]), 0)
        e = Point3f(c.pos + away * 11f0 + Vec3f(0, 0, 1.6f0)); g = NG.ground(w.island, (e[1], e[2]))
        eye = Point3f(e[1], e[2], max(e[3], g[3] + 1.2f0))
        return (c.id, [c.pos, c.pos + away], (eye, tg))
    elseif f in ("proud", "happy", "content") && f != "content"
        fwd = Vec3f(cos(c.yaw + NG.species_of(c).heading), sin(c.yaw + NG.species_of(c).heading), 0)
        eye = Point3f(c.pos + fwd * 2.6f0 + Vec3f(-fwd[2], fwd[1], 0) * 0.8f0 + Vec3f(0, 0, 0.9f0 + 0.15f0 * sin(3f0 * Float32(mod(w.t, 100)))))
        return (c.id, [c.pos, c.pos + fwd], (eye, Point3f(c.pos + Vec3f(0, 0, 0.8f0))))
    end
    return nothing
end

function NG.step!(::MoodCam, game, dt)
    return nothing
end

function NG.start!(::MoodCam, game)
    MC[:state] = :attend; MC[:until] = 0.0; delete!(MC, :view)
    NG.CAMERA_GROUPS["moodcam"] = w -> begin
        # other moments for the same subject (a dance ring, the bench) come first
        v = Base.invokelatest(mood_view, game)
        v === nothing && return nothing
        for (k, g) in NG.CAMERA_GROUPS
            k == "moodcam" && continue
            o = Base.invokelatest(g, w)
            o !== nothing && Int32(o[1]) == Int32(v[1]) && return nothing
        end
        return v
    end
    return nothing
end

function NG.stop!(::MoodCam, game)
    delete!(NG.CAMERA_GROUPS, "moodcam")
end

register!(MoodCam())
