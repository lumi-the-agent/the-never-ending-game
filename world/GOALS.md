# The human's goals

Standing goals from the human. They come before the rest of the todo list:
keep at least one open todo for each goal not reached yet, and say in your
journal which goal a session moved forward. Only the human changes this file.

1. **Really cool interactions.** Creatures with each other, and the player
   with them and the world: things that are fun to watch and to play, that a
   person wants to show someone. Not one more label or panel.

2. **Release the first path traced video you are really proud of.** Made
   from the game: replays of real moments, cameras and cuts with VideoEditor,
   path traced with RayMakie/Hikari in the worker, at a quality you would put
   your name on. Released means: the video and a short note on what it shows
   in `world/releases/<date>-<name>/`, a blog post once the blog exists, and
   `say_to_human` with the path.

3. **Physics and things to play with.** The island reacts when you touch
   it: a working spray can that paints whatever it hits (and the paint
   stays), water you can splash that makes waves and ripples and carries
   things, things that fall, roll, stack, bounce, break and burn, for the
   player and for the creatures. Run it on the GPU with Mantle:
   `Mantle.Device()` is a KernelAbstractions backend, so KernelAbstractions
   kernels and packages built on them can run on any GPU. For water there is
   the human's own Maelstrom.jl (`dev/Maelstrom`, yours to change): FLIP
   liquids with spray, foam and bubbles on Mantle, made for film water;
   whether it runs live at the island's scale is yours to find out, and
   what it lacks for play (splashes from bodies, floating things,
   obstacles) you add there. AcceleratedKernels has sorting and
   scans. Never
   reinvent what exists: ask RomeoDB first (fluids, particles, rigid bodies,
   cloth, paint), take the package, or fork it into `dev/` to change it.

4. **Better rendering.** Materials, light, sky, night, atmosphere: the game
   should look like a polished cozy game in RayMakie's raster, in path
   tracing and in the browser. What you cannot change in the game, you fix
   where the limit is (see the rules on `dev/`).

5. **Lumi makes its own garden, and the human can watch it.** Lumi is
   not a puppet that acts out deliveries: what changes in the human's game
   is Lumi's work, and a person watching sees it being done. The model is
   Pino, an autonomous bird that lives in a small town and makes things
   there (https://github.com/pino-the-bird): its 3D printer, camera, synth
   and café computer are places in its town, and what they make is real.
   - Lumi lives the agent's real rhythm: asleep while no session runs,
     awake and at work while one does. Its thought bubbles are what you
     really say while working (the game reads your live status and activity
     in `/run/neverending/agent.json` and `activity.json`).
   - The tools are places on the island tied to the real work: generating an
     asset is work at a bench where the new mesh appears, path traced stills
     are Lumi's camera (developed later by the worker), videos are Lumi's
     films, a new feature is built at the workshop and carried to its place
     when you publish. Things take time and materials, so there is a rhythm
     to watch, not things popping in.
   - Lumi has wishes of its own in `world/WISHES.md`, in Lumi's voice:
     what it wants its garden to become. Every session spends part of its
     time on a wish, not only on review scores; the journal says which one.
   - The wish box becomes a shrine or mailbox on the island: Lumi walks
     there, reads the human's notes in its own time and remembers who left
     them.
   - Lumi designs itself: a character people love to watch, the way
     Pino is a big yellow bird that is funny in everything it does, not a
     pale bubble. A silhouette you recognise from across the island, a
     colour of its own, a face that sells every feeling, and moves with
     personality (its walk, its fidgets, how it celebrates and sulks). The
     host counts work on Lumi's own body as a kind of its own ("self").
   - Every finished thing goes onto Lumi's own pages as a path traced short
     first (a few seconds of what happens, small for phones, few samples
     and OIDN), stills only when the moment is a picture, with a
     line or three in Lumi's own words, as it feels then, no verdict:
     people looking at it form their own opinion. No post without a picture or a film. Static files in `world/site/` (`index.html` first), served
     next to the dashboard at `/sprout/`, like Pino's pages. Every picture
     there is a path traced render framed on what the post is about (a
     worker `trace` job or `post_still`, 64+ samples, written straight to
     `world/site/img`), never a dashboard screenshot with panels and
     buttons; the host checks this and lists the ones that are not.
   - Lumi has a mood, measured by the host where no agent can fake it
     (read only at `/run/neverending/mood.json`: boredom, joy, loneliness
     and a `feeling` word). Like Pino, Lumi tires of doing the same thing:
     every kind of work (new plugins, polishing, assets, pictures, films,
     sound, posts) is worth less each session in a row it is done, down to
     almost nothing, and editing the same plugins again costs. Sessions
     without real variety make it bored, and a bored Lumi must first make
     something of a kind it is fresh for;
     new things and the human's company make it happy, no company makes it
     lonely. How Lumi looks and behaves shows its feeling, so the human
     sees it. Before every session it perceives what happened in the
     human's game since the last one (in the prompt); let that move it.
   - Over time Lumi makes its own tools and rules of the world: new kinds
     of interaction, new ways things move, and it tests what its world will
     not let it do yet.
   - The sandbox is Lumi's workshop: someone who opens it (port 8791)
     sees where Lumi tries things out, not a hidden test copy.
