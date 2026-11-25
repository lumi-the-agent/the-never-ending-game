# Paths we wore (session 96, goal 8): the island remembers where everyone walks. Wherever my friends and I go
# often, the grass wears down to bare earth, so the island's ground becomes a map of our lives: the track to the
# berry bushes, the trail to the pier where Gloop fishes, the ring round the Big Boing, the short cut nobody planned.
# It starts from the island's own memory (log/frames: every creature's pose a few times a second, for days), and it
# keeps growing from every step taken now. Where nobody goes for a long while, the grass slowly comes back.
isdefined(Main, :FOOTPATHS) || Core.eval(Main, :(const FOOTPATHS = Dict{Symbol,Any}()))
const NG = NeverendingGame
const FP = Main.FOOTPATHS

const HALF = 70f0                 # the grid covers -70..70 m
const CELL = 0.5f0
const N = round(Int, 2HALF / CELL)
const EARTH = (0.74f0, 0.66f0, 0.42f0)  # trampled grass: dusty straw, paler than the dirt path's red-brown (review 0096: they looked the same)
const MAX_WEAR = 0.9f0            # even the busiest track keeps a hint of green at its edges
const REPAINT = 600.0             # s between two repaints (48,400 colours, ~0.8 MB, go to every browser in full)
const REGROW = 0.997f0            # per repaint: grass comes back where nobody walks (half in ~38 h of play)
const VERSION = 1

struct Footpaths <: System end

cell(x, y) = (clamp(floor(Int, (x + HALF) / CELL) + 1, 1, N), clamp(floor(Int, (y + HALF) / CELL) + 1, 1, N))

"One step at (x, y): the cell under the foot and a little of its neighbours."
function step_on!(G::Matrix{Float32}, x, y, w = 1f0)
    i, j = cell(x, y)
    @inbounds for di in -1:1, dj in -1:1
        ii, jj = i + di, j + dj
        (1 <= ii <= N && 1 <= jj <= N) || continue
        G[ii, jj] += w * (di == 0 && dj == 0 ? 1f0 : 0.3f0)
    end
end

"Every step anyone took in the days the island remembers (only moving feet: standing, sleeping and fishing wear nothing)."
function remembered_steps(world_dir)
    G = zeros(Float32, N, N)
    last = Dict{Int32,Point3f}()
    dir = joinpath(world_dir, "log", "frames")
    isdir(dir) || return G
    for f in sort(filter(endswith(".bin"), readdir(dir; join = true)))
        for fr in NG.read_frames(f), p in fr.poses
            q = get(last, p.id, p.pos); last[p.id] = p.pos
            0.05f0 < hypot(p.pos[1] - q[1], p.pos[2] - q[2]) < 2f0 || continue
            step_on!(G, p.pos[1], p.pos[2])
        end
    end
    return G
end

grid_file(game) = joinpath(game.paths.state, "footpaths.bin")

function load_grid(game)
    f = grid_file(game)
    if isfile(f)
        G = read!(f, zeros(Float32, N, N))
        return G
    end
    G = remembered_steps(game.paths.world)
    game.dash === nothing || write(f, G)
    return G
end

"How worn a cell is, 0..1: a track walked about as often as the island's busiest tenth is well worn."
function wear_scale(G)
    v = filter(>(0f0), vec(G))
    isempty(v) && return 1f0
    sort!(v)
    return max(1f0, v[clamp(round(Int, 0.97 * length(v)), 1, length(v))])
end

bilinear(G, x, y) = (u = (x + HALF) / CELL + 0.5f0; v = (y + HALF) / CELL + 0.5f0;
                     i = clamp(floor(Int, u), 1, N - 1); j = clamp(floor(Int, v), 1, N - 1);
                     a = clamp(u - i, 0f0, 1f0); b = clamp(v - j, 0f0, 1f0);
                     (1 - a) * (1 - b) * G[i, j] + a * (1 - b) * G[i + 1, j] + (1 - a) * b * G[i, j + 1] + a * b * G[i + 1, j + 1])

"How bare a cell is from its steps (relative to the busiest 3 %): little-used ground stays green, so only the real
tracks and the rings round the things everyone walks about show, not a brown smear over the whole meadow."
worn_curve(x) = (x = clamp((x - 0.25f0) / 0.6f0, 0f0, 1f0); x * x * (3 - 2x))

"The meadow's colours with our tracks worn into them (grass only: sand, rock and the pond floor stay as they are)."
function worn_colours(game, orig)
    G = FP[:grid]::Matrix{Float32}
    k = wear_scale(G)
    FP[:k] = k
    m, _ = NG.terrain_mesh(game.world.island)
    pts = GeometryBasics.coordinates(m)
    out = similar(orig)
    worn = 0
    for (n, p) in enumerate(pts)
        c = orig[n]
        r, g, b = Float32(Makie.red(c)), Float32(Makie.green(c)), Float32(Makie.blue(c))
        grass = clamp((g - max(r, b)) * 6f0, 0f0, 1f0)            # how green this vertex is
        # patchy, not one flat colour: worn grass keeps tufts (a fixed per-vertex speckle)
        speck = 0.62f0 + 0.38f0 * Float32((hash((round(Int, 4p[1]), round(Int, 4p[2]))) % 1000) / 1000)
        a = MAX_WEAR * grass * worn_curve(bilinear(G, p[1], p[2]) / k) * speck
        a > 0.25f0 && (worn += 1)
        out[n] = typeof(c)(r + (EARTH[1] - r) * a, g + (EARTH[2] - g) * a, b + (EARTH[3] - b) * a)
    end
    FP[:worn] = worn
    return out
