# Friends sleep like friends (session 94, todo #496, the perfectionist: "piglets and crabs sleep standing with their
# eyes open, like a freeze-frame of statues"). The made-over bodies have legs of their own and the engine's sleep
# pose only squashes and rolls the body a little, so a sleeping pig stood on four straight legs. Now a sleeper lies
# down: the whole body sinks by its leg length (the legs fold away into the grass), eased over a second and a half,
# and gets up again the same way when it wakes.
isdefined(Main, :SLEEPERS) || Core.eval(Main, :(const SLEEPERS = Dict{Symbol,Any}()))
const NG = NeverendingGame
const SLP = Main.SLEEPERS

"How far each kind sinks to lie down (its legs' length, m); blobs and Lumi have their own sleep."
const SINK = Dict("Snootle" => 0.2f0, "Fluffkin" => 0.24f0, "Crabbit" => 0.16f0)
const DOWN_T = 1.5f0         # s to lie down
const UP_T = 0.6f0           # s to get up

struct Sleepers <: System end

"Closed eyes for the made-over bodies (their eyes are painted into the mesh): a lid over each eye, in the body part's
frame (forward, left, up; profiled s94: the pig's eyes sit above the snout, the sheep's on the dark face)."
const LIDS_OK = true         # the piglets' lids sit on their eyes (media/s94/lids6.png, s94)
const LIDS = Dict("Snootle" => ((0.53f0, 0.18f0, 0.66f0), RGBf(0.93, 0.6, 0.63)),
                  "Fluffkin" => ((0.55f0, 0.14f0, 0.7f0), RGBf(0.13, 0.12, 0.14)))

function lids!(game, lying)
    sc = game.stage.scene
    if !(haskey(SLP, :lids) && SLP[:lids].parent === sc)
        for p in filter(p -> haskey(p.attributes, :name) && p.attributes[:name][] === :sleeper_lids, copy(sc.plots))
            delete!(sc, p)                       # (left by the last load: names must be unique, s94)
        end
        SLP[:lids] = meshscatter!(sc, [Point3f(0, 0, -50)]; marker = Sphere(Point3f(0), 1f0), markersize = [Vec3f(0)],
                                  rotation = [Makie.Quaternionf(0, 0, 0, 1)], color = [RGBf(0, 0, 0)], name = :sleeper_lids)
    end
    w = game.world
    ps = Point3f[]; ms = Vec3f[]; rs = Makie.Quaternionf[]; cs = RGBf[]
    for c in w.creatures
        get(lying, c.id, 0f0) > 0.6f0 || continue
        lid = get(LIDS, c.species, nothing); lid === nothing && continue
        sp = NG.species_of(c)
        out = [(Point3f[], Makie.Quaternionf[], Vec3f[]) for _ in sp.parts]
        NG.pose_parts!(out, sp, c.pos, NG.drawn_yaw(c), c.action, c.phase, c.mood, c.extra, c.seed, NG.anim_time(w))
        P, q, sc3 = out[1][1][1], out[1][2][1], out[1][3][1]
        (x, y, z), col = lid
        for side in (1f0, -1f0)
            push!(ps, P + q * (sc3 .* Vec3f(x, side * y, z))); push!(rs, q); push!(ms, Vec3f(0.03f0, 0.062f0, 0.05f0)); push!(cs, col)
        end
    end
    if isempty(ps)
        get(SLP, :lids_shown, true) && Makie.update!(SLP[:lids]; arg1 = [Point3f(0, 0, -50)], markersize = [Vec3f(0)],
                                                     rotation = [Makie.Quaternionf(0, 0, 0, 1)], color = [RGBf(0, 0, 0)])
        SLP[:lids_shown] = false
    else
        Makie.update!(SLP[:lids]; arg1 = ps, markersize = ms, rotation = rs, color = cs); SLP[:lids_shown] = true
    end
end

ease(u) = (u = clamp(u, 0f0, 1f0); u * u * (3 - 2u))

function NG.step!(::Sleepers, game, dt)
    w = game.world
    lying = get!(() -> Dict{Int32,Float32}(), SLP, :lying)::Dict{Int32,Float32}   # how far down (0..1) each one is
    for c in w.creatures
        d = get(SINK, c.species, 0f0)
        d > 0 || continue
        c.controlled && (delete!(lying, c.id); continue)
        k = get(lying, c.id, 0f0)
        if c.action === :sleep
            k == 0 && NG.emit!(w, :lie_down; who = c.name)                    # (new on the island since s94)
            k = min(1f0, k + Float32(dt) / DOWN_T)
        elseif k > 0
            k == 1 && NG.emit!(w, :get_up; who = c.name)
            k = max(0f0, k - Float32(dt) / UP_T)
        else
            continue
        end
        g = NG.terrain_height(w.island, c.pos[1], c.pos[2])
        c.pos = Point3f(c.pos[1], c.pos[2], g - d * ease(k))
        k > 0 ? (lying[c.id] = k) : delete!(lying, c.id)
    end
    game.stage === nothing || !(LIDS_OK || get(SLP, :lids_try, false)) || lids!(game, lying)
end

NG.start!(::Sleepers, game) = (SLP[:lying] = Dict{Int32,Float32}(); delete!(SLP, :lids); SLP[:lids_shown] = true; nothing)

function NG.stop!(::Sleepers, game)
    haskey(SLP, :lids) && SLP[:lids].parent !== nothing && delete!(SLP[:lids].parent, SLP[:lids])
    delete!(SLP, :lids)
end

register!(Sleepers())
