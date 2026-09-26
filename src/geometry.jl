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
    entropic_samples(n; count=400, alphabet=2, style=:structured, rng, normalize=true)

Entropy vectors of `count` random distributions over `n` random variables,
as the columns of a matrix. Every column is a point the Shannon cone must
contain, since it comes from an actual distribution.

Two ways of drawing the distributions:

* `:structured` (the default) gives each variable a parent among the
  earlier ones and a noise level, so a sample runs from one variable being
  a function of another to the two being independent. This reaches across
  the cone.
* `:random` draws the joint distribution outright. Such a distribution is
  nearly always close to independent, so these samples pile up against the
  facet where the mutual information vanishes and leave most of the cone
  empty — which is worth seeing once, and is why it is not the default.
* `:uniform` works backwards, for two variables only: it picks a point of
  the cone uniformly and builds a distribution with exactly those
  entropies, through [`entropic_distribution`](@ref). This is the only
  style that covers the cone evenly, since it does not sample
  distributions at all; `alphabet` is then whatever the construction
  needs.

With `normalize`, each column is divided by its joint entropy, which puts
the samples on one slice of the cone rather than along the rays through it.
"""
function entropic_samples(n::Int; count::Int=400, alphabet::Int=2,
                          style::Symbol=:structured, concentration::Real=0.6,
                          rng::AbstractRNG=Random.default_rng(),
                          normalize::Bool=true)
    n < 1 && throw(XitipError("need at least one variable"))
    style in (:structured, :random, :uniform) ||
        throw(XitipError("style must be :structured, :random or :uniform"))
    style === :uniform && n != 2 &&
        throw(XitipError("uniform sampling of the cone is only available " *
                         "for two variables"))
    full = (1 << n) - 1
    out = zeros(Float64, full, count)
    for j in 1:count
        if style === :uniform
            out[:, j] = uniform_cone_point(rng, normalize)
            continue
        end
        p = style === :structured ?
            structured_distribution(n, alphabet, rng) :
            rand(rng, alphabet^n) .^
                (1 / clamp(concentration * exp(randn(rng)), 0.05, 20.0))
        h = entropy_vector(p, n, alphabet)
        normalize && h[full] > 0 && (h ./= h[full])
        out[:, j] = h
    end
    return out
end

"""
A point drawn uniformly from the slice of the two-variable cone, scaled to
fill the cone when `normalize` is off. The point is returned rather than
the distribution, but a distribution with exactly these entropies exists
and [`entropic_distribution`](@ref) builds it.
"""
function uniform_cone_point(rng::AbstractRNG, normalize::Bool)
    a, b = rand(rng), rand(rng)
    a + b < 1 && ((a, b) = (1 - a, 1 - b))      # fold into the triangle
    scale = normalize ? 1.0 : cbrt(rand(rng))   # spread through the volume
    return scale .* [a, b, 1.0]
end

"""
A joint distribution with a dependence structure drawn at random: each
variable either stands on its own or follows one of the earlier ones
through a random relabelling, corrupted with probability `noise`. Sweeping
the noise takes a pair from "one is a function of the other" to "the two
are independent", which is what carries the samples across the cone.
"""
function structured_distribution(n::Int, alphabet::Int, rng::AbstractRNG)
    parents = [i == 1 ? 0 : rand(rng, 0:i-1) for i in 1:n]
    noise = [rand(rng)^2 for _ in 1:n]          # favour strong dependence
    relabel = [Random.shuffle(rng, 0:alphabet-1) for _ in 1:n]
    own = map(1:n) do _
        weights = rand(rng, alphabet) .^
                  (1 / clamp(exp(randn(rng)), 0.1, 10.0))
        weights ./ sum(weights)
    end
    p = zeros(Float64, alphabet^n)
    for outcome in 0:alphabet^n - 1
        x = digits(outcome; base=alphabet, pad=n)
        probability = 1.0
        for i in 1:n
            if parents[i] == 0
                probability *= own[i][x[i] + 1]
            else
                target = relabel[i][x[parents[i]] + 1]
                probability *= (1 - noise[i]) * (x[i] == target) +
                               noise[i] * own[i][x[i] + 1]
            end
        end
        p[outcome + 1] = probability
    end
    return p
end

"""
    marginal_with_entropy(h) -> Vector{Float64}

