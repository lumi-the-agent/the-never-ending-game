# The owl that hunts by ear (s132, projects/owl-ears.md). At night an owl sits in the tree west of the cottage and
# listens. Every step the jumped-in player takes is a sound at their feet; physics/echo.jl `hear` traces it through
# the island's solid world (terrain, trees, rocks, buildings) to the owl's head, and the owl turns to where the
# FIRST wavefront comes from (precedence effect), not to where you are: a step behind the cottage reaches it over
# the roof, so it looks the wrong way. A faint moonlit spot on the ground is where it is looking.
isdefined(Main, :OWLEARS) || Core.eval(Main, :(const OWLEARS = Dict{Symbol,Any}()))
const NG = NeverendingGame
const OW = Main.OWLEARS
isdefined(Main, :OwlHearing) || Core.eval(Main, :(module OwlHearing end))
isdefined(Main.OwlHearing, :hear) || Base.include(Main.OwlHearing, joinpath(@__DIR__, "..", "physics", "echo.jl"))
const OH = Main.OwlHearing

const OW_ASSET = "20261127-023850-460-asset"   # the owl (generated s132); until it exists the owl stays away
const OW_NEAR = Point2f(-15.0, 4.0)            # it takes the tree nearest this spot (west of the cottage)
const OW_STEP = 0.7f0                          # m walked per footstep
const OW_HEAR_DB = -44f0                       # quieter than this (re a unit source at 1 m) and it hears nothing
const OW_RAYS = 8000
const OW_RANGE = 35f0                          # m: farther steps are not traced
const OW_HIDE = Point3f(0, 0, -50)

struct OwlEars <: System end

ow_night(w) = (h = 24 * NG.daytime(w); h >= 20.5 || h < 5.0)
ow_player(w) = (k = findfirst(c -> c.controlled, w.creatures); k === nothing ? nothing : w.creatures[k])
ow_flat(a, b) = hypot(a[1] - b[1], a[2] - b[2])
ow_flat3(a, b) = sqrt(sum(abs2, Vec3f(a - b)))

"The owl's perch: the top of the crown of the tree nearest OW_NEAR, and its head 0.25 m above."
function ow_perch!(w)
    trees = [p for p in w.props if p.kind === :tree]
    t = trees[argmin([ow_flat(p.pos, OW_NEAR) for p in trees])]
    # s132 measured this tree's crown (scale 1.06): top 3.69 m, the surface 0.5 m out at 3.08 m: sit on that shoulder
    OW[:perch] = Point3f(t.pos[1] + 0.5f0, t.pos[2], t.pos[3] + 2.9f0 * t.scale)
    OW[:head] = OW[:perch] + Point3f(0, 0, 0.25)
end

"The solid world as a BVH, once: the triangles on the main thread (~0.8 s), the BVH in a task (~1.1 s)."
function ow_world!(game)
    haskey(OW, :tlas_task) && return
    tris = Base.invokelatest(OH.solid_triangles, game.stage.scene)
    OW[:ntris] = length(tris)
    OW[:tlas_task] = Threads.@spawn Base.invokelatest(OH.echo_tlas, tris, OH.KA.CPU())
end
ow_tlas() = (t = get(OW, :tlas_task, nothing); t !== nothing && istaskdone(t) ? fetch(t) : nothing)

function ow_plots!(game)
    if !(haskey(OW, :spot) && OW[:spot].parent !== nothing)
        OW[:spot] = meshscatter!(game.stage.scene, [OW_HIDE]; marker = Makie.Cylinder(Point3f(0), Point3f(0, 0, 0.02f0), 1f0),
                                 markersize = Vec3f(0), color = RGBAf(0.75, 0.85, 1.0, 0.35), transparency = true,
                                 name = :owlears_spot)
    end
    haskey(OW, :body) && return
    # the owl comes once its asset is in the catalog (the worker makes it); look every 30 s
    time() - get(OW, :looked, 0.0) > 30 || return
    OW[:looked] = time()
    if any(e -> e["id"] == OW_ASSET, NG.load_catalog(game.paths))
        model = NG.load_asset(game.paths, OW_ASSET; size = 512)
        OW[:body] = NG.asset_instances!(game.stage.scene, model, [OW_HIDE]; markersize = Vec3f(0.55),
                                        rotation = Makie.qrotation(Vec3f(0, 0, 1), 0f0), name = :owlears_owl)
    end
