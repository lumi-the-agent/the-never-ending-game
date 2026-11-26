# The island weighs its words (session 115): everything anyone says pours out of the speech bubble as a
# trickle of sand and lands at the speaker's feet. Loud words (!, CAPITALS) pour more, long ones longer.
# The sand slides down to its angle of repose, so busy chatting spots grow into dunes, and the speaker is
# lifted onto the heap. The wind takes a little each minute, so the island is a map of its recent talk:
# a hill where they argued, a dune where Gloop shouts "Higher!" all day.
#   Main.WORDSAND[:H]  the sand heights on a 0.5 m grid over -HALF..HALF (m)
#   Main.WORDSAND[:speed]  how fast sand pours (1; films speed it up for a timelapse)
isdefined(Main, :WORDSAND) || Core.eval(Main, :(const WORDSAND = Dict{Symbol,Any}()))
const NG = NeverendingGame
const WS = Main.WORDSAND

const HALF = 50f0                    # the grid covers -50..50 m (the land is inside ~45 m)
const CELL = 0.5f0
const N = round(Int, 2HALF / CELL) + 1
const SIGMA = 0.9f0                  # a word's heap spreads about this far (m)
const REPOSE = 0.33f0                # steepest sand slope (rise per metre) before it slides
const WIND = 0.05f0                  # share of the sand the wind takes per minute
const SWEEP = 0.012f0                # m the wind lifts off every cell per minute: a dusting blows away, the meadow shows again (s117: the island had become a sandpit)
const POUR = 1.6f0                   # s a word takes to pour out
const MAXH = 2.0f0                   # no dune higher than this: the follow camera (2-3 m over its subject) stays out of the sand
const SINK = 0.25f0                  # the first 25 cm of sand settle into the grass and are not drawn: a dusting leaves the meadow green, only real dunes show (s118: the meadow round the cottage read as a sandpit, perfectionist s115/s117)
const GRAINS = 360                   # falling grains drawn at once
const SAND_LO = RGBf(0.86, 0.72, 0.47)   # thin sand: pale gold
const SAND_HI = RGBf(0.93, 0.62, 0.36)   # deep heaps: warmer, apricot (STYLE: warm, saturated)

struct WordSand <: System end

xy(i, j) = (-HALF + (i - 1) * CELL, -HALF + (j - 1) * CELL)
cellof(x, y) = (clamp(round(Int, (x + HALF) / CELL) + 1, 1, N), clamp(round(Int, (y + HALF) / CELL) + 1, 1, N))

"How much sand a sentence weighs (peak height in m): longer is more, '!' and CAPITALS are loud."
function weight(text::AbstractString)
    n = count(isletter, text)
    loud = count(==('!'), text) > 0 ? 1.8f0 : 1f0
    caps = n > 0 && count(isuppercase, text) > 0.6n ? 1.6f0 : 1f0
    return min(0.12f0, (0.012f0 + 0.0022f0 * n) * loud * caps)
end

"Pour `amount` (peak m) of sand around (x, y), spread like a little heap."
function deposit!(H, x, y, amount)
    i0, j0 = cellof(x, y)
    r = ceil(Int, 2.5f0 * SIGMA / CELL)
    @inbounds for i in max(1, i0 - r):min(N, i0 + r), j in max(1, j0 - r):min(N, j0 + r)
        px, py = xy(i, j)
        d2 = (px - x)^2 + (py - y)^2
        H[i, j] += amount * exp(-d2 / (2SIGMA^2))
    end
end

"Sand slides from a cell to a lower neighbour while the slope between them is steeper than its angle of repose."
function slide!(H, box)
    lim = REPOSE * CELL
    i1, i2, j1, j2 = box
    moved = false
    @inbounds for _ in 1:6, i in max(2, i1):min(N - 1, i2), j in max(2, j1):min(N - 1, j2)
        h = H[i, j]
        h < 0.002f0 && continue
        for (di, dj) in ((1, 0), (-1, 0), (0, 1), (0, -1))
            d = H[i, j] - H[i + di, j + dj]
            if d > lim
                m = 0.25f0 * (d - lim)
                H[i, j] -= m; H[i + di, j + dj] += m
                moved = true
            end
        end
    end
    return moved
