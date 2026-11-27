# The wire I drew burns out where I rushed it (s155, projects/drawn-wire.md). A 0.1 mm copper wire drawn from a 0.5 mm
# rod in 15 passes (physics/draw.jl), one pass rushed 30% along its length: a neck 47 um thick in a 50 um wire. Laid
# between two copper posts on a bank of 8 cells (0.75 V, 0.105 Ohm each; physics/circuit.jl), switched on at 1 s: the
# whole wire heats, the neck first and hottest; it parts THERE at 2.5 s and the rest goes dark. Real time. Every
# segment's glow is its solved temperature: colour from Planck's law at 450/550/650 nm, strength from the radiance at
# 600 nm through a square-root tone curve (the camera's exposure; the true range is 1:7000 from 900 K to melting).
#   submit_job(:clip; path, script = "movies/drawnwire.jl", call = "drawnwire_clip")
using NeverendingGame, GeometryBasics, Makie, LinearAlgebra
const NG = NeverendingGame
Base.include(@__MODULE__, joinpath(@__DIR__, "..", "physics", "draw.jl"))
Base.include(@__MODULE__, joinpath(@__DIR__, "..", "physics", "circuit.jl"))

function dtube(pts, rad; nring = 8)
    P = [Point3f(p...) for p in pts]
    n = length(P)
    verts = Point3f[]; fcs = GLTriangleFace[]
    for i in 1:n
        t = normalize(i == 1 ? P[2] - P[1] : i == n ? P[n] - P[n-1] : P[i+1] - P[i-1])
        a = abs(t[3]) < 0.9 ? Vec3f(0, 0, 1) : Vec3f(1, 0, 0)
        u = normalize(cross(t, a)); w = cross(t, u)
        for k in 0:nring-1
            ph = 2pi * k / nring
            push!(verts, P[i] + rad * (cos(ph) * u + sin(ph) * w))
        end
    end
    for i in 1:n-1, k in 0:nring-1
        a = (i - 1) * nring + k + 1; b = (i - 1) * nring + mod(k + 1, nring) + 1
        c = i * nring + k + 1; d = i * nring + mod(k + 1, nring) + 1
        push!(fcs, GLTriangleFace(a, c, b)); push!(fcs, GLTriangleFace(b, c, d))
    end
    GeometryBasics.normal_mesh(GeometryBasics.Mesh(verts, fcs))
end

"The rod drawn carefully except one pass rushed at `frac` along (the hand stops when the load has fallen by `give`)."
function drawn_rod(; frac = 0.3, give = 0.1)
    rod = Draw.Rod(d = 0.5e-3, L = 0.004, ds = 1e-4)
    holes = Float64[]; r = 0.25e-3
    while r > 0.0505e-3
        r = max(0.05e-3, r * sqrt(0.8)); push!(holes, r)
    end
    rushed = false
    for h in holes
        if h < 0.105e-3 && !rushed
            Draw.pass!(rod, holes[end]; stone = :basalt, give, from = round(Int, frac * length(rod.r)))
            rushed = true
        end
        Draw.pass!(rod, h; stone = :basalt)
    end
    rod
end

"Run the wire on the cell bank; temperatures and parted segments every film frame (switched on at `on`)."
function burn_frames(rod; Rcell = 0.105, ncell = 8, dt = 0.005, seconds = 5.0, fps = 24, on = 1.0)
    C = Circuit
    cells = [C.Cell((0.02 * (i - 1) + 0.012, 0.0, 0.0), (0.02 * (i - 1), 0.0, 0.0); emf = 0.75, R = Rcell, r_term = 4e-3) for i in 1:ncell]
    pts = Draw.layout(rod, (0.0, 0.05, 0.0), (1.0, 0.0, 0.0)); L = sum(rod.l)
    xe = 0.02 * (ncell - 1) + 0.012
    lead1 = C.straight((0.0, 0.0, 0.0), (0.0, 0.05, 0.0); ds = 5e-3, r = 0.5e-3)
    lp = vcat([(xe, y, 0.0) for y in 0:0.005:0.08], [(x, 0.08, 0.0) for x in xe-0.005:-0.005:L+0.001], [(L, 0.08, 0.0)],
              [(L, y, 0.0) for y in 0.075:-0.005:0.05])
    wire = C.Wire(pts; r = rod.r)
    net = C.Net(wires = [lead1, C.Wire(lp; r = 0.5e-3), wire], cells = cells)
    nf = round(Int, seconds * fps)
    T = [fill(C.T_AMB, length(wire.T)) for _ in 1:nf]; P = [falses(length(wire.T)) for _ in 1:nf]
    t = 0.0; tpart = NaN
    for f in 1:nf
        tf = (f - 1) / fps
        while t < tf - on - 1e-9
            C.step!(net, dt); t += dt
            isnan(tpart) && any(>=(1.0), wire.melt) && (tpart = t + on)
        end
        T[f] = copy(wire.T); P[f] = wire.melt .>= 1.0
    end
    (; T, P, tpart, L, at = findfirst(>=(1.0), wire.melt))
end

planck(lam, T) = 1 / (exp(0.014388 / (lam * T)) - 1)
const BINS = collect(range(800.0, 1358.0; length = 9))          # glow levels (K): below the first, plain copper

function glow_material(T)
    rgb = (planck(650e-9, T), planck(550e-9, T), planck(450e-9, T))
    m = maximum(rgb)
    s = 60 * sqrt(planck(600e-9, T) / planck(600e-9, 1358.0))
    NG.Hikari.Emission(color = Float32.(rgb ./ m), strength = Float32(s), two_sided = true)
