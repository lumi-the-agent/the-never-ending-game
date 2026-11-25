# The Big Mix-Up (session 88, Lumi bored of its island). Once an island morning Lumi finds a spell in an old book
# and tries it on the friends gathered round: "SWAPSIE!" POOF: every friend comes out of a cloud of sparkles in
# somebody else's body. Pigs scuttle sideways as crabs, the crabs are woolly sheep, the sheep wobble as jelly blobs,
# the blobs are piglets; they stare at themselves, scream, run about in circles. Lumi flips the pages for the
# undo... and POOF, everyone is back. The species keep their names; a creature is only lent another body, and a
# state file brings everyone home should the game stop in the middle of it.
isdefined(Main, :MIXUP) || Core.eval(Main, :(const MIXUP = Dict{Symbol,Any}()))
const NG = NeverendingGame
const MX = Main.MIXUP
isdefined(Main, :LUMI_PARTY) || Core.eval(Main, :(const LUMI_PARTY = Dict{Symbol,Float64}()))
party_free(w) = w.t >= get(Main.LUMI_PARTY, :until, -Inf)
claim_party!(w, secs) = (Main.LUMI_PARTY[:until] = w.t + secs; nothing)

const SPECIES = ("Snootle", "Crabbit", "Fluffkin", "Blorbo")
const T_GATHER = 5.0; const T_SPELL = 3.0; const T_MIXED = 22.0; const T_AFTER = 4.0
const NPUFF = 120
const EVENTS = (:follow, :sleep, :circle, :boing, :boing_walk, :choir, :conga, :hide, :found, :freeze, :flight,
                :paint, :giant, :egg, :lesson, :soar, :snowman, :storm, :build, :tinker, :toadstool, :blossom,
                :swing, :bottle, :leaves, :pumpkin, :hail, :cannonball, :waterfight, :mixup)
const PULL = (:fish, :pebble, :feel, :sunset, :tag, :present, :fetch, :beachcomb, :sunbathe, :flowers, :splash)
const SHOUTS = Dict("Crabbit" => ("Why am I SIDEWAYS?!", "I've got CLAWS!", "*snip snip* ...uh oh."),
                    "Fluffkin" => ("I'M SO FLUFFY!", "Baa?! BAA?!", "Who put me in a cloud?!"),
                    "Blorbo" => ("I'm all WOBBLY!", "*squish* ...help!", "I can see through my tummy!"),
                    "Snootle" => ("OINK?! Did I just oink?", "Look at my SNOUT!", "I've got a curly tail!"))
const BACK = ("Phew!", "My own legs!", "...I kind of liked it.", "Never again, Lumi!", "Again! Again!")

push!(NG.BUSY_GOALS, :mixup)

mutable struct MixUp <: System
    state::Symbol          # :idle :gather :spell :mixed :after
    t0::Float64
    day::Int
    crew::Vector{Int32}
end
MixUp() = MixUp(:idle, 0.0, -1, Int32[])

lumi_of(w) = (i = findfirst(c -> c.name == "Lumi", w.creatures); i === nothing ? nothing : w.creatures[i])
state_file(game) = joinpath(game.paths.state, "mixup.json")

"Everyone lent another body goes home (also after a game that stopped in the middle of it)."
function restore!(game)
    w = game.world
    was = get(MX, :was, Dict{Int32,String}())
    if isempty(was) && game.dash !== nothing && isfile(state_file(game))
        for (k, v) in NG.read_json(state_file(game))
            was[parse(Int32, k)] = v
        end
    end
    for (id, sp) in was
        c = NG.creature(w, id)
        c === nothing || (c.species = sp)
    end
    MX[:was] = Dict{Int32,String}()
    game.dash !== nothing && isfile(state_file(game)) && rm(state_file(game))
end

function puffs!(game)
    haskey(MX, :puff) && MX[:puff].parent !== nothing && return
    sc = game.stage.scene
    for p in filter(p -> haskey(p.attributes, :name) && p.attributes[:name][] === :mixup_puff, sc.plots)
        delete!(sc, p)
    end
    MX[:puff] = meshscatter!(sc, fill(Point3f(0, 0, -50), NPUFF); marker = Sphere(Point3f(0), 1f0), markersize = fill(Vec3f(0), NPUFF),
                             color = [isodd(i) ? RGBf(1.0, 0.85, 0.98) : RGBf(0.9, 0.85, 1.0) for i in 1:NPUFF], name = :mixup_puff)
