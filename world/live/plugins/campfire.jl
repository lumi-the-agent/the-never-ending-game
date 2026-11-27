# A campfire to keep in check (s152, project fire, physics/fire.jl). On the south shore at (-3.0, -16.0): a log crib
# inside a ring of six wooden stakes. Jumped in as Lumi beside it: 7 lights the crib (or builds a new one once it is out),
# 8 throws a beakful of sea water on the stake or log nearest Lumi. The wind turns slowly round the island; the stake
# the flames lean onto heats, dries, catches, chars and falls (FireBody: heat by radiation and flame contact, the
# EN 1995-1-2 reduced section). Fire time runs on the island's clock (a day is 5 h, so 4.8x real time).
using GeometryBasics, Makie, LinearAlgebra
isdefined(Main, :LOCAL_KEYS) || Core.eval(Main, :(const LOCAL_KEYS = Dict{String,Any}()))
isdefined(Main, :CAMPFIRE) || Core.eval(Main, :(const CAMPFIRE = Dict{Symbol,Any}()))
const NG = NeverendingGame
const CF = Main.CAMPFIRE
Base.include(@__MODULE__, joinpath(@__DIR__, "..", "physics", "fire.jl"))

const CF_SPOT = (-3.0f0, -16.0f0)     # the clearest place on the island (NOTES 'Fire'): sand, 1.4 m from anything
const CF_NEAR = 2.2f0
const CF_LIGHT = Makie.Keyboard._7
const CF_WATER = Makie.Keyboard._8
const CF_WIND = 2f0                   # m/s, a steady sea breeze that turns round the island
const CF_TURN = 2f0 * Float32(pi) / 600f0   # rad per island-second: once round in 10 island minutes
const CF_DRAW = 1 / 12                # redraw the wood and the flames 12 times a second

struct Campfire <: System end

function cf_bodies(burning::Bool)
    bs = FireBody[]
    # a log crib: two logs along x, two across them along y
    push!(bs, fire_body(1, :wood, (0f0, -0.12f0, 0.045f0), (0.42f0, 0.09f0, 0.09f0); moisture = 0.08, burning, T = burning ? 700f0 : FIRE_TAMB))
    push!(bs, fire_body(2, :wood, (0f0, 0.12f0, 0.045f0), (0.42f0, 0.09f0, 0.09f0); moisture = 0.08, burning, T = burning ? 700f0 : FIRE_TAMB))
    push!(bs, fire_body(3, :wood, (-0.12f0, 0f0, 0.135f0), (0.09f0, 0.42f0, 0.09f0); moisture = 0.08, burning, T = burning ? 700f0 : FIRE_TAMB))
    push!(bs, fire_body(4, :wood, (0.12f0, 0f0, 0.135f0), (0.09f0, 0.42f0, 0.09f0); moisture = 0.08, burning, T = burning ? 700f0 : FIRE_TAMB))
    for k in 1:6                       # a ring of stakes 0.48 m out
        a = (k - 1) * Float32(pi) / 3
        push!(bs, fire_body(10 + k, :wood, (0.48f0 * cos(a), 0.48f0 * sin(a), 0.4f0), (0.07f0, 0.07f0, 0.8f0); load = 0.3))
    end
    return bs
end

const CF_WOOD = (0.55f0, 0.36f0, 0.2f0)
const CF_CHAR = (0.07f0, 0.05f0, 0.04f0)
function cf_color(b::FireBody, fuel0)
    s = clamp(b.char / 0.008f0 + (1 - b.fuel / fuel0) + (b.burning ? 0.2f0 : 0f0), 0f0, 1f0)
    RGBf((1 - s) .* CF_WOOD .+ s .* CF_CHAR...)
end

"Every piece of wood as a box (a fallen stake lies as `fall!` left it; a burning log thins as its fuel goes)."
function cf_wood_mesh(bs, fuel0, o)
    ms = GeometryBasics.Mesh[]; cols = RGBf[]
    for b in bs
        f = b.id <= 4 ? max(b.fuel / fuel0[b.id], 0.15f0) : 1f0
        sz = b.id <= 4 ? (b.size[1] >= b.size[2] ? Vec3f(b.size[1], f * b.size[2], f * b.size[3]) : Vec3f(f * b.size[1], b.size[2], f * b.size[3])) : Vec3f(b.size...)
        c = Point3f(o[1] + b.pos[1], o[2] + b.pos[2], o[3] + b.pos[3] - 0.5f0 * (b.size[3] - sz[3]))
        m = GeometryBasics.expand_faceviews(GeometryBasics.normal_mesh(Rect3f(c - 0.5f0 * sz, sz)))
        push!(ms, m)
        append!(cols, fill(cf_color(b, fuel0[b.id]), length(GeometryBasics.coordinates(m))))
    end
    m = merge(ms)
    return m, cols
