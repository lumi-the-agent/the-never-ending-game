# (s178: physics/cartcord.jl counted the cord's copper twice; fixed: the clip now pulls off at 21.0 s, 3.09 m. Cart.ground: a road over real ground, project dune)
# The cart drives itself on a long cord (s177, project cartcord). The iron drum motor's twin sits on the cart's rear
# deck; through the winch's oak cogs (6:1) and a leather belt (15 -> 40 mm) it turns the rear axle, and a twin copper
# cord runs back to the first of the six clay pots by the drum's block, held there by a spring clip. Nothing sets a
# speed: physics/cartcord.jl steps the motor's circuit (Motor.step!, the cord's copper in it), the belt (it slips at
# the capstan limit), the cart on its planks and the cord (Rope's tether, dragged over the ground, taut at its
# length). When the cord's pull beats the clip's grip the clip lets go, the circuit opens and the cart coasts to a stop.
# M by the cart (in Jump in) switches it on, Q changes its axle pulley; when nobody plays, it runs now and then.
using GeometryBasics, Makie, LinearAlgebra
isdefined(Main, :CARTCORD) || Core.eval(Main, :(const CARTCORD = Dict{Symbol,Any}()))
const NG = NeverendingGame
const CK = Main.CARTCORD
Base.include(@__MODULE__, joinpath(@__DIR__, "..", "physics", "motor.jl"))
Base.include(@__MODULE__, joinpath(@__DIR__, "..", "physics", "motorlook.jl"))
Base.include(@__MODULE__, joinpath(@__DIR__, "..", "physics", "rope.jl"))
Base.include(@__MODULE__, joinpath(@__DIR__, "..", "physics", "potcell.jl"))
Base.include(@__MODULE__, joinpath(@__DIR__, "..", "physics", "cartcord.jl"))

struct CartCordSys <: System end

const CK_CLIP = (4.35f0, -14.72f0)    # pot 1's copper strip (irondrum.jl id_pots!: the row's west end)
const CK_Y = -14.72f0                 # the track's line; the cart drives west (-x)
const CK_X0 = 0.30                    # the cart's start, metres west of the clip
const CK_CORD = 3.0                   # metres of cord
const CK_RW = 0.10f0                  # wheel radius
const CK_KEY = Makie.Keyboard.m     # (B blows bubbles, P paints in Jump in: s177 picked free keys)
const CK_PKEY = Makie.Keyboard.q
const CK_PULLEYS = (0.03, 0.04, 0.06)   # s177: the axle pulley the player picks (P): 12:1, 16:1, 24:1 after the 6:1 cogs
const CK_PLANK = 0.02f0               # plank thickness
const CK_IRON = NG.Hikari.Principled(base_color = (0.40f0, 0.40f0, 0.42f0), metallic = 0.6f0, roughness = 0.45f0)
const CK_FERRITE = NG.Hikari.Principled(base_color = (0.09f0, 0.09f0, 0.10f0), metallic = 0.0f0, roughness = 0.65f0)
const CK_LEATHER = NG.Hikari.Principled(base_color = (0.30f0, 0.17f0, 0.09f0), roughness = 0.7f0)
# s180: the cord was brown cloth on brown oak and nobody could see it: a pale waxed-cotton braid over the twin copper
const CK_CLOTH = NG.Hikari.Principled(base_color = (0.80f0, 0.74f0, 0.60f0), roughness = 0.75f0)
const CK_CORD_R = 0.0055f0            # the cord's radius: 11 mm of braid over two 0.75 mm^2 strands

ck_cyl(a, b, r; n = 24) = GeometryBasics.normal_mesh(Cylinder(Point3f(a...), Point3f(b...), Float32(r)))
ck_box(o, s) = GeometryBasics.normal_mesh(Rect3f(Point3f(o...), Vec3f(s...)))

function ck_merge(ms)
    pts = Point3f[]; fs = GeometryBasics.TriangleFace{Int}[]
    for m in ms
        o = length(pts)
        append!(pts, Point3f.(GeometryBasics.coordinates(m)))
        append!(fs, [GeometryBasics.TriangleFace((Int.(GeometryBasics.value.(Tuple(f))) .+ o)...) for f in GeometryBasics.faces(m)])
    end
    GeometryBasics.normal_mesh(GeometryBasics.Mesh(pts, fs))
end

