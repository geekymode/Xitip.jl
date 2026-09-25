#----------------------------------------------------------------------------
# Decompositions as trees and graphs
#----------------------------------------------------------------------------
#
# The structures here are plain data, so they can be built and tested without
# a plotting package. Drawing them needs CairoMakie, GraphMakie and Graphs,
# which a package extension adds methods for; see `plot_proof_tree`,
# `plot_chain_rule` and `plot_constraints`.

"""
    TreeNode

A node of a [`DecompositionTree`](@ref): `label` is the short form shown in
the picture, `detail` the entropy form behind it (may be empty), `kind` is
one of `:expression`, `:term`, `:constraint`, `:remainder` or `:constant`,
and `children` indexes into the tree's `nodes`.
"""
struct TreeNode
    label::String
    detail::String
    kind::Symbol
    children::Vector{Int}
    note::String            # why the node is non-negative, where that needs saying
end
TreeNode(label, detail, kind, children) = TreeNode(label, detail, kind, children, "")

"""
    DecompositionTree

A decomposition of an information expression, as a tree of
[`TreeNode`](@ref)s. `nodes[root]` is the expression that was decomposed.
"""
struct DecompositionTree
    nodes::Vector{TreeNode}
    root::Int
    title::String
end

Base.length(t::DecompositionTree) = length(t.nodes)

function Base.show(io::IO, ::MIME"text/plain", t::DecompositionTree)
    show_subtree(io, t, t.root, "", true)
    return
end

function show_subtree(io::IO, t::DecompositionTree, i::Int, indent::String,
                      last::Bool)
    node = t.nodes[i]
    branch = isempty(indent) ? "" : (last ? "└─ " : "├─ ")
    lines = node_lines(node)
    println(io, indent, branch, lines[1])
    # a continuation line sits under the label, past the branch it belongs to
    below = indent * (isempty(indent) ? "" : (last ? "   " : "│  "))
    for extra in lines[2:end]
        println(io, below, " "^length(branch), extra)
    end
    for (k, c) in enumerate(node.children)
        show_subtree(io, t, c, indent * (isempty(indent) ? "  " :
                     (last ? "   " : "│  ")), k == length(node.children))
    end
    return
end

"""
What to print for a node: a constraint says what it stands for and why it
is non-negative, the expression being decomposed gives its own name where
it has one, and everything else is its label alone.
"""
function node_lines(node::TreeNode)
    if node.kind === :constraint && !isempty(node.detail)
        # a note that is only a relation belongs on the same line; one that
        # names the quantity ("-I(W;Y|X) = 0") gets a line of its own
        bare = node.note in (">= 0", "= 0")
        head = node.label * " = " * node.detail * (bare ? "  " * node.note : "")
        return bare || isempty(node.note) ? [head] : [head, "= " * node.note]
    elseif node.kind === :expression && !isempty(node.detail)
        return [node.label * "  =  " * node.detail]
    end
    return [node.label]
end

"""
    proof_tree(p::Proof) -> DecompositionTree
    proof_tree(r::Result) -> DecompositionTree

The derivation behind a proof as a tree: the expression splits into the
first non-negative term and what is left, that remainder splits again, and
so on until nothing (or a non-negative constant) remains.

A constraint is shown as what it stands for and why it is non-negative,
as in the picture:

```jldoctest
julia> proof_tree(explain("H(X,Y,Z) <= H(X,Y) + H(Z)"))
H(Z) + H(X,Y) - H(X,Y,Z)  =  I(X,Y;Z)
  ├─ I(X;Z|Y)
  └─ I(Y;Z)

julia> proof_tree(explain("I(X;Z) <= I(X;Y)", "X/Y/Z"))
-H(Z) + H(Y) + H(X,Z) - H(X,Y)
  ├─ C1 = H(Y) - H(X,Y) - H(Z,Y) + H(X,Z,Y)
  │     = -I(X;Z|Y) = 0
  └─ I(X;Y|Z)
```
"""
function proof_tree(p::Proof)
    nodes = TreeNode[]
    # the root holds the expression being decomposed
    push!(nodes, TreeNode(chop_relation(p.expression),
                          p.expression_name, :expression, Int[]))
    current = 1
    for step in p.steps
        term = isone(step.coefficient) ? step.label :
               format(step.coefficient) * " " * step.label
        # a constraint is not obviously non-negative, so the node says why:
        # "= -I(W;Y|X) = 0" for an equality used in reverse, for instance
        note = isempty(step.source) ? "" :
               (isempty(step.named) ? step.justification :
                step.named * " " * step.justification)
        push!(nodes, TreeNode(term, step.expansion,
                              isempty(step.source) ? :term : :constraint,
                              Int[], note))
        push!(nodes[current].children, length(nodes))
        # nothing left to split after the last step, unless a constant is
        step.remainder == "0" && continue
        rest = isempty(step.remainder_name) ? step.remainder :
               step.remainder_name
        push!(nodes, TreeNode(rest, step.remainder, :remainder, Int[]))
        push!(nodes[current].children, length(nodes))
        current = length(nodes)
    end
    # the last remainder is the last term itself; do not say it twice
    for (i, node) in enumerate(nodes)
        node.kind == :remainder && length(node.children) == 1 &&
            nodes[only(node.children)].label == node.label &&
            (nodes[i] = TreeNode(node.label, node.detail, :term, Int[], node.note))
    end
    # a left over constant is a term of the sum like any other
    isempty(p.steps) || iszero(p.constant) ||
        (nodes[current] = TreeNode(nodes[current].label, nodes[current].detail,
                                   :constant, nodes[current].children,
                                   nodes[current].note))
    return prune(DecompositionTree(nodes, 1, p.expression))