end

"Where sand lies: the box of cells to look at (grown by every deposit)."
function grow_box(b, x, y)
    i0 = cellof(x, y)
    r = ceil(Int, 2.5f0 * SIGMA / CELL) + 8
    return (min(b[1], i0[1] - r), max(b[2], i0[1] + r), min(b[3], i0[2] - r), max(b[4], i0[2] + r))
end

function sand_at(H, x, y)
    i, j = cellof(x, y)
    T = get(WS, :T, nothing)
    T === nothing && return max(0f0, H[i, j] - SINK)
    return max(0f0, H[i, j] * shore_thin(T[i, j]) - SINK)
end

"How much of a cell's sand is drawn: none at the waterline, all of it 0.55 m up the beach (see `sand_mesh`)."
shore_thin(t) = clamp((t - 0.05f0) / 0.5f0, 0f0, 1f0)

"The sand as one mesh draped over the ground (only cells with sand in them)."
function sand_mesh(H, T)
    pts = Vector{Point3f}(undef, N * N)
    cols = Vector{RGBf}(undef, N * N)
    @inbounds for j in 1:N, i in 1:N
        x, y = xy(i, j)
        # toward the waterline the drawn sand thins to nothing, so its edge sinks under the beach instead of
        # standing over it in dark teeth (s117: the black band along the shore, perfectionist s115)
        h = max(0f0, H[i, j] * shore_thin(T[i, j]) - SINK)
        pts[i + (j - 1) * N] = Point3f(x, y, T[i, j] + h - 0.05f0)         # no sand: just under the grass
        a = clamp(h / 0.9f0, 0f0, 1f0)
        speck = 0.94f0 + 0.06f0 * Float32((hash((i, j)) % 1000) / 1000)
        c = SAND_LO * (1 - a) + SAND_HI * a
        cols[i + (j - 1) * N] = RGBf(c.r * speck, c.g * speck, c.b * speck)
    end
    faces = GeometryBasics.TriangleFace{Int}[]
    @inbounds for j in 1:N-1, i in 1:N-1
        k = i + (j - 1) * N
        max(H[i, j], H[i + 1, j], H[i, j + 1], H[i + 1, j + 1]) > SINK + 0.04f0 || continue
        min(T[i, j], T[i + 1, j], T[i, j + 1], T[i + 1, j + 1]) > 0.05f0 || continue   # not in the sea (no corner dips)
        push!(faces, GeometryBasics.TriangleFace(k, k + 1, k + N + 1))
        push!(faces, GeometryBasics.TriangleFace(k, k + N + 1, k + N))
    end
    isempty(faces) && push!(faces, GeometryBasics.TriangleFace(1, 2, N + 1))
    return GeometryBasics.Mesh(pts, faces; normal = GeometryBasics.normals(pts, faces)), cols
end

state_file(game) = joinpath(game.paths.state, "wordsand.bin")

"""
The ground as the terrain mesh draws it (straight between its 0.9 m samples, `NG.terrain_mesh`), not the smooth
height function: on round hilltops the curve lies centimetres above the drawn ground, and thin sand poked out of
it in a jagged staircase along its edge (first film, s115).
"""
function drawn_ground(isl; n = 220)
    ext = 2.2f0 * isl.radius
    xs = range(-ext, ext; length = n)
    G = [NG.terrain_height(isl, x, y) for x in xs, y in xs]
    d = Float32(step(xs))
    T = zeros(Float32, N, N)
    for j in 1:N, i in 1:N
        x, y = xy(i, j)
        u = (x + ext) / d + 1; v = (y + ext) / d + 1
        a = clamp(floor(Int, u), 1, n - 1); b = clamp(floor(Int, v), 1, n - 1)
        fu = clamp(u - a, 0f0, 1f0); fv = clamp(v - b, 0f0, 1f0)
        # the same split as the mesh's faces: (a,b)-(a+1,b)-(a+1,b+1) and (a,b)-(a+1,b+1)-(a,b+1)
        T[i, j] = fu >= fv ? G[a, b] + fu * (G[a + 1, b] - G[a, b]) + fv * (G[a + 1, b + 1] - G[a + 1, b]) :
                             G[a, b] + fv * (G[a, b + 1] - G[a, b]) + fu * (G[a + 1, b + 1] - G[a, b + 1])
    end
    return T
