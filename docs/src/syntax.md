```@meta
CurrentModule = Xitip
```

# Expression syntax

Each statement is one string. The first one passed to [`prove`](@ref) or
[`explain`](@ref) is the statement to be proven; the rest are constraints.

## Quantities

| Syntax | Meaning |
|:--|:--|
| `H(X)` | entropy |
| `H(X,Y)` | joint entropy |
| `H(X,Y\|Z,W)` | conditional entropy |
| `I(X;Y)` | mutual information |
| `I(X;Y\|Z)` | conditional mutual information |
| `I(X;Y;Z)` | multivariate mutual information (can be negative) |
| `I(X,Y;Z)` | sets on either side |

`:` works as a separator too, so `I(X:Y)` is `I(X;Y)`.

Variable names match `[A-Za-z][A-Za-z0-9_]*`. `H` and `I` are ordinary variable
names unless followed by `(`, so `H(H1,I1)` is the joint entropy of two
variables called `H1` and `I1`.

## Relations

A statement is a linear combination of quantities on each side, related by
`<=`, `>=` or `=` (`==` is accepted as well):

```julia
"2 H(X) - 0.5 I(X;Y) >= 1"
"H(X,Y) = H(X) + H(Y|X)"
```

Coefficients may be integers or decimals; both are read as exact rationals, so
`0.1` is exactly 1/10. Constants are allowed on either side.

An equality statement is proven in both directions, and an equality constraint
may be used in both directions.

## Shorthands

| Syntax | Meaning |
|:--|:--|
| `X/Y/Z` | Markov chain `X → Y → Z`; any length, e.g. `W/X/Y/Z` |
| `X/Y,Z/W` | the links may be sets |
| `X.Y.Z` | mutual independence |
| `X:Y,Z` | `X` is a function of `Y,Z` |

A Markov chain of length ``n`` implies ``n-2`` conditional independence
relations, one per link; a proof refers to each of them as "from constraint
``k``".

## Comments and blank lines

`#` starts a comment, and blank lines are ignored:

```@example syntax
using Xitip
prove("H(X) >= 0   # entropy is non-negative")
```

```@example syntax
prove(["", "# the statement:", "I(X;Y) >= 0"])
```

Statements can also be passed as a vector of strings, which is what the command
line does when reading from standard input.

## Errors

Invalid input raises a [`SyntaxError`](@ref) that points at the problem:

```@repl syntax
using Xitip # hide
prove("I(X;;Y) >= 0")
```

Contradictory constraints raise a [`XitipError`](@ref), because under them
everything would be vacuously true:

```@repl syntax
prove("H(X) >= 0", "H(X) = 1", "H(X) = 2")
```

The same error reports a problem that is too large: at most 30 variables, and
in practice far fewer (see [How it works](@ref)).
