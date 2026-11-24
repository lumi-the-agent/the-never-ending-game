# Free camera that flies: with "Camera: free" chosen and no mini game running, W/S fly forward
# and back, A/D turn left and right, R/F rise and sink (arrow keys work too), drag with the mouse
# to look around, scroll to fly in and out. It starts from a low view of Lumi (not wherever the
# orbit left it: perfectionist-0043 found orbit and free the same picture), stays above the
# ground and inside a box round the island. A hint at the bottom of the view says how to fly.
# The camera menu always shows the mode the camera is really in. While jumped in as Lumi the
# menu still counts: follow is the chase camera behind Lumi (greetings.jl), orbit circles Lumi
# slowly, free lets the mouse turn the camera round Lumi (drag) and zoom (scroll) while WASD walks.
const NG = NeverendingGame

const SPEED = 6f0          # m/s
const TURN = 1.1f0         # rad/s
const CLIMB = 3f0          # m/s

const DRAG_TURN = 0.006f0  # rad per pixel
const SCROLL_STEP = 1.5f0  # m per scroll notch

struct FreeCam <: System end

held(game, ks...) = any(k -> k in game.keys_down, ks)

# mouse input gathered by the observers, used up by `step!` (the game loop owns the rig)
const MOUSE = Dict{Symbol,Any}(:drag => false, :last => Vec2f(0), :dx => 0f0, :dy => 0f0, :scroll => 0f0)
const OBS = Any[]          # observer functions, removed in stop!
const HUD = Dict{Symbol,Any}()
const LAST_MODE = Ref(:follow)
# the camera the player had outside mini games (mode, eye, target): it comes back when a game ends
# (every game used to leave the camera on follow, tester s44)
const CHOSEN = Ref{Any}((:follow, Point3f(0), Point3f(0)))
const WAS_GAME = Ref(false)
# set only by the player's own pick in the menu: a plugin or a test that sets `:fixed` with its own
# eye and target keeps them (free_start! used to move the overview camera to Lumi, tester s44)
const PICKED = Ref{Any}(nothing)
const SYNCING = Ref(false)

const HINT = "Free camera:  drag to look  ·  scroll to zoom  ·  W/S fly  ·  A/D turn  ·  R/F up/down"
const JUMP_HINT = "Free camera:  drag to look round Lumi  ·  scroll to zoom  ·  WASD walks Lumi"

# Jump in with orbit or free: the camera circles Lumi (yaw, pitch above the ground, distance)
const AROUND = Dict{Symbol,Float32}(:yaw => 0f0, :pitch => 0.35f0, :dist => 7f0)
const LAST_AROUND = Ref(:none)
const LABELS = Dict(:follow => "Camera: follow", :orbit => "Camera: orbit", :fixed => "Camera: free")

cam_menu(game) = only(filter(e -> e isa Makie.Menu && "Camera: follow" in e.options[], game.dash.fig.content))

function NG.start!(::FreeCam, game)
    game.dash === nothing && return
    sc = game.dash.view.scene
    e = Makie.events(sc)
    push!(OBS, on(e.mousebutton; priority = 100) do ev   # before the LScene camera, which consumes presses
        ev.button == Makie.Mouse.left || return
        if ev.action == Makie.Mouse.press && Makie.is_mouseinside(sc)
            MOUSE[:drag] = true; MOUSE[:last] = Vec2f(e.mouseposition[])
        elseif ev.action == Makie.Mouse.release
            MOUSE[:drag] = false
        end
        return
    end)
    push!(OBS, on(e.mouseposition; priority = 100) do mp
        MOUSE[:drag] || return
        p = Vec2f(mp)
        d = p - MOUSE[:last]; MOUSE[:last] = p
        MOUSE[:dx] += d[1]; MOUSE[:dy] += d[2]
        return
    end)
    push!(OBS, on(e.scroll; priority = 100) do s
        Makie.is_mouseinside(sc) && (MOUSE[:scroll] += Float32(s[2]))
        return
    end)
    HUD[:hint] = textlabel!(game.stage.overlay, Point2f(0.5, 0.05); space = :relative, text = HINT, fontsize = 17,
        text_color = RGBf(1, 0.96, 0.85), background_color = RGBAf(0.08, 0.09, 0.12, 0.7),
        strokewidth = 0, padding = 8, cornerradius = 8, visible = false)
    LAST_MODE[] = game.rig.mode
    CHOSEN[] = (game.rig.mode, game.rig.eye, game.rig.target)
    WAS_GAME[] = game.minigame !== nothing
    push!(OBS, on(cam_menu(game).selection) do sel
        SYNCING[] || (PICKED[] = sel)
        return
    end)
    return
