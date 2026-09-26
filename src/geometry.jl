#----------------------------------------------------------------------------
# The geometry of entropy vectors
#----------------------------------------------------------------------------
#
# An entropy vector of n random variables is a point of R^(2^n-1), one
# coordinate per non-empty subset. The elemental inequalities cut out the
# Shannon cone Γ, which holds every vector that satisfies them; the entropic
# vectors, those that come from an actual distribution, sit inside it. For
# two variables the cone is three-dimensional and can be drawn exactly; past
# that the pictures come from sampling and projection.

"""
    entropy_vector(p) -> Vector{Float64}

The entropy of every non-empty subset of `n` random variables under the
joint distribution `p`, which is indexed by outcome `0:alphabet^n - 1`
written in base `alphabet`. Entry `S` of the result is `H` of the subset
whose bitmask is `S`, in bits.
"""
function entropy_vector(p::AbstractVector{<:Real}, n::Int, alphabet::Int)
    total = sum(p)
    full = (1 << n) - 1
    h = zeros(Float64, full)
    for S in 1:full
        marginal = Dict{Int,Float64}()
        for (i, prob) in enumerate(p)
            prob <= 0 && continue
            outcome, key, digits = i - 1, 0, 1
            for v in 0:n-1
                symbol = outcome % alphabet
                outcome ÷= alphabet
                if S & (1 << v) != 0
                    key += symbol * digits
                    digits *= alphabet
                end
            end
            marginal[key] = get(marginal, key, 0.0) + prob / total
        end
        h[S] = -sum(q * log2(q) for q in values(marginal) if q > 0; init=0.0)
    end
    return h
end

"""
    entropic_samples(n; count=400, alphabet=2, concentration=0.6, rng, normalize=true)

Entropy vectors of `count` random distributions over `n` random variables,
as the columns of a matrix. Every column is a point the Shannon cone must
contain, since it comes from an actual distribution.

`concentration` shapes the distributions: values below 1 favour peaked ones
and so spread the samples through the cone, rather than piling them up near
the uniform distribution. With `normalize`, each column is divided by its
joint entropy, which puts the samples on one slice of the cone instead of
along the rays through it.
"""
function entropic_samples(n::Int; count::Int=400, alphabet::Int=2,
                          concentration::Real=0.6,
                          rng::AbstractRNG=Random.default_rng(),
                          normalize::Bool=true)
    n < 1 && throw(XitipError("need at least one variable"))
    full = (1 << n) - 1
    out = zeros(Float64, full, count)
    for j in 1:count
        # a Dirichlet-ish draw: powers of uniforms, which concentrate the
        # mass on fewer outcomes as the exponent shrinks. The exponent
        # itself varies from sample to sample, so the points spread through
        # the cone instead of gathering where one peakedness puts them.
        shape = clamp(concentration * exp(randn(rng)), 0.05, 20.0)
        p = rand(rng, alphabet^n) .^ (1 / shape)
        h = entropy_vector(p, n, alphabet)
        normalize && h[full] > 0 && (h ./= h[full])
        out[:, j] = h
    end
    return out
end

"""
    expression_coefficients(expression, names) -> Dict{Int,Coef}

The coefficients of an information expression over the variables `names`,
keyed by subset bitmask (key 0 is the constant term). The expression is
anything that could stand on one side of a statement.

```jldoctest
julia> sort(collect(Xitip.expression_coefficients("I(X;Y)", ["X", "Y"])))
3-element Vector{Pair{Int64, Rational{BigInt}}}:
 1 => 1
 2 => 1
 3 => -1
```
"""
function expression_coefficients(expression::AbstractString,
                                 names::AbstractVector{<:AbstractString})
    # an expression is a statement with everything already on one side
    stmt = parse_statement(String(expression) * " >= 0")
    stmt isa Relation ||
        throw(XitipError("not an information expression: $expression"))
    index = Dict(String(v) => i for (i, v) in enumerate(names))
    coefs = Dict{Int,Coef}()
    for term in stmt.left
        for v in (term.quantity === nothing ? String[] :
                  [w for vl in varlists(term.quantity) for w in vl])
            haskey(index, v) ||
                throw(XitipError("unknown variable $v in $expression"))
        end
        add_term!(coefs, index, term, 1)
    end
    return filter(kv -> !iszero(kv.second), coefs)
