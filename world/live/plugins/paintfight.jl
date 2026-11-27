# The Great Paint Fight (session 68): Lumi carries three pots of paint across the meadow, wobbles,
# trips... SPLOOSH. A fountain of red, blue, yellow and mint paint rains down on every friend close by.
# They stare at their spots, someone flings a blob back ("You got me!"), and the whole meadow breaks
# into a paint fight: everyone scoops paint and lobs it at everyone else, splats on bodies and grass,
# until they stand there polka-dotted, laughing. The spots stay on them for a while; the splats on the
# grass fade. Press P when you are Lumi.
isdefined(Main, :PAINT) || Core.eval(Main, :(const PAINT = Dict{Symbol,Any}()))
const NG = NeverendingGame

# one island-wide effect at a time (s110, review #538: snow, a paint fight and a drift together drowned each other out)
isdefined(Main, :ISLAND_FX) || Core.eval(Main, :(const ISLAND_FX = Dict{Symbol,Any}()))
fx_free(w) = w.t >= get(Main.ISLAND_FX, :until, -Inf)
claim_fx!(w, secs, who) = (Main.ISLAND_FX[:until] = w.t + secs; Main.ISLAND_FX[:who] = who; nothing)
const P = Main.PAINT

const GAP = (600.0, 1000.0)       # sim seconds between two paint fights
const REACH = 11f0                # friends this close join in
const NDROP = 70                  # drops in the big spill
const NBALL = 24                  # paint balls in the air at once
const NSPLAT = 220                # splat pieces on the grass
const NBLOB = 14                  # paint spots per creature
const TRIP = 2.2                  # seconds of wobbling before the spill
const FIGHT = 20.0                # seconds of paint fight
const STAY = 150.0                # spots stay on bodies (sim seconds; 25 min of balls was a balloon seller, perfectionist-0070)
const COLOURS = (RGBf(0.95, 0.22, 0.32), RGBf(0.18, 0.52, 0.96), RGBf(1.0, 0.84, 0.12),
                 RGBf(0.28, 0.86, 0.52), RGBf(0.66, 0.34, 0.94), RGBf(1.0, 0.5, 0.12))
const WOBBLE = ("whoa...", "whoa-whoa-", "WHOA-WHOA-WHOAAA!")
const SPLOOSH = ("SPLOOOSH!!!", "SPLATTT!!!", "KER-SPLOSH!!!")
const STARE = ("...", "Is this... paint?", "I'm BLUE!", "Lumi!!!", "My fur!")
const START = ("You got me!", "PAINT FIGHT!!!", "Take THAT!", "Hee hee!")
const HIT = ("SPLAT!", "Hey!", "Got you!", "Bullseye!", "Eek!", "Not my face!", "Ha ha!", "Again!")
const END = ("Look at us!", "I'm a rainbow!", "Best. Day. Ever.", "Again tomorrow?", "So pretty!")
const KEEP = (:follow, :choir, :answer, :conga, :circle, :rain, :build, :tinker, :kite, :boing, :boing_walk,
              :hide, :found, :freeze, :sneezed, :hiccup, :flight, :giant, :storm, :toadstool, :blossom, :swing, :bottle, :leaves)

push!(NG.BUSY_GOALS, :paint)

mutable struct Ball
    from::Point3f
    to::Point3f
    t0::Float64
    T::Float64
    h::Float32
    col::RGBf
    target::Int32      # creature hit on arrival, or 0
end

mutable struct PaintFight <: System
    state::Symbol                 # :idle, :trip, :spill, :fight, :after
    t0::Float64
    next_t::Float64
    lumi::Int32
    friends::Vector{Int32}
    balls::Vector{Ball}
    throw_at::Dict{Int32,Float64} # id => when it throws next
    said::Int
    player::Bool
end
PaintFight() = PaintFight(:idle, 0.0, -1.0, 0, Int32[], Ball[], Dict{Int32,Float64}(), 0, false)

emote(id, kind) = isdefined(Main, :EMOTES) && haskey(Main.EMOTES, :emote) && Base.invokelatest(Main.EMOTES[:emote], id, kind)
lumi_of(w) = (i = findfirst(c -> c.name == "Lumi", w.creatures); i === nothing ? nothing : w.creatures[i])
free(c) = !c.controlled && c.goal.kind ∉ KEEP && c.goal.kind !== :paint && c.action !== :sleep
flat(a, b) = hypot(a[1] - b[1], a[2] - b[2])
cast(s) = [s.lumi; s.friends]
painting(c) = c !== nothing && c.goal.kind === :paint

