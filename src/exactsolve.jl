#----------------------------------------------------------------------------
# Exact linear algebra
#----------------------------------------------------------------------------

"""
    exact_solve(M, rhs) -> y or nothing

Solve  M y = rhs  exactly by Gauss-Jordan elimination (M may be non-square
or singular; free variables are set to zero). `nothing` if inconsistent.
"""
function exact_solve(M::Matrix{Coef}, rhs::Vector{Coef})
    R, C = size(M)
    M = [M rhs]
    pivots = Int[]
    row = 1
    for col in 1:C
        row > R && break
        p = findfirst(i -> !iszero(M[i, col]), row:R)
        p === nothing && continue
        p += row - 1
        if p != row
            M[row, :], M[p, :] = M[p, :], M[row, :]
        end
        M[row, :] ./= M[row, col]
        for i in 1:R
            i == row && continue
            f = M[i, col]
            iszero(f) && continue
            @views M[i, :] .-= f .* M[row, :]
        end
        push!(pivots, col)
        row += 1
    end
    all(i -> iszero(M[i, end]), row:R) || return nothing
    y = zeros(Coef, C)
    for (i, col) in enumerate(pivots)
        y[col] = M[i, end]
    end
    return y
end
