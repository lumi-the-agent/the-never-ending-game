# The compass bowl (s147, big goal "Sparks from stones"). Above the north beach at (-4.9, 17.8), a stone basin of
# water with a lily pad floating in it, and on the pad an iron spike that was magnetised (remanence 1 T). The needle
# turns by the torque m x B and nothing else: B is the island's own weak field (25 uT horizontal, pointing +y, "north")
# plus the magnet stone's field (plugins/magnetstone.jl), computed from the stone's own surface charges wherever it is.
# Carry the stone past the bowl and the needle swings to it; take it away and it swings back north. The water damps the
# pad through its viscous (Stokes) boundary layer, c = pi mu r^4 / delta, delta = sqrt(nu / omega), so it swings a while.
using GeometryBasics, Makie, LinearAlgebra
isdefined(Main, :COMPASSBOWL) || Core.eval(Main, :(const COMPASSBOWL = Dict{Symbol,Any}()))
const NG = NeverendingGame
const CB = Main.COMPASSBOWL

const CB_SPOT = (-4.9f0, 17.8f0)
const CB_R = 0.25f0                     # basin radius
const MU0 = 4pi * 1e-7
const B_ISLAND = (0.0, 25e-6)           # horizontal field of the island, T
const N_L = 0.12; const N_R = 0.003     # the needle: a 12 cm spike
const N_M = 1.0 / MU0 * pi * N_R^2 * N_L        # its moment, A m^2 (remanence 1 T)
const N_MASS = 7870 * pi * N_R^2 * N_L
const PAD_R = 0.09; const PAD_MASS = 0.004
const I_ZZ = N_MASS * N_L^2 / 12 + PAD_MASS * PAD_R^2 / 2
const MU_W = 1.0e-3; const NU_W = 1.0e-6

struct CompassBowl <: System end

# the stone's field at p (horizontal part), from the charges magnetstone.jl keeps in Main.MAGSTONE
function stone_B(p)
    isdefined(Main, :MAGSTONE) || return (0.0, 0.0)
    MS = Main.MAGSTONE
    haskey(MS, :pts) && haskey(MS, :c) || return (0.0, 0.0)
    _stone_B(p, MS[:pts]::Vector{NTuple{3,Float64}}, MS[:q]::Vector{Float64}, MS[:c]::NTuple{3,Float64}, MS[:psi]::Float64)
end
function _stone_B(p, P, Q, c, psi)
    cs, sn = cos(psi), sin(psi)
    d0 = (p[1] - c[1], p[2] - c[2], p[3] - c[3])
    d = (cs * d0[1] + sn * d0[2], -sn * d0[1] + cs * d0[2], d0[3])
    hx = 0.0; hy = 0.0
    @inbounds for k in eachindex(Q)
        e1 = d[1] - P[k][1]; e2 = d[2] - P[k][2]; e3 = d[3] - P[k][3]
        r2 = e1 * e1 + e2 * e2 + e3 * e3; s = Q[k] / (4pi * r2 * sqrt(r2))
        hx += s * e1; hy += s * e2
    end
    (MU0 * (cs * hx - sn * hy), MU0 * (sn * hx + cs * hy))
end