# ---------------------------------------------------------------- plots

function plots!(game)
    for k in (:balls, :splats, :blobs, :pots)
        haskey(P, k) && P[k].parent !== nothing && delete!(P[k].parent, P[k])
    end
    hidden(n) = (fill(Point3f(0, 0, -50), n), fill(Vec3f(0), n))
    ps, ms = hidden(NBALL)
    P[:balls] = meshscatter!(game.stage.scene, ps; marker = Sphere(Point3f(0), 1f0), markersize = ms,
                             color = fill(COLOURS[1], NBALL), name = :paint_balls)
    ps, ms = hidden(NSPLAT)
    P[:splats] = meshscatter!(game.stage.scene, ps; marker = Sphere(Point3f(0), 1f0), markersize = ms,
                              rotation = fill(Makie.Quaternionf(0, 0, 0, 1), NSPLAT),
                              color = fill(COLOURS[1], NSPLAT), name = :paint_splats)
    P[:pots] = meshscatter!(game.stage.scene, fill(Point3f(0, 0, -50), 3); marker = Cylinder(Point3f(0), Point3f(0, 0, 1), 1f0),
                            markersize = fill(Vec3f(0), 3), rotation = fill(Makie.Quaternionf(0, 0, 0, 1), 3),
                            color = [COLOURS[1], COLOURS[2], COLOURS[3]], name = :paint_pots)
    P[:blobs] = meshscatter!(game.stage.scene, [Point3f(0, 0, -50)]; marker = Sphere(Point3f(0), 1f0),
                             markersize = [Vec3f(0)], rotation = [Makie.Quaternionf(0, 0, 0, 1)], color = [COLOURS[1]],
                             name = :paint_blobs)
end

# splats on the grass: (pos, size, yaw, colour, born); one splat = a big blot and a few droplets around it
function splat!(w, at, col; big = 1f0)
    sp = P[:splat]
    g = NG.ground(w.island, (at[1], at[2]))
    r = big * (0.22f0 + 0.2f0 * rand(w.rng))
    push!(sp, (g + Point3f(0, 0, 0.025f0), Vec3f(r, r * (0.6f0 + 0.3f0 * rand(w.rng)), 0.012f0), Float32(2pi * rand(w.rng)), col, w.t))
    for _ in 1:3
        a = 2pi * rand(w.rng); d = r * (1.3f0 + 1.2f0 * rand(w.rng)); rr = r * (0.15f0 + 0.2f0 * rand(w.rng))
        q = NG.ground(w.island, (at[1] + d * cos(a), at[2] + d * sin(a)))
        push!(sp, (q + Point3f(0, 0, 0.025f0), Vec3f(rr, rr, 0.01f0), 0f0, col, w.t))
    end
    while length(sp) > NSPLAT
        popfirst!(sp)
    end
    P[:splats_dirty] = true
end

function draw_splats!(w)
    sp = P[:splat]
    # splats fade (shrink away) a few minutes after they landed, oldest first
    filter!(x -> w.t - x[5] < 300, sp)
    n = length(sp)
    shrink(x) = Float32(clamp((300 - (w.t - x[5])) / 60, 0, 1))
    ps = [i <= n ? sp[i][1] : Point3f(0, 0, -50) for i in 1:NSPLAT]
    ms = [i <= n ? sp[i][2] * shrink(sp[i]) : Vec3f(0) for i in 1:NSPLAT]
    rs = [i <= n ? Makie.qrotation(Vec3f(0, 0, 1), sp[i][3]) : Makie.Quaternionf(0, 0, 0, 1) for i in 1:NSPLAT]
    cs = [i <= n ? sp[i][4] : COLOURS[1] for i in 1:NSPLAT]
    Makie.update!(P[:splats]; arg1 = ps, markersize = ms, rotation = rs, color = cs)
end

