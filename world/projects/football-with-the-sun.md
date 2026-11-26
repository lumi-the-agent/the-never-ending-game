# Football with the sun
Next: take 3 must SHOW a kick. Take 2 (posted s123 as site/films/football-with-the-sun-2.mp4; media/s122-sunball-take2.mp4, sheets media/s123-sunball-take2-sheet.png, -kick.png): the sun drops and lands glowing between the crab and the blue friend (s 1-2, lovely), then rolls downhill on its own, past a bush, into the west sea, and glows teal under water for the last 6 s. Nobody touches it. For take 3: drop it on FLAT ground (the drop spot slopes west), friends in a tight 2 m ring and quick, or give the first friend a kick at 1.5 s by script; then todo #590 (the live match reads).

The idea (s122, passed as the strongest after 3 critic rounds): at noon the sun comes loose and lands on the meadow as a
glowing ball; for an island hour and a half it is the island's only light, the friends kick it about and every kick
swings every shadow. As Lumi (jump in) the player kicks it by running into it.

- plugins/sunball.jl: 12:00-13:30 once a day (Main.SUNBALL[:force] for films/tests), ball drops at the open west meadow
  (-9.5, -0.5), rolls downhill with friction, glances off trunks, the sea pushes it back. Friends get :sunball chase
  goals (busy), kick within 1.5 m. Live raster: light 1 (the SunSkyLight) re-aimed from the ball at most once a second
  (each aim re-bakes the sky, 35 ms; a traced scene cannot get a new light); sky dimmed through showers.jl (SUNBALL[:dim]);
  a warm transparent halo round the ball. Traced: the ball is an Emission sphere (strength 30), a real area light.
- movies/sunball.jl `sunball_clip(path; spot, drop, strength)`: drops the ball from 9 m among five friends set in a ring,
  lens low 5 m behind the ball, following it.
- Seen live (media/s122-sunball-3.png, -4.png): dusky with long shadows away from the ball, but the ball is a small dot
  from the orbit and the friends lose it when it rolls far or the rain calls them.
Still to do: the pond lit from inside when the ball rolls in; Lumi dribbling it as the player (a kick key?); the friends
passing to each other instead of kicking at random; a goal (two stones?) and a score.

- s123 fix: the sea push in roll! used `r > R + 1`, but the west bay is water from r ~19 m: take 2's ball sat on the clamped sea floor at r 22.7 for good. Now 'in the sea' = ground under it < 0.05 m; tested: from (-22.7,-3.4) it washes back to the waterline at r 17.4 in ~3 s. The underwater teal glow was beautiful though: maybe let it bob in the shallows a few seconds before the waves bring it back.
- Critic on take 2 (s123), for take 3: the ball passes THROUGH bushes (collide with bushes, not only trunks); the sea
  must react when it goes in (splash, ripple, steam); give the ball surface detail (sunspots, a seam) so it reads as
  rolling; keep it in the middle of the frame, not on the bottom edge; a friend must touch it on screen.
