#----------------------------------------------------------------------------
# What would make a statement true
#----------------------------------------------------------------------------
#
# A statement that is not provable is not the end of the story: it may be
# provable once something is assumed about the variables. The natural
# assumptions to try are the elemental quantities themselves, each forced to
# zero, because every one of them reads as a condition anybody would state
# out loud -- an independence, a conditional independence, or a functional
# dependence -- and because they are exactly the inequalities the prover
# already works with.
#
# The counterexample prunes the search. If a quantity is already zero at the
# counterexample, assuming it is zero leaves that counterexample in place, so
# that assumption cannot help on its own. A set of assumptions is worth
# testing only when at least one of its members is strictly positive there.

"""
One set of assumptions that makes a statement provable, with the
constraint text to feed back to [`prove`](@ref) and what each one means.
"""
struct SufficientCondition
    constraints::Vector{String}
    meanings::Vector{String}
end

"""
The result of [`sufficient_conditions`](@ref): the minimal sets of
assumptions found, and how far the search went.
"""
struct Conditions
    statement::Vector{String}
    found::Vector{SufficientCondition}
    candidates::Int
    tested::Int
    maxsize::Int
    exhausted::Bool
end

"""
    sufficient_conditions(lines...; maxsize=2, limit=6, budget=4000) -> Conditions

Find assumptions under which a statement that is not provable becomes
provable. Each candidate assumption sets one elemental quantity to zero —
an independence, a conditional independence, or a functional dependence —
and the search reports the smallest sets that work, leaving out any set
that merely extends one already found.

The statement must not already be provable; [`explain`](@ref) it first if
you are not sure.

```jldoctest
julia> conditions = sufficient_conditions("I(X;Y|Z) <= I(X;Y)");

julia> [only(c.constraints) for c in conditions.found]
3-element Vector{String}:
 "I(X;Y|Z) = 0"
 "I(X;Z|Y) = 0"
 "I(Y;Z|X) = 0"
```

Conditioning can raise mutual information, so that statement is not
provable; it becomes provable as soon as any one of the three variables is
conditionally independent of another, the second and third of those being
the Markov chains `X/Y/Z` and `Y/X/Z`.

`maxsize` is how many assumptions may be combined, `limit` how many sets to
report, and `budget` a cap on how many statements are proven along the way,
which matters for many variables: the number of candidates is the number of
elemental inequalities, `n + binomial(n,2) * 2^(n-2)`.
"""
sufficient_conditions(lines::AbstractString...; kw...) =
    sufficient_conditions(collect(lines); kw...)

function sufficient_conditions(lines::AbstractVector{<:AbstractString};
                               maxsize::Int=2, limit::Int=6,
                               budget::Int=4000, method::Symbol=:auto)
    maxsize >= 1 || throw(XitipError("maxsize must be at least one"))
    result = explain(lines; method=method)
    result.verdict &&
        throw(XitipError("the statement is already provable, so there is " *
                         "nothing to assume"))

    stmts, sources = parse_statements(lines)
    P = Problem(stmts, sources)
    names = P.var_names
    texts, meanings = candidate_conditions(length(names), names)

    # a quantity that is already zero at the counterexample cannot rule it
    # out, so a working set has to move at least one that is not
    useful = trues(length(texts))
    counter = findfirst(c -> c isa Counterexample, result.certificates)
    if counter !== nothing
        h = result.certificates[counter].entropies
        for (k, g) in pairs(elemental_inequalities(length(names)))
            value = sum(Float64(v) * Float64(h[mask]) for (mask, v) in g.a;
                        init=0.0)
            useful[k] = value > 1e-9
        end
    end

    found = SufficientCondition[]
    tested = 0
    exhausted = true
    works(set) = prove([lines; texts[set]]; method=method)
    covered(set) = any(issubset(c, set) for c in
                       (Set(indexin(f.constraints, texts)) for f in found))

    for size in 1:maxsize
        for set in combinations(eachindex(texts), size)
            any(useful[k] for k in set) || continue
            covered(Set(set)) && continue
            if tested >= budget
                exhausted = false
                break
            end
            tested += 1
            works(set) || continue
            push!(found, SufficientCondition(texts[set], meanings[set]))
            length(found) >= limit && (exhausted = false; break)
        end
        (length(found) >= limit || tested >= budget) && break
    end
    return Conditions(collect(String, lines), found, length(texts), tested,
                      maxsize, exhausted)
end

"""Every elemental quantity, as a constraint and as a sentence."""
function candidate_conditions(n::Int, names)
    texts, meanings = String[], String[]
    for g in elemental_inequalities(n)
        name = name_quantity(Dict(g.a), names)
        name === nothing && continue
        push!(texts, name * " = 0")
        push!(meanings, condition_meaning(g, names))
    end
    return texts, meanings
end

"""What forcing one elemental quantity to zero says about the variables."""
function condition_meaning(g::Generator, names)
    i, j, K = g.data
    given = [names[v + 1] for v in 0:length(names)-1 if K & (1 << v) != 0]
    if g.kind === :entropy
        others = [names[v + 1] for v in 0:length(names)-1 if v != i]
        return "$(names[i + 1]) is a function of $(join(others, ", ")), " *
               "written $(names[i + 1]):$(join(others, ","))"
    end
    a, b = names[i + 1], names[j + 1]
    isempty(given) &&
        return "$a and $b are independent, written $a.$b"
    # with everything else given, this is exactly a three part Markov chain
    return "$a and $b are independent given $(join(given, ", "))" *
           (length(given) + 2 == length(names) ?
            ", the Markov chain $a/$(join(given, ","))/$b" : "")
end

"""Subsets of `xs` of the given size, in order."""
function combinations(xs, size::Int)
    out = Vector{Int}[]
    n = length(xs)
    size > n && return out
    index = collect(1:size)
    while true
        push!(out, [xs[k] for k in index])
        k = size
        while k >= 1 && index[k] == n - size + k
            k -= 1
        end
        k == 0 && break
        index[k] += 1
        for m in k+1:size
            index[m] = index[m-1] + 1
        end
    end
    return out
end

function Base.show(io::IO, ::MIME"text/plain", c::Conditions)
    println(io, "Not provable as it stands:")
    for line in c.statement
        println(io, "    ", line)
    end
    if isempty(c.found)
        print(io, "\nNo set of at most ", c.maxsize,
              c.maxsize == 1 ? " assumption" : " assumptions",
              " out of ", c.candidates, " candidates makes it provable")
        c.exhausted || print(io, " within the budget")
        println(io, ".")
        return
    end
    println(io, "\nProvable if you assume any one of these:")
    for (k, condition) in pairs(c.found)
        println(io)
        println(io, "  ", k, ". ", join(condition.constraints, "  and  "))
        for meaning in condition.meanings
            println(io, "       ", meaning)
        end
    end
    c.exhausted ||
        println(io, "\n(search stopped early; there may be more)")
end

Base.show(io::IO, c::Conditions) = show(io, MIME"text/plain"(), c)
