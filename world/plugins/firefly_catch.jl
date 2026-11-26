# Firefly catch: steer Lumi (W/S walk, A/D turn, shift runs) and catch the glowing fireflies before time runs out.
# A start card says what to do; the clock starts with the first key. Every key lights up in the key bar,
# every catch bursts into sparks, the end card shows the time, the best and "R plays again".
const NG = NeverendingGame

# best scores survive restarts (state/bests.json, shared by the mini games); a quiet copy never writes
bests_file(game) = joinpath(game.paths.state, "bests.json")
load_best(game, key, default) = (f = bests_file(game); isfile(f) ? Float64(get(NG.read_json(f), key, default)) : Float64(default))
function save_best!(game, key, v)
    game.dash === nothing && return
    # a UI test's round is not the player's best (tests put P[:best] back, not this file)
    game.tests !== nothing && NG.running(game.tests) && return
    f = bests_file(game)
    d = isfile(f) ? NG.read_json(f) : Dict{String,Any}()
    d[key] = v
    NG.write_json(f, d)
end
const N_FLIES = 8
const TIME_LIMIT = 60.0
const CATCH_RADIUS = 1.0f0
const FLEE_RADIUS = 2.0f0         # flies drift away when Lumi comes this close
const FLEE_SPEED = 0.45f0         # m/s: well below Lumi's walk, so W alone catches up (0.9 made a first play lose)
const MAX_LEVEL = 4               # each win makes the next round's fireflies quicker (a reason to play twice, review #18)
level(game) = Int(get!(() -> round(Int, load_best(game, "firefly_level", 1)), P, :level))
flee_speed(game) = FLEE_SPEED * (1f0 + 0.25f0 * (level(game) - 1))
const N_SPARKS = 24
const SPARK_TIME = 0.8
const PARK = Point3f(0, 0, -50)
const KEY_NAMES = ("W", "A", "S", "D", "Shift", "R")
const KEYS = (Makie.Keyboard.w, Makie.Keyboard.a, Makie.Keyboard.s, Makie.Keyboard.d, Makie.Keyboard.left_shift, Makie.Keyboard.r)
# the key bar sits in the bottom-left corner: in the middle it covered the rivals' name tags (tester s45)
const KEY_X = (0.045, 0.09, 0.135, 0.18, 0.24, 0.3)
const KEY_OFF = RGBAf(0.08, 0.09, 0.12, 0.72)
const KEY_ON = RGBAf(0.95, 0.75, 0.25, 0.95)

# Plots cannot be deleted from the traced scene: they are created once per process and reused,
# kept in Main so a plugin hot reload finds them again. Bump the version to rebuild them.
const PLOTS_VERSION = 5
isdefined(Main, :FIREFLY_PLOTS) || Core.eval(Main, :(const FIREFLY_PLOTS = Dict{Symbol,Any}()))
const P = Main.FIREFLY_PLOTS

mutable struct FireflyCatch <: MiniGame
    jump::NG.JumpIn
    flies::Vector{Point3f}        # each fly's home point (it wobbles around it)
    caught::Vector{Bool}
    state::Symbol                 # :ready (start card), :playing, :over (end card)
    t::Float64                    # play time
    t_state::Float64              # time in the current state
    score::Int
    lumi::Int32
    spark_at::Point3f
    spark_t::Float64
    flash::Float64                # HUD flash after a catch
end

function FireflyCatch(game)
    j = NG.JumpIn(game)
    FireflyCatch(j, Point3f[], Bool[], :ready, 0.0, 0.0, 0, j.id, PARK, 99.0, 0.0)
end

NG.game_title(::Type{FireflyCatch}) = "Firefly catch (WASD)"
NG.game_description(::Type{FireflyCatch}) =
    "Catch all $N_FLIES glowing fireflies in $(Int(TIME_LIMIT)) seconds. W/S walk, A/D turn, Shift runs, R restarts."

fly_pos(base::Point3f, t, i) = base + Point3f(0.5f0 * sin(1.3f0 * t + i), 0.5f0 * cos(0.9f0 * t + 2i), 0.35f0 * sin(2.1f0 * t + i))

