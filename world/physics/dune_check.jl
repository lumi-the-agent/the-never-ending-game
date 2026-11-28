# s178, project dune: does the cart's motor charge the pots on a downhill, with nothing added? (It does.)
# The cartcord Sim as it is (Motor.step! through the six pots, oak cogs 6:1, belt 15 -> 40 mm), a 3 m cord's copper,
# no clip yank, the track tilted. Run: include this file, then DuneCheck.run().
module DuneCheck
include(joinpath(@__DIR__, "motor.jl"))
include(joinpath(@__DIR__, "rope.jl"))
include(joinpath(@__DIR__, "cartcord.jl"))
using Printf

function hill(slope; on = true, seconds = 40.0, every = 4.0)
    s = CartCord.Sim(; L_cord = 3.0, F_clip = 1e9, on, cart = CartCord.Cart(slope = slope),
                     belt = CartCord.Belt(r_p = 0.015, r_a = 0.04, gear = 6.0))
    s.cord.L = 60.0       # the copper is a 3 m cord's, the tether long enough never to go taut (no yank in this test)
    rows = NamedTuple[]; Q = 0.0; Qw = 0.0; tw = 0.0
    while s.t < seconds
        CartCord.step!(s, 1e-3); Q += s.st.I * 1e-3; Qw += s.st.I * 1e-3; tw += 1e-3
        if tw >= every - 5e-4
            push!(rows, (; t = s.t, x = s.cart.x, v = s.cart.v, rev_s = s.st.ω / 2pi, I = Qw / tw, Q))
            Qw = 0.0; tw = 0.0
        end
    end
    rows
end

function run()
    for (sl, on) in ((0.0, true), (-0.04, true), (-0.08, true), (-0.08, false))
        println("slope $sl, circuit ", on ? "to the pots" : "OPEN")
        for r in hill(sl; on, seconds = on ? 40.0 : 24.0)
            @printf("  t %4.1f  x %5.2f m  v %5.1f cm/s  %5.2f rev/s  I %+6.3f A  Q drawn %+6.2f C\n", r.t, r.x, 100r.v, r.rev_s, r.I, r.Q)
        end
    end
end
end
