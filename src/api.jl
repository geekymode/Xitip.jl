#----------------------------------------------------------------------------
# Public API
#----------------------------------------------------------------------------

"""
    ProofStep

One step of a step-by-step proof: `coefficient` times the non-negative
quantity `name` is split off the expression, leaving `remainder`. So

    expression so far  =  coefficient * name  +  remainder

`expansion` is the quantity written with entropies, `label` is how it is
written in the chain of equalities (a short `C1` for a constraint, whose
text is then in `source`), and `remainder_name` is the remainder as a
single information quantity where it is one.

`named` is the quantity itself under a name where it has one — an equality
constraint used in reverse is the negation of one, as in `-I(W;Y|X)` — and
`justification` says why it is non-negative: `">= 0"` for an inequality,
`"= 0"` for an equality constraint.
"""
struct ProofStep
    coefficient::Coef
    name::String            # "I(X;Y|Z)"
    label::String           # "I(X;Y|Z)" or "C1" for a constraint
    source::String          # "constraint 1: X/Y/Z" for a constraint, else ""
    expansion::String       # the quantity written with entropies
    remainder::String       # what is left of the expression after this step
    remainder_name::String  # the remainder as one quantity, if it is one
    latex_remainder::String # the remainder, as LaTeX
    latex_expansion::String # the quantity written with entropies, as LaTeX
    named::String           # the quantity under a name, if it has one
    latex_named::String     # the same, as LaTeX
    justification::String   # why it is non-negative: ">= 0" or "= 0"
end

"""
    Proof

Why an information expression is Shannon-type: it equals a non-negative
combination of elemental inequalities and constraints, plus a non-negative
constant.

`steps` is the same proof as a derivation that subtracts one non-negative
quantity at a time; print it with [`print_proof`](@ref).
"""
struct Proof
    expression::String
    expression_name::String             # the expression as one quantity, if it is one
    terms::Vector{Pair{Coef,String}}    # multiplier => inequality used
    constant::Coef                      # left over non-negative constant
    steps::Vector{ProofStep}
    latex_expression::String            # the expression, as LaTeX
    latex_terms::Vector{String}
end

"""
    TermValue

One quantity of the statement that was refuted, as it stands at the
counterexample: `2 I(X;Y|Z)` with `coefficient` 2, `quantity` `"I(X;Y|Z)"`,
`value` the quantity's own value there, and `side` `:left` or `:right` of
the relation as it was written.

`expansion` is the quantity written with entropies and `substitution` the
same with the counterexample's numbers put in, so that
`I(A;B|C) = H(A,C) + H(B,C) - H(C) - H(A,B,C) = 21 + 21 - 13 - 28 = 1`
can be read off in full.
"""
struct TermValue
    coefficient::Coef
    quantity::String
    value::Coef
    side::Symbol
    expansion::String       # the quantity written with entropies
    substitution::String    # the same, with the counterexample's numbers
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
    latex_expression::String            # the expression, as LaTeX
    statement::String                   # the statement as it was written
    terms::Vector{TermValue}            # its quantities, valued at h
    relation::String                    # "<=", ">=" or "=" as it was written
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

format(c::Coef) = denominator(c) == 1 ? string(numerator(c)) :
                  string(numerator(c), "/", denominator(c))

# e.g. "2 H(X,Y) - H(Y) + 3"
function format(coefs::AbstractDict, names)
    parts = String[]
    # singletons first, then larger subsets, constant term last
    for (S, c) in sort(collect(coefs); by=p -> (p[1] == 0, count_ones(p[1]), p[1]))
        iszero(c) && continue
        sign = isempty(parts) ? (c < 0 ? "-" : "") : (c < 0 ? " - " : " + ")
        mag = abs(c)
        num = (mag == 1 && S != 0) ? "" : format(mag) * (S == 0 ? "" : " ")
        push!(parts, sign * num * (S == 0 ? "" : "H($(setname(S, names)))"))
    end
    isempty(parts) && push!(parts, "0")
    return join(parts)
end

# e.g. "2 H(X,Y) - H(Y) + 3 >= 0"
format(r::LinRel, names) =
    format(r.coefs, names) * (r.equality ? " = 0" : " >= 0")

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
    # what the statement itself reads at those values, which is where the
    # entropies above connect to the statement that was refuted
    if !isempty(c.terms)
        println(io, "  There the statement reads")
        rows = String[]
        for side in (:left, :right)
            terms = [t for t in c.terms if t.side === side]
            isempty(terms) && continue
            total = side_total(c, side)
            sum_text = join((format(t.coefficient * t.value) for t in terms),
                            " + ")
            push!(rows, (side === :left ? "left side" : "right side") * "\0" *
                        join((term_text(t) for t in terms), " + ") * "\0" *
                        (length(terms) == 1 ? format(total) :
                         sum_text * "  =  " * format(total)))
        end
        cols = [maximum(length(split(r, "\0")[k]) for r in rows) for k in 1:2]
        for r in rows
            a, b, c_ = split(r, "\0")
            println(io, "    ", rpad(a, cols[1]), "  ", rpad(b, cols[2]),
                    "  =  ", c_)
        end
        println(io, "  so it asks for ", format(side_total(c, :left)), " ",
                c.relation, " ", format(side_total(c, :right)),
                ", which is false.")
        # and how each quantity gets its value out of the entropies above
        println(io, "  where")
        widths = (maximum(length(t.quantity) for t in c.terms),
                  maximum(length(t.expansion) for t in c.terms),
                  maximum(length(t.substitution) for t in c.terms))
        for t in c.terms
            println(io, "    ", rpad(t.quantity, widths[1]), "  =  ",
                    rpad(t.expansion, widths[2]), "  =  ",
                    rpad(t.substitution, widths[3]), "  =  ", format(t.value))
        end
    end
    # the numbers are entropies in bits, not probabilities, and a direction
    # may be scaled at will, so neither is bounded by 1
    c.direction && println(io, "  Any positive multiple of these values ",
                           "fails in the same way.")
    return
