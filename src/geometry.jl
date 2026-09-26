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
    imeasure(h, names=default_names(n)) -> Vector{Pair{String,Float64}}

The atoms of the I-measure at the entropy vector `h`: one value per region
of the Venn diagram of `n` random variables, named by the information
quantity it is. The atoms sum to the joint entropy, and every one of them
is an elemental inequality — except the ones shared by three or more
variables, which may be negative.

```jldoctest
julia> h = entropy_vector([1,0,0,1,0,1,1,0] ./ 4, 3, 2);   # Z = X xor Y

julia> imeasure(h)
7-element Vector{Pair{String, Float64}}:
 "H(X|Y,Z)" => 0.0
 "H(Y|X,Z)" => 0.0
 "H(Z|X,Y)" => 0.0
 "I(X;Y|Z)" => 1.0
 "I(X;Z|Y)" => 1.0
 "I(Y;Z|X)" => 1.0
 "I(X;Y;Z)" => -1.0
```
"""
function imeasure(h::AbstractVector{<:Real},
                  names::AbstractVector{<:AbstractString}=
                      default_names(trailing_ones(length(h))))
    n = length(names)
    length(h) == (1 << n) - 1 ||
        throw(XitipError("expected $((1 << n) - 1) entropies for " *
                         "$n variables, got $(length(h))"))
    out = Pair{String,Float64}[]
    for S in sort(1:(1 << n) - 1; by=S -> (count_ones(S), S))
        push!(out, atom_name(S, names) => atom_value(S, h, n))
    end
    return out
end

"""The atom inside every variable of `S` and outside every other one."""
function atom_value(S::Int, h::AbstractVector{<:Real}, n::Int)
    rest = ((1 << n) - 1) & ~S
    total = 0.0
    for T in 1:(1 << n) - 1
        T & ~S == 0 || continue                       # T a non-empty subset of S
        sign = isodd(count_ones(T)) ? 1.0 : -1.0
        total += sign * (h[T | rest] - (rest == 0 ? 0.0 : h[rest]))
    end
    return total
end

"""What that atom is called: `H(X|Y,Z)`, `I(X;Y|Z)`, `I(X;Y;Z)`."""
function atom_name(S::Int, names)
    n = length(names)
    inside = [names[i] for i in 1:n if S & (1 << (i - 1)) != 0]
    outside = [names[i] for i in 1:n if S & (1 << (i - 1)) == 0]
    given = isempty(outside) ? "" : "|" * join(outside, ",")
    return length(inside) == 1 ? "H($(inside[1])$given)" :
           "I($(join(inside, ";"))$given)"
end

"""
    shared_slice(h) -> (b, c) or nothing

The three-variable entropy vector `h` in the coordinates the cone's shape
lives in, normalised. `b` holds `I(X;Y|Z)`, `I(X;Z|Y)`, `I(Y;Z|X)` and `c`
holds `I(X;Y;Z)`, all divided by their total, which is the part of
`H(X,Y,Z)` that is not private to one variable. `nothing` when there is no
shared information to speak of, the three variables being independent.

The private atoms `H(X|Y,Z)`, `H(Y|X,Z)`, `H(Z|X,Y)` are dropped, which
loses no shape: each appears in exactly one elemental inequality, saying it
is non-negative, so they contribute a free orthant and nothing more.
"""
function shared_slice(h::AbstractVector{<:Real})
    length(h) == 7 || throw(XitipError("this slice is for three variables"))
    b = [atom_value(3, h, 3), atom_value(5, h, 3), atom_value(6, h, 3)]
    c = atom_value(7, h, 3)
    total = sum(b) + c
    total <= 1e-9 && return nothing
    return b ./ total, c / total
end

"""
    shared_cone_vertices() -> Vector{Pair{Vector{Float64},String}}

The five vertices of [`shared_slice`](@ref)'s picture of the three-variable
Shannon cone, with a distribution sitting on each. In those coordinates the
cone is a triangular bipyramid: one apex where all shared information is
common to all three variables, an equatorial triangle where `I(X;Y;Z)` is
zero, and a second apex where it is as negative as it can be.

