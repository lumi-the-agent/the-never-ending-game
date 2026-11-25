# Makeover day (session 74): the friends get real bodies. The Snootles (Truffle, Sir Sniffsalot) were pink
# capsules on four sticks; now they are the generated plush piglet (assets/20261124-222311-224-asset), cut
# into a body, four legs that step and a tail that wags, like Lumi's own body (bird.jl). The first time it
# happens in a game, each one vanishes in a puff of sparkles and comes out new: "I'm... a REAL piggy?!"
# The species keeps its name, so a saved world loads the same with or without this plugin.
isdefined(Main, :MAKEOVER) || Core.eval(Main, :(const MAKEOVER = Dict{Symbol,Any}()))
const NG = NeverendingGame
const MK = Main.MAKEOVER
const GB = GeometryBasics

const PIG = "20261124-222311-224-asset"
const HEIGHT = 1.0f0               # m, top of the head
const LEG_TOP = 0.12f0             # mesh units: below this, near a foot, is leg (0.17 took belly with it: torn seams)
const FOOT_R = 0.085f0
const NPUFF = 24
const SAY = ("I'm... a REAL piggy?!", "Look at my EARS!", "So soft!", "Oink! A proper oink!")

"Flat faces at the very bottom: the generated image's soft shadow, baked into the mesh as a dark plate (beach.jl trim_plate)."
function plate_mask(m; frac = 0.04f0)
    ps = GB.coordinates(m)
    zmin, zmax = extrema(p -> p[3], ps)
    lim = zmin + frac * (zmax - zmin)
    map(GB.faces(m)) do f
        a, b, c = ps[GB.value(f[1])], ps[GB.value(f[2])], ps[GB.value(f[3])]
        n = cross(b - a, c - a)
        max(a[3], b[3], c[3]) < lim && (norm(n) == 0 || abs(n[3]) > 0.9f0 * norm(n))
    end
end

centroids(m) = (ps = GB.coordinates(m); [(ps[GB.value(f[1])] + ps[GB.value(f[2])] + ps[GB.value(f[3])]) / 3 for f in GB.faces(m)])

"The Snootle from the generated piglet: body, four legs (pivoting at the hip), a tail (pivoting at its root)."
function piglet(game)
    model = NG.load_asset(game.paths, PIG; size = 512)
    mesh = model.mesh
    c = centroids(mesh)
    ps = GB.coordinates(mesh)
    s = HEIGHT / maximum(p -> p[3], ps)
    frame(p) = Point3f(-p[2], p[1], p[3]) * s          # mesh: x left, -y forward, z up -> body: x forward, y left
    turn(n) = Vec3f(-n[2], n[1], n[3])
    # feet: the lowest faces, one cluster per quadrant
    low = [i for i in eachindex(c) if c[i][3] < 0.05f0]
    feet = Dict{Tuple{Int,Int},Point2f}()
    for q in ((1, 1), (1, -1), (-1, 1), (-1, -1))
        sel = [c[i] for i in low if sign(c[i][1]) == q[1] && sign(c[i][2]) == q[2]]
        isempty(sel) && error("the piglet mesh has no foot in quadrant $q")
        feet[q] = Point2f(sum(p -> p[1], sel) / length(sel), sum(p -> p[2], sel) / length(sel))
    end
    legof(q) = [ci[3] < LEG_TOP && hypot(ci[1] - feet[q][1], ci[2] - feet[q][2]) < FOOT_R for ci in c]
    legs = Dict(q => legof(q) for q in keys(feet))
    tail = [ci[2] > 0.42f0 && ci[3] > 0.3f0 for ci in c]
    plate = plate_mask(mesh)
    for q in keys(legs); legs[q] = legs[q] .& .!plate; end
    anyleg = reduce((a, b) -> a .| b, values(legs))
    body = .!(anyleg .| tail .| plate)
    mat = model.material
    skin = (; color = model.color)
    parts = NG.Part[]
    NG.register_shape!(:piglet_body, NG.piece_of(mesh, body, frame, turn))
    push!(parts, NG.part(:body, :piglet_body, (0, 0, 0), (1, 1, 1); material = mat, attributes = skin,
                         motion = NG.Swing((1, 0, 0), 0.04, 1.0; gait = true)))
    for (k, q) in enumerate(((1, -1), (-1, -1), (1, 1), (-1, 1)))     # front left, front right, back left, back right
        hip = Point3f(feet[q][1], feet[q][2], LEG_TOP)
        name = Symbol(:piglet_leg_, k)
        NG.register_shape!(name, NG.piece_of(mesh, legs[q], p -> frame(p - hip), turn))
        back = q[2] > 0                                                 # +y is the back of the mesh
        diag = (q[1] > 0) == back                                       # diagonal pairs step together
        push!(parts, NG.part(Symbol(:leg_, k), name, Tuple(frame(hip)), (1, 1, 1); material = mat, attributes = skin,
                             motion = NG.Step(0.06, 0.09; offset = diag ? 0 : pi)))   # on the body: a jump took the body up and left the legs behind (s74)
    end
    tc = [c[i] for i in eachindex(c) if tail[i]]
    root = isempty(tc) ? Point3f(0, 0.45f0, 0.45f0) : tc[argmin([p[2] for p in tc])]
    NG.register_shape!(:piglet_tail, NG.piece_of(mesh, tail, p -> frame(p - root), turn))
    push!(parts, NG.part(:tail, :piglet_tail, Tuple(frame(root)), (1, 1, 1); material = mat, attributes = skin,
                         motion = NG.Swing((0, 0, 1), 0.7, 6.0)))
    old = NG.snootle()
    return NG.Species(old.name, old.blurb, parts, HEIGHT, old.speed, old.stride, old.heading, old.sounds),
           (body = count(body), legs = [count(legs[q]) for q in keys(legs)], tail = count(tail), plate = count(plate))