A probability vector whose entropy is exactly `h` bits. Over `m` symbols
the family `(1-s, s/(m-1), ..., s/(m-1))` has entropy increasing in `s`
from 0 to `log2(m)`, so the right `s` is found by bisection.
"""
function marginal_with_entropy(h::Real)
    h <= 0 && return [1.0]
    m = max(2, ceil(Int, 2.0^h))
    spread(s) = (q = s / (m - 1);
                 -(1 - s) * log2(1 - s) - s * log2(q))
    entropy(s) = s <= 0 ? 0.0 : s >= (m - 1) / m ? log2(m) : spread(s)
    low, high = 0.0, (m - 1) / m
    for _ in 1:200                              # bisection on a monotone map
        mid = (low + high) / 2
        entropy(mid) < h ? (low = mid) : (high = mid)
    end
    s = (low + high) / 2
    return [1 - s; fill(s / (m - 1), m - 1)]
end

"""
    entropic_distribution(h) -> (p, alphabet)

A joint distribution of two random variables whose entropy vector is `h`,
which must satisfy the elemental inequalities. Every such `h` has one, so
the Shannon cone for two variables is exactly the set of entropy vectors of
distributions — nothing in the picture of it is unreachable.

The witness is `X = (U,V)` and `Y = (U,W)` for independent `U, V, W`, which
gives `I(X;Y) = H(U)`, `H(X|Y) = H(V)` and `H(Y|X) = H(W)`. The three
elemental inequalities say exactly that those three entropies are
non-negative, so the construction runs for any point of the cone.

```jldoctest
julia> p, alphabet = entropic_distribution([0.8, 0.5, 1.0]);

julia> round.(entropy_vector(p, 2, alphabet); digits=6)
3-element Vector{Float64}:
 0.8
 0.5
 1.0
```
"""
function entropic_distribution(h::AbstractVector{<:Real})
    length(h) == 3 ||
        throw(XitipError("the construction is for two variables, so three " *
                         "entropies: H(X), H(Y), H(X,Y)"))
    shared, x_only, y_only = h[1] + h[2] - h[3], h[3] - h[2], h[3] - h[1]
    min(shared, x_only, y_only) < -1e-12 &&
        throw(XitipError("not in the Shannon cone: $(collect(h))"))
    u, v, w = marginal_with_entropy.(max.((shared, x_only, y_only), 0))
    alphabet = max(length(u) * length(v), length(u) * length(w))
    p = zeros(Float64, alphabet^2)
    for (i, pu) in pairs(u), (j, pv) in pairs(v), (k, pw) in pairs(w)
        x = (i - 1) * length(v) + (j - 1)
        y = (i - 1) * length(w) + (k - 1)
        p[1 + x + alphabet * y] += pu * pv * pw
    end
    return p, alphabet
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
inequality, meeting along three extreme rays — `X` constant, `Y` constant
and `X = Y`.

The cone is infinite, since the inequalities are homogeneous, so the drawing
truncates it at `H(X,Y) = reach`. A second panel shows that same slice
head on, where the cone is a triangle with the rays as its corners; this is
usually the easier of the two to read.

$PLOT_HINT

Keywords: `samples` scatters that many entropy vectors of random
distributions inside the cone, `outside` marks a point that breaks one of
the inequalities and shows where it lands on the slice, `style` is how the
samples are drawn (see [`entropic_samples`](@ref); `:uniform` covers the
cone evenly), `slice` draws the second panel, `azimuth` and `elevation` rotate the cone, `reach` is where
it is cut off, plus `alphabet`, `size` and `fontsize`.
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
