# Included from runtests.jl.

@testset "step-by-step proofs" begin
    # Recompute the proof independently: the multipliers times the
    # inequalities they name, plus the constant, must equal the expression.
    function check_proof(lines, p::Proof)
        P = Problem(Xitip.parse_statements(lines)...)
        names = P.var_names
        gens = generators(P)
        by_name = Dict(Xitip.describe(g, names, P.sources) => g for g in gens)
        total = Dict{Int,Coef}()
        add!(k, v) = (total[k] = get(total, k, zero(Coef)) + v)
        for (c, name) in p.terms
            @test c > 0
            g = by_name[name]                      # the name must identify it
            for (k, v) in g.a
                add!(k, c * v)
            end
            iszero(g.b) || add!(0, c * g.b)
        end
        @test p.constant >= 0
        add!(0, p.constant)
        filter!(kv -> !iszero(kv.second), total)
        target = filter(kv -> !iszero(kv.second), P.inquiries[1].coefs)
        @test total == target
        # the steps mirror the terms and end with nothing left over
        @test length(p.steps) == length(p.terms)
        @test [s.coefficient for s in p.steps] == first.(p.terms)
        # a constraint keeps its own text (relation included), an elemental
        # inequality drops the " >= 0" we added to it
        @test [s.name for s in p.steps] ==
              [startswith(t, "from constraint") ? t : Xitip.chop_relation(t)
               for t in last.(p.terms)]
        @test last(p.steps).remainder == Xitip.format(p.constant)
        return true
    end

    cases = [["H(X,Y) <= H(X) + H(Y)"],
             ["2 H(X,Y,Z) <= H(X,Y) + H(Y,Z) + H(X,Z)"],
             ["H(X,Y,Z) <= H(X,Y) + H(Z)"],
             ["I(X;Z) <= I(X;Y)", "X/Y/Z"],
             ["I(X;Y|Z) <= I(X;Y)", "H(Z) = 0"],
             ["0.5 H(X) + 0.5 H(Y) >= 0.5 H(X,Y)"],
             ["2 H(X) >= 1", "H(X) >= 1"],
             ["H(X|Y) <= H(X)"]]
    for lines in cases
        r = explain(lines)
        @test r.verdict
        for p in r.certificates
            check_proof(lines, p)
        end
    end

    # constraints are named by their own text
    out = sprint(print_proof, explain("I(X;Z) <= I(X;Y)", "X/Y/Z"))
    @test occursin("C1", out)
    @test occursin("(from constraint 1, reversed: X/Y/Z)", out)
    out = sprint(print_proof, explain("H(X) >= 1", "H(X) >= 2"))
    @test occursin("(from constraint 1: H(X) >= 2)", out)
    @test occursin("1/2 C1", out)
    # a constraint keeps its own relation in the shown text
    out = sprint(print_proof, explain("I(B;C) <= H(A)", "I(B;C|A) = 0"))
    @test occursin("(from constraint 1, reversed: I(B;C|A) = 0)", out)
    out = sprint(print_proof, explain("I(X;Y|Z) <= I(X;Y)", "H(Z) = 0"))
    @test occursin("H(Z) = 0)", out) && !occursin("H(Z))", out)

    # comments are stripped from the shown text
    out = sprint(print_proof, explain("H(X) >= 1", "H(X) >= 2  # why not"))
    @test occursin("(from constraint 1: H(X) >= 2)", out)
    @test !occursin("why not", out)

    # printed form: a chain of equalities that peels off one term at a time
    out = sprint(print_proof, explain("2 H(X,Y,Z) <= H(X,Y) + H(Y,Z) + H(X,Z)"))
    @test occursin("E  =  H(X,Y) + H(X,Z) + H(Y,Z) - 2 H(X,Y,Z)", out)
    @test occursin("=  I(X;Y|Z)  +  [ H(Z) + H(X,Y) - H(X,Y,Z) ]", out)
    @test occursin("=  I(X;Y|Z)  +  I(X;Z|Y)  +  I(Y;Z)", out)
    @test occursin("where every term is non-negative:", out)
    @test occursin("I(Y;Z)    =  H(Y) + H(Z) - H(Y,Z)", out)
    @test occursin("so E is a sum of non-negative terms, hence E >= 0.", out)
    @test count("=  ", out) >= 4          # one chain line per step, plus E

    # fractions print readably, and a left over constant is reported
    out = sprint(print_proof, explain("0.5 H(X) + 0.5 H(Y) >= 0.5 H(X,Y)"))
    @test occursin("=  1/2 I(X;Y)", out)
    @test !occursin("//", out)
    out = sprint(print_proof, explain("2 H(X) + 1 >= 0"))
    @test occursin("[ 1 ]", out)
    @test occursin("and the constant 1 >= 0, hence E >= 0.", out)
    # a statement that is identically zero needs no terms at all
    out = sprint(print_proof, explain("H(X,Y) = H(X) + H(Y|X)"))
    @test count("E is identically 0", out) == 2

    # an equality gives one derivation per direction
    out = sprint(print_proof, explain("H(X,Y) = H(X) + H(Y|X)"))
    @test count("Proof of", out) == 2

    # counterexamples and the certificate-free simplex path
    out = sprint(print_proof, explain("H(X) <= H(Y)"))
    @test occursin("No proof of", out)
    out = sprint(print_proof, explain("H(X) >= 0"; method=:simplex))
    @test occursin("no certificate", out)

    # command line
    code, out, _ = run_cli("--steps", "H(X,Y) <= H(X) + H(Y)")
    @test code == 0 && occursin("=  I(X;Y)", out)
    code, out, _ = run_cli("-s", "H(X) <= H(Y)")
    @test code == 1 && occursin("No proof of", out)
    code, out, _ = run_cli("-s", "-q", "H(X,Y) <= H(X) + H(Y)")
    @test code == 0 && isempty(out)
end
