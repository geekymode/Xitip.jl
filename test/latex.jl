# Included from runtests.jl.

@testset "LaTeX output" begin
    tex = latex_string(explain("H(X,Y,Z) <= H(X,Y) + H(Z)"))
    @test occursin("\\begin{align*}", tex) && occursin("\\end{align*}", tex)
    @test occursin("I(X ; Z \\mid Y)", tex)     # conditioning bar
    @test occursin("&\\ge 0 .", tex)
    @test !occursin("|", tex)                  # a bare pipe is not maths mode
    @test !occursin("//", tex)                 # no Julia rationals

    # fractions and subscripted names
    tex = latex_string(explain("0.5 H(X1) + 0.5 H(X2) >= 0.5 H(X1,X2)"))
    @test occursin("\\tfrac{1}{2} I(X_1 ; X_2)", tex)
    @test occursin("H(X_1,X_2)", tex)
    @test occursin("H(X_1)", latex_string(explain("H(X1) >= 0")))
    @test occursin("\\mathit{Foo}", latex_string(explain("H(Foo) >= 0")))
    @test occursin("X_{10}", latex_string(explain("H(X10) >= 0")))

    # a constraint keeps its terms together under its multiplier
    tex = latex_string(explain("H(X) >= 1", "H(X) >= 2"))
    @test occursin("\\tfrac{1}{2} \\left( H(X) - 2 \\right)", tex)

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
                          ["0.5 H(X1) + 0.5 H(X2) >= 0.5 H(X1,X2)"],
                          ["H(X) >= 1", "H(X) >= 2"],
                          ["I(X;Z) <= I(X;Y)", "X/Y/Z"],
                          ["H(X1,X2,X3,X4) <= H(X1)+H(X2)+H(X3)+H(X4)"],
                          ["H(Foo,X10) >= H(Foo)"],
                          ["H(X) <= H(Y)"],
                          ["I(A;B) <= I(A;B|C) + I(A;B|D) + I(C;D)"])
                    latex(io, explain(e))
                end
                println(io, "\\end{document}")
            end
            ok = success(pipeline(Cmd(`$pdflatex -interaction=nonstopmode
                                       -halt-on-error doc.tex`; dir=dir);
                                  stdout=devnull, stderr=devnull))
            @test ok
            @test isfile(joinpath(dir, "doc.pdf"))
            # nothing ran past the page margin
            log = read(joinpath(dir, "doc.log"), String)
            @test !occursin("Overfull", log)
        end
    end
end
