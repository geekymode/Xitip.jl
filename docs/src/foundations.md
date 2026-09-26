```@meta
CurrentModule = Xitip
```

# Xitip foundations

This page is the theory the package implements: what an information measure
is, what it means for an information inequality to be true, which
inequalities a machine can decide, and how the decision is actually made.
Everything here is reflected in the code, and the cross references point at
the functions that carry it out.

## Information measures

Let ``X_1, \dots, X_n`` be discrete random variables on a common probability
space. The **entropy** of a subset ``X_\alpha = (X_i : i \in \alpha)`` is

```math
H(X_\alpha) = -\sum_{x} p_\alpha(x) \log_2 p_\alpha(x),
```

measured in bits. Everything else the package understands is a linear
combination of these. Writing ``\alpha, \beta, \gamma`` for subsets of
``\{1, \dots, n\}``:

```math
\begin{aligned}
H(X_\alpha \mid X_\beta) &= H(X_{\alpha \cup \beta}) - H(X_\beta), \\[2pt]
I(X_\alpha ; X_\beta) &= H(X_\alpha) + H(X_\beta) - H(X_{\alpha \cup \beta}), \\[2pt]
I(X_\alpha ; X_\beta \mid X_\gamma) &= H(X_{\alpha \cup \gamma}) + H(X_{\beta \cup \gamma})
    - H(X_\gamma) - H(X_{\alpha \cup \beta \cup \gamma}).
\end{aligned}
```

Because each is a fixed linear combination of joint entropies, a statement
about conditional entropies and mutual informations is a statement about
joint entropies alone. That is the first reduction the package makes, and
`Xitip.expression_coefficients` is where it happens: an expression
becomes a vector of coefficients indexed by subset.

### The entropy vector

Collect the entropies of all ``2^n - 1`` non-empty subsets into a single
point:

```math
h = \bigl( H(X_\alpha) \bigr)_{\emptyset \neq \alpha \subseteq \{1,\dots,n\}}
    \in \mathbb{R}^{2^n - 1}.
```

This is the **entropy vector** of the distribution, and it is the object the
whole package manipulates. [`entropy_vector`](@ref) computes it from a joint
distribution, and [`evaluate`](@ref) evaluates any expression at such a
point.

Subsets are indexed by bitmask throughout, so for three variables entry 1 is
``H(X)``, entry 2 is ``H(Y)``, entry 3 is ``H(X,Y)``, entry 4 is ``H(Z)``,
and so on to entry 7, ``H(X,Y,Z)``.

### The I-measure

There is a second coordinate system for the same information, due to Yeung:
treat each variable as a set ``\tilde X_i`` and each entropy as a measure of
a union,

```math
H(X_\alpha) = \mu^*\Bigl( \bigcup_{i \in \alpha} \tilde X_i \Bigr).
```

This determines a signed measure ``\mu^*`` on the ``2^n - 1`` atoms of the
Venn diagram, and the change of coordinates is invertible: the entropy
vector and the vector of atoms carry the same information.
[`imeasure`](@ref) performs it, and [`plot_imeasure`](@ref) draws the result.

The atoms are worth knowing because they make the inequalities legible.
Every atom is itself a conditional mutual information, and all but the ones
shared by three or more variables are non-negative. The exception is real:
for ``Z = X \oplus Y`` with ``X, Y`` independent fair bits,
``I(X;Y;Z) = -1`` bit.

## Information inequalities

An **information inequality** is a statement

```math
\sum_{\alpha} c_\alpha H(X_\alpha) \geq 0
```

for fixed real coefficients ``c_\alpha``, asserted for every distribution of
``X_1, \dots, X_n``. (An inequality with a constant term, or with the two
sides written separately, is rearranged into this form first; equalities are
two inequalities.) Geometrically it asserts that the entropy vector of every
distribution lies in a half space.

A **constrained** inequality asserts the same thing only for distributions
satisfying given linear equalities or inequalities — a Markov chain, an
independence, a functional dependence. The package's constraint syntax
compiles to exactly such linear relations; see
[Expression syntax](@ref).

