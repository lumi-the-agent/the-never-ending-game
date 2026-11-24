---
name: make-asset
description: Generate new 3D assets (text prompt to image to textured mesh) with JuliaVision in the background worker, reuse existing ones from the catalog, and place them in the world.
---

# Assets

1. Look first: `assets("lantern")` searches `world/assets/catalog.json`.
2. Generate in the worker (it runs one job at a time; the games and your
   session do not wait):

```julia
id = submit_job(:asset; prompt = "a small mossy stone lantern, stylized, soft colors", tags = ["prop", "stone"])
job(id)["status"]          # queued / running / done / failed (with "error")
j = wait_job(id)           # or check later; j["result"] has image, mesh, faces
```

   Roughly: the image takes ~4 min (Qwen-Image), the mesh several more
   (Trellis2). `NeverendingGame.estimate(NeverendingGame.TimingStats("world/state/timing.json"), "job:asset")`
   has the real median once a few ran.
3. The prompt describes ONE object and its look (shape, material, colours,
   style), never light, glow, a place or a background: "warm glow" or "in a
   forest" makes the image model paint a background, and a painted background
   becomes part of the mesh. The worker adds the framing and the cut-out
   request itself (`asset_prompt`), checks that the background came out
   transparent and that the object is not cut off at the border
   (`cutout_problem`), and tries two more seeds before it fails with the
   reason. Light comes later, from the material (`Hikari.Emission`) or a
   light in the scene. Still look at `image.png`: is it the object you meant,
   in the game's style (`world/STYLE.md`)?
   A mesh comes out about 1.5 units tall (Trellis2 fits it into a unit box)
   with 40k faces; pass `faces = 15_000` for small props that appear many
   times, more for a hero piece.
4. Try a spot in your sandbox (it stands with its bottom on the ground; size
   it with `scale`):
   `live_eval("NeverendingGame.place_asset(game, \"<id>\", (3.0, 2.0); scale = 1.0)")`
   It is an `AssetActor`. To keep it, place it from a plugin's `start!` (when
   it is not there yet) and `publish()`: world edits made with `live_eval`
   stay in the sandbox.

Drawing many copies in a plugin (trees, rocks, bushes, fence posts): load the
asset once and draw ALL copies of it with one instanced plot:

```julia
model = NG.load_asset(game.paths, id)            # or NG.AssetModel(metamesh; material = tinted_dict)
plot = NG.asset_instances!(game.stage.scene, model, positions;
                           rotation = [NG.rot_z(yaw) for ...], markersize = [Vec3f(s) for ...])
```

Hide one copy by setting its markersize to `Vec3f(0)` (update the vector),
never with a plot per copy: every plot sends its mesh and texture to each
browser that opens the page, and forty single-tree plots (2048² textures)
made the page take minutes to load and froze the game meanwhile. Textures for
the raster and the browser are 256² (`asset_color`); the path tracer uses the
full one from the material.

Single steps: `submit_job(:image; prompt)`, `submit_job(:mesh; image = path)`.
Path traced stills of the current world: `submit_job(:trace; path, samples = 128)`.

Meshes are saved with `Serialization` (`mesh.jls`, a GeometryBasics MetaMesh
with PBR material); load with `Serialization.deserialize`.