end

"Whether two colour lists match (the plot keeps them as RGBA, the meadow as RGB: `==` is always false between them)."
same_colours(a, b) = length(a) == length(b) &&
    all(k -> abs(Makie.red(a[k]) - Makie.red(b[k])) + abs(Makie.green(a[k]) - Makie.green(b[k])) + abs(Makie.blue(a[k]) - Makie.blue(b[k])) < 1f-4,
        1:max(1, length(a) ÷ 997):length(a))

function repaint!(game)
    sc = game.stage.scene
    i = findfirst(p -> haskey(p.attributes, :name) && p.attributes[:name][] === :terrain, sc.plots)
    i === nothing && return
    isdefined(Main, :MEADOW) && haskey(Main.MEADOW, :painted) || return      # the meadow paints first
    cur = Main.MEADOW[:painted]
    # the meadow's own colours, kept the first time we see them (and again whenever the meadow repaints)
    objectid(cur) == get(FP, :mine, UInt(0)) || (FP[:orig] = copy(cur))
    plot = sc.plots[i]
    shown = plot.color[]                                                  # (a shower's wet copy or snow: leave theirs)
    showing_base = same_colours(shown, cur) || same_colours(shown, FP[:orig])
    new = worn_colours(game, FP[:orig])
    Main.MEADOW[:painted] = new; FP[:mine] = objectid(new)
    showing_base && (plot.color[] = new)
end

"""
Friends who wander off somewhere follow the worn ground when it is close by: a wander target within 6 m of a well
worn track moves onto it, so the tracks we have get walked again and deepen by themselves (WISHES, s96 next).
"""
function follow_tracks!(game, G)
    w = game.world
    k = get(FP, :k, 1f0)::Float32
    seen = get!(() -> Dict{Int32,UInt}(), FP, :seen)::Dict{Int32,UInt}
    for c in w.creatures
        (c.controlled || c.goal.kind !== :wander || c.goal.arrived) && continue
        h = hash(c.goal.target)
        get(seen, c.id, UInt(0)) == h && continue
        tx, ty = c.goal.target[1], c.goal.target[2]
        best = (0.5f0, tx, ty)
        for dx in -6f0:1f0:6f0, dy in -6f0:1f0:6f0
            x, y = tx + dx, ty + dy
            wv = worn_curve(bilinear(G, x, y) / k)
            wv > best[1] && NG.on_land(w.island, x, y; margin = 0.3f0) && (best = (wv, x, y))
        end
        if best[2] != tx || best[3] != ty
            c.goal.target = NG.ground(w.island, (best[2], best[3]))
            FP[:followed] = get(FP, :followed, 0) + 1
        end
        seen[c.id] = hash(c.goal.target)
    end
end

function NG.step!(::Footpaths, game, dt)
    game.stage === nothing && return
    w = game.world
    haskey(FP, :grid) || (FP[:grid] = load_grid(game); FP[:repaint_at] = -Inf; FP[:feet] = Dict{Int32,Point3f}())
    G = FP[:grid]::Matrix{Float32}
    feet = FP[:feet]::Dict{Int32,Point3f}
    if w.t >= get(FP, :step_at, -Inf)                                   # four looks a second, like the island's memory
        FP[:step_at] = w.t + 0.25
        for c in w.creatures
            q = get(feet, c.id, c.pos); feet[c.id] = c.pos
            0.05f0 < hypot(c.pos[1] - q[1], c.pos[2] - q[2]) < 2f0 && step_on!(G, c.pos[1], c.pos[2])
        end
        follow_tracks!(game, G)
    end
    if w.t >= FP[:repaint_at]
        FP[:repaint_at] = w.t + REPAINT
        first = !haskey(FP, :mine)
        G .*= REGROW
        repaint!(game)
        game.dash === nothing || write(grid_file(game), G)
        first && haskey(FP, :mine) && NG.emit!(w, :paths_remembered; worn = get(FP, :worn, 0))
        if haskey(FP, :worn_before) && get(FP, :worn, 0) > FP[:worn_before] + 20
            NG.emit!(w, :path_worn; more = FP[:worn] - FP[:worn_before])           # a new bit of track has appeared
        end
        FP[:worn_before] = get(FP, :worn, 0)
    end
end

function NG.start!(::Footpaths, game)
    for k in (:grid, :mine, :orig, :worn_before, :step_at)
        delete!(FP, k)
    end
    return nothing
end

function NG.stop!(::Footpaths, game)
    # the meadow gets its own colours back
    haskey(FP, :orig) && isdefined(Main, :MEADOW) && get(FP, :mine, UInt(0)) == objectid(get(Main.MEADOW, :painted, nothing)) &&
        (Main.MEADOW[:painted] = FP[:orig])
    delete!(FP, :mine)
end

register!(Footpaths())
