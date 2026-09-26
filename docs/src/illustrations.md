```@meta
CurrentModule = Xitip
```

# Illustrations

A proof is a decomposition, and a decomposition is a tree: the expression
splits into a non-negative term and a remainder, which splits again. These
utilities turn that structure, and the constraints of a problem, into pictures.

Drawing needs [CairoMakie](https://docs.makie.org) and
[GraphMakie](https://graph.makie.org); the package itself stays free of
dependencies and only gains the plotting methods once they are loaded:

```@example plots
using Xitip
using CairoMakie, GraphMakie, Graphs, NetworkLayout
CairoMakie.activate!(type="png") # hide
nothing # hide
```

The structures themselves ([`proof_tree`](@ref), [`chain_rule_tree`](@ref),
[`constraint_graph`](@ref)) are plain data and need nothing extra.

## The tree behind a proof

[`plot_proof_tree`](@ref) draws the derivation. The expression sits at the
root, each non-negative term branches off to the left, and what is still to
account for carries on down to the right, until nothing is left:

```@example plots
plot_proof_tree(explain("2 H(X,Y,Z) <= H(X,Y) + H(Y,Z) + H(X,Z)"))
```

Reading it: Han's inequality for three variables is `I(X;Y|Z)` plus
`I(X,Y;Z)`, and that second piece is in turn `I(X;Z|Y)` plus `I(Y;Z)`.

Terms coming from your own constraints are drawn in their own colour and
labelled `C1`, `C2`, ..., with their entropy form and the reason they are
non-negative. `C1` below is minus a conditional mutual information, which the
Markov chain forces to zero:

```@example plots
plot_proof_tree(explain("I(W;Z) <= I(X;Y)", "W/X/Y/Z"))
```

Without a plotting package loaded, or for a statement with no proof, the same
call raises a [`XitipError`](@ref) saying so. The text form is always
available:

```@example plots
proof_tree(explain("I(W;Z) <= I(X;Y)", "W/X/Y/Z"))
```

`detail=true` writes the entropy form under each label, which is worth it for
small trees and unreadable for large ones:

```@example plots
plot_proof_tree(explain("H(X,Y,Z) <= H(X,Y) + H(Z)"); detail=true)
```

## The chain rule

[`plot_chain_rule`](@ref) draws the expansion

```math
H(X_1, \ldots, X_n) = H(X_1) + H(X_2 \mid X_1) + \cdots +
                      H(X_n \mid X_1, \ldots, X_{n-1})
```

as the tree it is, each remainder conditioning on one more variable:

```@example plots
plot_chain_rule(["X", "Y", "Z", "W"])
```

Everything can be conditioned on a fixed set from the start:

```@example plots
plot_chain_rule(["A", "B", "C"], ["S"])
```

## The constraints of a problem

[`plot_constraints`](@ref) draws the variables and the structural constraints
tying them together: a Markov chain as a path, mutual independence as dashed
links, and a functional dependence as an arrow from each argument to the
variable it determines.

```@example plots
plot_constraints("I(W;Z) <= I(X;Y)", "W/X/Y/Z")
```

```@example plots
plot_constraints("H(S) <= H(X,Y)", "S:X,Y", "X.Y", "Y/S/Z")
```

Constraints written as general relations (`I(X;Y|Z) = 0` and the like) have no
natural edge, so they are left out; [`constraint_graph`](@ref) returns exactly
what is drawn.

## A counterexample

When a statement cannot be proven, the certificate is a set of entropy values
that satisfies every elemental inequality and constraint but not the statement.
[`plot_counterexample`](@ref) draws what the statement's own quantities come to
at those values, which is where the verdict comes from, and the entropies
behind them:

```@example plots
plot_counterexample(explain("I(X;Y|Z) <= I(X;Y)"))
```

The top panel is the statement, term by term: each bar is one quantity as
written, coloured by which side of the relation it sits on, and the dashed
lines are what the two sides add up to. The statement asks for the left line
to sit below the right one, and it does not.

Between the panels, each quantity is written out in entropies with the
counterexample's numbers put in, so the bars above and the bars below are
joined by arithmetic the reader can check:

```
I(A;B|C) = -H(C) + H(A,C) + H(B,C) - H(A,B,C) = -13 + 21 + 21 - 28 = 1
```

The structure of the entropies is often the point too. For the Ingleton
expression the singletons all agree, the pairs agree except for one, and the
triples agree again — the shape of the polymatroid that defeats it:

```@example plots
plot_counterexample(explain("I(A;B) <= I(A;B|C) + I(A;B|D) + I(C;D)"))
```

[`entropy_table`](@ref) returns the same numbers as exact rationals:

```@example plots
entropy_table(explain("I(X;Y|Z) <= I(X;Y)"))
```

## More of the same

A proof that leans on several constraints, over eight variables and ten levels
deep:

```@example plots
statement = "I(B;D,X,Z) <= I(W;A,B,C,D)"
constraints = ["I(W;A,B,C,D) = I(Y;B,C,X)", "I(D;A,B,C,Y) = I(B;D,X,Z)",
               "I(D;A,B,C) = 0", "I(Y;A,D,W|B,C,X) = 0"]
plot_proof_tree(explain([statement; constraints]))
```

Han's inequality for three variables, whose proof is a chain of three terms:

```@example plots
plot_proof_tree(explain("2 H(X,Y,Z) <= H(X,Y) + H(Y,Z) + H(X,Z)"))
```

## The geometry behind all of this

An entropy vector of ``n`` random variables is a point of ``\mathbb{R}^{2^n-1}``,
one coordinate per non-empty subset. The elemental inequalities cut a cone out
of that space, and every vector that comes from an actual distribution lies
inside it.

For two variables the space is three-dimensional — ``H(X)``, ``H(Y)``,
``H(X,Y)`` — and the cone can be drawn exactly. It has one facet per elemental
inequality, and the three meet along three extreme rays, each of which is a
recognisable distribution:

```@example plots
plot_entropy_cone(; outside=(0.9, 0.9, 0.4))
```

The green points are entropy vectors of random distributions, which must lie
inside. The cross is `(0.9, 0.9, 0.4)`, which is not an entropy vector of
anything: it claims `H(X,Y) = 0.4` while `H(X) = 0.9`, so `H(Y|X) < 0`.

Past two variables the space is too big to draw — seven dimensions for three
variables, fifteen for four — so [`plot_entropy_space`](@ref) samples entropy
vectors, normalises them by their joint entropy so they land on one slice, and
projects the result onto its two principal directions. Colouring by an
expression shows where in the cloud that expression changes sign:

```@example plots
plot_entropy_space(3; color="I(X;Y;Z)")
```

The multivariate mutual information `I(X;Y;Z)` is negative over much of the
cloud, which is why `I(X;Y;Z) >= 0` is not provable.

!!! note "What the cloud is and is not"
    The points are entropic: each comes from a distribution. They do not fill
    the Shannon cone — sampling only reaches where the sampler goes — and past
    three variables the entropic vectors are a strict subset of the cone in any
    case. The picture is a view of where distributions land, not a drawing of
    the cone itself.

The pieces behind these are available on their own:
[`entropic_samples`](@ref) draws the vectors, [`entropy_vector`](@ref) takes
one distribution to its entropies, [`evaluate`](@ref) values an expression at a
point, and [`cone_rays`](@ref) gives the extreme rays for the cases small
enough to write down.

## Saving a figure

The figures are ordinary Makie figures, so they are saved the usual way, in
whatever format CairoMakie supports:

```julia
fig = plot_proof_tree(explain("H(X,Y,Z) <= H(X,Y) + H(Z)"))
save("proof.pdf", fig)     # or .png, .svg
```

The figure is sized from the labels it has to fit, so it is readable without
being asked. `size = (width, height)`, `title`, `fontsize` and `wrap` (how many
characters before a long expression is broken over lines) are there for when
the default does not suit the expression at hand.
