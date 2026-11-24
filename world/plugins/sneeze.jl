# The Big Sneeze (session 64): now and then a feather tickles Lumi's beak. "ah... ah... AAAH..." the
# friends around it freeze, gasp and lean back... "AH-CHOOOO!!!" A storm of golden feathers bursts off
# Lumi, every friend close by is blown head over heels backwards, lands dizzy, and the island shouts
# "Bless you!". Then they all scramble for the feathers fluttering down, and Lumi stands there plucked
# and embarrassed.
isdefined(Main, :SNEEZE) || Core.eval(Main, :(const SNEEZE = Dict{Symbol,Any}()))
const NG = NeverendingGame
const S = Main.SNEEZE

const GAP = (360.0, 600.0)        # sim seconds between two sneezes
const REACH = 9.5f0               # friends this close are blown away
const N = 140                     # feathers
const WIND = 3.4                  # seconds of "ah... ah..."
const GOLD = RGBf(1.0, 0.74, 0.22)
const AHS = ("ah...", "ah... ah...", "AH... AAAH...")
const CHOOS = ("AH-CHOOOO!!!", "AAH-CHOOOOO!!!", "HA-CHOOOM!!!")
const UHOH = ("Uh oh...", "Duck!", "She's gonna blow!", "Hold on to something!", "Not again...")
const BLESS = ("Bless you!", "Bless you!!", "Gesundheit!", "Whoaaa!", "My ears!")
const FIND = ("A golden feather!", "Mine! Mine!", "So shiny!", "I'll keep it forever!", "Feather hat!")
const KEEP = (:follow, :answer, :conga, :circle, :rain, :build, :tinker, :kite, :boing, :boing_walk,
              :hide, :found, :freeze)

push!(NG.BUSY_GOALS, :sneezed)

mutable struct Sneeze <: System
    state::Symbol                 # :idle, :wind, :choo, :after
    t0::Float64
    next_t::Float64
    lumi::Int32
    friends::Vector{Int32}
    flights::Dict{Int32,Any}      # id => (from, to, T, spin)
    hunt::Dict{Int32,Int}         # id => feather index it runs for
    fpos::Vector{Point3f}         # feathers
    fvel::Vector{Vec3f}
    fspin::Vector{Float32}
    frest::Vector{Bool}
    fgone::Vector{Bool}
    said::Int
    player::Bool                  # the player pressed X (Lumi is jumped in)
end
Sneeze() = Sneeze(:idle, 0.0, -1.0, 0, Int32[], Dict{Int32,Any}(), Dict{Int32,Int}(),
                  fill(Point3f(0), N), fill(Vec3f(0), N), zeros(Float32, N), fill(true, N), fill(true, N), 0, false)

emote(id, kind) = isdefined(Main, :EMOTES) && haskey(Main.EMOTES, :emote) && Base.invokelatest(Main.EMOTES[:emote], id, kind)
lumi_of(w) = (i = findfirst(c -> c.name == "Lumi", w.creatures); i === nothing ? nothing : w.creatures[i])
free(c) = !c.controlled && c.goal.kind ∉ KEEP && c.goal.kind !== :sneezed   # nappers get blown out of bed too
flat(a, b) = hypot(a[1] - b[1], a[2] - b[2])
head(c) = c.pos + Point3f(0.35f0 * cos(c.yaw), 0.35f0 * sin(c.yaw), 1.35f0)

# ---------------------------------------------------------------- feathers

function feather_plot!(game)
    haskey(S, :plot) && S[:plot].parent !== nothing && delete!(S[:plot].parent, S[:plot])
    # a feather: a long thin flattened ellipsoid (one hidden copy always, the raster needs one)
    haskey(S, :wornplot) && S[:wornplot].parent !== nothing && delete!(S[:wornplot].parent, S[:wornplot])
    S[:wornplot] = meshscatter!(game.stage.scene, [Point3f(0, 0, -50)]; marker = Sphere(Point3f(0), 1f0),
                                markersize = [Vec3f(0)], rotation = [Makie.Quaternionf(0, 0, 0, 1)], color = GOLD, name = :sneeze_worn)
    S[:plot] = meshscatter!(game.stage.scene, fill(Point3f(0, 0, -50), N); marker = Sphere(Point3f(0), 1f0),
                            markersize = fill(Vec3f(0), N), rotation = fill(Makie.Quaternionf(0, 0, 0, 1), N),
                            color = GOLD, name = :sneeze_feathers)
