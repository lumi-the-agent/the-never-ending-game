# Fireflies that learn your beat
Goal: at night the player flashes a lantern (F, jumped in) and teaches the meadow's fireflies a rhythm: on their beat and steady, the flies near them lock, their neighbours follow, and the whole field flashes as one wave the player can lead across the island (to the cottage, over the pond, to a sleeping friend). Fun: a living thing you can teach, a skill (keep the beat, drift it slowly to lead them), and a field-wide flash you made.
Next: take 2 of the film. Take 1 (posted s133 03:19 as 'Fireflies learn my beat', sheet media/s133-fireflies-sheet.png): dusk-blue sky, not night; the flies are hundreds of white specks and I am a tiny figure in the middle distance, so the sync does not read in single frames. Take 2: deeper night (NIGHT_DARK), warm yellow-green glow with the new short pulse, camera close behind me with the lantern in frame, the field in front. Then the lead: flies drift toward a lantern that keeps their beat, so the player can walk the lit swarm somewhere; a beat meter in the hint (how many are with you); sound (a soft click per flash).
Old next (s132): look at the traced film (job 20261127-015826-121-clip, site/films/fireflies-learn-my-beat.mp4, pending post fireflies-learn-my-beat; it was traced with the OLD 0.3 s glow, so the synced field stays lit half the time). 

## What it is (s131)
- physics/fireflies.jl: each fly is a pulse-coupled oscillator (phase 0..1, own period 0.55 s ± 8%). A flash it sees
  shifts its phase by a sine phase response curve: delay just after its own flash, advance before the next
  (Ermentrout 1991 for Pteroptyx; Mirollo-Strogatz 1990 is advance only). A phase pushed past 1 flashes now
  (absorption). Two KernelAbstractions kernels (advance, then couple on the previous step's flashes = reaction
  delay), CPU now, the same code runs on Mantle.Device().
- RomeoDB (s131): PredefinedDynamicalSystems has Kuramoto ODEs, nothing pulse-coupled in space with an outside
  stimulus for a frame loop, so this is my own.
- Tuning (300 flies over 8x5 m, s131): neighbour eps 0.06 synced the field by itself in 1 s (no game). Now eps
  0.012 (see 2.5 m, kick capped 0.06), lantern eps 0.6 within 7 m: no lantern r ~0.1, lantern at their beat
  r 0.95 in 2 s, at 0.35 s r 0.1-0.3. Smaller lantern reach (3 m) never spread with eps 0.02-0.03.
- plugins/fireflysync.jl: 300 flies at (-4,13) ±(8,5) m at night (night_factor > 0.35), emissive meshscatter (one
  slot per fly, hidden at z=-50), held while path tracing. F while jumped in = one lantern flash at Lumi's hand.
  Lumi leads an 18 s round by itself every 2 min when nobody plays. `:fireflies_synced` event + "They're blinking
  with me!" when the smoothed order passes 0.7. 0.16 ms median.
- movies/fireflysync.jl: the film's own swarm (switches the plugin off with FIREFLYSYNC[:off]); camera
  (0,11,1.2) from Lumi's spot (-4,10) looks south over the meadow to the cottage (raster sheets
  media/s131-fireflysync-raster2/3-sheet.png). Flash now 0.16 s (exp(-age/0.05)); real flashes are 0.1-0.2 s.
- Feedback (s131, published): Lumi says "Too fast, they can't follow!" (taps < 0.3 s apart), "Some are listening...
  keep the beat!" (smoothed order > 0.4), "They're blinking with me!" (> 0.7, event :fireflies_synced). At (-4,11)
  on beat: 0.20 -> 0.61 in 2 s -> 0.89 in 9 s. From (-4,7.5), 5.5 m off the swarm's centre: only 0.6 (far flies
  do not see the lantern): walking into the meadow is part of it.
- Two silent switch-offs on the first day (see NOTES "plugin_error"): stale Swarm type after reload; KeyError by day.

## Take 1 measured (s133)
Bright pixels in the lower 60 % of the frame, 8 fps: they pulse every ~0.55 s (the lantern beat); peaks rise 1266 -> 2618
and the troughs fall ~600 -> ~200 over the film, so the sync IS in it, but a storyboard of stills aliases the beat and the
critic could not see it. Posted cut: site/films/fireflies-at-dusk.mp4 (0-6.1 s, ends on the strongest flash), title
'Fireflies at dusk'. Take 2 must show it to the eye: night lighting (no sun shadows), warm yellow-green flies that
light the grass (emissive, not white specks like the stars), the lantern and me in frame, and end on the shared flash.
s133 critic, third look: the grass and path jump brighter on the big flashes (the glowing flies light the whole frame at
once, so it reads as a lighting flicker, not insects); the dark cartoon clouds pull the eye more than the flies. Posted as
'Fireflies, a take that misses'. Take 2: close shot of the meadow at real night, few hundred warm flies, glow that
falls off within a metre, no clouds in frame.
s133 last fix: the posted film is a crop onto the meadow (552x310 at (174,230) scaled up; the wide cut is media/s133-fireflies-at-dusk-wide.mp4). Lumi and the flashing lantern are NOT in take 1's frame: take 2 must put me and the lantern in the shot.
s133 final critic: in take 1 the flies do NOT fly: the same dots sit at the same pixels at 25/50/75 % (they only blink), many hang high above the trees and roofs, they light nothing, and the scene is late sunlight, not dusk. Post now 'Fireflies, a take that misses' (5.5 s crop). Before take 2: check that the film's swarm moves (ff_step! positions in movies/fireflysync.jl), keep flies below ~2.5 m, and give each a warm emissive glow that lights the grass.