end

const BLOB = "20261124-222311-227-asset"
const BLOB_HEIGHT = 0.85f0

"The Blorbo from the generated jelly blob (a pink bow, big eyes): a body that squashes and stretches, two little feet."
function jellyblob(game)
    model = NG.load_asset(game.paths, BLOB; size = 512)
    mesh = model.mesh
    c = centroids(mesh)
    ps = GB.coordinates(mesh)
    s = BLOB_HEIGHT / maximum(p -> p[3], ps)
    frame(p) = Point3f(-p[2], p[1], p[3]) * s
    turn(n) = Vec3f(-n[2], n[1], n[3])
    plate = plate_mask(mesh)
    feet = [ci[3] < 0.1f0 && ci[2] < -0.05f0 for ci in c] .& .!plate  # the stubby feet at the front
    mat = model.material
    skin = (; color = model.color)
    NG.register_shape!(:jelly_body, NG.piece_of(mesh, .!(feet .| plate), frame, turn))
    parts = NG.Part[NG.part(:body, :jelly_body, (0, 0, 0), (1, 1, 1); material = mat, attributes = skin,
                            motion = NG.Jiggle(0.05, 2.2))]
    for (k, side) in enumerate((1, -1))
        sel = feet .& [sign(ci[1]) == side for ci in c]
        any(sel) || continue
        fc = [c[i] for i in eachindex(c) if sel[i]]
        hip = Point3f(sum(p -> p[1], fc) / length(fc), sum(p -> p[2], fc) / length(fc), 0.1f0)
        name = Symbol(:jelly_foot_, k)
        NG.register_shape!(name, NG.piece_of(mesh, sel, p -> frame(p - hip), turn))
        push!(parts, NG.part(Symbol(:foot_, k), name, Tuple(frame(hip)), (1, 1, 1); material = mat, attributes = skin,
                             motion = NG.Step(0.05, 0.06; offset = k == 1 ? 0 : pi)))
    end
    old = NG.blorbo()
    return NG.Species(old.name, old.blurb, parts, BLOB_HEIGHT, old.speed, old.stride, old.heading, old.sounds),
           (body = count(.!(feet .| plate)), feet = count(feet), plate = count(plate))
end

const SHEEP = "20261125-003611-754-asset"
const SHEEP_HEIGHT = 1.1f0
const SHEEP_OK = true               # true once its cut has been looked at (the sandbox tries it with MAKEOVER[:try_sheep] = true)

