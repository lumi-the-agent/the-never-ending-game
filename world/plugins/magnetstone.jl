# The magnet stone (s147, big goal "Sparks from stones", road step 1). A magnet stone lies on the north beach
# at (-3.8, 18.9), and iron spikes from an old boat lie scattered around it. Jumped in as Lumi, stand by the stone and
# press 5 to pick it up (5 again puts it down); carried, it hangs low in front of Lumi, and every spike feels it.
# Physics, nothing scripted: the stone is a ceramic magnet block (physics/em.jl: field of any mesh + magnetisation, the
# charge model, Br from EM.MATERIALS[:ferrite]). A spike is soft iron: the stone's field H magnetises it along its
# length up to saturation (a long rod's demagnetising factor N ~ (ln 2a - 1)/a^2), across it barely (N = 1/2). The pull
# is (m . grad) B, the turn is m x B. On the sand it slides only when the pull beats Coulomb friction, it lifts when
# the pull beats its weight, and it sticks where it touches the stone and rides along while the field holds it.
using GeometryBasics, Makie, LinearAlgebra
isdefined(Main, :MAGSTONE) || Core.eval(Main, :(const MAGSTONE = Dict{Symbol,Any}()))
const NG = NeverendingGame
const MS = Main.MAGSTONE
Base.include(@__MODULE__, joinpath(@__DIR__, "..", "physics", "em.jl"))

const MG_SPOT = (-3.8f0, 18.9f0)          # the north beach, bare sand
const MG_KEY = Makie.Keyboard._5
const MG_NEAR = 1.0f0
const MG_FAR = 0.45
# each quadrature charge stands for a 1.75 cm patch of the face: smear it over half that (field at 15 cm changes ~0.3%)
const MG_EPS2 = (0.5 * 2 * 0.07 / 8)^2
const MG_HALF = (0.07, 0.055, 0.045)          # half sizes of the block, m
const MG_NSPIKE = 14
const SP_L = 0.12; const SP_R = 0.003          # an old boat spike: 12 cm, 6 mm thick
const SP_V = pi * SP_R^2 * SP_L
const SP_M = EM.MATERIALS[:iron].density * SP_V
const SP_MS = 1.7e6                            # iron's saturation magnetisation, A/m
const SP_NPAR = let a = SP_L / (2SP_R); (log(2a) - 1) / a^2 end
const SP_MU = 0.5                              # iron on sand
const G = 9.81

struct MagnetStone <: System end

mutable struct Spike
    p::NTuple{3,Float64}; v::NTuple{3,Float64}
    u::NTuple{3,Float64}                       # unit axis
    w::Float64                                 # yaw rate on the ground
    stuck::Bool; rel::NTuple{3,Float64}; relu::NTuple{3,Float64}   # where on the stone (stone frame) when stuck
end

t3(a) = (Float64(a[1]), Float64(a[2]), Float64(a[3]))
add(a, b) = (a[1] + b[1], a[2] + b[2], a[3] + b[3]); sub(a, b) = (a[1] - b[1], a[2] - b[2], a[3] - b[3])
mul(s, a) = (s * a[1], s * a[2], s * a[3]); dot3(a, b) = a[1] * b[1] + a[2] * b[2] + a[3] * b[3]
cross3(a, b) = (a[2] * b[3] - a[3] * b[2], a[3] * b[1] - a[1] * b[3], a[1] * b[2] - a[2] * b[1])
nrm(a) = sqrt(dot3(a, a)); unit(a) = mul(1 / max(nrm(a), 1e-12), a)

function box_mesh(h)
    v = [(sx * h[1], sy * h[2], sz * h[3]) for sz in (-1, 1) for sy in (-1, 1) for sx in (-1, 1)]
    f = [(1, 3, 4), (1, 4, 2), (5, 6, 8), (5, 8, 7), (1, 2, 6), (1, 6, 5), (3, 7, 8), (3, 8, 4), (1, 5, 7), (1, 7, 3), (2, 4, 8), (2, 8, 6)]
    v, f
end

# the stone's charges in its own frame, built once. Magnetised along its long axis (x, the way Lumi carries it): its
# poles are its ends, like a lodestone's (s147: magnetised up, its field level with it was vertical and a floating
# compass beside it could not turn)
function mg_charges()
    v, f = box_mesh(MG_HALF)
    m = EM.magnet(v, f, (EM.MATERIALS[:ferrite].Br / EM.MU0, 0.0, 0.0); n = 8)
    m.pts, m.q
end