```jldoctest
julia> [name for (_, name) in shared_cone_vertices()]
5-element Vector{String}:
 "X = Y = Z"
 "X = Y, Z independent"
 "X = Z, Y independent"
 "Y = Z, X independent"
 "Z = X xor Y"
```
"""
shared_cone_vertices() =
    [[0.0, 0.0, 0.0] => "X = Y = Z",
     [1.0, 0.0, 0.0] => "X = Y, Z independent",
     [0.0, 1.0, 0.0] => "X = Z, Y independent",
     [0.0, 0.0, 1.0] => "Y = Z, X independent",
     [0.5, 0.5, 0.5] => "Z = X xor Y"]

"""
    shared_cone_facets() -> Vector{Pair{Vector{Int},String}}

The six facets of the bipyramid [`shared_cone_vertices`](@ref) describes,
each as the vertices it is spanned by together with the elemental
inequality that is tight on it. Every facet of the drawn body is one of the
nine elemental inequalities made an equation; the other three,
`H(X|Y,Z), H(Y|X,Z), H(Z|X,Y) >= 0`, are tight everywhere on it, since the
slice is what is left after dropping exactly those directions.

```jldoctest
julia> [name for (_, name) in shared_cone_facets()]
6-element Vector{String}:
 "I(X;Y|Z) = 0"
 "I(X;Z|Y) = 0"
 "I(Y;Z|X) = 0"
 "I(X;Y) = 0"
 "I(X;Z) = 0"
 "I(Y;Z) = 0"
```
"""
shared_cone_facets() =
    [[1, 3, 4] => "I(X;Y|Z) = 0",
     [1, 2, 4] => "I(X;Z|Y) = 0",
     [1, 2, 3] => "I(Y;Z|X) = 0",
     [3, 4, 5] => "I(X;Y) = 0",
     [2, 4, 5] => "I(X;Z) = 0",
     [2, 3, 5] => "I(Y;Z) = 0"]

"""
    shared_coefficients(statement, names=default_names(3)) -> (w, private)

Rewrite a statement about three variables as an affine function of the
slice coordinates `b = (I(X;Y|Z), I(X;Z|Y), I(Y;Z|X))`: the statement holds
at a point of the slice exactly when `w[1] + w[2:4]'b >= 0`. `private`
holds the coefficients of the three private atoms `H(X|Y,Z)`, `H(Y|X,Z)`,
`H(Z|X,Y)`, which the slice drops.

