# Included from runtests.jl.
#
# These check what the exported Lean source says. Whether Lean accepts it is
# checked by lean/verify.jl, which needs a Mathlib project and so does not
# run here.

@testset "lean export" begin
    source = lean("H(X,Y,Z) <= H(X,Y) + H(Z)")
    @test occursin("import Mathlib", source)
    @test occursin("theorem xitip_proof", source)
    @test occursin("linarith", source)
    @test occursin("(h_", source) && occursin(" : ℝ)", source)
    # the statement appears as a comment, so the file says what it proves
    @test occursin("H(X,Y,Z) <= H(X,Y) + H(Z)", source)
    @test !occursin("import", lean("H(X,Y,Z) <= H(X,Y) + H(Z)"; imports=false))
    @test occursin("theorem my_thm", lean("H(X) >= 0"; theorem="my_thm"))

    # the goal and the hypotheses must be the certificate, not a paraphrase:
    # the multipliers times the quantities have to add up to the expression
    for lines in (["H(X,Y,Z) <= H(X,Y) + H(Z)"],
                  ["I(W;Z) <= I(X;Y)", "W/X/Y/Z"],
                  ["2 H(X,Y,Z) <= H(X,Y) + H(Y,Z) + H(X,Z)"],
                  ["0.5 H(X) + 0.25 H(Y) <= H(X) + H(Y)"],
                  ["H(X) >= 1", "H(X) >= 2"])
        for proof in [c for c in explain(lines).certificates
                      if c isa Xitip.Proof]
            total = Dict{Int,Xitip.Coef}()
            for step in proof.steps, (mask, v) in step.quantity
                total[mask] = get(total, mask, zero(Xitip.Coef)) +
                              step.coefficient * v
            end
            iszero(proof.constant) ||
                (total[0] = get(total, 0, zero(Xitip.Coef)) + proof.constant)
            filter!(kv -> !iszero(kv.second), total)
            @test total == proof.coefficients
        end
    end

    # every hypothesis in the file is one of the proof's quantities, and the
    # goal is the expression
    lines = ["H(X,Y,Z) <= H(X,Y) + H(Z)"]
    proof = only(explain(lines).certificates)
    source = lean(lines; imports=false)
    @test count(l -> occursin(r"^    \(e\d+ :", l), split(source, '\n')) ==
          length(proof.steps)
    @test occursin("0 ≤ h_X_Y + h_Z - h_X_Y_Z := by", source)

    # only the entropies that are mentioned get a variable
    @test occursin("(h_Y h_X_Y h_Y_Z h_X_Y_Z h_Z : ℝ)", source)
    @test !occursin("h_X ", source)          # H(X) alone is never used here

    # rationals stay exact and typed, never a float
    ratio = lean("0.5 H(X) + 0.25 H(Y) <= H(X) + H(Y)"; imports=false)
    @test occursin("(1/2 : ℝ)", ratio)
    @test occursin("(3/4 : ℝ)", ratio)
    @test !occursin("0.5", replace(ratio, "0.5 H(X) + 0.25 H(Y)" => ""))

    # an identity has nothing to assume, so it must not emit an empty binder
    identity = lean("I(X;Y) = H(X) + H(Y) - H(X,Y)"; imports=false)
    @test !occursin("( : ℝ)", identity)
    @test occursin("theorem xitip_proof_1", identity)   # one per direction
    @test occursin("theorem xitip_proof_2", identity)

    # a constant term rides along as a number, on both sides
    constant = lean("H(X) >= 1", "H(X) >= 2"; imports=false)
    @test occursin("(e1 : 0 ≤ -2 + h_X)", constant)
    @test occursin(": 0 ≤ -1 + h_X := by", constant)
    # and a constraint keeps its own text, without a second relation tacked on
    @test occursin("-- from constraint 1: H(X) >= 2\n", constant)
    @test !occursin(">= 2 >= 0", constant)

    # nothing to export
    @test_throws XitipError lean("H(X) <= H(Y)")
    @test_throws XitipError lean("I(X;Y;Z) >= 0")
    @test_throws XitipError lean("H(X) >= 0"; method=:simplex)
end
