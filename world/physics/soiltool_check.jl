# Checks for physics/soiltool.jl (s171): include("physics/soiltool_check.jl"); soiltool_check()
# 1. A wide smooth vertical blade is Rankine's passive pressure exactly: ½γd²Kp w + 2cd√Kp w (classical, closed form).
# 2. A narrow stick pushes more soil per metre of width than a wide blade (the side crescents), but not more than a
#    laterally loaded pile in sand (Broms 1964: 3 Kp σv per unit width, from pile tests), and its force grows with
#    depth and with firmer sand.
include(joinpath(@__DIR__, "wheelsand.jl")); include(joinpath(@__DIR__, "soiltool.jl")); include(joinpath(@__DIR__, "sandwater.jl"))

const SAND_UNIT_WEIGHT = Dict(:dry_sand => 1600 * 9.81, :firm_sand => 1750 * 9.81)   # N/m3: loose dry / compacted

function soiltool_check()
    dry = WheelSand.SOILS[:dry_sand]; firm = WheelSand.SOILS[:firm_sand]
    γd = SAND_UNIT_WEIGHT[:dry_sand]; γf = SAND_UNIT_WEIGHT[:firm_sand]
    K = SoilTool.kp(dry.phi)
    # 1. Rankine: cohesionless, then with cohesion
    s0 = (; dry..., c = 0.0)
    d, w = 0.3, 10.0
    r0 = SoilTool.wedge(s0, γd, d, w; δ = 0.0, ρ = 0.0, nβ = 4000).H
    ran0 = 0.5γd * d^2 * K * w
    @assert abs(r0 - ran0) < 0.005ran0 "wide blade, c = 0: $(r0) vs Rankine $(ran0)"
    r1 = SoilTool.wedge(dry, γd, d, w; δ = 0.0, ρ = 0.0, nβ = 4000).H
    ran1 = ran0 + 2dry.c * d * sqrt(K) * w
    @assert abs(r1 - ran1) < 0.005ran1 "wide blade with cohesion: $(r1) vs Rankine $(ran1)"
    # 2. a 3 cm stick
    sw = 0.03
    rows = map((0.05, 0.10, 0.15, 0.20)) do d
        t = SoilTool.tine(dry, γd, d, sw); tf = SoilTool.tine(firm, γf, d, sw)
        wide = SoilTool.wedge(dry, γd, d, 1.0; ρ = 0.0).H * sw      # the same width as a slice of a wide blade
        broms = sw * (1.5K * γd * d^2 + 3 * 2dry.c * sqrt(K) * d)
        @assert wide < t.H <= broms * 1.0001 "stick at $(d) m: wide-slice $(wide) < $(t.H) <= Broms $(broms)"
        @assert tf.H > t.H "firm sand is not harder than dry at $(d) m"
        (; d_cm = 100d, dry_N = round(t.H, digits = 1), firm_N = round(tf.H, digits = 1),
           wide_slice_N = round(wide, digits = 1), broms_N = round(broms, digits = 1), dc_cm = round(100t.dc, digits = 1))
    end
    @assert issorted([r.dry_N for r in rows]) "deeper is not harder"
    # 3. damp sand (sandwater.jl): no apparent cohesion at the waterline (saturated) or high on the dune (drained), a
    #    peak in between; the stick is hardest in the damp band and softest in the buoyed swash
    beach = map((0.0, 0.05, 0.1, 0.2, 0.3, 0.5, 1.0, 2.0)) do h
        dm = SandWater.damp(dry, h)
        (; h, θ = round(dm.θ, digits = 3), c_app_Pa = round(dm.c_app), stick15_N = round(SoilTool.tine(dm.soil, dm.γ, 0.15, sw).H, digits = 1))
    end
    ca = [b.c_app_Pa for b in beach]; st = [b.stick15_N for b in beach]
    @assert ca[1] == 0 && ca[end] < 0.05maximum(ca) && 0.3e3 < maximum(ca) < 3e3 "apparent cohesion: $(ca)"
    @assert argmax(st) in 3:5 && st[1] < st[end] "the stick across the beach: $(st)"
    (; rankine = (c0 = (r0, ran0), c = (r1, ran1)), stick = rows, beach)
end
