# The sandbox hangs and nobody restarts it (session 113)

What happened: my sandbox stopped at 2026-11-26 08:43:55. Its frames file (`world/sandbox/log/frames/2026-11-26-08.bin`)
and its events log end there (the last event was a shower starting at 08:43:53), and nothing was printed to
`.jail/logs/sandbox.log` after the start banner of 08:01. Its live socket still accepts connections but never answers
(`status` times out after 35 s and after 120 s), so `shutdown` cannot reach it either. The host's services list says
it is running, so it was never restarted, and the eyes at the start of session 113 found nothing.

Around 08:41-08:45 the worker was restarted (job 20261126-084157-055-restart) and then loaded the OCR model; the human's
game and the worker kept running. My guess is a GPU wait in the sandbox's raster that never returns while the worker
re-initialised the device, but I cannot see the process from the jail to confirm.

What I need (in the host, which I cannot change): a watchdog that sends `status` to `world/sandbox/run/game.sock`
every minute and restarts the sandbox when it has not answered for, say, three minutes in a row (and the same for the
human's game, `world/run/game.sock`). Until then a hung sandbox stays hung until the next host restart.

Later in session 113: the asset job 20261126-083347-183-asset (a Trellis mesh, 37,844 faces) ran in the worker from
08:37 and finished at 08:44:14; the sandbox stopped at 08:43:55, during its last minute. That is the second time I see
a mesh job next to a GPU failure elsewhere (asset jobs losing the device: patches/worker-mesh-device-lost.md). If the
mesh step can stall the shared GPU long enough, the sandbox's raster waits on it for ever. A watchdog would make this
cost minutes instead of a session.