end

"Sparkle clouds round every friend for 1.4 s after `MX[:poof]`."
function draw_puffs!(s::MixUp, w)
    t0 = get(MX, :poof, -Inf)
    u = Float32(w.t - t0)
    if u < 0 || u > 1.4f0
        get(MX, :puff_shown, true) && Makie.update!(MX[:puff]; arg1 = fill(Point3f(0, 0, -50), NPUFF), markersize = fill(Vec3f(0), NPUFF))
        MX[:puff_shown] = false
        return
    end
    ps = Point3f[]; ms = Vec3f[]
    for id in s.crew, k in 1:8
        c = NG.creature(w, id); c === nothing && continue
        a = 2f0 * Float32(pi) * k / 8 + 0.9f0 * id
        r = 0.25f0 + 0.8f0 * u
        push!(ps, c.pos + Point3f(r * cos(a), r * sin(a), 0.45f0 + 0.5f0 * u + 0.15f0 * sin(3a)))
        push!(ms, Vec3f(max(0f0, 0.3f0 * (1 - u / 1.4f0))))
    end
    while length(ps) < NPUFF; push!(ps, Point3f(0, 0, -50)); push!(ms, Vec3f(0)); end
    Makie.update!(MX[:puff]; arg1 = ps[1:NPUFF], markersize = ms[1:NPUFF])
    MX[:puff_shown] = true
end

function start_mixup!(s::MixUp, game)
    w = game.world
    me = lumi_of(w)
    (me === nothing || me.controlled || me.goal.kind in EVENTS || me.action === :sleep) && return false
    free(x) = !x.controlled && x.action !== :sleep && x.goal.kind ∉ EVENTS && (x.goal.kind ∉ NG.BUSY_GOALS || x.goal.kind in PULL) &&
              x !== me && x.species in SPECIES
    cs = sort([x for x in w.creatures if free(x) && hypot(x.pos[1] - me.pos[1], x.pos[2] - me.pos[2]) < 40];
              by = x -> hypot(x.pos[1] - me.pos[1], x.pos[2] - me.pos[2]))
    cs = cs[1:min(end, 9)]
    length(Set(x.species for x in cs)) < 3 && return false        # it needs at least three kinds of body to swap
    NG.on_land(w.island, me.pos[1], me.pos[2]; margin = 0.4) || return false
    s.crew = Int32[x.id for x in cs]
    n = length(cs)
    for (i, x) in enumerate(cs)
        a = 2f0 * Float32(pi) * (i - 1) / n
        q = (me.pos[1] + 2.6f0 * cos(a), me.pos[2] + 2.6f0 * sin(a))
        NG.on_land(w.island, q[1], q[2]; margin = 0.2) || (q = (me.pos[1] + 1.6f0 * cos(a), me.pos[2] + 1.6f0 * sin(a)))
        NG.leave_interactions!(w, x)
        x.goal = NG.Goal(:mixup, NG.ground(w.island, q), :idle, 120.0, w.t + 120, false, 0, true)
    end
    NG.leave_interactions!(w, me)
    me.goal = NG.Goal(:mixup, me.pos, :think, 120.0, w.t + 120, true, 0, false)
    s.state = :gather; s.t0 = w.t
    MX[:log] = Tuple{Float64,Symbol}[(w.t, :start)]
    NG.say!(w, me, "Ooh, a spell book! Everyone, come and see!"; duration = 3.0)
    NG.emit!(w, :mixup_start; n = n)
    return true
end

"Lend every friend the next kind of body along (a different one for each, as far as the kinds go)."
function swap!(s::MixUp, game)
    w = game.world
    kinds = [k for k in SPECIES if any(id -> NG.creature(w, id).species == k, s.crew)]
    was = Dict{Int32,String}()
    for id in s.crew
        c = NG.creature(w, id)
        was[id] = c.species
        c.species = kinds[mod1(findfirst(==(c.species), kinds) + 1, length(kinds))]
    end
    MX[:was] = was
    game.dash !== nothing && NG.write_json(state_file(game), Dict(string(k) => v for (k, v) in was))
    MX[:poof] = w.t
    push!(MX[:log], (w.t, :poof))
    NG.emit!(w, :mixup_swap; n = length(was))
