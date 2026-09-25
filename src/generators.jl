#----------------------------------------------------------------------------
# Shannon-type LP
#----------------------------------------------------------------------------
#
# Let h be the vector of joint entropies. An inequality  v·h + v0 >= 0  is
# Shannon-type (given constraints  a_i·h + b_i >= 0) iff it follows from the
# elemental inequalities and the constraints. By the affine Farkas lemma
# (for a feasible constraint system) this holds iff there are multipliers
# y >= 0 with
#
#       Σ y_i a_i = v    and    Σ y_i b_i <= v0,
#
# where the a_i range over the elemental inequalities (b_i = 0) and the
# constraints (equalities contribute both a_i and -a_i). Hence we solve
#
#       min b·y   s.t.   A y = v,  y >= 0
#
# and the inequality holds iff the LP is feasible and its optimum is <= v0
# (or it is unbounded, which only happens for contradictory constraints).
# A solution y is a certificate: it expresses the inequality as a
# non-negative combination of elemental inequalities and constraints.

"""
    Generator(a, b, line, kind, data)

A generator  `a·h + b >= 0`  of the cone of implied inequalities.

`line` is set on the first generator of an equality constraint (the next
generator is then its negation). `kind` and `data` describe where the
generator comes from, so that certificates can be printed:

| kind          | data                | meaning                          |
|:--------------|:--------------------|:---------------------------------|
| `:entropy`    | `(i, 0, 0)`         | `H(X_i | rest) >= 0`             |
| `:mutinf`     | `(i, j, K)`         | `I(X_i ; X_j | X_K) >= 0`        |
| `:constraint` | `(row, sign, 0)`    | constraint `row`, negated if < 0 |

`equality` records that the constraint was written as an equality, so the
generator is not merely non-negative but zero.
"""
struct Generator
    a::Vector{Pair{Int,Coef}}
    b::Coef
    line::Bool
    kind::Symbol
    data::NTuple{3,Int}
    equality::Bool
end
Generator(a, b, line, kind, data) = Generator(a, b, line, kind, data, false)

"""
Elemental inequalities for `n` random variables:

    H(X_i | X_rest) >= 0               for all i
    I(X_i ; X_j | X_K) >= 0            for all i < j, K ⊆ rest \\ {i,j}

These generate all Shannon-type inequalities.
"""
function elemental_inequalities(n::Int)
    gens = Generator[]
    full = (1 << n) - 1
    pair(k, v) = k => Coef(v)
    for i in 0:n-1
        c = full ⊻ (1 << i)
        a = [pair(full, 1)]
        c != 0 && push!(a, pair(c, -1))
        push!(gens, Generator(a, Coef(0), false, :entropy, (i, 0, 0)))
    end
    for i in 0:n-2, j in i+1:n-1
        A, B = 1 << i, 1 << j
        rest = full ⊻ A ⊻ B
        K = rest
        while true          # enumerate all subsets K of rest
            a = [pair(A | K, 1), pair(B | K, 1), pair(A | B | K, -1)]
            K != 0 && push!(a, pair(K, -1))
            push!(gens, Generator(a, Coef(0), false, :mutinf, (i, j, K)))
            K == 0 && break
            K = (K - 1) & rest
        end
    end
    return gens
end

"""Number of elemental inequalities (they come first in `generators`)."""
count_elemental(n::Int) = n < 2 ? n : n + binomial(n, 2) << (n - 2)

"""
    generators(P::Problem) -> Vector{Generator}

All elemental inequalities followed by the constraints of `P`. An equality
constraint contributes two generators (itself and its negation).
"""
function generators(P::Problem)
    gens = elemental_inequalities(length(P.var_names))
    for r in P.constraints
        a = [k => v for (k, v) in r.coefs if k != 0]
        b = get(r.coefs, 0, zero(Coef))
        push!(gens, Generator(a, b, r.equality, :constraint, (r.row, 1, 0),
                              r.equality))
        r.equality && push!(gens, Generator([k => -v for (k, v) in a], -b,
                                            false, :constraint, (r.row, -1, 0),
                                            true))
    end
    return gens
end

# Names of the variables in the subset `mask`, e.g. "X,Y".
setname(mask::Int, names) =
    join((names[i] for i in 1:length(names) if mask & (1 << (i-1)) != 0), ",")

"""
    describe(g::Generator, names, sources=String[]) -> String

The generator as a readable information expression, e.g. `"I(X;Y|Z) >= 0"`.
A constraint is named by its number and, if `sources` has it, its own text.
"""
function describe(g::Generator, names, sources=String[])
    full = (1 << length(names)) - 1
    if g.kind == :entropy
        i = g.data[1]
        rest = full ⊻ (1 << i)
        cond = rest == 0 ? "" : "|" * setname(rest, names)
        return "H($(names[i+1])$cond) >= 0"
    elseif g.kind == :mutinf
        i, j, K = g.data
        cond = K == 0 ? "" : "|" * setname(K, names)
        return "I($(names[i+1]);$(names[j+1])$cond) >= 0"
    end
    # A statement can imply several relations (a Markov chain implies one
    # per link), so this is "from constraint k", not "constraint k".
    row, sign, _ = g.data
    text = checkbounds(Bool, sources, row) && !isempty(sources[row]) ?
           ": " * sources[row] : ""
    return "from constraint $(row - 1)$(sign < 0 ? ", reversed" : "")$text"
end
