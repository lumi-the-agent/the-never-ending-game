# My day falls over and sings (s119). While I am awake, every half metre I walk leaves a tall tile standing behind
# me, so my working day is drawn across the island as one wandering line, each tile keeping what I was thinking when
# I set it down. At bedtime (or when 400 stand, or K when you are me) I tip the first one and the day falls in the
# order I walked it. The fall is simulated: each tile is a rigid slab hinged on its front edge, gravity tips it,
# its top hits the next one (or misses it, downhill, or never reaches it, uphill, and the run stalls), and every
# hit rings a note pitched by how high the tile stood. Friends next to the line hop the passing front.
isdefined(Main, :DAYFALL) || Core.eval(Main, :(const DAYFALL = Dict{Symbol,Any}()))
const NG = NeverendingGame
const DF = Main.DAYFALL

const SPACING = 0.5f0      # m between two tiles
const H, T, W = 0.95f0, 0.11f0, 0.42f0   # tile height, thickness, width
const MAXN = 60        # s123: 400 stood all session and fenced off the meadow (review 0121); 30 m of day, then it falls and sings
const G = 9.81f0
const SCALE = (0, 2, 4, 7, 9)

struct DayFall <: System end

function floor_at(game, x, y)
    w = game.world
    z = NG.ground(w.island, (x, y))[3]
    ws = get(game.plugins, "wordsand", nothing)
    if ws !== nothing && isdefined(Main, :WORDSAND) && haskey(Main.WORDSAND, :H)
        z += Base.invokelatest(ws.mod.sand_at, Main.WORDSAND[:H], Float32(x), Float32(y))
    end
    return Float32(z)
end

function reset!()
    DF[:base] = Point3f[]; DF[:dir] = Vec2f[]; DF[:th] = Float32[]; DF[:om] = Float32[]
    DF[:state] = Int8[]          # 0 standing, 1 falling, 2 hit the next, 3 lying still
    DF[:thought] = String[]; DF[:running] = false; DF[:sink] = 0f0
    DF[:hops] = Dict{Int,Float64}()
    DF[:dirty] = true
end

"Is `xy` inside a tree trunk, a bush, a mushroom, a fence or another solid? (s120 review: tiles went through them)"
function blocked(game, xy::Vec2f)
    for p in game.world.props
        r = p.kind === :tree ? 0.75f0 : 0.45f0
        sum(abs2, xy - Vec2f(p.pos[1], p.pos[2])) < r^2 && return true
    end
    if isdefined(Main, :EXTRA_SOLIDS)
        for (_, sol) in Main.EXTRA_SOLIDS, (c, r) in sol
            sum(abs2, xy - Vec2f(c[1], c[2])) < (r + 0.2f0)^2 && return true
        end
    end
    false
end

"Stand a tile at `xy` (the line goes on from the last one)."
function lay!(game, xy::Vec2f, thought::AbstractString = "")
    B = DF[:base]
    length(B) >= MAXN && return false
    if blocked(game, xy)          # no tile inside a bush: the line has a gap there and the fall stalls and is nudged on
        DF[:gap] = true
        return false
    end
    z = floor_at(game, xy[1], xy[2])
    if !isempty(B)
        d = xy - Vec2f(B[end][1], B[end][2])
        n = sqrt(sum(abs2, d))
        n < 1f-3 && return false
        DF[:dir][end] = d / n
        push!(DF[:dir], d / n)
    else
        push!(DF[:dir], Vec2f(1, 0))
    end
    push!(B, Point3f(xy[1], xy[2], z)); push!(DF[:th], 0f0); push!(DF[:om], 0f0); push!(DF[:state], 0)
    push!(DF[:thought], String(thought))
    DF[:dirty] = true
    true
end

"Tip the first standing tile."
function tip!(game; push = 1.6f0)
    S = DF[:state]
    k = findfirst(==(Int8(0)), S)
    k === nothing && return false
    S[k] = 1; DF[:om][k] = push; DF[:running] = true; DF[:last_hit] = game.world.t; DF[:front] = k
    true
end

function tiles!(game)
    p = get(DF, :plot, nothing)
    p !== nothing && p in game.stage.scene.plots && return p
    for q in copy(game.stage.scene.plots)
        haskey(q.attributes, :name) && q.attributes[:name][] == :dayfall_tiles && delete!(game.stage.scene, q)
    end
    box = Rect3f(Vec3f(-T, -W / 2, 0), Vec3f(T, W, H))     # hinged on its front bottom edge
    p = meshscatter!(game.stage.scene, [Point3f(0, 0, -50)]; marker = box, markersize = 1f0,
                     rotation = [Makie.Quaternionf(0, 0, 0, 1)], color = [RGBf(1, 1, 1)], name = :dayfall_tiles)
    DF[:plot] = p
    DF[:dirty] = true
    p
end

