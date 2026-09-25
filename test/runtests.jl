using Test
using Random

using Xitip
using Xitip: Problem, parse_lines, parse_statement, tokenize, generators,
             elemental_inequalities, count_elemental, homogenize, nnls,
             certify_true, certify_false, certify_false_exact, exact_solve,
             simplex, decide, implied, Coef, LinRel, SIMPLEX_FALLBACKS,
             describe, format

@testset "Xitip" begin
    include("parser.jl")
    include("prover.jl")
    include("certificates.jl")
    include("random.jl")
    include("cli.jl")
    include("proofsteps.jl")
    include("latex.jl")
    include("quantities.jl")
end