end

"""Drop nodes no longer reachable from the root and renumber the rest."""
function prune(t::DecompositionTree)
    order = Int[]
    stack = [t.root]
    while !isempty(stack)
        i = popfirst!(stack)
        push!(order, i)
        append!(stack, t.nodes[i].children)
    end
    length(order) == length(t.nodes) && return t
    renumber = Dict(old => new for (new, old) in enumerate(order))
    nodes = [TreeNode(t.nodes[i].label, t.nodes[i].detail, t.nodes[i].kind,
                      [renumber[c] for c in t.nodes[i].children],
                      t.nodes[i].note)
             for i in order]
    return DecompositionTree(nodes, renumber[t.root], t.title)
end

function proof_tree(r::Result)
    r.verdict || throw(XitipError("there is no proof to draw: the statement " *
                                  "does not follow from the elemental " *
                                  "inequalities"))
    isempty(r.certificates) &&
        throw(XitipError("no certificate: the statement was decided by the " *
                         "simplex method, which produces none"))
    return proof_tree(first(r.certificates)::Proof)
end

"""
    chain_rule_tree(vars) -> DecompositionTree
    chain_rule_tree(vars, given) -> DecompositionTree

The chain rule for a joint entropy as a tree:

```math
H(X_1, \\ldots, X_n \\mid Y) = H(X_1 \\mid Y) + H(X_2, \\ldots, X_n \\mid X_1, Y)
```

applied again to each remainder, down to the last variable.

```jldoctest
julia> chain_rule_tree(["X", "Y", "Z"])
H(X,Y,Z)
  ├─ H(X)
  └─ H(Y,Z|X)
     ├─ H(Y|X)
     └─ H(Z|X,Y)
```
"""
chain_rule_tree(vars::AbstractVector{<:AbstractString},
                given::AbstractVector{<:AbstractString}=String[]) =
    chain_rule_tree(String.(vars), String.(given))

function chain_rule_tree(vars::Vector{String}, given::Vector{String})
    isempty(vars) && throw(XitipError("need at least one variable"))
    entropy(set, cond) = "H(" * join(set, ",") *
                         (isempty(cond) ? "" : "|" * join(cond, ",")) * ")"
    nodes = [TreeNode(entropy(vars, given), "", :expression, Int[])]
    current = 1
    cond = copy(given)
    for (k, v) in enumerate(vars)
        k == length(vars) && break
        push!(nodes, TreeNode(entropy([v], cond), "", :term, Int[]))
        push!(cond, v)
        push!(nodes, TreeNode(entropy(vars[k+1:end], cond), "", :remainder,
                              Int[]))
        append!(nodes[current].children, [length(nodes) - 1, length(nodes)])
        current = length(nodes)
    end
    length(vars) == 1 ||
        (nodes[current] = TreeNode(nodes[current].label, nodes[current].detail,
                                   :term, Int[]))
    return DecompositionTree(nodes, 1, entropy(vars, given))
end

"""
    VariableGraph

The variables of a problem and how its constraints tie them together;
`edges` carries `(src, dst, kind, label)` with `kind` one of `:markov`,
`:independent` or `:function`.
"""
struct VariableGraph
    names::Vector{String}
    edges::Vector{Tuple{Int,Int,Symbol,String}}
    title::String
end

"""
    constraint_graph(lines...) -> VariableGraph

The structural constraints of a problem as a graph over its variables:
a Markov chain becomes a path, mutual independence a set of undirected
links, and a functional dependence an arrow from each argument to the
variable it determines.

Constraints written as general relations (`I(X;Y|Z) = 0` and the like) have
no natural edge and are left out, as is the statement being proven.

```jldoctest
julia> g = constraint_graph("I(W;Z) <= I(X;Y)", "W/X/Y/Z");

julia> g.names
4-element Vector{String}:
 "W"
 "Z"
 "X"
 "Y"

julia> g.edges
3-element Vector{Tuple{Int64, Int64, Symbol, String}}:
 (1, 3, :markov, "W/X/Y/Z")
 (3, 4, :markov, "W/X/Y/Z")
 (4, 2, :markov, "W/X/Y/Z")
```
"""
constraint_graph(lines::AbstractString...) = constraint_graph(collect(lines))

