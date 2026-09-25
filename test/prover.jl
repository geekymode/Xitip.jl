# Included from runtests.jl.

@testset "basic Shannon inequalities" begin
    @test prove("H(X) >= 0")
    @test prove("I(X;Y) >= 0")
    @test prove("I(X;Y|Z) >= 0")
    @test prove("H(X,Y) <= H(X) + H(Y)")
    @test prove("H(X|Y) <= H(X)")
    @test prove("H(X,Y) = H(X) + H(Y|X)")                   # chain rule
    @test prove("I(X;Y) = H(X) + H(Y) - H(X,Y)")
    @test prove("I(X;Y,Z) = I(X;Y) + I(X;Z|Y)")              # chain rule for I
    @test prove("H(X,Y,Z) <= H(X,Y) + H(Y,Z) - H(Y)") == prove("I(X;Z|Y) >= 0")
    @test prove("2 H(X,Y,Z) <= H(X,Y) + H(Y,Z) + H(X,Z)")    # Han's inequality
end

@testset "not provable" begin
    @test !prove("H(X) >= 1")
    @test !prove("H(X) <= H(Y)")
    @test !prove("I(X;Y|Z) <= I(X;Y)")
    @test !prove("I(X;Y|Z) >= I(X;Y)")
    @test !prove("I(X;Y;Z) >= 0")                   # can be negative
    @test !prove("H(X,Y) = H(X) + H(Y)")
    # Zhang-Yeung and Ingleton: valid resp. invalid, but not Shannon-type
    @test !prove("2I(C;D) <= I(A;B) + I(A;C,D) + 3I(C;D|A) + I(C;D|B)")
    @test !prove("I(A;B) <= I(A;B|C) + I(A;B|D) + I(C;D)")
end

@testset "constraints" begin
    @test prove("I(X;Y|Z) <= I(X;Y)", "H(Z) = 0")
    @test prove("I(X;Z) <= I(X;Y)", "X/Y/Z")                # data processing
    @test prove("I(A;D) <= I(B;C)", "A/B/C/D")
    @test prove("I(X;Y) = 0", "X.Y")
    @test prove("X.Y.Z", "I(X;Y,Z) = 0", "I(Y;Z) = 0")
    @test prove("H(X,Y) = H(Y)", "X:Y")
    @test prove("X:Y,Z", "H(X|Y,Z) = 0")
    @test prove("H(X) >= 1", "H(X) >= 2")
    @test prove("H(X) >= 1", "H(X) = 2")
    @test !prove("H(X) >= 3", "H(X) = 2")
    @test prove("H(X) <= 2.5", "H(X,Y) <= 2.5")
    @test prove("X/Y/Z", "X/Y/Z")                   # inquiry equals constraint
    @test prove("X/Y/Z", "I(X;Z|Y) = 0")            # statements as inquiries
    @test prove("A/B/C/D", "I(A;C|B) = 0", "I(A,B;D|C) = 0")
    @test !prove("A/B/C/D", "I(A;C|B) = 0")
    @test !prove("X/Y/Z")
    @test !prove("X.Y")
    @test !prove("X:Y")
    # constraints must not be stronger than they should be
    @test !prove("H(Y) = 0", "X/Y/Z")
    @test !prove("I(X;Y) = 0", "X/Y/Z")
    @test !prove("H(X) = 0", "X.Y")
    @test !prove("H(X) = 0", "X:Y")
    @test !prove("H(Y|X) = 0", "X:Y")
    @test_throws XitipError prove("H(X) >= 0", "H(X) = 1", "H(X) = 2")
    @test_throws XitipError prove("H(X) >= 0", "0 >= 1")
end

@testset "exact arithmetic" begin
    # 0.1 + 0.2 != 0.3 in floating point
    @test prove("0.1 H(X) + 0.2 H(X) >= 0.3 H(X)")
    @test prove("0.1 H(X) + 0.2 H(X) = 0.3 H(X)")
    @test prove("H(X) >= 1.00000001", "H(X) = 1.00000001")
    @test !prove("H(X) >= 1.00000001", "H(X) = 1")
    @test prove(".5 H(X) <= H(X)")
end

@testset "degenerate inputs" begin
    @test prove("1 >= 0")
    @test !prove("0 >= 1")
    @test prove("2 = 2")
    @test prove("H(X) - H(X) = 0")
    @test prove("H(X|X) = 0")
    @test prove("I(X;X) = H(X)")
end

@testset "larger problems" begin
    for n in 5:8
        v = ["X$i" for i in 1:n]
        @test prove("H(" * join(v, ",") * ") <= " * join(("H($x)" for x in v), " + "))
        @test !prove("I(X1;X2) <= I(X1;X2|" * join(v[3:end], ",") * ")")
    end
    # the simplex method agrees where it is fast enough
    for n in 5:6
        v = ["X$i" for i in 1:n]
        e = "I(X1;X2) <= I(X1;X2|X3) + I(X1;X2|X4) + I(X3;X4) + H(" * join(v[5:end], ",") * ")"
        @test prove(e) == prove(e; method=:simplex)
    end
end
