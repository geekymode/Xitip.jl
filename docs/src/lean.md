```@meta
CurrentModule = Xitip
```

# Formal proof in Lean

A proof from this package is already close to what a proof assistant wants.
It is not an argument in prose: it is the statement written as a
non-negative combination of inequalities, with exact rational multipliers,
verified in rational arithmetic before it is returned. Handing that to Lean
is a transcription rather than a search.

[`lean`](@ref) does the transcription.

```@example lean
using Xitip

print(lean("H(X,Y,Z) <= H(X,Y) + H(Z)"; imports = false))
```

`linarith` closes the goal because the combination it would have to find is
the one the certificate already contains.

## What this says, and what it does not

Being precise here matters more than the feature does.

The theorem says: **the statement follows from those particular inequalities
by linear arithmetic, and Lean has checked that it does.** If the export
dropped a term, mangled a coefficient or quietly weakened the goal, Lean
would reject it.

The theorem does **not** say the variables are entropies. `h_X_Y` is a plain
real number, and each hypothesis is an assumption rather than a theorem. So
what is machine-checked is the part this package is responsible for — the
linear algebra over the elemental inequalities — and not the information
theory underneath it, which is assumed.

That split is deliberate. The arithmetic core is where a bug in *this*
package would show up, and it is the layer a machine can check without a
multi-gigabyte dependency. Closing the remaining gap needs a bridge, below.

## Checking it

`lean/verify.jl` generates a set of proofs and compiles them against any
Lean project that has Mathlib:

```console
$ git clone https://github.com/teorth/pfr.git
$ cd pfr && lake exe cache get && cd ..
$ julia --project=. lean/verify.jl pfr
sub       compiles
markov    compiles
han       compiles
identity  compiles
constant  compiles
four      compiles
rational  compiles
eight     compiles
control   rejected as it should be
```

Those cover constraints, rational coefficients, a constant term, an identity
that needs no assumptions at all, and an eight-variable statement.

The last line is the one that makes the rest mean something. A theorem can
compile for the wrong reason — if the goal were vacuous, or a hypothesis
unnecessary, Lean would still accept it. So the harness takes a proof, drops
one hypothesis, and checks that Lean then **rejects** it. Compiling is only
evidence when not compiling was possible.

## The bridge, which is not written

To say the variables are entropies, each `h_α` has to become the entropy of
a tuple of random variables, and each hypothesis has to be discharged from a
library lemma rather than assumed:

```lean
have e1 : 0 ≤ H[⟨X, Z⟩] + H[⟨Y, Z⟩] - H[Z] - H[⟨X, Y, Z⟩] :=
  by have := condMutualInfo_nonneg X Y Z ; ...
```

The lemmas exist. Core Mathlib carries only binary entropy
(`Mathlib.Analysis.SpecialFunctions.BinaryEntropy`), but Terence Tao's
[PFR project](https://github.com/teorth/pfr) has the multivariate API in the
`ProbabilityTheory` namespace — `entropy`, `condEntropy`, `mutualInfo`,
`condMutualInfo`, with `mutualInfo_nonneg` and `condMutualInfo_nonneg`,
which are exactly the elemental inequalities. The newer
[LeanInfoTheory](https://github.com/serhatemrecoban/LeanInfoTheory) is
another candidate.

The work is not the nonnegativity lemmas but the bookkeeping around them.
This package indexes entropies by subset, so `H(X,Y)` and `H(Y,X)` are the
same coordinate; in Lean `H[⟨X, Y⟩]` and `H[⟨Y, X⟩]` are different terms
that happen to be equal, and an associativity choice has to be made for
three or more. A faithful bridge needs a canonical tuple order and the
rewriting to reach it, per arity, before `linarith` sees one consistent set
of atoms.

Until that exists, the honest description of [`lean`](@ref) is the one
above: it exports the arithmetic, and the arithmetic is checked.

## Limits

Only a provable statement can be exported — there is nothing to transcribe
otherwise, and [`lean`](@ref) raises rather than emitting something
misleading:

```@example lean
try
    lean("I(X;Y|Z) <= I(X;Y)")
catch e
    println(e.msg)
end
```

A verdict that came from the simplex fallback carries no certificate, so it
cannot be exported either. An equality exports as two theorems, one per
direction.