end

function setup!(game)
    sc = game.stage.scene
    for p in [p for p in sc.plots if haskey(p.attributes, :name) && p.attributes[:name][] in (:wordsand, :wordsand_grains)]
        delete!(sc, p)                                                    # names are unique (a crashed run's leftovers)
    end
    T = drawn_ground(game.world.island)
    H = zeros(Float32, N, N)
    f = state_file(game)
    isfile(f) && filesize(f) == sizeof(H) && read!(f, H)
    WS[:T] = T; WS[:H] = H; WS[:box] = (1, N, 1, N)
    m, cols = sand_mesh(H, T)
    WS[:plot] = mesh!(sc, m; color = cols, name = :wordsand, shading = true,
                      material = NG.Hikari.Diffuse(color = (1, 1, 1)))
    WS[:grains] = meshscatter!(sc, fill(Point3f(0, 0, -50), GRAINS); markersize = 0.045, color = SAND_HI,
                               name = :wordsand_grains)
    WS[:pours] = Any[]
    WS[:heard] = Dict{Int32,Float64}()
    WS[:scene] = sc
    WS[:dirty] = false; WS[:redraw_at] = 0.0; WS[:save_at] = game.world.t + 60; WS[:wind_at] = game.world.t + 60
    WS[:lift] = Dict{Int32,Float32}()
    get!(WS, :speed, 1f0)
    get!(WS, :poured, 0)
end

function NG.step!(::WordSand, game, dt)
    game.stage === nothing && return
    get(WS, :scene, nothing) === game.stage.scene || setup!(game)
    w = game.world
    H = WS[:H]::Matrix{Float32}
    T = WS[:T]::Matrix{Float32}
    speed = Float32(WS[:speed])
    heard = WS[:heard]::Dict{Int32,Float64}
    pours = WS[:pours]::Vector{Any}
    # new words: everyone whose speech bubble started since we last listened
    for s in w.speech
        get(heard, s.who, -Inf) >= s.from && continue
        heard[s.who] = s.from
        c = NG.creature(w, s.who)
        c === nothing && continue
        NG.terrain_height(w.island, c.pos[1], c.pos[2]) > 0.1f0 || continue        # words said at sea sink
        push!(pours, (who = s.who, t0 = w.t, amount = weight(s.text) * Float32(get(WS, :gain, 1f0)), x = c.pos[1], y = c.pos[2]))
        WS[:poured] += 1
    end
    # pouring: the sand of each word lands over POUR seconds, at the speaker's feet as it walks
    if !isempty(pours)
        for (k, p) in enumerate(pours)
            c = NG.creature(w, p.who)
            x, y = c === nothing ? (p.x, p.y) : (c.pos[1], c.pos[2])
            deposit!(H, x, y, p.amount * Float32(dt) * speed / POUR)
            WS[:box] = grow_box(WS[:box], x, y)
            pours[k] = merge(p, (x = x, y = y))
        end
        filter!(p -> w.t - p.t0 < POUR / speed, pours)
        WS[:dirty] = true
    end
    draw_grains!(game, pours)
    # the wind takes a little; the sand slides to its slope
    if w.t >= WS[:wind_at]
        WS[:wind_at] = w.t + 60
        H .= max.(H .* (1 - WIND) .- SWEEP, 0f0)
        WS[:dirty] = true
    end
    # s125: while a stomp rings the ground, stomp.jl lifts this mesh; redrawing it flat then made the sand flicker
    stomping = isdefined(Main, :STOMP) && haskey(Main.STOMP, :sys) && Main.STOMP[:sys].active
    if WS[:dirty] && w.t >= WS[:redraw_at] && !stomping
        WS[:redraw_at] = w.t + 0.5
        WS[:dirty] = false
        slide!(H, WS[:box])
        clamp!(H, 0f0, Float32(get(WS, :maxh, MAXH)))     # films may set WS[:maxh] higher
        m, cols = sand_mesh(H, T)
        pl = WS[:plot]
        Makie.update!(pl; arg1 = m, color = cols)
    end
    lift!(w, H)
    w.t >= get(WS, :hill_at, 0.0) && (WS[:hill_at] = w.t + 1.0; hill_life!(w, H))
    sled!(w, H, Float32(dt))
    if w.t >= WS[:save_at]
        WS[:save_at] = w.t + 60
        game.dash === nothing || write(state_file(game), H)
    end
