# Circuits from what touches what (s155, big goal "From beach stones to an electric cart", road step 1).
# Nothing here is a netlist someone typed. The parts are wires (polylines of real metal with a radius, bare or wrapped)
# and cells (two terminals, an EMF and an internal resistance). Every solve:
#   - contact: wherever two bare wires come within the sum of their radii (anywhere along them, a wire with itself
#     too: a bare coil whose turns touch shorts its own turns), wherever a terminal touches a wire, wherever two
#     terminals touch, there is a node on each and a contact between them; its resistance is Holm's constriction
#     (rho1 + rho2) / 4a with the contact spot a = sqrt(F / pi H) from the pressing force and the softer metal's hardness;
#   - resistance: each wire between two of its nodes is rho(T) l / A summed over its segments, each at its own
#     temperature; a segment that has melted through is open;
#   - Kirchhoff: nodal analysis, cells as their Norton equivalents, each piece of the network that hangs together
#     gets its own reference node (a loose wire just floats);
#   - heat: I^2 R into each segment; out by natural convection (Morgan's correlation for a horizontal cylinder in
#     air, air properties at the film temperature), by radiation, and along the wire by conduction; at the melting
#     point the latent heat goes in first, then the segment parts.
# Checked (selftest): Ohm's law and parallel wires by hand; a bare wire laid across two leads shorts them, a wrapped one
# does not; the steady fusing current of copper wire in still air against Preece's measurements (I = 10244 d^1.5, d in
# inches): 0.25 mm 10.2 A vs 10.0, 1 mm within ~20%; and a thin wire on good cells glows and melts, on brine cells it
# barely warms. Looked first (rule 6): RomeoDB's circuit packages (ModelingToolkitStandardLibrary Electrical, ACME,
# Cadnip, JosephsonCircuits) compile a fixed netlist; here the netlist changes every frame (a brush slides off a segment,
# a wire melts, two wires cross), so it is rebuilt from the geometry each solve, a few dozen nodes, a dense solve.
module Circuit
using LinearAlgebra

const V3 = NTuple{3,Float64}
const SIGMA = 5.670374e-8
const T_AMB = 293.15
const G0 = 9.81

"""
Metals: resistivity at 20 C (Ohm m) and its temperature coefficient (1/K, linear: copper is within ~10% of the tables
up to its melting point, iron runs higher above 800 K), density, specific heat (J/kg K), melting point (K), latent heat
(J/kg), hardness (Pa, sets the contact spot), emissivity (tarnished, as a hot wire soon is), thermal conductivity.
"""
const METALS = Dict(
    :copper => (; rho = 1.68e-8, alpha = 3.93e-3, dens = 8960.0, c = 385.0, Tm = 1358.0, Lf = 2.05e5, H = 0.4e9, eps = 0.5, k = 400.0),
    :iron   => (; rho = 9.7e-8,  alpha = 6.5e-3,  dens = 7870.0, c = 449.0, Tm = 1811.0, Lf = 2.47e5, H = 1.0e9, eps = 0.7, k = 80.0),
)

rho_at(m, T) = m.rho * (1 + m.alpha * (T - 293.15))

"A wire: polyline (m), radius, metal, wrapped or bare; each segment's temperature and molten fraction (1: parted)."
mutable struct Wire
    p::Vector{V3}
    r::Vector{Float64}       # radius of each segment (a drawn wire is not even)
    metal::Symbol
    insulated::Bool          # wrapped: touches things only at its two bare ends
    T::Vector{Float64}
    melt::Vector{Float64}
end
function Wire(p; r = 0.25e-3, metal = :copper, insulated = false)
    q = V3[]
    for x in p    # a point on top of the last one is no segment
        (isempty(q) || norm(x .- q[end]) > 1e-9) && push!(q, x)
    end
    length(q) >= 2 || error("a wire needs two distinct points")
    rv = r isa Number ? fill(Float64(r), length(q) - 1) : (length(r) == length(q) - 1 ? collect(Float64, r) :
        error("one radius per segment: $(length(q) - 1), got $(length(r))"))
    Wire(q, rv, metal, insulated, fill(T_AMB, length(q) - 1), zeros(length(q) - 1))
end

"A straight wire from a to b in segments of at most ds."
function straight(a, b; ds = 2e-3, kw...)
    n = max(1, ceil(Int, norm(b .- a) / ds))
    Wire([a .+ (b .- a) .* (i / n) for i in 0:n]; kw...)
