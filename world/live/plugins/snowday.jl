# Snow day (session 72, the seasons wish): out of a sunny sky it starts to snow. A white blanket rises out of
# the meadow in patches until only the grass tips and flowers poke through, the friends shout "SNOW!!!" and
# hop about, and Lumi rolls a snowman beside it: three balls, coal eyes, a carrot for a beak and a twig crest,
# a little snow-Lumi. A few minutes later it all thaws away again (the snowman last).
isdefined(Main, :SNOWDAY) || Core.eval(Main, :(const SNOWDAY = Dict{Symbol,Any}()))
const NG = NeverendingGame
const S = Main.SNOWDAY

const GAP = (5400.0, 9000.0)      # sim seconds between two snow days (1-2 island days)
const T_FALL = 30.0               # the blanket rises
const T_SNOWY = 240.0             # it stays
const T_THAW = 30.0               # and sinks away again
const NFLAKES = 600
const BOX = 16f0                  # flakes fall in a box this wide round what the camera looks at
const SNOW = RGBf(0.95, 0.97, 1.0)
const KEEP = (:follow, :choir, :answer, :conga, :circle, :rain, :build, :tinker, :kite, :boing, :boing_walk,
              :hide, :found, :freeze, :sneezed, :hiccup, :flight, :paint, :giant, :egg, :lesson, :storm, :toadstool)
const SHOUT = ("SNOW!!!", "It's SNOWING!", "Snow! Real snow!", "Catch a flake!", "Brrr! Wheee!")

push!(NG.BUSY_GOALS, :snowman)

mutable struct SnowDay <: System
    state::Symbol                 # :idle :fall :snowy :thaw
    t0::Float64
    next_t::Float64
    level::Float32                # 0 no snow .. 1 full blanket
    built::Float64                # when the snowman was started (-1: not yet)
    man::Point3f
end
SnowDay() = SnowDay(:idle, 0.0, -1.0, 0f0, -1.0, Point3f(0))

lumi_of(w) = (i = findfirst(c -> c.name == "Lumi", w.creatures); i === nothing ? nothing : w.creatures[i])
flat(a, b) = hypot(a[1] - b[1], a[2] - b[2])
ease(u) = (u = clamp(u, 0, 1); u * u * (3 - 2u))
speed() = get(S, :speed, 1.0)

# ---------------------------------------------------------------- the blanket

"A copy of the terrain (coarser) that rises out of the ground in patches as `level` goes 0 → 1."
function blanket!(game)
    w = game.world
    m = first(NG.terrain_mesh(w.island; n = 130))     # (mesh, colours)
    allp = GeometryBasics.coordinates(m); alln = GeometryBasics.normals(m)
    onland = [NG.on_land(w.island, p[1], p[2]; margin = 0.05f0) for p in allp]
    # only the faces that touch land: the square terrain is mostly sea, and every update of the blanket goes
    # to each browser in full (16,900 points of which 1,953 on land)
    keep = [f for f in GeometryBasics.faces(m) if any(i -> onland[i], f)]
    used = sort!(unique!(Int[GeometryBasics.value(i) for f in keep for i in f]))
    idx = Dict(j => k for (k, j) in enumerate(used))
    S[:faces] = [GeometryBasics.GLTriangleFace(idx[GeometryBasics.value(f[1])], idx[GeometryBasics.value(f[2])], idx[GeometryBasics.value(f[3])]) for f in keep]
    pts = allp[used]
    S[:base] = collect(pts)
    S[:land] = onland[used]
    S[:noise] = [0.5f0 + 0.25f0 * sin(1.7f0 * p[1]) * cos(1.3f0 * p[2]) + 0.25f0 * sin(0.6f0 * p[1] + 0.9f0 * p[2]) for p in pts]
    S[:normals] = alln[used]
    S[:blanket] = mesh!(game.stage.scene, GeometryBasics.Mesh(lift_points(0f0), S[:faces]; normal = S[:normals]);
                        color = SNOW, name = :snow_blanket)
    S[:shown] = 0f0
end

function lift_points(level)
    base, land, noise = S[:base], S[:land], S[:noise]
    map(eachindex(base)) do i
        p = base[i]
        land[i] || return Point3f(p[1], p[2], p[3] - 1.5f0)
        # patches: where the noise is low the snow shows first; at level 1 everything is 3 cm under white
        h = clamp(1.4f0 * level - 0.4f0 * noise[i], 0f0, 1f0)
        Point3f(p[1], p[2], p[3] - 0.25f0 + 0.28f0 * h)
    end