If those are all non-negative, nothing is lost: raising a private atom only
raises the left side, so the statement holds on the whole cone exactly when
it holds on the slice. If one is negative the statement already fails by
raising that entropy alone, whatever the shared part does.
"""
function shared_coefficients(statement::AbstractString,
                             names::AbstractVector{<:AbstractString}=
                                 default_names(3))
    length(names) == 3 || throw(XitipError("this slice is for three variables"))
    coefs = relation_coefficients(statement, names)
    # atom S gets every coefficient whose subset it lies inside
    weight(S) = sum(Float64(c) for (mask, c) in coefs
                    if mask != 0 && mask & S != 0; init=0.0)
    constant = Float64(get(coefs, 0, 0))
    b, c = weight.((3, 5, 6)), weight(7)
    # on the slice the fourth atom is 1 - sum(b), and the constant rides along
    return ([constant + c; collect(b) .- c], weight.((1, 2, 4)))
end

"""Coefficients of a statement with everything moved to the left of `>= 0`."""
function relation_coefficients(statement::AbstractString,
                               names::AbstractVector{<:AbstractString})
    stmt = parse_statement(String(statement))
    stmt isa Relation ||
        throw(XitipError("not an inequality: $statement"))
    index = Dict(String(v) => i for (i, v) in enumerate(names))
    coefs = Dict{Int,Coef}()
    flip = stmt.rel === :le ? -1 : 1
    for term in stmt.left
        add_term!(coefs, index, term, flip)
    end
    for term in stmt.right
        add_term!(coefs, index, term, -flip)
    end
    return filter(kv -> !iszero(kv.second), coefs)
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

Draw the Shannon cone for `n` random variables, `n` being 2 or 3.

For two variables it lives in the three dimensions
`(H(X), H(Y), H(X,Y))`: three facets, one per elemental
inequality, meeting along three extreme rays — `X` constant, `Y` constant
and `X = Y`.

The cone is infinite, since the inequalities are homogeneous, so the drawing
truncates it at `H(X,Y) = reach`. A second panel shows that same slice
head on, where the cone is a triangle with the rays as its corners; this is
usually the easier of the two to read.

$PLOT_HINT

For three variables the cone lives in seven dimensions, but only four of
them carry any shape: written in the atoms of the I-measure, the nine
elemental inequalities are `H(X|Y,Z), H(Y|X,Z), H(Z|X,Y) >= 0`, which
involve nothing else, together with `I(X;Y|Z), I(X;Z|Y), I(Y;Z|X) >= 0` and
`I(X;Y) , I(X;Z), I(Y;Z) >= 0`. Dropping the three private atoms and
normalising leaves a three-dimensional body, and that body is a triangular
bipyramid — drawn exactly, with a distribution named at each of its five
vertices. Its equator is `I(X;Y;Z) = 0`, so the lower half is precisely
where three-way mutual information is negative. See
[`shared_slice`](@ref) and [`shared_cone_vertices`](@ref).

Each of its six facets is one of the six elemental inequalities that
survive, made an equation, and they are labelled as such. A statement about
three variables is a half space, so `cut` draws where its boundary meets
the body: the statement is provable exactly when no vertex of the body
falls outside, which the figure marks. See [`shared_cone_facets`](@ref) and
[`shared_coefficients`](@ref).

Keywords for three variables: `cut` is a statement to draw the boundary of,
`facets` labels the facets, plus `samples`, `alphabet`, `size`, `fontsize`,
`azimuth`, `elevation`, `rng`.

Keywords for two variables: `samples` scatters that many entropy vectors of random
distributions inside the cone, `outside` marks a point that breaks one of
the inequalities and shows where it lands on the slice, `style` is how the
samples are drawn (see [`entropic_samples`](@ref); `:uniform` covers the
cone evenly), `slice` draws the second panel, `azimuth` and `elevation` rotate the cone, `reach` is where
it is cut off, plus `alphabet`, `size` and `fontsize`.
"""
plot_entropy_cone(::Any...; kw...) = throw(XitipError(PLOT_HINT))

"""
    plot_imeasure(h; kwargs...) -> Figure

Draw the I-measure of two or three random variables as a Venn diagram with
every region carrying its value. `h` is an entropy vector, or a
[`Result`](@ref) whose counterexample supplies one. A negative region is
drawn in red: those are the ones no elemental inequality forbids.

$PLOT_HINT

Keywords: `names`, `title`, `size`, `fontsize`.
"""
plot_imeasure(::Any...; kw...) = throw(XitipError(PLOT_HINT))

"""
    plot_entropy_space(n; kwargs...) -> Figure

Look at the entropy vectors of `n` random variables, which live in
`2^n - 1` dimensions, by drawing sampled ones in two dimensions.

`coordinates` gives two information expressions to use as the axes, e.g.
`("I(X;Y)", "I(X;Y|Z)")`. Prefer this: the axes then mean something, and a
statement relating the two is a line you can see the points fall on one
side of.

Without it the axes are the two principal directions of the sample, which
carry the most spread but are mixtures of all `2^n - 1` entropies and mean
nothing on their own. Distance in that picture is not distance in any
quantity, and clumps in it are the sampler's dependency structures — one
clump per choice of which variable follows which — not features of the
cone. For three variables [`plot_entropy_cone`](@ref) draws the real thing
instead.

`color` names an expression to colour the points by, which shows where in
the cloud it turns negative.

$PLOT_HINT
"""
plot_entropy_space(::Any...; kw...) = throw(XitipError(PLOT_HINT))