end

function draw_feathers!(s::Sneeze, w)
    p = S[:plot]
    ms = [s.fgone[i] ? Vec3f(0) : Vec3f(0.08, 0.28, 0.02) for i in 1:N]
    rot = [Makie.qrotation(Vec3f(0, 0, 1), s.fspin[i] * Float32(s.frest[i] ? 1 : w.t)) *
           Makie.qrotation(Vec3f(1, 0, 0), s.frest[i] ? 0f0 : 0.6f0 * sin(Float32(3w.t) + i)) for i in 1:N]
    Makie.update!(p; arg1 = copy(s.fpos), markersize = ms, rotation = rot)
end

# a feather in the cap: whoever caught one wears it stuck upright on top of its head for a while
const WEAR = 1500.0     # sim seconds (25 min)
const MAXW = 12

function draw_worn!(w)
    worn = S[:worn]
    filter!(kv -> kv[2] > w.t, worn)
    ps = Point3f[]; rs = Makie.Quaternionf[]; ss = Vec3f[]
    t = Float32(w.t)
    for (id, _) in worn
        c = NG.creature(w, id)
        (c === nothing || length(ps) >= MAXW) && continue
        sp = NG.species_of(c)
        out = [(Point3f[], Makie.Quaternionf[], Vec3f[]) for _ in sp.parts]
        NG.pose_parts!(out, sp, c.pos, c.yaw, c.action, c.phase, c.mood, c.extra, c.seed, t)
        top = c.pos; tz = -1f9
        for o in out, i in eachindex(o[1])
            q = o[1][i] + o[2][i] * (o[3][i] .* Vec3f(0, 0, 1))
            q[3] > tz && (tz = q[3]; top = q)
        end
        sway = 0.15f0 * sin(3t + c.seed)
        push!(ps, top + Point3f(0, 0, 0.08f0))
        push!(rs, Makie.qrotation(Vec3f(0, 0, 1), c.yaw + sway) * Makie.qrotation(Vec3f(1, 0, 0), 1.25f0))
        push!(ss, Vec3f(0.045, 0.15, 0.012))
    end
    isempty(ps) && (ps = [Point3f(0, 0, -50)]; rs = [Makie.Quaternionf(0, 0, 0, 1)]; ss = [Vec3f(0)])
    Makie.update!(S[:wornplot]; arg1 = ps, rotation = rs, markersize = ss)
end

function burst!(s::Sneeze, w, me)
    o = head(me)
    for i in 1:N
        a = 2pi * rand(w.rng)
        up = 2.5 + 5.5 * rand(w.rng)
        side = 2.0 + 5.0 * rand(w.rng)
        s.fpos[i] = o + Point3f(0.2randn(w.rng), 0.2randn(w.rng), 0.2rand(w.rng))
        s.fvel[i] = Vec3f(side * cos(a) + 3cos(me.yaw), side * sin(a) + 3sin(me.yaw), up)
        s.fspin[i] = Float32(2pi * rand(w.rng)) * (rand(w.rng) < 0.5 ? -1 : 1)
        s.frest[i] = false
        s.fgone[i] = false
    end
end

function fly_feathers!(s::Sneeze, w, dt)
    for i in 1:N
        (s.fgone[i] || s.frest[i]) && continue
        v = s.fvel[i]
        # gravity, a lot of air drag, and a leafy side-to-side sway on the way down
        v = v + Vec3f(0, 0, -9.0f0 * dt)
        v = v * Float32(exp(-2.2dt))
        sway = 0.9f0 * sin(Float32(4w.t) + 1.7f0i)
        p = s.fpos[i] + Point3f(v * Float32(dt)) + Point3f(sway * Float32(dt), 0, 0)
        g = NG.ground(w.island, (p[1], p[2]))
        if p[3] <= g[3] + 0.03f0 && v[3] < 0
            p = Point3f(p[1], p[2], g[3] + 0.03f0)
            s.frest[i] = true
        end
        s.fpos[i] = p
        s.fvel[i] = v
    end
end

# ---------------------------------------------------------------- the sneeze