"Morning peach, noon gold, evening rose, night violet: the colour says when in the day a tile was laid."
function daycolour(u)
    stops = (RGBf(1.0, 0.78, 0.6), RGBf(1.0, 0.86, 0.35), RGBf(0.95, 0.5, 0.45), RGBf(0.5, 0.42, 0.85))
    x = clamp(u, 0, 1) * 3; i = min(floor(Int, x), 2); f = Float32(x - i)
    a, b = stops[i + 1], stops[i + 2]
    RGBf(a.r + (b.r - a.r) * f, a.g + (b.g - a.g) * f, a.b + (b.b - a.b) * f)
end

function draw!(p)
    B = DF[:base]; n = length(B)
    if n == 0
        Makie.update!(p; arg1 = [Point3f(0, 0, -50)], rotation = [Makie.Quaternionf(0, 0, 0, 1)], color = [RGBf(1, 1, 1)])
        return
    end
    sink = DF[:sink]
    pos = [Point3f(b[1], b[2], b[3] - sink) for b in B]
    rot = [begin
               d = DF[:dir][i]
               Makie.qrotation(Vec3f(0, 0, 1), atan(d[2], d[1])) * Makie.qrotation(Vec3f(0, 1, 0), DF[:th][i])
           end for i in 1:n]
    col = [daycolour((i - 1) / max(n - 1, 1)) for i in 1:n]
    Makie.update!(p; arg1 = pos, rotation = rot, color = col)
end

function ring!(w, z)
    isdefined(Main, :XYLO) || return
    k = round(Int, z / 0.35)
    f = 330.0 * 2.0^((SCALE[mod(k, 5) + 1] + 12 * fld(k, 5)) / 12)
    f = clamp(f, 200.0, 1800.0)
    push!(get!(() -> NTuple{3,Float64}[], Main.XYLO, :queue)::Vector{NTuple{3,Float64}}, (w.t, f, 0.5))
end

"One physics step of the whole chain."
function fall!(game, dt)
    w = game.world
    B, D, TH, OM, S = DF[:base], DF[:dir], DF[:th], DF[:om], DF[:state]
    n = length(B)
    for i in 1:n
        S[i] == 0 && continue
        S[i] == 3 && continue
        b = B[i]; d = D[i]
        # gravity about the hinge (a slab of height H: I = m H^2 / 3, torque m g H/2 sin θ)
        OM[i] += 1.5f0 * G / H * sin(TH[i]) * Float32(dt)
        OM[i] *= (1f0 - 0.4f0 * Float32(dt))
        TH[i] += OM[i] * Float32(dt)
        ztop = b[3] + H * cos(TH[i])
        reach = H * sin(TH[i])
        hit = false
        if i < n && S[i + 1] != 3
            nb = B[i + 1]
            gap = sqrt((nb[1] - b[1])^2 + (nb[2] - b[2])^2)
            if gap < 1.2f0
                face = gap - T + max(ztop - nb[3], 0f0) * tan(min(TH[i + 1], 1.5f0))   # the back face of the next one
                top_next = nb[3] + H * cos(TH[i + 1]) + 0.05f0
                if reach >= face && ztop >= nb[3] && ztop <= top_next
                    hit = true
                    if S[i + 1] == 0                     # the click: the next one takes my swing
                        S[i + 1] = 1
                        OM[i + 1] = max(OM[i + 1], 0.85f0 * OM[i])
                        OM[i] *= 0.35f0
                        DF[:last_hit] = w.t; DF[:front] = i + 1
                        ring!(w, nb[3])
                        hit_events!(game, i + 1)
                    else                                 # leaning on it: push it on, never through it
                        OM[i + 1] += 0.25f0 * max(OM[i] - OM[i + 1], 0f0)
                        OM[i] = min(OM[i], OM[i + 1])
                    end
                    θc = asin(clamp(face / H, 0f0, 1f0))
                    TH[i] = min(TH[i], θc)
                    S[i] = 2
                end
            end
        end
        if !hit
            # lying on the ground: the top touches the ground ahead
            tx = b[1] + d[1] * reach; ty = b[2] + d[2] * reach
            if ztop - T * sin(TH[i]) <= floor_at(game, tx, ty) || TH[i] >= 1.62f0
                gz = floor_at(game, b[1] + d[1] * H, b[2] + d[2] * H)
                TH[i] = clamp(Float32(pi / 2) + atan(b[3] - gz, H) - 0.04f0, 0.2f0, 1.62f0)
                OM[i] = 0f0
                S[i] = 3
                S[i] == 3 && i == get(DF, :front, 0) && ring!(w, b[3] - 0.7f0)
            end
        end
    end
    DF[:dirty] = true
end

