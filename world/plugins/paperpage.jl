# A page of my notebook flutters down (s127). Not keyframed: each page is a rigid plate (A4, 80 g/m², 5 g) falling
# through air with quasi-steady flat-plate aerodynamics: a force across the page from the angle the air meets it
# (lift slope 2π at small angles, a plate's 1.2 at large ones), applied at a centre of pressure that sits a quarter of
# the way in from the leading edge at grazing angles and in the middle when it falls flat. That offset makes the
# turning moment that real falling paper has (Andersen, Pesavento & Wang 2005): the page swings, side-slips and
# sometimes tumbles by itself. Plus skin friction along the page and rotational air damping; 1 ms substeps.
# It lands by contact: each corner that reaches the ground gets a normal impulse (no bounce) and friction (μ 0.6), so the
# page rocks down onto the grass and comes to rest by itself; at rest it lies there PAGE_LIE seconds, and is gone.
#   Every PAGE_EVERY s of game time a page drops 4 m over Lumi.   Main.PAPERPAGE[:force] = true  drop one now.
const NG = NeverendingGame
using LinearAlgebra: norm, cross, dot, normalize
isdefined(Main, :PAPERPAGE) || Core.eval(Main, :(const PAPERPAGE = Dict{Symbol,Any}()))
const PP = Main.PAPERPAGE

const PAGE_A = 0.297f0          # m, along e1
const PAGE_B = 0.21f0           # m, along e2
const PAGE_M = 0.08f0 * PAGE_A * PAGE_B
const PAGE_I = Vec3f(PAGE_M * PAGE_B^2 / 12, PAGE_M * PAGE_A^2 / 12, PAGE_M * (PAGE_A^2 + PAGE_B^2) / 12)  # body e1, e2, n
const PAGE_RHO = 1.2f0
const PAGE_EVERY = 150.0
const PAGE_LIE = 45.0
const PAGE_N = 3
const PAGE_WIND = Vec3f(0.35, 0.15, 0)

mutable struct Page
    x::Vec3f
    v::Vec3f
    R::Mat3f        # columns: e1, e2, n
    w::Vec3f        # angular velocity, world
    landed_at::Float64
    on::Bool
    still::Float32  # s it has lain without moving
end

mutable struct PaperPage <: System
    next_at::Float64
    pages::Vector{Page}
end

skew(w) = Mat3f(0, w[3], -w[2], -w[3], 0, w[1], w[2], -w[1], 0)
function orthonormal(R::Mat3f)
    e1 = normalize(Vec3f(R[:, 1])); e2 = Vec3f(R[:, 2]); e2 = normalize(e2 - dot(e2, e1) * e1)
    return Mat3f(e1..., e2..., cross(e1, e2)...)
end

"One substep of a falling plate: gravity, the air across it at its centre of pressure, friction along it, rotational damping."
function page_step!(p::Page, dt::Float32)
    e1, e2, n = Vec3f(p.R[:, 1]), Vec3f(p.R[:, 2]), Vec3f(p.R[:, 3])
    A = PAGE_A * PAGE_B
    u = p.v - PAGE_WIND
    s = norm(u)
    F = Vec3f(0, 0, -9.81f0 * PAGE_M)
    τ = zero(Vec3f)
    if s > 1f-4
        un = dot(u, n)
        ut = u - un * n
        sa = clamp(abs(un) / s, 0f0, 1f0)                       # sin of the angle of attack
        cn = min(2f0 * Float32(pi) * sa, 1.2f0)
        FN = -0.5f0 * PAGE_RHO * cn * A * s^2 * sign(un) * n
        nt = norm(ut)
        if nt > 1f-5
            t = ut / nt                                          # the way the page moves in its own plane: the leading edge
            L = PAGE_A * abs(dot(t, e1)) + PAGE_B * abs(dot(t, e2))
            d = 0.25f0 * L * sqrt(1f0 - sa^2)                    # quarter chord at grazing, the middle when falling flat
            τ += cross(d * t, FN)
            F += -0.5f0 * PAGE_RHO * 0.04f0 * A * nt * ut       # skin friction, both sides
        end
        F += FN
    end
    # rotational air damping (quadratic) and a touch of linear
    wb = p.R' * p.w
    span = Vec3f(PAGE_B, PAGE_A, max(PAGE_A, PAGE_B))
    τb = Vec3f((-0.5f0 * PAGE_RHO * span[i]^5 * PAGE_A * abs(wb[i]) * wb[i] / 8 - 2f-7 * wb[i] for i in 1:3)...)
    τ += p.R * τb
    # Euler's equations in the body frame
    tb = p.R' * τ
    wdot_b = Vec3f((tb[1] - (PAGE_I[3] - PAGE_I[2]) * wb[2] * wb[3]) / PAGE_I[1],
                   (tb[2] - (PAGE_I[1] - PAGE_I[3]) * wb[3] * wb[1]) / PAGE_I[2],
                   (tb[3] - (PAGE_I[2] - PAGE_I[1]) * wb[1] * wb[2]) / PAGE_I[3])
    p.w += dt * (p.R * wdot_b)
    p.v += dt * F / PAGE_M
    p.x += dt * p.v
    p.R = orthonormal(p.R + dt * skew(p.w) * p.R)
end

function page_corners(p::Page)
    e1, e2 = Vec3f(p.R[:, 1]), Vec3f(p.R[:, 2])
    return [Point3f(p.x + sa * PAGE_A / 2 * e1 + sb * PAGE_B / 2 * e2) for (sa, sb) in ((-1, -1), (1, -1), (1, 1), (-1, 1))]
