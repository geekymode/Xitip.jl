```@meta
CurrentModule = Xitip
```

# Examples

Every output on this page is produced when the documentation is built, so it is
what the current version actually prints. The figures come from the plotting
utilities described on the [Illustrations](@ref) page:

```@example ex
using Xitip
using CairoMakie, GraphMakie, Graphs, NetworkLayout
CairoMakie.activate!(type="png") # hide
nothing # hide
```

## Basic Shannon inequalities

```@example ex
[prove("H(X) >= 0"),
 prove("I(X;Y) >= 0"),
 prove("H(X|Y) <= H(X)"),
 prove("H(X,Y) <= H(X) + H(Y)"),          # subadditivity
 prove("H(X,Y) = H(X) + H(Y|X)"),         # chain rule
 prove("I(X;Y,Z) = I(X;Y) + I(X;Z|Y)"),   # chain rule for mutual information
 prove("2 H(X,Y,Z) <= H(X,Y) + H(Y,Z) + H(X,Z)")]   # Han's inequality
```

Statements that do not follow from the basic inequalities:

```@example ex
[prove("H(X) >= 1"),
 prove("H(X) <= H(Y)"),
 prove("I(X;Y|Z) <= I(X;Y)"),
 prove("I(X;Y;Z) >= 0"),        # multivariate mutual information can be negative
 prove("H(X,Y) = H(X) + H(Y)")]
```

## Constraints

```@example ex
[prove("I(X;Y|Z) <= I(X;Y)", "H(Z) = 0"),
 prove("I(X;Z) <= I(X;Y)", "X/Y/Z"),          # data processing
 prove("I(A;D) <= I(B;C)", "A/B/C/D"),
 prove("I(X;Y) = 0", "X.Y"),                  # mutual independence
 prove("H(X,Y) = H(Y)", "X:Y"),               # X is a function of Y
 prove("X:Y,Z", "H(X|Y,Z) = 0")]              # ... and the other way round
```

Constraints that contradict each other are an error, since anything at all
would follow from them:

```@repl ex
using Xitip # hide
prove("H(X) >= 0", "H(X) = 1", "H(X) = 2")
```

## Exact arithmetic

Coefficients are exact rationals, so decimals behave:

```@example ex
[prove("0.1 H(X) + 0.2 H(X) >= 0.3 H(X)"),   # 0.1 + 0.2 == 0.3 exactly here
 prove("0.1 H(X) + 0.2 H(X) = 0.3 H(X)"),
 prove("H(X) >= 1.00000001", "H(X) = 1.00000001"),
 prove("H(X) >= 1.00000001", "H(X) = 1")]
```

## Counting variables

[`count_variables`](@ref) counts the distinct random variables in all
statements, which is what `oXitipLen` did:

```@example ex
count_variables("I(X;Y|Z) <= I(X;Y)", "H(W) = 0")
```

## The chain rule as a tree

```@example ex
plot_chain_rule(["X", "Y", "Z", "W"])
```

## A step-by-step proof

```@example ex
print_proof(explain("2 H(X,Y,Z) <= H(X,Y) + H(Y,Z) + H(X,Z)"))
```

The same derivation as a tree: each branch to the left is a non-negative term,
and the line down the right is what is still to account for.

```@example ex
plot_proof_tree(explain("2 H(X,Y,Z) <= H(X,Y) + H(Y,Z) + H(X,Z)"))
```

## Data processing over a four-variable Markov chain

`I(W;Z) <= I(X;Y)` given `W/X/Y/Z`. The chain implies one relation per link, so
two of them appear, as `C1` and `C2`:

```@example ex
print_proof(explain("I(W;Z) <= I(X;Y)", "W/X/Y/Z"))
```

The constraint itself, drawn over the variables:

```@example ex
plot_constraints("I(W;Z) <= I(X;Y)", "W/X/Y/Z")
```

and the proof as a tree, with the two relations the chain implies in their own
colour:

```@example ex
plot_proof_tree(explain("I(W;Z) <= I(X;Y)", "W/X/Y/Z"))
```

The same proof as LaTeX:

```@example ex
latex(explain("I(W;Z) <= I(X;Y)", "W/X/Y/Z"))
```

## Eight variables with fourteen constraints

A statement over `A, B, C, D, W, X, Y, Z`:

```math
I(B; D, X, Z) \le I(W; A, B, C, D)
```

under constraints tying the four "inner" variables to the four "outer" ones.
This is the largest kind of problem the package is comfortable with: 8
variables means 255 dimensions and 1800 basic inequalities.

