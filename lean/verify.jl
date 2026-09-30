#!/usr/bin/env julia
#
# Generate the Lean core of several proofs and compile them, plus a negative
# control. Usage:  julia --project=. lean/verify.jl <path to a Mathlib project>

using Xitip

project = length(ARGS) >= 1 ? ARGS[1] :
          error("usage: julia lean/verify.jl <path to a Lean project with Mathlib>")
isdir(project) || error("no such directory: $project")

eight = ["X$i" for i in 1:8]
cases = [
    "sub"      => ["H(X,Y,Z) <= H(X,Y) + H(Z)"],
    "markov"   => ["I(W;Z) <= I(X;Y)", "W/X/Y/Z"],
    "han"      => ["2 H(X,Y,Z) <= H(X,Y) + H(Y,Z) + H(X,Z)"],
    "identity" => ["I(X;Y) = H(X) + H(Y) - H(X,Y)"],
    "constant" => ["H(X) >= 1", "H(X) >= 2"],
    "four"     => ["H(X1,X2,X3,X4) <= H(X1)+H(X2)+H(X3)+H(X4)"],
    "rational" => ["0.5 H(X) + 0.25 H(Y) <= H(X) + H(Y)"],
    "eight"    => ["H(" * join(eight, ",") * ") <= " *
                   join(("H($x)" for x in eight), " + ")],
]

# elan installs into ~/.elan/bin, which a non-login shell may not have
const LAKE = something(Sys.which("lake"),
                       let e = joinpath(homedir(), ".elan", "bin", "lake")
                           isfile(e) ? e : nothing
                       end,
                       Some(nothing))
LAKE === nothing && error("lake not found; install Lean with elan first")

compiles(file) = success(pipeline(Cmd(`$LAKE env lean $file`; dir=project);
                                  stdout=devnull, stderr=devnull))

failures = String[]
for (name, lines) in cases
    file = "Xitip_$name.lean"
    write(joinpath(project, file), lean(lines; theorem="xitip_$name"))
    ok = compiles(file)
    println(rpad(name, 10), ok ? "compiles" : "FAILED")
    ok || push!(failures, name)
end

# a proof whose hypotheses are not all needed would be passing for the wrong
# reason, so check that Lean rejects it once one of them is gone
source = lean(cases[1].second; theorem="xitip_control")
without = join([l for l in split(source, '\n') if !occursin("(e1 :", l)], '\n')
write(joinpath(project, "Xitip_control.lean"), without)
if compiles("Xitip_control.lean")
    println("control   FAILED: still compiles without a hypothesis")
    push!(failures, "control")
else
    println("control   rejected as it should be")
end

foreach(f -> rm(joinpath(project, "Xitip_$f.lean"); force=true),
        [first.(cases); "control"])
isempty(failures) || error("Lean rejected: " * join(failures, ", "))
println("\nall proofs compiled, control rejected")
