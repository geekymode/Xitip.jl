#----------------------------------------------------------------------------
# Simplex method (exact arithmetic)
#----------------------------------------------------------------------------

"""
    simplex(A, b, c) -> (status, value)

Solve  min c·x  s.t.  A x = b,  x >= 0  with the two-phase tableau simplex
method in exact arithmetic. `status` is `:optimal`, `:infeasible` or
`:unbounded`.
"""
function simplex(A::Matrix{T}, b::Vector{T}, c::Vector{T}) where {T}
    m, n = size(A)

    # Phase 1: tableau [A I | b] with b >= 0 and artificial basis.
    W = zeros(T, m, n + m + 1)
    for i in 1:m
        s = b[i] < 0 ? -one(T) : one(T)
        for j in 1:n
            W[i, j] = s * A[i, j]
        end
        W[i, n + i] = one(T)
        W[i, end] = s * b[i]
    end
    basis = collect(n+1:n+m)
    cost1 = [zeros(T, n); ones(T, m)]
    _, infeas = run_simplex!(W, basis, cost1, n + m)
    infeas > 0 && return (:infeasible, zero(T))

    # Drive the (zero valued) artificial variables out of the basis. Rows
    # where that is impossible are linearly dependent and can be dropped.
    keep = trues(m)
    for i in 1:m
        basis[i] > n || continue
        j = findfirst(j -> !iszero(W[i, j]), 1:n)
        if j === nothing
            keep[i] = false
        else
            pivot!(W, nothing, basis, i, j)
        end
    end
    W = W[keep, [1:n; n+m+1]]
    basis = basis[keep]

    # Phase 2
    return run_simplex!(W, basis, c, n)
end

# Number of consecutive degenerate pivots before switching to Bland's rule.
const MAX_DEGENERATE = 50

function run_simplex!(W::Matrix{T}, basis, cost, ncols) where {T}
    m = size(W, 1)
    last = size(W, 2)
    # Reduced costs; z[end] is minus the objective value.
    z = zeros(T, last)
    z[1:ncols] .= cost[1:ncols]
    for i in 1:m
        cb = cost[basis[i]]
        iszero(cb) && continue
        for j in 1:last
            z[j] -= cb * W[i, j]
        end
    end
    degenerate = 0
    while true
        # Entering column: the most negative reduced cost (Dantzig's rule)
        # needs far fewer pivots than Bland's rule (lowest index with
        # negative reduced cost), but can cycle at degenerate vertices.
        # After a run of degenerate pivots, use Bland's rule until the
        # objective improves again; this guarantees termination.
        q = 0
        if degenerate >= MAX_DEGENERATE
            q = something(findfirst(j -> z[j] < 0, 1:ncols), 0)
        else
            zmin = zero(T)
            for j in 1:ncols
                if z[j] < zmin
                    q, zmin = j, z[j]
                end
            end
        end
        q == 0 && return (:optimal, -z[end])
        # Leaving row: minimum ratio (ties: lowest basis index, as required
        # by Bland's rule).
        r = 0
        best = zero(T)
        for i in 1:m
            W[i, q] > 0 || continue
            ratio = W[i, end] / W[i, q]
            if r == 0 || ratio < best || (ratio == best && basis[i] < basis[r])
                r, best = i, ratio
            end
        end
        r == 0 && return (:unbounded, zero(T))
        degenerate = iszero(best) ? degenerate + 1 : 0
        pivot!(W, z, basis, r, q)
    end
end

function pivot!(W::Matrix{T}, z, basis, r, q) where {T}
    cols = [j for j in axes(W, 2) if !iszero(W[r, j])]
    piv = W[r, q]
    for j in cols
        W[r, j] /= piv
    end
    for i in axes(W, 1)
        i == r && continue
        f = W[i, q]
        iszero(f) && continue
        for j in cols
            W[i, j] -= f * W[r, j]
        end
    end
    if z !== nothing
        f = z[q]
        if !iszero(f)
            for j in cols
                z[j] -= f * W[r, j]
            end
        end
    end
    basis[r] = q
end
