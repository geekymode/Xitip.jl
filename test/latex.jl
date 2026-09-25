# Included from runtests.jl.

@testset "LaTeX output" begin
    tex = latex_string(explain("H(X,Y,Z) <= H(X,Y) + H(Z)"))
    @test occursin("\\begin{align*}", tex) && occursin("\\end{align*}", tex)
    @test occursin("I(X ; Z \\mid Y)", tex)     # conditioning bar
    @test occursin("\\;\\ge\\; 0", tex)
    @test occursin("E &= H(Z) + H(X,Y) - H(X,Y,Z)", tex)
    @test occursin("&= I(X ; Z \\mid Y) + I(Y ; Z)", tex)
    @test !occursin("|", tex)                  # a bare pipe is not maths mode
    @test !occursin("//", tex)                 # no Julia rationals

    # fractions and subscripted names
    tex = latex_string(explain("0.5 H(X1) + 0.5 H(X2) >= 0.5 H(X1,X2)"))
    @test occursin("\\tfrac{1}{2} I(X_1 ; X_2)", tex)
    @test occursin("H(X_1,X_2)", tex)
    @test occursin("H(X_1)", latex_string(explain("H(X1) >= 0")))
    @test occursin("\\mathit{Foo}", latex_string(explain("H(Foo) >= 0")))
    @test occursin("X_{10}", latex_string(explain("H(X10) >= 0")))

    # constraints become C_1, C_2, ... and are defined below the chain
    tex = latex_string(explain("H(X) >= 1", "H(X) >= 2"))
    @test occursin("\\tfrac{1}{2} C_{1}", tex)
    @test occursin("C_{1} &= H(X) - 2", tex)
    @test occursin("\\text{(from constraint 1)}", tex)
    @test !occursin(">=", tex)          # text mode would mangle it
    tex = latex_string(explain("I(X;Z) <= I(X;Y)", "X/Y/Z"))
    @test occursin("\\text{(from constraint 1, reversed)}", tex)

    # steps=true gives the full chain, expand=true all the definitions
    tex = latex_string(explain("H(X,Y,Z) <= H(X,Y) + H(Z)"); steps=true)
    @test occursin("+ [ H(Y) + H(Z) - H(Y,Z) ]", tex)
    @test !occursin("where", tex)       # no constraints to define
    tex = latex_string(explain("H(X,Y,Z) <= H(X,Y) + H(Z)"); expand=true)
    @test occursin("I(Y ; Z) &= H(Y) + H(Z) - H(Y,Z)", tex)

    # counterexamples
    tex = latex_string(explain("H(X) <= H(Y)"))
    @test occursin("\\;<\\; 0", tex) && occursin("H(X,Y) &=", tex)

    # no certificate to render
    @test occursin("% no certificate", latex_string(explain("H(X) >= 0"; method=:simplex)))

    # command line
    code, out, _ = run_cli("--latex", "H(X,Y,Z) <= H(X,Y) + H(Z)")
    @test code == 0 && occursin("\\begin{align*}", out)
    code, out, _ = run_cli("-l", "H(X) <= H(Y)")
    @test code == 1 && occursin("\\;<\\; 0", out)
end

@testset "LaTeX compiles" begin
    # Only where a TeX installation is available (skipped in CI).
    pdflatex = Sys.which("pdflatex")
    if pdflatex === nothing
        @info "pdflatex not found, skipping the compilation test"
    else
        mktempdir() do dir
            open(joinpath(dir, "doc.tex"), "w") do io
                println(io, "\\documentclass{article}")
                println(io, "\\usepackage{amsmath}")
                println(io, "\\begin{document}")
                for e in (["H(X,Y,Z) <= H(X,Y) + H(Z)"],
                          ["H(X1,X2,X3,X4,X5) <= H(X1)+H(X2)+H(X3)+H(X4)+H(X5)"],
                          ["0.5 H(X1) + 0.5 H(X2) >= 0.5 H(X1,X2)"],
                          ["H(X) >= 1", "H(X) >= 2"],
                          ["I(X;Z) <= I(X;Y)", "X/Y/Z"],
                          ["I(W;Z) <= I(X;Y)", "W/X/Y/Z"],
                          ["H(X1,X2,X3,X4) <= H(X1)+H(X2)+H(X3)+H(X4)"],
                          ["H(Foo,X10) >= H(Foo)"],
                          ["H(X) <= H(Y)"],
                          ["I(A;B) <= I(A;B|C) + I(A;B|D) + I(C;D)"])
                    latex(io, explain(e))
                    latex(io, explain(e); steps=true, expand=true)
                end
                println(io, "\\end{document}")
            end
            ok = success(pipeline(Cmd(`$pdflatex -interaction=nonstopmode
                                       -halt-on-error doc.tex`; dir=dir);
                                  stdout=devnull, stderr=devnull))
            @test ok
            @test isfile(joinpath(dir, "doc.pdf"))
            # nothing ran past the right margin (an overfull \\vbox would
            # only mean the test document itself needs a page break)
            log = read(joinpath(dir, "doc.log"), String)
            @test !occursin("Overfull \\hbox", log)
        end
    end
end
