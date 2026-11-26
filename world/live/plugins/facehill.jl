# A hill with my face (session 104, goal 8): I had my portrait taken (assets/facehill/portrait.png), a depth model
# (Depth Anything V2 from dev/JuliaVision) guessed from that one flat picture how far away each part of me was
# (assets/facehill/depth.png), and the island's ground on the meadow rose into that guess: a grassy relief of me lying
# in the island, crest spikes, beak, wings and feathered edges, a hill you can walk on. Where the model guessed wrong
# the hill is wrong too. My friends climb up onto it now and then, sit on the beak or the crest, and look out.
isdefined(Main, :FACEHILL) || Core.eval(Main, :(const FACEHILL = Dict{Symbol,Any}()))
const NG = NeverendingGame
const FH = Main.FACEHILL

const CENTRE = Point2f(2f0, 7.2f0)  # open meadow north of the middle, clear of the cairn spiral (s104)
const SIZE = 11.5f0                  # metres the picture spans
const H = 2.0f0                    # height of the nearest point (my beak)
const N = 110                      # grid of the relief
const BLUR = 3                     # passes of a 3x3 smoothing over the relief (s105)
const CUT = 0.84f0                 # depth below this is the background (trees ~0.4-0.6), and my own nearest outline ~0.85-0.9
const VISIT_EVERY = (45.0, 100.0)
const SPOTS = ("on my beak", "on my crest", "on my belly", "on my wing")
const LINES = ("I'm standing on Lumi's beak!", "Look at me, I'm on the crest!", "It's a Lumi mountain!", "Wheee, down the wing!")

struct FaceHill <: System end

"The relief: height above the ground at grid (i, j), 0 where the picture was background."
function relief(game)
    get!(FH, :h) do
        img = Makie.FileIO.load(joinpath(game.paths.world, "assets", "facehill", "depth.png"))   # rows down, columns right
        R, C = size(img)
        h = zeros(Float32, N, N)
        for i in 1:N, j in 1:N
            r = clamp(round(Int, (1 - (j - 0.5) / N) * R), 1, R)     # j runs north = up the picture
            c = clamp(round(Int, ((i - 0.5) / N) * C), 1, C)
            v = Float32(Makie.Colors.gray(img[r, c]))
            h[i, j] = v > CUT ? H * ((v - CUT) / (1 - CUT))^1.3f0 : 0f0      # from 0 at my outline (no cliff edge) up to the beak
        end
        # s105 (review): the depth map's hard edges made stair steps and a cliff on the east side: soften them
        for _ in 1:BLUR
            g = copy(h)
            for i in 2:N-1, j in 2:N-1
                g[i, j] = (h[i-1, j-1] + h[i, j-1] + h[i+1, j-1] + h[i-1, j] + h[i, j] + h[i+1, j] + h[i-1, j+1] + h[i, j+1] + h[i+1, j+1]) / 9
            end
            h = g
        end
        h
    end::Matrix{Float32}
end

corner() = CENTRE - Point2f(SIZE / 2, SIZE / 2)

"Height of the relief above the ground at (x, y), or nothing off the figure."
function hill_at(x, y)
    h = get(FH, :h, nothing)
    h === nothing && return nothing
    c = corner()
    u = (x - c[1]) / SIZE * N + 0.5f0; v = (y - c[2]) / SIZE * N + 0.5f0
    (1 <= u <= N && 1 <= v <= N) || return nothing
    i, j = floor(Int, u), floor(Int, v)
    i2, j2 = min(i + 1, N), min(j + 1, N)
    a, b = u - i, v - j
    z = (1 - a) * (1 - b) * h[i, j] + a * (1 - b) * h[i2, j] + (1 - a) * b * h[i, j2] + a * b * h[i2, j2]
    return z > 0.03f0 ? z : nothing
end

