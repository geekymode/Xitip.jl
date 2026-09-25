# Included from runtests.jl.

@testset "syntax" begin
    @test prove("I(X:Y) >= 0") == prove("I(X;Y) >= 0")
    @test prove("H(X) >= 0 # comment")
    @test prove("H(X) >= 0\r")                          # CRLF input
    @test prove("I (X;Y) >= 0")                         # blank before '('
    @test prove("H(X) == H(X)")
    @test prove("-H(X) <= 0")
    @test prove("", "# only comments", "H(X) >= 0")     # first statement
    @test prove("H(H1, I1) >= H(H1)")                   # names starting with H/I
    @test_throws XitipError prove("")
    @test_throws XitipError prove(["# nothing"])
    for bad in ["I(X;;Y) >= 0", "H(X) >=", "H(X) > 0", "X/Y", "H(X)>=1e-3",
                "I(X) >= 0", "H(X;Y) >= 0", "2 X >= 0", "H() >= 0", "H(X) >= 0)"]
        @test_throws SyntaxError prove(bad)
    end
    e = try prove("I(X;;Y|Z) <= I(X;Y)") catch e; e end
    @test e.col == 5 && e.len == 1
    @test occursin("in row 1 col 5", e.msg)
    e = try prove("H(X)>=0", "H(Y) >= %") catch e; e end
    @test occursin("in row 2 col 9", e.msg)
end

@testset "count_variables" begin
    @test count_variables("1 >= 0") == 0
    @test count_variables("H(X) >= 0") == 1
    @test count_variables("I(X;Y|Z) <= I(X;Y)") == 3
    @test count_variables("I(X;Y|Z) <= I(X;Y)", "H(W) = 0") == 4
    @test count_variables("", "# comment", "A/B/C/D") == 4
    # more than MAX_VARS is fine for counting
    @test count_variables("H(" * join(("X$i" for i in 1:40), ",") * ") >= 0") == 40
end

@testset "too many variables" begin
    @test_throws XitipError prove("H(" * join(("X$i" for i in 1:31), ",") * ") >= 0")
end