function cb_ensure!(game)
    haskey(CB, :plots) && return
    for p in copy(game.stage.scene.plots)
        haskey(p.attributes, :name) && startswith(string(p.attributes[:name][]), "compassbowl_") && delete!(game.stage.scene, p)
    end
    g = NG.ground(game.world.island, CB_SPOT)
    base = Point3f(g[1], g[2], g[3])
    CB[:base] = base
    CB[:th] = get(CB, :th, 0.3); CB[:w] = get(CB, :w, 0.0)
    stone = NG.Hikari.Diffuse(color = (0.55, 0.53, 0.50), roughness = 0.8f0)
    bowl = GeometryBasics.normal_mesh(Cylinder(base, base + Point3f(0, 0, 0.10f0), CB_R))
    water = GeometryBasics.normal_mesh(Cylinder(base + Point3f(0, 0, 0.10f0), base + Point3f(0, 0, 0.102f0), CB_R - 0.025f0))
    pad = GeometryBasics.normal_mesh(Cylinder(Point3f(0, 0, 0), Point3f(0, 0, 0.004f0), Float32(PAD_R)))
    north = GeometryBasics.normal_mesh(Cylinder(Point3f(0, 0, 0.007f0), Point3f(Float32(N_L / 2), 0, 0.007f0), Float32(N_R)))
    south = GeometryBasics.normal_mesh(Cylinder(Point3f(-Float32(N_L / 2), 0, 0.007f0), Point3f(0, 0, 0.007f0), Float32(N_R)))
    p1 = mesh!(game.stage.scene, bowl; color = RGBf(0.55, 0.53, 0.50), name = :compassbowl_bowl, material = stone)
    p2 = mesh!(game.stage.scene, water; color = RGBf(0.25, 0.42, 0.50), name = :compassbowl_water,
               material = NG.Hikari.Diffuse(color = (0.25, 0.42, 0.50), roughness = 0.05f0))
    p3 = mesh!(game.stage.scene, pad; color = RGBf(0.30, 0.55, 0.22), name = :compassbowl_pad,
               material = NG.Hikari.Diffuse(color = (0.30, 0.55, 0.22), roughness = 0.5f0))
    p4 = mesh!(game.stage.scene, north; color = RGBf(0.80, 0.12, 0.10), name = :compassbowl_north,
               material = NG.Hikari.Diffuse(color = (0.80, 0.12, 0.10), roughness = 0.4f0))
    p5 = mesh!(game.stage.scene, south; color = RGBf(0.30, 0.29, 0.28), name = :compassbowl_south,
               material = NG.Hikari.Diffuse(color = (0.30, 0.29, 0.28), roughness = 0.4f0))
    CB[:plots] = (p1, p2, p3, p4, p5)
    return
end

function NG.step!(::CompassBowl, game, dt)
    game.stage === nothing && return
    cb_ensure!(game)
    w = game.world
    base = CB[:base]::Point3f
    p = (Float64(base[1]), Float64(base[2]), Float64(base[3]) + 0.11)
    bs = stone_B(p)
    B = (B_ISLAND[1] + bs[1], B_ISLAND[2] + bs[2])
    th = CB[:th]::Float64; om = CB[:w]::Float64
    nsub = 8; h = min(Float64(dt), 1 / 20) / nsub
    for _ in 1:nsub
        k = N_M * hypot(B...)
        delta = sqrt(NU_W / max(sqrt(k / I_ZZ), 0.05))          # Stokes layer at the swing's own frequency
        c = pi * MU_W * PAD_R^4 / delta
        tau = N_M * (cos(th) * B[2] - sin(th) * B[1]) - c * om
        om += h * tau / I_ZZ
        th += h * om
    end
    CB[:th] = mod(th + pi, 2pi) - pi; CB[:w] = om
    q = Makie.qrotation(Vec3f(0, 0, 1), Float32(th))
    top = base + Point3f(0, 0, 0.102f0)
    for pl in CB[:plots][3:5]
        Makie.rotate!(pl, q); Makie.translate!(pl, Vec3f(top...))
    end
    # Lumi notices when the stone beats the island's field at the bowl
    strong = hypot(bs...) > hypot(B_ISLAND...)
    if strong && !get(CB, :strong, false)
        me = NG.creature(w, "Lumi")
        me !== nothing && hypot(me.pos[1] - base[1], me.pos[2] - base[2]) < 3 && NG.say!(w, me, "The needle turned to the stone!"; duration = 2.0)
        NG.emit!(w, :compass_swing; uT = round(hypot(bs...) * 1e6))
    end
    CB[:strong] = strong
    return
end

function NG.stop!(::CompassBowl, game)
    game.stage === nothing && return
    for p in copy(game.stage.scene.plots)
        haskey(p.attributes, :name) && startswith(string(p.attributes[:name][]), "compassbowl_") && delete!(game.stage.scene, p)
    end
    delete!(CB, :plots)
end

register!(CompassBowl())
