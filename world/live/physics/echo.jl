# The island answers a clap (s129): acoustic ray tracing through the island's real geometry with Raycore's BVH.
# Rays leave the clap in every direction and bounce (mostly mirror-like, partly scattered) off whatever they hit.
# At every hit, "diffuse rain": if the listener is in plain view of the hit point, the scattered part of the ray's
# energy reaches the ear after (path so far + distance to the ear) / 343 m/s. The arrivals make the impulse
# response; a synthetic hand clap convolved with it is what you hear. Nothing is placed by hand: an echo exists
# because a surface is there.
using Raycore, GeometryBasics, LinearAlgebra, StaticArrays, Random, Makie
const KA = Raycore.KernelAbstractions
const Adapt = Raycore.Adapt

const SOUND_C = 343f0

"A Raycore TLAS (on `backend`) holding the triangles (a, b, c) as one mesh."
function echo_tlas(tris, backend)
    pts = Point3f[]; fs = GLTriangleFace[]
    for (k, (a, b, c)) in enumerate(tris)
        push!(pts, a, b, c); push!(fs, GLTriangleFace(3k - 2, 3k - 1, 3k))
    end
    m = GeometryBasics.normal_mesh(GeometryBasics.Mesh(pts, fs))
    tlas = Raycore.TLAS(backend)
    push!(tlas, m, SMatrix{4,4,Float32,16}(1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1))
    Raycore.sync!(tlas)
    tlas
end

@inline function unit_dir(u1, u2)
    z = 1f0 - 2f0 * u1; r = sqrt(max(0f0, 1f0 - z * z)); ph = 2f0 * Float32(pi) * u2
    Vec3f(r * cos(ph), r * sin(ph), z)
end

# One thread per ray: up to B bounces; for each bounce writes the arrival delay (s) and energy at the ear.
# Slots per ray: 2b-1 the scattered share reaching the ear from the b-th hit ("diffuse rain"), 2b the ray itself
# passing through the ear's sphere after b reflections (the mirror echo of a wall, the image source).
KA.@kernel function echo_kernel!(delay, energy, tlas, src, ear, ear_r, u, refl, scatter, B)
    i = KA.@index(Global)
    @inbounds begin
        d = unit_dir(u[1, i], u[2, i])
        o = src; e = 1f0; L = 0f0
        for b in 1:2B
            delay[b, i] = 0f0; energy[b, i] = 0f0
        end
        for b in 0:B
            hit, tri, t, _, _ = Raycore.closest_hit(tlas, Raycore.Ray(; o = o, d = d))
            tseg = hit ? t : 2000f0
            if b >= 1            # a reflected ray passing the ear
                s = clamp(dot(ear - o, d), 0f0, tseg)
                if norm(o + s * d - ear) < ear_r
                    energy[2b, i] = e; delay[2b, i] = (L + s) / SOUND_C
                end
            end
            (hit && b < B) || break
            x = o + t * d; L += t
            v = tri.vertices
            n = normalize(cross(v[2] - v[1], v[3] - v[1]))
            dot(n, d) > 0 && (n = -n)
            e *= refl
            x = x + 0.01f0 * n
            toear = ear - x; de = norm(toear); w = toear / de
            c = dot(n, w)
            if c > 0
                blocked, _, tb, _, _ = Raycore.any_hit(tlas, Raycore.Ray(; o = x, d = w))
                if !blocked || tb > de
                    # scattered share, Lambert lobe, through the ear's disc
                    energy[2b + 1, i] = e * scatter * c / Float32(pi) * (Float32(pi) * ear_r^2) / max(de * de, 0.25f0)
                    delay[2b + 1, i] = (L + de) / SOUND_C
                end
            end
            # the rest goes on mirror-like, a little roughened
            r = d - 2f0 * dot(d, n) * n
            j = unit_dir((u[3, i] * (b + 1)) % 1f0, (u[4, i] * (b + 1)) % 1f0)
            d = normalize(r + 0.25f0 * j); dot(d, n) < 0 && (d = r)
            e *= (1f0 - scatter)
            o = x
        end
    end