"A ring about the y axis between y0 and y1, radii ri..ro, each surface its own vertices (sharp edges, outward)."
function ck_ring(ri, ro, y0, y1; n = 48)
    pts = Point3f[]; fs = GeometryBasics.TriangleFace{Int}[]
    xz(r, k) = (r * cos(2pi * k / n), r * sin(2pi * k / n))
    function band!(a, b)
        o = length(pts)
        for k in 0:n
            p = xz(a[2], k); q = xz(b[2], k)
            push!(pts, Point3f(p[1], a[1], p[2]), Point3f(q[1], b[1], q[2]))
        end
        for k in 0:n-1
            i = o + 2k + 1
            push!(fs, GeometryBasics.TriangleFace(i, i + 1, i + 3), GeometryBasics.TriangleFace(i, i + 3, i + 2))
        end
    end
    band!((y0, ro), (y1, ro)); band!((y1, ri), (y0, ri)); band!((y1, ro), (y1, ri)); band!((y0, ri), (y0, ro))
    GeometryBasics.normal_mesh(GeometryBasics.Mesh(pts, fs))
end

"A spoked oak wheel about the y axis at the origin: rim, six spokes, hub (a wainwright's, small)."
function ck_wheel(r, w)
    ms = Any[ck_ring(r - 0.014, r, -w / 2, w / 2), ck_ring(0.008, 0.022, -w / 2 - 0.006, w / 2 + 0.006; n = 20)]
    for k in 0:5
        φ = 2pi * k / 6
        d = (cos(φ), sin(φ))
        push!(ms, ck_cyl((0.02 * d[1], 0, 0.02 * d[2]), ((r - 0.01) * d[1], 0, (r - 0.01) * d[2]), 0.0055))
    end
    ck_merge(ms)
end

"Where the cart stands: track metres x west of the clip -> world point on the planks (y on the track's line)."
ck_world(w, x, dy = 0.0f0) = Point3f(CK_CLIP[1] - Float32(x), CK_Y + dy, ck_road(w))
ck_ground(w, x, dy = 0.0f0) = (p = (CK_CLIP[1] - Float32(x), CK_Y + dy); Point3f(p..., NG.ground(w.island, p)[3]))
"The plank road's top: laid LEVEL on oak sleepers at the highest ground along it (s177: following the ground's 3% rise,
the cart stalled after 28 cm: 3 N of slope on top of 2 N of rolling is more than this motor gives at the wheels)."
ck_road(w) = get!(CK, :roadz) do
    maximum(NG.ground(w.island, (CK_CLIP[1] - Float32(x), CK_Y + dy))[3] for x in 0:0.1:3.7, dy in (-0.16f0, 0.16f0)) + CK_PLANK + 0.01f0
end