end

"The flames: per merged flame, tongues from the fuel up along its lean (Heskestad height, Thomas lean)."
function cf_flame_mesh(bs, flames, t, o)
    ms = GeometryBasics.Mesh[]
    byid = Dict(b.id => b for b in bs)
    for (c, L, Q, ids) in flames
        L < 0.03f0 && continue
        g = [byid[i] for i in ids]
        bx = sum(b -> b.pos[1], g) / length(g); by = sum(b -> b.pos[2], g) / length(g)
        bz = minimum(b -> b.pos[3] + 0.5f0 * b.size[3], g)
        base = Point3f(o[1] + bx, o[2] + by, o[3] + bz)
        axis = Vec3f(o[1] + c[1], o[2] + c[2], o[3] + c[3]) - base
        D = clamp(0.1f0 * L, 0.03f0, 0.09f0)
        sp = clamp(0.5f0 * maximum(b -> max(b.size[1], b.size[2]), g), 0.05f0, 0.4f0)
        for j in 1:7
            a = 2f0 * Float32(pi) * j / 7 + 0.7f0 * t
            off = j == 1 ? Vec3f(0) : Vec3f(0.6f0 * sp * cos(a), 0.4f0 * sp * sin(a), 0)
            h = 1f0 + 0.2f0 * sin(9f0 * t + 2.1f0 * j) + 0.1f0 * sin(23f0 * t + j)
            b0 = base + off - Vec3f(0, 0, 0.05f0)
            push!(ms, GeometryBasics.normal_mesh(Cylinder(b0, b0 + (j == 1 ? 1.8f0 : 1.4f0 * h) * axis, (j == 1 ? 1f0 : 0.6f0) * D)))
        end
    end
    isempty(ms) && return GeometryBasics.expand_faceviews(GeometryBasics.normal_mesh(Cylinder(Point3f(o[1], o[2], o[3] - 3), Point3f(o[1], o[2], o[3] - 2.9f0), 0.01f0)))
    return GeometryBasics.expand_faceviews(merge(ms))
end

function cf_ensure!(game)
    haskey(CF, :wood) && CF[:wood].parent === game.stage.scene && return
    sc = game.stage.scene
    for p in copy(sc.plots)
        haskey(p.attributes, :name) && startswith(string(p.attributes[:name][]), "campfire_") && delete!(sc, p)
    end
    g = NG.ground(game.world.island, CF_SPOT)
    CF[:o] = Point3f(g[1], g[2], g[3])
    # a reload defines FireBody anew: bodies kept in Main.CAMPFIRE from before are of the old type (s152: MethodError)
    get(CF, :bodies, nothing) isa Vector{FireBody} || cf_reset!(false)
    m, cols = cf_wood_mesh(CF[:bodies], CF[:fuel0], CF[:o])
    CF[:wood] = mesh!(sc, m; color = cols, material = NG.Hikari.Diffuse(color = CF_WOOD, roughness = 0.9f0), name = :campfire_wood)
    CF[:flame] = mesh!(sc, cf_flame_mesh(CF[:bodies], [], 0f0, CF[:o]); color = RGBf(1.0, 0.55, 0.15),
                       material = NG.Hikari.Emission(color = (1.0, 0.52, 0.14), strength = 6.0), name = :campfire_flame)
    CF[:drawn] = 0.0
    # the chase view stood behind Lumi, its body hid the fire (s152): from the sea side, Lumi and the ring both in view
    isdefined(Main, :LOCAL_CAMS) || Core.eval(Main, :(const LOCAL_CAMS = Dict{String,Any}()))
    oo = CF[:o]
    Main.LOCAL_CAMS["campfire"] = gm -> (get(CF, :near, false) && gm.minigame isa NG.JumpIn) ?
        (Point3f(oo[1] - 0.6f0, oo[2] - 2.7f0, oo[3] + 1.5f0), Point3f(oo[1] - 0.3f0, oo[2] + 0.1f0, oo[3] + 0.35f0)) : nothing
    Main.LOCAL_KEYS["campfire"] = gm -> get(CF, :near, false) ?
        (any(b -> b.burning, CF[:bodies]) ? "8 throw sea water on the nearest wood" : "7 light the fire   8 throw sea water") : nothing
    return
