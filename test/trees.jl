# Included from runtests.jl.

# every node reachable from the root exactly once, and nothing orphaned
function check_tree(t)
    seen = zeros(Int, length(t.nodes))
    stack = [t.root]
    while !isempty(stack)
        i = pop!(stack)
        seen[i] += 1
        append!(stack, t.nodes[i].children)
    end
    @test all(isequal(1), seen)
    return t
end

leaves(t) = [n for n in t.nodes if isempty(n.children)]

@testset "proof trees" begin
    t = check_tree(proof_tree(explain("H(X,Y,Z) <= H(X,Y) + H(Z)")))
    @test t.nodes[t.root].kind == :expression
    @test t.nodes[t.root].label == "H(Z) + H(X,Y) - H(X,Y,Z)"
    @test [n.label for n in leaves(t)] == ["I(X;Z|Y)", "I(Y;Z)"]
    @test occursin("├─ I(X;Z|Y)", sprint(show, MIME"text/plain"(), t))

    # one leaf per term of the proof, whatever the shape
    for lines in (["2 H(X,Y,Z) <= H(X,Y) + H(Y,Z) + H(X,Z)"],
                  ["I(W;Z) <= I(X;Y)", "W/X/Y/Z"],
                  ["H(X1,X2,X3,X4) <= H(X1)+H(X2)+H(X3)+H(X4)"],
                  ["H(X) >= 1", "H(X) >= 2"])
        r = explain(lines)
        t = check_tree(proof_tree(r))
        @test length(leaves(t)) == length(only(r.certificates).terms)
        @test count(n -> n.kind == :expression, t.nodes) == 1
    end

    # constraints are labelled C1, C2, ... and carry both their entropy form
    # and the reason they are non-negative
    t = proof_tree(explain("I(W;Z) <= I(X;Y)", "W/X/Y/Z"))
    cs = [n for n in t.nodes if n.kind == :constraint]
    @test [n.label for n in cs] == ["C1", "C2"]
    @test first(cs).detail == "H(X) - H(W,X) - H(X,Y) + H(W,X,Y)"
    @test first(cs).note == "-I(W;Y|X) = 0"
    # an inequality constraint has no name of its own, only its sign
    t = proof_tree(explain("H(X) >= 1", "H(X) >= 2"))
    @test only(n for n in t.nodes if n.kind == :constraint).note == ">= 0"

    # a left over constant is a leaf of its own
    t = proof_tree(explain("2 H(X) + 1 >= 0"))
    @test "1" in [n.label for n in leaves(t)]

    # nothing to draw
    @test_throws XitipError proof_tree(explain("H(X) <= H(Y)"))
    @test_throws XitipError proof_tree(explain("H(X) >= 0"; method=:simplex))
end

@testset "chain rule trees" begin
    t = check_tree(chain_rule_tree(["X", "Y", "Z"]))
    @test t.nodes[t.root].label == "H(X,Y,Z)"
    @test [n.label for n in leaves(t)] == ["H(X)", "H(Y|X)", "H(Z|X,Y)"]

    t = check_tree(chain_rule_tree(["A", "B"], ["C"]))
    @test t.nodes[t.root].label == "H(A,B|C)"
    @test [n.label for n in leaves(t)] == ["H(A|C)", "H(B|C,A)"]

    # n variables give n terms, and the last conditions on all the others
    for n in 1:6
        vars = ["X$i" for i in 1:n]
        t = check_tree(chain_rule_tree(vars))
        @test length(leaves(t)) == n
        @test last(leaves(t)).label ==
              (n == 1 ? "H(X1)" : "H(X$n|" * join(vars[1:n-1], ",") * ")")
    end
    @test_throws XitipError chain_rule_tree(String[])
end

@testset "constraint graphs" begin
    g = constraint_graph("I(W;Z) <= I(X;Y)", "W/X/Y/Z")
    @test Set(g.names) == Set(["W", "X", "Y", "Z"])
    @test all(e -> e[3] === :markov, g.edges)
    @test length(g.edges) == 3                      # one per link
    name(i) = g.names[i]
    @test Set((name(a), name(b)) for (a, b, _, _) in g.edges) ==
          Set([("W", "X"), ("X", "Y"), ("Y", "Z")])

    g = constraint_graph("H(X) >= 0", "X.Y.Z")      # mutual independence
    @test length(g.edges) == 3                      # every pair
    @test all(e -> e[3] === :independent, g.edges)

    g = constraint_graph("H(X) >= 0", "X:Y,Z")      # X is a function of Y,Z
    @test all(e -> e[3] === :function, g.edges)
    @test Set((g.names[a], g.names[b]) for (a, b, _, _) in g.edges) ==
          Set([("Y", "X"), ("Z", "X")])

    # sets on the links of a Markov chain
    g = constraint_graph("H(X) >= 0", "X/Y,Z/W")
    @test length(g.edges) == 4

    # constraints with no natural edge, and the statement itself, are left out
    g = constraint_graph("I(X;Y) >= 0", "I(X;Y|Z) = 0", "H(W) = 0")
    @test isempty(g.edges)
    g = constraint_graph("X/Y/Z")                   # the statement, not a constraint
    @test isempty(g.edges)

    # mixed kinds keep their own edges
    g = constraint_graph("H(X) >= 0", "X:Y,Z", "Y/Z/W")
    @test Set(e[3] for e in g.edges) == Set([:function, :markov])
end

@testset "counterexample tables" begin
    t = entropy_table(explain("H(X) <= H(Y)"))
    @test first.(t) == ["H(X)", "H(Y)", "H(X,Y)"]
    @test last.(t) == Coef[5, 4, 7]

    # ordered by the size of the subset, then by the subset itself
    t = entropy_table(explain("I(A;B) <= I(A;B|C) + I(A;B|D) + I(C;D)"))
    @test length(t) == 15
    @test first.(t)[1:4] == ["H(A)", "H(B)", "H(C)", "H(D)"]
    @test last(t).first == "H(A,B,C,D)"
    counts = [count(==(','), k) + 1 for (k, _) in t]
    @test issorted(counts)
    # the values really are the counterexample's
    c = only(explain("I(A;B) <= I(A;B|C) + I(A;B|D) + I(C;D)").certificates)
    @test Set(last.(t)) == Set(c.entropies)

    @test_throws Exception entropy_table(explain("H(X) >= 0"))   # no counterexample
end

@testset "plotting needs the extension" begin
    # without CairoMakie and friends loaded, the hint says what to load
    for call in (() -> plot_proof_tree(explain("H(X) >= 0")),
                 () -> plot_chain_rule(["X", "Y"]),
                 () -> plot_constraints("H(X) >= 0", "X/Y/Z"),
                 () -> plot_counterexample(explain("H(X) <= H(Y)")))
        err = try call() catch e; e end
        @test err isa XitipError
        @test occursin("CairoMakie", sprint(showerror, err))
        @test occursin("GraphMakie", sprint(showerror, err))
    end
end