end
const PAGE_FACES = [GLTriangleFace(1, 2, 3), GLTriangleFace(1, 3, 4)]

page_touching(p::Page, is) = any(q -> q[3] <= NG.terrain_height(is, q[1], q[2]) + 0.003f0, page_corners(p))

"Ground contact at the corners: push out of the ground, a normal impulse that stops the corner sinking, Coulomb friction."
function page_contacts!(p::Page, is, dt::Float32)
    Iinv = p.R * Mat3f(1 / PAGE_I[1], 0, 0, 0, 1 / PAGE_I[2], 0, 0, 0, 1 / PAGE_I[3]) * p.R'
    for q in page_corners(p)
        g = NG.terrain_height(is, q[1], q[2]) + 0.002f0
        q[3] < g || continue
        p.x += Vec3f(0, 0, g - q[3])
        r = Vec3f(q) - p.x
        vc = p.v + cross(p.w, r)
        vc[3] < 0 || continue
        ez = Vec3f(0, 0, 1)
        rn = cross(r, ez)
        jn = -vc[3] / (1 / PAGE_M + dot(rn, Iinv * rn))
        p.v += jn * ez / PAGE_M
        p.w += Iinv * (jn * rn)
        vc = p.v + cross(p.w, r)
        vt = Vec3f(vc[1], vc[2], 0)
        nt = norm(vt)
        nt > 1f-6 || continue
        t = vt / nt
        rt = cross(r, t)
        jt = min(nt / (1 / PAGE_M + dot(rt, Iinv * rt)), 0.6f0 * jn)
        p.v -= jt * t / PAGE_M
        p.w -= Iinv * (jt * rt)
    end
end

pp_find(sc, name) = (i = findfirst(q -> haskey(q.attributes, :name) && q.attributes[:name][] == name, sc.plots);
                     i === nothing ? nothing : sc.plots[i])

function pp_setup!(game)
    sc = game.stage.scene
    PP[:plots] = Any[]
    for k in 1:PAGE_N
        name = Symbol("paperpage_", k)
        old = pp_find(sc, name)
        old === nothing || delete!(sc, old)
        hide = [Point3f(0, 0, -50), Point3f(0.1, 0, -50), Point3f(0.1, 0.1, -50), Point3f(0, 0.1, -50)]
        push!(PP[:plots], mesh!(sc, GeometryBasics.Mesh(hide, PAGE_FACES); color = RGBf(0.96, 0.95, 0.9),
                                material = NG.Hikari.DiffuseTransmission(reflectance = (0.82, 0.8, 0.74), transmittance = (0.45, 0.43, 0.38)),
                                name, visible = false))
    end
    PP[:scene] = sc
end

function pp_drop!(sys::PaperPage, w)
    me = findfirst(c -> c.name == "Lumi", w.creatures)
    me === nothing && return
    k = findfirst(p -> !p.on, sys.pages)
    k === nothing && (k = argmin([p.landed_at for p in sys.pages]))
    c = w.creatures[me]
    a = Float32(2pi * rand()); tilt = 0.25f0 + 0.35f0 * rand(Float32)
    Rz = Mat3f(cos(a), sin(a), 0, -sin(a), cos(a), 0, 0, 0, 1)
    Rx = Mat3f(1, 0, 0, 0, cos(tilt), sin(tilt), 0, -sin(tilt), cos(tilt))
    x = Vec3f(c.pos[1] + 0.6f0, c.pos[2] - 0.4f0, NG.terrain_height(w.island, c.pos[1], c.pos[2]) + 4.2f0)
    sys.pages[k] = Page(x, Vec3f(0), Rz * Rx, Vec3f(0), Inf, true, 0f0)
    PP[:plots][k].visible = true
    NG.emit!(w, :paperpage_drop; page = k)
end

function NG.step!(sys::PaperPage, game, dt)
    game.stage === nothing && return
    (get(PP, :scene, nothing) === game.stage.scene && haskey(PP, :plots)) || pp_setup!(game)
    w = game.world
    PP[:sys] = sys
    if get(PP, :force, false) || w.t >= sys.next_at
        PP[:force] = false
        sys.next_at = w.t + PAGE_EVERY
        pp_drop!(sys, w)
    end
    h = Float32(clamp(dt, 0, 0.05))
    n = max(1, ceil(Int, h / 0.001f0))
    for (k, p) in enumerate(sys.pages)
        p.on || continue
        if isinf(p.landed_at)
            for _ in 1:n
                page_step!(p, h / n)
                page_contacts!(p, w.island, h / n)
            end
            if norm(p.v) < 0.03f0 && norm(p.w) < 0.3f0 && page_touching(p, w.island)
                p.still += h
                if p.still > 0.4f0
                    p.v = zero(Vec3f); p.w = zero(Vec3f)
                    p.landed_at = w.t
                    NG.emit!(w, :paperpage_land; page = k)
                end
            else
                p.still = 0f0
            end
        elseif w.t - p.landed_at > PAGE_LIE
            p.on = false
            PP[:plots][k].visible = false
            continue
        end
        Makie.update!(PP[:plots][k]; arg1 = GeometryBasics.Mesh(page_corners(p), PAGE_FACES))
    end
end

function NG.stop!(sys::PaperPage, game)
    haskey(PP, :plots) || return
    for q in PP[:plots]
        q.visible = false
    end
end

register!(PaperPage(0.0, [Page(Vec3f(0), Vec3f(0), Mat3f(1, 0, 0, 0, 1, 0, 0, 0, 1), Vec3f(0), Inf, false, 0f0) for _ in 1:PAGE_N]))