function ck_build!(game)
    sc = game.stage.scene; w = game.world
    for p in copy(sc.plots)
        haskey(p.attributes, :name) && startswith(string(p.attributes[:name][]), "cartcord_") && delete!(sc, p)
    end
    delete!(CK, :roadz); delete!(CK, :phase)
    oak = mo_wood(base = (0.56, 0.40, 0.24)); oakm = mo_wood(moving = true, base = (0.56, 0.40, 0.24))
    # the plank road: two lines of sawn oak boards under the wheels, each board on the ground where it lies
    for (k, x) in enumerate(0.05:0.62:3.6), dy in (-0.16f0, 0.0f0, 0.16f0)
        a = ck_world(w, x, dy) - Point3f(0, 0, CK_PLANK); b = ck_world(w, x + 0.6, dy) - Point3f(0, 0, CK_PLANK)
        L = norm(b - a); u = (b - a) / L
        q = Makie.qrotation(Vec3f(0, 1, 0), Float32(atan(u[3], -u[1])))
        pl = mesh!(sc, ck_box((-L, -0.06, -0.004), (L, 0.12, CK_PLANK + 0.004)); color = RGBf(0.56, 0.42, 0.27), material = oak,
                   name = Symbol("cartcord_plank", k, "_", round(Int, 100dy)))
        Makie.rotate!(pl, q); Makie.translate!(pl, a)
        for xe in (x + 0.03, x + 0.57)                 # a sleeper under each end, down into the ground
            g = ck_ground(w, xe, dy); top = ck_road(w) - CK_PLANK
            mesh!(sc, ck_box((g[1] - 0.025, g[2] - 0.07, g[3] - 0.03), (0.05, 0.14, top - g[3] + 0.03)); color = RGBf(0.45, 0.33, 0.2),
                  material = oak, name = Symbol("cartcord_sleeper", k, "_", round(Int, 100dy), "_", round(Int, 100xe)))
        end
    end
    # s180: the road's bed. The boards stood level on bare sleepers over sand falling away beneath them, a row of
    # benches (post critic); a road builder banks packed sand up under them: a berm from the ground to the boards
    sandm = NG.Hikari.Principled(base_color = (0.74f0, 0.64f0, 0.47f0), roughness = 0.95f0)
    bp = Point3f[]; bf = GeometryBasics.TriangleFace{Int}[]
    xs = 0.0:0.1:3.7; top = ck_road(w) - CK_PLANK
    for x in xs
        gl = ck_ground(w, x, -0.34f0); gr = ck_ground(w, x, 0.34f0); wx = CK_CLIP[1] - Float32(x)
        push!(bp, Point3f(wx, CK_Y - 0.34f0, gl[3] - 0.03f0), Point3f(wx, CK_Y - 0.23f0, top),
                  Point3f(wx, CK_Y + 0.23f0, top), Point3f(wx, CK_Y + 0.34f0, gr[3] - 0.03f0))
    end
    for i in 0:length(xs)-2, j in 1:3
        a = 4i + j; b = a + 4
        push!(bf, GeometryBasics.TriangleFace(a, a + 1, b + 1), GeometryBasics.TriangleFace(a, b + 1, b))
    end
    for o in (0, 4 * (length(xs) - 1))                  # the two ends
        push!(bf, GeometryBasics.TriangleFace(o + 1, o + 2, o + 3), GeometryBasics.TriangleFace(o + 1, o + 3, o + 4))
    end
    mesh!(sc, GeometryBasics.normal_mesh(GeometryBasics.Mesh(bp, bf)); color = RGBf(0.74, 0.64, 0.47), material = sandm,
          name = :cartcord_berm)
    # the cart, built about its middle at axle height (forward = -x): frame, deck, axles, wheels, motor, cogs, belt
    body = Any[]
    fr = Any[]
    for dy in (-0.11, 0.11)
        push!(fr, ck_box((-0.33, dy - 0.02, 0.02), (0.66, 0.04, 0.05)))            # side rails
    end
    for x in -0.30:0.085:0.28
        push!(fr, ck_box((x, -0.15, 0.07), (0.075, 0.30, 0.016)))                  # deck boards, a gap between each
    end
    for x in (-0.24, 0.24), dy in (-0.11, 0.11)
        push!(fr, ck_box((x - 0.025, dy - 0.022, -0.012), (0.05, 0.044, 0.034)))   # axle blocks under the rails
    end
    push!(body, (ck_merge(fr), oak, RGBf(0.56, 0.40, 0.24), :frame))
    push!(body, (ck_merge([ck_cyl((x, -0.19, 0), (x, 0.19, 0), 0.008) for x in (-0.24, 0.24)]), CK_IRON, RGBf(0.4, 0.4, 0.42), :axles))
    # the motor on the rear deck (axle along y): two dark stones either side of the iron drum, copper coil ends
    mz = 0.086 + 0.04
    push!(body, (ck_merge([ck_box((0.12, -0.05, 0.086), (0.035, 0.10, 0.08)), ck_box((0.235, -0.05, 0.086), (0.035, 0.10, 0.08))]),
                 CK_FERRITE, RGBf(0.09, 0.09, 0.10), :stones))
    push!(body, (ck_merge([ck_box((0.175, -0.075, 0.086), (0.04, 0.018, 0.05)), ck_box((0.175, 0.057, 0.086), (0.04, 0.018, 0.05)),
                           ck_box((0.125, 0.146, 0.086), (0.04, 0.016, 0.05))]),
                 oak, RGBf(0.5, 0.35, 0.2), :motorbed))           # bearing blocks: the motor's axle, the countershaft's
    push!(body, (ck_merge([ck_cyl((0.195, -0.08, 0.126), (0.195, 0.12, 0.126), 0.003), ck_cyl((0.145, 0.10, 0.126), (0.145, 0.165, 0.126), 0.003)]),
                 CK_IRON, RGBf(0.4, 0.4, 0.42), :shafts))
    wheels = [(Point3f(x, dy, 0), x) for x in (-0.24f0, 0.24f0) for dy in (-0.16f0, 0.16f0)]
    CK[:parts] = Any[]; CK[:wheels] = Any[]
    for (m, mat, col, nm) in body
        push!(CK[:parts], mesh!(sc, m; color = col, material = mat, name = Symbol("cartcord_", nm)))
    end
    for (k, (p, _)) in enumerate(wheels)
        wh = mesh!(sc, ck_wheel(Float64(CK_RW), 0.03); color = RGBf(0.5, 0.36, 0.22), material = oakm, name = Symbol("cartcord_wheel", k))
        push!(CK[:wheels], (wh, p))
    end
    # turning parts on the motor: the iron drum with its two coils (spins), the oak cogs, the pulleys
    CK[:drum] = mesh!(sc, ck_merge([ck_cyl((0, -0.045, 0), (0, 0.045, 0), 0.032), ck_box((-0.034, -0.047, -0.004), (0.068, 0.094, 0.008))]);
                      color = RGBf(0.4, 0.4, 0.42), material = CK_IRON, name = :cartcord_drum)
    CK[:coil] = mesh!(sc, ck_merge([ck_ring(0.030, 0.035, -0.05, -0.044; n = 32), ck_ring(0.030, 0.035, 0.044, 0.05; n = 32)]);
                      color = RGBf(0.86, 0.46, 0.24), material = mo_copper(), name = :cartcord_coil)
    pegs(r, n, y0, y1) = [ck_cyl((r * cos(2pi * k / n), y0, r * sin(2pi * k / n)), (r * cos(2pi * k / n), y1, r * sin(2pi * k / n)), 0.0022; n = 8)
                          for k in 0:n-1]
    # the 36-cog oak wheel (pale hornbeam pegs) and the 15 mm belt pulley on the countershaft; the 6-peg pinion on the motor
    CK[:cog] = mesh!(sc, ck_merge(vcat([ck_ring(0.030, 0.040, -0.006, 0.006), ck_ring(0.004, 0.015, 0.014, 0.03; n = 20)],
                                       [ck_box((-0.003, -0.005, 0.006), (0.006, 0.01, 0.026))])); color = RGBf(0.5, 0.35, 0.2),
                     material = oakm, name = :cartcord_cog)
    CK[:pegs] = mesh!(sc, ck_merge(pegs(0.043, 36, -0.006, 0.006)); color = RGBf(0.86, 0.80, 0.66), material = mo_wood(moving = true, base = (0.95, 0.89, 0.75)),
                      name = :cartcord_pegs)
    CK[:pinion] = mesh!(sc, ck_merge(vcat([ck_ring(0.002, 0.006, -0.006, 0.006; n = 12)], pegs(0.007, 6, -0.006, 0.006)));
                        color = RGBf(0.5, 0.35, 0.2), material = oakm, name = :cartcord_pinion)
    CK[:pulley] = mesh!(sc, ck_merge([ck_ring(0.009, 0.04, -0.012, 0.012), ck_ring(0.030, 0.042, -0.014, -0.012), ck_ring(0.030, 0.042, 0.012, 0.014)]);
                        color = RGBf(0.5, 0.35, 0.2), material = oakm, name = :cartcord_pulley)
    CK[:belt] = mesh!(sc, ck_box((0, 0, 0), (0.01, 0.01, 0.01)); color = RGBf(0.3, 0.17, 0.09), material = CK_LEATHER, name = :cartcord_belt)
    CK[:cord_obs] = Observable(mtube([ck_world(w, 0.0), ck_world(w, CK_X0)], CK_CORD_R; nring = 8))
    mesh!(sc, CK[:cord_obs]; color = RGBf(0.80, 0.74, 0.60), material = CK_CLOTH, name = :cartcord_cord)
    CK[:clip] = mesh!(sc, ck_box((-0.008, -0.006, -0.006), (0.016, 0.012, 0.012)); color = RGBf(0.86, 0.46, 0.24), material = mo_copper(),
                      name = :cartcord_clip)
    CK[:built] = sc
    CK[:sim] = CartCord.Sim(; L_cord = CK_CORD, on = false, cart = CartCord.Cart(x = CK_X0),
                            belt = CartCord.Belt(gear = 6, r_p = 0.015, r_a = 0.04))
    ck_draw!(w)