end

"March from the head along `d` to the ground: where the owl is looking."
function ow_gaze_point(isl, o::Point3f, d::Vec3f)
    s = 0.5f0
    while s < 60f0
        p = o + s * d
        p[3] < NG.terrain_height(isl, p[1], p[2]) && return p
        s += 0.25f0
    end
    return nothing
end

"One footstep at `foot`, `db` louder than a walk: what the owl hears, and where it turns."
function ow_footstep!(game, foot::Point3f, db::Float32)
    tl = ow_tlas(); tl === nothing && return
    w = game.world
    h = Base.invokelatest(OH.hear, tl, OH.KA.CPU(), foot + Point3f(0, 0, 0.05), OW[:head]; rays = OW_RAYS, seed = rand(1:10^6))
    lvl = h.level + db
    OW[:last] = (t = w.t, level = lvl, direct = h.direct, from = h.from, t0 = h.t0)
    (isfinite(lvl) && lvl > OW_HEAR_DB) || return
    OW[:yaw_goal] = atan(h.from[2], h.from[1])
    g = ow_gaze_point(w.island, OW[:head], h.from)
    OW[:gaze] = g === nothing ? nothing : (g, w.t)
    NG.emit!(w, :owl_heard; level = round(lvl, digits = 1), direct = h.direct,
             off_deg = round(acosd(clamp(sum(h.from .* Vec3f(foot - OW[:head])) / ow_flat3(foot, OW[:head]), -1f0, 1f0))))
end

function NG.step!(::OwlEars, game, dt)
    game.stage === nothing && return
    w = game.world
    haskey(OW, :head) || ow_perch!(w)
    ow_plots!(game)
    night = ow_night(w)
    body = get(OW, :body, nothing)
    if body !== nothing
        yaw = get(OW, :yaw, 0f0)
        goal = get(OW, :yaw_goal, yaw)
        dy = mod(goal - yaw + Float32(pi), 2f0 * Float32(pi)) - Float32(pi)
        yaw += clamp(dy, -6f0 * Float32(dt), 6f0 * Float32(dt))       # a quick, smooth head turn
        OW[:yaw] = yaw
        Makie.update!(body; arg1 = [night ? OW[:perch] : OW_HIDE], rotation = [Makie.qrotation(Vec3f(0, 0, 1), yaw)])
    end
    # the gaze spot fades over 2 s
    gz = get(OW, :gaze, nothing)
    if gz !== nothing && night
        a = Float32(w.t - gz[2])
        r = a < 2f0 ? 0.9f0 * (1f0 - a / 2f0) + 0.3f0 : 0f0
        Makie.update!(OW[:spot]; arg1 = [gz[1] + Point3f(0, 0, 0.03)], markersize = Vec3f(r, r, 1))
    else
        OW[:spot].markersize[] == Vec3f(0) || Makie.update!(OW[:spot]; markersize = Vec3f(0))
    end
    night || return
    me = ow_player(w)
    me === nothing && return
    ow_flat(me.pos, OW[:head]) < OW_RANGE || return
    ow_world!(game)
    # footsteps: one every OW_STEP metres walked; running is louder (6 dB)
    last = get(OW, :lastpos, me.pos)
    walked = get(OW, :walked, 0f0) + ow_flat(me.pos, last)
    OW[:lastpos] = me.pos
    if walked >= OW_STEP
        speed = ow_flat(me.pos, last) / max(Float32(dt), 1f-3)
        ow_footstep!(game, Point3f(me.pos), speed > 3f0 ? 6f0 : 0f0)
        walked = 0f0
    end
    OW[:walked] = walked
    nothing
end

function NG.start!(::OwlEars, game)
    for k in (:spot, :body)
        p = get(OW, k, nothing)
        p !== nothing && p.parent !== nothing && delete!(p.parent, p)
        delete!(OW, k)
    end
    delete!(OW, :head)
    nothing
end

register!(OwlEars())
