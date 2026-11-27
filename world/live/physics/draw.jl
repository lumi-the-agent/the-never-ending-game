# Drawing copper wire through a stone plate (s155, project drawn-wire, big goal road step 9 with circuit.jl).
# A rod is a row of short segments, each with its radius, length and the plastic strain it has taken (work hardening).
# A pass pulls it, tip first, through a conical hole of the plate:
#   - the stress it takes is Sachs' (slab method, Coulomb friction mu on a die of half angle alpha):
#     sigma_d = sigma_m (1 + B)/B (1 - (A1/A0)^B), B = mu cot(alpha), sigma_m the mean flow stress over the pass;
#   - the copper hardens as it goes (Ludwik fit for annealed copper, the same law as wire.jl: 60 MPa + 320 MPa eps^0.45);
#   - the drawn wire past the hole must carry that pull: if sigma_d stays below its flow stress the pass is clean
#     (practical limit ~50% area per pass here); if not, the wire just out of the hole yields, its load capacity
#     sigma(eps) A e^-d passes its maximum (Considere) and it necks: the hand feels it give and stops (`give`, a
#     fraction of the load lost) and the neck stays in the wire; a hand that does not stop snaps it;
#   - the hole wears by the drawn length (Archard: depth rate k p / H, a sandstone plate wears fast, basalt hardly).
# The radii go into circuit.jl (one per segment), so a neck from a rushed pass is where that wire glows first and parts.
# Looked first (rule 6): RomeoDB has no wire-drawing model; metal forming packages are FEM frameworks, too heavy for a
# per-pass slab estimate that runs while the player pulls.
module Draw

const SY0 = 60e6       # Pa, annealed copper (as wire.jl)
const KH = 320e6
const NH = 0.45

flow(e) = SY0 + KH * max(e, 0.0)^NH
mean_flow(e0, e1) = (n = 16; sum(flow(e0 + (e1 - e0) * (k - 0.5) / n) for k in 1:n) / n)

"Sachs' drawing stress for a pass from strain e0 taking an area strain de, friction mu, die half angle alpha."
function sachs(e0, de; mu = 0.1, alpha = deg2rad(8))
    B = mu * cot(alpha)
    mean_flow(e0, e0 + de) * (1 + B) / B * (1 - exp(-B * de))
end

"Stone plates: hardness (Pa) and Archard's wear coefficient of copper sliding through it."
const STONES = Dict(:sandstone => (; H = 1.0e9, k = 1e-4), :basalt => (; H = 6.0e9, k = 1e-6))

"A rod: segment radii (m), lengths (m) and plastic strains."
mutable struct Rod
    r::Vector{Float64}
    l::Vector{Float64}
    e::Vector{Float64}
end
Rod(; d = 2e-3, L = 0.05, ds = 1e-3) = (n = round(Int, L / ds); Rod(fill(d / 2, n), fill(ds, n), zeros(n)))

"""
Pull the rod through a hole of radius `hole` (it wears as it goes). `give`: the fraction of the load the hand lets
the wire lose before stopping (`nothing`: it never stops, a neck snaps). Returns (; result, at, hole, sigma_d_max):
`from`: the segment the pull starts at (a rush partway along). result :clean, :necked (the pass stopped at segment `at`, a neck left there) or :snapped (rod parted at `at`).
"""
function pass!(rod::Rod, hole; mu = 0.1, alpha = deg2rad(8), stone = :sandstone, give = 0.02, from = 1)
    st = STONES[stone]
    sdmax = 0.0
    for i in from:length(rod.r)
        rod.r[i] <= hole && continue                # already thinner than the hole: slips through
        de = 2 * log(rod.r[i] / hole)
        sd = sachs(rod.e[i], de; mu, alpha)
        sdmax = max(sdmax, sd)
        e1 = rod.e[i] + de
        if sd < flow(e1)
            # clean: the segment comes out the hole's size, harder and longer (volume kept)
            rod.l[i] *= exp(de); rod.r[i] = hole; rod.e[i] = e1
            hole += st.k * mean_flow(rod.e[i] - de, e1) / st.H * rod.l[i]
            continue
        end
        # the pull is more than the drawn wire can carry: the segment just out of the hole yields and necks
        A1 = pi * hole^2
        F = sd * A1
        cap(d) = flow(e1 + d) * A1 * exp(-d)       # what the yielding segment can carry at extra strain d
        ds_ = range(0, 2.0; length = 4001)
        caps = cap.(ds_)
        kmax = argmax(caps)
        rod.l[i] *= exp(de); rod.e[i] = e1; rod.r[i] = hole
        if give === nothing      # a hand that keeps pulling: the neck runs to fracture
            rod.r[i] = 0.0
            return (; result = :snapped, at = i, hole, sigma_d_max = sdmax)
        end
        # past the maximum the load falls; the hand stops when it has fallen by `give`
        kstop = findfirst(k -> k > kmax && caps[k] <= (1 - give) * caps[kmax], eachindex(caps))
        kstop === nothing && (kstop = length(caps))
        d = ds_[kstop]
        rod.r[i] = hole * exp(-d / 2); rod.l[i] *= exp(d); rod.e[i] += d
        return (; result = :necked, at = i, hole, sigma_d_max = sdmax)
    end
    (; result = :clean, at = 0, hole, sigma_d_max = sdmax)
end

"The largest clean area reduction from strain e (bisection on sigma_d = flow at the exit)."
function limit_reduction(e; mu = 0.1, alpha = deg2rad(8))
    lo, hi = 0.0, 3.0
    for _ in 1:60
        mid = (lo + hi) / 2
        sachs(e, mid; mu, alpha) < flow(e + mid) ? (lo = mid) : (hi = mid)
    end
    1 - exp(-lo)
end

"Positions of the rod's segment ends laid out straight from a along unit direction u (for circuit.jl)."
function layout(rod::Rod, a, u)
    s = vcat(0.0, cumsum(rod.l))
    [a .+ u .* x for x in s]
end

end # module