end

"A cell: its two terminals (points, touching within r_term), EMF (V) and internal resistance (Ohm)."
struct Cell
    plus::V3
    minus::V3
    emf::Float64
    R::Float64
    r_term::Float64
end
Cell(plus, minus; emf = 0.75, R = 3.0, r_term = 5e-3) = Cell(plus, minus, emf, R, r_term)

"Everything on the bench. `F` is the force pressing touching parts together (N; a wire twisted on by hand ~1 N)."
Base.@kwdef mutable struct Net
    wires::Vector{Wire} = Wire[]
    cells::Vector{Cell} = Cell[]
    F::Float64 = 1.0
    R_film::Float64 = 0.0    # tarnish on every contact (Ohm), on top of the constriction
    Ta::Float64 = T_AMB
end

seglen(w::Wire, i) = norm(w.p[i+1] .- w.p[i])
area(w::Wire, i) = pi * w.r[i]^2
parted(w::Wire, i) = w.melt[i] >= 1.0

"Closest points of segments p1-q1 and p2-q2: (s, t, distance) with s, t in [0, 1]."
function seg_seg(p1, q1, p2, q2)
    d1 = q1 .- p1; d2 = q2 .- p2; r = p1 .- p2
    a = dot(d1, d1); e = dot(d2, d2); f = dot(d2, r)
    c = dot(d1, r); b = dot(d1, d2); den = a * e - b * b
    s = den > 1e-30 ? clamp((b * f - c * e) / den, 0.0, 1.0) : 0.0
    t = e > 1e-30 ? (b * s + f) / e : 0.0
    if t < 0
        t = 0.0; s = a > 1e-30 ? clamp(-c / a, 0.0, 1.0) : 0.0
    elseif t > 1
        t = 1.0; s = a > 1e-30 ? clamp((b - c) / a, 0.0, 1.0) : 0.0
    end
    s, t, norm((p1 .+ s .* d1) .- (p2 .+ t .* d2))
end

"Closest point of segment p-q to x: (t, distance)."
function seg_pt(p, q, x)
    d = q .- p; L2 = dot(d, d)
    t = L2 > 1e-30 ? clamp(dot(x .- p, d) / L2, 0.0, 1.0) : 0.0
    t, norm(p .+ t .* d .- x)
end

# The places of a wire that can touch: every segment if bare, only the two end points if wrapped.
touch_segs(w::Wire) = w.insulated ? Int[] : [i for i in eachindex(w.T) if !parted(w, i)]
ends(w::Wire) = ((1, 0.0, w.p[1]), (length(w.T), 1.0, w.p[end]))

holm(m1, m2, F) = (m1.rho + m2.rho) / (4 * sqrt(F / (pi * min(m1.H, m2.H))))