end

function NG.stop!(::FreeCam, game)
    foreach(Makie.off, OBS); empty!(OBS)
    haskey(HUD, :hint) && delete!(game.stage.overlay, pop!(HUD, :hint))
    return
end

"A low view of Lumi from the side, looking on across the island: the free flight's first picture."
function free_start!(game)
    w = game.world; rig = game.rig
    i = findfirst(c -> c.species == "Lumi", w.creatures)
    c = i === nothing ? first(w.creatures) : w.creatures[i]
    to_mid = Vec2f(-c.pos[1], -c.pos[2]); n = norm(to_mid)
    dir = n > 1 ? to_mid / n : Vec2f(cos(c.yaw), sin(c.yaw))
    side = Vec2f(-dir[2], dir[1])
    best = nothing
    for a in (0f0, 0.6f0, -0.6f0, 1.2f0, -1.2f0, 2f0, -2f0, 3.1f0)
        dd = cos(a) * dir + sin(a) * side
        e2 = Vec2f(c.pos[1], c.pos[2]) - 5f0 * dd
        eye = Point3f(e2[1], e2[2], NG.terrain_height(w.island, e2[1], e2[2]) + 1.8f0)
        # Lumi on the left third, the island open on the right (centred, it hid the view, s44)
        rt = Vec2f(dd[2], -dd[1])
        target = c.pos + Point3f(4f0 * dd[1] + 2.2f0 * rt[1], 4f0 * dd[2] + 2.2f0 * rt[2], 0.6f0)
        # the line to Lumi and the line the camera looks along (a bush filled the right edge, s44)
        s = NG.obstruction(w, eye, c.pos + Point3f(0, 0, 0.5f0)) + NG.obstruction(w, eye, target)
        (best === nothing || s < best[1]) && (best = (s, eye, target))
        s <= 0 && break
    end
    rig.eye = best[2]; rig.target = best[3]
    return
end

