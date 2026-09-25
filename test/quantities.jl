# Included from runtests.jl.

@testset "recognising information quantities" begin
    # name the expression of a statement, as the prover sees it
    function named(expr)
        P = Problem(Xitip.parse_statements([expr * " >= 0"])...)
        return Xitip.name_quantity(P.inquiries[1].coefs, P.var_names)
    end

    @test named("H(X)") == "H(X)"
    @test named("H(X,Y)") == "H(X,Y)"
    @test named("H(X,Y) - H(Y)") == "H(X|Y)"
    @test named("H(X,Y,Z) - H(Z)") == "H(X,Y|Z)"
    @test named("H(X) + H(Y) - H(X,Y)") == "I(X;Y)"
    @test named("H(X,Z) + H(Y,Z) - H(Z) - H(X,Y,Z)") == "I(X;Y|Z)"
    @test named("H(X,W) + H(Y,Z,W) - H(W) - H(X,Y,Z,W)") == "I(X;Y,Z|W)"
    # the same quantities written directly
    @test named("H(X|Y)") == "H(X|Y)"
    @test named("I(X;Y|Z)") == "I(X;Y|Z)"
    @test named("I(X,Y;Z|W)") == "I(X,Y;Z|W)"
    # positive multiples keep the factor
    @test named("2 H(X,Z) + 2 H(Y,Z) - 2 H(Z) - 2 H(X,Y,Z)") == "2 I(X;Y|Z)"
    @test named("0.5 H(X) + 0.5 H(Y) - 0.5 H(X,Y)") == "1/2 I(X;Y)"

    # not single quantities
    @test named("H(X) - H(Y)") === nothing          # Y is not a subset of X
    @test named("H(X) + H(Y)") === nothing
    @test named("H(X) + H(Y) - H(X,Y) + 1") === nothing     # constant term
    @test named("H(X) + H(Y) + H(Z) - H(X,Y,Z)") === nothing
    @test named("-H(X)") === nothing                # negative multiple
    @test named("-I(X;Y)") === nothing
    @test named("H(X) + H(Y) + H(Z) - H(X,Y) - H(X,Z) - H(Y,Z) + H(X,Y,Z)") === nothing
    @test named("0") === nothing
    @test named("H(X) + H(Y) - H(X,Y,Z)") === nothing       # not the union
    @test named("H(X) + H(X,Y) - H(Y)") === nothing         # overlapping sets
    @test named("H(X,Y) - 1") === nothing                   # constant term
    @test named("H(X) + H(Y) - H(X,Y) + 2 H(Z)") === nothing  # extra term

    # shown in proofs next to the raw form
    out = sprint(print_proof, explain("H(X,Y,Z) <= H(X,Y) + H(Z)"))
    @test occursin("E = H(Z) + H(X,Y) - H(X,Y,Z)  =  I(X,Y;Z)", out)
    @test occursin("[ H(Y) + H(Z) - H(Y,Z) ]", out)
    @test occursin("+  I(Y;Z)", out)
    # an expression that is not a single quantity shows only the raw form
    out = sprint(print_proof, explain("I(X;Z) <= I(X;Y)", "X/Y/Z"))
    @test occursin("E = -H(Z) + H(Y) + H(X,Z) - H(X,Y)\n", out)
    @test occursin("[ -H(Z) + H(X,Z) + H(Z,Y) - H(X,Z,Y) ]", out)
    @test occursin("+  I(X;Y|Z)", out)

    # naming costs nothing noticeable on a large problem
    @test only(explain("H(X1,X2,X3,X4,X5,X6) <= H(X1)+H(X2)+H(X3)+H(X4)+H(X5)+H(X6)").certificates) isa Proof
end
