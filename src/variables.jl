#----------------------------------------------------------------------------
# Variables
#----------------------------------------------------------------------------

varlists(q::Quantity) = [q.parts; [q.cond]]
varlists(r::Relation) = [vl for t in [r.left; r.right]
                            if t.quantity !== nothing
                            for vl in varlists(t.quantity)]
varlists(s::Union{MarkovChain,MutualIndependence}) = s.parts
varlists(s::FunctionOf) = [s.func, s.of]

"""Distinct variable names, in order of first appearance."""
function variables(stmts)
    names = String[]
    seen = Set{String}()
    for s in stmts, vl in varlists(s), v in vl
        v in seen || (push!(seen, v); push!(names, v))
    end
    return names
end