function wind_up!(s::Sneeze, game, me; least = 3)
    w = game.world
    friends = [c for c in w.creatures if c !== me && free(c) && flat(c.pos, me.pos) < REACH]
    length(friends) < least && return false
    s.state = :wind
    s.t0 = w.t
    S[:eyedir] = nothing
    s.lumi = me.id
    s.friends = [c.id for c in friends]
    s.said = 0
    empty!(s.flights); empty!(s.hunt); S[:ready] = Dict{Int32,Float64}()
    for c in friends
        NG.leave_interactions!(w, c)
        c.goal = NG.Goal(:sneezed, c.pos, :gasp, 60.0, w.t + 60, true, 0, false)
        c.yaw = atan(me.pos[2] - c.pos[2], me.pos[1] - c.pos[1])
    end
    NG.leave_interactions!(w, me)
    me.controlled || (me.goal = NG.Goal(:sneezed, me.pos, :gasp, 60.0, w.t + 60, true, 0, false))
    NG.say!(w, me, AHS[1]; duration = 1.2)
    isempty(friends) || NG.say!(w, friends[1], rand(w.rng, UHOH); duration = 2.0)
    NG.emit!(w, :sneeze_windup; n = length(friends), who = join([c.name for c in friends], ", "))
    return true
end

function choo!(s::Sneeze, game)
    w = game.world
    me = NG.creature(w, s.lumi)
    s.state = :choo
    s.t0 = w.t
    NG.say!(w, me, rand(w.rng, CHOOS); duration = 2.5)
    burst!(s, w, me)
    for id in s.friends
        c = NG.creature(w, id)
        (c === nothing || c.goal.kind !== :sneezed) && continue
        d = flat(c.pos, me.pos)
        dir = d < 0.1 ? Vec2f(cos(me.yaw), sin(me.yaw)) : Vec2f(c.pos[1] - me.pos[1], c.pos[2] - me.pos[2]) / Float32(d)
        far = 2.0f0 + 0.45f0 * (REACH - Float32(d))
        to = c.pos
        for k in 10:-1:1   # as far as the land goes
            q = c.pos + Point3f(dir[1] * far * k / 10, dir[2] * far * k / 10, 0)
            if NG.on_land(w.island, q[1], q[2]; margin = 0.15)
                to = NG.ground(w.island, (q[1], q[2])); break
            end
        end
        s.flights[id] = (from = c.pos, to = to, T = 0.9 + 0.08far, h = 0.6f0 + 0.18f0 * far,
                         spin = (rand(w.rng) < 0.5 ? -1f0 : 1f0) * (9f0 + 6f0 * rand(w.rng)))
        c.goal.action = :scared
    end
    NG.emit!(w, :sneeze; n = length(s.flights), who = join([NG.creature(w, id).name for id in keys(s.flights)], ", "))
end

function step_flights!(s::Sneeze, w, dt)
    for (id, f) in collect(s.flights)
        c = NG.creature(w, id)
        if c === nothing || c.controlled || c.goal.kind !== :sneezed
            delete!(s.flights, id); continue
        end
        u = min(1.0, (w.t - s.t0) / f.T)
        p = f.from + (f.to - f.from) * Float32(u)
        c.pos = Point3f(p[1], p[2], p[3] + 4f0 * f.h * Float32(u * (1 - u)))
        c.yaw += f.spin * Float32(dt) * Float32(1 - u)
        c.action = :scared; c.goal.action = :scared
        if u >= 1
            delete!(s.flights, id)
            c.pos = NG.ground(w.island, (f.to[1], f.to[2]))
            c.goal = NG.Goal(:sneezed, c.pos, :gasp, 30.0, w.t + 30, true, 0, false)
            S[:ready][id] = w.t + 1.4 + rand(w.rng)      # dizzy for a moment, then off for the feathers
            NG.emit!(w, :sneeze_landed; who = c.name)
        end
    end
end

function nearest_feather(s::Sneeze, c, taken)
    best, bi = 1f9, 0
    for i in 1:N
        (s.fgone[i] || !s.frest[i] || i in taken) && continue
        d = flat(s.fpos[i], c.pos)
        d < best && (best = d; bi = i)
    end
    return bi
end