# paint spots on bodies: id => [(part, at, size, colour)] anchored on a body part like the outfits
function blob!(w, c, col)
    sp = NG.species_of(c)
    list = get!(P[:spots], c.id, Any[])
    # where the paint lands: a random side of the creature, on the posed part reaching out furthest that way
    # (s68: picking a part by its `scale` put every spot on Lumi's legs or Cumulus's face; mesh parts are unit scale)
    out = [(Point3f[], Makie.Quaternionf[], Vec3f[]) for _ in sp.parts]
    NG.pose_parts!(out, sp, c.pos, NG.drawn_yaw(c), c.action, c.phase, c.mood, c.extra, c.seed, NG.anim_time(w))
    centre = c.pos + Point3f(0, 0, 0.55f0 * sp.height)
    dir = normalize(Vec3f(randn(w.rng), randn(w.rng), 0.6f0 * randn(w.rng) + 0.25f0))
    best = (-Inf32, 0, 0)
    for k in eachindex(out), j in eachindex(out[k][1])
        q = out[k][1][j]; r = maximum(out[k][3][j])
        reach = dot(Vec3f(q - centre), dir) + 0.8f0 * r - 0.35f0 * norm(cross(Vec3f(q - centre), dir))
        reach > best[1] && (best = (reach, k, j))
    end
    _, k, j = best
    k == 0 && return
    # the same direction in the part's own frame, onto its surface
    at = normalize(inv(out[k][2][j]) * dir) * 0.86f0
    push!(list, (k, j, at * 0.85f0, 0.055f0 + 0.04f0 * rand(w.rng), col))   # small and sunk in: dabs, not balls
    length(list) > NBLOB && popfirst!(list)
    P[:until][c.id] = w.t + STAY
end

function draw_pots!(s::PaintFight, w, me)
    show = s.state === :trip && me !== nothing
    ps = Point3f[]; rs = Makie.Quaternionf[]; ms = Vec3f[]
    for k in 1:3
        if show
            t = Float32(w.t - s.t0)
            sway = (0.08f0 + 0.1f0 * t) * sin(7f0 * t + 0.9f0k)
            f = Vec3f(cos(me.yaw), sin(me.yaw), 0)
            push!(ps, body(me) + Point3f(0.45f0 * f[1], 0.45f0 * f[2], 0.15f0 + 0.3f0 * (k - 1)) + Point3f(sway * f[2] * k, -sway * f[1] * k, 0))
            push!(rs, Makie.qrotation(Vec3f(f[2], -f[1], 0), sway * k))
            push!(ms, Vec3f(0.17, 0.17, 0.27))
        else
            push!(ps, Point3f(0, 0, -50)); push!(rs, Makie.Quaternionf(0, 0, 0, 1)); push!(ms, Vec3f(0))
        end
    end
    Makie.update!(P[:pots]; arg1 = ps, rotation = rs, markersize = ms)
end

"How big the creature is drawn now (giant.jl scales Lumi's herd about its feet)."
giant_size(c) = isdefined(Main, :GIANT) && haskey(Main.GIANT, :sys) && Main.GIANT[:sys].lumi == c.id ? Main.GIANT[:sys].s : 1f0

function draw_blobs!(w)
    spots = P[:spots]
    for (id, until) in collect(P[:until])
        (until < w.t || NG.creature(w, id) === nothing) && (delete!(P[:until], id); delete!(spots, id))
    end
    ps = Point3f[]; ss = Vec3f[]; cs = RGBf[]; rs = Makie.Quaternionf[]
    t = NG.anim_time(w)
    for (id, list) in spots
        c = NG.creature(w, id)
        sp = NG.species_of(c)
        out = [(Point3f[], Makie.Quaternionf[], Vec3f[]) for _ in sp.parts]
        NG.pose_parts!(out, sp, c.pos, NG.drawn_yaw(c), c.action, c.phase, c.mood, c.extra, c.seed, t)
        g = giant_size(c)
        # a giant's spots, scaled with it, hung round it like balloons (Lumi's mesh parts sit at its feet point,
        # so its spots never lay on the surface): none while it is big
        g > 1.05f0 && continue
        # the creature the player steers shows none: the chase camera looks at its back (a bunch of balls filled
        # the middle of every mini game after a fight, perfectionist-0070)
        c.controlled && continue
        for (k, j, at, r, col) in list
            (k > length(out) || j > length(out[k][1])) && continue
            o = out[k]
            # round blobs: flat discs along the surface normal fanned out like petals on one small part (s68,
            # media/s68/spots-flat.png): the spots crowd onto one part, which wants fixing first
            # Lumi's mesh parts all sit at its feet point, so its spots hung round its feet like balloons (s70):
            # for Lumi they go on an ellipsoid round its body instead
            q = sp.name == "Lumi" ? c.pos + Point3f(0, 0, 0.95f0) + o[2][j] * (Vec3f(0.3f0, 0.28f0, 0.42f0) .* at) :
                                    o[1][j] + o[2][j] * (o[3][j] .* at)
            push!(ps, c.pos + g * (q - c.pos))
            push!(rs, Makie.Quaternionf(0, 0, 0, 1))
            push!(ss, Vec3f(g * r))
            push!(cs, col)
        end
    end
    P[:blobs_shown] = !isempty(ps)
    isempty(ps) && (ps = [Point3f(0, 0, -50)]; ss = [Vec3f(0)]; cs = [COLOURS[1]]; rs = [Makie.Quaternionf(0, 0, 0, 1)])
    Makie.update!(P[:blobs]; arg1 = ps, markersize = ss, color = cs, rotation = rs)
