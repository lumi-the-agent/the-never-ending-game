# Knock on anything (s138, project knock-anything). Jumped in as Lumi, press L next to a placed thing (a stone lantern,
# the signpost, the basket, a toadstool, the cottage) and hear the note it really makes: its modes come from its own
# shape and material (physics/modes.jl: voxels -> FinEtools hex FEM -> Arpack, solved once per asset and cached in
# state/modes/<id>.jls). The knock excites each mode by its shape where Lumi's beak hits it, along the way Lumi faces;
# a bigger copy (scale) rings lower (f ~ 1/size). The page plays it as decaying sines, one per mode, plus the click.
using GeometryBasics, Makie, Serialization, LinearAlgebra, Bonito
isdefined(Main, :KNOCK) || Core.eval(Main, :(const KNOCK = Dict{Symbol,Any}()))
const NG = NeverendingGame
const KN = Main.KNOCK
const KN_REACH = 1.4f0      # metres from Lumi's front point to the thing's surface (its nearest FE node)

struct Knock <: System end

function kn_modes(game, id)
    cache = get!(() -> Dict{String,Any}(), KN, :modes)
    get!(cache, id) do
        f = joinpath(game.paths.world, "state", "modes", "$id.jls")
        isfile(f) ? deserialize(f) : nothing
    end
end

"The placed thing Lumi's beak is nearest to, with the FE node it hits (local frame) and the knock direction."
function kn_target(game, me)
    yaw = me.yaw + NG.species_of(me).heading
    fwd = Vec3f(cos(yaw), sin(yaw), 0)
    beak = Point3f(me.pos) + 0.35f0 * fwd + Point3f(0, 0, 0.7f0)
    best = nothing; bd = KN_REACH
    for a in game.world.actors
        a isa NG.AssetActor || continue
        hypot(a.pos[1] - beak[1], a.pos[2] - beak[2]) > 6 && continue
        m = kn_modes(game, a.asset)
        m === nothing && continue
        c, s = cos(-a.yaw), sin(-a.yaw)
        r = (beak - a.pos) / a.scale
        lp = (c * r[1] - s * r[2] - m.lo[1], s * r[1] + c * r[2] - m.lo[2], r[3])   # node frame: lo corner, base z = 0
        q = argmin([(m.xyz[i, 1] - lp[1])^2 + (m.xyz[i, 2] - lp[2])^2 + (m.xyz[i, 3] - lp[3])^2 for i in 1:size(m.xyz, 1)])
        d = a.scale * sqrt((m.xyz[q, 1] - lp[1])^2 + (m.xyz[q, 2] - lp[2])^2 + (m.xyz[q, 3] - lp[3])^2)
        d < bd || continue
        dir = (c * fwd[1] - s * fwd[2], s * fwd[1] + c * fwd[2], 0.0)
        best = (a, m, q, dir); bd = d
    end
    return best
end

"Per mode (Hz, amplitude, decay 1/s) of a knock at node q along dir, for a copy at `scale`."
function kn_partials(m, q, dir, scale; contact = 0.0006)
    out = Vector{Vector{Float64}}()
    for k in eachindex(m.freqs)
        f = m.freqs[k] / scale
        (20 <= f <= 12000) || continue
        a = abs(m.shapes[3q-2, k] * dir[1] + m.shapes[3q-1, k] * dir[2] + m.shapes[3q, k] * dir[3]) * abs(sinc(2f * contact))
        push!(out, [f, a, m.damping[k] / scale])
    end
    isempty(out) && return out
    amax = maximum(p -> p[2], out)
    for p in out; p[2] /= amax; end
    return out
end

