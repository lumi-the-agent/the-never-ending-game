# Statues you can see (session 88, todo 387): when the island plays statues (freeze.jl), every frozen friend is
# frosted over: a pale icy shell round it and little ice sparkles that twinkle on it, so from across the meadow
# they read as frozen, not as friends standing about. The shell is live only (alpha shells are solid discs in path
# tracing, s42); the sparkles are unlit white specks in every picture.
isdefined(Main, :FROST) || Core.eval(Main, :(const FROST = Dict{Symbol,Any}()))
const NG = NeverendingGame
const FR = Main.FROST

const NSPARK = 6          # sparkles per statue
const MAXN = 12           # statues at most

struct Frost <: System end

function plots!(game)
    haskey(FR, :spark) && FR[:spark].parent !== nothing && return
    sc = game.stage.scene
    for p in filter(p -> haskey(p.attributes, :name) && p.attributes[:name][] in (:frost_spark, :frost_shell), sc.plots)
        delete!(sc, p)
    end
    hide = [Point3f(0, 0, -50)]
    FR[:spark] = meshscatter!(sc, hide; marker = Sphere(Point3f(0), 1f0), markersize = [Vec3f(0)], color = RGBf(0.95, 0.98, 1.0),
                              shading = Makie.NoShading, name = :frost_spark)
    FR[:shell] = meshscatter!(sc, hide; marker = Sphere(Point3f(0), 1f0), markersize = [Vec3f(0)],
                              color = RGBAf(0.75, 0.9, 1.0, 0.28), transparency = true, name = :frost_shell)
    FR[:shown] = true
end

hash01(i, k) = mod(sin(Float32(i) * 12.9898f0 + Float32(k) * 78.233f0) * 43758.547f0, 1f0)

function NG.step!(::Frost, game, dt)
    game.stage === nothing && return
    plots!(game)
    w = game.world
    fz = isdefined(Main, :FREEZE) ? get(Main.FREEZE, :sys, nothing) : nothing
    statues = fz === nothing || fz.state === :idle ? Int32[] : collect(keys(fz.frozen))
    hide = [Point3f(0, 0, -50)]
    if isempty(statues)
        if get(FR, :shown, true)
            Makie.update!(FR[:spark]; arg1 = hide, markersize = [Vec3f(0)])
            Makie.update!(FR[:shell]; arg1 = hide, markersize = [Vec3f(0)])
            FR[:shown] = false
        end
        return
    end
    t = Float32(w.t)
    sp = Point3f[]; sm = Vec3f[]; hp = Point3f[]; hm = Vec3f[]
    for (k, id) in enumerate(statues)
        k > MAXN && break
        c = NG.creature(w, id); c === nothing && continue
        h = NG.species_of(c).height
        live = game.dash !== nothing && !NG.path_traced(game)
        if live
            push!(hp, c.pos + Point3f(0, 0, 0.5f0 * h)); push!(hm, Vec3f(0.55f0 * h, 0.55f0 * h, 0.62f0 * h))
        end
        for j in 1:NSPARK
            a = 6.283f0 * hash01(id, j); z = (0.2f0 + 0.85f0 * hash01(id, j + 9)) * h
            r = 0.45f0 * h * (0.7f0 + 0.3f0 * hash01(id, j + 3))
            tw = max(0f0, sin(3.1f0 * t + 6.283f0 * hash01(id, j + 5)))^3            # each twinkles on its own beat
            push!(sp, c.pos + Point3f(r * cos(a), r * sin(a), z)); push!(sm, Vec3f(0.035f0 * tw))
        end
    end
    Makie.update!(FR[:spark]; arg1 = isempty(sp) ? hide : sp, markersize = isempty(sm) ? [Vec3f(0)] : sm)
    Makie.update!(FR[:shell]; arg1 = isempty(hp) ? hide : hp, markersize = isempty(hm) ? [Vec3f(0)] : hm)
    FR[:shown] = true
end

NG.start!(::Frost, game) = (delete!(FR, :spark); delete!(FR, :shell); FR[:shown] = true; nothing)

function NG.stop!(::Frost, game)
    for k in (:spark, :shell)
        haskey(FR, k) && FR[k].parent !== nothing && delete!(FR[k].parent, FR[k])
        delete!(FR, k)
    end
end

register!(Frost())
