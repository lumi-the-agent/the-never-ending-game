# A field coil wound by hand round an iron pole (s179, project fieldcoil). The winding is laid turn by turn, layer by
# layer, round a round core: its wire length, resistance and copper mass come from the turns themselves (the same turns
# the game draws), and the field it makes from the motor's own FEM (motor2d.jl Geo(field = true), its table in
# data/fieldcoil-torque.csv: drive torque at 80 armature A-turns against field A-turns per pole, iron saturating).
#   w = FieldCoil.winding(turns = 200); FieldCoil.stall(w)        # series-wound on the six clay pots
# Copper: rho 1.72e-8 Ohm m, 8960 kg/m^3. Pots: 6 x (0.78 V, 0.5 Ohm) in series; armature 80 turns, 2.03 Ohm (drummotor.jl).
module FieldCoil

const RHO = 1.72e-8
const DCU = 8960.0
const TABLE = joinpath(@__DIR__, "data", "fieldcoil-torque.csv")

"The FEM table: [(field A-turns per pole, drive torque N m at 80 armature A-turns)]."
function table(path = TABLE)
    rows = [split(l, ",") for l in eachline(path) if !startswith(l, "#") && !startswith(l, "NIf")]
    [(parse(Float64, r[1]), parse(Float64, r[2])) for r in rows]
end

"Drive torque (N m) for field `nif` A-turns per pole at 80 armature A-turns: linear between the solved points."
function drive(nif, tab = table())
    nif <= tab[1][1] && return tab[1][2]
    for i in 1:length(tab)-1
        (a, ta), (b, tb) = tab[i], tab[i+1]
        a <= nif <= b && return ta + (nif - a) / (b - a) * (tb - ta)
    end
    error("field $(nif) A-turns is past the solved table ($(tab[end][1])): solve further in motor2d.jl")
end

"""
Lay `turns` turns of round wire (diameter `d`, m) on a round core (radius `rc`) of winding length `len`: layer k holds
floor(len / d) turns at radius rc + (k - 1/2) d. Returns the layers [(radius, turns)], the wire length (m), the outer
radius, the copper mass (kg) and the resistance (Ohm) of ONE pole's coil.
"""
function winding(; turns = 200, d = 0.8e-3, rc = 0.026, len = 0.036)
    per = floor(Int, len / d)
    per >= 1 || error("wire $(d) m is wider than the winding length $(len) m")
    layers = Tuple{Float64,Int}[]
    left = turns; k = 0
    while left > 0
        k += 1
        n = min(per, left)
        push!(layers, (rc + (k - 0.5) * d, n))
        left -= n
    end
    wire = sum(2pi * r * n for (r, n) in layers)
    area = pi * d^2 / 4
    (; turns, d, rc, len, layers, wire, outer = rc + k * d, mass = wire * area * DCU, R = RHO * wire / area)
end

"""
The wire's own path, the way a hand winds it: layer 1 runs out along the core, layer 2 comes back over it, and so on,
each layer one wire diameter further out, `seg` points a turn. Local frame: the core's axis is +x from 0 to `len`,
(y, z) radial. One continuous polyline (the game draws it as one tube of radius d / 2), so the turns the player counts
are the turns in the physics.
"""
function path(w; seg = 24)
    pts = NTuple{3,Float64}[]
    for (k, (r, n)) in enumerate(w.layers)
        out = isodd(k)
        x0 = out ? w.d / 2 : w.len - w.d / 2
        dx = (out ? 1 : -1) * w.d / seg
        for i in 0:n*seg
            ph = 2pi * i / seg
            push!(pts, (x0 + i * dx, r * cos(ph), r * sin(ph)))
        end
    end
    pts
end

"""
Series-wound on the clay pots: the same current through both poles' coils and the armature. Stall torque (N m), the
current, the field A-turns per pole and the heat in the field coils. `pots` clay pots of 0.78 V and 0.5 Ohm in series.
"""
function stall(w; pots = 6, Ra = 2.03, tab = table())
    V = 0.78pots; Rp = 0.5pots
    I = V / (Rp + Ra + 2w.R)
    nif = w.turns * I
    (; I, nif, torque = drive(nif, tab) * I, heat_W = I^2 * 2w.R, copper_kg = 2w.mass)
end

end
