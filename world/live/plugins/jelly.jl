# I swallow what I hit (s118). Now and then I go jelly: I hop at a friend, a clear green jelly swells round me
# and swallows it, and the friend floats inside, slowly turning, while I wobble about with it. Then a hiccup
# squashes the jelly and spits the friend out in an arc. Traced, the jelly is real glass with a green medium
# inside (Hikari MediumInterface), so the friend is seen through it, bent and tinted; live it is see-through green.
isdefined(Main, :JELLY) || Core.eval(Main, :(const JELLY = Dict{Symbol,Any}()))
const NG = NeverendingGame
const J = Main.JELLY

const EVERY = 240.0        # real seconds between swallows in the live game
const T_HOP, T_GULP, T_CARRY, T_HIC, T_END = 1.1, 1.9, 9.0, 9.6, 10.8
const RAD = Vec3f(1.05, 1.05, 1.0)   # the full jelly's radii (Lumi is 1.4 m tall, a friend 0.5 m)

struct Jelly <: System end
push!(NG.BUSY_GOALS, :jelly)          # nobody calls a friend away from inside me

smooth(u) = (u = clamp(u, 0, 1); u * u * (3 - 2u))
gnd(w, xy) = NG.ground(w.island, (xy[1], xy[2]))[3]

function coat!(game)
    p = get(J, :plot, nothing)
    p !== nothing && p in game.stage.scene.plots && return p
    for q in copy(game.stage.scene.plots)       # a crashed earlier run's coat
        haskey(q.attributes, :name) && q.attributes[:name][] == :jelly_coat && delete!(game.stage.scene, q)
    end
    glass = NG.Hikari.Glass(color = (0.92, 1.0, 0.9), ior = 1.36)
    inside = NG.Hikari.HomogeneousMedium(σ_a = NG.Hikari.RGBSpectrum(0.55f0, 0.06f0, 0.5f0),
                                         σ_s = NG.Hikari.RGBSpectrum(0.03f0))
    p = mesh!(game.stage.scene, Makie.Sphere(Point3f(0), 1f0); color = RGBAf(0.45, 0.95, 0.4, 0.38),
              transparency = true, visible = false,
              material = NG.Hikari.MediumInterface(glass; inside = inside), name = :jelly_coat)
    J[:plot] = p
    p
end

"Start a swallow: Lumi hops at `victim` (a creature)."
function swallow!(game, victim)
    w = game.world
    lumi = findfirst(c -> c.species == "Lumi", w.creatures)
    lumi === nothing && return false
    l = w.creatures[lumi]
    J[:lumi] = l; J[:victim] = victim
    J[:t0] = w.t
    J[:from] = Vec2f(l.pos[1], l.pos[2])
    d = Vec2f(victim.pos[1] - l.pos[1], victim.pos[2] - l.pos[2])
    n = max(norm(d), 0.1f0)
    J[:dir] = d / n
    J[:to] = Vec2f(victim.pos[1], victim.pos[2]) - J[:dir] * 0.35f0
    J[:said] = Set{Symbol}()
    J[:yaw0] = victim.yaw
    J[:active] = true
    J[:player] = l.controlled
    for c in (l, victim)
        c.controlled && continue
        c.action = :idle
        c.goal = NG.Goal(:jelly, c.pos, :idle, 60.0, w.t + 60, true, 0, false)
    end
    true
end

norm(v) = sqrt(sum(abs2, v))

say_once!(w, c, key, text) = (key in J[:said] || (push!(J[:said], key); NG.say!(w, c, text; duration = 1.8)))