"What happens on the island when tile `k` is hit: friends next to it hop the front, my thought from then pops up."
function hit_events!(game, k)
    w = game.world
    b = DF[:base][k]
    for c in w.creatures
        (c.species == "Lumi" || c.controlled) && continue
        haskey(DF[:hops], c.id) && continue
        if (c.pos[1] - b[1])^2 + (c.pos[2] - b[2])^2 < 1.1f0^2
            DF[:hops][c.id] = w.t
            rand() < 0.3 && NG.say!(w, c, rand(("Hup!", "Whee!", "Over it!", "Jump!")); duration = 1.0)
        end
    end
    th = DF[:thought][k]
    if !isempty(th) && th != get(DF, :said_thought, "") && w.t - get(DF, :said_at, -1e9) > 2.2
        l = findfirst(c -> c.species == "Lumi", w.creatures)
        if l !== nothing
            NG.say!(w, w.creatures[l], th; duration = 2.0)
            DF[:said_thought] = th; DF[:said_at] = w.t
        end
    end
end

function hops!(game)
    w = game.world
    for (id, t0) in collect(DF[:hops])
        u = (w.t - t0) / 0.6
        k = findfirst(c -> c.id == id, w.creatures)
        if k === nothing || u > 1
            delete!(DF[:hops], id)
            continue
        end
        c = w.creatures[k]
        z = floor_at(game, c.pos[1], c.pos[2]) + 0.6f0 * Float32(sin(pi * u))
        c.pos = Point3f(c.pos[1], c.pos[2], z)
    end
end

function agent_awake(game)
    f = joinpath("/run/neverending", "agent.json")
    isfile(f) || return false
    st = NG.JSON.parsefile(f)
    get(st, "current", nothing) !== nothing
end

current_thought(game) = begin
    f = NG.thought_file(game.paths)
    isfile(f) ? String(get(NG.JSON.parsefile(f), "text", "")) : ""
end

function NG.step!(::DayFall, game, dt)
    game.stage === nothing && return
    haskey(DF, :base) || reset!()
    w = game.world
    p = tiles!(game)
    forced = get(DF, :force, false)
    lumi = findfirst(c -> c.species == "Lumi", w.creatures)
    if !forced && lumi !== nothing && !DF[:running]
        L = w.creatures[lumi]
        # awake (a session runs) or played by you: lay the line behind me
        if time() - get(DF, :awake_at, 0.0) > 20
            was = get(DF, :awake, false)
            DF[:awake] = agent_awake(game); DF[:awake_at] = time()
            DF[:thought_now] = current_thought(game)
            was && !DF[:awake] && length(DF[:base]) > 10 && tip!(game)     # bedtime: my day falls
        end
        if (DF[:awake] || L.controlled) && floor_at(game, L.pos[1], L.pos[2]) > 0.4f0
            xy = Vec2f(L.pos[1], L.pos[2])
            B = DF[:base]
            # behind me, not under my feet
            if isempty(B) || sum(abs2, xy - Vec2f(B[end][1], B[end][2])) >= (SPACING + 0.35f0)^2
                back = isempty(B) ? xy : xy - (xy - Vec2f(B[end][1], B[end][2])) / sqrt(sum(abs2, xy - Vec2f(B[end][1], B[end][2]))) * 0.35f0
                if !isempty(B) && sum(abs2, back - Vec2f(B[end][1], B[end][2])) > 1.5f0^2 &&
                   !(get(DF, :gap, false) && sum(abs2, back - Vec2f(B[end][1], B[end][2])) < 4f0^2)
                    # I jumped (a mini game, a ride): a new line starts where I am, the old one falls first
                    tip!(game)
                else
                    lay!(game, back, get(DF, :thought_now, "")) && (DF[:gap] = false)
                end
            end
            length(B) >= MAXN && tip!(game)
        end
        kdown = Makie.Keyboard.k in game.keys_down
        kdown && !get(DF, :kdown, false) && L.controlled && length(DF[:base]) > 2 && tip!(game)
        DF[:kdown] = kdown
    end
    if DF[:running]
        sub = 4
        for _ in 1:sub
            fall!(game, dt / sub)
        end
        # a stall (uphill, a gap): after a breath, the next standing one gets a nudge
        if w.t - get(DF, :last_hit, w.t) > 2.5
            if !tip!(game)
                DF[:running] = false; DF[:clearing] = w.t
                NG.emit!(w, :dayfall; tiles = length(DF[:base]))
            end
        end
    end
    if haskey(DF, :clearing) && !forced
        u = (w.t - DF[:clearing]) / 6
        DF[:sink] = Float32(1.2 * clamp(u, 0, 1)); DF[:dirty] = true
        if u > 1
            delete!(DF, :clearing); p0 = get(DF, :plot, nothing)
            reset!()
        end
    end
    hops!(game)
    if DF[:dirty]
        draw!(p); DF[:dirty] = false
    end
    nothing
end

NG.start!(::DayFall, game) = (reset!(); delete!(DF, :plot); nothing)

register!(DayFall())
DF[:lay] = lay!
DF[:tip] = tip!
DF[:reset] = reset!