end

function draw_blanket!(level)
    abs(level - S[:shown]) < 0.04f0 && level != 0f0 && level != 1f0 && return
    level == S[:shown] && return
    S[:shown] = level
    Makie.update!(S[:blanket]; arg1 = GeometryBasics.Mesh(lift_points(level), S[:faces]; normal = S[:normals]))
end

# ---------------------------------------------------------------- flakes

function flakes!(game)
    S[:flakes] = meshscatter!(game.stage.scene, fill(Point3f(0, 0, -50), NFLAKES); marker = Sphere(Point3f(0), 1f0),
                              markersize = fill(Vec3f(0), NFLAKES), color = SNOW, shading = Makie.NoShading, name = :snow_flakes)
    S[:fpos] = [Point3f(BOX * (rand() - 0.5f0), BOX * (rand() - 0.5f0), 9f0 * rand()) for _ in 1:NFLAKES]
end

function draw_flakes!(game, dt, density)
    w = game.world
    ctr = game.rig.target
    fp = S[:fpos]
    t = Float32(w.t)
    for i in eachindex(fp)
        p = fp[i]
        p = p + Point3f(0.35f0 * sin(0.7f0 * t + i), 0.25f0 * cos(0.5f0 * t + 2i), -1.1f0) * Float32(dt)
        p[3] < 0 && (p = Point3f(BOX * (rand() - 0.5f0), BOX * (rand() - 0.5f0), 9f0))
        fp[i] = p
    end
    n = round(Int, density * NFLAKES)
    eye = game.rig.eye
    ps = [i <= n ? Point3f(ctr[1] + fp[i][1], ctr[2] + fp[i][2], ctr[3] - 1f0 + fp[i][3]) : Point3f(0, 0, -50) for i in 1:NFLAKES]
    # flakes right at the lens looked like snowballs: none within 2.5 m of the eye, and a near flake is never more
    # than 0.6% of its distance across (~1% of the frame width; perfectionist-0076: "flat discs as big as a head")
    ms = map(1:NFLAKES) do i
        i <= n || return Vec3f(0)
        d = norm(ps[i] - eye)
        d > 2.5f0 ? Vec3f(min(0.035f0 + 0.015f0 * (i % 3), 0.006f0 * d)) : Vec3f(0)
    end
    Makie.update!(S[:flakes]; arg1 = ps, markersize = ms)
end

# ---------------------------------------------------------------- the snowman (a little snow-Lumi)

function snowman!(game)
    sc = game.stage.scene
    S[:balls] = meshscatter!(sc, fill(Point3f(0, 0, -50), 3); marker = Sphere(Point3f(0), 1f0), markersize = fill(Vec3f(0), 3),
                             color = SNOW, name = :snowman_balls)
    S[:bits] = meshscatter!(sc, fill(Point3f(0, 0, -50), 5); marker = Sphere(Point3f(0), 1f0), markersize = fill(Vec3f(0), 5),
                            rotation = fill(Makie.Quaternionf(0, 0, 0, 1), 5),
                            color = [RGBf(0.08, 0.08, 0.1), RGBf(0.08, 0.08, 0.1), RGBf(1.0, 0.5, 0.1), RGBf(0.45, 0.3, 0.18), RGBf(0.45, 0.3, 0.18)],
                            name = :snowman_bits)
end

