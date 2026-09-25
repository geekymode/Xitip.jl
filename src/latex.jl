#----------------------------------------------------------------------------
# LaTeX output
#----------------------------------------------------------------------------

# "X,Y" -> "H(X,Y)" with names escaped for maths mode
latex_entropy(mask::Int, names) = "H(" * latex_names(mask, names) * ")"

latex_names(mask::Int, names) =
    join((latex_name(names[i]) for i in 1:length(names)
          if mask & (1 << (i - 1)) != 0), ",")

# "X_1" and "Xabc" render as \mathit{}, a bare letter as itself
function latex_name(v::AbstractString)
    length(v) == 1 && return v
    m = match(r"^([A-Za-z])([0-9]+)$", v)
    m === nothing && return "\\mathit{$(replace(v, "_" => "\\_"))}"
    return length(m[2]) == 1 ? "$(m[1])_$(m[2])" : "$(m[1])_{$(m[2])}"
end

function latex_coefficient(c::Coef; first::Bool=false)
    sign = c < 0 ? "-" : (first ? "" : "+")
    mag = abs(c)
    body = denominator(mag) == 1 ?
           (mag == 1 ? "" : string(numerator(mag))) :
           "\\tfrac{$(numerator(mag))}{$(denominator(mag))}"
    return sign, body
end

# "H(X) + H(Y) - 2 H(X,Y) + 3" in maths mode
function latex(coefs::AbstractDict, names)
    parts = String[]
    for (S, c) in sort(collect(coefs); by=p -> (p[1] == 0, count_ones(p[1]), p[1]))
        iszero(c) && continue
        sign, body = latex_coefficient(c; first=isempty(parts))
        term = S == 0 ? (isempty(body) ? "1" : body) :
               (isempty(body) ? "" : body * " ") * latex_entropy(S, names)
        push!(parts, isempty(sign) ? term : sign * " " * term)
    end
    isempty(parts) && push!(parts, "0")
    return join(parts, " ")
end

# An elemental inequality or constraint as a maths-mode quantity.
function latex(g::Generator, names, sources)
    if g.kind == :entropy
        i = g.data[1]
        rest = ((1 << length(names)) - 1) ⊻ (1 << i)
        cond = rest == 0 ? "" : " \\mid " * latex_names(rest, names)
        return "H($(latex_name(names[i+1]))$cond)"
    elseif g.kind == :mutinf
        i, j, K = g.data
        cond = K == 0 ? "" : " \\mid " * latex_names(K, names)
        return "I($(latex_name(names[i+1])) ; $(latex_name(names[j+1]))$cond)"
    end
    coefs = Dict{Int,Coef}(g.a)
    iszero(g.b) || (coefs[0] = g.b)
    body = latex(coefs, names)
    # a constraint is a whole expression: keep it together under its factor
    return count(!iszero, values(coefs)) > 1 ? "\\left( $body \\right)" : body
end

"""
    latex([io=stdout], x)

Write a [`Proof`](@ref), [`Counterexample`](@ref) or [`Result`](@ref) as
LaTeX, ready to paste into a paper. Proofs become an `align*` block that
rewrites the expression as a sum of non-negative quantities; a
counterexample becomes the table of entropy values that defeats it.

# Examples
```julia
julia> latex(explain("H(X,Y,Z) <= H(X,Y) + H(Z)"))
\\begin{align*}
  H(Z) + H(X,Y) - H(X,Y,Z)
    &= I(X ; Z \\mid Y) + I(Y ; Z) \\\\
    &\\ge 0 .
\\end{align*}
```
"""
latex(x::Union{Proof,Counterexample,Result}) = latex(stdout, x)

# Join aligned lines of an align* block (all but the last end with \\).
print_align(io, lines) = println(io, join(lines, " \\\\\n"))

# Split a list of rendered terms into lines of at most `per` terms.
function chunk(terms, per)
    isempty(terms) && return ["0"]
    return [join(terms[i:min(i + per - 1, end)], " ")
            for i in 1:per:length(terms)]
end

function latex(io::IO, p::Proof; per_line::Int=4)
    terms = String[]
    for (c, tex) in zip(first.(p.terms), p.latex_terms)
        sign, body = latex_coefficient(c; first=isempty(terms))
        factor = isempty(body) ? "" : body * " "
        push!(terms, (isempty(sign) ? "" : sign * " ") * factor * tex)
    end
    if !iszero(p.constant)
        sign, body = latex_coefficient(p.constant; first=isempty(terms))
        push!(terms, (isempty(sign) ? "" : sign * " ") *
                     (isempty(body) ? "1" : body))
    end
    lines = String[]
    for (i, part) in enumerate(chunk(split_terms(p.latex_expression), per_line))
        push!(lines, (i == 1 ? "  &" : "    &\\quad ") * part)
    end
    for (i, part) in enumerate(chunk(terms, per_line))
        push!(lines, (i == 1 ? "    &= " : "    &\\quad ") * part)
    end
    push!(lines, "    &\\ge 0 .")
    println(io, "\\begin{align*}")
    print_align(io, lines)
    println(io, "\\end{align*}")
    return
end

# Break a rendered expression back into its terms, for line wrapping.
function split_terms(expr::AbstractString)
    terms = String[]
    for tok in split(expr, " ")
        if (tok == "+" || tok == "-") && !isempty(terms)
            push!(terms, String(tok))
        elseif isempty(terms) || terms[end] in ("+", "-")
            isempty(terms) ? push!(terms, String(tok)) :
                             (terms[end] *= " " * tok)
        else
            terms[end] *= " " * tok
        end
    end
    return terms
end

function latex(io::IO, c::Counterexample; per_line::Int=3)
    tail = " \\;=\\; " * latex_number(c.value) * " \\;<\\; 0"
    parts = chunk(split_terms(c.latex_expression), per_line + 1)
    parts[end] *= tail
    println(io, "\\begin{align*}")
    print_align(io, [(i == 1 ? "  &" : "    &\\quad ") * part
                     for (i, part) in enumerate(parts)])
    println(io, "\\end{align*}")
    println(io, "for the ", c.direction ? "direction" : "entropies")
    println(io, "\\begin{align*}")
    n = length(c.var_names)
    entries = ["$(latex_entropy(S, c.var_names)) &= $(latex_number(c.entropies[S]))"
               for S in 1:(1 << n) - 1]
    print_align(io, ["  " * join(entries[i:min(i + per_line - 1, end)], ", & ")
                     for i in 1:per_line:length(entries)])
    println(io, "\\end{align*}")
    return
end

function latex(io::IO, r::Result)
    if isempty(r.certificates)
        println(io, "% no certificate: decided by the simplex method")
        return
    end
    for (i, c) in enumerate(r.certificates)
        i == 1 || println(io)
        latex(io, c)
    end
    return
end

latex_number(c::Coef) = denominator(c) == 1 ? string(numerator(c)) :
                        "\\tfrac{$(numerator(c))}{$(denominator(c))}"

"""LaTeX source of `x` as a string."""
latex_string(x) = sprint(latex, x)
