# Air on sheets: the drag a thin sheet feels moving through still or moving air, so paper falls
# like paper (slow, side-slipping, gliding where it tilts) instead of like a plate in vacuum.
# Per vertex: its share of the surface (a third of each triangle at it, as an area vector) and
# quadratic drag on the velocity relative to the wind, mostly along the normal (a flat plate's
# pressure drag, C ≈ 1.2) and a little along the surface (skin friction). The drag is applied
# implicitly per vertex (the normal speed shrinks by 1 / (1 + k dt)), so it never reverses a
# velocity however large the step. Lumi, s127: added for paper letters falling on the island.

"""
    SheetAir(; density = 1.2, normal = 1.2, tangential = 0.02, wind = Vec3f(0))

Air for `air!`: `density` (kg/m³), the drag coefficients across the sheet (`normal`) and along it
(`tangential`), and the wind velocity (m/s).
"""
Base.@kwdef struct SheetAir
    density::Float32 = 1.2f0
    normal::Float32 = 1.2f0
    tangential::Float32 = 0.02f0
    wind::Vec3f = Vec3f(0)
end

function air_drag!(v, x, tris, vtri_start, vtri, mass, fixed, wind::Vec3f, ρn::Float32, ρt::Float32, dt::Float32, one)
    i = KI.get_global_id(Int32).x
    i <= length(v) || return nothing
    @inbounds begin
        fixed[i] != 0 && return nothing
        an = zero(Vec3f)
        for k in vtri_start[i]:(vtri_start[i + 1] - 1)
            t = tris[vtri[k]]
            a = approximate(x[t[1]]); b = approximate(x[t[2]]); c = approximate(x[t[3]])
            an += cross(b - a, c - a) / 6.0f0          # a third of the triangle's area, along its normal
        end
        A = norm(an)
        (A > 0 && mass[i] > 0) || return nothing
        n = an / A
        u = approximate(v[i]) - wind
        un = dot(u, n)
        ut = u - un * n
        kn = 0.5f0 * ρn * A * abs(un) / mass[i]
        kt = 0.5f0 * ρt * A * norm(ut) / mass[i]
        dv = -(un - un / (1.0f0 + kn * dt)) * n - (ut - ut / (1.0f0 + kt * dt))
        v[i] = moved(v[i], dv, one[1])
    end
    return nothing
end

"""
    air!(target, solver::SheetSolver, state, dt, air::SheetAir)

Slows every free sheet vertex by the air over one step of `dt`: call it before `step!`.
"""
function air!(target, s::SheetSolver, state::State, dt, air::SheetAir)
    m = s.model
    launch!(target, air_drag!, (state.v, state.x, m.tris, m.vtri_start, m.vtri, m.mass, m.fixed, air.wind,
        air.density * air.normal, air.density * air.tangential, Float32(dt), m.one), s.n)
    return nothing
end