### The entropic region

Which vectors ``h \in \mathbb{R}^{2^n-1}`` actually arise as entropy vectors?
The set of them is the **entropic region**

```math
\Gamma^*_n = \{ h : h \text{ is the entropy vector of some distribution} \},
```

and the true information inequalities are exactly the half spaces containing
``\Gamma^*_n``, or rather its closure ``\overline{\Gamma^*_n}``, which is a
convex cone. So "is this inequality true?" is the question "does this half
space contain ``\overline{\Gamma^*_n}``?"

That question is not known to be decidable, and ``\Gamma^*_n`` has no known
finite description for ``n \geq 4``. The package therefore answers a
different, decidable question, and is precise about which.

## Shannon-type inequalities

The **basic inequalities** are the non-negativity of the measures above:
``H(X_\alpha \mid X_\beta) \geq 0`` and
``I(X_\alpha ; X_\beta \mid X_\gamma) \geq 0`` for all subsets. They are all
consequences of a much smaller set.

A vector ``h`` satisfies all basic inequalities if and only if it satisfies
the **elemental inequalities**:

```math
\begin{aligned}
&H(X_i \mid X_{\{1,\dots,n\} \setminus \{i\}}) \geq 0
    && \text{for each } i, \\[2pt]
&I(X_i ; X_j \mid X_K) \geq 0
    && \text{for each } i < j \text{ and each } K \subseteq \{1,\dots,n\} \setminus \{i,j\}.
\end{aligned}
```

There are

```math
n + \binom{n}{2} 2^{\,n-2}
```

of them — 9 for three variables, 28 for four, 1800 for eight — and they are
minimal: none is implied by the others. `Xitip.elemental_inequalities`
generates exactly this list, and it is the only place the package encodes
information theory at all. Everything after it is linear algebra.

The region they cut out,

```math
\Gamma_n = \{ h : h \text{ satisfies every elemental inequality} \},
```

is a polyhedral cone, whose points are the **polymatroids**. Since every
entropy vector satisfies the basic inequalities,

```math
\overline{\Gamma^*_n} \subseteq \Gamma_n .
```

An inequality that holds on all of ``\Gamma_n`` is called **Shannon-type**,
and those are the ones this package decides.

### Where the two regions part

For ``n = 2`` and ``n = 3`` the containment is an equality (for ``n = 3``
after taking closures), so Shannon-type is the same as true. The
[Illustrations](@ref) page draws both cases exactly: for two variables
``\Gamma_2`` is a triangle in its slice, and every point of it really is an
entropy vector, built constructively by [`entropic_distribution`](@ref); for
three variables ``\Gamma_3`` is a triangular bipyramid.

From ``n = 4`` the containment is strict. The Zhang–Yeung inequality

```math
2 I(C;D) \leq I(A;B) + I(A;C,D) + 3 I(C;D \mid A) + I(C;D \mid B)
```

is true for all distributions but does not hold on all of ``\Gamma_4``, so it
is not Shannon-type and this package correctly reports it as not provable:

```@example foundations
using Xitip
prove("2I(C;D) <= I(A;B) + I(A;C,D) + 3I(C;D|A) + I(C;D|B)")
```

This is the one place where a "false" needs care. The package's answer means
*not provable from the basic inequalities*, and the counterexample it returns
is a polymatroid — a point of ``\Gamma_n`` — which for ``n \geq 4`` need not
come from any distribution.

## Foundations of the inequality checker

Fix the statement ``v \cdot h + v_0 \geq 0`` to be decided, and let
``g_1, \dots, g_m`` be the elemental inequalities together with the
constraints, each written as ``a_j \cdot h + b_j \geq 0``. An equality
constraint contributes both directions, which is why a proof may cite a
constraint "reversed".

### The reduction to a cone

The statement follows from the generators exactly when it is a non-negative
combination of them plus a non-negative slack. Adding one coordinate for the
constant term, write ``t = (v, v_0)`` and ``g_j = (a_j, b_j)``. Then

> the statement is provable ``\iff`` ``t`` lies in the convex cone generated
> by ``g_1, \dots, g_m`` and the slack direction ``(0, 1)``.

