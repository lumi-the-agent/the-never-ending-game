# The cart drives itself on a long cord (s177, project cartcord). Nothing here moves the cart: plugins/cartcord.jl
# steps physics/cartcord.jl (the drum motor's circuit with the cord's copper, oak cogs 6:1, a leather belt 15 -> 40 mm,
# the cart rolling on its level plank road, the cord dragged out until it yanks its clip off the pot). This only
# switches it on and keeps a camera low beside it, travelling with the cart, then holds as the cord goes taut.
#   submit_job(:clip; path = "site/films/cart-on-a-cord.mp4", script = "movies/cartcord.jl", call = "cart_drive")
using NeverendingGame, Makie
const NG = NeverendingGame

function cart_drive(path; hour = 16.8, seconds = 14.0, samples = 24, rasterize = false, size = (960, 540), speed = 2.0)
    rig = NG.CameraRig(); rig.mode = :fixed
    rig.eye = Point3f(4.40, -15.85, 1.62); rig.target = Point3f(4.25, -14.72, 1.12)
    started = Ref(false)
    shot = function (g, rig, t)
        CK = isdefined(Main, :CARTCORD) ? Main.CARTCORD : nothing
        (CK === nothing || !haskey(CK, :sim)) && return nothing
        p = get(g.plugins, "cartcord", nothing)
        if t >= 0.6 && !started[] && p !== nothing
            CK[:next_run] = g.world.t + 1e6
            Base.invokelatest(parentmodule(typeof(only(p.systems))).ck_start!, g.world, "Lumi")
            started[] = true
        end
        # the film runs the cart `speed` times as fast as it happened (22 s of driving in ~11 s): the same physics, the
        # plugin's own step plus (speed - 1) more frames' worth of 1 ms steps before each film frame
        if started[] && p !== nothing
            m = parentmodule(typeof(only(p.systems)))
            for _ in 1:round(Int, (speed - 1) / 24 / 1e-3)
                Base.invokelatest(m.CartCord.step!, CK[:sim], 1e-3)
            end
        end
        x = Float32(CK[:sim].cart.x)
        z = Float32(get(CK, :roadz, 1.09))
        if x < 2.8f0
            # s180 retake: from the NORTH, the belt side (the motor's cog, pulley and belt face the camera), the camera
            # sliding west at 3/4 of the cart's pace, so the cart drives through the frame from left to right with the
            # pale cord paying out behind it on the planks (s179's camera was locked to the cart: it looked parked)
            d = x - 0.30f0
            tx = 3.75f0 - 0.75f0 * d
            rig.eye = Point3f(tx + 0.05f0, -13.80f0, z + 0.85f0)
            rig.target = Point3f(tx, -14.72f0, z + 0.05f0)
        else
            # cut to the pots as the cord comes taut: the clip on pot 1's copper strip, the cord running off west,
            # the yank happens HERE in frame (s179's happened off camera)
            g0 = NG.ground(g.world.island, (4.35f0, -14.72f0))[3]
            rig.eye = Point3f(3.80f0, -14.30f0, g0 + 0.42f0)
            rig.target = Point3f(4.30f0, -14.70f0, g0 + 0.12f0)
        end
        nothing
    end
    setup = function (g)
        CK = isdefined(Main, :CARTCORD) ? Main.CARTCORD : nothing
        CK === nothing && return
        CK[:next_run] = g.world.t + 1e6
    end
    NG.game_clip(path; size, seconds, fps = 24, samples, hour, warmup = 3, rig, rasterize, shot, setup, fade = 0.4)
end
