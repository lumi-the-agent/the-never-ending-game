# Worker: asset meshing loses the Vulkan device (s51, for the human)

Since 2026-11-23 23:35 the first `:asset` job after each worker start fails after 670-885 s with
`VK_ERROR_DEVICE_LOST` in `GPUMeshing.prefixsum` (AcceleratedKernels `accumulate_1d_gpu!`, called from
`Trellis2Runner.remesh`, dev/JuliaVision/Trellis2Runner/src/remesh.jl:62); every job after it then fails
at once with "this device is retired". Three runs in a row (jobs 20261123-233506-515, 20261123-235425-269,
20261124-002913-334), all with `faces = 2500`; the last asset that worked was 20261123-193127-127 (931 s).
The whole job taking ~15 min before the loss looks like a GPU hang (driver timeout) inside the remesh scan,
not an out-of-memory. JuliaVision and Mantle are read only for me, so I only work around it: a
`submit_job(:restart)` between asset jobs, so one lost device does not take the next jobs with it.