end

const BOASTS = ("I'm the king of the hill!", "Look how tall I am!", "I can see the sea from here!", "Higher!")
const FALLS = ("WHOAAA!", "Uh oh. UH OH!", "Avalanche!", "Not again!")

"""
Life on a dune, once a second: whoever stands high on the sand boasts about it (which pours more sand under them),
and a dune that grows too tall under someone gives way: it slumps, spreads wide, and they ride it down shouting.
"""
function hill_life!(w, H)
    boasted = get!(() -> Dict{Int32,Float64}(), WS, :boasted)::Dict{Int32,Float64}
    sleds = get!(() -> Dict{Int32,Any}(), WS, :sleds)::Dict{Int32,Any}
    for c in w.creatures
        (c.controlled || c.action === :sleep) && continue
        h = sand_at(H, c.pos[1], c.pos[2])
        if h > 1.4f0 && rand() < 0.04
            x, y = c.pos[1], c.pos[2]
            i0, j0 = cellof(x, y)
            r = ceil(Int, 3f0 / CELL)
            gone = 0f0
            @inbounds for i in max(1, i0 - r):min(N, i0 + r), j in max(1, j0 - r):min(N, j0 + r)
                px, py = xy(i, j)
                hypot(px - x, py - y) < 3f0 || continue
                d = 0.45f0 * H[i, j]; H[i, j] -= d; gone += d
            end
            ring = gone * CELL^2 / (2f0 * pi * 4.5f0^2)        # the slumped sand spreads in a wide low skirt
            @inbounds for i in max(1, i0 - 3r):min(N, i0 + 3r), j in max(1, j0 - 3r):min(N, j0 + 3r)
                px, py = xy(i, j)
                d = hypot(px - x, py - y)
                H[i, j] += ring * exp(-(d - 4f0)^2 / (2f0 * 1.5f0^2))
            end
            WS[:box] = grow_box(WS[:box], x + 9f0, y + 9f0); WS[:box] = grow_box(WS[:box], x - 9f0, y - 9f0)
            c.pos = Point3f(x, y, NG.terrain_height(w.island, x, y) + sand_at(H, x, y))
            NG.say!(w, c, FALLS[rand(1:length(FALLS))])
            NG.emit!(w, :sand_avalanche; who = c.name, height = round(h, digits = 2))
            WS[:dirty] = true
        elseif h > 0.45f0 && !haskey(sleds, c.id) && !NG.busy(c) && rand() < 0.04
            start_sled!(w, H, c, sleds)
        elseif h > 0.6f0 && w.t - get(boasted, c.id, -Inf) > 45 && rand() < 0.08
            boasted[c.id] = w.t
            NG.say!(w, c, BOASTS[rand(1:length(BOASTS))])
            NG.emit!(w, :sand_king; who = c.name, height = round(h, digits = 2))
        end
    end
end

const WHEE = ("Wheeee!", "Sand slide!", "Out of my way!", "Bellyflop!")
const AGAIN = ("Again!", "That was the best!", "Sand in my ears", "Who's next?")
push!(NG.BUSY_GOALS, :sled)

"""
Sledding (s115): a friend on a dune sometimes throws itself down its steepest side, arms up, at 3.5 m/s, and the
ride carves a groove in the sand that the next one follows. At the foot it gets up and shouts for another go
(which, being speech, pours a little more sand).
"""
function start_sled!(w, H, c, sleds)
    x, y = c.pos[1], c.pos[2]
    gx = sand_at(H, x + 1f0, y) - sand_at(H, x - 1f0, y)
    gy = sand_at(H, x, y + 1f0) - sand_at(H, x, y - 1f0)
    g = hypot(gx, gy)
    g < 0.08f0 && return
    sleds[c.id] = (dir = Vec2f(-gx / g, -gy / g), t0 = w.t)
    c.goal = NG.Goal(:sled, c.pos, :idle, 4.0, w.t + 4, true, 0, false)
    NG.say!(w, c, WHEE[rand(1:length(WHEE))]; duration = 1.5)
