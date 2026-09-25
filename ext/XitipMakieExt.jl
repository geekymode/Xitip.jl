module XitipMakieExt

using Xitip
using Xitip: DecompositionTree, TreeNode, VariableGraph,
             proof_tree, chain_rule_tree, constraint_graph, entropy_table
using CairoMakie
using GraphMakie
using Graphs
using NetworkLayout: Buchheim, Stress

# Colour by what a node is: the expression being decomposed, a term of the
# proof, a term coming from one of the user's constraints, what is still
# left at that point, or the constant at the very end.
const NODE_COLOUR = Dict(
    :expression => RGBf(0.20, 0.29, 0.44),
    :term       => RGBf(0.16, 0.45, 0.35),
    :constraint => RGBf(0.63, 0.35, 0.12),
    :remainder  => RGBf(0.45, 0.47, 0.52),
    :constant   => RGBf(0.45, 0.47, 0.52),
)

const EDGE_STYLE = Dict(
    :markov      => (:solid, RGBf(0.20, 0.29, 0.44)),
    :independent => (:dash, RGBf(0.45, 0.47, 0.52)),
    :function    => (:solid, RGBf(0.63, 0.35, 0.12)),
)

# A constraint is drawn as C1, C2, ... to keep the tree narrow, so its
# label has to say what that stands for; everything else shows its entropy
# form only when asked.
function label_of(node::TreeNode, detail::Bool, width::Int)
    wrap(text) = Xitip.wrap_expression(text, width)
    if node.kind === :constraint && !isempty(node.detail)
        # "C1 = H(X) - H(W,X) - ...", then why that is non-negative:
        # "= -I(W;Y|X) = 0", since a constraint is not obviously so
        head = node.label * " = " * wrap(node.detail)
        return isempty(node.note) ? head : head * "\n= " * node.note
    end
    detail && !isempty(node.detail) && node.detail != node.label &&
        return wrap(node.label) * "\n" * wrap(node.detail)
    return wrap(node.label)
end

"""Lay a decomposition tree out and draw it."""
function draw_tree(t::DecompositionTree; detail::Bool=false,
                   size=nothing, title::AbstractString=t.title,
                   fontsize::Real=14, wrap::Union{Int,Nothing}=nothing,
                   maxwidth::Int=640)
    g = SimpleDiGraph(length(t.nodes))
    for (i, node) in enumerate(t.nodes), c in node.children
        add_edge!(g, i, c)
    end
    depth = maximum(node_depth(t, i) for i in eachindex(t.nodes)) + 1
    # Keep the figure no wider than a page: a figure that has to be scaled
    # down to fit takes its labels with it, and the text ends up unreadable.
    # Wrapping the labels harder trades width for height, which costs nothing.
    labels, room_left, room_right = String[], 0, 0
    for width in (wrap === nothing ? (34, 30, 26, 22, 18, 14) : (wrap,))
        labels = [label_of(node, detail, width) for node in t.nodes]
        room_left, room_right = label_room(t, labels)
        estimate = 0.62 * fontsize * (room_left + room_right) + 40 * depth
        (estimate <= maxwidth || width == 14) && break
    end
    # a term hangs off to the left of its parent, so its label reads outwards
    # from there; everything else keeps its label on the right
    outwards = falses(length(t.nodes))
    for node in t.nodes, (k, c) in enumerate(node.children)
        outwards[c] = k == 1 && length(node.children) > 1
    end
    aligns = [o ? (:right, :center) : (:left, :center) for o in outwards]
    offsets = [Point2f(o ? -0.08 : 0.08, 0) for o in outwards]
    colours = [NODE_COLOUR[node.kind] for node in t.nodes]
    # the labels are information expressions, not short names, so the figure
    # is sized from the widest line and the tallest label, after wrapping
    widest = maximum(maximum(length, split(l, "\n")) for l in labels)
    tallest = maximum(count(==('\n'), l) for l in labels) + 1
    legend = length(unique(node.kind for node in t.nodes
                           if node.kind !== :expression)) > 1
    figsize = something(size,
                        (clamp(round(Int, 0.62 * fontsize *
                                          (room_left + room_right) +
                                          40 * depth), 640, maxwidth),
                         max(260, depth * (58 + 20 * tallest)) +
                         (legend ? 40 : 0)))

    fig = Figure(; size=figsize)
    ax = Axis(fig[1, 1]; title=String(title), titlesize=fontsize + 3,
              titlegap=12)
    graphplot!(ax, g;
               layout = Buchheim(),
               node_size = 13,
               node_color = colours,
               nlabels = labels,
               nlabels_fontsize = fontsize,
               nlabels_align = aligns,
               nlabels_offset = offsets,
               nlabels_color = colours,
               arrow_show = false,
               edge_color = RGBf(0.72, 0.74, 0.78),
               edge_width = 1.6)
    # a legend, so the colours do not have to be guessed; the root explains
    # itself, so it does not count towards needing one
    present = unique(node.kind for node in t.nodes)
    labelled = filter(!isequal(:expression), present)
    for (kind, text) in ((:term, "non-negative term"),
                         (:constraint, "from a constraint"),
                         (:remainder, "what is left"),
                         (:constant, "constant"))
        kind in present || continue
        scatter!(ax, [NaN], [NaN]; color=NODE_COLOUR[kind], markersize=11,
                 label=text)
    end
    # below the plot, where it cannot land on a node or a label
    length(labelled) > 1 && Legend(fig[2, 1], ax; orientation=:horizontal,
                                  framevisible=false, labelsize=fontsize - 1,
                                  padding=(0, 0, 0, 0), rowgap=0)
    hidedecorations!(ax)
    hidespines!(ax)
    # room on the right for the labels, which extend past their node
    # autolimitmargin is a fraction of the data range, so turn the pixels the
    # labels need into that fraction
    px_left = 0.55 * fontsize * room_left
    px_right = 0.55 * fontsize * room_right
    share = clamp((px_left + px_right) / figsize[1], 0.0, 0.8)
    scale = 1 / max(0.2, 1 - share)
    ax.xautolimitmargin = (0.04 + scale * px_left / figsize[1],
                           0.04 + scale * px_right / figsize[1])
    ax.yautolimitmargin = (0.15, 0.15)
    return fig