end

function cf_reset!(burning)
    CF[:bodies] = cf_bodies(burning)
    CF[:fuel0] = Dict(b.id => b.fuel for b in CF[:bodies])
    CF[:said] = Set{Tuple{Int,Symbol}}()
    return
end

function NG.step!(::Campfire, game, dt)
    game.stage === nothing && return
    me = NG.creature(game.world, "Lumi")
    me === nothing && return
    get(CF, :bodies, nothing) isa Vector{FireBody} || delete!(CF, :wood)
    cf_ensure!(game)
    w = game.world; o = CF[:o]; bs = CF[:bodies]
    t0 = time_ns()
    free = game.minigame === nothing || game.minigame isa NG.JumpIn
    near = me.controlled && free && hypot(me.pos[1] - o[1], me.pos[2] - o[2]) < CF_NEAR
    CF[:near] = near
    pressed(k) = (s = Symbol("key_", Int(k)); d = k in game.keys_down; was = get(CF, s, false); CF[s] = d; d && !was)
    if near && pressed(CF_LIGHT)
        if !any(b -> b.burning, bs)
            all(b -> b.id > 4 || b.fuel < 0.2f0 * CF[:fuel0][b.id], bs) || any(b -> b.broken, bs) ? cf_reset!(true) :
                foreach(b -> b.id <= 4 && (b.burning = true; b.mflux = b.mat.G; b.T = max(b.T, 700f0)), bs)
            bs = CF[:bodies]
            NG.say!(w, me, "There! Now where is the wind going?"; duration = 3.0)
            NG.emit!(w, :campfire_lit)
        end
    end
    if near && pressed(CF_WATER)
        # the nearest wood to Lumi's beak gets a beakful (0.4 kg) of sea water
        tip = (me.pos[1] - o[1] + 0.35f0 * cos(me.yaw), me.pos[2] - o[2] + 0.35f0 * sin(me.yaw))
        i = argmin([hypot(b.pos[1] - tip[1], b.pos[2] - tip[2]) for b in bs])
        water!(bs[i], 0.4f0)
        NG.emit!(w, :campfire_water; target = bs[i].id, burning = bs[i].burning)
    end
    # wind: a breeze turning slowly round
    a = CF_TURN * Float32(w.t)
    wind = (CF_WIND * cos(a), CF_WIND * sin(a))
    CF[:wind] = wind
    k = Float32(86400 / w.day_length)            # fire runs on the island's clock
    ft = Float32(min(dt, 0.1)) * k
    n = max(1, ceil(Int, ft / 0.5f0))
    for _ in 1:n
        CF[:t] = get(CF, :t, 0f0) + ft / n
        for (id, e, _) in fire_step!(bs, ft / n, CF[:t]; wind)
            (id, e) in CF[:said] && continue
            push!(CF[:said], (id, e))
            id > 4 && e === :ignite && NG.say!(w, me, "A stake's caught! Water, quick!"; duration = 3.0)
            id > 4 && e === :break && (NG.say!(w, me, "Oh no, it's going over!"; duration = 3.0); NG.feel!(w, me, :sad))
            NG.emit!(w, :campfire_event; id, what = e)
        end
    end
    # draw: the wood when it changes colour, the flames while they burn (path traced: held still, NOTES 'OOM')
    if time() - CF[:drawn] > CF_DRAW
        CF[:drawn] = time()
        m, cols = cf_wood_mesh(bs, CF[:fuel0], o)
        CF[:wood][1][] = m; CF[:wood].color[] = cols
        if !NG.path_traced(game)
            CF[:flame][1][] = cf_flame_mesh(bs, merged_flames(bs, wind), Float32(time() % 1000), o)
        end
    end
    CF[:ms] = (time_ns() - t0) / 1e6
    return
end

function NG.stop!(::Campfire, game)
    game.stage === nothing && return
    for p in copy(game.stage.scene.plots)
        haskey(p.attributes, :name) && startswith(string(p.attributes[:name][]), "campfire_") && delete!(game.stage.scene, p)
    end
    delete!(CF, :wood)
    delete!(Main.LOCAL_KEYS, "campfire")
end

register!(Campfire())
