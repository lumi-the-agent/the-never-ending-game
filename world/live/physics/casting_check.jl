# Checks for physics/casting.jl (s170): include("physics/casting_check.jl"); casting_check()
# A plate mould poured full gives a plate of the pit's shape (minus lead's 6% freezing shrinkage), freezing in about a
# minute; lead on flat sand stands as a puddle a few mm thick (its surface tension); in a thin channel it runs a
# limited way and freezes (a misrun), farther when hotter, deeper, or on dry sand (which takes heat slower).
include(joinpath(@__DIR__, "casting.jl"))

function casting_check()
    dx = 0.01
    g1 = zeros(40, 30); g1[15:26, 13:18] .= -0.01
    p1 = Casting.pour!(Casting.Pour(g1, dx); src = (20, 15), volume = 72e-6, rate = 30e-6)
    c1 = Casting.casting(p1); pit = 1000 .* p1.ds[15:26, 13:18]
    @assert abs(c1.cm3 - 72 * Casting.LEAD.rho_l / Casting.LEAD.rho_s) < 0.5 "lead lost or made: $(c1.cm3) cm3"
    @assert minimum(pit) > 8.5 "the pit did not fill: $(extrema(pit)) mm"
    @assert 20 < c1.t_s < 150 "a 1 cm plate froze in $(c1.t_s) s"
    p2 = Casting.pour!(Casting.Pour(zeros(40, 40), dx); src = (20, 20), volume = 30e-6, rate = 30e-6)
    mean = 1000 * sum(p2.ds) / count(>(1e-5), p2.ds)
    @assert 2.5 < mean < 5.0 "a puddle on flat sand stands $(mean) mm thick"
    function channel(; depth = 0.004, Tpour = 400.0, sand = Casting.SANDS[:damp])
        gr = fill(0.03, 110, 7); gr[3:8, 2:6] .= -0.02; gr[9:110, 4] .= -depth
        p = Casting.pour!(Casting.Pour(gr, 0.01); src = (5, 4), volume = 100e-6, rate = 40e-6, Tpour, sand)
        something(findlast(>(1e-5), p.ds[9:110, 4]), 0)
    end
    base = channel(); hot = channel(Tpour = 450.0); deep = channel(depth = 0.008); dry = channel(sand = Casting.SANDS[:dry])
    @assert 10 < base < 60 "a 4 mm channel ran $(base) cm"
    @assert hot > base && deep > base && dry > base "fluidity: base $base, hot $hot, deep $deep, dry $dry"
    (; plate_cm3 = c1.cm3, plate_kg = c1.kg, plate_freeze_s = c1.t_s, puddle_mm = mean, run_cm = (; base, hot, deep, dry))
end