end

"""
    echo_arrivals(tlas, backend, src, ear; rays, bounces) -> (delays, energies)

Each ray carries 1/rays of the clap's energy. Energies are relative to a unit source.
"""
function echo_arrivals(tlas, backend, src, ear; rays = 200_000, bounces = 4, refl = 0.8f0, scatter = 0.5f0,
                       ear_r = 0.5f0, seed = 1)
    st = Adapt.adapt(backend, tlas)
    u = KA.allocate(backend, Float32, 4, rays); copyto!(u, rand(MersenneTwister(seed), Float32, 4, rays))
    delay = KA.zeros(backend, Float32, 2bounces + 1, rays); energy = KA.zeros(backend, Float32, 2bounces + 1, rays)
    echo_kernel!(backend)(delay, energy, st, Point3f(src), Point3f(ear), Float32(ear_r), u, Float32(refl),
                          Float32(scatter), bounces; ndrange = rays)
    KA.synchronize(backend)
    dl = vec(Array(delay)); en = vec(Array(energy)) ./ rays
    keep = en .> 0
    dl[keep], en[keep]
end

"Impulse response at `sr`: the direct sound, then every arrival as a click of amplitude sqrt(energy) (random sign)."
function echo_ir(delays, energies, direct_d; sr = 24000, seconds = 1.5, seed = 2, ear_r = 0.5)
    ir = zeros(Float64, round(Int, seconds * sr))
    rng = MersenneTwister(seed)
    j = round(Int, direct_d / SOUND_C * sr) + 1
    ir[j] += sqrt(pi * ear_r^2 / (4pi * direct_d^2))    # power through the ear's disc, like the arrivals
    for (t, e) in zip(delays, energies)
        k = round(Int, t * sr) + 1
        k <= length(ir) && (ir[k] += sqrt(e) * (rand(rng) < 0.5 ? -1 : 1) * exp(-t / 2.0))  # air
    end
    ir
end

"A hand clap: a few ms of shaped noise with a body around 1-2 kHz."
function clap_sound(; sr = 24000, seed = 5)
    rng = MersenneTwister(seed); n = round(Int, 0.09 * sr); y = 0.0; y2 = 0.0
    map(1:n) do j
        t = j / sr
        y = 0.55y + 0.45 * (2rand(rng) - 1)       # soften the top
        y2 = 0.8y2 + 0.2y
        (y - y2) * (t < 0.002 ? t / 0.002 : exp(-(t - 0.002) / 0.012))
    end
end

"Convolve a sound with an impulse response (direct, small sizes)."
function convolve(a, h)
    out = zeros(Float64, length(a) + length(h) - 1)
    nz = findall(!iszero, h)
    for k in nz, (i, x) in enumerate(a)
        out[i + k - 1] += x * h[k]
    end
    out
end

function write_wav(path, buf; sr = 24000)
    buf = buf ./ max(1e-9, maximum(abs, buf) / 0.85)
    open(path, "w") do io
        n = length(buf)
        write(io, "RIFF", UInt32(36 + 2n), "WAVE", "fmt ", UInt32(16), UInt16(1), UInt16(1), UInt32(sr), UInt32(2sr),
              UInt16(2), UInt16(16), "data", UInt32(2n))
        for x in buf; write(io, round(Int16, clamp(x, -1, 1) * 32000)); end
    end
    path
end

# ── seeing the clap (s130): where and when the sound touches the island ─────────────────────────────

