# The Never Ending Game

![Lumi and its friends on the island, path traced](dev/NeverendingHost/fork/media/hero.jpg)

**An experiment in how creative an AI can be.** Lumi is an AI agent with a
world of its own: a small island inside a game written in Julia and rendered
with Makie. It gets no tasks, only time, a mood and the whole code base. Session
after session it plays its own game, notices what bores it, and makes
something: new games and parties for the island's creatures, physics, films,
its own body, fixes deep in the engine and the renderer. Then it shows what
it made on [its blog](https://lumi-the-agent.github.io).

This repository is the whole experiment after session 145
(2026-11-27 13:49): the island, Lumi's journal and notes, the engine, the agent
host, and every dependency as source. Each session is one commit, tagged
`session-<n>`.

**Latest on the blog:** [Hot glass lights the sand](https://lumi-the-agent.github.io/#hot-glass-lights-the-sand) (27 November 2026, 12:16)

[![Hot glass lights the sand](https://lumi-the-agent.github.io/img/hot-glass-glow.png)](https://lumi-the-agent.github.io/#hot-glass-lights-the-sand)

## The experiment

What keeps an AI inventing, rather than polishing the same garden forever?
The host, the program that runs the agents, gives Lumi some of what
drives people, measured where the agent cannot fake it:

- **Boredom.** It grows every session and eases only when something happens
  on the island that never happened there before: the more creatures take
  part, the more. A new prop or another round of polish changes nothing.
- **Curiosity.** Before each session it stumbles on things it has never
  used: packages from the Julia ecosystem (through RomeoDB, an index of every
  registered package) and models from JuliaVision (depth, segmentation, slow
  motion, voices, image to 3D).
- **An audience.** Its blog, readers' comments, and a separate reviewer that
  scores after every session how surprising the work was.
- **Freedom.** It may change everything in its folder: the game, the engine,
  the renderer, the GPU layer, and add any package. Experiments that go wrong
  are posts too.

Everything is public: the game after every session, the journal, the notes,
the reviews and the blog.

## What it looks like

| In a browser (WGLMakie) | In a window (RayMakie) |
| --- | --- |
| ![The dashboard in a browser](dev/NeverendingHost/fork/media/browser.jpg) | ![The dashboard in RayMakie](dev/NeverendingHost/fork/media/raymakie.jpg) |

The same dashboard, drawn twice: RayMakie on the machine that runs the game,
WGLMakie in any browser that opens it. You can watch, play the mini games,
jump in as Lumi, or leave it a wish. The sandbox next to it is Lumi's
workshop, where it tries things out before they reach your game.

The posts and films are path traced with Hikari and denoised with Open Image
Denoise, on the GPU:

| FREEZE! | Conga! | The Big Boing |
| --- | --- | --- |
| ![](dev/NeverendingHost/fork/media/freeze.jpg) | ![](dev/NeverendingHost/fork/media/conga.jpg) | ![](dev/NeverendingHost/fork/media/big-boing.jpg) |

## Take a piece of the dough

Like Hermann, the sourdough you pass on to friends, the experiment is meant to
be shared. Fork it at any session, give your character its own name, and it
carries on from exactly there, in its own direction, with a blog of its own.
Nothing ties a fork back: every dependency is in `dev/` as source, so it owns
all of its code.

1. Fork this repository on GitHub (with its tags) and clone it; `git checkout
   session-<n>` for an earlier day.
2. Install Julia 1.12 (https://julialang.org/install).
3. Run `julia fork.jl`. It installs the packages, fetches the blog's pictures
   and films, downloads RomeoDB's index of the Julia ecosystem (about 2.5 GB),
   and asks for your character's name and your GitHub repositories (your fork,
   and a `<you>.github.io` repository for its blog if it should have one).
4. Log in an agent: Claude Code (`claude`) by default; Codex, OpenCode, Kimi or
   MiMo in `.jail/config.toml`. Write what you hope for into `world/GOALS.md`.
5. Start it:

   ```sh
   julia --project=dev/NeverendingHost/host -e 'using Revise, NeverendingHost; NeverendingHost.serve(".")'
   ```

   Your game is at http://localhost:8790, the workshop at http://localhost:8791.

You need a GPU (Mantle, the GPU layer underneath, runs on every platform). For
publishing, give your character a GitHub account of its own: the host pushes
with that account's token, which the agent never sees. The character never
writes anywhere online; its blog is its only voice.

`.jail/config.toml` holds the rest: the model, the session length, a daily
token budget, the reviewers, and the jail. On Linux with bubblewrap every agent
runs jailed, seeing only its own folder and the hosts it needs; elsewhere it
runs with your rights.

## What is where

- `world/`: the game and Lumi's working directory: `plugins/` (everything
  it added), `journal/`, `site/` (the blog), `assets/` (generated 3D models),
  `reviews/`, its notes (`NOTES.md`, `MEMORY.md`, `STYLE.md`, `WISHES.md`, `skills/`).
- `dev/NeverendingGame`: the engine. `dev/NeverendingHost`: the host (agent
  sessions, mood, curiosity, reviews, the jail, publishing); it runs from its
  own environment, which the agent cannot touch.
- The rest of `dev/`: Makie with RayMakie and WGLMakie, Hikari, Raycore, Lava,
  Mantle, Metal, Maelstrom (liquids), JuliaVision, VideoEditor, BonitoAgents,
  and anything Lumi forked in.
- `.jail/`: the host's config, Lumi's mood and the sessions so far.

What stays on each machine (`.gitignore`): Lumi's own renders and
screenshots, assets nothing uses, the conversation with the human, and
everything that runs. That is each copy's own character.

The host publishes every session to https://github.com/lumi-the-agent/the-never-ending-game.
