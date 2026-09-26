# Included from runtests.jl.

@testset "sufficient conditions" begin
    c = sufficient_conditions("I(X;Y|Z) <= I(X;Y)")
    @test [only(f.constraints) for f in c.found] ==
          ["I(X;Y|Z) = 0", "I(X;Z|Y) = 0", "I(Y;Z|X) = 0"]
    # whatever is reported must actually work, checked by proving it again
    for f in c.found
        @test prove(vcat("I(X;Y|Z) <= I(X;Y)", f.constraints))
    end
    # the two Markov readings are spelled out
    @test any(occursin("Markov chain X/Y/Z", m)
              for f in c.found for m in f.meanings)
    @test any(occursin("Markov chain Y/X/Z", m)
              for f in c.found for m in f.meanings)

    # the counterexample prune must not lose an answer: compare with brute
    # force over every candidate, for statements small enough to do so
    names = ["X", "Y", "Z"]
    every = [Xitip.name_quantity(Dict(g.a), names) * " = 0"
             for g in Xitip.elemental_inequalities(3)]
    for statement in ("I(X;Y|Z) <= I(X;Y)", "I(X;Y;Z) >= 0",
                      "H(X,Y,Z) <= H(X,Y)", "I(X;Y) <= I(X;Z) + I(Y;Z)")
        brute = Set(t for t in every if prove([statement, t]))
        found = Set(only(f.constraints) for f in
                    sufficient_conditions(statement; maxsize=1,
                                          limit=99).found)
        @test found == brute
    end

    # a functional dependence reads as one
    c = sufficient_conditions("H(X) <= H(Y)")
    @test only(only(c.found).constraints) == "H(X|Y) = 0"
    @test occursin("X is a function of Y", only(only(c.found).meanings))

    # some statements need two assumptions, and none of size one is reported
    statement = "2H(X,Y,Z) <= H(X,Y) + H(Y,Z)"
    @test isempty(sufficient_conditions(statement; maxsize=1).found)
    pair = sufficient_conditions(statement; maxsize=2)
    @test !isempty(pair.found)
    for f in pair.found
        @test length(f.constraints) == 2
        @test prove(vcat(statement, f.constraints))
    end

    # and some have none at all within reach
    none = sufficient_conditions("H(X) + H(Y) + H(Z) <= H(X,Y,Z)"; maxsize=2)
    @test isempty(none.found)
    @test occursin("No set of at most 2", sprint(show, none))

    # reported sets are minimal: none contains another
    c = sufficient_conditions("2I(C;D) <= I(A;B) + I(A;C,D) + 3I(C;D|A) + I(C;D|B)";
                              maxsize=2, limit=5)
    sets = [Set(f.constraints) for f in c.found]
    @test all(!issubset(sets[i], sets[j])
              for i in eachindex(sets) for j in eachindex(sets) if i != j)

    # constraints already given are kept, and the search adds to them
    given = ["I(X;Y|Z) <= I(X;Y)", "H(Z|X,Y) = 0"]
    c = sufficient_conditions(given)
    @test !isempty(c.found)
    @test all(prove(vcat(given, f.constraints)) for f in c.found)

    @test_throws XitipError sufficient_conditions("H(X) >= 0")
    @test_throws XitipError sufficient_conditions("H(X) <= H(Y)"; maxsize=0)

    # the printed form names the statement and the assumptions
    text = sprint(show, MIME"text/plain"(), sufficient_conditions("H(X) <= H(Y)"))
    @test occursin("Not provable as it stands", text)
    @test occursin("H(X|Y) = 0", text)
end