function ensure_plots!(game)
    get(P, :version, 0) == PLOTS_VERSION && return
    for k in collect(keys(P))
        k === :version || k === :best || delete!(P, k)   # old plots stay parked and hidden in the scene
    end
    scene = game.stage.scene
    # yellow-green firefly light (perfectionist-0094: they read as white pebbles). Live they are unlit colour, the
    # Emission only in quiet traced copies: in the raster an Emission mesh draws as a clipped white area light (s51)
    glow = NG.Hikari.Emission(color = (0.8, 1.0, 0.3), strength = 6.0)
    traced = (game.dash === nothing ? (; material = glow) : (;))
    P[:flies] = meshscatter!(scene, fill(PARK, N_FLIES); marker = Sphere(Point3f(0), 1f0), markersize = 0.24f0,
        color = RGBf(0.78, 1, 0.28), traced..., shading = NoShading, visible = false)
    # a soft glow round each fly, so it reads as a light at noon too (perfectionist-0055: "plain white
    # puffs"): three thin shells per fly, fading out (one big shell shows a hard ring)
    P[:halo] = meshscatter!(scene, fill(PARK, 3N_FLIES); marker = Sphere(Point3f(0), 1f0, ), markersize = halo_sizes(1f0),
        color = repeat([RGBAf(0.75, 1, 0.3, 0.22), RGBAf(0.7, 0.95, 0.25, 0.11), RGBAf(0.65, 0.9, 0.2, 0.05)], N_FLIES),
        shading = NoShading, transparency = true, visible = false)
    # a thin beam of light from the ground up to each fly: you can see where they are from across the island
    P[:beams] = meshscatter!(scene, fill(PARK, N_FLIES); marker = Cylinder(Point3f(0), Point3f(0, 0, 1), 1f0),
        markersize = fill(Vec3f(0.035, 0.035, 3), N_FLIES), color = RGBAf(1, 0.9, 0.5, 0.55),
        material = NG.Hikari.Emission(color = (1.0, 0.85, 0.45), strength = 2.0), visible = false)
    P[:sparks] = meshscatter!(scene, fill(PARK, N_SPARKS); marker = Sphere(Point3f(0), 1f0), markersize = 0.07f0,
        color = RGBf(1, 0.97, 0.7), material = NG.Hikari.Emission(color = (1.0, 0.95, 0.6), strength = 8.0), visible = false)
    ov = game.stage.overlay
    P[:hud] = textlabel!(ov, Point2f(0.5, 0.93); space = :relative, text = " ", fontsize = 24,
        text_color = RGBf(1, 0.95, 0.6), background_color = RGBAf(0.08, 0.09, 0.12, 0.75),
        strokewidth = 0, padding = 10, cornerradius = 8, visible = false)
    P[:card] = textlabel!(ov, Point2f(0.5, 0.64); space = :relative, text = " ", fontsize = 22, justification = :center,
        text_color = RGBf(1, 0.97, 0.85), background_color = RGBAf(0.07, 0.08, 0.13, 0.86),
        strokewidth = 0, padding = 22, cornerradius = 14, visible = false)
    for (i, name) in enumerate(KEY_NAMES)
        P[Symbol(:key_, i)] = textlabel!(ov, Point2f(KEY_X[i], 0.05); space = :relative, text = name, fontsize = 17,
            text_color = RGBf(1, 1, 1), background_color = KEY_OFF, strokewidth = 0, padding = 9, cornerradius = 6,
            visible = false)
    end
    P[:version] = PLOTS_VERSION
end

"Sizes of the three glow shells of every fly."
halo_sizes(k) = repeat(Float32[0.42, 0.62, 0.9] .* k, N_FLIES)
const PLOT_KEYS = (:flies, :halo, :beams, :sparks, :hud, :card, (Symbol(:key_, i) for i in 1:length(KEY_NAMES))...)
show_plots!(on::Bool) = foreach(k -> (P[k].visible[] = on), PLOT_KEYS)

const START_TEXT = """Firefly catch
Catch all $N_FLIES glowing fireflies in $(Int(TIME_LIMIT)) seconds.
Follow the light beams. Fireflies drift away when you come close!

W / S  walk      A / D  turn      Shift  run

Press W to start"""

