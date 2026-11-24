# RayMakie raster: empty meshscatter fails

`dev/Makie/RayMakie/src/plots/mesh.jl:769` `instanced_bounds` calls `maximum` over the
instance scales; with zero instances (a meshscatter updated to `Point3f[]`) it throws
"reducing over an empty collection", and `raster_renderobject` fails for the whole frame/screenshot.

Fix: return empty bounds when `isempty(instances.positions)` (or pass `init` to the reductions).

Workaround in the game: plugins/areas.jl keeps one tiny instance at z = -50 instead of an empty plot.