# H at world point p from the stone at c with yaw psi (no allocation)
function mg_H(p, c, psi)
    cs, sn = cos(psi), sin(psi)
    d0 = sub(p, c)
    d = (cs * d0[1] + sn * d0[2], -sn * d0[1] + cs * d0[2], d0[3])      # into the stone's frame
    hx, hy, hz = _mg_sum(d, MS[:pts]::Vector{NTuple{3,Float64}}, MS[:q]::Vector{Float64})
    (cs * hx - sn * hy, sn * hx + cs * hy, hz)
end
function _mg_sum(d, P, Q)          # typed (a function barrier: MS is a Dict{Symbol,Any})
    hx = 0.0; hy = 0.0; hz = 0.0
    @inbounds for k in eachindex(Q)
        e = sub(d, P[k]); r2 = dot3(e, e) + MG_EPS2; s = Q[k] / (4pi * r2 * sqrt(r2))
        hx += s * e[1]; hy += s * e[2]; hz += s * e[3]
    end
    (hx, hy, hz)
end
mg_B(p, c, psi) = mul(EM.MU0, mg_H(p, c, psi))

inside_stone(p, c, psi; pad = 0.0) = begin
    cs, sn = cos(psi), sin(psi); d0 = sub(p, c)
    d = (cs * d0[1] + sn * d0[2], -sn * d0[1] + cs * d0[2], d0[3])
    abs(d[1]) < MG_HALF[1] + pad && abs(d[2]) < MG_HALF[2] + pad && abs(d[3]) < MG_HALF[3] + pad
end
to_stone(p, c, psi) = (d0 = sub(p, c); (cos(psi) * d0[1] + sin(psi) * d0[2], -sin(psi) * d0[1] + cos(psi) * d0[2], d0[3]))
from_stone(d, c, psi) = add(c, (cos(psi) * d[1] - sin(psi) * d[2], sin(psi) * d[1] + cos(psi) * d[2], d[3]))
rot_from_stone(d, psi) = (cos(psi) * d[1] - sin(psi) * d[2], sin(psi) * d[1] + cos(psi) * d[2], d[3])

"Induced moment of a spike with axis u in field H: along the rod up to saturation, across it H/N with N = 1/2."
function spike_m(u, H)
    hp = dot3(H, u)
    mp = clamp(hp / SP_NPAR, -SP_MS, SP_MS)
    hq = sub(H, mul(hp, u))
    mul(SP_V, add(mul(mp, u), mul(2.0, hq)))
end

ground_z(w, x, y) = Float64(NG.ground(w.island, (Float32(x), Float32(y)))[3])

function mg_ensure!(game)
    # a reloaded plugin has a new Spike type, and MS outlives it: old spikes fail the typeassert in mg_physics!
    # and switch the system off (s148: the worker's compass film had no stone, no spikes)
    haskey(MS, :spikes) && !(MS[:spikes] isa Vector{Spike}) && (delete!(MS, :spikes); delete!(MS, :plots))
    haskey(MS, :spikes) && haskey(MS, :plots) && return
    for p in copy(game.stage.scene.plots)
        haskey(p.attributes, :name) && p.attributes[:name][] in (:magnetstone_block, :magnetstone_spikes) && delete!(game.stage.scene, p)
    end
    w = game.world
    MS[:pts], MS[:q] = mg_charges()
    gz = ground_z(w, MG_SPOT...)
    MS[:c] = (Float64(MG_SPOT[1]), Float64(MG_SPOT[2]), gz + MG_HALF[3]); MS[:psi] = 0.0; MS[:carried] = false
    rng = Random.MersenneTwister(147)
    MS[:spikes] = map(1:MG_NSPIKE) do i
        x, y = 0.0, 0.0
        while true                                             # on dry sand, not in the sea
            a = 2pi * rand(rng); r = 0.45 + 1.1 * rand(rng)
            x = MG_SPOT[1] + r * cos(a); y = MG_SPOT[2] + r * sin(a)
            ground_z(w, x, y) > 0.1 && break
        end
        yaw = 2pi * rand(rng)
        Spike((x, y, ground_z(w, x, y) + SP_R), (0.0, 0.0, 0.0), (cos(yaw), sin(yaw), 0.0), 0.0, false, (0.0, 0.0, 0.0), (1.0, 0.0, 0.0))
    end
    blk = GeometryBasics.normal_mesh(Rect3f(Point3f(-MG_HALF[1], -MG_HALF[2], -MG_HALF[3]), Vec3f(2MG_HALF[1], 2MG_HALF[2], 2MG_HALF[3])))
    MS[:blk] = Observable(Makie.Mat4f(Makie.I))
    pb = mesh!(game.stage.scene, blk; color = RGBf(0.16, 0.15, 0.17), name = :magnetstone_block,
               material = NG.Hikari.Diffuse(color = (0.16, 0.15, 0.17), roughness = 0.7f0))
    nail = GeometryBasics.normal_mesh(Cylinder(Point3f(0, 0, -SP_L / 2), Point3f(0, 0, SP_L / 2), Float32(SP_R)))
    pos = Observable([Point3f(s.p...) for s in MS[:spikes]]); rot = Observable([Vec3f(s.u...) for s in MS[:spikes]])
    ps = meshscatter!(game.stage.scene, pos; marker = nail, rotation = rot, markersize = 1f0, color = RGBf(0.42, 0.24, 0.14),
                      name = :magnetstone_spikes, material = NG.Hikari.Diffuse(color = (0.42, 0.24, 0.14), roughness = 0.6f0))
    MS[:plots] = (pb, ps); MS[:pos] = pos; MS[:rot] = rot
    mg_place_block!()
    return
