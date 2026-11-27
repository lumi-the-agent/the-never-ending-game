# A jug with lines cut in it, dipped and fired (s141, project pottery): used by movies/kiln.jl and plugins/kiln.jl.
# Needs GeometryBasics and Makie in the including module.
Base.include(@__MODULE__, joinpath(@__DIR__, "glaze.jl"))

const JL = Glaze.L
# a paler celadon than the default: less iron, a few more bubbles (the museum pot is pale grey-green)
const GLAZE = (; α = (0.45, 0.36, 0.70), β = 0.2, tint = (0.70, 0.70, 0.62))
# Glaze.celadon gives LINEAR reflectance; a plot's colour is sRGB (RayMakie and the raster linearise it), so encode it
# (s141: passing linear values made the first jug film a muddy dark olive, 0.63 -> 0.35).
srgb(x) = x <= 0.0031308 ? 12.92x : 1.055x^(1 / 2.4) - 0.055
glaze_rgb(hm; dim = 1.0) = RGBf((srgb(dim * c) for c in Glaze.celadon(hm; GLAZE...))...)

"Jug profile radius (m) at height z (m): round belly, a neck from 12 cm, a lip at the top."
jug_r(z) = z < 0.118 ? 0.032 + 0.028 * sin(π * clamp((z + 0.01) / 0.14, 0, 1)) :
                       0.0365 - 0.006 * sin(π * clamp((z - 0.118) / 0.024, 0, 1)) + 0.004 * exp(-((z - 0.1425) / 0.002)^2)

"The cuts a potter makes in the leather-hard jug (relief in m): `pairs` double lines round it, a double ring, a raised ring at the shoulder."
function jug_body(nx, ny; pairs = 6, depth = 0.0006, width = 0.0008)
    b = zeros(nx, ny)
    C = nx * JL
    groove(d, w, dp) = d < w ? -dp * (1 - d / w) : 0.0
    ridge(d, w, ht) = d < w ? ht * sqrt(1 - (d / w)^2) : 0.0
    for j in 1:ny, i in 1:nx
        x = (i - 0.5) * JL; y = (j - 0.5) * JL
        v = 0.0
        if 0.012 < y < 0.112                              # the vertical double lines run over the belly
            for p in 0:pairs-1, off in (0.0, 0.0045)
                x0 = (p + 0.3) * C / pairs + off
                d = abs(x - x0); d = min(d, C - d)
                v = min(v, groove(d, width, depth))
            end
        end
        for y0 in (0.040, 0.0445)
            v = min(v, groove(abs(y - y0), width, depth))
        end
        v += ridge(abs(y - 0.100), 0.0012, 0.0010)          # pinched-up ring at the shoulder
        b[i, j] = v
    end
    b
end

"Fire the jug: returns relief b, glaze thickness h on the (round, up) grid. The foot (bottom 6 mm) is wiped bare, as potters do."
function fire_jug(; nx = 700, ny = 290, h0 = 0.00035, steps = 12000)
    b = jug_body(nx, ny)
    h = fill(h0, nx, ny)
    h[:, 1:12] .= 0.0
    Glaze.fire!(h, b; steps)
    b, h
end

"Mesh of the fired jug (outside, lip, inside, floor) with per-vertex colours from the glaze thickness."
function jug_mesh(b, h, base::Point3f; inner = 0.004, dz = JL)
    nx, ny = size(h)
    pts = Point3f[]; cols = RGBf[]
    W = nx + 1
    zs = [(j - 0.5) * dz for j in 1:ny]
    for j in 1:ny, k in 1:W                      # outside
        i = mod1(k, nx); θ = 2π * (k - 1) / nx
        r = jug_r(zs[j]) + b[i, j] + h[i, j]
        push!(pts, base + Point3f(r * cos(θ), r * sin(θ), zs[j]))
        push!(cols, glaze_rgb(h[i, j]))
    end
    o = length(pts)
    for j in 1:ny, k in 1:W                      # inside: glazed too (poured in and out), a plain coat
        θ = 2π * (k - 1) / W * (W / nx)
        r = max(jug_r(zs[j]) - inner, 0.004)
        push!(pts, base + Point3f(r * cos(θ), r * sin(θ), zs[j]))
        push!(cols, glaze_rgb(0.0004; dim = 0.6))
    end
    faces = TriangleFace{Int}[]
    for j in 1:ny-1, k in 1:W-1
        a = (j - 1) * W + k; c = j * W + k
        push!(faces, TriangleFace(a, a + 1, c + 1), TriangleFace(a, c + 1, c))
        a2 = o + a; c2 = o + c
        push!(faces, TriangleFace(a2, c2 + 1, a2 + 1), TriangleFace(a2, c2, c2 + 1))
    end
    for k in 1:W-1                               # the lip joins outside to inside
        a = (ny - 1) * W + k; a2 = o + a
        push!(faces, TriangleFace(a, a2 + 1, a + 1), TriangleFace(a, a2, a2 + 1))
    end
    ctr = length(pts) + 1                        # the floor inside
    push!(pts, base + Point3f(0, 0, zs[1])); push!(cols, cols[o+1])
    for k in 1:W-1
        push!(faces, TriangleFace(ctr, o + k + 1, o + k))
    end
    GeometryBasics.normal_mesh(pts, faces), cols
end


"Block means of the fired fields (si cells round, sj up): a lighter mesh for the live game. Use with `jug_mesh(...; dz = sj * JL)`."
function coarsen(b, h, si, sj)
    nx, ny = size(h)
    mx, my = nx ÷ si, ny ÷ sj
    bb = [sum(b[(I-1)*si+1:I*si, (J-1)*sj+1:J*sj]) / (si * sj) for I in 1:mx, J in 1:my]
    hh = [sum(h[(I-1)*si+1:I*si, (J-1)*sj+1:J*sj]) / (si * sj) for I in 1:mx, J in 1:my]
    bb, hh
end
