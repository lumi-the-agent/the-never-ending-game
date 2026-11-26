# Lens clear: every camera (follow, chat and group views, night shots) avoids a picture where a
# creature, a bush or a tree BESIDE the line of sight fills a big part of the frame. The engine's
# `obstruction` only looks along the line from eye to target, so a bystander turtle shell or a
# bush in a lower corner (review s32: a third to half of a chat frame) went unnoticed.
# A camera blocker (NG.CAMERA_BLOCKERS): for each thing in the view cone, its angular size; past
# ~11° (about a sixth of the frame) it costs, so `follow_view` turns to another side.
const NG = NeverendingGame

const HALF_FOV = 32f0    # degrees, horizontal half view of the 16:9 dashboard camera (vertical ~22°)
const HALF_VFOV = 22.5f0  # degrees, vertical half view (Makie's fovy 45)
const FREE_DEG = 11f0    # angular radius a thing may have before it costs
const SIN_FREE = sind(FREE_DEG)

"Cost of a ball of radius `r` at `m` seen from `eye` looking along `fwd`: 0 when small or out of view."
function lens_cost(eye, fwd, m, r, far = Inf32)
    v = Vec3f(m - eye)
    d = norm(v)
    d < 1f-3 && return 2f0
    d - r > far && return 0f0
    r < SIN_FREE * d && return 0f0       # smaller than FREE_DEG: most of the island, no trig (s61: 1 ms a call)
    ar = asind(min(1f0, r / d))
    ar <= FREE_DEG && return 0f0
    # in the picture: within the horizontal AND the vertical half view (a crown overhead, out of the
    # 22° vertical view, used to count with the 32° horizontal one and spoiled every low shot, s34)
    right = cross(fwd, Vec3f(0, 0, 1)); right = norm(right) < 1f-3 ? Vec3f(1, 0, 0) : normalize(right)
    up = cross(right, fwd)
    z = dot(v, fwd)
    z <= 0 && return 0f0
    atand(abs(dot(v, right)), z) - ar > HALF_FOV && return 0f0
    atand(abs(dot(v, up)), z) - ar > HALF_VFOV && return 0f0
    return (ar - FREE_DEG) / 8f0
end

function lens_block(w, eye, target)
    fwd = Vec3f(target - eye)
    norm(fwd) < 1f-3 && return 0f0
    far = norm(fwd) + 0.6f0     # behind the subject is backdrop, not a blocker (sleepers in their nooks, s34)
    fwd = normalize(fwd)
    o = 0f0
    for c in w.creatures
        hypot(c.pos[1] - target[1], c.pos[2] - target[2]) < 0.35f0 && continue   # the subject
        sp = NG.species_of(c)
        r = max(0.5f0 * sp.height, NG.body_radius(sp))
        o += lens_cost(eye, fwd, c.pos + Point3f(0, 0, 0.5f0 * sp.height), r, far)
    end
    for p in w.props
        if p.kind === :bush
            o += lens_cost(eye, fwd, p.pos + Point3f(0, 0, 0.4f0 * p.scale), 0.75f0 * p.scale, far)
        elseif p.kind === :tree
            # a trunk beside the lens filled a third of a chat frame once the bystanders were avoided
            o += lens_cost(eye, fwd, p.pos + Point3f(0, 0, 0.8f0 * p.scale), 0.45f0 * p.scale, far)
            o += lens_cost(eye, fwd, p.pos + Point3f(0, 0, 2.6f0 * p.scale), 1.3f0 * p.scale)   # a crown counts behind the subject too: it fills the top of the frame
            # the real crowns are ~4 m wide and pines hang down to a metre: only near the lens (surface within 3 m), so an
            # eye tucked under or beside a crown costs while front views past a tree stay free (todo #507, s96)
            o += lens_cost(eye, fwd, p.pos + Point3f(0, 0, 1.9f0 * p.scale), 1.6f0 * p.scale, 3f0)
            o += lens_cost(eye, fwd, p.pos + Point3f(0, 0, 3.8f0 * p.scale), 2.1f0 * p.scale, 3f0)
        end
    end
    # houses, benches, toadstools (AssetActors): the cottage covered half a follow view (s56)
    for a in w.actors
        a isa NG.AssetActor || continue
        hypot(a.pos[1] - target[1], a.pos[2] - target[2]) < 1.2f0 && continue    # what the shot is about
        r, h = actor_size(a)
        o += lens_cost(eye, fwd, a.pos + Point3f(0, 0, 0.5f0 * h), r, far)
    end
    return o
end

isdefined(Main, :LENS_SIZES) || Core.eval(Main, :(const LENS_SIZES = Dict{String,Tuple{Float32,Float32}}()))
"An asset actor's (radius, height) in metres, from its mesh (read once per asset)."
function actor_size(a)
    r, h = get!(Main.LENS_SIZES, a.asset) do
        cat = NG.load_catalog(NG.world_paths())
        i = findfirst(e -> e["id"] == a.asset, cat)
        i === nothing && return (0.5f0, 1.0f0)
        mm = NG.Serialization.deserialize(cat[i]["mesh"])
        ps = GeometryBasics.coordinates(mm.mesh)
        ext(k) = maximum(p[k] for p in ps) - minimum(p[k] for p in ps)
        (0.5f0 * max(ext(1), ext(2)), Float32(ext(3)))
    end
    return r * a.scale, h * a.scale
end

struct LensClear <: System end
"""
The Big Boing toadstool (boing.jl, a plugin plot, no prop) along the line of sight: about 1 per blocked sample.
Since s68 it stands on a 1.3 m stem under a 1 m dome, and the follow camera framed a dance ring through it (s70).
"""
function toadstool_block(eye, target)
    (isdefined(Main, :BOING) && haskey(Main.BOING, :center)) || return 0f0
    c = Main.BOING[:center]
    o = 0f0
    for s in 0.1f0:0.1f0:0.9f0
        q = eye + s * (target - eye)
        hypot(q[1] - c[1], q[2] - c[2]) < 2.0f0 && q[3] < c[3] + 2.4f0 && (o += 1f0)
    end
    return o
end

"The board by the cottage (missme.jl): cameras chose views through it (the G run-up, s108). Its spot is fixed per world."
function board_block(game, eye, target)
    haskey(game.plugins, "missme") || return 0f0
    p = get!(() -> Base.invokelatest(game.plugins["missme"].mod.board_spot, game.world)[1], Main.LENSCLEAR_BOARD, objectid(game.world))
    o = 0f0
    for s in 0.1f0:0.1f0:0.9f0
        q = eye + s * (target - eye)
        hypot(q[1] - p[1], q[2] - p[2]) < 0.9f0 && q[3] < p[3] + 2.0f0 && (o += 1f0)
    end
    return o
end

function NG.start!(::LensClear, game)
    isdefined(Main, :LENSCLEAR_BOARD) || Core.eval(Main, :(const LENSCLEAR_BOARD = Dict{UInt,Any}()))
    NG.CAMERA_BLOCKERS["lens"] = (eye, target) -> lens_block(game.world, eye, target)
    NG.CAMERA_BLOCKERS["toadstool"] = toadstool_block
    NG.CAMERA_BLOCKERS["board"] = (eye, target) -> board_block(game, eye, target)
    nothing
end
NG.step!(::LensClear, game, dt) = nothing
NG.stop!(::LensClear, game) = (delete!(NG.CAMERA_BLOCKERS, "lens"); delete!(NG.CAMERA_BLOCKERS, "toadstool"); delete!(NG.CAMERA_BLOCKERS, "board"); nothing)

register!(LensClear())