end

# ---------------------------------------------------------------- flying paint

body(c) = c.pos + Point3f(0, 0, 0.7f0 * NG.species_of(c).height)

function throw!(s::PaintFight, w, from::Point3f, to::Point3f, col; target = Int32(0), T = nothing, h = nothing)
    length(s.balls) >= NBALL && return
    d = flat(from, to)
    push!(s.balls, Ball(from, to, w.t, T === nothing ? 0.55 + 0.06d : T, h === nothing ? 0.4f0 + 0.18f0 * d : h, col, target))
end

function fly!(s::PaintFight, w)
    for b in copy(s.balls)
        u = (w.t - b.t0) / b.T
        u < 1 && continue
        filter!(x -> x !== b, s.balls)
        if b.target != 0
            c = NG.creature(w, b.target)
            if c !== nothing
                blob!(w, c, b.col)
                splat!(w, c.pos + Point3f(0.5randn(w.rng), 0.5randn(w.rng), 0), b.col; big = 0.7f0)
                if painting(c)
                    c.action = rand(w.rng) < 0.5 ? :scared : :laugh
                    c.goal.action = c.action
                    rand(w.rng) < 0.45 && NG.say!(w, c, rand(w.rng, HIT); duration = 1.4)
                end
                NG.emit!(w, :paint_hit; who = c.name)
            end
        else
            splat!(w, b.to, b.col)
            # a drop of the spill that lands on a friend sticks to it
            for id in s.friends
                c = NG.creature(w, id)
                painting(c) && flat(c.pos, b.to) < 0.8 && (blob!(w, c, b.col); break)
            end
        end
    end
    ps = [i <= length(s.balls) ? begin
              b = s.balls[i]; u = Float32(clamp((w.t - b.t0) / b.T, 0, 1))
              p = b.from + (b.to - b.from) * u; p + Point3f(0, 0, 4f0 * b.h * u * (1 - u))
          end : Point3f(0, 0, -50) for i in 1:NBALL]
    ms = [i <= length(s.balls) ? Vec3f(s.balls[i].target == 0 ? 0.11f0 : 0.15f0) : Vec3f(0) for i in 1:NBALL]
    cs = [i <= length(s.balls) ? s.balls[i].col : COLOURS[1] for i in 1:NBALL]
    Makie.update!(P[:balls]; arg1 = ps, markersize = ms, color = cs)
end

# ---------------------------------------------------------------- the fight

function begin!(s::PaintFight, game, me; least = 3)
    w = game.world
    near = [c for c in w.creatures if c.id != me.id && free(c) && flat(c.pos, me.pos) < REACH]
    sort!(near; by = c -> flat(c.pos, me.pos))
    length(near) < least && return false
    near = near[1:min(end, 8)]
    s.lumi = me.id
    s.friends = [c.id for c in near]
    s.state = :trip
    s.t0 = w.t
    delete!(P, :eyedir)
    s.said = 0
    empty!(s.balls); empty!(s.throw_at)
    NG.leave_interactions!(w, me)
    me.controlled || (me.goal = NG.Goal(:paint, me.pos, :scared, 60.0, w.t + 60, true, 0, false))
    for c in near
        NG.leave_interactions!(w, c)
        c.goal = NG.Goal(:paint, c.pos, :idle, 60.0, w.t + 60, true, 0, false)
        # everyone turns to watch Lumi wobble
        c.yaw = atan(me.pos[2] - c.pos[2], me.pos[1] - c.pos[1])
    end
    NG.emit!(w, :paint_trip; n = length(near))
    return true