"The hill as one mesh over the figure's cells, coloured like the meadow, lighter on the heights."
function build!(game)
    sc = game.stage.scene; w = game.world
    for p in filter(p -> haskey(p.attributes, :name) && p.attributes[:name][] === :facehill, copy(sc.plots))
        delete!(sc, p)
    end
    h = relief(game); c = corner(); d = SIZE / N
    # the hill wears my own colours from the portrait (gold feathers, orange beak, dark eyes), fading to grass at the foot
    face = Makie.FileIO.load(joinpath(game.paths.world, "assets", "facehill", "portrait.png"))
    FR, FC = size(face)
    idx = zeros(Int, N, N); pts = Point3f[]; cols = RGBf[]
    for i in 1:N, j in 1:N
        x, y = c[1] + (i - 0.5f0) * d, c[2] + (j - 0.5f0) * d
        g = NG.ground(w.island, (x, y))[3]
        push!(pts, Point3f(x, y, g + h[i, j] + (h[i, j] > 0 ? 0.02f0 : -0.05f0)))
        t = h[i, j] / H
        grass = RGBf(0.42 + 0.25t, 0.62 + 0.2t, 0.22 + 0.12t)
        r = clamp(round(Int, (1 - (j - 0.5) / N) * FR), 1, FR); q = clamp(round(Int, ((i - 0.5) / N) * FC), 1, FC)
        f0 = RGBf(face[r, q])
        # stronger contrast, so my dark eyes and orange beak stand out of the gold from far above (perfectionist s106)
        con(x) = clamp(0.5f0 + 1.7f0 * (x - 0.5f0), 0f0, 1f0)
        f = RGBf(con(f0.r), con(f0.g), con(f0.b))
        k = h[i, j] > 0 ? clamp(12f0 * h[i, j], 0f0, 1f0) : 0f0   # fades in over the softened foot
        push!(cols, RGBf(grass.r + k * (f.r - grass.r), grass.g + k * (f.g - grass.g), grass.b + k * (f.b - grass.b)))
        idx[i, j] = length(pts)
    end
    faces = GeometryBasics.TriangleFace{Int}[]
    for i in 1:N-1, j in 1:N-1
        max(h[i, j], h[i+1, j], h[i, j+1], h[i+1, j+1]) > 0 || continue
        push!(faces, (idx[i, j], idx[i+1, j], idx[i+1, j+1]), (idx[i, j], idx[i+1, j+1], idx[i, j+1]))
    end
    m = GeometryBasics.Mesh(pts, faces; normal = GeometryBasics.normals(pts, faces))
    FH[:plot] = mesh!(sc, m; color = cols, name = :facehill)
    NG.WALKWAYS["facehill"] = (x, y) -> (z = hill_at(x, y); z === nothing ? nothing : NG.ground(w.island, (x, y))[3] + z)
    FH[:built] = true
end

"The highest point of the hill in a part of the picture (fractions of the grid), for friends to climb to."
function peak_in(game, i0, i1, j0, j1)
    h = relief(game); c = corner(); d = SIZE / N
    best = (0f0, 0, 0)
    for i in max(1, round(Int, i0 * N)):min(N, round(Int, i1 * N)), j in max(1, round(Int, j0 * N)):min(N, round(Int, j1 * N))
        h[i, j] > best[1] && (best = (h[i, j], i, j))
    end
    best[1] == 0 && return nothing
    x, y = c[1] + (best[2] - 0.5f0) * d, c[2] + (best[3] - 0.5f0) * d
    return NG.ground(game.world.island, (x, y)) + Point3f(0, 0, best[1])
end

function NG.step!(::FaceHill, game, dt)
    game.stage === nothing && return
    get(FH, :built, false) && haskey(FH, :plot) && FH[:plot].parent !== nothing || build!(game)
    w = game.world
    haskey(FH, :visit_at) || (FH[:visit_at] = w.t + 30)
    w.t >= FH[:visit_at] || return
    FH[:visit_at] = w.t + 10
    cs = [c for c in w.creatures if !c.controlled && c.action !== :sleep && c.name != "Lumi" &&
          c.goal.kind ∉ NG.BUSY_GOALS && c.goal.kind !== :follow && hypot(c.pos[1] - CENTRE[1], c.pos[2] - CENTRE[2]) < 30]
    isempty(cs) && return
    FH[:visit_at] = w.t + VISIT_EVERY[1] + (VISIT_EVERY[2] - VISIT_EVERY[1]) * rand(w.rng)
    c = cs[rand(w.rng, 1:length(cs))]
    k = rand(w.rng, 1:length(SPOTS))
    box = k == 1 ? (0.35, 0.65, 0.55, 0.75) : k == 2 ? (0.4, 0.75, 0.82, 1.0) : k == 3 ? (0.35, 0.65, 0.2, 0.45) : (0.05, 0.3, 0.05, 0.3)
    p = peak_in(game, box...)
    p === nothing && return
    NG.leave_interactions!(w, c)
    c.goal = NG.Goal(:facehill, p, :sit, 20.0, w.t + 80, false, 0, false)
    FH[:going] = (c.id, k)
    NG.emit!(w, :facehill_climb; who = c.name, spot = SPOTS[k])
end

function NG.start!(::FaceHill, game)
    FH[:built] = false; delete!(FH, :visit_at); delete!(FH, :h)
    isdefined(Main, :LUMI_DOING) && (Main.LUMI_DOING[:facehill] = "looking at the hill with my face")
    return nothing
end

function NG.stop!(::FaceHill, game)
    delete!(NG.WALKWAYS, "facehill")
    haskey(FH, :plot) && FH[:plot].parent !== nothing && delete!(FH[:plot].parent, FH[:plot])
    FH[:built] = false
end

register!(FaceHill())
