#----------------------------------------------------------------------------
# Non-negative least squares
#----------------------------------------------------------------------------

"""
    nnls(A, b) -> (x, passive) or nothing

Lawson-Hanson active set method for  min ||A x - b||  s.t.  x >= 0.
Returns `nothing` if it does not converge (rounding errors).
"""
function nnls(A::Matrix{Float64}, b::Vector{Float64})
    N = size(A, 2)
    tol = 1e-10 * max(1.0, norm(b))
    x = zeros(N)
    passive = falses(N)
    w = A' * b
    iters = 0
    while true
        # Add the variable with the largest gradient component, if any.
        t, wmax = 0, tol
        for j in 1:N
            if !passive[j] && w[j] > wmax
                t, wmax = j, w[j]
            end
        end
        t == 0 && return x, passive
        passive[t] = true
        while true
            (iters += 1) > 3N && return nothing
            idx = findall(passive)
            s = A[:, idx] \ b
            if all(>(0), s)
                x .= 0
                x[idx] .= s
                break
            end
            # Move towards s until a variable hits zero, drop it and retry.
            α = minimum(x[j] / (x[j] - s[k]) for (k, j) in enumerate(idx) if s[k] <= 0)
            for (k, j) in enumerate(idx)
                x[j] += α * (s[k] - x[j])
                if x[j] <= 1e-12
                    x[j] = 0
                    passive[j] = false
                end
            end
        end
        w = A' * (b - A * x)
    end
end