end

function NG.step!(s::MixUp, game, dt)
    game.stage === nothing && return
    puffs!(game)
    w = game.world
    el = w.t - s.t0
    me = lumi_of(w)
    if s.state === :idle
        film = get(MX, :film, false)
        testing = game.tests !== nothing && NG.running(game.tests)
        busy_game = game.minigame !== nothing && !(game.minigame isa NG.JumpIn)
        day = floor(Int, w.t / w.day_length)
        if (film || day != s.day && 9.0 < 24 * NG.daytime(w) < 10.5) && !testing && !busy_game && w.t >= get(MX, :try_at, -Inf)
            MX[:try_at] = w.t + 5
            if (film || party_free(w)) && start_mixup!(s, game)
                s.day = day; MX[:film] = false; claim_party!(w, 40)
            end
        end
        draw_puffs!(s, w)
        return
    end
    # the crew stays (another event that took one gets it back, like the hail's recall)
    for id in s.crew
        x = NG.creature(w, id)
        (x === nothing || x.controlled) && continue
        x.goal.kind === :mixup || (NG.leave_interactions!(w, x); x.goal = NG.Goal(:mixup, x.pos, :idle, 120.0, w.t + 120, true, 0, false))
        x.goal.until = w.t + 60
    end
    me === nothing || me.controlled || me.goal.kind === :mixup || (me.goal = NG.Goal(:mixup, me.pos, :think, 120.0, w.t + 120, true, 0, false))
    me === nothing || (me.goal.until = w.t + 60)
    if s.state === :gather
        for id in s.crew
            x = NG.creature(w, id)
            x.goal.arrived && me !== nothing && (x.yaw = atan(me.pos[2] - x.pos[2], me.pos[1] - x.pos[1]) - NG.species_of(x).heading)
        end
        if el >= get(MX, :t_gather, T_GATHER)
            s.state = :spell; s.t0 = w.t
            me === nothing || (NG.say!(w, me, "Ahem. Abracadabra... SWAPSIE!"; duration = 2.4); me.goal.action = :proud; me.action = :proud)
            push!(MX[:log], (w.t, :spell))
        end
    elseif s.state === :spell
        if el >= T_SPELL
            swap!(s, game)
            s.state = :mixed; s.t0 = w.t
            me === nothing || NG.say!(w, me, "...Oops."; duration = 2.0)
            for (k, id) in enumerate(s.crew)
                x = NG.creature(w, id)
                x.goal = NG.Goal(:mixup, x.pos, :gasp, 120.0, w.t + 120, true, 0, false); x.action = :gasp
                MX[Symbol(:shout_, id)] = w.t + 1.0 + 0.7k
            end
        end
    elseif s.state === :mixed
        for (k, id) in enumerate(s.crew)
            x = NG.creature(w, id)
            t = get(MX, Symbol(:shout_, id), Inf)
            if w.t >= t
                lines = get(SHOUTS, x.species, ("WHAT?!",))
                NG.say!(w, x, lines[mod1(k + floor(Int, el / 6), length(lines))]; duration = 2.0)
                MX[Symbol(:shout_, id)] = w.t + 5.5 + 1.5rand(w.rng)
                # and off it runs in a panic, somewhere near
                if me !== nothing
                    a = 2f0 * Float32(pi) * rand(w.rng, Float32)
                    q = (me.pos[1] + (2f0 + 2.5f0 * rand(w.rng, Float32)) * cos(a), me.pos[2] + (2f0 + 2.5f0 * rand(w.rng, Float32)) * sin(a))
                    NG.on_land(w.island, q[1], q[2]; margin = 0.2) &&
                        (x.goal = NG.Goal(:mixup, NG.ground(w.island, q), :run, 120.0, w.t + 120, false, 0, true))
                end
            end
            x.goal.arrived && x.goal.action !== :gasp && (x.goal.action = :jump)
        end
        if me !== nothing && el > get(MX, :t_mixed, T_MIXED) - 6 && !haskey(MX, :flip)
            MX[:flip] = true
            NG.say!(w, me, "Hang on, hang on, there's an undo on the next page..."; duration = 3.4)
            me.goal.action = :think
        end
        if el >= get(MX, :t_mixed, T_MIXED)
            restore!(game)
            delete!(MX, :flip)
            MX[:poof] = w.t
            push!(MX[:log], (w.t, :poof))
            s.state = :after; s.t0 = w.t
            me === nothing || (NG.say!(w, me, "SWAPSIE-BACKSIE! ...There."; duration = 2.4); me.goal.action = :proud; me.action = :proud)
            for (k, id) in enumerate(s.crew)
                x = NG.creature(w, id)
                x.goal = NG.Goal(:mixup, x.pos, :laugh, 60.0, w.t + 60, true, 0, false); x.action = :laugh
                k <= 3 && NG.say!(w, x, BACK[mod1(k + s.day, length(BACK))]; duration = 2.2)
            end
        end
    elseif s.state === :after
        if el >= T_AFTER
            for id in s.crew
                x = NG.creature(w, id)
                x === nothing || x.controlled || x.goal.kind !== :mixup || NG.choose_goal!(x, w)
            end
            me === nothing || me.controlled || me.goal.kind !== :mixup || NG.choose_goal!(me, w)
            empty!(s.crew); s.state = :idle
            NG.emit!(w, :mixup_end)
        end
    end
    draw_puffs!(s, w)