# One thread per ray: the point of each of its first B hits, the time the sound gets there (path / 343 m/s)
# and the energy it still carries (the same reflection as `echo_kernel!`). A time of -1 marks no hit.
KA.@kernel function echo_hits_kernel!(hx, ht, he, tlas, src, u, refl, scatter, B)
    i = KA.@index(Global)
    @inbounds begin
        d = unit_dir(u[1, i], u[2, i])
        o = src; e = 1f0; L = 0f0
        for b in 1:B
            ht[b, i] = -1f0; he[b, i] = 0f0
        end
        for b in 1:B
            hit, tri, t, _, _ = Raycore.closest_hit(tlas, Raycore.Ray(; o = o, d = d))
            hit || break
            x = o + t * d; L += t
            hx[1, b, i] = x[1]; hx[2, b, i] = x[2]; hx[3, b, i] = x[3]
            ht[b, i] = L / SOUND_C; he[b, i] = e
            v = tri.vertices
            n = normalize(cross(v[2] - v[1], v[3] - v[1]))
            dot(n, d) > 0 && (n = -n)
            e *= refl * (1f0 - scatter)
            x = x + 0.01f0 * n
            r = d - 2f0 * dot(d, n) * n
            j = unit_dir((u[3, i] * b) % 1f0, (u[4, i] * b) % 1f0)
            d = normalize(r + 0.25f0 * j); dot(d, n) < 0 && (d = r)
            o = x
        end
    end
end

"""
    echo_hits(tlas, backend, src; rays, bounces) -> (pos::Vector{Point3f}, time::Vector{Float32}, energy::Vector{Float32})

Every place a clap at `src` touches the island, with the time the sound arrives there (s) and the energy the ray
still carries (1 at the clap). Rays are spread evenly over the sphere, so the density of points is the loudness.
"""
function echo_hits(tlas, backend, src; rays = 4000, bounces = 3, refl = 0.8f0, scatter = 0.5f0, seed = 1)
    st = Adapt.adapt(backend, tlas)
    u = KA.allocate(backend, Float32, 4, rays); copyto!(u, rand(MersenneTwister(seed), Float32, 4, rays))
    hx = KA.zeros(backend, Float32, 3, bounces, rays)
    ht = KA.zeros(backend, Float32, bounces, rays); he = KA.zeros(backend, Float32, bounces, rays)
    echo_hits_kernel!(backend)(hx, ht, he, st, Point3f(src), u, Float32(refl), Float32(scatter), bounces; ndrange = rays)
    KA.synchronize(backend)
    X = Array(hx); T = vec(Array(ht)); E = vec(Array(he))
    keep = findall(>=(0f0), T)
    P = [Point3f(X[1, k], X[2, k], X[3, k]) for k in CartesianIndices((bounces, rays))][:]
    P[keep], T[keep], E[keep]
end

"""
    stage_triangles(scene) -> Vector{NTuple{3,Point3f}}

The world triangles of every visible mesh and meshscatter in a stage scene (transforms, markersize and rotation
applied). Call it while the scene is alive (inside `with_scratch_game`'s do-block or a film's `setup`).
`keep(plot)` picks the plots (atomic plots: test `Makie.parent_scene`-free things like the name of the top plot).
"""
function stage_triangles(scene; keep = p -> true)
    tris = NTuple{3,Point3f}[]
    addmesh!(m, f) = begin
        ps = GeometryBasics.decompose(Point3f, m); fs = GeometryBasics.decompose(GLTriangleFace, m)
        for fc in fs
            push!(tris, (f(ps[fc[1]]), f(ps[fc[2]]), f(ps[fc[3]])))
        end
    end
    for p in Makie.collect_atomic_plots(scene)
        Makie.to_value(get(p.attributes, :visible, true)) || continue
        keep(p) || continue
        M = Makie.transformationmatrix(p)[]
        tf(x) = Point3f((M * Vec4f(x[1], x[2], x[3], 1))[Vec(1, 2, 3)])
        if p isa Makie.Mesh
            addmesh!(p[1][], tf)
        elseif p isa Makie.MeshScatter
            marker = Makie.to_value(p.marker)      # a mesh or a primitive: decompose takes both
            pos = p[1][]; ms = p.markersize[]; rot = p.rotation[]
            for (k, x) in enumerate(pos)
                s = ms isa AbstractVector && !(ms isa StaticVector) ? ms[k] : ms       # a Vec3f is ONE size
                q = Makie.to_rotation(rot isa AbstractVector && !(rot isa StaticVector) ? rot[k] : rot)
                S = s isa Number ? Vec3f(s) : Vec3f(s...)
                addmesh!(marker, y -> tf(Point3f(x) + q * Vec3f(S .* Vec3f(y))))
            end
        end
    end
    tris