end

const WIRE_SPOT = (5.6f0, -13.0f0)      # open ground by the tops board (the motor film's spot; s155 first try sat in a plant clump)

function drawnwire_parts(; seconds = 5.0, fps = 24, on = 1.0)
    rod = drawn_rod()
    run = burn_frames(rod; seconds, fps, on)
    S = Dict{Symbol,Any}()
    copper = NG.Hikari.Copper(roughness = 0.22f0)
    stone = NG.Hikari.Diffuse(color = (0.34, 0.31, 0.28), roughness = 0.9f0)
    setup = function (gm)
        for p in gm.stage.scene.plots
            haskey(p.attributes, :name) && p.attributes[:name][] in (:rain, :rainrings, :raincloud) && (p.visible[] = false)
        end
        isdefined(Main, :SHOWERS) && (Main.SHOWERS[:off] = true)
        w = gm.world; sc = gm.stage.scene
        g = NG.ground(w.island, WIRE_SPOT)
        base = Point3f(g[1], g[2], g[3] + 0.04f0)                 # top of the stone slab
        h = 0.03f0                                              # wire height over the slab
        L = Float32(run.L)
        O = base + Point3f(-L / 2, 0, h)                        # the wire's first end
        S[:O] = O
        mesh!(sc, GeometryBasics.normal_mesh(Rect3f(base - Point3f(L / 2 + 0.03f0, 0.05f0, 0.04f0), Vec3f(L + 0.06f0, 0.1f0, 0.04f0)));
              color = RGBf(0.34, 0.31, 0.28), name = :dw_slab, material = stone)
        for (k, x) in enumerate((0.0f0, L))                     # two thick copper posts the wire is wound on
            mesh!(sc, GeometryBasics.normal_mesh(Cylinder(base + Point3f(x - L / 2, 0, 0), base + Point3f(x - L / 2, 0, h + 0.004f0), 0.0025f0));
                  color = RGBf(0.85, 0.45, 0.3), material = copper, name = Symbol("dw_post", k))
        end
        pts = [O + Point3f(Float32(sum(rod.l[1:i])), 0, 0) for i in 0:length(rod.l)]
        segs = Vector{Any}(undef, length(rod.r)); glows = [Any[] for _ in rod.r]
        for i in eachindex(rod.r)
            m = dtube([pts[i], pts[i+1]], Float32(rod.r[i]))
            segs[i] = mesh!(sc, m; color = RGBf(0.85, 0.45, 0.3), material = copper, name = Symbol("dw_seg", i))
            for b in 1:length(BINS)-1
                Tm = (BINS[b] + BINS[b+1]) / 2
                gp = mesh!(sc, dtube([pts[i], pts[i+1]], Float32(rod.r[i]) * 1.02f0); color = RGBf(1, 0.4, 0.1),
                           material = glow_material(Tm), name = Symbol("dw_glow", i, "_", b))
                gp.visible[] = false
                push!(glows[i], gp)
            end
        end
        S[:segs] = segs; S[:glows] = glows; S[:pts] = pts
        for c in w.creatures
            hypot(c.pos[1] - WIRE_SPOT[1], c.pos[2] - WIRE_SPOT[2]) < 6 && c.name != "Lumi" &&
                (c.pos = NG.ground(w.island, (WIRE_SPOT[1] + 14f0, WIRE_SPOT[2] - 9f0)); c.goal = NG.Goal())
            c.name == "Lumi" && (c.controlled = true)
        end
    end
    shot = function (gm, rig, t)
        for p in gm.stage.scene.plots
            haskey(p.attributes, :name) && (p.attributes[:name][] in (:tops_live_board, :tops_live_top)) && (p.visible[] = false)
        end
        f = clamp(round(Int, t * fps) + 1, 1, length(run.T))
        T = run.T[f]; P = run.P[f]
        for i in eachindex(T)
            S[:segs][i].visible[] = !P[i]
            b = min(searchsortedlast(BINS, T[i]), length(BINS) - 1)   # at the melting point: the brightest level
            for (k, gp) in enumerate(S[:glows][i])
                gp.visible[] = !P[i] && k == b
            end
        end
        neck = S[:pts][run.at === nothing ? 12 : run.at]
        me = NG.creature(gm.world, "Lumi")
        if me !== nothing                                       # Lumi behind the slab, watching its wire
            me.pos = NG.ground(gm.world.island, (neck[1] + 0.15f0, neck[2] + 0.75f0)); me.yaw = -1.75f0
        end
        rig.mode = :fixed
        rig.eye = neck + Point3f(-0.006f0, -0.02f0, 0.009f0)    # 2.3 cm from the neck (the rig has no zoom; its view is wide)
        rig.target = neck + Point3f(0.003f0, 0.004f0, -0.002f0)
        return nothing
    end
    return setup, shot, S, run
end

function drawnwire_clip(path; samples = 24, width = 960, height = 540, fps = 24, seconds = 5.0, hour = 18.4, rasterize = false)
    setup, shot, S, run = drawnwire_parts(; seconds, fps)
    res = NG.game_clip(path; size = (width, height), seconds, fps, samples, hour, warmup = 0.3, rasterize,
                       rig = NG.CameraRig(; mode = :fixed), setup, shot, fade = 0)
    return merge(res, (; path, parts_at_s = run.tpart, parts_at_segment = run.at))
end