end

function mg_place_block!()
    pb = MS[:plots][1]; c = MS[:c]
    Makie.rotate!(pb, Makie.qrotation(Vec3f(0, 0, 1), Float32(MS[:psi])))
    Makie.translate!(pb, Vec3f(c...))
end

function mg_physics!(w, dt)
    c = MS[:c]::NTuple{3,Float64}; psi = MS[:psi]::Float64
    # adaptive steps: a spike moves at most 4 mm per step, so a fast one cannot pass the stone's surface between two
    # steps (s147: one did, took the near field's energy and flew 25 m)
    for s in MS[:spikes]::Vector{Spike}
      tl = dt; iters = 0
      while tl > 1e-9 && iters < 200
        h = min(tl, dt / 4, 0.004 / max(nrm(s.v), 1e-6)); tl -= h; iters += 1
        # at rest past MG_FAR the pull is <0.2% of what friction holds (s147: 8.7x at 15 cm, 0.1x at 25, 0.0015x at 40): skip
        !s.stuck && s.v == (0.0, 0.0, 0.0) && s.w == 0.0 && hypot(s.p[1] - c[1], s.p[2] - c[2]) > MG_FAR && continue
        if s.stuck
            s.p = from_stone(s.rel, c, psi); s.u = rot_from_stone(s.relu, psi); s.v = (0.0, 0.0, 0.0)
            Hc = mg_H(s.p, c, psi); m = spike_m(s.u, Hc)
            # held while the pull towards the stone (at contact) beats its weight; else it drops
            dl = 0.004; mh = unit(m); mm = nrm(m)
            gB = mul(mm / (2dl), sub(mg_B(add(s.p, mul(dl, mh)), c, psi), mg_B(sub(s.p, mul(dl, mh)), c, psi)))
            towards = unit(sub(c, s.p))
            dot3(gB, towards) < SP_M * G && (s.stuck = false)
            continue
        end
        Hc = mg_H(s.p, c, psi)
        m = spike_m(s.u, Hc); mm = nrm(m)
        F = (0.0, 0.0, -SP_M * G)
        if mm > 1e-9
            dl = 0.004; mh = mul(1 / mm, m)
            F = add(F, mul(mm / (2dl), sub(mg_B(add(s.p, mul(dl, mh)), c, psi), mg_B(sub(s.p, mul(dl, mh)), c, psi))))
        end
        T = cross3(m, mul(EM.MU0, Hc))
        gz = ground_z(w, s.p[1], s.p[2]) + SP_R
        on_ground = s.p[3] <= gz + 1e-4 && F[3] <= 0
        if on_ground
            N = -F[3]
            Fh = (F[1], F[2], 0.0); vh = (s.v[1], s.v[2], 0.0)
            if nrm(vh) < 1e-3 && nrm(Fh) <= SP_MU * N
                s.v = (0.0, 0.0, 0.0)                                     # static friction holds it
            else
                fr = nrm(vh) > 1e-6 ? mul(-SP_MU * N / nrm(vh), vh) : mul(-SP_MU * N / max(nrm(Fh), 1e-12), Fh)
                a = mul(1 / SP_M, add(Fh, fr))
                nv = add(vh, mul(h, a))
                dot3(nv, vh) < 0 && nrm(Fh) <= SP_MU * N && (nv = (0.0, 0.0, 0.0))   # friction stops, never reverses
                s.v = nv
            end
            # yaw: the z torque turns it on the sand against friction (a rod pivoting: friction torque ~ mu N L/4)
            I = SP_M * SP_L^2 / 12; tf = SP_MU * N * SP_L / 4
            if abs(s.w) < 1e-3 && abs(T[3]) <= tf
                s.w = 0.0
            else
                s.w += h * (T[3] - sign(s.w == 0 ? T[3] : s.w) * tf) / I
            end
            ang = s.w * h; cs, sn = cos(ang), sin(ang)
            s.u = unit((cs * s.u[1] - sn * s.u[2], sn * s.u[1] + cs * s.u[2], 0.0))
            s.p = add(s.p, mul(h, s.v)); s.p = (s.p[1], s.p[2], ground_z(w, s.p[1], s.p[2]) + SP_R)
        else
            s.v = add(mul(0.995, s.v), mul(h / SP_M, F))             # a little air drag
            # in the air the field turns it along B fast (it is light): integrate the axis with the torque, damped
            I = SP_M * SP_L^2 / 12
            om = mul(h / I * 0.5, T)
            s.u = unit(add(s.u, cross3(om, s.u)))
            s.p = add(s.p, mul(h, s.v))
            gz2 = ground_z(w, s.p[1], s.p[2]) + SP_R
            if s.p[3] < gz2
                s.p = (s.p[1], s.p[2], gz2); s.v = (0.3 * s.v[1], 0.3 * s.v[2], 0.0)
                s.u = unit((s.u[1], s.u[2], 0.0) == (0.0, 0.0, 0.0) ? (1.0, 0.0, 0.0) : (s.u[1], s.u[2], 0.0))
            end
        end
        # touching the stone: it sticks (iron on a magnet), end first, where it touched
        tip1 = add(s.p, mul(SP_L / 2, s.u)); tip2 = sub(s.p, mul(SP_L / 2, s.u))
        if inside_stone(tip1, c, psi; pad = 0.002) || inside_stone(tip2, c, psi; pad = 0.002) || inside_stone(s.p, c, psi; pad = SP_R)
            s.stuck = true; s.rel = to_stone(s.p, c, psi)
            s.relu = (cos(psi) * s.u[1] + sin(psi) * s.u[2], -sin(psi) * s.u[1] + cos(psi) * s.u[2], s.u[3])
            NG.emit!(w, :magnet_grab; n = count(x -> x.stuck, MS[:spikes]))
        end
      end
    end