"""
A chase camera for playing: always behind Lumi so W goes "into" the screen, rising over
trees instead of swinging around them (the follow view turns around Lumi, which loses the player).
"""
# every view looks down at most ~30° (s68: the two high ones, 34° and 54°, were taken whenever trees stood
# behind Lumi, and the perfectionist played all three mini games looking down on a flat green map):
# blocked low views turn to the side instead of rising
const CHASE_VIEWS = ((0f0, 7f0, 3.2f0), (0f0, 5f0, 2f0), (0f0, 4f0, 1.3f0), (0.35f0, 6f0, 3f0), (-0.35f0, 6f0, 3f0),
    (0.35f0, 4.5f0, 1.5f0), (-0.35f0, 4.5f0, 1.5f0), (0f0, 6.5f0, 3.4f0), (0.7f0, 5f0, 2f0), (-0.7f0, 5f0, 2f0),
    (1.1f0, 5.5f0, 2.8f0), (-1.1f0, 5.5f0, 2.8f0), (0f0, 4f0, 2.2f0))
const CHASE_K = Ref(1)    # the view in use: kept while it stays about as good as the best, so the camera does not flicker

"""
Trees and bushes between the eye and Lumi, as solid cylinders (pines are wide low down, which the engine's
two crown balls miss): samples along the line of sight and the eye itself, 1 per sample inside a tree.
"""
function trees_in_view(w, eye, target)
    o = 0f0
    for s in (0f0, 0.12f0, 0.25f0, 0.38f0, 0.5f0, 0.62f0, 0.74f0, 0.85f0)
        q = eye + s * (target - eye)
        for p in w.props
            if p.kind === :tree
                r = 1.6f0 * p.scale
                (q[1] - p.pos[1])^2 + (q[2] - p.pos[2])^2 < r^2 && p.pos[3] + 0.6f0 * p.scale < q[3] < p.pos[3] + 4.6f0 * p.scale && (o += 1f0)
            elseif p.kind === :bush    # a big bush in front hid Lumi completely (s39, media/s39-peek.png)
                r = 0.95f0 * p.scale
                (q[1] - p.pos[1])^2 + (q[2] - p.pos[2])^2 < r^2 && q[3] < p.pos[3] + 1.4f0 * p.scale && (o += 1f0)
            end
        end
    end
    return o
end

function chase_camera!(game, c, dt; snap = false)
    w = game.world
    target = c.pos + Point3f(0, 0, 0.6f0)
    a = c.yaw + NG.species_of(c).heading + Float32(pi)
    view(k) = (v = CHASE_VIEWS[k]; target + Point3f(v[2] * cos(a + v[1]), v[2] * sin(a + v[1]), v[3]))
    best = (Inf32, 1)
    for k in eachindex(CHASE_VIEWS)        # behind and a bit above, then lower, slightly turned, higher
        o = (NG.obstruction(w, view(k), target) + trees_in_view(w, view(k), target)) + 0.01f0 * k
        o < best[1] && (best = (o, k))
        o <= 0.01f0 * k && break
    end
    keep = CHASE_K[] <= length(CHASE_VIEWS) && (NG.obstruction(w, view(CHASE_K[]), target) + trees_in_view(w, view(CHASE_K[]), target)) + 0.01f0 * CHASE_K[] <= best[1] + 0.3f0
    keep || (CHASE_K[] = best[2])
    eye = view(CHASE_K[])
    k = snap ? 1f0 : Float32(1 - exp(-3dt / 0.45))
    game.rig.mode = :fixed
    game.rig.target += k * (target - game.rig.target)
    game.rig.eye = orbit_lerp(game.rig.eye, eye, game.rig.target, k)
end

