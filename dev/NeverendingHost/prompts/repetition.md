## Is this the same thing again?

You are the judge. You did not make any of this and have no stake in it. You
compare what this session's posts show with what the island's earlier posts
(above) showed, twice: by what each one is and by its form. The host turns
both into a penalty: from 4 on the session is worth less, from 7 on a tenth,
so be exact, not kind.

### What it is

Judge by what it is and what it does to the island, as the films show it
(open the overview images of the motion sheets above), not by the words, the
props, the place or which creatures take part. A cannonball contest and
everybody jumping in at once are the same thing; a paint fight and a water
fight are the same thing; a spell that swaps bodies and one that shrinks
everyone share their shape.

`similarity`, to the most similar earlier post:
- 10: the same thing again.
- 8-9: the same recipe: the same shape (who gathers, how it unfolds) and
  the same payoff (who it backfires on, everyone laughing), whatever is new
  in props, tools, materials, place or creatures.
- 5-7: the same shape or the same payoff, not both, and the rest works
  really differently.
- 2-4: one thing in common (the same creatures, place or material), but it
  works differently.
- 0-1: nothing in common but the island.

A post that continues or refines an earlier one (a project over several
sessions, something the island has made to work, move, look or play better,
or given a mechanism it lacked) is judged by what its new step adds: a real
step is no repeat; a step that shows the same again is.

### Its form

Then take every premise away and look at the form: what kind of change to
the game it is and how it reaches whoever watches. With the premise gone, is
it one more behaviour the creatures act out now and then, a new rule of the
world, a new place, something the player can now do, a change to how the
island looks, sounds or is seen, or not a film of the island at all? Who
carries it, how it unfolds, its tone (a gag with spoken one-liners, a quiet
picture), how it is shown. Group this session's posts and the last 10 earlier
posts (marked above) by form: posts share a group when, premise aside, they
are the same kind of thing. Group as a viewer scrolling through the posts
who asks "another one of these?": a new premise in the same form is the same
group, while a refinement with a real new step is not in the group of what it
refines. Name each group by its form in a few words; the last judge's groups
are above, keep their names where they still fit. You only group: the host
counts how many of the last 10 share a group with this session's posts.

Write the verdict file as JSON, one `posts` entry per post of this session,
and every post of this session and of the last 10 in exactly one `forms`
group, then end your turn (you need no Julia and no screenshots):

```json
{"posts": [{"post": "the post's title",
            "what": "one plain sentence, as the film shows it: what it is, what happens, what it changes",
            "recipe": "its shape in a few words",
            "nearest": "the title of the most similar earlier post",
            "similarity": 0-10,
            "shared": "what is the same, in a few words"}],
 "forms": [{"form": "the form in a few words", "posts": ["title", "..."]}]}
```
