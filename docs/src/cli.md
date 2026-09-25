```@meta
CurrentModule = Xitip
```

# Command line

`bin/xitip` runs the prover from a shell:

```console
$ bin/xitip 'I(X;Y|Z) <= I(X;Y)' 'H(Z) = 0'
The information expression is TRUE.
```

The first expression is the statement to prove; any further ones are
constraints. With no arguments, or when the last argument is `-`, expressions
are read from standard input, one per line, so a problem can live in a file:

```console
$ cat markov.txt
I(W;Z) <= I(X;Y)
W/X/Y/Z
$ bin/xitip - < markov.txt
The information expression is TRUE.
```

## Options

| Option | Meaning |
|:--|:--|
| `-p`, `--proof` | print the proof, or the counterexample if there is none |
| `-s`, `--steps` | print the proof as a step-by-step derivation |
| `-l`, `--latex` | print the proof or counterexample as LaTeX |
| `-c`, `--count` | print the number of distinct random variables instead |
| `--simplex` | decide with the exact simplex method only (slow; for cross-checking) |
| `-q`, `--quiet` | print nothing, only set the exit code |
| `-v`, `--version` | print the version |
| `-h`, `--help` | print usage |

## Exit codes

| Code | Meaning |
|:--|:--|
| 0 | the statement is true (or `--count` succeeded) |
| 1 | false, or a non-Shannon-type inequality |
| 2 | error: syntax error, contradictory constraints, too many variables |
| 3 | internal error |

So a shell script can branch on the result:

```console
$ if bin/xitip -q 'I(X;Z) <= I(X;Y)' 'X/Y/Z'; then echo proven; fi
proven
```

## Startup time

Each invocation pays for Julia's startup and code loading, about two seconds.
For many statements, prefer one session:

```julia
using Xitip
for line in eachline("statements.txt")
    println(prove(line), "  ", line)
end
```

## Calling it from Julia

[`Xitip.main`](@ref) is the command line interface itself, and takes the
streams to write to, which makes it easy to drive from a script or a test:

```@example cli
using Xitip
out = IOBuffer()
code = Xitip.main(["--steps", "H(X,Y) <= H(X) + H(Y)"]; out=out)
(code, String(take!(out)))
```