end

"""How wide the labels on each side of the tree are, in characters."""
function label_room(t::DecompositionTree, labels)
    outwards = falses(length(t.nodes))
    for node in t.nodes, (k, c) in enumerate(node.children)
        outwards[c] = k == 1 && length(node.children) > 1
    end
    linewidth(l) = maximum(length, split(l, "\n"))
    left = maximum((linewidth(labels[i]) for i in eachindex(labels)
                    if outwards[i]); init=0)
    right = maximum((linewidth(labels[i]) for i in eachindex(labels)
                     if !outwards[i]); init=0)
    return left, right
end

function node_depth(t::DecompositionTree, target::Int)
    depth = Dict(t.root => 0)
    stack = [t.root]
    while !isempty(stack)
        i = pop!(stack)
        for c in t.nodes[i].children
            depth[c] = depth[i] + 1
            push!(stack, c)
        end
    end
    return get(depth, target, 0)
end

Xitip.plot_proof_tree(t::DecompositionTree; kw...) = draw_tree(t; kw...)
Xitip.plot_proof_tree(p::Proof; kw...) = draw_tree(proof_tree(p); kw...)
Xitip.plot_proof_tree(r::Result; kw...) = draw_tree(proof_tree(r); kw...)
Xitip.plot_proof_tree(lines::AbstractString...; kw...) =
    draw_tree(proof_tree(explain(collect(lines))); kw...)

Xitip.plot_chain_rule(t::DecompositionTree; kw...) = draw_tree(t; kw...)
Xitip.plot_chain_rule(vars::AbstractVector{<:AbstractString},
                      given::AbstractVector{<:AbstractString}=String[]; kw...) =
    draw_tree(chain_rule_tree(vars, given); kw...)
Xitip.plot_chain_rule(vars::AbstractString...; kw...) =
    draw_tree(chain_rule_tree(collect(vars)); kw...)