function kn_play!(game, partials)
    game.dash === nothing && return
    haskey(game.plugins, "voice") || return
    for s in Base.invokelatest(game.plugins["voice"].mod.sessions!, game)
        Bonito.evaljs(s, Bonito.js"""
            const X = window.lumiXylo || (window.lumiXylo = {ctx: new (window.AudioContext || window.webkitAudioContext)(), n: 0});
            const ctx = X.ctx;
            if (ctx.state === 'suspended') { ctx.resume(); }
            if (ctx.state === 'running') {
                const t = ctx.currentTime + 0.03;
                const out = ctx.createGain(); out.gain.value = 0.22; out.connect(ctx.destination);
                // the click: 8 ms of noise, the contact itself
                const nb = ctx.createBuffer(1, Math.floor(ctx.sampleRate * 0.008), ctx.sampleRate), ch = nb.getChannelData(0);
                for (let i = 0; i < ch.length; i++) { ch[i] = (Math.random() * 2 - 1) * Math.exp(-i / (ch.length / 4)); }
                const nsrc = ctx.createBufferSource(); nsrc.buffer = nb; const ng = ctx.createGain(); ng.gain.value = 0.5;
                nsrc.connect(ng); ng.connect(out); nsrc.start(t);
                for (const [f, a, d] of $(partials)) {          // one decaying sine per mode of the thing
                    const o = ctx.createOscillator(), v = ctx.createGain();
                    o.type = 'sine'; o.frequency.value = f; o.connect(v); v.connect(out);
                    const len = Math.min(3.0, 4.6 / Math.max(d, 0.5));
                    v.gain.setValueAtTime(0.0001, t);
                    v.gain.exponentialRampToValueAtTime(Math.max(0.0002, 0.5 * a), t + 0.002);
                    v.gain.exponentialRampToValueAtTime(0.0001, t + len);
                    o.start(t); o.stop(t + len + 0.05);
                }
            }
        """)
    end
end


# ── The sway: while it rings, the knocked copy is hidden (scale 0) and a deformed copy of its mesh stands in, moving in
# its loudest mode, slowed so an eye can follow (true pitch is 100-1000 Hz) and exaggerated to 4 % of its height.
const KN_RING = 2.4         # seconds the sway lasts
"Per vertex of the asset's model, the FE node it follows (nearest node on the voxel grid), cached per asset."
function kn_follow(game, id, m)
    cache = get!(() -> Dict{String,Any}(), KN, :follow)
    get!(cache, id) do
        model = NG.lifted_asset(game.paths, id)
        h = minimum(filter(>(1e-6), abs.(diff(sort(unique(m.xyz[:, 1]))))))
        key(x, y, z) = (round(Int, x / h), round(Int, y / h), round(Int, z / h))
        grid = Dict(key(m.xyz[q, 1], m.xyz[q, 2], m.xyz[q, 3]) => q for q in 1:size(m.xyz, 1))
        vs = coordinates(model.mesh)
        nodes = Vector{Int}(undef, length(vs))
        for (i, p) in enumerate(vs)
            x, y, z = p[1] - m.lo[1], p[2] - m.lo[2], p[3]
            k = key(x, y, z)
            q = get(grid, k, 0)
            if q == 0
                q = argmin([(m.xyz[r, 1] - x)^2 + (m.xyz[r, 2] - y)^2 + (m.xyz[r, 3] - z)^2 for r in 1:size(m.xyz, 1)])
                grid[k] = q
            end
            nodes[i] = q
        end
        (; model, nodes)
    end
end

