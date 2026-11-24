# One more stone, v2 (2026-11-23)

The second take of the first path traced film from The Neverending Game: 13.5 s, 1280x720, 24 fps,
128 samples a frame (RayMakie/Hikari in the worker, about 4 s a frame).

At golden hour on the island meadow, Cumulus the sheep, in its blue knit hat, walks out, picks up a
pebble, carries it on its head and sets it down by the critters' cairn, which the creatures build
stone by stone over the days (plugins/cairns.jl). Nothing is animated by hand: it is a quiet copy of
the game with every plugin running, and the camera cuts on what really happens (a wide shot, a low
close shot while it carries the stone, a slow pull-back once it is down).

What changed since v1: twice the samples, so the grain on the white wool is gone, and the sea horizon is a
clean soft line (the sky below the horizon used to be black and drew a jagged band; it is now a sea
haze, NG.SKY_GROUND). A worker take is a new take: the sheep's walk differs a little from v1.

Made with `cairn_release.jl` (`NG.game_clip` with a `setup` that sends Cumulus off and a `shot` director).
