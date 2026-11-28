# The wind over the dune, solved (s161, projects/wind.md): a 3D incompressible flow over a patch of ground in
# WaterLily.jl (GPU through KernelAbstractions), with the ground and every fence, rock, cart or friend as an
# immersed body given by its signed distance. Wakes, gaps, the lee eddy behind a fence (the reversed flow
# that drops sand there) all come out of the flow, nothing is painted. What the sand needs from it is the
# shear on the ground: the friction speed u* from the near-ground velocity by the law of the wall.
module GroundWind

using WaterLily, StaticArrays, LinearAlgebra

const KARMAN = 0.41

"Signed distance to an axis-aligned box with centre `c` and half sizes `h` (all in cells)."
@inline function box_sdf(x, c, h)
    q = abs.(x .- c) .- h
    norm(max.(q, 0)) + min(maximum(q), 0)
end

"""
A fence of horizontal boards across the wind (porosity from the gaps): base at x = `x0` (cells), centred at
`yc`, `width` and `height` in cells, boards `board` cells tall with `gap` between them, `thick` cells thick.
Returns a vector of boxes (centre, half sizes).
"""
function fence_boxes(x0, yc, ground; width, height, board = 2, gap = 1, thick = 1)
    boxes = Tuple{SVector{3,Float32},SVector{3,Float32}}[]
    z = ground + gap                      # the lowest gap lets a jet through under the fence, as real ones do
    while z + board <= ground + height + 1e-3
        push!(boxes, (SVector{3,Float32}(x0, yc, z + board / 2), SVector{3,Float32}(thick / 2, width / 2, board / 2)))
        z += board + gap
    end
    boxes
end

"""
A fence of upright slats across the wind: `slat` cells wide with `gap` between them (porosity gap/(slat+gap)),
from the ground up to `height`, `width` long, centred at `yc`, at x = `x0`.
"""
function slat_boxes(x0, yc, ground; width, height, slat = 1, gap = 1, thick = 1)
    boxes = Tuple{SVector{3,Float32},SVector{3,Float32}}[]
    y = yc - width / 2
    while y + slat <= yc + width / 2 + 1e-3
        push!(boxes, (SVector{3,Float32}(x0, y + slat / 2, ground + height / 2), SVector{3,Float32}(thick / 2, slat / 2, height / 2)))
        y += slat + gap
    end
    boxes
end

"""
    wind_sim(; n = (96, 48, 32), U = 1, ground = 3, boxes = [], Re = 5e3, mem = Array)

A wind tunnel over flat ground `ground` cells deep with `boxes` (centre, half sizes) standing on it; the wind
blows along +x at `U` (cells per unit time). `Re` is in fence heights when there are boxes.
"""
function wind_sim(; n = (96, 48, 32), U = 1f0, ground = 3f0, boxes = Tuple{SVector{3,Float32},SVector{3,Float32}}[],
                  L = 10f0, Re = 5f3, z0 = 0.05f0, mem = Array)
    bx = Tuple(boxes)                     # a tuple so the sdf closure is isbits on the GPU
    sdf(x, t) = begin
        d = x[3] - ground
        for (c, h) in bx
            d = min(d, box_sdf(x, c, h))
        end
        d
    end
    # the wind comes in as an atmospheric surface layer (log law over sand of roughness z0, U at the domain top),
    # not as a uniform slab: a uniform inlet makes its own separation where it first meets the no-slip ground
    zt = Float32(n[3]) - ground
    inlet(i, x, t) = i == 1 ? U * clamp(log(max(x[3] - ground, z0) / z0) / log(zt / z0), 0f0, 1f0) : 0f0
    Simulation(n, inlet, L; U, ν = U * L / Re, body = AutoBody(sdf), T = Float32, mem)
end