end

# "2 I(C;D)", "I(A;B)", or just "3" for a constant term
term_text(t::TermValue) =
    isempty(t.quantity) ? format(t.coefficient) :
    (t.coefficient == 1 ? "" : format(t.coefficient) * " ") * t.quantity

"""The value of one side of the statement at the counterexample."""
side_total(c::Counterexample, side::Symbol) =
    sum((t.coefficient * t.value for t in c.terms if t.side === side);
        init=zero(Coef))

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

"""
    print_proof([io=stdout], x)

Print a [`Proof`](@ref), [`Counterexample`](@ref) or [`Result`](@ref) as a
step-by-step derivation: each step subtracts one non-negative quantity from
the expression and shows what is left, until nothing (or a non-negative
constant) remains.

# Examples
```julia
julia> print_proof(explain("I(X;Z) <= I(X;Y)", "X/Y/Z"))
Proof of  E >= 0  where  E = H(Y) - H(Z) - H(X,Y) + H(X,Z)

  step 1:  subtract  1 * ( constraint 1 (negated) )
                     = -H(Y) + H(Z) + H(X,Y) - H(X,Z) + H(Y,Z) - H(X,Y,Z)
           leaving   H(Y,Z) - H(X,Y,Z) ... 
```
"""
print_proof(x) = print_proof(stdout, x)

function print_proof(io::IO, p::Proof)
    expr = chop_relation(p.expression)
    head = "Proof of  E >= 0  where  E = " * expr
    println(io, head, isempty(p.expression_name) ? "" : "  =  " * p.expression_name)
    println(io)
    if isempty(p.steps)
        println(io, iszero(p.constant) ?
                    "  E is identically 0, hence E >= 0." :
                    "  E is the constant $(format(p.constant)) >= 0.")
        return
    end
    # E = <first term> + [ what is left ] = ... = <all terms>
    println(io, "  E  =  ", expr)
    parts = String[]
    for s in p.steps
        push!(parts, isone(s.coefficient) ? s.label :
                     format(s.coefficient) * " " * s.label)
        rest = s.remainder == "0" ? "" : "  +  [ " * s.remainder * " ]"
        println(io, "     =  ", join(parts, "  +  "), rest)
    end
    println(io)
    println(io, "  where every term is non-negative:")
    label_width = maximum(length(s.label) for s in p.steps)
    body_width = maximum(length(s.expansion) for s in p.steps)
    # a term that has a name of its own is shown under it, which is how a
    # constraint used in reverse explains itself: C1 = -I(W;Y|X) = 0
    named_width = maximum(length(s.named) == length(s.label) ? 0 :
                          length(s.named) for s in p.steps)
    for s in p.steps
        print(io, "    ", rpad(s.label, label_width), "  =  ",
              rpad(s.expansion, body_width))
        named = isempty(s.named) || s.named == s.label ? "" : s.named
        if named_width > 0
            print(io, isempty(named) ? " "^(named_width + 5) :
                      "  =  " * rpad(named, named_width))
        end
        print(io, "  ", s.justification)
        println(io, isempty(s.source) ? "" : "   (" * s.source * ")")
    end
    println(io)
    if iszero(p.constant)
        println(io, "  so E is a sum of non-negative terms, hence E >= 0.")
    else
        println(io, "  and the constant ", format(p.constant),
                " >= 0, hence E >= 0.")
    end
    return
end

function print_proof(io::IO, c::Counterexample)
    show(io, MIME"text/plain"(), c)
    return
end

function print_proof(io::IO, r::Result)
    if isempty(r.certificates)
        println(io, r.verdict ? "TRUE" : "NOT PROVABLE",
                " (no certificate: decided by the simplex method)")
        return
    end
    for (i, c) in enumerate(r.certificates)
        i == 1 || println(io)
        print_proof(io, c)
    end
    return
end

# "H(X) - H(Y) >= 0" -> "H(X) - H(Y)"
chop_relation(s::AbstractString) =
    replace(replace(s, r" >= 0$" => ""), r" = 0$" => "")