end

# ── Hearing where a sound comes from (s132, projects/owl-ears.md) ──────────────────────────────────────────────
# The owl's head is the ear. Like echo_kernel!, every ray from the sound bounces through the island; each arrival
# at the head also records the direction it comes FROM (unit vector from the head), so the listener can place the
# sound the way animals do: by the first wavefront (precedence effect), not by the loudest.
KA.@kernel function hear_kernel!(delay, energy, from, tlas, src, ear, ear_r, u, refl, scatter, B)
    i = KA.@index(Global)
    @inbounds begin
        d = unit_dir(u[1, i], u[2, i])
        o = src; e = 1f0; L = 0f0
        for b in 1:2B
            delay[b, i] = 0f0; energy[b, i] = 0f0
            from[1, b, i] = 0f0; from[2, b, i] = 0f0; from[3, b, i] = 0f0
        end
        for b in 0:B
            hit, tri, t, _, _ = Raycore.closest_hit(tlas, Raycore.Ray(; o = o, d = d))
            tseg = hit ? t : 2000f0
            if b >= 1            # a reflected ray passing through the head: comes from back along the ray
                s = clamp(dot(ear - o, d), 0f0, tseg)
                if norm(o + s * d - ear) < ear_r
                    energy[2b, i] = e; delay[2b, i] = (L + s) / SOUND_C
                    from[1, 2b, i] = -d[1]; from[2, 2b, i] = -d[2]; from[3, 2b, i] = -d[3]
                end
            end
            (hit && b < B) || break
            x = o + t * d; L += t
            v = tri.vertices
            n = normalize(cross(v[2] - v[1], v[3] - v[1]))
            dot(n, d) > 0 && (n = -n)
            e *= refl
            x = x + 0.01f0 * n
            toear = ear - x; de = norm(toear); w = toear / de
            c = dot(n, w)
            if c > 0
                blocked, _, tb, _, _ = Raycore.any_hit(tlas, Raycore.Ray(; o = x, d = w))
                if !blocked || tb > de
                    energy[2b + 1, i] = e * scatter * c / Float32(pi) * (Float32(pi) * ear_r^2) / max(de * de, 0.25f0)
                    delay[2b + 1, i] = (L + de) / SOUND_C
                    from[1, 2b + 1, i] = -w[1]; from[2, 2b + 1, i] = -w[2]; from[3, 2b + 1, i] = -w[3]
                end
            end
            r = d - 2f0 * dot(d, n) * n
            j = unit_dir((u[3, i] * (b + 1)) % 1f0, (u[4, i] * (b + 1)) % 1f0)
            d = normalize(r + 0.25f0 * j); dot(d, n) < 0 && (d = r)
            e *= (1f0 - scatter)
            o = x
        end
    end
end

"Line of sight: 1 in `open_[1]` when nothing is hit from `o` along `d` within `r`."
KA.@kernel function los_kernel!(open_, tlas, o, d, r)
    i = KA.@index(Global)
    hit, _, t, _, _ = Raycore.closest_hit(tlas, Raycore.Ray(; o = o, d = d))
    @inbounds open_[i] = (hit && t < r) ? Int32(0) : Int32(1)
end