"""
The friction speed on the ground (in units of the free wind U) at every (x, y) cell, from the speed `k`
cells above the ground by the law of the wall with roughness `z0` (cells), and the sign of the near-ground
wind along x (negative in the lee eddy). Returns (ustar, ux) as CPU matrices.
"""
function ground_shear(sim; ground = 3, k = 2, z0 = 0.05f0)   # k = 2: the first cell is smeared by the immersed boundary
    u = Array(sim.flow.u)
    nx, ny = size(u, 1), size(u, 2)
    kz = Int(ground) + 1 + k              # +1 for WaterLily's ghost layer
    zr = Float32(k + 0.5)                 # height of that cell centre above the ground, cells
    us = zeros(Float32, nx, ny); ux = zeros(Float32, nx, ny)
    for j in 1:ny, i in 1:nx
        v = sqrt(u[i, j, kz, 1]^2 + u[i, j, kz, 2]^2)
        us[i, j] = KARMAN * v / log(zr / z0)
        ux[i, j] = u[i, j, kz, 1]
    end
    us ./ sim.U, ux ./ sim.U
end

"The near-ground wind direction (unit x, y components) `k` cells above the ground, as CPU matrices."
function ground_direction(sim; ground = 3, k = 2)
    u = Array(sim.flow.u); kz = Int(ground) + 1 + k
    ux = u[:, :, kz, 1]; uy = u[:, :, kz, 2]
    m = max.(sqrt.(ux .^ 2 .+ uy .^ 2), 1f-6)
    ux ./ m, uy ./ m
end

"""
Saltation flux (kg per metre per second) by Kawamura (1951): q = C (rho_air/g) (u* - u*t)(u* + u*t)^2 above the
threshold friction speed u*t, nothing below it. Fine dune sand: u*t about 0.25 m/s.
"""
kawamura(us; ust = 0.25f0, C = 2.78f0, rho_air = 1.2f0, g = 9.81f0) =
    us > ust ? C * rho_air / g * (us - ust) * (us + ust)^2 : 0f0

"""
The flux the grains really carry: saltating grains keep hopping after the wind slows, so the flux relaxes
towards the wind's capacity `qs` over a saturation length `ls` (m) along the wind (Sauermann, Kroy &
Herrmann 2001: e . grad q = (qs - q)/ls), instead of dropping to it at once. Solved to steady state by upwind
Jacobi sweeps. Where q > qs the sand settles: in a fence's wake it is carried in through the gaps first.
"""
function saturated_flux(qs, dirx, diry, dx_m; ls = 1f0, iters = 400)
    nx, ny = size(qs)
    q = copy(qs); qn = similar(q)
    for _ in 1:iters
        for j in 1:ny, i in 1:nx
            ex = dirx[i, j]; ey = diry[i, j]
            iu = clamp(ex > 0 ? i - 1 : i + 1, 1, nx); ju = clamp(ey > 0 ? j - 1 : j + 1, 1, ny)
            a = abs(ex) / dx_m; b = abs(ey) / dx_m
            qn[i, j] = (a * q[iu, j] + b * q[i, ju] + qs[i, j] / ls) / (a + b + 1 / ls)
        end
        q, qn = qn, q
    end
    q
end

"""
    blow!(h, us, dirx, diry, dx_m, dt; rho_bulk = 1600, ls = nothing, q = nothing)

Move sand on the heights `h` (m) for `dt` seconds: the flux (kawamura of the friction speed `us`, m/s; relaxed
over the saturation length `ls` when given; or `q` precomputed) goes along the near-ground wind (unit components
dirx, diry), and the surface changes by -div(q)/rho_bulk (Exner). Where the wind slows (a fence's wake, the lee
eddy, which blows back towards the fence) the flux drops and the sand it carried settles: that is the drift.
Cells are `dx_m` metres.
"""
function blow!(h, us, dirx, diry, dx_m, dt; rho_bulk = 1600f0, ls = nothing, q = nothing)
    nx, ny = size(h)
    qm = q !== nothing ? q : ls === nothing ? kawamura.(us) : saturated_flux(kawamura.(us), dirx, diry, dx_m; ls)
    qx = qm .* dirx
    qy = qm .* diry
    for j in 2:ny-1, i in 2:nx-1                      # upwind divergence: sand leaves a cell the way the wind goes
        fxe = qx[i, j] > 0 ? qx[i, j] : qx[i+1, j]; fxw = qx[i-1, j] > 0 ? qx[i-1, j] : qx[i, j]
        fyn = qy[i, j] > 0 ? qy[i, j] : qy[i, j+1]; fys = qy[i, j-1] > 0 ? qy[i, j-1] : qy[i, j]
        h[i, j] -= dt / rho_bulk * ((fxe - fxw) + (fyn - fys)) / dx_m
    end
    h
end

end