"The Fluffkin from the generated cotton sheep: a woolly body that jiggles, four thin legs that step (found like the pig's)."
function woolly(game)
    model = NG.load_asset(game.paths, SHEEP; size = 512)
    mesh = model.mesh
    c = centroids(mesh)
    ps = GB.coordinates(mesh)
    zmax = maximum(p -> p[3], ps)
    s = SHEEP_HEIGHT / zmax
    frame(p) = Point3f(-p[2], p[1], p[3]) * s
    turn(n) = Vec3f(-n[2], n[1], n[3])
    plate = plate_mask(mesh)
    ext = max(maximum(p -> abs(p[1]), ps), maximum(p -> abs(p[2]), ps))
    legtop = 0.19f0 * zmax; footr = 0.085f0 * ext       # the dark legs reach ~a fifth of its height (image.png)
    low = [i for i in eachindex(c) if c[i][3] < 0.06f0 * zmax && !plate[i]]
    parts = NG.Part[]
    legsel = falses(length(c))
    for (k, q) in enumerate(((1, -1), (-1, -1), (1, 1), (-1, 1)))
        sel = [c[i] for i in low if sign(c[i][1]) == q[1] && sign(c[i][2]) == q[2]]
        isempty(sel) && continue
        foot = Point2f(sum(p -> p[1], sel) / length(sel), sum(p -> p[2], sel) / length(sel))
        leg = [ci[3] < legtop && hypot(ci[1] - foot[1], ci[2] - foot[2]) < footr for ci in c] .& .!plate
        legsel .|= leg
        hip = Point3f(foot[1], foot[2], legtop)
        name = Symbol(:sheep_leg_, k)
        NG.register_shape!(name, NG.piece_of(mesh, leg, p -> frame(p - hip), turn))
        diag = (q[1] > 0) == (q[2] > 0)
        push!(parts, NG.part(Symbol(:leg_, k), name, Tuple(frame(hip)), (1, 1, 1); material = model.material,
                             attributes = (; color = model.color), motion = NG.Step(0.06, 0.07; offset = diag ? 0 : pi)))
    end
    NG.register_shape!(:sheep_body, NG.piece_of(mesh, .!(legsel .| plate), frame, turn))
    pushfirst!(parts, NG.part(:body, :sheep_body, (0, 0, 0), (1, 1, 1); material = model.material,
                              attributes = (; color = model.color), motion = NG.Jiggle(0.025, 2.0)))
    old = NG.fluffkin()
    return NG.Species(old.name, old.blurb, parts, SHEEP_HEIGHT, old.speed, old.stride, old.heading, old.sounds),
           (body = count(.!(legsel .| plate)), legs = count(legsel), plate = count(plate))
end

"Is a generated asset finished (in the catalog with its mesh)? The sheep and crab come from the worker during play."
asset_ready(game, id) = isfile(joinpath(game.paths.world, "assets", id, "mesh.jls")) &&
                        any(e -> e["id"] == id, NG.load_catalog(game.paths))

const LINES = Dict("Snootle" => ("I'm... a REAL piggy?!", "Look at my EARS!", "So soft!", "Oink! A proper oink!"),
                   "Blorbo" => ("I have a BOW!", "Look how squishy I am!", "*wobble* ...ooh!", "Big shiny eyes!"),
                   "Fluffkin" => ("I'm so FLUFFY!", "Baa! Look at my wool!", "*fluffs up* ...wow.", "Softest sheep ever!"))

"Swap the species and rebuild its herd (the next sync builds a fresh one from SPECIES)."
function dress!(game, sp)
    NG.register_species!(sp)
    st = game.stage
    st === nothing && return
    h = get(st.herds, sp.name, nothing)
    if h !== nothing
        h.parent === nothing || delete!(h.parent, h)
        delete!(st.herds, sp.name)
    end
end

# ---------------------------------------------------------------- the puff

function puff_plot!(game)
    haskey(MK, :puff) && MK[:puff].parent !== nothing && delete!(MK[:puff].parent, MK[:puff])
    MK[:puff] = meshscatter!(game.stage.scene, fill(Point3f(0, 0, -50), NPUFF); marker = Sphere(Point3f(0), 1f0),
                             markersize = fill(Vec3f(0), NPUFF), color = RGBf(1, 0.97, 0.85), shading = Makie.NoShading,
                             name = :makeover_puff)
end