end

function spill!(s::PaintFight, w, me)
    s.state = :spill
    s.t0 = w.t
    NG.say!(w, me, rand(w.rng, SPLOOSH); duration = 2.5)
    o = body(me) + Point3f(0.6f0 * cos(me.yaw), 0.6f0 * sin(me.yaw), 0.5f0)
    # half the drops go for a friend, the rest anywhere around
    for i in 1:NDROP
        col = COLOURS[mod1(i, 4)]
        if i <= 2length(s.friends)
            c = NG.creature(w, s.friends[mod1(i, length(s.friends))])
            to = c.pos + Point3f(0.4randn(w.rng), 0.4randn(w.rng), 0)
        else
            a = 2pi * rand(w.rng); d = 1.5f0 + 7f0 * rand(w.rng)
            to = Point3f(o[1] + d * cos(a), o[2] + d * sin(a), 0)
        end
        to = NG.ground(w.island, (to[1], to[2]))
        d = flat(o, to)
        push!(s.balls, Ball(o, to, w.t + 0.25rand(w.rng), 0.8 + 0.1d, 2.5f0 + 0.3f0 * d, col, 0))
    end
    # Lumi wears its own spill
    for _ in 1:6
        blob!(w, me, rand(w.rng, COLOURS[1:4]))
    end
    for _ in 1:5
        splat!(w, me.pos + Point3f(0.8randn(w.rng), 0.8randn(w.rng), 0), rand(w.rng, COLOURS[1:4]); big = 1.6f0)
    end
    NG.emit!(w, :paint_spill; who = me.name)
end

function fight!(s::PaintFight, w)
    if isempty(s.friends)           # every friend was taken by another event: no fight (s89: first() of none switched the plugin off)
        s.state = :after; s.t0 = w.t
        return
    end
    s.state = :fight
    s.t0 = w.t
    for (k, id) in enumerate(s.friends)
        s.throw_at[id] = w.t + 0.3 + 0.5k * rand(w.rng)
    end
    s.throw_at[s.lumi] = w.t + 1.5
    c = NG.creature(w, first(s.friends))
    NG.say!(w, c, rand(w.rng, START); duration = 2.0)
    NG.emit!(w, :paint_fight; n = length(s.friends) + 1)
end

function step_fight!(s::PaintFight, game)
    w = game.world
    everyone = [c for c in (NG.creature(w, id) for id in cast(s)) if c !== nothing && (painting(c) || c.controlled && c.id == s.lumi)]
    for c in everyone
        c.controlled && continue
        if w.t >= get(s.throw_at, c.id, Inf)
            others = [o for o in everyone if o.id != c.id && flat(o.pos, c.pos) < 9]
            isempty(others) && (others = [o for o in everyone if o.id != c.id])
            isempty(others) && continue
            # mostly the nearest few, sometimes someone across the meadow
            sort!(others; by = o -> flat(o.pos, c.pos))
            o = rand(w.rng) < 0.7 ? others[rand(w.rng, 1:min(3, end))] : rand(w.rng, others)
            c.yaw = atan(o.pos[2] - c.pos[2], o.pos[1] - c.pos[1])
            # stand and throw (a hop), then dodge a step or two
            c.goal = NG.Goal(:paint, c.pos, :jump, 0.6, w.t + 60, true, 0, false)
            c.action = :jump
            throw!(s, w, body(c) + Point3f(0, 0, 0.3f0), body(o), rand(w.rng, COLOURS); target = o.id)
            s.throw_at[c.id] = w.t + 1.1 + 1.4rand(w.rng)
        elseif w.t >= get(s.throw_at, c.id, Inf) - 0.7 && c.goal.arrived && rand(w.rng) < 0.02
            a = 2pi * rand(w.rng)
            q = c.pos + Point3f(1.6f0 * cos(a), 1.6f0 * sin(a), 0)
            NG.on_land(w.island, q[1], q[2]; margin = 0.3) &&
                (c.goal = NG.Goal(:paint, NG.ground(w.island, (q[1], q[2])), :laugh, 0.5, w.t + 60, false, 0, true))
        end
        c.goal.until = w.t + 60
    end
    # the player as Lumi throws with P too
    return everyone
end

