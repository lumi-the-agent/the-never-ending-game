# Checks for physics/sandfield.jl (s160): run with include("physics/sandfield_check.jl"); sandfield_check()
# A towed cart wheel rolled across fresh dry sand must leave a rut with berms, lose exactly the compacted volume and
# stand no steeper than repose (+ a little for unfinished sweeps); a loaded wheel on a plank must tip it towards the load.
include(joinpath(@__DIR__, "wheelsand.jl")); include(joinpath(@__DIR__, "sandfield.jl"))

function sandfield_check(; backend = SandField.KA.CPU())
    s = WheelSand.SOILS[:dry_sand]
    tw = WheelSand.towed(s, 35 * 9.81 / 4, 0.2, 0.05)
    f = SandField.Field(200, 60, 0.01; backend)
    V0 = SandField.sand_volume(f)
    for xc in 0.3:0.01:1.7
        U = SandField.wheel_under(f, xc, 0.3, 0.2, 0.05, -tw.z)
        Ud = SandField.KA.allocate(backend, Float32, size(U)); copyto!(Ud, U)
        SandField.press!(f, Ud; bulb = 0.05); SandField.slump!(f, 8)
    end
    fill!(f.under, Inf32); SandField.slump!(f, 400)
    h = Array(f.h)
    lost = V0 - SandField.sand_volume(f); comp = sum(Array(f.comp)) * f.dx^2
    rut = minimum(h[100, :]); berm = maximum(h[100, :]); slope = SandField.max_slope(f)
    @assert abs(lost - comp) < 1e-3 * comp "sand not conserved: lost $lost, compacted $comp"
    @assert rut < -0.01 && berm > 0.003 "no rut/berm: $rut $berm"
    @assert slope < 36 "steeper than repose: $slope"
    g = SandField.Field(200, 60, 0.01)
    P = (; xc = 1.0, yc = 0.3, Lp = 1.0, bp = 0.2, m = 2.5)
    q = SandField.plank_rest(g, Array(g.h), P, [(0.75, 0.3, 1470.0)]; soil = s, bekker = WheelSand.bekker)
    @assert q.ok && q.pitch > 0.5 "plank did not tip towards the load: $(q.pitch)"
    (; rut_mm = 1000rut, berm_mm = 1000berm, slope, lost_cm3 = 1e6lost, plank_pitch = q.pitch)
end
