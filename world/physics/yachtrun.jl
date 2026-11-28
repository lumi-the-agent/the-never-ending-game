# The land yacht running on the beach (s165, project landyacht, idea 'Sail it yourself'): the live sail
# (SailFlow.live_sail, three solved 2D slices on the canvas arc joined by a lifting line) at the apparent wind, against
# the four towed wheels' rolling resistance in the sand (WheelSand.towed, Bekker-Wong). Along the heading only for
# now: no heel, no steering. Nothing here is a polar or a lookup: the sail force is whatever the flow gives at the
# angle the apparent wind and the sheet make, and the apparent wind swings forward as the cart speeds up, so a sheet
# set for the start is wrong once it runs.
module YachtRun
using LinearAlgebra
import ..SailFlow, ..WheelSand

const RHO = 1.2            # air, kg/m^3
const G = 9.81

"""
    run_yacht(; wind = 6.0, wind_from_deg = 90, sheet_deg = 20, sheet = nothing, mass = 95.0, area = 3.36,
              chord_m = 1.2, aspect = 4, r = 0.35, b = 0.10, soil = :dry_sand, t_end = 20.0, dt = 0.1)

The cart starts at rest heading along +x; the true wind blows from `wind_from_deg` off the bow (90: beam). The sail
sits `sheet_deg` off the centre line, to leeward (`sheet(t, beta_deg)` overrides it each step: the player's hand).
Returns a vector of named tuples per step: t, v, apparent speed and angle, angle of attack, CL, CD, drive, resistance.
"""
function run_yacht(; wind = 6.0, wind_from_deg = 90, sheet_deg = 20, sheet = nothing, mass = 95.0, area = 3.36,
                   chord_m = 1.2, aspect = 4, r = 0.35, b = 0.10, soil = :dry_sand, t_end = 20.0, dt = 0.1)
    s = WheelSand.SOILS[soil]
    roll = WheelSand.towed(s, mass * G / 4, r, b)
    R = 4 * roll.resistance                                   # rolling resistance, N (load does not change: no heel)
    wf = deg2rad(wind_from_deg)
    Wv = -wind * [cos(wf), sin(wf)]                           # true wind velocity (blowing towards)
    v = 0.0; t = 0.0
    beta0 = wf; ls = SailFlow.live_sail(beta0 - deg2rad(sheet_deg); aspect)
    out = NamedTuple[]
    while t < t_end
        Va = Wv - [v, 0.0]                                    # apparent wind: true wind minus the cart's own motion
        U = norm(Va)
        beta = atan(-Va[2], -Va[1])                           # where it comes from, off the bow
        sd = deg2rad(sheet === nothing ? sheet_deg : sheet(t, rad2deg(beta)))
        alpha = beta - sd                                     # angle of attack on the sail
        f = SailFlow.sail_force!(ls, alpha, U * dt / chord_m)
        q = 0.5 * RHO * U^2 * area
        drive = q * (f.CL * sin(beta) - f.CD * cos(beta))     # lift is square to the apparent wind, drag along it
        net = drive - (v > 1e-3 ? R : clamp(drive, 0.0, R))   # the sand holds it still until the sail beats it
        v = max(v + net / mass * dt, 0.0)
        t += dt
        push!(out, (; t, v, U, beta_deg = rad2deg(beta), alpha_deg = rad2deg(alpha), CL = f.CL, CD = f.CD, drive, R))
    end
    out
end

end
