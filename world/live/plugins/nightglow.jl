# Night glow: after sunset the meadow flowers light up with a soft bioluminescent cyan,
# brighter the darker it gets, so the island at night has little lights to walk between.
# One meshscatter over all flower heads; hidden by day.
isdefined(Main, :NIGHTGLOW) || Core.eval(Main, :(const NIGHTGLOW = Dict{Symbol,Any}()))

const NG = NeverendingGame
const GLOW_VERSION = 10   # s134 low-poly glow markers
const GLOW_COLOR = (0.45, 1.0, 0.85)

struct NightGlow <: System end

# each glowing flower has a few soft motes hovering over it, bobbing slowly: a bright core and a faint
# halo each. (Session 29: the five flat petals round a core floated as hard cyan discs over the
# generated flowers, which have their own petals now.)
const MOTES = 3
const MOTE_HUES = (RGBf(0.55, 1.0, 0.85), RGBf(0.65, 0.9, 1.0), RGBf(0.85, 1.0, 0.6), RGBf(1.0, 0.9, 0.55))
const HALO_ALPHA = 0.10f0
const HALO = 2.2f0    # halo size per core size (4x at alpha 0.16 read as grey soap bubbles)

"Rest point, bob phase and colour of every mote (MOTES per flower, in flower order)."
function mote_layout(w)
    base = Point3f[]; phase = Float32[]; col = RGBf[]; sz = Float32[]
    for (n, p) in enumerate(w.props)
        p.kind === :flower || continue
        s = p.scale
        for k in 1:MOTES
            a = Float32(n * 1.7 + 2pi * k / MOTES)
            r = (0.12f0 + 0.06f0 * k) * s
            push!(base, p.pos + Point3f(r * cos(a), r * sin(a), (0.45f0 + 0.14f0 * k) * s))
            push!(phase, Float32(n * 0.9 + k * 2.1))
            push!(col, MOTE_HUES[mod1(n + k, length(MOTE_HUES))])
            push!(sz, (0.022f0 + 0.006f0 * (k % 2)) * s)
        end
    end
    if isempty(base)    # the raster cannot draw an empty meshscatter
        push!(base, Point3f(0, 0, -50)); push!(phase, 0f0); push!(col, MOTE_HUES[1]); push!(sz, 0.01f0)
    end
    return base, phase, col, sz
end

"Where the motes are at time `t`: each drifts on its own small loop."
mote_positions(base, phase, t) = [b + Point3f(0.05f0 * sin(0.7f0 * t + f), 0.05f0 * cos(0.6f0 * t + 1.3f0 * f), 0.07f0 * sin(1.1f0 * t + f))
                                  for (b, f) in zip(base, phase)]

function build_glow!(game)
    for k in (:plot, :halo)
        haskey(Main.NIGHTGLOW, k) && delete!(Main.NIGHTGLOW[k].parent, Main.NIGHTGLOW[k])
        delete!(Main.NIGHTGLOW, k)
    end
    w = game.world
    base, phase, col, sz = mote_layout(w)
    Main.NIGHTGLOW[:base] = base; Main.NIGHTGLOW[:phase] = phase
    Main.NIGHTGLOW[:sizes] = [Vec3f(x) for x in sz]
    Main.NIGHTGLOW[:ids] = [p.id for p in w.props if p.kind === :flower]   # MOTES instances each, in this order
    Main.NIGHTGLOW[:hidden] = Set{Int32}()
    pos = mote_positions(base, phase, Float32(w.t))
    # a quiet copy (game_clip, game_still: path traced) gets low-poly motes and no halos: every instance is an
    # emissive area light, and ~1000 of them ran a dusk clip out of GPU memory (s41, 191 MB alloc failed)
    quiet = game.dash === nothing
    Main.NIGHTGLOW[:quiet] = quiet
    marker = NG.shape(:glowdot)   # s134: low-poly in the live game too (5 M emissive faces ran films out of GPU memory)
    Main.NIGHTGLOW[:plot] = meshscatter!(game.stage.scene, pos; marker, markersize = Main.NIGHTGLOW[:sizes],
        color = col, shading = Makie.NoShading, material = NG.Hikari.Emission(color = GLOW_COLOR, strength = 3.0),
        visible = false, name = :nightglow_flowers)
    Main.NIGHTGLOW[:halo] = meshscatter!(game.stage.scene, pos; marker = NG.shape(:glowball), markersize = HALO .* Main.NIGHTGLOW[:sizes],
        color = [RGBAf(c, HALO_ALPHA) for c in col], shading = Makie.NoShading, transparency = true,
        material = NG.Hikari.Emission(color = GLOW_COLOR, strength = 1.0),   # emissive: no shadow blobs on the grass (RayMakie casts_shadow)
        visible = false, name = :nightglow_halos)
    Main.NIGHTGLOW[:key] = (GLOW_VERSION, NG.props_version(w))
end

function NG.start!(::NightGlow, game)
    game.stage === nothing && return
    get(Main.NIGHTGLOW, :key, nothing) == (GLOW_VERSION, NG.props_version(game.world)) &&
        Main.NIGHTGLOW[:plot].parent === game.stage.scene || build_glow!(game)
    return
end

function NG.step!(::NightGlow, game, dt)
    game.stage === nothing && return
    get(Main.NIGHTGLOW, :key, nothing) == (GLOW_VERSION, NG.props_version(game.world)) || build_glow!(game)
    on = NG.night_factor(game.world) > 0.35f0 || get(Main.NIGHTGLOW, :force, false)   # :force: look at them by day (screenshots)
    p, h = Main.NIGHTGLOW[:plot], Main.NIGHTGLOW[:halo]
    p.visible[] == on || (p.visible[] = on; h.visible[] = on && !get(Main.NIGHTGLOW, :quiet, false))
    hide_picked!(p, h)        # by day too: a flower picked at noon has no bloom at dusk
    on || return
    NG.path_traced(game) && return     # held still while tracing: moved glowing motes leak GPU area lights (NG.path_traced)
    pos = mote_positions(Main.NIGHTGLOW[:base], Main.NIGHTGLOW[:phase], Float32(game.world.t))
    Makie.update!(p; arg1 = pos); Makie.update!(h; arg1 = pos)
    return
end

"A flower picked for a gift (plugins/flowergift.jl, FLORA_PLOTS[:picked]) has no bloom until it regrows."
function hide_picked!(plot, halo)
    isdefined(Main, :FLORA_PLOTS) || return
    picked = get(Main.FLORA_PLOTS, :picked, nothing)
    picked === nothing && return
    ids = Main.NIGHTGLOW[:ids]
    hidden = Set{Int32}(id for id in ids if haskey(picked, id))
    hidden == Main.NIGHTGLOW[:hidden] && return
    Main.NIGHTGLOW[:hidden] = hidden
    sizes = copy(Main.NIGHTGLOW[:sizes])
    n = MOTES
    for (k, id) in enumerate(ids)
        id in hidden && (sizes[(k - 1) * n + 1:k * n] .= Ref(Vec3f(0)))
    end
    Makie.update!(plot; markersize = sizes)
    Makie.update!(halo; markersize = HALO .* sizes)
end

NG.stop!(::NightGlow, game) = foreach(k -> haskey(Main.NIGHTGLOW, k) && (Main.NIGHTGLOW[k].visible[] = false), (:plot, :halo))

register!(NightGlow())