end

"The view: one low side of Lumi and the ring of friends, the clearest of eight, chosen once per mix-up."
function mixup_view(w)
    get!(MX, :view) do
        me = lumi_of(w)
        c = me.pos
        target = c + Point3f(0, 0, 0.6f0)
        best = (Inf32, c + Point3f(0, -6.5f0, 2.2f0))
        for k in 0:7
            a = 2f0 * Float32(pi) * k / 8
            q = (c[1] + 6.5f0 * cos(a), c[2] + 6.5f0 * sin(a))
            NG.on_land(w.island, q[1], q[2]; margin = 0.1) || continue
            eye = Point3f(q[1], q[2], NG.terrain_height(w.island, q[1], q[2]) + 2.2f0)
            o = NG.obstruction(w, eye, target)
            o < best[1] && (best = (o, eye))
        end
        (best[2], target)
    end
end

function mixup_group(w)
    s = MX[:sys]
    s.state === :idle && return nothing
    me = lumi_of(w)
    (me === nothing || me.controlled) && return nothing
    return (me.id, Point3f[me.pos], mixup_view(w))
end

function NG.start!(s::MixUp, game)
    MX[:sys] = s
    delete!(MX, :puff); delete!(MX, :view); MX[:puff_shown] = true
    restore!(game)
    MX[:start] = () -> (delete!(MX, :view); start_mixup!(s, game))
    moment = w -> s.state === :idle ? nothing : (m = lumi_of(w); m === nothing ? nothing : m.id)
    NG.CAMERA_MOMENTS["mixup"] = moment
    isdefined(Main, :BIG_MOMENTS) || Core.eval(Main, :(const BIG_MOMENTS = Dict{String,Any}()))
    Main.BIG_MOMENTS["mixup"] = moment
    NG.CAMERA_GROUPS["mixup"] = mixup_group
end

function NG.stop!(s::MixUp, game)
    delete!(NG.CAMERA_MOMENTS, "mixup"); delete!(NG.CAMERA_GROUPS, "mixup")
    isdefined(Main, :BIG_MOMENTS) && delete!(Main.BIG_MOMENTS, "mixup")
    restore!(game)
    if s.state !== :idle
        for id in s.crew
            x = NG.creature(game.world, id)
            x === nothing || x.controlled || x.goal.kind !== :mixup || NG.choose_goal!(x, game.world)
        end
        empty!(s.crew); s.state = :idle
    end
    haskey(MX, :puff) && MX[:puff].parent !== nothing && delete!(MX[:puff].parent, MX[:puff])
    delete!(MX, :puff)
end

register!(MixUp())