end

"Put every part where the simulation has it."
function ck_draw!(w)
    s = CK[:sim]; x = s.cart.x
    c = ck_world(w, x) + Point3f(0, 0, CK_RW)          # the cart's middle at axle height
    for p in CK[:parts]
        Makie.translate!(p, c)
    end
    φ = Float32(x / CK_RW)
    for (wh, p) in CK[:wheels]
        Makie.rotate!(wh, Makie.qrotation(Vec3f(0, 1, 0), -φ)); Makie.translate!(wh, c + p)
    end
    mc = c + Point3f(0.195, 0, 0.126)                  # the motor's axle (along y)
    Makie.rotate!(CK[:drum], Makie.qrotation(Vec3f(0, 1, 0), -Float32(s.st.θ))); Makie.translate!(CK[:drum], mc)
    Makie.translate!(CK[:coil], mc)
    # the 36-cog wheel turns the 15 mm pulley; the belt runs down to the 40 mm pulley on the rear axle
    gφ = Float32(s.st.θ / s.belt.gear)                 # the countershaft turns the other way, 6 times slower
    cs = mc + Point3f(-0.050, 0.0, 0)
    Makie.rotate!(CK[:pinion], Makie.qrotation(Vec3f(0, 1, 0), -Float32(s.st.θ))); Makie.translate!(CK[:pinion], mc + Point3f(0, 0.11, 0))
    for k in (:cog, :pegs)
        Makie.rotate!(CK[k], Makie.qrotation(Vec3f(0, 1, 0), gφ)); Makie.translate!(CK[k], cs + Point3f(0, 0.11, 0))
    end
    ra = Float32(s.belt.r_a)
    Makie.scale!(CK[:pulley], Vec3f(ra / 0.04f0, 1, ra / 0.04f0))
    Makie.rotate!(CK[:pulley], Makie.qrotation(Vec3f(0, 1, 0), -φ)); Makie.translate!(CK[:pulley], c + Point3f(0.24, 0.13, 0))
    top = cs + Point3f(0, 0.135, 0); bot = c + Point3f(0.24, 0.13, 0)
    belt = mtube([top + Point3f(-0.015, 0, 0), bot + Point3f(-ra, 0, 0), bot + Point3f(0, 0, -ra), bot + Point3f(ra, 0, 0),
                  top + Point3f(0.015, 0, 0), top + Point3f(0, 0, 0.015), top + Point3f(-0.015, 0, 0)], 0.003f0; nring = 5)
    CK[:belt][1][] = belt
    # the cord: from the clip (or wherever its end now lies) over the tether's particles to the cart's rear
    pts = [ck_world(w, xi[1]) + Point3f(0, 0, CK_CORD_R) for xi in s.cord.x]    # the cord lies on the planks
    pts[1] = s.clipped ? Point3f(CK_CLIP[1], CK_CLIP[2], NG.ground(w.island, CK_CLIP)[3] + 0.15f0) : pts[1]
    pts[end] = c + Point3f(0.33, 0, 0.03)
    CK[:cord_obs][] = mtube(pts, CK_CORD_R; nring = 8)
    Makie.translate!(CK[:clip], pts[1])