function finish!(s::PaintFight, game)
    w = game.world
    for id in cast(s)
        c = NG.creature(w, id)
        (c === nothing || c.controlled || !painting(c)) && continue
        NG.remember!(c, w.t, "had a big paint fight with Lumi and came home covered in spots")
        c.mood = min(1f0, c.mood + 0.15f0)
        NG.choose_goal!(c, w)
    end
    empty!(s.balls); empty!(s.throw_at)
    s.state = :idle
    s.player = false
    s.next_t = w.t + GAP[1] + (GAP[2] - GAP[1]) * rand(w.rng)
    NG.emit!(w, :paint_end)
end

function NG.step!(s::PaintFight, game, dt)
    w = game.world
    s.next_t < 0 && (s.next_t = w.t + 120.0)
    # draw while anyone wears spots, and once more after the last ones went (or the plot keeps stale spots)
    (isempty(P[:until]) && !get(P, :blobs_shown, false)) || draw_blobs!(w)
    # the splats only change when one lands, and fade slowly: redraw then, or every 2 s while some lie about
    if get(P, :splats_dirty, false) || !isempty(P[:splat]) && w.t - get(P, :drawn, -Inf) > 2
        draw_splats!(w)
        P[:splats_dirty] = false
        P[:drawn] = w.t
    end
    me0 = lumi_of(w)
    # jumped in as Lumi: P trips over the pots (idle), or throws a paint ball (in a fight)
    pdown = Makie.Keyboard.p in game.keys_down
    rising = pdown && !get(P, :pdown, false)
    P[:pdown] = pdown
    if rising && me0 !== nothing && me0.controlled
        if s.state === :idle
            begin!(s, game, me0; least = 0) && (s.player = true)
        elseif s.state === :fight
            others = [c for c in (NG.creature(w, id) for id in s.friends) if painting(c)]
            if !isempty(others)
                o = argmin(c -> flat(c.pos, me0.pos + Point3f(3cos(me0.yaw), 3sin(me0.yaw), 0)), others)
                throw!(s, w, body(me0) + Point3f(0, 0, 0.4f0), body(o), rand(w.rng, COLOURS); target = o.id)
            end
        end
    end
    if s.state === :idle
        testing = game.tests !== nothing && NG.running(game.tests)
        busy_game = game.minigame !== nothing && !(game.minigame isa NG.JumpIn)
        if w.t >= s.next_t && !testing && !busy_game && 9 < 24 * NG.daytime(w) < 18.5
            me = lumi_of(w)
            ok = me !== nothing && free(me) && fx_free(w) && NG.on_land(w.island, me.pos[1], me.pos[2]; margin = 0.6) && begin!(s, game, me)
            ok && claim_fx!(w, 120.0, "paint")
            ok || (s.next_t = w.t + 60)
        end
        return
    end
    me = NG.creature(w, s.lumi)
    if me === nothing || game.minigame !== nothing && !(game.minigame isa NG.JumpIn)
        return finish!(s, game)
    end
    el = w.t - s.t0
    mine = painting(me) && !me.controlled
    if s.state === :trip
        # Lumi wobbles under the pots, everyone holds their breath
        k = min(3, 1 + floor(Int, 3el / TRIP))
        if k > s.said
            s.said = k
            NG.say!(w, me, WOBBLE[k]; duration = 1.0)
        end
        mine && (me.action = :scared; me.goal.action = :scared; me.yaw += Float32(3dt * sin(9w.t)))
        for id in s.friends
            c = NG.creature(w, id)
            painting(c) && (c.action = :gasp; c.goal.action = :gasp)
        end
        cur, since = NG.AUTO_SUBJECT[]
        watching = s.player || game.dash === nothing || game.rig.mode !== :follow || cur == s.lumi && w.t - since > 1.0
        el >= TRIP && (watching || el >= 8) && spill!(s, w, me)
    elseif s.state === :spill
        mine && (me.action = el < 1.5 ? :scared : :shy; me.goal.action = me.action)
        for id in s.friends
            c = NG.creature(w, id)
            painting(c) || continue
            if el < 1.6
                c.action = :scared
            elseif s.said < 4 + length(s.friends) && rand(w.rng) < 0.03
                s.said += 1
                NG.say!(w, c, rand(w.rng, STARE); duration = 1.6)
                c.action = :gasp
            end
            c.goal.action = c.action
        end
        el > 3.2 && isempty(s.balls) && fight!(s, w)
    elseif s.state === :fight
        everyone = step_fight!(s, game)
        if el > FIGHT || length(everyone) < 2
            s.state = :after
            s.t0 = w.t
            for (i, c) in enumerate(everyone)
                c.controlled && continue
                c.goal = NG.Goal(:paint, c.pos, :laugh, 60.0, w.t + 60, true, 0, false)
                i <= 4 && NG.say!(w, c, rand(w.rng, END); duration = 2.4)
                emote(c.id, :heart)
            end
        end
    else
        el > 1 && isempty(s.balls) && el > 5 && finish!(s, game)
    end
    s.state === :idle || fly!(s, w)
    (s.state === :trip || s.state === :spill && el < 0.2) && draw_pots!(s, w, me)
    return
