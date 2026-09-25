# Xitip.jl

[**Documentation**](https://geekymode.github.io/Xitip.jl/dev/) |
[Examples](https://geekymode.github.io/Xitip.jl/dev/examples/) |
[Plots](https://geekymode.github.io/Xitip.jl/dev/plots/) |
[How it works](https://geekymode.github.io/Xitip.jl/dev/internals/)

Information Theoretic Inequality Prover in pure Julia.

Xitip.jl decides whether an expression over entropies and mutual
informations of discrete random variables follows from the basic properties
of Shannon entropy — optionally under constraints such as Markov chains,
independence, or functional dependence.

It is a reimplementation of [Xitip](http://xitip.epfl.ch/) / Citip / ITIP
that needs only Julia's standard library: parser, prover and solvers are all
in this package. Two things set it apart from those tools:

- **Every answer is exact.** The verdict never depends on a floating point
  tolerance. Coefficients are exact rationals, so `0.1` means exactly 1/10.
- **Every answer comes with a certificate**, verified in exact rational
  arithmetic: a proof that writes the expression as a non-negative
  combination of basic inequalities — printable as a step-by-step
  derivation — or a counterexample that satisfies every basic inequality
  and constraint but not the expression.

## Installation

The package is not registered. From a local clone:

```julia
julia> using Pkg; Pkg.develop(path="/path/to/Xitip.jl")
```

It has no dependencies beyond the standard library. Plotting is optional: a
package extension adds it when CairoMakie, GraphMakie, Graphs and
NetworkLayout are loaded, see the
[Plots](https://geekymode.github.io/Xitip.jl/dev/plots/) page. `Project.toml` declares
Julia 1.6 and later; it has only been run here on 1.13, and the CI workflow
covers 1.6, 1.10 and the current release.

## Quick start

```julia
julia> using Xitip

julia> prove("I(X;Y|Z) <= I(X;Y)")          # not a Shannon-type inequality
false

julia> prove("I(X;Y|Z) <= I(X;Y)", "H(Z) = 0")    # with a constraint
true

julia> prove("I(X;Z) <= I(X;Y)", "X/Y/Z")         # data processing
true
```

`explain` returns the same verdict with its certificate:

```julia
julia> explain("H(X,Y) <= H(X) + H(Y)")
TRUE
Proof of  H(X) + H(Y) - H(X,Y) >= 0:
         1 * ( I(X;Y) >= 0 )

julia> print_proof(explain("2 H(X,Y,Z) <= H(X,Y) + H(Y,Z) + H(X,Z)"))
Proof of  E >= 0  where  E = H(X,Y) + H(X,Z) + H(Y,Z) - 2 H(X,Y,Z)

  E  =  H(X,Y) + H(X,Z) + H(Y,Z) - 2 H(X,Y,Z)
     =  I(X;Y|Z)  +  [ H(Z) + H(X,Y) - H(X,Y,Z) ]
     =  I(X;Y|Z)  +  I(X;Z|Y)  +  [ H(Y) + H(Z) - H(Y,Z) ]
     =  I(X;Y|Z)  +  I(X;Z|Y)  +  I(Y;Z)

  where every term is non-negative:
    I(X;Y|Z)  =  -H(Z) + H(X,Z) + H(Y,Z) - H(X,Y,Z)  >= 0
    I(X;Z|Y)  =  -H(Y) + H(X,Y) + H(Y,Z) - H(X,Y,Z)  >= 0
    I(Y;Z)    =  H(Y) + H(Z) - H(Y,Z)                >= 0

  so E is a sum of non-negative terms, hence E >= 0.
```

The chain of equalities splits one non-negative quantity off the
expression at a time; the bracket is what is still left to account for, and
the last line has nothing left. Every term is then listed with its entropy
form, so each line can be checked by hand. Where a remainder (or the
statement itself) is a single information quantity it is named, and
constraints appear as `C1`, `C2`, ... with their own text alongside.

For a paper, `latex` writes the same proof as an `align*` block (long
expressions are wrapped, and counterexamples become a table of entropy
values):

```julia
julia> latex(explain("H(X,Y,Z) <= H(X,Y) + H(Z)"))
\begin{align*}
  &H(Z) + H(X,Y) - H(X,Y,Z) \\
    &= I(X ; Z \mid Y) + I(Y ; Z) \\
    &\ge 0 .
\end{align*}
```

### Command line

`bin/xitip` is a ready-to-run script:

```console
$ bin/xitip 'I(X;Y|Z) <= I(X;Y)' 'H(Z) = 0'
The information expression is TRUE.

$ bin/xitip --proof 'H(X,Y) <= H(X) + H(Y)'
TRUE
Proof of  H(X) + H(Y) - H(X,Y) >= 0:
         1 * ( I(X;Y) >= 0 )

$ bin/xitip --steps 'H(X,Y,Z) <= H(X,Y) + H(Z)'
Proof of  E >= 0  where  E = H(Z) + H(X,Y) - H(X,Y,Z)  =  I(X,Y;Z)

  E  =  H(Z) + H(X,Y) - H(X,Y,Z)
     =  I(X;Z|Y)  +  [ H(Y) + H(Z) - H(Y,Z) ]
     =  I(X;Z|Y)  +  I(Y;Z)

  where every term is non-negative:
    I(X;Z|Y)  =  -H(Y) + H(X,Y) + H(Y,Z) - H(X,Y,Z)  >= 0
    I(Y;Z)    =  H(Y) + H(Z) - H(Y,Z)                >= 0

  so E is a sum of non-negative terms, hence E >= 0.

$ bin/xitip --count 'I(X;Y|Z) <= I(X;Y)'
3
```

The first expression is the one to be proven; any further ones are
constraints. With no arguments, or when the last argument is `-`,
expressions are read from standard input, one per line.

| Option | Meaning |
|:--|:--|
| `-p`, `--proof` | print the proof, or the counterexample if there is none |
| `-s`, `--steps` | print the proof as a step-by-step derivation |
| `-l`, `--latex` | print the proof or counterexample as LaTeX |
| `-c`, `--count` | print the number of distinct random variables instead (like `oXitipLen`) |
| `--simplex` | decide with the exact simplex method only (slow; for cross-checking) |
| `-q`, `--quiet` | print nothing, only set the exit code |
| `-v`, `--version`, `-h`, `--help` | version / usage |

Exit codes: `0` true, `1` false or non-Shannon-type, `2` error (syntax,
contradictory constraints), `3` internal error.

### A longer example

Data processing for a four-variable Markov chain, `I(W;Z) <= I(X;Y)` given
`W/X/Y/Z`. The chain implies one relation per link, so two of them appear
as `C1` and `C2`:

```console
$ bin/xitip --steps 'I(W;Z) <= I(X;Y)' 'W/X/Y/Z'
Proof of  E >= 0  where  E = -H(W) - H(Z) + H(X) + H(Y) + H(W,Z) - H(X,Y)

  E  =  -H(W) - H(Z) + H(X) + H(Y) + H(W,Z) - H(X,Y)
     =  C1  +  [ -H(W) - H(Z) + H(Y) + H(W,Z) + H(W,X) - H(W,X,Y) ]
     =  C1  +  C2  +  [ -H(W) - H(Z) + H(W,Z) + H(W,X) + H(Z,Y) - H(W,Z,X,Y) ]
     =  C1  +  C2  +  I(W;Y|Z,X)  +  [ -H(W) - H(Z) + H(W,Z) + H(W,X) + H(Z,X) + H(Z,Y) - H(W,Z,X) - H(Z,X,Y) ]
     =  C1  +  C2  +  I(W;Y|Z,X)  +  I(Z;X|W)  +  [ -H(Z) + H(Z,X) + H(Z,Y) - H(Z,X,Y) ]
     =  C1  +  C2  +  I(W;Y|Z,X)  +  I(Z;X|W)  +  I(X;Y|Z)

  where every term is non-negative:
    C1          =  H(X) - H(W,X) - H(X,Y) + H(W,X,Y)           >= 0   (from constraint 1, reversed: W/X/Y/Z)
    C2          =  H(Y) - H(Z,Y) - H(W,X,Y) + H(W,Z,X,Y)       >= 0   (from constraint 1, reversed: W/X/Y/Z)
    I(W;Y|Z,X)  =  -H(Z,X) + H(W,Z,X) + H(Z,X,Y) - H(W,Z,X,Y)  >= 0
    I(Z;X|W)    =  -H(W) + H(W,Z) + H(W,X) - H(W,Z,X)          >= 0
    I(X;Y|Z)    =  -H(Z) + H(Z,X) + H(Z,Y) - H(Z,X,Y)          >= 0

  so E is a sum of non-negative terms, hence E >= 0.
```

The same proof as LaTeX, ready for a paper:

```latex
julia> latex(explain("I(W;Z) <= I(X;Y)", "W/X/Y/Z"))
\begin{align*}
  E &= - H(W) - H(Z) + H(X) + H(Y) + H(W,Z) - H(X,Y) \\
    &= C_{1} + C_{2} + I(W ; Y \mid Z,X) + I(Z ; X \mid W) \\
    &\quad + I(X ; Y \mid Z) \;\ge\; 0
\end{align*}
where
\begin{align*}
  C_{1} &= H(X) - H(W,X) - H(X,Y) + H(W,X,Y) \;\ge\; 0 \\
    &\quad \text{(from constraint 1, reversed)} \\
  C_{2} &= H(Y) - H(Z,Y) - H(W,X,Y) + H(W,Z,X,Y) \;\ge\; 0 \\
    &\quad \text{(from constraint 1, reversed)}
\end{align*}
```

`latex(...; steps=true)` gives the full chain instead of the one-line
identity, and `expand=true` adds the entropy form of every term (the
constraints are always listed). The output compiles with `amsmath`, and
long expressions are wrapped to stay inside the page margin.

## Expression syntax

| Syntax | Meaning |
|:--|:--|
| `H(X)`, `H(X,Y)`, `H(X,Y|Z,W)` | (conditional) joint entropy |
| `I(X;Y)`, `I(X;Y|Z)`, `I(X;Y;Z)` | (conditional, multivariate) mutual information; `:` works as `;` |
| `2 H(X) - 0.5 I(X;Y) >= 1` | linear combinations, with relations `<=`, `>=`, `=` |
| `X/Y/Z/W` | Markov chain (any length, sets allowed: `X/Y,Z/W`) |
| `X.Y.Z` | mutual independence |
| `X:Y,Z` | `X` is a function of `Y,Z` |
| `# ...` | comment |

Variable names are `[A-Za-z][A-Za-z0-9_]*`. `H` and `I` are ordinary names
unless followed by `(`.

## API

| Function | Purpose |
|:--|:--|
| `prove(lines...; method=:auto) -> Bool` | is the first statement implied by the rest? |
| `explain(lines...; method=:auto) -> Result` | same, with certificates |
| `print_proof([io], x)` | print a `Result`, `Proof` or `Counterexample` as a step-by-step derivation |
| `proof_tree(x)`, `chain_rule_tree(vars)`, `constraint_graph(lines...)` | the same decompositions as data |
| `plot_proof_tree(x)`, `plot_chain_rule(vars)`, `plot_constraints(lines...)` | draw them (needs CairoMakie and GraphMakie) |
| `latex([io], x; steps, expand)`, `latex_string(x)` | the same as LaTeX (`align*`, needs `amsmath`) |
| `count_variables(lines...) -> Int` | number of distinct random variables |
| `Xitip.main(args; out, err) -> Int` | the command line interface |

`Result` has fields `verdict::Bool` and `certificates::Vector`, holding
`Proof` values (one per part of a true statement; an equality has two) or a
single `Counterexample`. `Proof` lists the multiplier of each basic
inequality used, and its `steps` hold the same proof as a derivation
(`ProofStep`: multiplier, inequality, its entropy form, and the remainder
after subtracting it). `Counterexample` holds the entropy values `h` indexed by
subset bitmask, with `direction = true` when `h` is a direction along which
the expression decreases without bound rather than a single point.

Errors: `SyntaxError` (with the offending line and a marker) and
`XitipError` (contradictory constraints, too many variables).

`method=:simplex` decides with the exact simplex method alone. It produces
no certificate and is much slower beyond about 7 variables, but it is an
independent implementation, which the test suite uses for cross-checking.

## How it works

An expression `v·h + v₀ ≥ 0` over the vector `h` of joint entropies is
Shannon-type when it follows from the *elemental inequalities*
`H(Xᵢ|rest) ≥ 0` and `I(Xᵢ;Xⱼ|X_K) ≥ 0`, which generate all of them. By
Farkas' lemma, exactly one of these holds:

- `v` is a non-negative combination of those inequalities and the
  constraints — **a proof**;
- there is an `h` satisfying all of them but not the expression — **a
  counterexample**.

The package finds whichever exists by projecting the target onto the cone
generated by the inequalities, using non-negative least squares
(Lawson–Hanson) in floating point: a zero residual gives the proof's
multipliers, a non-zero residual is the counterexample. The result is then
**verified exactly**: the multipliers are recomputed as exact rationals and
checked for non-negativity, and a counterexample is rounded to small
integers and checked against every inequality exactly. Only if verification
fails does an exact rational simplex method decide (which the test suite
never had to do, over thousands of random problems).

## Performance

Time per call in a warm session, on an Apple Silicon laptop. `n` is the
number of random variables; the problem has 2ⁿ−1 dimensions and grows to
1800 basic inequalities at `n = 8`.

| n | provable | not provable |
|--:|--:|--:|
| 4 | 0.003 s | 0.001 s |
| 5 | < 0.001 s | 0.001 s |
| 6 | 0.001 s | 0.005 s |
| 7 | 0.003 s | 0.07 s |
| 8 | 0.033 s | 1.0 s |

The command line adds about 2.3 s for Julia's startup and code loading, so
for many expressions prefer a single session over repeated `bin/xitip`
calls. For comparison, the exact simplex method (`--simplex`) needs 20 s
for the 8-variable case in the right column, which is why it is only the
fallback.

A statement that cannot be proven takes longer when constraints are
involved, because the counterexample then has to be certified by an exact
projection rather than by rounding: about 12 s for an 8-variable problem
with a handful of constraints.

## Limitations

- **Non-Shannon-type inequalities.** A negative answer means "not provable
  from the basic inequalities": either false, or true for a deeper reason.
  The Zhang–Yeung inequality is true but correctly reported as not
  provable here.
- Counterexamples are polymatroids. Beyond three variables not every
  polymatroid comes from an actual probability distribution, so a
  counterexample refutes provability, not necessarily the statement.
- At most 30 variables, and in practice about 9: the problem size doubles
  with each variable.
- Variables that always appear together are not collapsed, an optimization
  the original Xitip had.

## Tests

```console
$ julia --project=. -e 'using Pkg; Pkg.test()'
```

5414 checks covering the parser, known Shannon and non-Shannon results,
constraints, the certificate checks (including rejection of wrong
certificates), the command line interface, and randomized problems that are
cross-checked against the simplex method and against entropies of random
probability distributions. Proofs are re-verified independently there: the
multipliers times the inequalities they name must add up to the expression.
Where a TeX installation is available, the generated LaTeX is compiled with
`pdflatex` and checked for lines running past the margin.

## Credits

Xitip was written by *Rethna Pulikkoonattu*, *Etienne Perron* and *Suhas
Diggavi*; it builds on ITIP by *Raymond W. Yeung* and *Ying-On Yan*. The
C++ fork Citip, and the updated modular c++ oxitip developed by *Thomas
Gläßle* and *Nivedita Rethnakar* et. al.

## License

GPL-3.0-or-later; see [LICENSE](LICENSE).
