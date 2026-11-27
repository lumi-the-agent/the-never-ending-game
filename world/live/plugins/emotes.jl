# Emotes: little signs float up from a creature's head and fade, so you see how it feels
# without reading a label: z when it sleeps, notes when it dances or plays, hearts when it
# eats or chats happily or makes a friend, "…" when it sulks, "!" when it is greeted.
# Other plugins add one with `Base.invokelatest(Main.EMOTES[:emote], id, :heart)` (set while this runs).
# Two plots in the dashboard's 2D overlay: a scatter of hearts (the font has no ♥) and a text of glyphs.
isdefined(Main, :EMOTES) || Core.eval(Main, :(const EMOTES = Dict{Symbol,Any}()))
const NG = NeverendingGame
const EM = Main.EMOTES

const HEART = BezierPath([MoveTo(Point2f(0, -0.5)),
    CurveTo(Point2f(-0.15, -0.3), Point2f(-0.55, -0.1), Point2f(-0.5, 0.2)),
    CurveTo(Point2f(-0.45, 0.5), Point2f(-0.05, 0.55), Point2f(0, 0.25)),
    CurveTo(Point2f(0.05, 0.55), Point2f(0.45, 0.5), Point2f(0.5, 0.2)),
    CurveTo(Point2f(0.55, -0.1), Point2f(0.15, -0.3), Point2f(0, -0.5)), ClosePath()])

# kind => (glyph or :heart, colour, seconds on screen)
const KINDS = Dict(
    :heart => (:heart, RGBf(1.0, 0.36, 0.5), 1.8),
    :note  => ("♪", RGBf(1.0, 0.86, 0.35), 1.6),
    :sleep => ("z", RGBf(0.75, 0.85, 1.0), 2.2),
    :sulk  => ("…", RGBf(0.72, 0.74, 0.8), 2.0),
    :hey   => ("!", RGBf(1.0, 0.95, 0.6), 1.2),
    :what  => ("?", RGBf(0.8, 0.9, 1.0), 1.5))
# what a creature shows by itself while it does something: action => (kind, every so many seconds)
const BY_ACTION = Dict(:sleep => (:sleep, 1.4), :dance => (:note, 0.8), :play => (:note, 1.5),
                       :jump => (:note, 1.2), :sulk => (:sulk, 2.2), :eat => (:heart, 2.5))
const NEAR = 18.0f0          # only creatures this close to the camera show emotes
const RISE = 70.0f0          # pixels an emote floats up over its life

mutable struct Emote
    id::Int32
    kind::Symbol
    t0::Float64
    dx::Float32              # a little sideways drift, so a row of z's does not stack
end

struct Emotes <: System end

"Show emote `kind` (:heart :note :sleep :sulk :hey :what) above creature `id` now."
function emote!(id::Integer, kind::Symbol)
    haskey(KINDS, kind) || error("unknown emote $kind")
    push!(EM[:live], Emote(Int32(id), kind, EM[:clock], Float32(rand() * 24 - 12)))
    return
end

function NG.start!(::Emotes, game)
    game.stage === nothing && return
    for k in (:hearts, :glyphs)
        haskey(EM, k) && delete!(EM[k].parent, EM[k])
    end
    ov = game.stage.overlay
    EM[:hearts] = scatter!(ov, [Point2f(-100, -100)]; marker = HEART, markersize = 26, color = [RGBAf(1, 0.4, 0.5, 0)],
        strokewidth = 1.5, strokecolor = [RGBAf(0.3, 0.05, 0.1, 0)], name = :emote_hearts)
    EM[:glyphs] = text!(ov, [Point2f(-100, -100)]; text = [" "], fontsize = 30, font = :bold, align = (:center, :center),
        color = [RGBAf(1, 1, 1, 0)], strokewidth = 2, strokecolor = [RGBAf(0.06, 0.07, 0.1, 0)], name = :emote_glyphs)
    EM[:live] = Emote[]
    EM[:next] = Dict{Int32,Float64}()
    EM[:clock] = 0.0
    EM[:shown] = 0
    EM[:emote] = emote!
    return
end

function NG.step!(::Emotes, game, dt)
    game.stage === nothing && return
    haskey(EM, :live) || NG.start!(Emotes(), game)
    w = game.world
    EM[:clock] += dt
    now = EM[:clock]
    sc = game.stage.scene
    eye = Point3f(sc.camera.eyeposition[])
    # creatures near the camera emote by themselves while they sleep, dance, play, sulk, eat
    nxt = EM[:next]
    for c in w.creatures
        a = get(BY_ACTION, c.action, nothing)
        a === nothing && (delete!(nxt, c.id); continue)
        norm(Vec3f(c.pos - eye)) < NEAR || continue
        kind, every = a
        kind === :heart && c.mood < 0 && continue
        t = get!(nxt, c.id, now + rand() * every)
        if now >= t
            push!(EM[:live], Emote(c.id, kind, now, Float32(rand() * 24 - 12)))
            nxt[c.id] = now + every * (0.8 + 0.4rand())
        end
    end
    # a z floats 2.2 s: when a friend wakes the sleeper (nap_woken), its z's went on floating over the new thought
    # ("meeting someone new" under a Z, perfectionist-0148). Awake means no z.
    awake(e) = e.kind === :sleep && (c = NG.creature(w, e.id); c !== nothing && c.action !== :sleep)
    filter!(e -> now - e.t0 < KINDS[e.kind][3] && !awake(e), EM[:live])
    hp = Point2f[]; hc = RGBAf[]; hs = RGBAf[]
    gp = Point2f[]; gt = String[]; gc = RGBAf[]; gs = RGBAf[]
    for e in EM[:live]
        c = NG.creature(w, e.id)
        c === nothing && continue
        px = NG.on_screen(sc, NG.head_point(w, c) + Point3f(0, 0, 0.25f0))
        px === nothing && continue
        glyph, col, life = KINDS[e.kind]
        f = Float32((now - e.t0) / life)
        alpha = f < 0.15f0 ? f / 0.15f0 : 1 - max(0.0f0, (f - 0.6f0) / 0.4f0)
        p = px + Point2f(e.dx * f, 18 + RISE * f)
        if glyph === :heart
            push!(hp, p); push!(hc, RGBAf(col, alpha)); push!(hs, RGBAf(0.3, 0.05, 0.1, alpha))
        else
            push!(gp, p); push!(gt, glyph); push!(gc, RGBAf(col, alpha)); push!(gs, RGBAf(0.06, 0.07, 0.1, 0.9alpha))
        end
    end
    EM[:shown] = length(hp) + length(gp)
    # the raster cannot draw empty plots: park one invisible element off screen
    isempty(hp) && (push!(hp, Point2f(-100, -100)); push!(hc, RGBAf(0, 0, 0, 0)); push!(hs, RGBAf(0, 0, 0, 0)))
    isempty(gp) && (push!(gp, Point2f(-100, -100)); push!(gt, " "); push!(gc, RGBAf(0, 0, 0, 0)); push!(gs, RGBAf(0, 0, 0, 0)))
    Makie.update!(EM[:hearts], hp; color = hc, strokecolor = hs)
    Makie.update!(EM[:glyphs], gp; text = gt, color = gc, strokecolor = gs)
    return
end

function NG.stop!(::Emotes, game)
    delete!(EM, :emote)
    for k in (:hearts, :glyphs)
        haskey(EM, k) && (EM[k].visible[] = false)
    end
end

register!(Emotes())
