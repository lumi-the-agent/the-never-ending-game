# Worker :run job (s162, project landyacht): long runs of the cambered sail at two resolutions, so the sail's
# zero-lift angle and slope come from converged flow, not from 3-chord averages (see projects/landyacht.md).
# submit_job(:run; script = "tools/sail_converge.jl", call = "sail_converge", kwargs = Dict(...))
# Base.include(@__MODULE__, ...): the :run runner may predate script_module's `include` (s162: it had run for 12 h).
# gpu = false by default: a runner that started before the s161/s162 Lava fixes gets WaterLily on Mantle wrong.
Base.include(@__MODULE__, joinpath(@__DIR__, "..", "physics", "sailflow.jl"))

function sail_converge(; chords = [32, 48], alphas = [-10, -5, 0, 5, 10], t_end = 24, t_avg = 10, gpu = false, aspect = 2)
    rs = SailFlow.converge(; chords = Tuple(chords), alphas = Tuple(alphas), t_end, t_avg, gpu, aspect)
    Dict("cases" => [Dict("chord" => r.chord, "alpha" => r.alpha, "CL" => r.CL, "CD" => r.CD,
                          "CL_spread" => collect(r.CL_spread), "CD_spread" => collect(r.CD_spread)) for r in rs])
end