"""Draw the variables of a problem and the constraints tying them together."""
function draw_constraints(vg::VariableGraph; size=nothing,
                          title::AbstractString=vg.title, fontsize::Real=15)
    n = length(vg.names)
    g = SimpleDiGraph(n)
    # what each edge is, looked up by its endpoints: GraphMakie walks the
    # graph's own edge order, which is not the order they were added in
    kind_of = Dict{Tuple{Int,Int},Symbol}()
    for (src, dst, kind, _) in vg.edges
        haskey(kind_of, (src, dst)) && continue
        add_edge!(g, src, dst)
        kind_of[(src, dst)] = kind
    end
    kinds = [kind_of[(src(e), dst(e))] for e in edges(g)]
    styles = [EDGE_STYLE[k][1] for k in kinds]
    colours = [EDGE_STYLE[k][2] for k in kinds]

    layout = path_layout(g, vg)
    legend = length(unique(last.(collect(kind_of)))) > 1
    figsize = something(size, (620, (layout isa Function ? 260 : 460) +
                                    (legend ? 40 : 0)))
    fig = Figure(; size=figsize)
    ax = Axis(fig[1, 1]; title=String(title), titlesize=fontsize + 2)
    graphplot!(ax, g;
               layout = layout,
               node_size = 34,
               node_color = RGBf(0.93, 0.94, 0.96),
               node_strokewidth = 1.5,
               node_strokecolor = RGBf(0.20, 0.29, 0.44),
               nlabels = vg.names,
               nlabels_fontsize = fontsize,
               nlabels_align = (:center, :center),
               nlabels_color = RGBf(0.12, 0.15, 0.20),
               edge_color = isempty(colours) ? RGBf(0.7, 0.7, 0.7) : colours,
               edge_width = 1.8,
               edge_attr = (; linestyle = isempty(styles) ? :solid : styles),
               # independence is symmetric, so it gets no arrow head
               arrow_show = any(k -> k !== :independent, kinds),
               arrow_size = [k === :independent ? 0 : 12 for k in kinds])
    for (kind, text) in ((:markov, "Markov chain"),
                         (:independent, "independent"),
                         (:function, "function of"))
        kind in kinds || continue
        style, colour = EDGE_STYLE[kind]
        lines!(ax, [NaN, NaN], [NaN, NaN]; color=colour, linestyle=style,
               linewidth=1.8, label=text)
    end
    length(unique(kinds)) > 1 && Legend(fig[2, 1], ax; orientation=:horizontal,
                                        framevisible=false,
                                        labelsize=fontsize - 2,
                                        padding=(0, 0, 0, 0), rowgap=0)
    hidedecorations!(ax)
    hidespines!(ax)
    ax.xautolimitmargin = (0.15, 0.15)
    ax.yautolimitmargin = (0.2, 0.2)
    return fig
end

"""
A chain of Markov links reads best as a straight line; anything else gets
the usual stress-minimising layout.
"""
function path_layout(g, vg::VariableGraph)
    n = nv(g)
    ends = [v for v in 1:n if length(all_neighbors(g, v)) == 1]
    if all(e -> e[3] === :markov, vg.edges) && length(ends) == 2 &&
            all(v -> length(all_neighbors(g, v)) <= 2, 1:n) && is_connected(g)
        order, seen = Int[], falses(n)
        v = first(ends)
        while true
            push!(order, v); seen[v] = true
            next = filter(u -> !seen[u], all_neighbors(g, v))
            isempty(next) && break
            v = first(next)
        end
        length(order) == n &&
            return _ -> [Point2f(i - 1, 0) for i in invperm(order)]
    end
    return Stress()
end

Xitip.plot_constraints(vg::VariableGraph; kw...) = draw_constraints(vg; kw...)
Xitip.plot_constraints(lines::AbstractString...; kw...) =
    draw_constraints(constraint_graph(collect(lines)); kw...)
Xitip.plot_constraints(lines::AbstractVector{<:AbstractString}; kw...) =
    draw_constraints(constraint_graph(lines); kw...)

"""Draw the entropy values that defeat a statement."""
function draw_counterexample(c::Counterexample; size=nothing,
                             title::AbstractString="", fontsize::Real=14)
    table = entropy_table(c)
    values = Float64[Float64(v) for (_, v) in table]
    labels = [k for (k, _) in table]
    n = length(c.var_names)
    sizes = [count_ones(S) for S in sort(1:(1 << n) - 1;
                                         by = S -> (count_ones(S), S))]
    # the same width as the trees, so the text reads at the same size
    figsize = something(size, (clamp(42 * length(values), 560, 640), 360))
    fig = Figure(; size=figsize)
    head = isempty(title) ?
           "entropies that satisfy every inequality but give " *
           "$(Xitip.format(c.value)) < 0" : String(title)
    ax = Axis(fig[1, 1]; title=head, titlesize=fontsize + 1,
              ylabel="entropy", xticks=(1:length(values), labels),
              xticklabelrotation=length(values) > 7 ? pi/4 : 0.0,
              xticklabelsize=fontsize - 1, yticklabelsize=fontsize - 1)
    barplot!(ax, 1:length(values), values;
             color = sizes, colormap = :dense, colorrange = (0, maximum(sizes)),
             strokewidth = 0.5, strokecolor = RGBf(0.35, 0.37, 0.42))
    hidespines!(ax, :t, :r)
    return fig
end

Xitip.plot_counterexample(c::Counterexample; kw...) = draw_counterexample(c; kw...)
Xitip.plot_counterexample(r::Result; kw...) =
    draw_counterexample(only(r.certificates)::Counterexample; kw...)
Xitip.plot_counterexample(lines::AbstractString...; kw...) =
    Xitip.plot_counterexample(explain(collect(lines)); kw...)

end # module XitipMakieExt
