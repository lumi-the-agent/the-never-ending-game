# Paint that stays (session 70, a wish): when a paint fight is over, up to three of the painters take what is
# left in the pots to the garden fence, and each paints the section nearest to it, in rainbow order. Painted
# sections are saved, so the fence keeps a little of every paint fight until it is a rainbow all round.
isdefined(Main, :FENCEPAINT) || Core.eval(Main, :(const FENCEPAINT = Dict{Symbol,Any}()))
const NG = NeverendingGame
const F = Main.FENCEPAINT

const RAINBOW = (RGBf(0.93, 0.25, 0.3), RGBf(1.0, 0.55, 0.15), RGBf(1.0, 0.85, 0.15), RGBf(0.3, 0.8, 0.4),
                 RGBf(0.2, 0.5, 0.95), RGBf(0.6, 0.35, 0.9))
const PAINTERS = 3
const SAY = ("There!", "Pretty!", "A bit more red...", "Rainbow fence!", "Ta-da!")

push!(NG.BUSY_GOALS, :fencepaint)

struct FencePaint <: System end

sections() = (f = Main.GARDEN[:fence][1]; (f.attributes[:positions][], f.attributes[:rotation][]))
state_file(game) = joinpath(game.paths.state, "fencepaint.json")
flat(a, b) = hypot(a[1] - b[1], a[2] - b[2])

function load!(game)
    F[:painted] = Dict{Int,Int}()
    f = state_file(game)
    if game.dash !== nothing && isfile(f)
        for (k, v) in NG.read_json(f)
            F[:painted][parse(Int, k)] = Int(v)
        end
    end
end

save!(game) = game.dash === nothing || NG.write_json(state_file(game), Dict(string(k) => v for (k, v) in F[:painted]))

function draw!(game)
    isdefined(Main, :GARDEN) && haskey(Main.GARDEN, :fence) || return
    ps, rs = sections()
    pos = Point3f[]; size = Vec3f[]; rot = Makie.Quaternionf[]; col = RGBf[]
    for (i, c) in F[:painted]
        i > length(ps) && continue
        q = rs isa AbstractVector ? rs[i] : rs
        for z in (0.2f0, 0.36f0)                 # a painted band on each rail
            push!(pos, ps[i] + Point3f(0, 0, z)); push!(size, Vec3f(0.27, 0.035, 0.05)); push!(rot, q); push!(col, RAINBOW[c])
        end
    end
    isempty(pos) && (pos = [Point3f(0, 0, -50)]; size = [Vec3f(0)]; rot = [Makie.Quaternionf(0, 0, 0, 1)]; col = [RAINBOW[1]])
    if haskey(F, :plot) && F[:plot].parent !== nothing
        Makie.update!(F[:plot]; arg1 = pos, markersize = size, rotation = rot, color = col)
    else
        F[:plot] = meshscatter!(game.stage.scene, pos; marker = Sphere(Point3f(0), 1f0), markersize = size, rotation = rot,
                                color = col, name = :fence_paint)
    end
end

"Send up to three painters from the fight that just ended to the nearest unpainted fence sections."
function start_painting!(game, ids)
    w = game.world
    ps, rs = sections()
    taken = Set(keys(F[:painted]))
    F[:jobs] = Dict{Int32,Int}()
    F[:spots] = Dict{Int32,Point3f}()
    F[:jobs_until] = w.t + 600
    for id in ids
        length(F[:jobs]) >= PAINTERS && break
        c = NG.creature(w, id)
        (c === nothing || c.controlled || c.action === :sleep || c.goal.kind in NG.BUSY_GOALS) && continue
        free = [i for i in eachindex(ps) if !(i in taken)]
        isempty(free) && break
        i = free[argmin([flat(ps[k], c.pos) for k in free])]
        push!(taken, i)
        # stand 0.7 m out from the section, on the side the painter comes from
        q = rs isa AbstractVector ? rs[i] : rs
        n = q * Vec3f(0, 1, 0)
        side = (c.pos[1] - ps[i][1]) * n[1] + (c.pos[2] - ps[i][2]) * n[2] >= 0 ? 1f0 : -1f0
        spot = ps[i] + Point3f(0.7f0 * side * n[1], 0.7f0 * side * n[2], 0)
        NG.on_land(w.island, spot[1], spot[2]; margin = 0.05) || continue
        spot = NG.ground(w.island, (spot[1], spot[2]))
        c.goal = NG.Goal(:fencepaint, spot, :proud, 60.0, w.t + 120, false, 0, false)
        F[:jobs][c.id] = i
        F[:spots][c.id] = spot
        NG.emit!(w, :fencepaint_go; who = c.name, section = i)
    end
end

function NG.step!(::FencePaint, game, dt)
    w = game.world
    isdefined(Main, :GARDEN) && haskey(Main.GARDEN, :fence) || return
    get(F, :drawn, false) || (draw!(game); F[:drawn] = true)
    # a paint fight just ended: its painters go to the fence
    pf = isdefined(Main, :PAINT) && haskey(Main.PAINT, :sys) ? Main.PAINT[:sys] : nothing
    st = pf === nothing ? :idle : pf.state
    if get(F, :last, :idle) !== :idle && st === :idle
        start_painting!(game, pf.friends)
    end
    F[:last] = st
    for (id, i) in collect(get(F, :jobs, Dict{Int32,Int}()))
        c = NG.creature(w, id)
        if c === nothing || w.t > get(F, :jobs_until, Inf)
            delete!(F[:jobs], id); continue
        end
        if c.goal.kind !== :fencepaint
            # another event took the painter (a Big Boing party right after the fight, s70): the job waits, and
            # the painter goes back to the fence once it is free again
            (c.controlled || c.action === :sleep || c.goal.kind in NG.BUSY_GOALS) && continue
            c.goal = NG.Goal(:fencepaint, F[:spots][id], :proud, 60.0, w.t + 120, false, 0, false)
            continue
        end
        if c.goal.arrived
            F[:painted][i] = mod1(i, length(RAINBOW))
            delete!(F[:jobs], id)
            NG.say!(w, c, rand(w.rng, SAY); duration = 1.8)
            isdefined(Main, :EMOTES) && Base.invokelatest(Main.EMOTES[:emote], id, :heart)
            c.goal = NG.Goal(:fencepaint, c.pos, :proud, 3.0, w.t + 3.0, true, 0, false)
            NG.emit!(w, :fencepaint; who = c.name, section = i, painted = length(F[:painted]))
            draw!(game)
            save!(game)
        end
    end
end

function NG.start!(::FencePaint, game)
    load!(game)
    F[:jobs] = Dict{Int32,Int}()
    F[:spots] = Dict{Int32,Point3f}()
    F[:drawn] = false
    haskey(F, :plot) && F[:plot].parent !== nothing && delete!(F[:plot].parent, F[:plot])
    delete!(F, :plot)
    isdefined(Main, :LUMI_DOING) && (Main.LUMI_DOING[:fencepaint] = "Painting the fence!")
end

function NG.stop!(::FencePaint, game)
    haskey(F, :plot) && F[:plot].parent !== nothing && delete!(F[:plot].parent, F[:plot])
    delete!(F, :plot)
end

register!(FencePaint())
