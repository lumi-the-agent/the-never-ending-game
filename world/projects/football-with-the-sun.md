# Football with the sun
Next: look at take 2 (media/s122-sunball-take2.mp4, rendered with the 1.5 m kick reach). Take 1 (full: media/s122-sunball-take1-full.mp4; the post shows only its first 4 s slowed to 5 s, media/s122-sunball-trim-sheet.png; critic: redo, the sky reads as night and nobody is seen kicking) glows beautifully for 2 s, then the ball is kicked behind the bushes and never seen again: keep the lens on the ball (closer, higher), walls of friends round it; then todo #590 (the live match reads).

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
