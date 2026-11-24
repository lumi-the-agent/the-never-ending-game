---
name: find-existing-code
description: Find existing functions before writing new ones - RomeoDB code search over the Julia ecosystem, grepping the local checkouts (Makie, RayMakie, Hikari, JuliaVision, VideoEditor). Use before implementing anything non-trivial.
---

# Find before you build

- **RomeoDB** (`romeo` MCP tools): `search` for functions by what they do,
  `search_packages`, `definition` for source, `find_existing` with a sketch of
  the code you are about to write, `similar_code`. It knows every registered
  package; local unregistered ones may be missing.
- **The checkouts** in `../dev` (read only), grep them:
  - `Makie/` (Makie, RayMakie in `Makie/RayMakie`, ComputePipeline): plots,
    GUI blocks (`Button`, `Slider`, `Menu`, `Textbox`, `Label`), cameras
  - `Hikari/`: materials (`Diffuse`, `Plastic`, `Glass`, `Emission`, `CoatedDiffuse`, …), lights, sky
  - `JuliaVision/`: models (image generation, image to 3D, segmentation,
    depth, speech, frame interpolation), each in its `*Runner` folder
  - `VideoEditor/`: video projects, scene clips, export, contact sheets
  - `BonitoAgents/`: the agent tooling you run on (read, do not change)
- **The engine**: `../dev/NeverendingGame/src` (`game.jl` loop, `plugins.jl`,
  `actors.jl`, `world.jl`, `behavior.jl`, `species.jl`, `scenery.jl`,
  `render.jl`, `assets.jl`, `dashboard.jl`, `live.jl`).
