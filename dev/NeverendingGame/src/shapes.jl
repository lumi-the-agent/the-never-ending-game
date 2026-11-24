# ── Unit meshes that body parts and props are made of ───────────────────────
#
# Every part is one of these unit shapes, scaled per part by a `Vec3f`, so a
# species is just a list of shapes, sizes, offsets and materials. All shapes are
# centred on the origin unless noted, with smooth normals.

"Unit sphere, radius 1."
unit_sphere(n::Int = 32) = GeometryBasics.normal_mesh(GeometryBasics.Tessellation(Sphere(Point3f(0), 1.0f0), n))

"""
Capsule of radius 1 along z: the sphere's upper half is shifted up by 0.5 and
the lower half down by 0.5, so it spans z in [-1.5, 1.5]. Normals of a sphere
stay correct for a capsule built this way.
"""
function unit_capsule(n::Int = 32)
    m = unit_sphere(n)
    pts = [Point3f(p[1], p[2], p[3] + (p[3] >= 0 ? 0.5f0 : -0.5f0)) for p in GeometryBasics.coordinates(m)]
    return GeometryBasics.Mesh(pts, GeometryBasics.faces(m); normal = GeometryBasics.normals(m))
end

"Cone with base radius 1 at z = 0 and apex at z = 1."
function unit_cone(n::Int = 32)
    pts = Point3f[]; nrm = Vec3f[]; fs = GLTriangleFace[]
    slope = normalize(Vec2f(1, 1))
    for i in 0:n
        a = 2pi * i / n
        d = Vec3f(cos(a), sin(a), 0)
        push!(pts, Point3f(d)); push!(nrm, normalize(Vec3f(d[1] * slope[2], d[2] * slope[2], slope[1])))
        push!(pts, Point3f(0, 0, 1)); push!(nrm, normalize(Vec3f(d[1] * slope[2], d[2] * slope[2], slope[1])))
    end
    for i in 0:(n - 1)
        b = 2i + 1
        push!(fs, GLTriangleFace(b, b + 2, b + 1))
    end
    # base cap
    c = length(pts) + 1
    push!(pts, Point3f(0, 0, 0)); push!(nrm, Vec3f(0, 0, -1))
    for i in 0:n
        a = 2pi * i / n
        push!(pts, Point3f(cos(a), sin(a), 0)); push!(nrm, Vec3f(0, 0, -1))
    end
    for i in 1:n
        push!(fs, GLTriangleFace(c, c + i + 1, c + i))
    end
    return GeometryBasics.Mesh(pts, fs; normal = nrm)
end

"Cylinder of radius 1 from z = 0 to z = 1 (with caps)."
unit_cylinder(n::Int = 32) =
    GeometryBasics.normal_mesh(GeometryBasics.Tessellation(Cylinder(Point3f(0, 0, 0), Point3f(0, 0, 1), 1.0f0), n))

"Torus in the xy plane: ring radius 1, tube radius `r`."
function unit_torus(r::Float32 = 0.3f0, n::Int = 32, m::Int = 16)
    pts = Point3f[]; nrm = Vec3f[]; fs = GLTriangleFace[]
    for i in 0:n, j in 0:m
        u = 2pi * i / n; v = 2pi * j / m
        c = Vec3f(cos(u), sin(u), 0)
        d = Vec3f(cos(v) * cos(u), cos(v) * sin(u), sin(v))
        push!(pts, Point3f(c + r * d)); push!(nrm, d)
    end
    idx(i, j) = i * (m + 1) + j + 1
    for i in 0:(n - 1), j in 0:(m - 1)
        push!(fs, GLTriangleFace(idx(i, j), idx(i + 1, j), idx(i + 1, j + 1)))
        push!(fs, GLTriangleFace(idx(i, j), idx(i + 1, j + 1), idx(i, j + 1)))
    end
    return GeometryBasics.Mesh(pts, fs; normal = nrm)
end

"The named unit shapes. Plugins may add more with `register_shape!`."
const SHAPES = Dict{Symbol,Any}()

function register_shape!(name::Symbol, mesh)
    SHAPES[name] = mesh
    return mesh
end

function shape(name::Symbol)
    isempty(SHAPES) && init_shapes!()
    return SHAPES[name]
end

"How far a shape reaches from its z axis (1 for the unit shapes; a mesh part's own footprint)."
shape_radius(name::Symbol) = maximum(p -> norm(Vec2f(p[1], p[2])), GeometryBasics.coordinates(shape(name)))

function init_shapes!()
    register_shape!(:sphere, unit_sphere())
    register_shape!(:capsule, unit_capsule())
    register_shape!(:cone, unit_cone())
    register_shape!(:cylinder, unit_cylinder())
    register_shape!(:torus, unit_torus())
    return SHAPES
end
