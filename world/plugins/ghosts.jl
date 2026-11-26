# Yesterday walks again (session 99, goal 8): now and then pale see-through ghosts of my friends and me appear and
# do exactly what we did at this very hour yesterday, step for step, from the island's own memory of every pose
# (log/frames). Yesterday's Gloop fishes off the pier beside today's Gloop; yesterday's me runs across today's
# meadow. The living stop and stare, and whoever meets its own ghost says something about it. Then they fade.
isdefined(Main, :GHOSTS) || Core.eval(Main, :(const GHOSTS = Dict{Symbol,Any}()))
const NG = NeverendingGame
const GH = Main.GHOSTS

const SHOW = 45.0                 # s the ghosts walk
const EVERY = (420.0, 720.0)      # s between two hauntings
const MEET_R = 3.0f0
const GHOST = RGBAf(0.78, 0.9, 1.0, 0.38)
const MEET_LINES = ("Is that... ME?", "I KNEW I was taller.", "Hello, yesterday me!", "Did I really walk like that?",
                    "Ooh, I remember that!", "Stop copying me! ...oh.")
const LUMI_LINES = ("That's us. Yesterday, at this very hour.", "Oh look, it's me, chasing my shadow again.")

mutable struct Ghosts <: System
    on::Bool
    t0::Float64          # island time the haunting started
    wall0::Float64       # the wall time of yesterday it replays from
    frames::Vector{Any}
    k::Int
    met::Set{Int32}
end
Ghosts() = Ghosts(false, 0.0, 0.0, Any[], 1, Set{Int32}())

"A see-through copy of a species: same parts and motions, every part a pale translucent colour."
function ghost_species(sp; traced = false)
    # traced copies ignore alpha, so there they are pale solid doubles
    # traced: half see-through with a sheen that brightens the rims (Hikari's own ghost recipe, materials.md: Diffuse
    # mixed with Transparent; glass ghosts had traced dark navy in s99). Live: the pale translucent colour, lit.
    mat = traced ? NG.Hikari.Add(NG.Hikari.Mix(NG.Hikari.Diffuse(color = (0.78, 0.9, 1.0)), NG.Hikari.Transparent(); factor = 0.65f0),
                                 NG.Hikari.Sheen(color = (0.85, 0.97, 1.0), roughness = 0.3f0)) : nothing
    parts = [NG.Part(p.name, p.shape, mat, p.offset, p.scale, p.tilt, p.motion, p.anchor, p.mirror,
                     merge(p.attributes, (color = GHOST, transparency = true)))   # lit (s107: unlit they read as flat white cut-outs)
             for p in sp.parts]
    return NG.Species(sp.name * " ghost", sp.blurb, parts, sp.height, sp.speed, sp.stride, sp.heading, sp.sounds)
end

"Yesterday's poses from this wall-clock time on (the hour's frame file and the next), or nothing."
function yesterday(game, span)
    w0 = time() - 86400
    dir = joinpath(game.paths.world, "log", "frames")
    fr = Any[]
    for dt in (0, 3600)
        f = joinpath(dir, Libc.strftime("%Y-%m-%d-%H", w0 + dt) * ".bin")
        isfile(f) || continue
        append!(fr, [x for x in NG.read_frames(f) if w0 <= x.wall <= w0 + span])
    end
    return isempty(fr) ? nothing : (w0, fr)
end

function begin_haunting!(s::Ghosts, game)
    y = yesterday(game, SHOW + 5)
    y === nothing && return false
    s.wall0, s.frames = y
    s.on = true; s.t0 = game.world.t; s.k = 1; empty!(s.met)
    me = findfirst(c -> c.name == "Lumi", game.world.creatures)
    if me !== nothing
        c = game.world.creatures[me]
        c.controlled || NG.say!(game.world, c, LUMI_LINES[rand(game.world.rng, 1:length(LUMI_LINES))]; duration = 3.0)
    end
    push!(get!(() -> Tuple{Float64,Symbol}[], GH, :log), (game.world.t, :arrive))
    NG.emit!(game.world, :ghosts_arrive; frames = length(s.frames))
    return true
end

# An EMPTY herd breaks every raster screenshot ("device storage requires an isbits element type, got Any", s100):
# a herd with no ghosts keeps one, far under the island.
const HIDDEN = Point3f(0, 0, -100)
hide!(h) = Makie.update!(h, [HIDDEN]; motion = [Vec3f(0)], state = [Vec3f(0)])

