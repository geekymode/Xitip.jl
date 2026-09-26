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
inside it. Proving a statement is asking whether a half space contains that
cone; a counterexample is a point of the cone outside the half space.

### The cone for two variables

For two variables the space is three-dimensional — ``H(X)``, ``H(Y)``,
``H(X,Y)`` — so the cone can be drawn exactly:

```@example plots
plot_entropy_cone(; outside=(0.8, 0.5, 0.6))
```

**Why it is a cone.** The three elemental inequalities

```math
H(X \mid Y) \ge 0, \qquad H(Y \mid X) \ge 0, \qquad I(X;Y) \ge 0
```

are all homogeneous — no constant term — so if a point satisfies them, so does
every positive multiple of it. The region is therefore closed under scaling:
it is an infinite cone with its apex at the origin, where all three entropies
vanish. The upper panel truncates it at ``H(X,Y) = 1`` purely so there is
something finite to draw.

**Its three facets** are the three inequalities, one each, drawn as the three
flat faces. A point on a facet is a distribution making that inequality tight:
on ``H(X \mid Y) = 0``, ``X`` is a function of ``Y``; on ``I(X;Y) = 0``, the
two are independent.

**Its three extreme rays** are where two facets meet, and each is a
recognisable distribution — ``X`` constant, ``Y`` constant, and ``X = Y``.
Every point of the cone is a non-negative combination of those three, which is
[`cone_rays`](@ref). That is the geometric form of the same fact the prover
uses: a Shannon-type inequality is one that holds at all three rays.

**The slice is the clean view.** The lower panel is the cone cut at
``H(X,Y) = 1``, i.e. every point divided by its joint entropy. Scaling is the
one direction that carries no information, so throwing it away loses nothing
and turns the cone into a plain triangle with the three rays as its corners
and the three facets as its edges. If the three-dimensional picture is hard to
read, read the triangle instead — it is the same object with a degree of
freedom removed. `azimuth` and `elevation` rotate the upper panel if a
different angle suits, and `slice=false` drops the lower one.

The red cross is `(0.8, 0.5, 0.6)`, which is not an entropy vector of
anything: it claims ``H(X,Y) = 0.6`` while ``H(X) = 0.8``, so
``H(X \mid Y) < 0``. In the triangle it lands outside the right edge, which is
the facet it breaks.

### Where random distributions land

The green points are entropy vectors of distributions drawn at random, and
they are worth a second look, because which distributions you draw decides
what you see:

```@example plots
using Random: MersenneTwister
names = ["X", "Y"]
fractions(style) = begin
    cloud = entropic_samples(2; count=2000, alphabet=3, style=style,
                             rng=MersenneTwister(1))
    (dependent = count(j -> evaluate("I(X;Y)", names, cloud[:, j]) > 0.5,
                       axes(cloud, 2)) / 2000,
     lopsided = count(j -> cloud[1, j] < 0.5, axes(cloud, 2)) / 2000)
end
(structured = fractions(:structured), random = fractions(:random))
```

Drawing the joint distribution outright — `style=:random` — gives something
close to independent almost every time, so the samples pile up against the
``I(X;Y) = 0`` edge and leave most of the triangle empty. This is a fact about
the sampler, not about the cone: the rest of the triangle is perfectly
reachable, it is just that a distribution picked with no structure rarely has
much mutual information.

So [`entropic_samples`](@ref) defaults to `style=:structured`, which gives each
variable a parent among the earlier ones and a noise level, sweeping from "one
is a function of the other" to "independent" and reaching across the cone. Pass
`style=:random` to see the pile-up for yourself.

### Does the sampling cover everything?

No — and it is worth being precise about why, because two different things
are going on.

A finite sample never covers a continuum, so the question is really whether
the samples *spread* over the cone or bunch in part of it. Cut the triangle
into a 40×40 grid and count how many of its 820 cells hold at least one
sample:

| samples | cells reached |
|--------:|--------------:|
| 400     | 16 % |
| 4 000   | 43 % |
| 40 000  | 67 % |
| 200 000 | 77 % |

More samples do fill it in, but slowly: five hundred times as many samples
buys 16 % → 77 %. The sampler's measure is very uneven, so the thin regions
fill at the rate of their probability, not at the rate of the sample count.

The second thing is a real question about the cone rather than the sampler:
**is every point of the triangle the entropy vector of some distribution?**
For two variables the answer is yes, and there is a construction. Take
independent `U`, `V`, `W` and set

```math
X = (U, V), \qquad Y = (U, W),
```

which gives ``I(X;Y) = H(U)``, ``H(X \mid Y) = H(V)`` and
``H(Y \mid X) = H(W)``. The three elemental inequalities say precisely that
those three entropies are non-negative, so *any* point of the cone can be
built this way — pick `U`, `V`, `W` with the required entropies and you are
done. [`entropic_distribution`](@ref) does it:

```@example plots
h = [0.8, 0.5, 1.0]                    # a point of the cone
p, alphabet = entropic_distribution(h)
entropy_vector(p, 2, alphabet)         # exactly the point asked for
```

So the Shannon cone for two variables is exactly the set of entropy vectors
— nothing drawn inside it is unreachable. (This is special to two and three
variables. From four on, the entropic vectors are a strict subset of the
cone, which is what the note below is about.)

That construction also gives a sampler that covers the cone evenly, by
working backwards: pick the point first, then build a distribution for it.
It reaches 99.5 % of the grid cells at 4 000 samples and all of them at
40 000:

```@example plots
plot_entropy_cone(; style=:uniform, samples=1200, slice=true)
```

This is the picture of the cone itself. The default `:structured` picture is
a picture of *where distributions land* when you draw them, which is a
different and also useful thing to see — the bunching along the
``I(X;Y) = 0`` edge is telling you that independence is what you get by
accident.

### More than two variables

Past two variables the space is too big to draw — seven dimensions for three,
fifteen for four — so [`plot_entropy_space`](@ref) samples entropy vectors,
normalises them by their joint entropy so they land on one slice, and projects
the result onto its two principal directions. Colouring by an expression shows
where in the cloud that expression changes sign:

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
