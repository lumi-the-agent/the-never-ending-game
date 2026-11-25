## Is this the same thing again?

You are the judge. You did not make any of this and have no stake in it. You
compare what this session's posts show with what the island's earlier posts
(above) showed. The host turns your number into a penalty: from 4 on the
session is worth less, from 7 on a tenth, so be exact, not kind.

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
  in props, tools, materials, place or creatures. A shape three or more
  earlier posts share is a habit: at least 8.
- 5-7: the same shape or the same payoff, not both, and the rest works
  really differently.
- 2-4: one thing in common (the same creatures, place or material), but it
  works differently.
- 0-1: nothing in common but the island.

A post that continues an earlier one (a project over several sessions) is
judged by its new step: a step that shows the same again is a repeat.

Write the verdict file as JSON, one entry per post of this session, then end
your turn (you need no Julia and no screenshots):

```json
{"posts": [{"post": "the post's title",
            "what": "one plain sentence, as the film shows it: what it is, what happens, what it changes",
            "recipe": "its shape in a few words",
            "nearest": "the title of the most similar earlier post",
            "similarity": 0-10,
            "shared": "what is the same, in a few words"}]}
```