end

function NG.step!(::MagnetStone, game, dt)
    game.stage === nothing && return
    me = NG.creature(game.world, "Lumi")
    me === nothing && return
    mg_ensure!(game)
    w = game.world
    dt = min(Float64(dt), 1 / 30)
    free = game.minigame === nothing || game.minigame isa NG.JumpIn
    c = MS[:c]
    near = me.controlled && free && hypot(me.pos[1] - c[1], me.pos[2] - c[2]) < MG_NEAR
    down = MG_KEY in game.keys_down
    if down && !get(MS, :down, false)
        if MS[:carried]
            MS[:carried] = false
            NG.say!(w, me, "Down it goes."; duration = 1.2)
        elseif near
            MS[:carried] = true
            NG.say!(w, me, "The magnet stone! Let's see what it finds."; duration = 2.0)
            NG.emit!(w, :magnet_pickup)
        end
    end
    MS[:down] = down
    if MS[:carried] && !(me.controlled && free)
        MS[:carried] = false                                     # Jump in ended: it stays where it was
    end
    if MS[:carried]
        fx, fy = cos(me.yaw), sin(me.yaw)
        x = me.pos[1] + 0.45 * fx; y = me.pos[2] + 0.45 * fy
        MS[:c] = (x, y, ground_z(w, x, y) + MG_HALF[3] + 0.03); MS[:psi] = Float64(me.yaw)
    else
        cc = MS[:c]; MS[:c] = (cc[1], cc[2], ground_z(w, cc[1], cc[2]) + MG_HALF[3])
    end
    t0 = time_ns()
    mg_physics!(w, dt)
    MS[:ms] = (time_ns() - t0) / 1e6
    mg_place_block!()
    Makie.update!(MS[:plots][2]; arg1 = [Point3f(s.p...) for s in MS[:spikes]], rotation = [Vec3f(s.u...) for s in MS[:spikes]])
    return
end

function NG.stop!(::MagnetStone, game)
    game.stage === nothing && return
    for p in copy(game.stage.scene.plots)
        haskey(p.attributes, :name) && p.attributes[:name][] in (:magnetstone_block, :magnetstone_spikes) && delete!(game.stage.scene, p)
    end
    delete!(MS, :plots)
end

register!(MagnetStone())