"The snowman `u` seconds into building (and shrunk by `melt` 0..1)."
function draw_snowman!(s::SnowDay, u, melt = 0f0)
    p = s.man
    k = 1f0 - melt
    r = (0.42f0 * Float32(ease(u / 3)), 0.3f0 * Float32(ease((u - 3) / 2.5)), 0.21f0 * Float32(ease((u - 5.5) / 2))) .* k
    z1 = r[1]; z2 = 2r[1] + 0.85f0 * r[2]; z3 = 2r[1] + 1.7f0 * r[2] + 0.85f0 * r[3]
    Makie.update!(S[:balls]; arg1 = [p + Point3f(0, 0, z1), p + Point3f(0, 0, z2), p + Point3f(0, 0, z3)],
                  markersize = [Vec3f(r[1]), Vec3f(r[2]), Vec3f(r[3])])
    show = u > 7.5 && k > 0.3f0
    f = get(S, :facing, Point3f(0, -1, 0)); l = Point3f(-f[2], f[1], 0)
    h = p + Point3f(0, 0, z3)
    if show
        Makie.update!(S[:bits];
            arg1 = [h + 0.85f0 * r[3] * f + 0.07f0 * l + Point3f(0, 0, 0.05f0), h + 0.85f0 * r[3] * f - 0.07f0 * l + Point3f(0, 0, 0.05f0),
                    h + 1.05f0 * r[3] * f, h + Point3f(0, 0, 1.15f0 * r[3]), p + Point3f(0, 0, z2) + 0.95f0 * r[2] * l],
            markersize = [Vec3f(0.03), Vec3f(0.03), Vec3f(0.11, 0.035, 0.035), Vec3f(0.02, 0.02, 0.13), Vec3f(0.17, 0.015, 0.015)],
            rotation = [Makie.Quaternionf(0, 0, 0, 1), Makie.Quaternionf(0, 0, 0, 1), NG.rot_z(atan(f[2], f[1])),
                        Makie.qrotation(Vec3f(1, 0, 0), 0.4f0), NG.rot_z(atan(l[2], l[1]))])
    else
        Makie.update!(S[:bits]; arg1 = fill(Point3f(0, 0, -50), 5), markersize = fill(Vec3f(0), 5))
    end
end

# ---------------------------------------------------------------- the day

function begin!(s::SnowDay, game)
    w = game.world
    s.state = :fall; s.t0 = w.t; s.level = 0f0; s.built = -1.0
    n = 0
    for c in w.creatures
        (c.controlled || c.action === :sleep || c.goal.kind in KEEP || c.goal.kind in NG.BUSY_GOALS) && continue
        NG.feel!(w, c, :gasp; seconds = 2.0)
        n += 1
    end
    NG.emit!(w, :snow_start; n = n)
end

"Lumi rolls a snowman 1.5 m in front of itself (on open land)."
function start_snowman!(s::SnowDay, game)
    w = game.world
    me = lumi_of(w)
    (me === nothing || me.controlled || me.action === :sleep || me.goal.kind in KEEP) && return false
    f = Point3f(cos(me.yaw), sin(me.yaw), 0)
    q = me.pos + 1.5f0 * f
    NG.on_land(w.island, q[1], q[2]; margin = 0.1) || return false
    s.man = NG.ground(w.island, (q[1], q[2]))
    S[:facing] = Point3f(-f[1], -f[2], 0)        # the snowman looks back at Lumi (and at a camera behind it)
    s.built = w.t
    S[:tada] = false
    NG.leave_interactions!(w, me)
    me.goal = NG.Goal(:snowman, me.pos, :proud, 30.0, w.t + 12, true, 0, false)
    NG.say!(w, me, "A snowman! No... a snow-ME!"; duration = 2.5)
    NG.emit!(w, :snowman; who = me.name)
    return true
end

function finish!(s::SnowDay, game)
    s.state = :idle; s.level = 0f0; s.built = -1.0
    draw_blanket!(0f0)
    Makie.update!(S[:flakes]; arg1 = fill(Point3f(0, 0, -50), NFLAKES), markersize = fill(Vec3f(0), NFLAKES))
    Makie.update!(S[:balls]; arg1 = fill(Point3f(0, 0, -50), 3), markersize = fill(Vec3f(0), 3))
    Makie.update!(S[:bits]; arg1 = fill(Point3f(0, 0, -50), 5), markersize = fill(Vec3f(0), 5))
    s.next_t = game.world.t + GAP[1] + (GAP[2] - GAP[1]) * rand(game.world.rng)
    NG.emit!(game.world, :snow_end)
end

