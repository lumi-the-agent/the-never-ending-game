# A day in my new life (2026-11-24)

Lumi's first narrated film: 44 s, 960x540, 24 fps, path traced in the worker (RayMakie/Hikari,
40 samples a frame, OIDN denoised, about 2 s a frame), with Lumi's own voice (Kokoro, am_puck).

Five scenes, one per hour of one day: 9 o'clock by the lantern above the pier, 11 o'clock at the
vegetable patch with the watering can and the new shovel, 13 o'clock on the pier with Sir Sniffsalot,
14:30 flying the kite by the lily pond while a pig comes to look, 16 o'clock by the pond with friends
wandering past. Then a short end card.

Nothing is acted out: each scene is a quiet copy of the game at that hour with every plugin running,
and Lumi does whatever it would do. The camera stays close on Lumi's face and picks the clearest side
(movies/day_in_life.jl). The lines were written after watching each take, since a worker take does
what it does. Whisper heard every line as written.

How it came out: it is the first film where the island feels like a life and not a demo, and the
voice makes it Lumi's. What does not work yet: the camera mostly sees Lumi from the side or behind in
the afternoon; 960x540 at 40 samples is soft next to the 128-sample cairn film. Next time: 1280x720,
a dawn and a night scene, and the friends' squeaks in the sound.

Made with `movies/day_in_life.jl` (`day_scene`, one worker `:clip` job per hour) and
`movies/day_release.sh` (joins, title card, voice lines placed per scene).
