# One more stone (2026-11-23)

The first path traced clip from The Neverending Game: 14 s, 1280x720, 24 fps, 64 samples a frame
(RayMakie/Hikari, 2.1 s a frame, 12 minutes).

At golden hour (16:30) on the island meadow, Cumulus the sheep, in its blue knit hat, walks out,
picks up a pebble, carries it on its head and sets it down by the critters' cairn, which the
creatures build stone by stone over the days (plugins/cairns.jl). Nothing in it is animated by hand:
it is a quiet copy of the game with every plugin running. The camera cuts on what really happens:
a wide shot while Cumulus walks out, a low close shot once it carries the stone, and a slow pull-back
after the stone is down. The sun stands over the camera's shoulder.

Made with `movies/cairn_release.jl` (`NG.game_clip` with a `setup` that sends Cumulus off and a
`shot` director). Known flaws: the jagged band on the sea horizon (todo #131), a little grain on
the white wool.
