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
latex(x::Union{Proof,Counterexample,Result}; kw...) = latex(stdout, x; kw...)

# Join aligned lines of an align* block (all but the last end with \\).
print_align(io, lines) = println(io, join(lines, " \\\\\n"))

# Split a list of rendered terms into lines of at most `per` terms.
function chunk(terms, per)
    isempty(terms) && return ["0"]
    return [join(terms[i:min(i + per - 1, end)], " ")
            for i in 1:per:length(terms)]
end

# Greedily fill lines of at most `width` characters with `pieces`. The
# first line can be shorter, to leave room for a label in front of it.
function chunk_width(pieces, width, first_width=width)
    lines = String[]
    for piece in pieces
        budget = length(lines) == 1 ? first_width : width
        if isempty(lines) || length(lines[end]) + length(piece) + 1 > budget
            push!(lines, piece)
        else
            lines[end] *= " " * piece
        end
    end
    return isempty(lines) ? ["0"] : lines
end

"""
    latex([io], p::Proof; steps=false, expand=false, width=68)

The proof as LaTeX. By default the expression is rewritten as a sum of
non-negative quantities; `steps=true` gives the full chain of equalities,
splitting one term off at a time with the remainder in brackets.
`expand=true` lists the entropy form of every term (constraints are always
listed, as `C_1`, `C_2`, ...).
"""
function latex(io::IO, p::Proof; steps::Bool=false, expand::Bool=false,
               width::Int=68)
    width = max(30, width - length(" \\;\\ge\\; 0"))   # room for the tail
    # the terms, and the label each one is written with
    terms, labels = String[], String[]
    nconstraints = 0
    for (k, step) in enumerate(p.steps)
        isconstraint = !isempty(step.source)
        isconstraint && (nconstraints += 1)
        label = isconstraint ? "C_{$nconstraints}" : p.latex_terms[k]
        push!(labels, label)
        sign, body = latex_coefficient(step.coefficient; first=isempty(terms))
        factor = isempty(body) ? "" : body * " "
        push!(terms, (isempty(sign) ? "" : sign * " ") * factor * label)
    end
    if !iszero(p.constant)
        sign, body = latex_coefficient(p.constant; first=isempty(terms))
        push!(terms, (isempty(sign) ? "" : sign * " ") *
                     (isempty(body) ? "1" : body))
    end

    lines = String[]
    emit!(prefix, pieces) =
        for (i, part) in enumerate(chunk_width(pieces, width))
            push!(lines, (i == 1 ? prefix : "    &\\quad ") * part)
        end
    emit!("  E &= ", split_terms(p.latex_expression))
    if steps
        for (k, step) in enumerate(p.steps)
            pieces = copy(terms[1:k])
            step.remainder == "0" ||
                append!(pieces, ["+ ["; split_terms(step.latex_remainder); "]"])
            emit!("    &= ", pieces)
        end
        iszero(p.constant) || emit!("    &= ", terms)
    else
        emit!("    &= ", isempty(terms) ? ["0"] : terms)
    end
    lines[end] *= " \\;\\ge\\; 0"
    println(io, "\\begin{align*}")
    print_align(io, lines)
    println(io, "\\end{align*}")

    # definitions: constraints always, the rest on request
    shown = [(l, s) for (l, s) in zip(labels, p.steps)
             if expand || !isempty(s.source)]
    isempty(shown) && return
    println(io, "where")
    println(io, "\\begin{align*}")
    defs = String[]
    for (label, step) in shown
        note = isempty(step.source) ? "" :
               " \\quad \\text{($(constraint_note(step.source)))}"
        # the label sits in front of the first line, the note after the last
        body = chunk_width(split_terms(step.latex_expansion), width,
                           max(20, width - length(label)))
        push!(defs, "  $label &= " * body[1])
        for extra in body[2:end]
            push!(defs, "    &\\quad " * extra)
        end
        defs[end] *= " \\;\\ge\\; 0"
        if !isempty(note)
            # keep the note on the same line only if there is room for it
            length(defs[end]) + length(note) <= width + length(label) + 8 ?
                (defs[end] *= note) :
                push!(defs, "    &\\quad " * strip(replace(note, "\\quad" => "", count=1)))
        end
    end
    print_align(io, defs)
    println(io, "\\end{align*}")
    return
end

# "constraint 1 reversed: X/Y/Z" -> "constraint 1 reversed". The statement
# itself is not repeated: LaTeX text mode would mangle its <, > and |, and
# its entropy form is on the same line anyway.
constraint_note(source::AbstractString) = String(first(split(source, ":")))

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

function latex(io::IO, c::Counterexample; per_line::Int=3, kw...)
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

function latex(io::IO, r::Result; kw...)
    if isempty(r.certificates)
        println(io, "% no certificate: decided by the simplex method")
        return
    end
    for (i, c) in enumerate(r.certificates)
        i == 1 || println(io)
        latex(io, c; kw...)
    end
    return
end

latex_number(c::Coef) = denominator(c) == 1 ? string(numerator(c)) :
                        "\\tfrac{$(numerator(c))}{$(denominator(c))}"

"""LaTeX source of `x` as a string; see [`latex`](@ref)."""
latex_string(x; kw...) = sprint(io -> latex(io, x; kw...))