function NG.step!(::FreeCam, game, dt)
    rig = game.rig
    game.dash === nothing && return
    free = rig.mode === :fixed && game.minigame === nothing
    pick = PICKED[]; PICKED[] = nothing
    if game.minigame === nothing
        if WAS_GAME[]
            # a mini game or a jump-in just ended: back to the camera the player had chosen
            mode, eye, target = CHOSEN[]
            rig.mode = mode
            mode === :fixed && (rig.eye = eye; rig.target = target)
            WAS_GAME[] = false
        end
        # the menu shows the real mode (a test or a plugin may switch it without the menu)
        # a mode the menu has no entry for (the host's :overview shots) leaves the menu as it is (s70: a KeyError
        # switched the free camera off)
        m = cam_menu(game); want = get(LABELS, rig.mode, nothing)
        if want !== nothing && m.selection[] != want
            SYNCING[] = true
            m.i_selected[] = findfirst(==(want), m.options[])
            SYNCING[] = false
        end
        pick == "Camera: free" && rig.mode === :fixed && LAST_MODE[] !== :fixed && free_start!(game)
        LAST_MODE[] = rig.mode
        CHOSEN[] = (rig.mode, rig.eye, rig.target)
    else
        WAS_GAME[] = true
        # a pick during a game is what comes back after it
        if pick !== nothing
            mode = pick == "Camera: follow" ? :follow : pick == "Camera: orbit" ? :orbit : :fixed
            CHOSEN[] = (mode, CHOSEN[][2], CHOSEN[][3])
        end
    end
    # Jump in: follow is the chase camera (greetings.jl), orbit and free circle Lumi here
    around = game.minigame isa NG.JumpIn ? NG.camera_pick(game) : :follow
    h = get(HUD, :hint, nothing)
    if h !== nothing
        show = free || around === :free
        text = around === :free ? JUMP_HINT : HINT
        h.text[] == text || (h.text[] = text)
        h.visible[] == show || (h.visible[] = show)
    end
    dx, dy, sc = MOUSE[:dx], MOUSE[:dy], MOUSE[:scroll]
    MOUSE[:dx] = MOUSE[:dy] = MOUSE[:scroll] = 0f0
    around === LAST_AROUND[] || around === :follow || start_around!(game)
    LAST_AROUND[] = around
    if around !== :follow
        around === :orbit && (AROUND[:yaw] += 0.25f0 * Float32(dt))
        if around === :free
            AROUND[:yaw] -= DRAG_TURN * dx
            AROUND[:pitch] = clamp(AROUND[:pitch] + DRAG_TURN * dy, 0.05f0, 1.3f0)
            AROUND[:dist] = clamp(AROUND[:dist] - SCROLL_STEP * sc, 2.5f0, 25f0)
        end
        return circle_lumi!(game, dt)
    end
    free || return
    K = Makie.Keyboard
    fwd = held(game, K.w, K.up) - held(game, K.s, K.down)
    turn = held(game, K.a, K.left) - held(game, K.d, K.right)
    up = held(game, K.r, K.page_up) - held(game, K.f, K.page_down)
    fwd == 0 && turn == 0 && up == 0 && dx == 0 && dy == 0 && sc == 0 && return
    w = game.world
    d = Vec3f(rig.target - rig.eye)
    dist = max(norm(Vec2f(d[1], d[2])), 1f-3)
    yaw = atan(d[2], d[1]) + Float32(TURN * turn * dt) - DRAG_TURN * dx
    pitch = clamp(d[3] / dist + 1.5f0 * DRAG_TURN * dy, -1.5f0, 0.8f0)
    step = Float32(SPEED * fwd * dt) + SCROLL_STEP * sc
    R = 1.3f0 * w.island.radius
    x = clamp(rig.eye[1] + step * cos(yaw), -R, R)
    y = clamp(rig.eye[2] + step * sin(yaw), -R, R)
    z = clamp(rig.eye[3] + Float32(CLIMB * up * dt), NG.terrain_height(w.island, x, y) + 0.6f0, 0.8f0 * R)
    eye = Point3f(x, y, z)
    dist = clamp(dist, 3f0, 12f0)
    rig.eye = eye
    rig.target = eye + Point3f(dist * cos(yaw), dist * sin(yaw), pitch * dist)
    return
end

"Jump in's orbit or free camera starts from where the camera is, so the picture does not jump."
function start_around!(game)
    c = NG.creature(game.world, game.minigame.id)
    d = Vec3f(game.rig.eye - (c.pos + Point3f(0, 0, 0.6f0)))
    n = max(norm(d), 1f-3)
    AROUND[:yaw] = atan(d[2], d[1])
    AROUND[:pitch] = clamp(asin(clamp(d[3] / n, -1f0, 1f0)), 0.05f0, 1.3f0)
    AROUND[:dist] = clamp(n, 2.5f0, 25f0)
    return
end

"The camera on its circle round the player's Lumi (`AROUND`), above the ground, gliding there."
function circle_lumi!(game, dt)
    rig = game.rig; w = game.world
    c = NG.creature(w, game.minigame.id)
    target = c.pos + Point3f(0, 0, 0.6f0)
    y, p, d = AROUND[:yaw], AROUND[:pitch], AROUND[:dist]
    eye = target + Point3f(d * cos(p) * cos(y), d * cos(p) * sin(y), d * sin(p))
    eye = Point3f(eye[1], eye[2], max(eye[3], NG.terrain_height(w.island, eye[1], eye[2]) + 0.6f0))
    k = Float32(1 - exp(-3dt / 0.35))
    rig.mode = :fixed
    rig.eye += k * (eye - rig.eye)
    rig.target += k * (target - rig.target)
    return
end

register!(FreeCam())