```@example ex
statement = "I(B;D,X,Z) <= I(W;A,B,C,D)"

constraints = [
    "I(W;A,B,C,D) = I(X;A,B,W)",
    "I(W;A,B,C,D) = I(Y;B,C,X)",
    "I(W;A,B,C,D) = I(Z;C,D,Y)",
    "I(A;B,C,D,Z) = I(B;D,X,Z)",
    "I(B;A,D,W,Z) = I(B;D,X,Z)",
    "I(C;A,D,W,Z) = I(B;D,X,Z)",
    "I(D;A,B,C,Y) = I(B;D,X,Z)",
    "I(C;A,W,Y) = I(B;D,X,Z)",
    "I(B;A) = 0",
    "I(C;A,B) = 0",
    "I(D;A,B,C) = 0",
    "I(X;C,D|A,B,W) = 0",
    "I(Y;A,D,W|B,C,X) = 0",
    "I(Z;A,B,W,X|C,D,Y) = 0",
]

prove([statement; constraints])
```

The proof uses nine terms, every multiplier equal to one:

```@example ex
print_proof(explain([statement; constraints]))
```

Only four of the fourteen constraints are needed — numbers 2, 7, 11 and 13,
the ones appearing as `C1` to `C4` above:

```@example ex
needed = [constraints[2], constraints[7], constraints[11], constraints[13]]
prove([statement; needed])
```

None of those four is redundant: dropping any one of them leaves a statement
that no longer follows from the basic inequalities. (Each of those queries
takes about 12 seconds, so they are not run while this page is built.)

```julia
julia> [prove([statement; needed[setdiff(1:4, i)]]) for i in 1:4]
4-element Vector{Bool}:
 0
 0
 0
 0
```

The whole derivation as a tree. `C1` to `C4` are the four constraints it
needs, the green leaves are elemental inequalities, and the line down the
middle is the remainder shrinking step by step:

```@example ex
plot_proof_tree(explain([statement; constraints]); size=(1500, 820), fontsize=9)
```

and as LaTeX:

```@example ex
latex(explain([statement; constraints]))
```

## Non-Shannon-type inequalities

Two famous statements that the basic inequalities cannot settle. The Ingleton
expression is not always non-negative for entropies, while the Zhang–Yeung
inequality is true but needs more than Shannon-type reasoning, so both come
back as "not provable":

```@example ex
[prove("I(A;B) <= I(A;B|C) + I(A;B|D) + I(C;D)"),                      # Ingleton
 prove("2I(C;D) <= I(A;B) + I(A;C,D) + 3I(C;D|A) + I(C;D|B)")]         # Zhang-Yeung
```

The counterexample for Ingleton is the familiar Vámos-like polymatroid:

```@example ex
explain("I(A;B) <= I(A;B|C) + I(A;B|D) + I(C;D)")
```

## Degenerate statements

```@example ex
[prove("1 >= 0"),
 prove("0 >= 1"),
 prove("H(X) - H(X) = 0"),
 prove("H(X|X) = 0"),
 prove("I(X;X) = H(X)")]
```

## From the command line

The same problems through `bin/xitip` (see [Command line](@ref)):

```console
$ bin/xitip 'I(X;Y|Z) <= I(X;Y)' 'H(Z) = 0'
The information expression is TRUE.

$ bin/xitip --steps 'H(X,Y,Z) <= H(X,Y) + H(Z)'
Proof of  E >= 0  where  E = H(Z) + H(X,Y) - H(X,Y,Z)  =  I(X,Y;Z)

  E  =  H(Z) + H(X,Y) - H(X,Y,Z)
     =  I(X;Z|Y)  +  [ H(Y) + H(Z) - H(Y,Z) ]
     =  I(X;Z|Y)  +  I(Y;Z)

  where every term is non-negative:
    I(X;Z|Y)  =  -H(Y) + H(X,Y) + H(Y,Z) - H(X,Y,Z)  >= 0
    I(Y;Z)    =  H(Y) + H(Z) - H(Y,Z)                >= 0

  so E is a sum of non-negative terms, hence E >= 0.

$ bin/xitip --latex 'H(X,Y,Z) <= H(X,Y) + H(Z)'
\begin{align*}
  E &= H(Z) + H(X,Y) - H(X,Y,Z) \\
    &= I(X ; Z \mid Y) + I(Y ; Z) \;\ge\; 0
\end{align*}

$ bin/xitip --count 'I(X;Y|Z) <= I(X;Y)'
3

$ echo 'I(X;Y|Z) <= I(X;Y)' | bin/xitip -
The information expression is either:
    1. FALSE, or
    2. a non-Shannon type inequality
```