end

function sled!(w, H, dt)
    sleds = get(WS, :sleds, nothing)
    (sleds === nothing || isempty(sleds)) && return
    for (id, s) in collect(sleds)
        c = NG.creature(w, id)
        if c === nothing || c.controlled
            delete!(sleds, id); continue
        end
        x = c.pos[1] + s.dir[1] * 3.5f0 * dt
        y = c.pos[2] + s.dir[2] * 3.5f0 * dt
        if sand_at(H, x, y) < 0.04f0 || w.t - s.t0 > 2.5 || !NG.on_land(w.island, x, y)
            delete!(sleds, id)
            c.action = :idle
            c.goal = NG.Goal(:sled, c.pos, :idle, 1.5, w.t + 1.5, true, 0, false)
            NG.say!(w, c, AGAIN[rand(1:length(AGAIN))])
            NG.emit!(w, :sand_slide; who = c.name, metres = round(3.5 * (w.t - s.t0), digits = 1))
            continue
        end
        i, j = cellof(x, y)
        H[i, j] = max(0f0, H[i, j] - 0.03f0)                  # the groove
        WS[:dirty] = true
        c.pos = Point3f(x, y, NG.terrain_height(w.island, x, y) + H[i, j])
        c.yaw = Float32(atan(s.dir[2], s.dir[1])) - NG.species_of(c).heading
        c.action = :jump
    end
end

"Whoever stands on sand stands on top of it (fliers above it stay where they are)."
function lift!(w, H)
    for c in w.creatures
        h = sand_at(H, c.pos[1], c.pos[2])
        h < 0.01f0 && continue
        g = NG.terrain_height(w.island, c.pos[1], c.pos[2])
        z = g + h - 0.03f0
        c.pos[3] < z && (c.pos = Point3f(c.pos[1], c.pos[2], z))
    end
end

"Grains falling from each speaker's bubble down to the heap."
function draw_grains!(game, pours)
    pl = WS[:grains]
    if isempty(pours)
        get(WS, :grains_shown, false) || return
        Makie.update!(pl; arg1 = fill(Point3f(0, 0, -50), GRAINS))
        WS[:grains_shown] = false
        return
    end
    w = game.world
    pts = fill(Point3f(0, 0, -50), GRAINS)
    per = max(1, GRAINS ÷ length(pours))
    speed = Float32(WS[:speed])
    n = 0
    for p in pours
        c = NG.creature(w, p.who)
        c === nothing && continue
        top = c.pos[3] + 1.4f0
        bottom = c.pos[3]
        a = Float32(w.t - p.t0) * speed
        for k in 1:min(per, round(Int, 20 + 900 * p.amount))
            n >= GRAINS && break
            ph = Float32((hash((p.who, k)) % 1000) / 1000)
            τ = mod(a * 1.6f0 + ph, 1f0)
            a * 1.6f0 + ph < 1f0 && continue                              # not poured yet
            r = 0.12f0 + 0.25f0 * τ
            θ = 6.283f0 * Float32((hash((k, p.who, 3)) % 1000) / 1000)
            n += 1
            pts[n] = Point3f(c.pos[1] + r * cos(θ) + 0.3f0, c.pos[2] + r * sin(θ), top - (top - bottom) * τ^2)
        end
    end
    Makie.update!(pl; arg1 = pts)
    WS[:grains_shown] = true
end

function NG.start!(::WordSand, game)
    delete!(WS, :scene)
    return nothing
end

function NG.stop!(::WordSand, game)
    sc = get(WS, :scene, nothing)
    sc === nothing && return
    for k in (:plot, :grains)
        haskey(WS, k) && WS[k] in sc.plots && delete!(sc, WS[k])
    end
    haskey(WS, :H) && game.dash !== nothing && write(state_file(game), WS[:H])
    delete!(WS, :scene)
end

register!(WordSand())