"""
The network the geometry makes. Nodes: taps on wires (arc position) and cell terminals. Returns
(; nnodes, res = [(n1, n2, R, kind, data)], cells = [(n+, n-, emf, R)], taps), kind :wire (data = (wire, s1, s2)) or :contact.
"""
function netlist(net::Net; tol = 1e-5)
    W = net.wires
    taps = [Tuple{Float64,Int}[] for _ in W]      # (arc position, node) per wire
    arc = [vcat(0.0, cumsum([seglen(w, i) for i in eachindex(w.T)])) for w in W]
    nn = Ref(0)
    newnode() = (nn[] += 1)
    tap!(k, i, f) = (s = arc[k][i] + f * (arc[k][i+1] - arc[k][i]); n = newnode(); push!(taps[k], (s, n)); n)
    res = Tuple{Int,Int,Float64,Symbol,Any}[]
    cu = METALS[:copper]
    # wire ends always are nodes
    for k in eachindex(W)
        tap!(k, 1, 0.0); tap!(k, length(W[k].T), 1.0)
    end
    # data: the two wire segments it joins for the heat through the spot ((k, i); k = 0: a cell terminal, a cool sink)
    contact!(n1, n2, m1, m2, a = (0, 0), b = (0, 0)) =
        push!(res, (n1, n2, holm(m1, m2, net.F) + net.R_film, :contact, (a, b, m1, m2)))
    # wire against wire (and against itself, segments not neighbours)
    for k1 in eachindex(W), k2 in k1:length(W)
        w1, w2 = W[k1], W[k2]
        m1, m2 = METALS[w1.metal], METALS[w2.metal]
        lim = maximum(w1.r) + maximum(w2.r) + tol
        if !w1.insulated && !w2.insulated
            for i in touch_segs(w1), j in touch_segs(w2)
                k1 == k2 && abs(i - j) <= 1 && continue
                s, t, d = seg_seg(w1.p[i], w1.p[i+1], w2.p[j], w2.p[j+1])
                d <= w1.r[i] + w2.r[j] + tol || continue
                # one contact per touching spot: skip the shared end of a segment the neighbour already counted
                (s == 0.0 && i > 1) && continue
                (t == 0.0 && j > 1) && continue
                contact!(tap!(k1, i, s), tap!(k2, j, t), m1, m2, (k1, i), (k2, j))
            end
        else
            # a wrapped wire's bare ends against the other wire (its segments if bare, its ends if wrapped)
            for (a, b, ma, mb) in ((w1, w2, m1, m2), (w2, w1, m2, m1)), (i, f, x) in ends(a)
                ka, kb = a === w1 ? (k1, k2) : (k2, k1)
                ka == kb && continue
                if b.insulated
                    for (j, g, y) in ends(b)
                        norm(x .- y) <= lim && contact!(tap!(ka, i, f), tap!(kb, j, g), ma, mb, (ka, i), (kb, j))
                    end
                    a === w2 && break     # ends against ends: once
                else
                    for j in touch_segs(b)
                        t, d = seg_pt(b.p[j], b.p[j+1], x)
                        d <= lim && contact!(tap!(ka, i, f), tap!(kb, j, t), ma, mb, (ka, i), (kb, j))
                    end
                end
            end
        end
    end
    # cell terminals
    cells = Tuple{Int,Int,Float64,Float64}[]
    term = Tuple{V3,Float64,Int}[]
    for c in net.cells
        np, nm = newnode(), newnode()
        push!(cells, (np, nm, c.emf, c.R))
        push!(term, (c.plus, c.r_term, np), (c.minus, c.r_term, nm))
    end
    for (x, rt, n) in term, k in eachindex(W)
        w = W[k]
        segs = w.insulated ? [(i, f, p) for (i, f, p) in ends(w)] : [(i, 0.0, x) for i in touch_segs(w)]
        for (i, f, _) in segs
            t, d = w.insulated ? (f, norm(w.p[f == 0 ? i : i + 1] .- x)) : seg_pt(w.p[i], w.p[i+1], x)
            d <= rt + w.r[i] + tol || continue
            (t == 0.0 && i > 1 && !w.insulated) && continue
            contact!(n, tap!(k, i, t), cu, METALS[w.metal], (0, 0), (k, i))
        end
    end
    for a in eachindex(term), b in a+1:length(term)
        (xa, ra, na), (xb, rb, nb) = term[a], term[b]
        # a cell's own two terminals are not a contact
        any(c -> c[1] == na && c[2] == nb, cells) && continue
        norm(xa .- xb) <= ra + rb + tol && contact!(na, nb, cu, cu)
    end
    # each wire between consecutive taps: merge taps at the same spot, then resistors over the segments between
    for k in eachindex(W)
        w = W[k]; m = METALS[w.metal]
        sort!(taps[k]; by = first)
        tk = taps[k]
        for q in 1:length(tk)-1
            (s1, n1), (s2, n2) = tk[q], tk[q+1]
            R, open = wire_R(w, arc[k], s1, s2, m)
            open && continue
            push!(res, (n1, n2, max(R, 1e-9), :wire, (k, s1, s2)))
        end
    end
    (; nnodes = nn[], res, cells, taps)
end

"Resistance of wire w between arc positions s1 < s2 (each segment at its temperature), and whether it is parted there."
function wire_R(w::Wire, arc, s1, s2, m)
    R = 0.0
    for i in eachindex(w.T)
        l = min(arc[i+1], s2) - max(arc[i], s1)
        l > 0 || continue
        parted(w, i) && return (0.0, true)
        R += rho_at(m, w.T[i]) * l / area(w, i)
    end
    R, false
end