"""
The eye moved a step `k` towards `eye`, around `target`: angle, distance and height each eased on their own,
and never more than 30° above the target. A straight slide cut a chord past Lumi's head when it turned
sharply, and the camera looked down 44° for a moment (s68, hide and seek).
"""
function orbit_lerp(cur::Point3f, eye::Point3f, target::Point3f, k::Float32)
    c = cur - target; e = eye - target
    rc = hypot(c[1], c[2]); re = hypot(e[1], e[2])
    ac = rc < 0.3f0 ? atan(e[2], e[1]) : atan(c[2], c[1])
    ae = atan(e[2], e[1])
    da = mod(ae - ac + Float32(pi), 2f0 * Float32(pi)) - Float32(pi)
    a = ac + k * da
    r = max(rc, 0.3f0) + k * (re - max(rc, 0.3f0))
    h = min(c[3] + k * (e[3] - c[3]), 0.577f0 * r)
    return target + Point3f(r * cos(a), r * sin(a), h)
end

"Can a creature of radius `r` walk straight from `a` to `b` (land all the way, no trunk, bush or rock)?"
function open_line(w, a, b, r)
    n = max(2, ceil(Int, norm(Vec2f(b[1] - a[1], b[2] - a[2])) / 0.4f0))
    all(0:n) do k
        x, y = a[1] + (b[1] - a[1]) * k / n, a[2] + (b[2] - a[2]) * k / n
        NG.on_land(w.island, x, y; margin = 0.6f0) && NG.walkway_height(x, y) === nothing &&
            !any(p -> haskey(NG.SOLID_FOOTPRINT, p.kind) && hypot(p.pos[1] - x, p.pos[2] - y) < NG.SOLID_FOOTPRINT[p.kind] * p.scale + r + 0.3f0, w.props)
    end
end

"Under a big tree's crown (2.6 × scale): Lumi chasing a fly there was a sliver between two crowns that filled 80% of the chase view (perfectionist-0070)."
under_crown(w, q) = any(p -> p.kind === :tree && hypot(p.pos[1] - q[1], p.pos[2] - q[2]) < 2.6f0 * p.scale, w.props)

"Is `q` within `gap` of a solid prop's footprint (trunk, bush, rock)?"
near_solid(w, q, gap) = any(p -> haskey(NG.SOLID_FOOTPRINT, p.kind) &&
                                 hypot(p.pos[1] - q[1], p.pos[2] - q[2]) < NG.SOLID_FOOTPRINT[p.kind] * p.scale + gap, w.props)

"""
Three flies in a chain ahead of `c`, each a straight open walk from the one before (W alone reaches
them). A blocked spot tries the next distance and wider angles, so a cramped start still gets three.
"""
function near_flies(w, c)
    out = Point3f[]
    from, last_d = c.pos, 1f0
    for d in (3.5f0, 4.5f0, 6f0, 7f0, 8.5f0, 10f0, 11.5f0)
        length(out) == 3 && break
        d < last_d + 2f0 && continue
        for da in (0.2f0, -0.3f0, 0.5f0, -0.6f0, 0.9f0, -1.0f0, 1.4f0, -1.5f0, 1.9f0, -2.0f0)
            a = c.yaw + (length(out) == 1 ? -da : da)
            q = NG.ground(w.island, (c.pos[1] + d * cos(a), c.pos[2] + d * sin(a)))
            if open_line(w, from, q, NG.body_radius(NG.species_of(c)))
                push!(out, q + Point3f(0, 0, 0.9f0)); from = q; last_d = d
                break
            end
        end
    end
    return out
end

