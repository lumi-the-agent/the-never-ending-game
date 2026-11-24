---
name: make-movie
description: Turn moments of the game into videos - replays from the event and frame logs, VideoEditor projects with cameras, raster previews and path traced exports. Use when making clips for the human or the blog.
---

# Movies

`game_clip` (render.jl, since s35) renders a clip of the game living on from the
latest snapshot, every plugin running, follow camera, path traced (or `rasterize = true`
for a quick preview); worker job `:clip` (params seconds, fps, samples, size, hour, warmup).
Look at frames with `ffmpeg -i clip.mp4 -vf "select='eq(n\,0)+eq(n\,30)',tile=2x1" -frames:v 1 sheet.png`.
Replays of logged moments (log window → VideoEditor → traced export) are not built yet. What exists:

- The logs: `world/log/events-<date>.jsonl` and `world/log/frames/*.bin`
  (`read_frames`, `read_events` in `eventlog.jl`): every pose every 0.2 s.
- `render.jl`: `record_clip` (raster clip of a running world), `screenshot`
  (path traced still), `CameraRig`.
- VideoEditor (`../dev/VideoEditor`): a scene clip from a recorded animation,
  keyed cameras, `exportvideo` (path traced), `contactsheet`/`filmstrip`
  (quick raster review). A worked example made when the game was set up:
  `../setup/ve_smoke_scene.jl` and `../setup/ve_smoke/`.
- Long renders belong in the worker (add a job kind in `assets.jl`), never in
  a running game.
- Trap: `screenshot`, `stage_scene` and `Stage` build the island from the
  engine's world only. Everything plugins draw (flora, areas, the glowing
  flowers, stars, mini game props) goes into the live `game.stage.scene` and
  is missing there, so a movie rendered that way shows the bare island. The
  render has to run the plugins on the scene it draws (they draw into
  `game.stage.scene` of whatever `Game` they get).
- Path tracing handles glowing instanced plots (meshscatter with
  `Hikari.Emission`): each glowing copy becomes its own light. Check a traced
  still of the live view with `live_path_tracing(true)` and a screenshot.

## Denoising (OIDN on the GPU, since 2026-11-24)

`game_still` and `game_clip` (the worker's `:trace` and `:clip` jobs) denoise every traced
picture with Open Image Denoise (JuliaVision's OIDNRunner, `GPUOIDN` in render.jl) on the
film's radiance with its albedo and normal guides, before tone mapping (`denoise = false`
turns it off). 16 samples come out clean where they used to be grainy, so: stills 64-128
samples, film frames 32-64 (faster takes, or a longer film in the same time). It is
spatial, frame by frame: check a film for flicker in slow pans.

## Pictures for your pages

Your pages (world/site, /lumi/) show only path traced renders: a `:trace` job or a
`post_still` call with 64+ samples, written straight to `world/site/img` (no copying, cropping
or resizing afterwards), with the camera on the thing the post is about. Dashboard screenshots
(`live_screenshot`) are evidence for you and the reviewer, never page pictures. The host checks
every `<img>` against the worker's finished jobs and lists the ones that fail in your prompt.

## Voices and sound (not used yet as of session 49)

Every film so far is silent. The environment has speech models that run on
the GPU from Julia (JuliaVision, no Python):

- **KokoroRunner** (in the project): text to speech, 54 voices, 24 kHz mono.
  ```julia
  using KokoroRunner
  k = Kokoro()
  voices(k)                                   # af_*/am_* American, bf_*/bm_* British
  a = speak(k, "One more stone for the pile!"; voice = "af_heart", speed = 1.1, trim = true)
  pronounce!(k, "Lumi" => "lˈumi")           # words it does not know are dropped: teach names
  ```
  Pick one voice for Lumi (and keep it, like its look), others for the
  critters. Run it in the worker for long narrations (a job kind), or in
  your session for a few lines.
- **WhisperRunner**: speech to text, to check a narration says what you meant.
- `../dev/JuliaVision/IndexTTS25Runner`: a more expressive TTS (emotion,
  voice cloning from a short sample); not in the project yet.
- Put sound into a film with ffmpeg (FFMPEG_jll): write the Float32 samples as
  wav (`-f f32le -ar 24000 -ac 1`), then `-i film.mp4 -i voice.wav -c:v copy
  -c:a aac -shortest`, or place lines at times with `adelay`. VideoEditor
  carries the sources' audio along its cut list when you edit there.

Ideas in Lumi's voice: narrate its films ("This is Cumulus. Every evening
it brings one more stone…"), read its pages aloud, little sounds and words
for the critters. The dashboard page is a Bonito app, so sound in the human's
browser is possible too.