function NG.step!(::Jelly, game, dt)
    game.stage === nothing && return
    w = game.world
    p = coat!(game)
    if !get(J, :active, false)
        p.visible[] && (p.visible = false)
        # the player as Lumi: J swallows whoever is nearest (within 3.5 m)
        jdown = Makie.Keyboard.j in game.keys_down
        jedge = jdown && !get(J, :jdown, false)
        J[:jdown] = jdown
        if jedge
            me = findfirst(c -> c.species == "Lumi" && c.controlled, w.creatures)
            if me !== nothing
                M = w.creatures[me]
                ds = [(norm(Vec2f(c.pos[1] - M.pos[1], c.pos[2] - M.pos[2])), k) for (k, c) in enumerate(w.creatures) if c !== M]
                best = isempty(ds) ? nothing : minimum(ds)
                if best !== nothing && best[1] < 3.5f0
                    swallow!(game, w.creatures[best[2]])
                else
                    NG.say!(w, M, "Nobody close enough to swallow..."; duration = 1.8)
                end
                return
            end
        end
        get(J, :force, false) && return              # films start it themselves
        time() - get!(J, :last, time()) < EVERY && return
        J[:last] = time()
        l = findfirst(c -> c.species == "Lumi", w.creatures)
        l === nothing && return
        L = w.creatures[l]
        near = [c for c in w.creatures if c !== L && norm(Vec2f(c.pos[1] - L.pos[1], c.pos[2] - L.pos[2])) < 7 &&
                                          !(c.goal.kind in NG.BUSY_GOALS) && !c.controlled]
        isempty(near) || swallow!(game, rand(near))
        return
    end
    l, v = J[:lumi], J[:victim]
    ts = Float32(get(J, :tscale, 1f0))         # films may run the whole swallow faster
    t = (w.t - J[:t0]) * ts
    dir = J[:dir]; side = Vec2f(-dir[2], dir[1])
    for c in (l, v)
        c.controlled && continue
        c.action = :idle
        c.goal = NG.Goal(:jelly, c.pos, :idle, 60.0, w.t + 60, true, 0, false)
    end
    heading = NG.species_of(l).heading
    # where Lumi is: hop to the victim, then a slow wobbly stroll in a small arc
    if t < T_HOP
        u = smooth(t / T_HOP)
        xy = J[:from] + (J[:to] - J[:from]) * u
        hop = 0.9f0 * sin(Float32(pi) * clamp(t / T_HOP, 0, 1))
        l.pos = Point3f(xy[1], xy[2], gnd(w, xy) + hop)
        l.yaw = Float32(atan(dir[2], dir[1])) - heading
    elseif !(get(J, :player, false) && l.controlled)    # the player walks me about with the friend inside
        s = Float32(clamp(t - T_GULP, 0, T_HIC - T_GULP))
        a = 0.12f0 * s
        xy = J[:to] + dir * (1.4f0 * sin(a)) + side * (1.4f0 * (1 - cos(a)))
        wob = (t > T_GULP && t < T_HIC) ? 0.06f0 * abs(sin(6f0 * s)) : 0f0
        l.pos = Point3f(xy[1], xy[2], gnd(w, xy) + wob)
        fw = dir * cos(a) + side * sin(a)
        l.yaw = Float32(atan(fw[2], fw[1])) - heading
    end
    lp = l.pos
    centre = Point3f(lp[1], lp[2], lp[3] + 0.8f0)
    # the coat: grows on the hop, swells round the friend, wobbles, squashes for the hiccup, shrinks away
    g = t < T_HOP ? 0.75f0 * smooth(t / T_HOP) :
        t < T_GULP ? 0.75f0 + 0.25f0 * smooth((t - T_HOP) / (T_GULP - T_HOP)) :
        t < T_HIC ? 1f0 : 1f0 - smooth((t - T_HIC - 0.3) / (T_END - T_HIC - 0.3))
    # a damped wobble after each impact (the gulp and the hiccup), and a slow jiggle while walking
    k1 = t > T_GULP ? exp(-2.2f0 * (t - T_GULP)) * sin(14f0 * (t - T_GULP)) : 0f0
    k2 = t > T_HIC ? exp(-3f0 * (t - T_HIC)) * sin(16f0 * (t - T_HIC)) : 0f0
    jig = (t > T_GULP && t < T_HIC) ? 0.04f0 * sin(7f0 * t) : 0f0
    sq = 0.22f0 * k1 + 0.3f0 * k2 + jig
    pre = (t > T_HIC - 0.35 && t < T_HIC) ? 0.25f0 * smooth((t - (T_HIC - 0.35)) / 0.35) : 0f0   # gathering the hiccup
    sz = g * RAD[3] * (1 - sq - pre)
    sxy = g * RAD[1] * (1 + 0.5f0 * sq + 0.15f0 * pre)
    if g > 0.01f0
        Makie.translate!(p, centre[1], centre[2], lp[3] + sz)
        Makie.scale!(p, sxy, sxy, sz)
        p.visible[] || (p.visible = true)
    else
        p.visible[] && (p.visible = false)
    end
    # the friend: stands until the jelly reaches it, then floats inside turning; the hiccup throws it out
    if t < T_HOP
        # waits, unaware
    elseif t < T_HIC
        u = smooth((t - T_HOP) / (T_GULP - T_HOP))
        fw = Vec2f(cos(l.yaw + heading), sin(l.yaw + heading))
        fo = haskey(J, :toward) ? 0.55f0 * fw + 0.45f0 * J[:toward] : fw   # films: a little toward the camera
        inside = Point3f(lp[1] + fo[1] * 0.6f0, lp[2] + fo[2] * 0.6f0, lp[3] + 0.55f0 + 0.12f0 * sin(2.3f0 * t))
        start = J[:vstart] = get(J, :vstart, v.pos)
        v.pos = Point3f(start[1] + (inside[1] - start[1]) * u, start[2] + (inside[2] - start[2]) * u,
                        start[3] + (inside[3] - start[3]) * u)
        v.yaw = J[:yaw0] + 1.6f0 * Float32(t - T_HOP)
        J[:out] = (v.pos, fw)
    elseif t < T_END + 0.4 + 1.2f0 * ts
        # thrown out along the way I hopped: a real ballistic arc that stops where it meets the ground
        p0 = J[:out][1]; fw = -J[:dir]           # over my shoulder, back the way I came
        s_ = Float32(t - T_HIC) / ts
        if !haskey(J, :landed)
            x = p0[1] + fw[1] * 2.8f0 * s_; y = p0[2] + fw[2] * 2.8f0 * s_
            z = p0[3] + 5.0f0 * s_ - 4.905f0 * s_^2
            gz = gnd(w, Vec2f(x, y))
            if z <= gz && s_ > 0.1f0
                J[:landed] = Point3f(x, y, gz)
            else
                v.pos = Point3f(x, y, z)
                v.yaw += 10f0 * Float32(dt)
            end
        end
        haskey(J, :landed) && (v.pos = J[:landed])
    end
    # what is said
    t > 0.2 && say_once!(w, l, :hop, "Bwoing!")
    t > T_GULP + 0.2 && say_once!(w, l, :gulp, "...oops. *gulp*")
    t > T_GULP + 2.4 && say_once!(w, v, :in, "It's squishy in here!")
    t > T_GULP + 5.0 && say_once!(w, v, :out, "Let me OUT!")
    t > T_HIC - 0.1 && say_once!(w, l, :hic, "HIC!")
    if t > T_END + 0.4 + 1.2f0 * ts
        v.pos = Point3f(v.pos[1], v.pos[2], gnd(w, Vec2f(v.pos[1], v.pos[2])))
        say_once!(w, v, :land, "...again?")
        NG.emit!(w, :jelly_swallow; who = l.name, swallowed = v.name)
        for c in (l, v)
            c.controlled || (c.goal = NG.Goal())
        end
        J[:active] = false
        delete!(J, :vstart); delete!(J, :landed)
        p.visible = false
    end
    nothing
end

NG.start!(::Jelly, game) = (J[:active] = false; delete!(J, :plot); nothing)

register!(Jelly())
J[:swallow] = swallow!