"Solve the network: node voltages, the current in every resistor (n1 -> n2) and every cell (out of +)."
function solve(nl)
    N = nl.nnodes
    parent = collect(1:N)
    find(i) = (while parent[i] != i; parent[i] = parent[parent[i]]; i = parent[i]; end; i)
    join!(a, b) = (parent[find(a)] = find(b))
    G = zeros(N, N); b = zeros(N)
    for (n1, n2, R, _, _) in nl.res
        g = 1 / R
        G[n1, n1] += g; G[n2, n2] += g; G[n1, n2] -= g; G[n2, n1] -= g
        join!(n1, n2)
    end
    for (np, nm, E, R) in nl.cells
        g = 1 / R
        G[np, np] += g; G[nm, nm] += g; G[np, nm] -= g; G[nm, np] -= g
        b[np] += E * g; b[nm] -= E * g
        join!(np, nm)
    end
    seen = Set{Int}()
    for i in 1:N
        r = find(i)
        r in seen && continue
        push!(seen, r)
        G[i, :] .= 0; G[i, i] = 1; b[i] = 0          # first node of each piece: the reference
    end
    V = G \ b
    I_res = [(V[n1] - V[n2]) / R for (n1, n2, R, _, _) in nl.res]
    I_cell = [(E - (V[np] - V[nm])) / R for (np, nm, E, R) in nl.cells]
    (; V, I_res, I_cell)
end

"Joule power (W) into every segment of every wire, and the contacts' heat (W), from a solution."
function joule(net::Net, nl, sol)
    P = [zeros(length(w.T)) for w in net.wires]
    Pc = 0.0
    for (q, (n1, n2, R, kind, data)) in enumerate(nl.res)
        I = sol.I_res[q]
        if kind === :contact
            Pc += I^2 * R
            continue
        end
        k, s1, s2 = data
        w = net.wires[k]; m = METALS[w.metal]
        a = 0.0
        for i in eachindex(w.T)
            l0 = seglen(w, i)
            l = min(a + l0, s2) - max(a, s1)
            l > 0 && (P[k][i] += I^2 * rho_at(m, w.T[i]) * l / area(w, i))
            a += l0
        end
    end
    P, Pc
end

"Natural convection off a horizontal wire of diameter d at T in air at Ta (Morgan 1975; air at the film temperature)."
function h_air(T, d; Ta = T_AMB)
    dT = max(T - Ta, 1e-6)
    Tf = (T + Ta) / 2
    k = 0.0241 * (Tf / 273.15)^0.81
    nu = 1.33e-5 * (Tf / 273.15)^1.75
    Ra = G0 / Tf * dT * d^3 * 0.71 / nu^2
    C, n = Ra < 1e-2 ? (0.675, 0.058) : Ra < 1e2 ? (1.02, 0.148) : Ra < 1e4 ? (0.850, 0.188) :
           Ra < 1e7 ? (0.480, 0.250) : (0.125, 0.333)
    C * Ra^n * k / d
end

"Heat lost per metre of wire (W/m) at T: convection + radiation."
q_loss(m, r, T; Ta = T_AMB) = (h_air(T, 2r; Ta) * (T - Ta) + m.eps * SIGMA * (T^4 - Ta^4)) * 2pi * r

"""
One step of dt: solve, heat, cool, conduct along the wires, melt. Re-solves in substeps short enough for the
conduction along the wire. Returns the last solution (with the network) for reading currents.
"""
function step!(net::Net, dt)
    ds_min = minimum((minimum(seglen(w, i) for i in eachindex(w.T)) for w in net.wires); init = 1.0)
    km = maximum((METALS[w.metal].k / (METALS[w.metal].dens * METALS[w.metal].c) for w in net.wires); init = 1e-4)
    nsub = max(1, ceil(Int, dt / (0.4 * ds_min^2 / km)))
    h = dt / nsub
    nl = netlist(net); sol = solve(nl)
    for sub in 1:nsub
        sub > 1 && (nl = netlist(net); sol = solve(nl))
        P, _ = joule(net, nl, sol)
        for (k, w) in enumerate(net.wires)
            m = METALS[w.metal]; n = length(w.T)
            Tn = copy(w.T); newmelt = copy(w.melt)
            for i in 1:n
                l = seglen(w, i)
                A = area(w, i)
                C = m.dens * m.c * A * l
                q = P[k][i] - q_loss(m, w.r[i], w.T[i]; Ta = net.Ta) * l
                # conduction to the neighbours (not across a parted segment); ends are left alone (adiabatic)
                for j in (i - 1, i + 1)
                    1 <= j <= n || continue
                    (parted(w, i) || parted(w, j)) && continue
                    q += m.k * min(A, area(w, j)) * (w.T[j] - w.T[i]) / ((l + seglen(w, j)) / 2)
                end
                if w.melt[i] < 1 && ((w.T[i] >= m.Tm && q > 0) || (w.melt[i] > 0 && q < 0))
                    # at the melting point the heat goes into melting (or, cooling, comes back out as it freezes)
                    Tn[i] = m.Tm
                    newmelt[i] = clamp(w.melt[i] + q * h / (m.Lf * m.dens * A * l), 0.0, 1.0)
                else
                    Tn[i] = w.T[i] + q * h / C
                end
            end
            # the first spot through parts and stops the current for the rest: one per substep (the most molten,
            # a tie going to the one nearest the middle, where the ends' cooling reaches least)
            done = [i for i in 1:n if w.melt[i] < 1 && newmelt[i] >= 1]
            if !isempty(done)
                p = argmax(i -> (newmelt[i], -abs(i - (n + 1) / 2)), done)
                for i in done
                    i == p || (newmelt[i] = prevfloat(1.0))
                end
            end
            for i in 1:n
                w.melt[i] < 1 && (w.melt[i] = newmelt[i])
            end
            w.T .= Tn
        end
        contact_heat!(net, nl, h)
    end
    (; nl, sol)