function kn_ring_start!(game, a, m, parts)
    kn_ring_end!(game)
    isempty(parts) && return
    f = kn_follow(game, a.asset, m)
    # the loudest audible mode, or the first mode for things too soft to sing
    k = 1; best = -1.0
    for j in eachindex(m.freqs)
        fj = m.freqs[j] / a.scale
        i = findfirst(p -> abs(p[1] - fj) < 1e-6, parts)
        i === nothing && continue
        parts[i][2] > best && (best = parts[i][2]; k = j)
    end
    φ = reshape(m.shapes[:, k], 3, :)
    φ = φ ./ maximum(sqrt.(sum(abs2, φ; dims = 1)))
    hgt = maximum(m.xyz[:, 3])
    c, s = cos(a.yaw), sin(a.yaw)
    sc = a.scale
    vs = coordinates(f.model.mesh)
    world(p) = Point3f(a.pos[1] + sc * (c * p[1] - s * p[2]), a.pos[2] + sc * (s * p[1] + c * p[2]), a.pos[3] + sc * p[3])
    rest = [world(p) for p in vs]
    U = [Vec3f(sc * (c * φ[1, q] - s * φ[2, q]), sc * (s * φ[1, q] + c * φ[2, q]), sc * φ[3, q]) * Float32(0.04 * hgt) for q in f.nodes]
    mk(pts) = GeometryBasics.Mesh(pts, faces(f.model.mesh); normal = [Vec3f(c * n[1] - s * n[2], s * n[1] + c * n[2], n[3]) for n in f.model.mesh.normal], uv = f.model.mesh.uv)
    obs = Observable(mk(rest))
    plot = mesh!(game.stage.scene, obs; color = f.model.color, material = f.model.material, name = :knock_sway)
    KN[:ring] = (; actor = a, scale = a.scale, plot, obs, rest, U, mk, t0 = time(), fvis = clamp(m.freqs[k] / a.scale / 100, 1.2, 3.5))
    # a snapshot taken while it rings would keep scale 0: note the real scale, `start!` puts it back after a restart
    write(kn_hidden_file(game), "$(a.asset) $(a.pos[1]) $(a.pos[2]) $(a.scale)")
    a.scale = 0f0
end

kn_hidden_file(game) = joinpath(game.paths.state, "knock-hidden.txt")

function NG.start!(::Knock, game)
    f = kn_hidden_file(game)
    isfile(f) || return
    id, x, y, sc = split(read(f, String))
    for a in game.world.actors
        a isa NG.AssetActor && a.asset == id && a.scale == 0 && hypot(a.pos[1] - parse(Float32, x), a.pos[2] - parse(Float32, y)) < 0.01 &&
            (a.scale = parse(Float32, sc))
    end
    rm(f)
    return
end

function kn_ring_step!(game)
    r = get(KN, :ring, nothing)
    r === nothing && return
    t = time() - r.t0
    t > KN_RING && return kn_ring_end!(game)
    amp = Float32(sin(2π * r.fvis * t) * exp(-1.6t))
    r.obs[] = r.mk(r.rest .+ amp .* r.U)
end

function kn_ring_end!(game)
    r = pop!(KN, :ring, nothing)
    r === nothing && return
    r.actor.scale = r.scale
    rm(kn_hidden_file(game); force = true)
    r.plot.parent === nothing || delete!(r.plot.parent, r.plot)
    return
end

function NG.step!(::Knock, game, dt)
    w = game.world
    me = NG.creature(w, "Lumi")
    me === nothing && return
    kdown = Makie.Keyboard.l in game.keys_down
    if kdown && !get(KN, :kdown, false) && me.controlled
        hit = kn_target(game, me)
        if hit === nothing
            NG.say!(w, me, "Nothing to knock on here."; duration = 1.4)
        else
            a, m, q, dir = hit
            parts = kn_partials(m, q, dir, a.scale)
            KN[:last] = (; asset = a.asset, what = m.what, node = q, partials = parts, t = w.t)
            kn_play!(game, parts)
            game.stage === nothing || kn_ring_start!(game, a, m, parts)
            me.action = :wave
            low = isempty(parts) ? 0.0 : parts[1][1]
            NG.say!(w, me, isempty(parts) ? "Thud! Too soft to sing." : "Knock! $(round(Int, low)) Hz $(m.what)."; duration = 1.8)
            NG.emit!(w, :knock; what = m.what, hz = round(low; digits = 1))
        end
    end
    KN[:kdown] = kdown
    game.stage === nothing || kn_ring_step!(game)
    return
end

register!(Knock())
