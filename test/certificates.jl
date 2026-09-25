# Included from runtests.jl.

@testset "certificate checks reject wrong certificates" begin
    # The least squares step is normally right, so the exact checks must be
    # tested directly: no certificate for the wrong answer may pass.
    X = Xitip
    rng = MersenneTwister(2)
    function setup(lines)
        P = Problem(parse_lines(lines))
        n = length(P.var_names)
        gens = X.generators(P)
        D, cols, t = X.homogenize(gens, n, P.inquiries[1].coefs)
        lines_ = [j for (j, g) in enumerate(gens) if g.line]
        return n, D, cols, t, lines_
    end
    # TRUE statements: no counterexample may be accepted.
    for lines in (["H(X,Y) <= H(X) + H(Y)"], ["I(X;Z) <= I(X;Y)", "X/Y/Z"],
                  ["H(X) >= 1", "H(X) >= 2"])
        n, D, cols, t, lines_ = setup(lines)
        for _ in 1:200
            r = randn(rng, D)
            @test X.certify_false(cols, lines_, t, r, n, D) === nothing
            passive = rand(rng, Bool, length(cols))
            any(passive) && @test X.certify_false_exact(cols, t, passive, D) === nothing
        end
    end
    # FALSE statements: no proof may be accepted.
    for lines in (["I(X;Y|Z) <= I(X;Y)"], ["H(X) >= 3", "H(X) = 2"],
                  ["I(X;Y) <= 0", "X/Y/Z"])
        n, D, cols, t, lines_ = setup(lines)
        for _ in 1:200
            passive = rand(rng, Bool, length(cols))
            any(passive) && @test X.certify_true(cols, t, passive) === nothing
        end
        @test X.certify_true(cols, t, trues(length(cols))) === nothing
    end
end

@testset "explain: proofs" begin
    r = explain("H(X,Y) <= H(X) + H(Y)")
    @test r.verdict
    @test length(r.certificates) == 1
    p = only(r.certificates)
    @test p isa Proof
    @test p.terms == [Coef(1) => "I(X;Y) >= 0"]
    @test p.constant == 0
    @test occursin("H(X) + H(Y) - H(X,Y) >= 0", p.expression)
    @test occursin("I(X;Y) >= 0", sprint(show, p))

    # every multiplier is non-negative, and an equality gives two proofs
    for lines in (["H(X,Y) = H(X) + H(Y|X)"], ["I(X;Z) <= I(X;Y)", "X/Y/Z"],
                  ["2 H(X) >= 1", "H(X) >= 1"], ["H(X,Y,Z) <= H(X,Y) + H(Z)"])
        r = explain(lines)
        @test r.verdict
        @test !isempty(r.certificates)
        for p in r.certificates
            @test p isa Proof
            @test all(t -> t.first > 0, p.terms)
            @test p.constant >= 0
        end
    end
    @test length(explain("H(X,Y) = H(X) + H(Y|X)").certificates) == 2

    # the simplex method decides without a certificate
    r = explain("H(X,Y) <= H(X) + H(Y)"; method=:simplex)
    @test r.verdict && isempty(r.certificates)
    @test occursin("no certificate", sprint(show, r))
end

@testset "explain: counterexamples" begin
    # Check the reported entropies really are a counterexample: they satisfy
    # every elemental inequality and constraint, but not the expression.
    function check(lines)
        r = explain(lines)
        @test !r.verdict
        c = only(r.certificates)
        @test c isa Counterexample
        P = Problem(parse_lines(lines))
        n = length(P.var_names)
        h = c.entropies
        @test length(h) == (1 << n) - 1
        @test all(>=(0), h)
        value(coefs) = sum((S == 0 ? (c.direction ? zero(Coef) : x) : x * h[S])
                           for (S, x) in coefs; init=zero(Coef))
        for g in elemental_inequalities(n)
            @test sum(x * h[S] for (S, x) in g.a; init=zero(Coef)) >= 0
        end
        for con in P.constraints
            v = value(con.coefs)
            @test con.equality ? v == 0 : v >= 0
        end
        @test value(P.inquiries[1].coefs) < 0
        @test c.value == value(P.inquiries[1].coefs)
        @test occursin("H(", sprint(show, c))
        # a direction may be scaled at will, and the output says so
        text = sprint(show, c)
        @test occursin("Any positive multiple", text) == c.direction
        return c
    end
    check(["H(X) <= H(Y)"])
    check(["I(X;Y|Z) <= I(X;Y)"])
    check(["I(X;Y;Z) >= 0"])
    check(["I(A;B) <= I(A;B|C) + I(A;B|D) + I(C;D)"])        # Ingleton
    check(["2I(C;D) <= I(A;B) + I(A;C,D) + 3I(C;D|A) + I(C;D|B)"])  # Zhang-Yeung
    check(["H(X) >= 3", "H(X) = 2"])
    check(["I(X;Y) >= 1", "H(X) <= 5"])
    check(["H(X) <= H(Y)", "X/Y/Z"])

    # counterexamples should be small enough to read
    c = check(["H(X) <= H(Y)"])
    @test maximum(c.entropies) < 100
end