end

"""
Heat through every contact spot: the same constriction as the current, thermal resistance 1/(4 a k) on each side
(Holm). A cell terminal is a big cool lump (held at Ta). Applied as the exact relaxation of each pair over h, because a
thin wire's segment empties through a spot in a few ms, faster than the step.
"""
function contact_heat!(net::Net, nl, h)
    for (n1, n2, R, kind, data) in nl.res
        kind === :contact || continue
        (a, b, m1, m2) = data
        spot = sqrt(net.F / (pi * min(m1.H, m2.H)))
        G = 1 / (1 / (4 * spot * m1.k) + 1 / (4 * spot * m2.k))
        side(s) = s[1] == 0 ? (nothing, 0, Inf) : (w = net.wires[s[1]]; m = METALS[w.metal];
            (w, s[2], m.dens * m.c * area(w, s[2]) * seglen(w, s[2])))
        (wa, ia, Ca), (wb, ib, Cb) = side(a), side(b)
        wa === nothing && wb === nothing && continue
        Ta_ = wa === nothing ? net.Ta : wa.T[ia]
        Tb_ = wb === nothing ? net.Ta : wb.T[ib]
        # the two relax toward their heat-weighted mean
        Tm = isinf(Ca) ? Ta_ : isinf(Cb) ? Tb_ : (Ca * Ta_ + Cb * Tb_) / (Ca + Cb)
        f = exp(-G * h * (1 / Ca + 1 / Cb))
        wa === nothing || (wa.T[ia] = Tm + (Ta_ - Tm) * f)
        wb === nothing || (wb.T[ib] = Tm + (Tb_ - Tm) * f)
    end
end

"Steady fusing current of a long straight wire in still air: the current whose heat balances the losses at the melting point."
function fusing_current(r; metal = :copper, Ta = T_AMB)
    m = METALS[metal]
    sqrt(q_loss(m, r, m.Tm; Ta) * pi * r^2 / rho_at(m, m.Tm))
end

"Preece (1884), wires in air: I = a d^1.5, d in inches; a = 10244 for copper, 3148 for iron."
preece(d; metal = :copper) = (metal === :copper ? 10244 : 3148) * (d / 0.0254)^1.5

# ---------------------------------------------------------------------------------------------------- checks

"A cell standing upright on the bench at x: + on top, - at its foot (terminals 1 cm apart)."
upright(x; kw...) = Cell((x, 0.0, 0.01), (x, 0.0, 0.0); kw...)