function after!(s::Sneeze, w)
    # landed friends shout "bless you", then run for the feathers
    for id in s.friends
        c = NG.creature(w, id)
        (c === nothing || c.goal.kind !== :sneezed || haskey(s.flights, id)) && continue
        if !haskey(s.hunt, id) && w.t >= get(S[:ready], id, Inf)
            i = nearest_feather(s, c, values(s.hunt))
            if i == 0
                c.goal = NG.Goal(:sneezed, c.pos, :laugh, 2.0, w.t + 2.0, true, 0, false)
                s.hunt[id] = -1
            else
                rand(w.rng) < 0.7 && NG.say!(w, c, rand(w.rng, BLESS); duration = 1.8)
                s.hunt[id] = i
                c.goal = NG.Goal(:sneezed, s.fpos[i], :jump, 1.2, w.t + 40, false, 0, true)
            end
        elseif get(s.hunt, id, 0) > 0
            i = s.hunt[id]
            if flat(c.pos, s.fpos[i]) < 0.9 || c.goal.arrived
                s.fgone[i] = true
                NG.say!(w, c, rand(w.rng, FIND); duration = 2.0)
                emote(id, :heart)
                NG.remember!(c, w.t, "caught one of Lumi's golden sneeze feathers")
                c.mood = min(1f0, c.mood + 0.1f0)
                NG.emit!(w, :sneeze_feather; who = c.name)
                S[:worn][id] = w.t + WEAR
                c.goal = NG.Goal(:sneezed, c.pos, :proud, 2.5, w.t + 2.5, true, 0, false)
                s.hunt[id] = -1
            end
        end
    end
end

function finish!(s::Sneeze, game)
    w = game.world
    for id in vcat(s.friends, [s.lumi])
        c = NG.creature(w, id)
        # never a controlled one: a mini game that starts takes Lumi over, and a new goal stopped it walking (s64 review)
        (c === nothing || c.controlled || c.goal.kind !== :sneezed) && continue
        NG.choose_goal!(c, w)
    end
    empty!(s.flights); empty!(s.hunt)
    s.state = :idle
    s.player = false
    s.next_t = w.t + GAP[1] + (GAP[2] - GAP[1]) * rand(w.rng)
    NG.emit!(w, :sneeze_end)
end

function NG.step!(s::Sneeze, game, dt)
    w = game.world
    s.next_t < 0 && (s.next_t = w.t + 60.0)
    isempty(S[:worn]) || draw_worn!(w)
    # feathers left on the grass blow away one by one
    # jumped in as Lumi: X sneezes (on the press, once per sneeze)
    xdown = Makie.Keyboard.x in game.keys_down
    me0 = lumi_of(w)
    if xdown && !get(S, :xdown, false) && s.state === :idle && me0 !== nothing && me0.controlled
        wind_up!(s, game, me0; least = 0) && (s.player = true)
    end
    S[:xdown] = xdown
    if s.state === :idle
        if any(!, s.fgone)
            for i in 1:N
                s.fgone[i] || rand(w.rng) < 0.25dt && (s.fgone[i] = true)
            end
            draw_feathers!(s, w)
        end
        testing = game.tests !== nothing && NG.running(game.tests)
        busy_game = game.minigame !== nothing && !(game.minigame isa NG.JumpIn)
        if w.t >= s.next_t && !testing && !busy_game && 8 < 24 * NG.daytime(w) < 19.5
            me = lumi_of(w)
            # on open land only: on the pier the friends flew into the sea and the feathers sank (s64)
            ok = me !== nothing && free(me) && me.action !== :sleep && NG.on_land(w.island, me.pos[1], me.pos[2]; margin = 0.6) &&
                 wind_up!(s, game, me)
            ok || (s.next_t = w.t + 45)
        end
        return
    end
    me = NG.creature(w, s.lumi)
    if me === nothing || game.minigame !== nothing && !(game.minigame isa NG.JumpIn)
        return finish!(s, game)
    end
    el = w.t - s.t0
    if s.state === :wind
        # friends lean back and gasp while Lumi's head tips back further and further
        k = min(3, 1 + floor(Int, 3el / WIND))
        if k > s.said
            s.said = k
            (me.goal.kind === :sneezed || s.player) && NG.say!(w, me, AHS[k]; duration = 1.3)
        end
        for id in s.friends
            c = NG.creature(w, id)
            c !== nothing && c.goal.kind === :sneezed && (c.goal.until = w.t + 60; c.action = :gasp)
        end
        # hold the last "AAAH..." until the follow camera has been on Lumi a moment, so the burst is seen
        # (s64: the camera arrived after the CHOO and showed only the feathers on the grass)
        cur, since = NG.AUTO_SUBJECT[]
        watching = s.player || game.dash === nothing || game.rig.mode !== :follow || cur == s.lumi && w.t - since > 1.2
        el >= WIND && (watching || el >= 9.0) && choo!(s, game)
    elseif s.state === :choo
        step_flights!(s, w, dt)
        if me.goal.kind === :sneezed
            me.goal.action = el < 1.2 ? :proud : :shy
            me.goal.until = w.t + 60
        end
        if isempty(s.flights)
            s.state = :after
            s.t0 = w.t
            (me.goal.kind === :sneezed || s.player) && NG.say!(w, me, "...oops. Excuse me.", duration = 2.5)
        end
    else
        after!(s, w)
        if el > 3.5 && me.goal.kind === :sneezed
            NG.feel!(w, me, :shy; seconds = 3.0)
        end
        if el > 25 || isempty(s.friends) && el > 3 || all(id -> (c = NG.creature(w, id); c === nothing || c.goal.kind !== :sneezed), s.friends)
            finish!(s, game)
        end
    end
    s.state === :idle || (fly_feathers!(s, w, dt); draw_feathers!(s, w))
    return
