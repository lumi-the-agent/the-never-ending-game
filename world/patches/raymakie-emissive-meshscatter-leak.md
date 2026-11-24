# Moving emissive meshscatter leaks Hikari area lights (path tracing OOM)

Found in session 34. Where: `dev/Makie/RayMakie/src/plots/meshscatter.jl`
(`meshscatter_update!` → `delete_trace_handles!` + `meshscatter_create!` →
`push_emitters!`) and Hikari `scene-mesh.jl` (`register_face_area_lights!` →
`flush_face_area_lights!` → `append!` on the `DiffuseAreaLight` set).

## What happens

A meshscatter with a Hikari `Emission` material (the game's 429 night-glow
flower motes + 429 halos) that moves every frame is rebuilt every frame while
path tracing: each instance is pushed as its own mesh and Hikari appends one
`DiffuseAreaLight` per emissive triangle. `delete!(hikari_scene, handle)` removes
the mesh but the area lights stay in the light set, so it only grows: after a
few seconds the light array needed 549 MB and Lava's pool (3.5 GB reserved) ran
out of memory.

Then the screen is stuck: `setrasterize!(screen, true)` sets
`screen.rasterize = true` before dropping the render objects; the drop resolves
`trace_renderobject` once more (another push, OOM), throws half way, and every
later `setrasterize!(screen, true)` returns early because the flag already
matches. ~60 plots keep `raster_path = false`, and every `colorbuffer` (screenshots,
UI tests) fails with "Failed to resolve trace_renderobject" until the process restarts.

## Suggested fixes

1. Hikari: `delete!(scene, handle)` of an emissive mesh should also remove (or
   free-list) the area lights `register_face_area_lights!` added for it.
2. RayMakie `setrasterize!`: set `screen.rasterize` only after the drop loop
   succeeded, and drop a trace render object without resolving its edge
   (read the cached value, do not recompute it).
3. Optional: an emissive meshscatter whose only change is `trace_transforms`
   could update the pushed meshes' vertices in place instead of re-pushing.

## Workaround in the game (session 34)

- `NeverendingGame.path_traced(game)`: plugins with moving glowing plots
  (nightglow, clouds, firefly home) hold them still while path tracing.
- `set_path_tracing!(game, false)` sets `rasterize = false` first, so switching
  off always redoes the full drop/rebuild.