function constraint_graph(lines::AbstractVector{<:AbstractString})
    stmts, sources = parse_statements(lines)
    names = variables(stmts)
    index = Dict(v => i for (i, v) in enumerate(names))
    edges = Tuple{Int,Int,Symbol,String}[]
    titles = String[]
    for (k, stmt) in enumerate(stmts)
        k == 1 && continue                      # the statement being proven
        text = sources[k]
        if stmt isa MarkovChain
            for i in 1:length(stmt.parts)-1, a in stmt.parts[i],
                    b in stmt.parts[i+1]
                push!(edges, (index[a], index[b], :markov, text))
            end
            push!(titles, text)
        elseif stmt isa MutualIndependence
            for i in 1:length(stmt.parts), j in i+1:length(stmt.parts),
                    a in stmt.parts[i], b in stmt.parts[j]
                push!(edges, (index[a], index[b], :independent, text))
            end
            push!(titles, text)
        elseif stmt isa FunctionOf
            for a in stmt.of, b in stmt.func
                push!(edges, (index[a], index[b], :function, text))
            end
            push!(titles, text)
        end
    end
    return VariableGraph(names, edges, join(titles, ",  "))
end

"""
    wrap_expression(text, width) -> String

Break an information expression over several lines at its `+` and `-`
signs, so that no line is much wider than `width` characters. Used to keep
the labels of a drawn tree readable.
"""
function wrap_expression(text::AbstractString, width::Int)
    length(text) <= width && return String(text)
    lines = String[]
    for term in split_terms(text)
        if isempty(lines) || length(lines[end]) + length(term) + 1 > width
            push!(lines, term)
        else
            lines[end] *= " " * term
        end
    end
    return join(lines, "\n")
end

"""
    entropy_table(c::Counterexample) -> Vector{Pair{String,Coef}}

The entropy values of a counterexample, as `"H(X,Y)" => value` pairs
ordered by how many variables each subset holds.

The values are entropies in bits, so they are bounded by the logarithm of
the alphabet size rather than by 1 — `H(X) = 6` is a variable with up to 64
equally likely values. When the counterexample is a direction
(`c.direction`), the scale is free as well: every positive multiple of the
values fails in the same way, and small integers are simply the most
readable representative.

```jldoctest
julia> entropy_table(only(explain("H(X) <= H(Y)").certificates))
3-element Vector{Pair{String, Rational{BigInt}}}:
   "H(X)" => 5
   "H(Y)" => 4
 "H(X,Y)" => 7
```
"""
function entropy_table(c::Counterexample)
    n = length(c.var_names)
    subsets = sort(1:(1 << n) - 1; by = S -> (count_ones(S), S))
    return ["H($(setname(S, c.var_names)))" => c.entropies[S] for S in subsets]
end

entropy_table(r::Result) = entropy_table(only(r.certificates)::Counterexample)

#----------------------------------------------------------------------------
# Plotting, provided by the extension in ext/XitipMakieExt.jl
#----------------------------------------------------------------------------

const PLOT_HINT = """
plotting needs CairoMakie, GraphMakie and Graphs:

    using CairoMakie, GraphMakie, Graphs, Xitip
"""

"""
    plot_proof_tree(x; kwargs...) -> Figure

Draw the derivation behind a proof as a hierarchical tree, with the
expression at the root, the non-negative terms branching off to one side and
the remainder carrying on down the other. `x` may be a [`Result`](@ref), a
[`Proof`](@ref) or a [`DecompositionTree`](@ref).

$PLOT_HINT

Keywords: `detail=true` shows the entropy form under each label,
`size=(width, height)`, `title`.
"""
plot_proof_tree(::Any...; kw...) = throw(XitipError(PLOT_HINT))

"""
    plot_chain_rule(vars; kwargs...) -> Figure

Draw the chain rule expansion of a joint entropy as a tree; see
[`chain_rule_tree`](@ref).

$PLOT_HINT
"""
plot_chain_rule(::Any...; kw...) = throw(XitipError(PLOT_HINT))

"""
    plot_counterexample(x; kwargs...) -> Figure

Draw the entropy values that defeat a statement as a bar chart, grouped by
how many variables each subset holds; `x` may be a [`Result`](@ref) or a
[`Counterexample`](@ref). See [`entropy_table`](@ref) for the numbers.

$PLOT_HINT
"""
plot_counterexample(::Any...; kw...) = throw(XitipError(PLOT_HINT))

"""
    plot_constraints(lines...; kwargs...) -> Figure

Draw the structural constraints of a problem as a graph over its variables;
see [`constraint_graph`](@ref).

$PLOT_HINT
"""
plot_constraints(::Any...; kw...) = throw(XitipError(PLOT_HINT))