end

"A side 7 m out from Lumi with no tree, bush, rock or the Big Boing toadstool in the line of sight; the camera's own side first."
function clear_side(w, me)
    rig = S[:game].rig
    a0 = atan(rig.eye[2] - me.pos[2], rig.eye[1] - me.pos[1])
    blocks = [(Point2f(p.pos[1], p.pos[2]), (p.kind === :tree ? 2.4f0 : 1.2f0) * p.scale) for p in w.props if p.kind in (:tree, :bush, :rock)]
    isdefined(Main, :BOING) && haskey(Main.BOING, :center) && push!(blocks, (Point2f(Main.BOING[:center][1], Main.BOING[:center][2]), 3.6f0))
    for da in (0f0, 0.5f0, -0.5f0, 1f0, -1f0, 1.5f0, -1.5f0, 2f0, -2f0, 2.6f0, -2.6f0, Float32(pi))
        d = Vec2f(cos(a0 + da), sin(a0 + da))
        ok = all(b -> all(t -> hypot(me.pos[1] + 7f0t * d[1] - b[1][1], me.pos[2] + 7f0t * d[2] - b[1][2]) > b[2], 0.15f0:0.1f0:1.05f0), blocks)
        ok && return d
    end
    return Vec2f(cos(a0), sin(a0))
end

"The camera frames Lumi with every friend it blew away."
function sneeze_group(w)
    s = S[:sys]
    (s.state === :idle || s.state === :after && w.t - s.t0 > 6) && return nothing
    me = NG.creature(w, s.lumi)
    me === nothing && return nothing
    pts = Point3f[me.pos]
    for id in s.friends
        c = NG.creature(w, id)
        c === nothing || flat(c.pos, me.pos) > 14 || push!(pts, c.pos)
    end
    # close enough to see the feathers: 7 m out on the side the camera already is, a little above
    d = get(S, :eyedir, nothing)
    d === nothing && (d = S[:eyedir] = clear_side(w, me))
    eye = me.pos + Point3f(7f0 * d[1], 7f0 * d[2], 3.0f0)
    return (me.id, pts, (eye, me.pos + Point3f(0, 0, 1.2f0)))
end

function NG.start!(s::Sneeze, game)
    S[:sys] = s
    S[:game] = game
    S[:ready] = Dict{Int32,Float64}()
    haskey(S, :worn) || (S[:worn] = Dict{Int32,Float64}())
    feather_plot!(game)
    NG.CAMERA_MOMENTS["sneeze"] = w -> (s.state === :idle || s.state === :after && w.t - s.t0 > 6) ? nothing : s.lumi
    NG.CAMERA_GROUPS["sneeze"] = sneeze_group
    isdefined(Main, :LUMI_DOING) && (Main.LUMI_DOING[:sneezed] = "ah... ah... CHOO!")
end

function NG.stop!(s::Sneeze, game)
    delete!(NG.CAMERA_MOMENTS, "sneeze")
    delete!(NG.CAMERA_GROUPS, "sneeze")
    s.state === :idle || finish!(s, game)
    for k in (:plot, :wornplot)
        haskey(S, k) && S[k].parent !== nothing && delete!(S[k].parent, S[k])
    end
end

register!(Sneeze())
