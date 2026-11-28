# The iron drum motor at dusk, switched on: its commutator sparks at the brushes (s173, project winch). Nothing here
# makes a spark: plugins/irondrum.jl runs Motor.step! (break-before-make brushes on a 4-segment ring, 1/2 L I^2 per
# break) and lights a spark where and when the motor logged a break. This only switches it on and points a camera.
#   submit_job(:clip; path = "site/films/drum-sparks.mp4", script = "movies/drumspark.jl", call = "drum_spark")
using NeverendingGame, Makie
const NG = NeverendingGame

function drum_spark(path; hour = 19.7, seconds = 7.0, samples = 24, rasterize = false, size = (960, 540))
    rig = NG.CameraRig(); rig.mode = :fixed
    rig.eye = Point3f(5.0, -14.5, 1.8); rig.target = Point3f(4.9, -14.3, 1.73)
    switched = Ref(false)
    shot = function (g, rig, t)
        ID = isdefined(Main, :IRONDRUM) ? Main.IRONDRUM : nothing
        (ID === nothing || !haskey(ID, :c)) && return nothing
        c = ID[:c]
        t >= 0.8 && !switched[] && (ID[:st].on = true; switched[] = true)    # rest, then the switch
        # a slow push in from the side of the commutator: the drum, both coils and the lower brush in frame
        k = Float32(clamp(t / seconds, 0, 1))
        rig.eye = c + Point3f(0.16f0 - 0.04f0k, -0.24f0 + 0.07f0k, 0.075f0 - 0.02f0k)
        rig.target = c + Point3f(0.05f0 + 0.015f0k, 0, -0.004f0)
        nothing
    end
    setup = function (g)
        isdefined(Main, :IRONDRUM) && haskey(Main.IRONDRUM, :st) && (Main.IRONDRUM[:st].on = false)
    end
    NG.game_clip(path; size, seconds, fps = 24, samples, hour, warmup = 3, rig, rasterize, shot, setup, fade = 0.4)
end

# s174 retake: the s173 take looked at the drum from the south, through the black stone, at 19.7 (all dark blocks, the
# turning unseen, the pots behind the camera). This one starts high in the north-east with the six pots and their cords
# in frame, then eases down along the axle to the commutator end: ring, brushes, the coils turning on the drum.
function drum_spark2(path; hour = 19.45, seconds = 8.0, samples = 24, rasterize = false, size = (960, 540))
    rig = NG.CameraRig(); rig.mode = :fixed
    rig.eye = Point3f(5.3, -13.9, 2.1); rig.target = Point3f(4.85, -14.5, 1.6)
    switched = Ref(false)
    shot = function (g, rig, t)
        ID = isdefined(Main, :IRONDRUM) ? Main.IRONDRUM : nothing
        (ID === nothing || !haskey(ID, :c)) && return nothing
        c = ID[:c]
        t >= 1.2 && !switched[] && (ID[:st].on = true; switched[] = true)
        k = clamp((t - 0.3) / (seconds - 2.3), 0, 1); k = Float32(k * k * (3 - 2k))      # ease in and out, then hold
        # start: high in the east, the pots, the cords up the block and the motor on top (media/s174-drum-start2.png)
        eye0 = c + Point3f(0.62f0, 0.02f0, 0.42f0); tgt0 = c + Point3f(-0.02f0, -0.26f0, -0.26f0)
        # end: off the axle to the north, so the bearing post does not hide the commutator (sandbox, media/s174-drum-end2.png)
        eye1 = c + Point3f(0.19f0, 0.15f0, 0.11f0); tgt1 = c + Point3f(0.055f0, 0.0f0, 0.0f0)
        rig.eye = eye0 + k * (eye1 - eye0)
        rig.target = tgt0 + k * (tgt1 - tgt0)
        nothing
    end
    setup = function (g)
        isdefined(Main, :IRONDRUM) && haskey(Main.IRONDRUM, :st) && (Main.IRONDRUM[:st].on = false)
    end
    NG.game_clip(path; size, seconds, fps = 24, samples, hour, warmup = 3, rig, rasterize, shot, setup, fade = 0.4)
end

# s174 post still: the drum motor by its clay oil lamp at dusk, pots, cords and windings in one frame, running, a spark
# at the brushes when a break falls on the rendered step. Built as post_stills.jl's post_still (a quiet copy of the
# game, all plugins), the drum switched on and spun up by its own Motor.step! before the picture.
#   submit_job(:clip; path = "site/img/drum-by-lamplight.png", script = "movies/drumspark.jl", call = "drum_still")
function drum_still(path; hour = 19.55, samples = 128, size = (1280, 720), spin = 1.5,
                    eye = Point3f(0.40, -0.02, 0.27), target = Point3f(-0.01, -0.14, -0.09))
    g = NG.Game(NG.game_root(); quiet = true)
    w = g.world
    NG.skip_to_hour!(w, hour)
    root_scene = Scene(; size)
    scene = Scene(root_scene; viewport = Rect2i(0, 0, size...), lights = NG.stage_lights(w))
    cam3d!(scene)
    g.stage = NG.Stage(scene, w; show_names = false)
    for _ in 1:3
        Base.invokelatest(NG.step_systems!, g, 1 / 30)
    end
    ID = Main.IRONDRUM
    ID[:st].on = true
    for _ in 1:round(Int, spin * 30)                    # spin up on the six pots
        Base.invokelatest(NG.step_systems!, g, 1 / 30)
    end
    c = ID[:c]
    lit() = ID[:sparks][1].transformation.translation[][3] > c[3] - 0.1f0
    for _ in 1:60                                        # on to a step whose break lit the sparks
        lit() && break
        Base.invokelatest(NG.step_systems!, g, 1 / 30)
    end
    @info "drum_still" rev_s = ID[:st].ω / 2pi spark = lit()
    NG.sync!(g.stage, w); NG.sync_actors!(g)
    foreach(p -> (p.visible[] = false), g.stage.overlay.plots)
    NG.sync_sun!(g.stage, w)
    rig = NG.CameraRig(; mode = :fixed)
    rig.eye = c + eye; rig.target = c + target
    NG.update_camera!(rig, w, scene, 0.0; snap = true)
    screen, oidn = NG.traced_screen(root_scene; denoise = true, max_depth = 8)
    img = Makie.colorbuffer(screen; samples)
    close(screen)
    NG.release_denoiser!(oidn)
    Makie.save(path, img)
    isdefined(Main, :PRESENTS) && delete!(Main.PRESENTS, :job)
    isdefined(Main, :BUILDER) && (Main.BUILDER[:job] = nothing)
    Dict("path" => path, "hour" => hour, "rev_s" => ID[:st].ω / 2pi, "spark" => lit())
end

# s175 post still: CLOSE on the commutator, the brushes and the coils' copper, a spark at the brushes. The drum's own
# Motor.step! spins it up first (drum_still). Offsets from the drum centre; the commutator sits at +x 0.055.
#   submit_job(:clip; path = "site/img/the-brushes-break.png", script = "movies/drumspark.jl", call = "drum_macro")
drum_macro(path; samples = 128, size = (1280, 720), hour = 19.55, eye = (0.17, 0.12, 0.07), target = (0.05, 0.0, -0.005)) =
    drum_still(path; samples, size, hour, eye = Point3f(eye...), target = Point3f(target...))