function reset!(m::FireflyCatch, game)
    w = game.world
    c = NG.creature(w, m.lumi)
    # out on the pier or in a nook W leads nowhere: start in the open meadow (the berry race's start line)
    if NG.walkway_height(c.pos[1], c.pos[2]) !== nothing || NG.free_run(w, c, c.yaw) < 3
        br = get(game.plugins, "berry_race", nothing)
        s = br === nothing ? nothing : Base.invokelatest(br.mod.start_spot, w)
        s === nothing || (c.pos = s[1]; c.yaw = atan(s[1][2] - s[2].pos[2], s[1][1] - s[2].pos[1]))   # back to the bush
    end
    NG.face_open!(w, c)    # woken in its nook at night Lumi faces a bush: W would push into it
    # the first three flies wait just ahead (W alone reaches them), the rest all over the island
    # (no three in reach from here: the meadow start line, where there is room; a far first fly lost first plays)
    m.flies = near_flies(w, c)
    if length(m.flies) < 3
        br = get(game.plugins, "berry_race", nothing)
        s = br === nothing ? nothing : Base.invokelatest(br.mod.start_spot, w)
        if s !== nothing
            p0, y0 = c.pos, c.yaw
            c.pos = s[1]; c.yaw = atan(s[1][2] - s[2].pos[2], s[1][1] - s[2].pos[1]); NG.face_open!(w, c)
            there = near_flies(w, c)
            length(there) > length(m.flies) ? (m.flies = there) : (c.pos = p0; c.yaw = y0)
        end
    end
    tries = 0
    while length(m.flies) < N_FLIES
        tries += 1
        p = NG.random_land_point(w; rmax = 0.8w.island.radius)
        d = norm(Vec2f(p[1] - c.pos[1], p[2] - c.pos[2]))
        # the rest within 15 m, so the last ones are not a 13 m walk with 14 s left (perfectionist-0103)
        d > 4 && (d < 15 || tries > 600) && !near_solid(w, p, 1.1f0) && !under_crown(w, p) &&
            push!(m.flies, p + Point3f(0, 0, 0.9f0))
    end
    m.caught = fill(false, N_FLIES)
    m.state = :ready; m.t = 0.0; m.t_state = 0.0; m.score = 0; m.spark_t = 99.0; m.flash = 0.0
    lv = level(game)
    Makie.update!(P[:card]; text = lv == 1 ? START_TEXT :
        replace(START_TEXT, "Firefly catch\n" => "Firefly catch  ·  Level $lv\nThe fireflies are quicker now!\n"))
    P[:card].visible[] = true
end

"Show or hide the creatures' name tags and speech (only when it changes: no update every frame)."
function name_tags!(game, on::Bool)
    l = game.stage.labels
    l === nothing || l.visible[] == on || (l.visible[] = on)
end

# The start card's view: the berry race's low look over Lumi's shoulder, Lumi under the card (tester s45:
# the chase view on the start card showed the card and foliage, Lumi hidden behind them). W rises to the chase view.
function start_view!(game, c, dt; snap = false)
    br = get(game.plugins, "berry_race", nothing)
    br === nothing && return chase_camera!(game, c, dt; snap)
    Base.invokelatest(br.mod.chase_camera!, game, c, dt; snap, low = true)
end

function NG.start!(m::FireflyCatch, game)
    NG.start!(m.jump, game)
    ensure_plots!(game)
    show_plots!(true)
    reset!(m, game)
    start_view!(game, NG.creature(game.world, m.lumi), 0.0; snap = true)
end


# ── The reward: every firefly you catch moves to the stone lantern by the cottage and stays there ──
const LANTERN = Point3f(-9.55, 4.25, 1.70)     # the cottage's stone lantern (an AssetActor in areas)
const HOME_MAX = 40
home_file(game) = joinpath(game.paths.state, "fireflies.json")
caught_total(game) = isfile(home_file(game)) ? Int(NG.read_json(home_file(game))["caught"]) : 0
save_total!(game, n) = NG.write_json(home_file(game), Dict("caught" => n))

"The fireflies at home: they circle the lantern, each on its own slow orbit."
struct FireflyHome <: System end

function NG.start!(s::FireflyHome, game)
    game.stage === nothing && return
    haskey(P, :home) && return
    P[:home] = meshscatter!(game.stage.scene, fill(PARK, HOME_MAX); marker = Sphere(Point3f(0), 1f0), markersize = 0.065f0,
        color = RGBf(1, 1, 0.6), material = NG.Hikari.Emission(color = (1.0, 0.9, 0.4), strength = 6.0))
end