function selftest(; verbose = true)
    out = Dict{String,Any}()
    say(s) = verbose && println(s)
    # 1. Ohm: one cell, a 1 m wire from + to - (the wire's ends on the terminals)
    c = Cell((0.0, 0.0, 0.0), (0.1, 0.0, 0.0); emf = 1.5, R = 0.5)
    w = Wire([(0.0, 0.0, 0.0), (0.0, 0.3, 0.0), (0.05, 0.6, 0.0), (0.1, 0.3, 0.0), (0.1, 0.0, 0.0)]; r = 0.25e-3)
    L = sum(seglen(w, i) for i in eachindex(w.T))
    Rw = 1.68e-8 * L / (pi * 0.25e-3^2)
    net = Net(wires = [w], cells = [c])
    sol = solve(netlist(net))
    Rc = 2 * holm(METALS[:copper], METALS[:copper], 1.0)
    out["ohm"] = (sol.I_cell[1], 1.5 / (0.5 + Rw + Rc))
    say("Ohm: I = $(round(sol.I_cell[1]; sigdigits = 6)) A, by hand $(round(1.5 / (0.5 + Rw + Rc); sigdigits = 6)) A (wire $(round(Rw; sigdigits = 3)) Ohm)")
    # 2. a second, identical wire alongside (not touching the first): the current through the load halves its R
    w2 = Wire([(0.0, 0.0, 0.0), (0.0, -0.3, 0.0), (0.05, -0.6, 0.0), (0.1, -0.3, 0.0), (0.1, 0.0, 0.0)]; r = 0.25e-3)
    sol2 = solve(netlist(Net(wires = [w, w2], cells = [c])))
    out["parallel"] = (sol2.I_cell[1], 1.5 / (0.5 + Rw / 2 + Rc / 2))
    say("Parallel: I = $(round(sol2.I_cell[1]; sigdigits = 6)) A, by hand $(round(1.5 / (0.5 + Rw / 2 + Rc / 2); sigdigits = 6)) A")
    # 3. a bare wire laid across the two leads near the cell shorts the loop; a wrapped one does not
    across(ins) = Wire([(-0.01, 0.1, 0.0005), (0.0333, 0.1, 0.0005), (0.0667, 0.1, 0.0005), (0.11, 0.1, 0.0005)]; r = 0.25e-3, insulated = ins)
    for ins in (false, true)
        nl = netlist(Net(wires = [w, across(ins)], cells = [c])); s = solve(nl)
        # current through the far part of the loop (the tip of the wire, arc position L/2)
        far = [abs(s.I_res[q]) for (q, r) in enumerate(nl.res) if r[4] === :wire && r[5][1] == 1 && r[5][2] < L / 2 < r[5][3]]
        out[ins ? "wrapped_across" : "bare_across"] = (s.I_cell[1], far[1])
        say((ins ? "Wrapped" : "Bare") * " wire across the leads: cell $(round(s.I_cell[1]; sigdigits = 4)) A, through the far loop $(round(far[1]; sigdigits = 3)) A")
    end
    # 4. fusing currents vs Preece
    for d in (0.1e-3, 0.25e-3, 0.5e-3, 1e-3)
        I, Ip = fusing_current(d / 2), preece(d)
        out["fuse_$(d * 1e3)mm"] = (I, Ip)
        say("Fusing, copper $(d * 1e3) mm: $(round(I; digits = 1)) A (Preece $(round(Ip; digits = 1)) A)")
    end
    # 5. a 0.1 mm copper wire, 5 cm, on six cells in a row: good cells (0.2 Ohm: big plates close together) vs brine cells (3 Ohm)
    for (name, Rcell) in (("good cells", 0.2), ("brine cells", 3.0))
        cells = [Cell((0.02 * (i - 1) + 0.012, 0.0, 0.0), (0.02 * (i - 1), 0.0, 0.0); emf = 0.75, R = Rcell, r_term = 4e-3) for i in 1:6]
        # cell i's + at x = 0.02(i-1) + 0.012, cell i+1's - at 0.02i: 8 mm apart, touching (r_term 4 mm each)
        lead1 = straight((0.0, 0.0, 0.0), (0.0, 0.05, 0.0); ds = 5e-3, r = 0.5e-3)
        lead2 = straight((0.112, 0.0, 0.0), (0.112, 0.05, 0.0); ds = 5e-3, r = 0.5e-3)
        thin = straight((0.0, 0.05, 0.0), (0.112, 0.05, 0.0); ds = 2e-3, r = 0.05e-3)
        net = Net(wires = [lead1, lead2, thin], cells = cells)
        Tmax = T_AMB; t_glow = NaN; t_melt = NaN; I0 = NaN
        for n in 1:2000
            st = step!(net, 0.01)
            n == 1 && (I0 = st.sol.I_cell[1])
            Tmax = max(Tmax, maximum(thin.T))
            isnan(t_glow) && maximum(thin.T) > 798 && (t_glow = n * 0.01)
            if any(>=(1.0), thin.melt)
                t_melt = n * 0.01; break
            end
        end
        out[name] = (; I0, Tmax, t_glow, t_melt)
        say("0.1 mm wire on six $name: $(round(I0; sigdigits = 3)) A, hottest $(round(Int, Tmax - 273.15)) C, glows (Draper, 525 C) at $(t_glow) s, melts through at $(t_melt) s")
    end
    out
end

end # module