By **Farkas' lemma**, exactly one of these holds:

```math
\begin{aligned}
\textbf{provable:}\quad & t = \sum_j y_j g_j, \quad y \geq 0, \\[2pt]
\textbf{not provable:}\quad & \exists\, z: \; z \cdot g_j \leq 0 \ \forall j,
    \quad z \cdot t > 0 .
\end{aligned}
```

The two alternatives are precisely the two certificates the package returns.
The multipliers ``y`` are a [`Proof`](@ref): they say the statement is a
non-negative combination of things already known to be non-negative, which is
what [`print_proof`](@ref) narrates line by line. The separating vector ``z``
is a [`Counterexample`](@ref): it satisfies every generator yet violates the
statement.

### How the alternative is found

Both certificates come out of one computation. Projecting ``t`` onto the cone
by **non-negative least squares** gives the coefficients ``y`` if the
projection reaches ``t``, and otherwise the residual ``t - \sum_j y_j g_j``
is a separating vector ``z``. The package uses the Lawson–Hanson active set
method (`Xitip.nnls`) for this.

That computation is in floating point, so it decides nothing on its own. The
certificate it produces is then **verified in exact rational arithmetic**
(`Rational{BigInt}`): a proof is checked by recomputing the combination, a
counterexample by checking every generator and the statement itself. Only a
verified certificate is returned, which is why a printed proof is the object
that was checked rather than a summary of a numerical result.

Floating point can produce a nearly-correct certificate — a multiplier that
should be zero coming out at ``10^{-17}``, or a counterexample sitting a
hair outside the cone. The package repairs these by rounding and shifting
into the interior, then re-verifies. If verification still fails, an exact
two-phase simplex method decides instead. This fallback is exact and always
terminates, but is far slower on these highly degenerate problems, and over
thousands of randomised test cases the test suite has never observed it being
needed.

### What a proof looks like geometrically

For three variables the whole argument can be seen at once. Dropping the
coordinates that carry no shape, ``\Gamma_3`` becomes a bipyramid with five
vertices, and since it is the convex hull of those five points, a linear
statement holds on all of it exactly when it holds at each of them. A
provable statement is a half space containing the body, touching it at a
face; a statement that is not provable is a plane cutting through it, and the
vertices on the wrong side are the counterexamples. `plot_entropy_cone(3;
cut = "...")` draws exactly this, and the test suite checks that reading
against [`prove`](@ref).

### Complexity, and why it is usable

The number of generators grows as ``n + \binom{n}{2} 2^{n-2}``, so eight
variables means 1800 elemental inequalities in 255 dimensions. Linear
programs of that size arising here are highly degenerate, which is what makes
a generic exact simplex slow; the projection approach above avoids the issue,
and an eight-variable constrained problem is decided in about a tenth of a
second.

## Summary

| question | answer |
|---|---|
| What is decided | whether the statement follows from the basic inequalities, i.e. holds on all of ``\Gamma_n`` |
| What "true" means | a verified non-negative combination of elemental inequalities and constraints |
| What "false" means | a verified point of ``\Gamma_n`` satisfying the constraints but not the statement |
| When "false" means false | always for ``n \leq 3``; for ``n \geq 4`` it means "not Shannon-type", since ``\overline{\Gamma^*_n} \subsetneq \Gamma_n`` |
| Arithmetic | decided numerically, certified exactly in rationals |

## Further reading

* R. W. Yeung, *Information Theory and Network Coding*, Springer 2008 — the
  I-measure, the elemental inequalities, and the framework this package
  implements.
* R. W. Yeung, "A framework for linear information inequalities", *IEEE
  Trans. Inform. Theory* 43(6), 1997.
* Z. Zhang and R. W. Yeung, "On characterization of entropy function via
  information inequalities", *IEEE Trans. Inform. Theory* 44(4), 1998 — the
  first non-Shannon-type inequality.
* R. W. Yeung and Y.-O. Yan, ITIP; T. Gläßle, Citip — the earlier
  implementations this package follows.