# Multipliers y over the columns [gens; slack] -> Proof. Subtracting the
# terms one by one records the derivation, ending at the leftover constant.
function make_proof(y, gens, r::LinRel, names, sources)
    used = [j for j in eachindex(gens) if !iszero(y[j])]
    # the user's own constraints first, then the largest multipliers
    sort!(used; by=j -> (gens[j].kind != :constraint, -y[j], j))
    terms = Pair{Coef,String}[]
    steps = ProofStep[]
    nconstraints = 0
    remainder = Dict{Int,Coef}(k => v for (k, v) in r.coefs if !iszero(v))
    for j in used
        g, c = gens[j], y[j]
        quantity = Dict{Int,Coef}(g.a)
        iszero(g.b) || (quantity[0] = g.b)
        for (k, v) in quantity
            remainder[k] = get(remainder, k, zero(Coef)) - c * v
            iszero(remainder[k]) && delete!(remainder, k)
        end
        name = describe(g, names, sources)
        push!(terms, c => name)
        isconstraint = g.kind == :constraint
        # only an elemental inequality carries a " >= 0" of our making; a
        # constraint label ends with the user's own text, relation included
        bare = isconstraint ? name : chop_relation(name)
        nconstraints += isconstraint
        push!(steps, ProofStep(c, bare,
                               isconstraint ? "C$nconstraints" : bare,
                               isconstraint ? bare : "",
                               format(quantity, names),
                               format(remainder, names),
                               something(name_quantity(remainder, names), ""),
                               latex(remainder, names),
                               latex(quantity, names),
                               something(signed_name(quantity, names), ""),
                               something(signed_name(quantity, names; tex=true), ""),
                               g.equality ? "= 0" : ">= 0"))
    end
    return Proof(format(r, names),
                 something(name_quantity(r.coefs, names), ""),
                 terms, y[end], steps, latex(r.coefs, names),
                 [latex(gens[j], names, sources) for j in used])
end

# Farkas certificate z = (u, τ) -> Counterexample. The entropies are h = -u,
# normalized by -τ if that is positive so that the constant term applies
# unscaled.
function make_counterexample(z, r::LinRel, names, D, statement, text)
    s = -z[D]
    direction = iszero(s)
    h = direction ? -z[1:D-1] : -z[1:D-1] ./ s
    at(coefs) = sum((S == 0 ? (direction ? zero(Coef) : c) : c * h[S])
                    for (S, c) in coefs; init=zero(Coef))
    return Counterexample(format(r, names), names, h, at(r.coefs), direction,
                          latex(r.coefs, names), text,
                          term_values(statement, names, at),
                          statement isa Relation ?
                          RELATION_TEXT[statement.rel] : "")
end

"""
Each quantity of the statement, valued at the counterexample, so that the
numbers can be read against the statement rather than only against the
expression with everything moved to one side.
"""
function term_values(statement, names, at)
    values = TermValue[]
    statement isa Relation || return values
    index = Dict(v => i for (i, v) in enumerate(names))
    for (side, terms) in ((:left, statement.left), (:right, statement.right))
        for term in terms
            coefs = Dict{Int,Coef}()
            add_term!(coefs, index, Term(one(Coef), term.quantity), 1)
            expansion, substitution = expand_with_numbers(coefs, names, at)
            push!(values, TermValue(term.coef,
                                    quantity_label(term.quantity),
                                    at(coefs), side, expansion, substitution))
        end
    end
    return values
end

"""
A quantity as a sum of entropies, and the same sum with the numbers of the
counterexample put in: `"H(A,C) + H(B,C) - H(C) - H(A,B,C)"` alongside
`"21 + 21 - 13 - 28"`.
"""
function expand_with_numbers(coefs, names, at)
    entries = sort(collect(coefs); by=p -> (p[1] == 0, count_ones(p[1]), p[1]))
    symbols, numbers = String[], String[]
    for (S, c) in entries
        iszero(c) && continue
        sign = isempty(symbols) ? (c < 0 ? "-" : "") : (c < 0 ? " - " : " + ")
        mag = abs(c)
        factor = mag == 1 ? "" : format(mag) * " "
        push!(symbols, sign * factor *
                       (S == 0 ? format(mag) : "H($(setname(S, names)))"))
        value = at(Dict(S => one(Coef)))        # the entropy itself, or 1
        push!(numbers, sign * factor * format(value))
    end
    return join(symbols), join(numbers)
end

"""`H(X,Y|Z)` or `I(X;Y|Z)` as written; a constant term has no quantity."""
function quantity_label(q::Union{Quantity,Nothing})
    q === nothing && return ""
    cond = isempty(q.cond) ? "" : "|" * join(q.cond, ",")
    length(q.parts) == 1 && return "H(" * join(only(q.parts), ",") * cond * ")"
    return "I(" * join((join(p, ",") for p in q.parts), ";") * cond * ")"
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
    stmts, sources = parse_statements(lines)
    P = Problem(stmts, sources)
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
            return Result(false, [make_counterexample(z, rel, P.var_names, D,
                                                     stmts[1], sources[1])])
        end
        cert === nothing ||
            push!(proofs, make_proof(cert, gens, rel, P.var_names, P.sources))
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