function NG.step!(s::FireflyHome, game, dt)
    haskey(P, :home) || return
    NG.path_traced(game) && return     # glowing flies held still while tracing (NG.path_traced)
    n = min(HOME_MAX, get!(() -> caught_total(game), P, :total))
    t = Float32(game.world.t)
    pts = P[:home_pts] = get(P, :home_pts, fill(PARK, HOME_MAX))
    for i in 1:HOME_MAX
        home = i > n ? PARK : LANTERN + Point3f((0.7f0 + 0.08f0 * (i % 5)) * cos(0.35f0 * t * (1 + 0.1f0 * (i % 3)) + 2.4f0 * i),
                                                   (0.7f0 + 0.08f0 * (i % 5)) * sin(0.35f0 * t * (1 + 0.1f0 * (i % 3)) + 2.4f0 * i),
                                                   0.6f0 + 0.12f0 * (i % 7) + 0.15f0 * sin(1.7f0 * t + i))
        # the ones just caught fly home from where the round ended, one after the other, in a high arc
        fl = get(P, :flight, nothing)
        if fl !== nothing && fl.first <= i <= fl.last && home != PARK
            u = clamp((game.world.t - fl.t0 - 0.25 * (i - fl.first)) / 4.0, 0.0, 1.0)
            e = Float32(u * u * (3 - 2u))
            home = (1 - e) * fl.from + e * home + Point3f(0.3f0 * sin(9f0 * e + i), 0.3f0 * cos(7f0 * e + i), 3f0 * sin(Float32(pi) * e))
        end
        pts[i] = home
    end
    Makie.update!(P[:home]; arg1 = pts)
end
NG.stop!(s::FireflyHome, game) = nothing

"A low front view of Lumi, the direction fixed at the end (a cheering Lumi turns)."
function end_view!(game, c, dt)
    fwd = get!(P, :end_dir) do
        a = c.yaw + NG.species_of(c).heading
        Point3f(cos(a), sin(a), 0)
    end
    k = Float32(1 - exp(-3dt / 0.8))
    game.rig.mode = :fixed
    game.rig.eye += k * (c.pos + 4.2f0 * fwd + Point3f(0, 0, 1.6f0) - game.rig.eye)
    game.rig.target += k * (c.pos + Point3f(0, 0, 1.5f0) - game.rig.target)
end

function NG.input!(m::FireflyCatch, game, ev)
    ev.action == Makie.Keyboard.press || return
    if ev.key == Makie.Keyboard.r
        reset!(m, game)
    elseif m.state === :ready && ev.key in (Makie.Keyboard.w, Makie.Keyboard.s, Makie.Keyboard.a, Makie.Keyboard.d, Makie.Keyboard.up)
        m.state = :playing; m.t_state = 0.0
        P[:card].visible[] = false
    end
end

"Where `p` is seen from Lumi: ahead, left, right or behind."
function direction_word(c, p)
    a = NG.wrap_angle(atan(p[2] - c.pos[2], p[1] - c.pos[1]) - c.yaw)
    abs(a) < 0.5 ? "ahead" : abs(a) > 2.4 ? "behind you" : a > 0 ? "to your left" : "to your right"
end

