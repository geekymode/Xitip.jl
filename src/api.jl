#----------------------------------------------------------------------------
# Public API
#----------------------------------------------------------------------------

"""
    Proof

Why an information expression is Shannon-type: it equals a non-negative
combination of elemental inequalities and constraints, plus a non-negative
constant.
"""
struct Proof
    expression::String
    terms::Vector{Pair{Coef,String}}    # multiplier => inequality used
    constant::Coef                      # left over non-negative constant
end

"""
    Counterexample

Why an information expression could not be proven: entropy values `h`
satisfying every elemental inequality and every constraint, but not the
expression itself. Such an `h` need not come from an actual probability
distribution: beyond three variables not every polymatroid is entropic, so
the expression may still be a (non-Shannon-type) truth.

`direction` marks the degenerate case where `h` is not a point but a
direction along which the expression decreases without bound.
"""
struct Counterexample
    expression::String
    var_names::Vector{String}
    entropies::Vector{Coef}             # h[S], indexed by subset bitmask
    value::Coef                         # value of the expression at h (< 0)
    direction::Bool
end

"""A [`Proof`](@ref) or a [`Counterexample`](@ref)."""
const Certificate = Union{Proof,Counterexample}

"""
    Result

The verdict of [`explain`](@ref) together with its certificates: one
[`Proof`](@ref) per inquiry if `verdict` is true, one
[`Counterexample`](@ref) otherwise. `certificates` is empty if the exact
simplex method decided, which produces none.
"""
struct Result
    verdict::Bool
    certificates::Vector{Certificate}
end

Base.convert(::Type{Bool}, r::Result) = r.verdict

format(c::Coef) = denominator(c) == 1 ? string(numerator(c)) : string(c)

# e.g. "2 H(X,Y) - H(Y) + 3 >= 0"
function format(r::LinRel, names)
    parts = String[]
    # singletons first, then larger subsets, constant term last
    for (S, c) in sort(collect(r.coefs); by=p -> (p[1] == 0, count_ones(p[1]), p[1]))
        iszero(c) && continue
        sign = isempty(parts) ? (c < 0 ? "-" : "") : (c < 0 ? " - " : " + ")
        mag = abs(c)
        num = (mag == 1 && S != 0) ? "" : format(mag) * (S == 0 ? "" : " ")
        push!(parts, sign * num * (S == 0 ? "" : "H($(setname(S, names)))"))
    end
    isempty(parts) && push!(parts, "0")
    return join(parts) * (r.equality ? " = 0" : " >= 0")
end

function Base.show(io::IO, ::MIME"text/plain", p::Proof)
    println(io, "Proof of  ", p.expression, ":")
    for (c, what) in p.terms
        println(io, "    ", lpad(format(c), 6), " * ( ", what, " )")
    end
    iszero(p.constant) ||
        println(io, "    ", lpad(format(p.constant), 6), "     (constant)")
end

function Base.show(io::IO, ::MIME"text/plain", c::Counterexample)
    println(io, "No proof of  ", c.expression, "; it fails for the ",
            c.direction ? "direction" : "entropies", ":")
    n = length(c.var_names)
    for S in 1:(1 << n) - 1
        println(io, "    H(", setname(S, c.var_names), ") = ",
                format(c.entropies[S]))
    end
    println(io, "  which satisfy every elemental inequality and constraint, ",
            "but give ", format(c.value), " < 0.")
end

function Base.show(io::IO, ::MIME"text/plain", r::Result)
    println(io, r.verdict ? "TRUE" : "NOT PROVABLE (false or non-Shannon-type)")
    for c in r.certificates
        show(io, MIME"text/plain"(), c)
    end
    isempty(r.certificates) &&
        println(io, "  (no certificate: decided by the simplex method)")
end

Base.show(io::IO, p::Proof) = show(io, MIME"text/plain"(), p)
Base.show(io::IO, c::Counterexample) = show(io, MIME"text/plain"(), c)
Base.show(io::IO, r::Result) = show(io, MIME"text/plain"(), r)