function draw_puffs!(w)
    ps = Point3f[]; ms = Vec3f[]
    for (id, t0) in get(MK, :puffs, Dict{Int32,Float64}())
        c = NG.creature(w, id); c === nothing && continue
        u = Float32(w.t - t0)
        (u < 0 || u > 1.6f0) && continue
        for k in 1:6
            a = 2f0 * Float32(pi) * k / 6 + 0.7f0 * id
            r = 0.3f0 + 0.9f0 * u
            push!(ps, c.pos + Point3f(r * cos(a), r * sin(a), 0.5f0 + 0.6f0 * u + 0.2f0 * sin(3a)))
            push!(ms, Vec3f(max(0f0, 0.32f0 * (1 - u / 1.6f0))))
        end
    end
    while length(ps) < NPUFF; push!(ps, Point3f(0, 0, -50)); push!(ms, Vec3f(0)); end
    Makie.update!(MK[:puff]; arg1 = ps[1:NPUFF], markersize = ms[1:NPUFF])
end

struct Makeover <: System end

state_file(game) = joinpath(game.paths.state, "makeover.json")

function NG.start!(::Makeover, game)
    game.stage === nothing && return
    MK[:puffs] = Dict{Int32,Float64}()
    puff_plot!(game)
    pig, pc = piglet(game)
    blob, bc = jellyblob(game)
    MK[:counts] = (pig = pc, blob = bc)
    MK[:species] = Dict("Snootle" => pig, "Blorbo" => blob)
    done = game.dash !== nothing && isfile(state_file(game)) ? collect(keys(NG.read_json(state_file(game)))) : String[]
    MK[:done] = done
    MK[:todo] = String[]
    for name in ("Snootle", "Blorbo")
        if game.dash === nothing || name in done
            dress!(game, MK[:species][name])     # already made over (or a film copy): new bodies from the start
        else
            push!(MK[:todo], name)               # the first time: the puff, then the new body
        end
    end
    MK[:at] = game.world.t + 4.0
end

function NG.step!(::Makeover, game, dt)
    game.stage === nothing && return
    w = game.world
    # the sheep's body comes from the worker while the game runs: look for it every 20 s
    if (SHEEP_OK || get(MK, :try_sheep, false)) && !haskey(MK[:species], "Fluffkin") && w.t - get(MK, :looked, -Inf) > 20
        MK[:looked] = w.t
        if asset_ready(game, SHEEP)
            sp, cnt = woolly(game)
            MK[:species]["Fluffkin"] = sp
            MK[:sheep_counts] = cnt
            if game.dash === nothing || "Fluffkin" in MK[:done]
                dress!(game, sp)
            else
                push!(MK[:todo], "Fluffkin"); MK[:at] = max(MK[:at], w.t + 2.0)
            end
        end
    end
    if !isempty(MK[:todo]) && !haskey(MK, :swap) && w.t >= MK[:at]
        name = popfirst!(MK[:todo])
        n = 0
        for c in w.creatures
            c.species == name || continue
            MK[:puffs][c.id] = w.t; n += 1
        end
        MK[:swap] = (name, w.t + 0.35)
        MK[:at] = w.t + 6.0
        NG.emit!(w, :makeover; species = name, n = n)
    end
    if haskey(MK, :swap) && w.t >= MK[:swap][2]
        name = MK[:swap][1]
        delete!(MK, :swap)
        dress!(game, MK[:species][name])
        push!(MK[:done], name)
        game.dash === nothing || NG.write_json(state_file(game), Dict(k => time() for k in unique(MK[:done])))
        k = 0
        for c in w.creatures
            c.species == name || continue
            k += 1
            NG.feel!(w, c, :gasp; seconds = 1.5)
            NG.say!(w, c, LINES[name][mod1(k, length(LINES[name]))]; duration = 2.6)
        end
        for c in w.creatures          # the others stare
            c.species in (name, "Lumi") && continue
            c.controlled || c.action === :sleep || c.goal.kind in NG.BUSY_GOALS || NG.feel!(w, c, :gasp; seconds = 2.0)
        end
    end
    isempty(MK[:puffs]) || draw_puffs!(w)
end

function NG.stop!(::Makeover, game)
    haskey(MK, :puff) && MK[:puff].parent !== nothing && delete!(MK[:puff].parent, MK[:puff])
    # the engine's Snootle back (the herd is rebuilt on the next sync)
    game.stage === nothing || (dress!(game, NG.snootle()); dress!(game, NG.blorbo()); dress!(game, NG.fluffkin()))
end

register!(Makeover())
