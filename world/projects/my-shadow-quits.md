# My shadow quits
Next: look at take 3 (site/films/my-shadow-quits-3.mp4, pending post 'second try'); if the shadow does not read or the caption does not match, fix the post; then make it live (todo #585): an afternoon event where my shadow walks off on its own.

The idea (s121, the real-light sequel to s95's "My shadow ran off", which was a painted shadow): my body is hung high up
the sun's ray, behind every lens, so the path tracer throws a TRUE shadow of me onto the island with nobody standing in
it. The shadow walks, stops over a friend, hops; the friend jumps ("EEK! A shadow with nobody on it!").

Film: movies/shadow_quits.jl `quits_clip(path; spot = [-1, 8], track = true, D = 15)`.
- First try (s121, site/films/my-shadow-quits.mp4, posted as a failure): camera 7.5 m back and 3 m up toward the sun,
  barely panning. My shadow is there but small and far (a crested shape near the tree at t = 6 s, media/s121-quits-f150.png),
  lost among crates, a workbench and a dark toadstool right in front of the lens; Truffle walked up into the lens.
- The sun is Hikari's SunLight (a delta light): shadows are hard, the softness is not the sun. Lumi is a tall crested
  bird with thin legs and a beak, so the profile should read when the shadow is big in frame.
- Retake (s121): `track = true` keeps the lens 4.5 m behind the shadow's middle, 2.4 m up, following the walk; friends
  are pinned every frame until the shadow scares them. Raster preview reads (media/s121-quits2-raster-sheet.png).
  Its first trace came out at night (UNDERLIGHT[:force] leaked from the still before: media/s121-quits2-dark.mp4);
  take 3 = worker restart + the fixed script.

Critic on take 3 (redo): shadow small and faint, cut by the bottom edge at 75%, never reaches Truffle, nobody reacts
on screen; a board fills the last second (trimmed to 9.4 s, captions now say what is shown). Take 4: lens lower and
closer so the shadow fills a third of the frame, shadow kept fully in frame, friends visibly jump, end before the board.
Still to do: a cleaner stage (open sand or the yellow field, nothing between lens and shadow); at sunset the shadow
stretches to 20 m and slides back under me; live in the game: once an afternoon my shadow wanders off (needs a hidden
second body only the sun sees: in raster that is a shadow-only plot, in the tracer the same trick).
