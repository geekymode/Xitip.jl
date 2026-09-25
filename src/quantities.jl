#----------------------------------------------------------------------------
# Recognising information quantities
#----------------------------------------------------------------------------
#
# An expression such as  -H(Z) + H(X,Z) + H(Y,Z) - H(X,Y,Z)  is easier to
# read as  I(X;Y|Z). Both the statement being proven and the remainder of
# each proof step are matched against the shapes
#
#       H(A)                          one term
#       H(A) - H(B)        = H(A\\B|B)         for B ⊂ A
#       H(A) + H(B) - H(A∪B)          = I(A;B)           for disjoint A, B
#       H(A) + H(B) - H(A∪B) - H(A∩B) = I(A\\D;B\\D|D)     for D = A∩B
#
# which needs no search: the sets are read off the terms themselves.

"""
    name_quantity(coefs, names) -> String or nothing

Recognise `coefs` as a positive multiple of a single information quantity,
e.g. `"2 I(X;Y|Z)"`. `nothing` if it is not one (or has a constant term).
"""
function name_quantity(coefs::AbstractDict, names; tex::Bool=false)
    terms = [k => v for (k, v) in coefs if !iszero(v)]
    (isempty(terms) || length(terms) > 4) && return nothing
    any(kv -> kv.first == 0, terms) && return nothing

    # scale to coprime integers, keeping the orientation
    factor = lcm(denominator.(last.(terms)))
    ints = [numerator(v * factor) for (_, v) in terms]
    factor //= gcd(ints)
    scaled = [k => Int(v * factor) for (k, v) in terms]

    plus = sort!([k for (k, v) in scaled if v == 1])
    minus = sort!([k for (k, v) in scaled if v == -1])
    length(plus) + length(minus) == length(scaled) || return nothing

    name = shape_name(plus, minus, names; tex)
    name === nothing && return nothing
    scale = 1 // factor
    isone(scale) && return name
    return (tex ? first(latex_coefficient(Coef(scale); first=true)) *
                  last(latex_coefficient(Coef(scale); first=true)) :
                  format(Coef(scale))) * " " * name
end

"""
    signed_name(coefs, names) -> String or nothing

Like [`name_quantity`](@ref), but also recognising the negation of a
quantity, which is what an equality constraint used in reverse is:
`"-I(W;Y|X)"`.
"""
function signed_name(coefs::AbstractDict, names; tex::Bool=false)
    name = name_quantity(coefs, names; tex)
    name === nothing || return name
    negated = name_quantity(Dict(k => -v for (k, v) in coefs), names; tex)
    return negated === nothing ? nothing : "-" * negated
end

function shape_name(plus, minus, names; tex::Bool=false)
    set(mask) = tex ? latex_names(mask, names) : setname(mask, names)
    cond(U) = U == 0 ? "" : (tex ? " \\mid " : "|") * set(U)
    sep = tex ? " ; " : ";"
    if length(plus) == 1 && isempty(minus)                  # H(A)
        return "H($(set(plus[1])))"
    elseif length(plus) == 1 && length(minus) == 1          # H(A\B|B)
        A, B = plus[1], minus[1]
        B & ~A == 0 && B != A || return nothing             # B ⊂ A
        return "H($(set(A & ~B))$(cond(B)))"
    elseif length(plus) == 2 && length(minus) == 1          # I(A;B)
        A, B = plus
        A & B == 0 && minus[1] == A | B || return nothing
        return "I($(set(A))$sep$(set(B)))"
    elseif length(plus) == 2 && length(minus) == 2          # I(A\D;B\D|D)
        A, B = plus
        D = A & B
        D != 0 && minus == sort([A | B, D]) || return nothing
        return "I($(set(A & ~D))$sep$(set(B & ~D))$(cond(D)))"
    end
    return nothing
end