end

push!(NG.BUSY_GOALS, :cart)

"Switch it on where it stands (at the start: Lumi pushed it back and clipped the cord on again)."
function ck_start!(w, who)
    s = CK[:sim]
    get(CK, :phase, :ready) === :ready || return
    s.st.on = true; s.taut = false; empty!(s.events)
    CK[:told] = Set{String}(); CK[:phase] = :run
    # s180: the pots' emf at their plates as the switch closes (they sag while the cart drives, come back at rest)
    NG.emit!(w, :cart_switched_on; who, pots_volts = round(s.st.E; digits = 3))
end

"""
s177: after the yank Lumi walks to the cart's front and pushes it back along the planks (the same physics: a push
force held to a walking pace, the belt turning the dead motor backwards), then clips the cord onto the pot again.
"""
function ck_push!(w, s)
    me = NG.creature(w, "Lumi")
    front = ck_world(w, s.cart.x + 0.45)
    if me === nothing || me.controlled
        s.F_ext = 0.0; return
    end
    if me.goal.kind !== :cart
        me.goal.kind in (:sleep, :flight) && return
        me.goal = NG.Goal(:cart, front, :idle, 1.0, 0.0, false, 0, false)
        NG.say!(w, me, "Ran out of cord. Back you go."; duration = 2.5)
    end
    me.goal.target = front; me.goal.arrived = false
    close = hypot(me.pos[1] - front[1], me.pos[2] - front[2]) < 0.35
    s.F_ext = close ? clamp(60.0 * (-0.25 - s.cart.v), -15.0, 0.0) : 0.0
    if s.cart.x <= CK_X0 + 0.02
        s.F_ext = 0.0; s.cart.v = 0.0; s.clipped = true
        n = length(s.cord.x) - 1                       # Lumi coils the cord back in a heap by the pot as it clips on
        for k in 0:n
            s.cord.x[k+1] = (k / n * s.cart.x, 0.0, 0.0); s.cord.v[k+1] = (0.0, 0.0, 0.0)
        end
        CK[:phase] = :ready
        me.goal = NG.Goal(:wander, me.pos, :idle, 1.0, 0.0, false, 0, false)
        NG.say!(w, me, "Clipped on. Again!"; duration = 2.5)
        NG.emit!(w, :cart_pushed_back; who = "Lumi")
    end
