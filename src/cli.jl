#----------------------------------------------------------------------------
# Command line interface
#----------------------------------------------------------------------------

const USAGE = """
usage: xitip [options] EXPR [CONSTRAINT ...] [-]

Information Theoretic Inequality Prover. Checks whether the first
expression is a Shannon-type consequence of the remaining ones. Expressions
are read from STDIN (one per line) if none are given or the last argument
is '-'.

Syntax:
  H(X,Y|Z)                  (conditional) joint entropy
  I(X;Y;Z|W)  I(X:Y)        (conditional, multivariate) mutual information
  2 H(X) - 0.5 I(X;Y) >= 1  linear combinations; relations <= >= =
  X/Y/Z                     Markov chain
  X.Y.Z                     mutual independence
  X:Y,Z                     X is a function of Y,Z
  # ...                     comment

Options:
  -p, --proof     print the proof, or the counterexample if there is none
  -c, --count     print the number of distinct random variables instead
      --simplex   decide with the exact simplex method only (slow, for
                  cross-checking)
  -q, --quiet     print nothing, only set the exit code
  -v, --version   print the version
  -h, --help      print this message

Exit codes:
  0  TRUE (or --count succeeded)
  1  FALSE or a non-Shannon-type inequality
  2  error (syntax error, contradictory constraints, ...)
  3  internal error
"""

"""
    main(args=ARGS; out=stdout, err=stderr) -> Int

Run the command line interface and return the exit code; see
`Xitip.USAGE`. The streams can be redirected, which is useful for testing.
"""
function main(args::Vector{String}; out::IO=stdout, err::IO=stderr)::Int
    count, proof, quiet, use_stdin = false, false, false, isempty(args)
    method = :auto
    exprs = String[]
    for a in args
        if a in ("-h", "--help")
            print(out, USAGE)
            return 0
        elseif a in ("-v", "--version")
            println(out, "Xitip.jl ", VERSION_STRING)
            return 0
        elseif a in ("-c", "--count")
            count = true
        elseif a in ("-p", "--proof")
            proof = true
        elseif a in ("-q", "--quiet")
            quiet = true
        elseif a == "--simplex"
            method = :simplex
        elseif a == "-"
            use_stdin = true
        elseif startswith(a, "--") || (startswith(a, "-") && length(a) > 1 &&
                                       isletter(a[2]) && !occursin(r"[(;|]", a))
            println(err, "ERROR: unknown option $a\n\n", USAGE)
            return 2
        else
            push!(exprs, a)
        end
    end
    use_stdin |= isempty(exprs)
    use_stdin && append!(exprs, readlines(stdin))

    say(args...) = (quiet || println(out, args...); nothing)
    try
        if count
            say(count_variables(exprs))
            return 0
        end
        result = explain(exprs; method)
        if proof && !quiet
            show(out, MIME"text/plain"(), result)
        elseif result.verdict
            say("The information expression is TRUE.")
        else
            say("The information expression is either:\n",
                "    1. FALSE, or\n",
                "    2. a non-Shannon type inequality")
        end
        return result.verdict ? 0 : 1
    catch e
        if e isa XitipError || e isa SyntaxError
            quiet || println(err, "ERROR: ", sprint(showerror, e))
            return 2
        end
        quiet || println(err, "INTERNAL ERROR: ",
                         sprint(showerror, e, catch_backtrace()))
        return 3
    end
end

main(; kw...) = main(copy(ARGS); kw...)
