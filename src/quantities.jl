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
function name_quantity(coefs::AbstractDict, names)
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

    name = shape_name(plus, minus, names)
    name === nothing && return nothing
    scale = 1 // factor
    return isone(scale) ? name : format(Coef(scale)) * " " * name
end

cond_of(U, names) = U == 0 ? "" : "|" * setname(U, names)

function shape_name(plus, minus, names)
    if length(plus) == 1 && isempty(minus)                  # H(A)
        return "H($(setname(plus[1], names)))"
    elseif length(plus) == 1 && length(minus) == 1          # H(A\B|B)
        A, B = plus[1], minus[1]
        B & ~A == 0 && B != A || return nothing             # B ⊂ A
        return "H($(setname(A & ~B, names))$(cond_of(B, names)))"
    elseif length(plus) == 2 && length(minus) == 1          # I(A;B)
        A, B = plus
        A & B == 0 && minus[1] == A | B || return nothing
        return "I($(setname(A, names));$(setname(B, names)))"
    elseif length(plus) == 2 && length(minus) == 2          # I(A\D;B\D|D)
        A, B = plus
        D = A & B
        D != 0 && minus == sort([A | B, D]) || return nothing
        return "I($(setname(A & ~D, names));$(setname(B & ~D, names))" *
               "$(cond_of(D, names)))"
    end
    return nothing
end
