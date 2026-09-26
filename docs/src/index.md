```@meta
CurrentModule = Xitip
```

# Xitip.jl

Information Theoretic Inequality Prover in pure Julia.

Xitip.jl decides whether an expression over entropies and mutual informations of
discrete random variables follows from the basic properties of Shannon entropy,
optionally under constraints such as Markov chains, independence or functional
dependence.

It is a reimplementation of [Xitip](http://xitip.epfl.ch/) / Citip / ITIP that
needs only Julia's standard library: parser, prover and solvers are all in this
package. Two things set it apart from those tools:

* **Every answer is exact.** The verdict never depends on a floating point
  tolerance. Coefficients are exact rationals, so `0.1` means exactly 1/10.
* **Every answer comes with a certificate**, verified in exact rational
  arithmetic: a [`Proof`](@ref) that writes the expression as a non-negative
  combination of basic inequalities — printable as a step-by-step derivation or
  as LaTeX — or a [`Counterexample`](@ref) that satisfies every basic inequality
  and constraint but not the expression.

## Installation

Xitip.jl is **not in the General registry**, so `Pkg.add("Xitip")` will not
find it. Install it from the repository instead:

```julia
julia> using Pkg; Pkg.add(url="https://github.com/geekymode/Xitip.jl")
```

or, in the package REPL — press `]` from the Julia prompt:

```
pkg> add https://github.com/geekymode/Xitip.jl
```

`rev` pins a branch, tag or commit, which is worth doing while the package is
unregistered and `main` can move:

```julia
julia> Pkg.add(url="https://github.com/geekymode/Xitip.jl", rev="main")
```

Then `using Xitip; prove("I(X;Y) >= 0")` should answer `true`. There are no
dependencies beyond the standard library, so nothing else is pulled in.

### Plotting (optional)

The figures come from a package extension, which loads itself once the
plotting packages are present. They are not installed with Xitip:

```julia
julia> Pkg.add(["CairoMakie", "GraphMakie", "Graphs", "NetworkLayout"])

julia> using Xitip, CairoMakie, GraphMakie, Graphs, NetworkLayout
```

Until they are loaded the plotting functions exist but raise an error saying
which packages to add. The [Illustrations](@ref) page shows what they draw.

### The command line tool, and working on the package

`bin/xitip` lives in the repository rather than in the installed package, so
for that — or to make changes — clone and `develop` instead:

```console
$ git clone https://github.com/geekymode/Xitip.jl
$ cd Xitip.jl
$ julia --project=. -e 'using Pkg; Pkg.instantiate()'
$ bin/xitip 'I(X;Y|Z) <= I(X;Y)'
```

```julia
julia> using Pkg; Pkg.develop(path="/path/to/Xitip.jl")
```

### Requirements

`Project.toml` declares Julia 1.9 and later, that being the oldest release
with package extensions, which the plotting support is built on. CI covers
1.9, 1.10 and the current release on Linux, macOS and Windows.

## Quick start

```@example quick
using Xitip

prove("I(X;Y|Z) <= I(X;Y)")          # not a Shannon-type inequality
```

```@example quick
prove("I(X;Y|Z) <= I(X;Y)", "H(Z) = 0")    # with a constraint
```

The first expression is the statement to prove; every later one is a
constraint. [`explain`](@ref) returns the same verdict together with its
certificate:

```@example quick
explain("H(X,Y) <= H(X) + H(Y)")
```

[`print_proof`](@ref) shows the same proof as a derivation, one non-negative
quantity at a time:

```@example quick
print_proof(explain("2 H(X,Y,Z) <= H(X,Y) + H(Y,Z) + H(X,Z)"))
```

and [`latex`](@ref) writes it for a paper:

```@example quick
latex(explain("H(X,Y,Z) <= H(X,Y) + H(Z)"))
```

When a statement cannot be proven, the certificate is a counterexample: entropy
values that satisfy every basic inequality and constraint but not the statement.

```@example quick
explain("H(X) <= H(Y)")
```

## Where to go next

* [Expression syntax](@ref) — what you can write.
* [Proofs and counterexamples](@ref) — what comes back, and how to print it.
* [Examples](@ref) — worked examples, from one-liners to eight variables with
  fourteen constraints.
* [Illustrations](@ref) — proofs as trees, the chain rule, the constraints of
  a problem as a graph, and a counterexample as a chart (needs CairoMakie and
  GraphMakie).
* [Command line](@ref) — `bin/xitip`.
* [How it works](@ref) — the algorithm, its cost and its limits.
* [API reference](@ref) — every exported function.

## Credits

Xitip was written by *Rethna Pulikkoonattu*, *Etienne Perron* and *Suhas
Diggavi*; it builds on ITIP by *Raymond W. Yeung* and *Ying-On Yan*. The C++
fork Citip, and the updated modular c++ oxitip developed by *Thomas Gläßle* and
*Nivedita Rethnakar* et. al.

## License

GPL-3.0-or-later.