end

function NG.step!(::CartCordSys, game, dt)
    game.stage === nothing && return
    get(CK, :built, nothing) === game.stage.scene && get(CK, :sim, nothing) isa CartCord.Sim || ck_build!(game)
    w = game.world; s = CK[:sim]
    me = NG.creature(w, "Lumi")
    if me !== nothing && me.controlled
        near = hypot(me.pos[1] - (CK_CLIP[1] - Float32(s.cart.x)), me.pos[2] - CK_Y) < 0.9
        down = CK_KEY in game.keys_down; was = get(CK, :kdown, false); CK[:kdown] = down
        near && down && !was && ck_start!(w, "player")
        # P: change the axle pulley while the cart stands at the start (the belt is moved to the new one)
        pd = CK_PKEY in game.keys_down; pw = get(CK, :pdown, false); CK[:pdown] = pd
        if near && pd && !pw && get(CK, :phase, :ready) === :ready
            i = something(findfirst(r -> abs(r - s.belt.r_a) < 1e-6, CK_PULLEYS), 2)
            s.belt.r_a = CK_PULLEYS[mod1(i + 1, length(CK_PULLEYS))]
            ratio = round(Int, s.belt.gear * s.belt.r_a / s.belt.r_p)
            NG.say!(w, me, "Axle pulley $(round(Int, 2000s.belt.r_a)) mm: $(ratio) to 1"; duration = 2.5)
            NG.emit!(w, :cart_pulley; mm = round(Int, 2000s.belt.r_a), ratio)
            ck_draw!(w)
        end
    elseif w.t > get(CK, :next_run, w.t + 30.0)
        ck_start!(w, "Lumi")
        CK[:next_run] = w.t + 240.0
    end
    haskey(CK, :next_run) || (CK[:next_run] = w.t + 30.0)
    xm = s.cart.x
    s.cart.slope = 0.0                                  # the road is level (ck_road)
    phase = get(CK, :phase, :ready)
    if phase === :run && !s.st.on && abs(s.cart.v) < 1e-5 && abs(s.st.ω) < 1e-3
        CK[:phase] = phase = s.cart.x > CK_X0 + 0.05 ? :push : :ready
    end
    phase === :push && ck_push!(w, s)
    moving = s.st.on || abs(s.cart.v) > 1e-5 || abs(s.st.ω) > 1e-3 || s.F_ext != 0
    if moving
        for _ in 1:max(1, round(Int, min(dt, 0.05) / 1e-3))
            CartCord.step!(s, 1e-3)
        end
        ck_draw!(w)
    else
        CartCord.rest!(s, min(dt, 0.05))                # s180: the pots' layers relax while the cart stands
    end
    told = get!(CK, :told, Set{String}())
    if !s.st.on && "drove" in told && !("sagged" in told)
        # s180: one run's sag, said when the motor stops (the pots' emf now vs at the switch)
        push!(told, "sagged"); NG.emit!(w, :pots_sagged; volts = round(s.st.E; digits = 3), fresh = round(sum(PotCell.emf, s.pots); digits = 3))
    end
    if s.cart.x > CK_X0 + 1.0 && !("drove" in told)
        push!(told, "drove"); NG.emit!(w, :cart_drove; metres = s.cart.x - CK_X0, cm_s = 100 * s.cart.v)
    end
    if !s.clipped && !("yank" in told)
        push!(told, "yank"); NG.emit!(w, :cord_yanked; metres = s.cart.x - CK_X0, cord_m = CK_CORD)
    end
end

function NG.stop!(::CartCordSys, game)
    game.stage === nothing && return
    for p in copy(game.stage.scene.plots)
        haskey(p.attributes, :name) && startswith(string(p.attributes[:name][]), "cartcord_") && delete!(game.stage.scene, p)
    end
    delete!(CK, :built)
end

register!(CartCordSys())
