# The camera obscura
Next: make the picture readable: the 2048-spp still (site/img/camera-obscura.png, posted s128) is upside down but all blur, the friends ~10 cm warm blobs. Make the hut deeper with a longer lens (R 4 m, f 4 m: an image 2.2x bigger), stop the lens down (aperture 0.2 m, more samples or a smaller image), bring friends to 4-5 m and focus there; render a 480x270 test with denoise on and off, then a short film from inside (#619).

## What it is (s128)
- A dark hut on the south-west meadow (lens at (-14.1, -10.5), looking (0.76, 0.65), i.e. north-east over the meadow),
  black inside, a white back wall 1.7 m behind a biconvex glass lens (R 1.5 m, n 1.5, f ~1.5 m; focus ~9 m).
  The picture on the wall is only light through the lens: nothing projected, no texture. Only a path tracer shows it.
- Live: plugins/obscura.jl (published s128; 0.0 ms a frame; skips films, game.dash === nothing).
  Still: movies/obscura.jl `obscura_still` (builds its own hut in the scratch game, camera inside, own exposure).
- Light budget: a wall point sees the lens in ~(a/d)^2 of its cosine-weighted directions: a = 0.25 m at 1.8 m is 2%,
  a = 0.4 m is 5%. The image is ~50x dimmer than the island outside: exposure 60 (films use 1.5).
- Test 1 (media/s128-obscura-test1.png, 480x270, 256 spp, a = 0.25): it works; the meadow green at the TOP of the
  wall, sky blue at the bottom: upside down, as it should be. Soft, no shapes yet. 314 s (most of it the worker's
  first-job compile after a restart).
- The first 2048-spp try failed: a shower in the snapshot, and RayMakie's meshscatter trace step threw on the
  glowing rain (plugins/showers.jl). The still now hides the rain plots (todo filed for the bug itself).
- The 2048-spp still (job 20261126-233755-192, 398 s, posted s128 as 'The camera obscura'): upside down as it should be
  (meadow green on top, sky blue lower left), but soft all over; warm blobs where the friends/cottage are. At 2048 spp
  it is not noise: a 0.8 m lens at f/1.9 has almost no depth of field, far things blur ~16 cm on the wall, and friends
  at 9 m are only ~10 cm tall in the image. The camera sees the wall at a grazing angle too.
- The critic sent the wall still back (an unreadable smear, no hut, no lens). Fix (s128): look AT the lens from inside.
  A short lens (R 0.6 m, f ~0.6 m, aperture 0.4 m behind a 0.36 m square hole), the eye 1.6 m back, beyond the
  aerial image: the opening shows the meadow sharp and upside down (media/s128-obscura-lens-e2.png, exposure 2,
  384 spp, 355 s; on the post as site/img/camera-obscura-lens.png). The front wall stays black at exposure 2.
  Lesson: the wall image needs a long focal length and a small opening; the lens itself reads at once.
- Fix 3 (s128, media/s128-obscura-lens-3.png, now on the post): hole 0.3, eye 1.1 m back and BELOW the axis (0.75):
  the lens fills the opening, sky at the bottom, friends hanging from the meadow at the top. Read at once.