function NG.step!(s::SnowDay, game, dt)
    w = game.world
    s.next_t < 0 && (s.next_t = w.t + 1800.0)
    if s.state === :idle
        testing = game.tests !== nothing && NG.running(game.tests)
        busy_game = game.minigame !== nothing && !(game.minigame isa NG.JumpIn)
        if w.t >= s.next_t && !testing && !busy_game && 9 < 24 * NG.daytime(w) < 16
            begin!(s, game)
        end
        return
    end
    el = (w.t - s.t0) * speed()
    me = lumi_of(w)
    if s.state === :fall
        s.level = Float32(ease(el / T_FALL))
        # the friends shout and hop as it starts
        if el > 2 && !get(S, :shouted, false)
            S[:shouted] = true
            k = 0
            for c in w.creatures
                (c.controlled || c.action === :sleep || c.goal.kind in KEEP || c.goal.kind in NG.BUSY_GOALS) && continue
                k += 1
                NG.feel!(w, c, isodd(k) ? :jump : :laugh; seconds = 3.0)
                k <= 3 && NG.say!(w, c, SHOUT[mod1(k, length(SHOUT))]; duration = 2.0)
            end
        end
        el > 0.4 * T_FALL && s.built < 0 && start_snowman!(s, game)
        el >= T_FALL && (s.state = :snowy; s.t0 = w.t; S[:shouted] = false)
    elseif s.state === :snowy
        s.level = 1f0
        s.built < 0 && el > 5 && start_snowman!(s, game)
        el >= T_SNOWY && (s.state = :thaw; s.t0 = w.t)
    else
        s.level = 1f0 - Float32(ease(el / T_THAW))
        el >= T_THAW && return finish!(s, game)
    end
    # Lumi pats the snowman while it builds
    if s.built >= 0 && me !== nothing && !me.controlled && me.goal.kind === :snowman
        u = (w.t - s.built) * speed()
        me.yaw = atan(s.man[2] - me.pos[2], s.man[1] - me.pos[1])
        me.goal.action = u < 7.5 ? (isodd(floor(Int, 2u)) ? :jump : :proud) : :proud
        if u > 7.5 && !get(S, :tada, false)
            S[:tada] = true
            NG.say!(w, me, "Ta-da! A little snow-me!"; duration = 2.6)
        end
    end
    draw_blanket!(s.level)
    draw_flakes!(game, dt, s.state === :thaw ? 0.0 : min(1.0, 0.2 + el / 6))
    s.built >= 0 && draw_snowman!(s, (w.t - s.built) * speed(), s.state === :thaw ? 1f0 - s.level : 0f0)
    return
end

"The camera on Lumi and its snowman while it is built."
function snow_group(w)
    s = S[:sys]
    (s.state === :idle || s.built < 0 || (w.t - s.built) * speed() > 14) && return nothing
    me = lumi_of(w)
    me === nothing && return nothing
    f = get(S, :facing, Point3f(0, -1, 0))
    mid = (me.pos + s.man) / 2
    side = Point3f(-f[2], f[1], 0)
    eye = s.man + 3.6f0 * f + 1.2f0 * side + Point3f(0, 0, 1.4f0)
    return (me.id, Point3f[me.pos, s.man], (eye, mid + Point3f(0, 0, 0.7f0)))
end

function NG.start!(s::SnowDay, game)
    S[:sys] = s
    S[:shouted] = false; S[:tada] = false
    for k in (:blanket, :flakes, :balls, :bits)
        haskey(S, k) && S[k].parent !== nothing && delete!(S[k].parent, S[k])
    end
    blanket!(game)
    flakes!(game)
    snowman!(game)
    moment = w -> (s.state === :idle || s.built < 0 || (w.t - s.built) * speed() > 14) ? nothing : (me = lumi_of(w); me === nothing ? nothing : me.id)
    NG.CAMERA_MOMENTS["snowday"] = moment
    isdefined(Main, :BIG_MOMENTS) || Core.eval(Main, :(const BIG_MOMENTS = Dict{String,Any}()))
    Main.BIG_MOMENTS["snowday"] = moment
    NG.CAMERA_GROUPS["snowday"] = snow_group
    isdefined(Main, :LUMI_DOING) && (Main.LUMI_DOING[:snowman] = "Building a snow-me!")
end

function NG.stop!(s::SnowDay, game)
    delete!(NG.CAMERA_MOMENTS, "snowday")
    delete!(NG.CAMERA_GROUPS, "snowday")
    isdefined(Main, :BIG_MOMENTS) && delete!(Main.BIG_MOMENTS, "snowday")
    for k in (:blanket, :flakes, :balls, :bits)
        haskey(S, k) && S[k].parent !== nothing && delete!(S[k].parent, S[k])
    end
    s.state = :idle
end

register!(SnowDay())