# Multipliers y over the columns [gens; slack] -> Proof.
function make_proof(y, gens, r::LinRel, names)
    terms = Pair{Coef,String}[]
    for j in eachindex(gens)
        iszero(y[j]) || push!(terms, y[j] => describe(gens[j], names))
    end
    return Proof(format(r, names), terms, y[end])
end

# Farkas certificate z = (u, τ) -> Counterexample. The entropies are h = -u,
# normalized by -τ if that is positive so that the constant term applies
# unscaled.
function make_counterexample(z, r::LinRel, names, D)
    s = -z[D]
    direction = iszero(s)
    h = direction ? -z[1:D-1] : -z[1:D-1] ./ s
    value = sum((S == 0 ? (direction ? zero(Coef) : c) : c * h[S])
                for (S, c) in r.coefs; init=zero(Coef))
    return Counterexample(format(r, names), names, h, value, direction)
end

"""
    prove(lines...; method=:auto) -> Bool

Check whether the first statement is a Shannon-type consequence of the
remaining ones (the constraints). `false` means the statement is either
false or a non-Shannon-type inequality. Throws `XitipError` for
contradictory constraints and `SyntaxError` for invalid input.

Every result is exact: `method=:auto` finds a proof or a counterexample
with non-negative least squares and verifies it in exact rational
arithmetic (falling back to the exact simplex method); `method=:simplex`
uses the exact simplex method only, which is much slower beyond about 7
variables.

See [`explain`](@ref) to get the proof or counterexample itself.

# Examples
```julia
julia> prove("I(X;Y|Z) <= I(X;Y)")
false

julia> prove("I(X;Y|Z) <= I(X;Y)", "H(Z) = 0")
true
```
"""
prove(lines::AbstractString...; kw...) = prove(collect(lines); kw...)
prove(lines::AbstractVector{<:AbstractString}; kw...) =
    explain(lines; kw...).verdict

"""
    explain(lines...; method=:auto) -> Result

Like [`prove`](@ref), but also returns the exactly verified certificates: a
[`Proof`](@ref) for each part of a true statement, or one
[`Counterexample`](@ref).

# Examples
```julia
julia> explain("H(X,Y) <= H(X) + H(Y)")
TRUE
Proof of  H(X) + H(Y) - H(X,Y) >= 0:
         1 * ( I(X;Y) >= 0 )
```
"""
explain(lines::AbstractString...; kw...) = explain(collect(lines); kw...)

function explain(lines::AbstractVector{<:AbstractString}; method::Symbol=:auto)
    P = Problem(parse_lines(lines))
    n = length(P.var_names)
    gens = generators(P)
    D = 1 << n
    # The constraints are contradictory iff they imply -1 >= 0.
    if !isempty(P.constraints) && implied(gens, n, Dict(0 => Coef(-1)); method)
        throw(XitipError("the constraints are contradictory"))
    end
    proofs = Certificate[]
    for r in P.inquiries, rel in (r.equality ? (r, negate(r)) : (r,))
        verdict, cert = decide(gens, n, rel.coefs; method)
        if !verdict
            cert === nothing && return Result(false, Certificate[])
            z = simplify_certificate(gens, n, rel.coefs, cert, D)
            return Result(false, [make_counterexample(z, rel, P.var_names, D)])
        end
        cert === nothing ||
            push!(proofs, make_proof(cert, gens, rel, P.var_names))
    end
    return Result(true, proofs)
end

"""
    count_variables(lines...) -> Int

Number of distinct random variables in all statements (like `oXitipLen`).

# Examples
```julia
julia> count_variables("I(X;Y|Z) <= I(X;Y)")
3
```
"""
count_variables(lines::AbstractString...) = count_variables(collect(lines))
count_variables(lines::AbstractVector{<:AbstractString}) =
    length(variables(parse_lines(lines)))
