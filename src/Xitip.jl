"""
    Xitip

Information Theoretic Inequality Prover in pure Julia.

Decides whether an information expression (over entropies and mutual
informations of discrete random variables) follows from the basic
properties of Shannon entropy, optionally under constraints such as Markov
chains, independence or functional dependence.

This is a reimplementation of Xitip/Citip/ITIP that needs only Julia's
standard library. Every answer comes with a proof or a counterexample that
is verified in exact rational arithmetic, so no floating point tolerance
decides whether an inequality holds.

```julia
julia> using Xitip

julia> prove("I(X;Y|Z) <= I(X;Y)", "H(Z) = 0")
true

julia> explain("H(X,Y) <= H(X) + H(Y)")
TRUE
Proof of  H(X) + H(Y) - H(X,Y) >= 0:
         1 * ( I(X;Y) >= 0 )
```

Exported: [`prove`](@ref), [`explain`](@ref), [`count_variables`](@ref),
[`Result`](@ref), [`Proof`](@ref), [`Counterexample`](@ref),
[`XitipError`](@ref), [`SyntaxError`](@ref).
"""
module Xitip

using LinearAlgebra: norm, svd
import Random
using Random: AbstractRNG

export prove, explain, print_proof, latex, latex_string, count_variables,
       Result, Proof, ProofStep, Counterexample, Certificate,
       XitipError, SyntaxError,
       proof_tree, chain_rule_tree, constraint_graph, entropy_table,
       entropic_samples, entropic_distribution, entropy_vector, evaluate,
       imeasure, shared_slice, shared_cone_vertices, shared_cone_facets,
       distribution_families,
       shared_coefficients, plot_imeasure,
       cone_rays,
       DecompositionTree, TreeNode, VariableGraph,
       plot_proof_tree, plot_chain_rule, plot_constraints,
       plot_counterexample, plot_entropy_cone, plot_entropy_space

const VERSION_STRING = "1.0.0"

"""Coefficients are exact rationals throughout."""
const Coef = Rational{BigInt}

# Random variables are identified with bits of an Int, subsets of them with
# bitmasks. The problem has 2^n-1 dimensions, so this limit is far beyond
# what can actually be solved.
const MAX_VARS = 30

include("errors.jl")
include("lexer.jl")
include("parser.jl")
include("variables.jl")
include("relations.jl")
include("generators.jl")
include("quantities.jl")
include("nnls.jl")
include("exactsolve.jl")
include("decide.jl")
include("simplex.jl")
include("api.jl")
include("trees.jl")
include("geometry.jl")
include("latex.jl")
include("cli.jl")

# Run a small workload while the package is precompiled, so that the first
# call in a fresh session does not pay for code generation (Julia >= 1.9
# caches the native code; older versions just ignore the result).
let io = IOBuffer()
    prove("I(X;Y|Z) <= I(X;Y)")
    prove("I(X;Z) <= I(X;Y)", "X/Y/Z")
    show(io, MIME"text/plain"(), explain("H(X,Y) <= H(X) + H(Y)"))
    show(io, MIME"text/plain"(), explain("H(X) <= H(Y)", "H(Y) >= 1"))
    count_variables("H(X) >= 0")
    main(String["--quiet", "H(X) >= 0"]; out=io, err=io)
end

end # module Xitip
