```@meta
CurrentModule = Xitip
```

# Proofs and counterexamples

[`prove`](@ref) answers `true` or `false`. [`explain`](@ref) answers with a
[`Result`](@ref), which carries the reason: a [`Proof`](@ref) for each part of a
true statement (an equality has two, one per direction), or a single
[`Counterexample`](@ref).

Both kinds of certificate are verified in exact rational arithmetic before they
are returned, so a printed proof is not a plausible-looking summary of a
floating point computation: it is the object that was checked.

## Proofs

A proof writes the statement as a non-negative combination of basic
inequalities and constraints:

```@example proofs
using Xitip

result = explain("H(X,Y,Z) <= H(X,Y) + H(Z)")
```

```@example proofs
proof = only(result.certificates)
proof.terms
```

### Step by step

[`print_proof`](@ref) shows the same proof as a chain of equalities. Each line
splits one non-negative quantity off the expression; the bracket holds what is
still to account for, and the last line has nothing left:

```@example proofs
print_proof(result)
```

Reading it:

* `E` is the statement written as entropies, with everything moved to one side.
  Where `E` is a single information quantity, that name is shown as well — here
  `I(X,Y;Z)`.
* Each chain line is an identity, not an assumption: the terms so far plus the
  bracket always equal `E`.
* The list below the chain gives the entropy form of every term, so each line
  can be checked by hand without expanding definitions.
* The last chain line is the conclusion: `E` is a sum of non-negative
  quantities.

A remainder that happens to be a single quantity is named, which is what turns
`H(Y) + H(Z) - H(Y,Z)` into `I(Y;Z)` above. The shapes recognised are `H(A)`,
`H(A|B)`, `I(A;B)` and `I(A;B|C)`, including positive multiples of them.

### Constraints in a proof

Constraints appear as `C1`, `C2`, ... in the chain, with their own text beside
their entropy form:

```@example proofs
print_proof(explain("I(X;Z) <= I(X;Y)", "X/Y/Z"))
```

A statement can imply several relations — a Markov chain implies one per link —
so a term reads "from constraint 1" rather than "constraint 1". An equality
constraint used in the other direction is marked "reversed".

A constraint is not non-negative for any obvious reason, so the list says why
it is. Here `C1` is minus a conditional mutual information, which is
non-negative only because the Markov chain forces that information to zero:

```
C1 = H(X) - H(W,X) - H(X,Y) + H(W,X,Y)  =  -I(W;Y|X)  = 0
```

A constraint written as an inequality is simply `>= 0`, and an elemental
inequality is non-negative by definition, so neither needs more.

### LaTeX

[`latex`](@ref) writes a proof for a paper. By default it is the identity
alone, which is usually what a paper wants:

```@example proofs
latex(result)
```

`steps=true` gives the full chain, and `expand=true` adds the entropy form of
every term (constraints are always listed, since the chain would otherwise
refer to something invisible):

```@example proofs
latex(result; steps=true, expand=true)
```

The output needs `amsmath`. Long expressions are wrapped to stay inside the
page margin; the package's own test suite compiles the output with `pdflatex`
where a TeX installation is available and fails on an overfull line.

[`latex_string`](@ref) returns the same text as a `String`.

## Counterexamples

When a statement cannot be proven, the certificate is a counterexample: entropy
values satisfying every basic inequality and every constraint, but not the
statement.

```@example proofs
explain("I(X;Y|Z) <= I(X;Y)")
```

The values are exact rationals, rounded to small numbers where possible, and
can be read off the [`Counterexample`](@ref):

```@example proofs
counter = only(explain("H(X) <= H(Y)").certificates)
counter.entropies        # indexed by subset bitmask: 1 = X, 2 = Y, 3 = X,Y
```

The printed counterexample ends with the same reading: what each side of the
statement comes to there, and how every quantity gets its value out of the
entropies above it.

### Reading the numbers

The values are **entropies in bits**, not probabilities: they are bounded by the
logarithm of the alphabet size, not by 1. `H(X) = 6` describes a variable with
up to 64 equally likely values, and `H(X,Y,Z) = 13` a triple with up to 8192.

`direction = true` marks the case where the values are not a point but a
direction: the statement has no constant term, so every positive multiple of
the values fails in the same way, and the small integers printed are just the
most readable representative. Dividing by the largest of them is equally
valid:

```@example proofs
table = entropy_table(explain("I(X;Y|Z) <= I(X;Y)"))
peak = maximum(last, table)
[k => Float64(v // peak) for (k, v) in table]
```

What matters is the relations between them. For the table above,

```math
I(X;Y) = H(X) + H(Y) - H(X,Y), \qquad
I(X;Y \mid Z) = H(X,Z) + H(Y,Z) - H(Z) - H(X,Y,Z),
```

and the second is the larger, which is why `I(X;Y|Z) <= I(X;Y)` fails.
Conditioning really can raise mutual information, and it does so in an
everyday distribution: let `X` and `Y` be independent fair bits and `Z = X`
xor `Y`. Then

```@example proofs
prove("I(X;Y|Z) <= I(X;Y)", "I(X;Y) = 0", "H(Z|X,Y) = 0", "H(X|Y,Z) = 0")
```

is still not provable, because those constraints describe exactly that
distribution, where `I(X;Y) = 0` while `I(X;Y|Z) = 1` bit.

!!! note "A counterexample is a polymatroid, not necessarily a distribution"
    Beyond three variables, not every vector satisfying the basic inequalities
    comes from an actual probability distribution. A counterexample therefore
    shows that the statement does not follow from the basic inequalities — it
    does not show the statement is false. The Zhang–Yeung inequality is true,
    yet correctly reported as not provable here.

## Results without a certificate

If the exact simplex fallback had to decide (which the test suite has never
observed over thousands of random problems), the verdict stands but
`certificates` is empty:

```@example proofs
explain("H(X,Y) <= H(X) + H(Y)"; method=:simplex)
```
