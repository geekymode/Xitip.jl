# Included from runtests.jl.

# Run the command line interface, returning (exit code, stdout, stderr).
function run_cli(args...)
    out, err = IOBuffer(), IOBuffer()
    code = Xitip.main(String[args...]; out, err)
    return code, String(take!(out)), String(take!(err))
end

@testset "command line interface" begin
    code, out, _ = run_cli("I(X;Y|Z) <= I(X;Y)", "H(Z) = 0")
    @test code == 0 && occursin("TRUE", out)

    code, out, _ = run_cli("I(X;Y|Z) <= I(X;Y)")
    @test code == 1 && occursin("non-Shannon", out)

    code, out, _ = run_cli("--count", "I(X;Y|Z) <= I(X;Y)")
    @test code == 0 && strip(out) == "3"
    @test run_cli("-c", "H(X) >= 0")[2] |> strip == "1"

    code, out, err = run_cli("I(X;;Y) >= 0")
    @test code == 2 && isempty(out) && occursin("syntax error", err)

    code, _, err = run_cli("H(X) >= 0", "H(X) = 1", "H(X) = 2")
    @test code == 2 && occursin("contradictory", err)

    # --proof prints the certificate
    code, out, _ = run_cli("--proof", "H(X,Y) <= H(X) + H(Y)")
    @test code == 0 && occursin("I(X;Y) >= 0", out)
    code, out, _ = run_cli("-p", "H(X) <= H(Y)")
    @test code == 1 && occursin("H(X,Y)", out)

    # --quiet prints nothing but keeps the exit code
    for args in (("H(X) >= 0",), ("H(X) >= 1",), ("I(X;;Y) >= 0",))
        code, out, err = run_cli("--quiet", args...)
        @test isempty(out) && isempty(err)
        @test code == (args[1] == "H(X) >= 0" ? 0 : args[1] == "H(X) >= 1" ? 1 : 2)
    end

    # --simplex agrees with the default method
    @test run_cli("--simplex", "H(X,Y) <= H(X) + H(Y)")[1] == 0
    @test run_cli("--simplex", "H(X) <= H(Y)")[1] == 1

    # expressions may start with '-'
    @test run_cli("-H(X) <= 0")[1] == 0

    code, out, _ = run_cli("--help")
    @test code == 0 && occursin("usage: xitip", out)
    code, out, _ = run_cli("--version")
    @test code == 0 && occursin("Xitip.jl", out)
    code, _, err = run_cli("--nonsense")
    @test code == 2 && occursin("unknown option", err)
end
