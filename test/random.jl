# Included from runtests.jl.

# Random linear combinations of information quantities over n variables.
function random_expr(rng, n; nterms=4)
    vars = ["X$i" for i in 1:n]
    rsub() = (s = filter(_ -> rand(rng, Bool), vars); isempty(s) ? [rand(rng, vars)] : s)
    terms = String[]
    for _ in 1:nterms
        c = rand(rng, -3:3)
        c == 0 && continue
        q = if rand(rng, Bool)
            "H(" * join(rsub(), ",") * (rand(rng, Bool) ? "|" * join(rsub(), ",") : "") * ")"
        else
            "I(" * join(rsub(), ",") * ";" * join(rsub(), ",") *
                (rand(rng, Bool) ? "|" * join(rsub(), ",") : "") * ")"
        end
        push!(terms, (c < 0 ? "- " : "+ ") * string(abs(c)) * " " * q)
    end
    isempty(terms) ? "0" : join(terms, " ")
end

# Joint entropy vector (bitmask of variable subset => entropy) of a random
# distribution of n binary random variables.
function random_entropies(rng, n)
    p = rand(rng, 1 << n) .^ 4          # skewed, some near-deterministic
    p ./= sum(p)
    h = zeros(1 << n)
    for S in 1:(1 << n) - 1
        marg = Dict{Int,Float64}()
        for ω in 0:(1 << n) - 1
            marg[ω & S] = get(marg, ω & S, 0.0) + p[ω+1]
        end
        h[S+1] = -sum(q * log2(q) for q in values(marg) if q > 0)
    end
    return h
end

# Translate a subset bitmask over the problem's variables (in order of
# appearance) to one over X1..Xn (bit k-1 for Xk).
function remap(S, names)
    out = 0
    for (i, name) in enumerate(names)
        S & (1 << (i - 1)) != 0 && (out |= 1 << (parse(Int, name[2:end]) - 1))
    end
    return out
end

function random_constraint(rng, n)
    vars = ["X$i" for i in 1:n]
    pick(k) = join(rand(rng, vars, k), ",")
    kind = rand(rng, 1:6)
    kind == 1 && return join((pick(1) for _ in 1:rand(rng, 3:4)), "/")
    kind == 2 && return join((pick(1) for _ in 1:rand(rng, 2:3)), ".")
    kind == 3 && return pick(1) * ":" * pick(2)
    kind == 4 && return random_expr(rng, n; nterms=2) * " = 0"
    kind == 5 && return random_expr(rng, n; nterms=2) * " >= " * string(rand(rng, -2:2))
    return "H(" * pick(1) * ") <= " * string(rand(rng, 1:3))
end

# Result of prove, or :contradictory
function outcome(lines; kw...)
    try
        prove(lines; kw...)
    catch e
        e isa XitipError || rethrow()
        :contradictory
    end
end

@testset "randomized: least squares vs simplex, soundness" begin
    rng = MersenneTwister(1)
    Xitip.SIMPLEX_FALLBACKS[] = 0
    ncalls = 0
    for trial in 1:300
        n = rand(rng, 2:4)
        lines = [random_expr(rng, n) * " >= " * string(rand(rng, -1:0))]
        for _ in 1:rand(rng, 0:2)
            push!(lines, random_constraint(rng, n))
        end
        @test outcome(lines) == outcome(lines; method=:simplex)
        ncalls += 1
    end
    # Certificates should almost always verify without the simplex method.
    @test Xitip.SIMPLEX_FALLBACKS[] <= ncalls ÷ 20

    ntrue = 0
    for trial in 1:300
        n = rand(rng, 2:4)
        expr = random_expr(rng, n) * " >= 0"
        result = prove(expr)
        @test result == prove(expr; method=:simplex)
        result || continue
        ntrue += 1
        # Anything proven must hold for actual entropy vectors.
        P = Problem(parse_lines([expr]))
        for _ in 1:20
            h = random_entropies(rng, n)
            val = sum(Float64(c) * (S == 0 ? 1.0 : h[remap(S, P.var_names) + 1])
                      for (S, c) in P.inquiries[1].coefs; init=0.0)
            @test val >= -1e-9
        end
    end
    @test ntrue > 20            # the test must actually exercise TRUE cases
end