end

"The camera frames the whole paint fight from a clear side, a little above."
function paint_group(w)
    s = P[:sys]
    s.state === :idle && return nothing
    me = NG.creature(w, s.lumi)
    me === nothing && return nothing
    pts = Point3f[me.pos]
    for id in s.friends
        c = NG.creature(w, id)
        c === nothing || flat(c.pos, me.pos) > 8 || push!(pts, c.pos)
    end
    mid = sum(pts) / length(pts)
    spread = maximum(p -> flat(p, mid), pts)
    far = s.state === :trip ? 6.5f0 : clamp(1.4f0 * Float32(spread) + 4f0, 7.5f0, 12f0)
    d = get(P, :eyedir, nothing)
    d === nothing && (d = P[:eyedir] = clear_side(w, me, 12f0))
    look = s.state === :trip ? me.pos : mid
    eye = look + Point3f(far * d[1], far * d[2], 0.38f0 * far)
    return (me.id, pts, (eye, look + Point3f(0, 0, 0.9f0)))
end

"A side out from Lumi with no tree, bush, rock or the Big Boing toadstool in the line of sight; the camera's own side first."
function clear_side(w, me, reach = 9f0)
    rig = P[:game].rig
    a0 = atan(rig.eye[2] - me.pos[2], rig.eye[1] - me.pos[1])
    blocks = [(Point2f(p.pos[1], p.pos[2]), (p.kind === :tree ? 2.4f0 : 1.2f0) * p.scale) for p in w.props if p.kind in (:tree, :bush, :rock)]
    isdefined(Main, :BOING) && haskey(Main.BOING, :center) && push!(blocks, (Point2f(Main.BOING[:center][1], Main.BOING[:center][2]), 3.6f0))
    for da in (0f0, 0.5f0, -0.5f0, 1f0, -1f0, 1.5f0, -1.5f0, 2f0, -2f0, 2.6f0, -2.6f0, Float32(pi))
        d = Vec2f(cos(a0 + da), sin(a0 + da))
        ok = all(b -> all(t -> hypot(me.pos[1] + reach * t * d[1] - b[1][1], me.pos[2] + reach * t * d[2] - b[1][2]) > b[2], 0.15f0:0.1f0:1.05f0), blocks)
        ok && return d
    end
    return Vec2f(cos(a0), sin(a0))
end

function NG.start!(s::PaintFight, game)
    P[:sys] = s
    P[:game] = game
    P[:splat] = Any[]
    haskey(P, :spots) || (P[:spots] = Dict{Int32,Vector{Any}}())
    haskey(P, :until) || (P[:until] = Dict{Int32,Float64}())
    # spots from before s71 had 25 min to go: no longer than STAY from now
    for (id, t) in P[:until]
        P[:until][id] = min(t, game.world.t + STAY)
    end
    # spots from before s68's placement had no part instance: drop them (the draw takes 5 fields)
    filter!(kv -> all(x -> length(x) == 5, kv[2]), P[:spots])
    delete!(P, :eyedir)
    plots!(game)
    NG.CAMERA_MOMENTS["paintfight"] = w -> s.state === :idle ? nothing : s.lumi
    NG.CAMERA_GROUPS["paintfight"] = paint_group
    isdefined(Main, :LUMI_DOING) && (Main.LUMI_DOING[:paint] = "PAINT FIGHT!")
end

function NG.stop!(s::PaintFight, game)
    delete!(NG.CAMERA_MOMENTS, "paintfight")
    delete!(NG.CAMERA_GROUPS, "paintfight")
    s.state === :idle || finish!(s, game)
    for k in (:balls, :splats, :blobs, :pots)
        haskey(P, k) && P[k].parent !== nothing && delete!(P[k].parent, P[k])
    end
end

register!(PaintFight())