function NG.step!(m::FireflyCatch, game, dt)
    w = game.world
    name_tags!(game, m.state !== :ready)   # the start card covers the middle of the view: no name tags under it
    c = NG.creature(w, m.lumi)
    # before the start the card is up and Lumi stands still; after the end too
    m.state === :playing ? NG.step!(m.jump, game, dt) : (c.action = :idle)
    m.t_state += dt
    # the end: a low front view of Lumi cheering under the end card (the chase view looked down on its back)
    m.state === :ready ? start_view!(game, c, dt) : m.state === :over && m.t_state > 1.0 ? end_view!(game, c, dt) : chase_camera!(game, c, dt)
    m.state === :playing && (m.t += dt)
    for (i, k) in enumerate(KEYS)   # the key bar: every key you hold lights up
        P[Symbol(:key_, i)].background_color[] = k in game.keys_down ? KEY_ON : KEY_OFF
    end
    head = c.pos + Point3f(0, 0, 0.5f0)
    pos = Vector{Point3f}(undef, N_FLIES)
    for i in 1:N_FLIES
        if m.state === :playing && !m.caught[i]
            d = Vec2f(m.flies[i][1] - c.pos[1], m.flies[i][2] - c.pos[2])
            dist = norm(d)
            if 0.01f0 < dist < FLEE_RADIUS   # drift away, slower than Lumi walks, but never off the island
                step = flee_speed(game) * Float32(dt) * d / dist
                nb = m.flies[i] + Point3f(step[1], step[2], 0)
                # and never into a nook by a trunk, bush or rock, where Lumi gets wedged chasing it
                NG.on_land(w.island, nb[1], nb[2]; margin = 0.8f0) && !near_solid(w, nb, 1.1f0) && !under_crown(w, nb) && (m.flies[i] = nb)
            end
        end
        p = fly_pos(m.flies[i], w.t, i)
        if m.state === :playing && !m.caught[i] && norm(p - head) < CATCH_RADIUS
            m.caught[i] = true
            m.score += 1
            m.spark_at = p; m.spark_t = 0.0; m.flash = 1.2
            NG.say!(w, c, m.score == N_FLIES ? "Got them all!" : rand(w.rng, ("Got one!", "Gotcha!", "Yes!", "Caught you!")); duration = 1.5)
            NG.emit!(w, :firefly_caught; who = c.name, score = m.score)
            P[:laugh_until] = w.t + 0.9
        end
        pos[i] = m.caught[i] ? PARK : p
    end
    # a catch shows on Lumi's face: a short laugh (todo #325; the player steers Lumi, so feel! leaves it alone
    # and the action is set here, after the engine's step)
    w.t < get(P, :laugh_until, -Inf) && (c.action = :laugh)
    # while path tracing the glowing flies move twice a second: every move re-pushes them as Hikari lights
    # that are never freed (NG.path_traced, patches/raymakie-emissive-meshscatter-leak.md)
    redraw = !NG.path_traced(game) || w.t - get(P, :traced_draw, -1.0) > 0.5
    redraw && (P[:traced_draw] = w.t)
    redraw && Makie.update!(P[:flies]; arg1 = pos, markersize = 0.27f0 + 0.07f0 * sin(Float32(6 * w.t)))   # they pulse, easy to spot
    # halos: raster and browser only (alpha shells turn into solid discs when traced)
    redraw && Makie.update!(P[:halo]; arg1 = [pos[(i - 1) ÷ 3 + 1] for i in 1:3N_FLIES],
        markersize = NG.path_traced(game) ? fill(0f0, 3N_FLIES) : halo_sizes(1f0 + 0.12f0 * sin(Float32(6 * w.t))))
    redraw && Makie.update!(P[:beams]; arg1 = [p == PARK ? PARK : Point3f(p[1], p[2], NG.terrain_height(w.island, p[1], p[2])) for p in pos],
        # a beam only for flies further than 6 m: close ones you see, and a beam next to the camera fills the view
        markersize = [p == PARK || norm(Vec2f(p[1] - c.pos[1], p[2] - c.pos[2])) < 6 ? Vec3f(0) :
                      Vec3f(0.035, 0.035, max(0.1f0, p[3] - NG.terrain_height(w.island, p[1], p[2]) + 2.5f0)) for p in pos])
    # the catch burst: sparks fly out and fall
    m.spark_t += dt
    if m.spark_t < SPARK_TIME
        s = Float32(m.spark_t)
        sp = [m.spark_at + Point3f(1.6f0 * s * cos(2pi * k / N_SPARKS) * (0.6f0 + 0.4f0 * sin(3k)),
                                   1.6f0 * s * sin(2pi * k / N_SPARKS) * (0.6f0 + 0.4f0 * sin(3k)),
                                   (1.5f0 + 0.6f0 * cos(5k)) * s - 2.5f0 * s^2) for k in 1:N_SPARKS]
        redraw && Makie.update!(P[:sparks]; arg1 = sp, markersize = 0.08f0 * (1 - s / Float32(SPARK_TIME)) + 0.01f0)
    elseif m.spark_t - dt < SPARK_TIME
        Makie.update!(P[:sparks]; arg1 = fill(PARK, N_SPARKS))
    end
    m.flash = max(0.0, m.flash - dt)
    # the HUD and the end
    left = max(0.0, TIME_LIMIT - m.t)
    if m.state === :playing && (m.score == N_FLIES || left <= 0)
        m.state = :over; m.t_state = 0.0
        delete!(P, :end_dir)
        won = m.score == N_FLIES
        best = get!(() -> load_best(game, "firefly_catch", Inf), P, :best)
        # the clock starts on the first key: a round won with no key (a test) ran 0.0 s and showed "Your best: 0.0 s"
        # after a real 41 s win (perfectionist-0049); such a time is no best
        best < 1 && (best = P[:best] = Inf)
        newbest = won && 1 <= m.t < best
        newbest && (P[:best] = m.t; save_best!(game, "firefly_catch", m.t))
        total = get!(() -> caught_total(game), P, :total) + m.score
        P[:flight] = (from = c.pos + Point3f(0, 0, 1f0), t0 = w.t + 0.5, first = min(HOME_MAX, total - m.score) + 1, last = min(HOME_MAX, total))
        P[:total] = total
        save_total!(game, total)
        lv = level(game)
        if won && lv < MAX_LEVEL      # the next round is a step harder
            P[:level] = lv + 1; save_best!(game, "firefly_level", lv + 1)
        end
        up = won ? (lv < MAX_LEVEL ? "\nNext round: level $(lv + 1), quicker fireflies!" : "\nTop level: the quickest fireflies!") : ""
        home = up
        home *= m.score == 0 ? "" : "\n$(m.score == 1 ? "Your firefly flies" : "Your $(m.score) fireflies fly") to the lantern by the cottage ($total there now)."
        Makie.update!(P[:card]; text = won ?
            @sprintf("All %d caught in %.1f s!\n%s%s\n\nPress R to play again", N_FLIES, m.t,
                     newbest ? "A new best time!" : isfinite(best) ? @sprintf("Your best: %.1f s", best) : "Your first win!", home) :
            @sprintf("Time's up! You caught %d of %d.\n%s%s\n\nPress R to play again", m.score, N_FLIES,
                     isfinite(best) ? @sprintf("Your best: all in %.1f s", best) : "Tip: Shift runs, fireflies drift away from you", home))
        P[:card].visible[] = true
        won && (c.action = :dance)
        # everyone close by cheers along: they turn to Lumi, hop and shout
        won && for o in w.creatures
            (o === c || o.controlled || o.goal.kind === :interact || o.action === :sleep) && continue
            norm(Vec2f(o.pos[1] - c.pos[1], o.pos[2] - c.pos[2])) < 9 || continue
            o.yaw = atan(c.pos[2] - o.pos[2], c.pos[1] - o.pos[1])
            o.goal = NG.Goal(:answer, o.pos, :jump, 3.0, w.t + 3.0, true, 0, false)
            NG.say!(w, o, rand(w.rng, ("Hooray!", "Wow, Lumi!", "All of them!", "Yay!")); duration = 2.5)
        end
    end
    msg = if m.state === :ready
        "Press W to start"
    elseif m.state === :over
        m.score == N_FLIES ? "All caught!" : @sprintf("Time's up: %d/%d", m.score, N_FLIES)
    else
        rest = [i for i in 1:N_FLIES if !m.caught[i]]
        j = rest[argmin([norm(pos[i] - c.pos) for i in rest])]
        @sprintf("Fireflies %d/%d    %2.0f s left    nearest %.0f m %s", m.score, N_FLIES, left,
                 norm(Vec2f(pos[j][1] - c.pos[1], pos[j][2] - c.pos[2])), direction_word(c, pos[j]))
    end
    Makie.update!(P[:hud]; text = msg)
    # the start card says "Press W to start" itself: no second prompt above it (tester s44)
    (m.state !== :ready) == P[:hud].visible[] || (P[:hud].visible[] = m.state !== :ready)
    P[:hud].text_color[] = m.flash > 0 ? RGBf(0.55, 1, 0.55) : RGBf(1, 0.95, 0.6)
    m.state === :over && m.score == N_FLIES && (c.action = :dance)
end

# the end card stays until R (play again) or Stop; after a minute it closes by itself
NG.finished(m::FireflyCatch) = m.state === :over && m.t_state > 60

function NG.stop!(m::FireflyCatch, game)
    name_tags!(game, true)
    if get(P, :version, 0) == PLOTS_VERSION
        foreach(k -> Makie.update!(P[k]; arg1 = fill(PARK, length(P[k][1][]))), (:flies, :halo, :beams, :sparks))
        show_plots!(false)
    end
    NG.stop!(m.jump, game)
    game.rig.mode = :follow
end

register!(FireflyCatch)
register!(FireflyHome())