"""
    hear(tlas, backend, src, ear; rays, bounces, window = 0.002) -> NamedTuple

What a listener with its head at `ear` hears of a sound at `src` (energies relative to a unit source):
`direct` (the straight path is open), `t0` (s, the first wavefront), `from` (unit vector from the head toward where
the first wavefront comes from: the energy-weighted direction of everything arriving within `window` of `t0`; the
precedence effect), `level` (dB re a unit source at 1 m, all energy in the first 80 ms), `n` (arrivals).
"""
function hear(tlas, backend, src, ear; rays = 20_000, bounces = 3, refl = 0.8f0, scatter = 0.5f0, ear_r = 0.5f0,
              window = 0.002f0, seed = 1)
    src = Point3f(src); ear = Point3f(ear)
    st = Adapt.adapt(backend, tlas)
    u = KA.allocate(backend, Float32, 4, rays); copyto!(u, rand(MersenneTwister(seed), Float32, 4, rays))
    delay = KA.zeros(backend, Float32, 2bounces + 1, rays); energy = KA.zeros(backend, Float32, 2bounces + 1, rays)
    from = KA.zeros(backend, Float32, 3, 2bounces + 1, rays)
    hear_kernel!(backend)(delay, energy, from, st, src, ear, Float32(ear_r), u, Float32(refl), Float32(scatter),
                          bounces; ndrange = rays)
    KA.synchronize(backend)
    D = vec(Array(delay)); E = vec(Array(energy)) ./ rays; F = reshape(Array(from), 3, :)
    k = findall(>(0f0), E)
    D = D[k]; E = E[k]; F = F[:, k]
    # the direct sound, if nothing stands between (inverse square: 1/(4 pi r^2) of a unit source through the head)
    dv = Vec3f(src - ear); r = norm(dv)
    open_ = KA.zeros(backend, Int32, 1)
    los_kernel!(backend)(open_, st, ear, dv / r, r - 0.05f0; ndrange = 1)
    KA.synchronize(backend)
    direct = Array(open_)[1] == 1
    if direct
        push!(D, r / SOUND_C); push!(E, Float32(pi) * ear_r^2 / (4f0 * Float32(pi) * r^2))
        F = hcat(F, dv / r)
    end
    isempty(E) && return (direct = direct, t0 = Inf32, from = Vec3f(0), level = -Inf32, n = 0)
    # the first wavefront: the earliest arrival carrying a noticeable share (single stray rays are noise)
    o = sortperm(D); cum = cumsum(E[o]); tot = cum[end]
    first_i = o[findfirst(>=(0.02f0 * tot), cum)]
    t0 = D[first_i]
    w = findall(t -> t0 <= t <= t0 + window, D)
    f = sum(E[j] * Vec3f(F[1, j], F[2, j], F[3, j]) for j in w)
    early = sum(E[j] for j in eachindex(D) if D[j] <= t0 + 0.08f0)
    (direct = direct, t0 = t0, from = f / max(norm(f), 1f-9), level = 10f0 * log10(early * 4f0 * Float32(pi) / (Float32(pi) * ear_r^2)),
     n = length(E))
end

"The solid world a sound meets: terrain, trees, rocks, logs, buildings and the asset actors; no grass, flowers,
creatures, particles or sky (a footstep in the grass must not count as walled in)."
const SOLID_NAMES = r"^(terrain|flora_tree|flora_bush|flora_rock|meadowlife_(log|stump|stones)|cairn_stones|gallery_(easels|wood)|area_pier|area_pond_stones|beachhut|obscura_hut_[0-9]|workshop_(bench|crate|rack)|tv_wood|swing_frame|garden_fence|blossom_trees|wheelbarrow|lookout_bench|meshscatter_[0-9]+)"
function solid_triangles(scene)
    keepers = Set{Any}()
    for p in scene.plots
        nm = haskey(p.attributes, :name) ? string(Makie.to_value(p.attributes[:name])) : ""
        occursin(SOLID_NAMES, nm) || continue
        for q in Makie.collect_atomic_plots(p)
            push!(keepers, q)
        end
    end
    stage_triangles(scene; keep = q -> q in keepers)
end