"The ghost herds (one per species), made the first time a species is needed."
function herd_of(game, species::String)
    hs = get!(() -> Dict{String,Any}(), GH, :herds)::Dict{String,Any}
    h = get(hs, species, nothing)
    (h !== nothing && h.parent !== nothing) && return h
    sp = get(NG.SPECIES, species, nothing)
    sp === nothing && return nothing
    hs[species] = NG.herd!(game.stage.scene, [HIDDEN]; species = ghost_species(sp; traced = game.dash === nothing), motion = [Vec3f(0)], state = [Vec3f(0)],
                           name = Symbol("ghost_", lowercase(species)))
end

function draw!(s::Ghosts, game)
    w = game.world
    hs = get(GH, :herds, Dict{String,Any}())::Dict{String,Any}
    if !s.on
        get(GH, :shown, true) && foreach(hide!, values(hs))
        GH[:shown] = false
        return
    end
    # the frame of yesterday at the same moment into the haunting
    target = s.wall0 + (w.t - s.t0)
    while s.k < length(s.frames) && s.frames[s.k + 1].wall <= target
        s.k += 1
    end
    f = s.frames[s.k]
    groups = Dict{String,Vector{Any}}()
    for p in f.poses
        c = NG.creature(w, p.id)
        c === nothing && continue
        push!(get!(() -> Any[], groups, c.species), (p, c))
    end
    for (species, ps) in groups
        h = herd_of(game, species)
        h === nothing && continue
        Makie.update!(h, [p.pos for (p, _) in ps]; motion = [Vec3f(p.yaw, p.phase, p.mood) for (p, _) in ps],
                      state = [Vec3f(p.action, p.extra, c.seed) for (p, c) in ps], time = Float32(w.t))
    end
    for (species, h) in hs
        haskey(groups, species) || hide!(h)
    end
    GH[:shown] = true
    GH[:frame] = f
end

"Whoever finds its own ghost close by stops, turns to it and says something about itself."
function meetings!(s::Ghosts, game)
    w = game.world
    f = get(GH, :frame, nothing); f === nothing && return
    for p in f.poses
        p.id in s.met && continue
        c = NG.creature(w, p.id)
        (c === nothing || c.controlled || c.action === :sleep || c.goal.kind in NG.BUSY_GOALS) && continue
        hypot(c.pos[1] - p.pos[1], c.pos[2] - p.pos[2]) < MEET_R || continue
        push!(s.met, p.id)
        NG.leave_interactions!(w, c)
        c.yaw = atan(p.pos[2] - c.pos[2], p.pos[1] - c.pos[1]) - NG.species_of(c).heading
        NG.feel!(w, c, rand(w.rng) < 0.5 ? :gasp : :laugh; seconds = 2.5)
        NG.say!(w, c, MEET_LINES[mod1(Int(p.id) + length(s.met), length(MEET_LINES))]; duration = 2.5)
        push!(GH[:log], (w.t, :meet))
        NG.emit!(w, :ghost_meet; who = c.name)
    end
end

function NG.step!(s::Ghosts, game, dt)
    game.stage === nothing && return
    w = game.world
    if !s.on
        testing = game.tests !== nothing && NG.running(game.tests)
        haskey(GH, :next) || (GH[:next] = w.t + 120 + 120 * rand(w.rng))
        if get(GH, :film, false) || (!testing && w.t >= GH[:next])
            GH[:next] = w.t + EVERY[1] + (EVERY[2] - EVERY[1]) * rand(w.rng)
            GH[:film] = false
            begin_haunting!(s, game)
        end
    else
        meetings!(s, game)
        if w.t - s.t0 > get(GH, :show, SHOW)
            s.on = false
            push!(GH[:log], (w.t, :fade))
            NG.emit!(w, :ghosts_fade; met = length(s.met))
        end
    end
    draw!(s, game)
end

function NG.start!(s::Ghosts, game)
    GH[:sys] = s; s.on = false
    delete!(GH, :next); delete!(GH, :frame)
    for p in filter(p -> haskey(p.attributes, :name) && startswith(string(p.attributes[:name][]), "ghost_"), copy(game.stage === nothing ? Any[] : game.stage.scene.plots))
        delete!(game.stage.scene, p)
    end
    GH[:herds] = Dict{String,Any}(); GH[:shown] = true
    GH[:start] = () -> begin_haunting!(s, game)
    isdefined(Main, :LUMI_DOING) && (Main.LUMI_DOING[:ghosts] = "watching yesterday walk past")
    return nothing
end

function NG.stop!(s::Ghosts, game)
    s.on = false
    for h in values(get(GH, :herds, Dict{String,Any}()))
        h.parent === nothing || delete!(h.parent, h)
    end
    GH[:herds] = Dict{String,Any}()
end

register!(Ghosts())