end

"""
    evaluate(expression, names, h) -> Float64

The value of an information expression at the entropy vector `h`, whose
entry `S` is the entropy of the subset with bitmask `S`.

```jldoctest
julia> evaluate("I(X;Y)", ["X", "Y"], [1.0, 1.0, 2.0])   # independent bits
0.0
```
"""
function evaluate(expression::AbstractString,
                  names::AbstractVector{<:AbstractString},
                  h::AbstractVector{<:Real})
    coefs = expression_coefficients(expression, names)
    return sum(Float64(c) * (S == 0 ? 1.0 : h[S]) for (S, c) in coefs; init=0.0)
end

evaluate(expression::AbstractString, h::AbstractVector{<:Real}) =
    evaluate(expression, default_names(Int(log2(length(h) + 1))), h)

"""Variable names `X1, X2, ...`, or `X, Y, Z, W` for the small cases."""
default_names(n::Int) =
    n <= 4 ? ["X", "Y", "Z", "W"][1:n] : ["X$i" for i in 1:n]

"""
    cone_rays(n) -> Vector{Pair{Vector{Int},String}}

The extreme rays of the Shannon cone, with what each one is, for the cases
small enough to write down: one variable, where the cone is a half line,
and two, where it is spanned by three rays.

```jldoctest
julia> cone_rays(2)
3-element Vector{Pair{Vector{Int64}, String}}:
 [1, 0, 1] => "Y constant"
 [0, 1, 1] => "X constant"
 [1, 1, 1] => "X = Y"
```
"""
function cone_rays(n::Int)
    n == 1 && return [[1] => "X"]
    n == 2 && return [[1, 0, 1] => "Y constant",
                      [0, 1, 1] => "X constant",
                      [1, 1, 1] => "X = Y"]
    throw(XitipError("the extreme rays are only written down for one or two " *
                     "variables; sample the cone instead"))
end

"""
    project(samples, dims=2) -> (coordinates, variance)

Project the columns of `samples` onto their `dims` principal directions,
returning the coordinates and the share of the variance each direction
carries. Used to look at entropy vectors of more than two variables, where
the space itself has 2^n-1 dimensions.
"""
function project(samples::AbstractMatrix{<:Real}, dims::Int=2)
    centre = sum(samples; dims=2) ./ size(samples, 2)
    centred = samples .- centre
    decomposition = svd(centred)
    dims = min(dims, length(decomposition.S))
    coordinates = decomposition.U[:, 1:dims]' * centred
    weights = decomposition.S .^ 2
    return coordinates, weights[1:dims] ./ sum(weights)
end

#----------------------------------------------------------------------------
# Plotting, provided by the extension
#----------------------------------------------------------------------------

"""
    plot_entropy_cone(; kwargs...) -> Figure

Draw the Shannon cone for two random variables, which lives in the three
dimensions `(H(X), H(Y), H(X,Y))`: three facets, one per elemental
inequality, meeting along three extreme rays.

$PLOT_HINT

Keywords: `samples` scatters that many entropy vectors of random
distributions inside the cone, `outside` marks a point that breaks one of
the inequalities, `alphabet`, `size`, `fontsize`.
"""
plot_entropy_cone(::Any...; kw...) = throw(XitipError(PLOT_HINT))

"""
    plot_entropy_space(n; kwargs...) -> Figure

Look at the entropy vectors of `n` random variables, which live in
`2^n - 1` dimensions, by projecting sampled ones onto their two principal
directions. `color` names an information expression to colour the points
by, e.g. `"I(X;Y;Z)"`, which shows where in the cloud it turns negative.

$PLOT_HINT
"""
plot_entropy_space(::Any...; kw...) = throw(XitipError(PLOT_HINT))
