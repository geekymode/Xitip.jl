#----------------------------------------------------------------------------
# Linear relations over joint entropies
#----------------------------------------------------------------------------
#
# A relation is stored as  Σ coefs[S] H(S) + coefs[0]  >= 0  (or = 0), where
# S is the bitmask of a non-empty subset of the random variables and key 0
# holds the constant term.

struct LinRel
    coefs::Dict{Int,Coef}
    equality::Bool
    row::Int                # line the statement came from (0 if unknown)
end
LinRel(coefs, equality) = LinRel(coefs, equality, 0)

negate(r::LinRel) = LinRel(Dict(k => -v for (k, v) in r.coefs), r.equality, r.row)

inc!(d::Dict{Int,Coef}, k::Int, v) = (d[k] = get(d, k, zero(Coef)) + v; d)

function subset(index::Dict{String,Int}, vl::VarList)
    s = 0
    for v in vl
        s |= 1 << (index[v] - 1)
    end
    return s
end

function add_term!(d, index, t::Term, scale::Int)
    coef = scale * t.coef
    if t.quantity === nothing
        inc!(d, 0, coef)
        return
    end
    # Multivariate (conditional) mutual information as the alternating sum
    # of conditional entropies over non-empty subsets T of the parts:
    #
    #       I(X1:...:Xk|Y) = - Σ (-1)^|T| H(T|Y),   H(T|Y) = H(T,Y) - H(Y)
    #
    # For k=1 this is just H(X1|Y).
    q = t.quantity
    parts = [subset(index, vl) for vl in q.parts]
    c = subset(index, q.cond)
    k = length(parts)
    k > MAX_VARS && throw(XitipError("Too many parts in mutual information! " *
                                     "At most $MAX_VARS are allowed."))
    for set in 1:(1 << k) - 1
        a, s = 0, -1
        for i in 1:k
            if set & (1 << (i - 1)) != 0
                a |= parts[i]
                s = -s
            end
        end
        inc!(d, a | c, s * coef)
    end
    # Σ over non-empty T of (-1)^|T| = -1, so the H(Y) terms sum to -H(Y):
    c != 0 && inc!(d, c, -coef)
end

function linrels(index, r::Relation)
    # l <= r  =>  -l + r >= 0;   l >= r  =>  l - r >= 0;   l = r  =>  l - r = 0
    ls = r.rel == :le ? -1 : 1
    d = Dict{Int,Coef}()
    foreach(t -> add_term!(d, index, t, ls), r.left)
    foreach(t -> add_term!(d, index, t, -ls), r.right)
    return [LinRel(d, r.rel == :eq)]
end

function linrels(index, mi::MutualIndependence)
    # 0 = H(a) + H(b) + ... - H(a,b,...)
    d = Dict{Int,Coef}()
    all = 0
    for vl in mi.parts
        s = subset(index, vl)
        all |= s
        inc!(d, s, 1)
    end
    inc!(d, all, -1)
    return [LinRel(d, true)]
end

function linrels(index, mc::MarkovChain)
    # For each link: 0 = I(a:c|b) = H(a,b) + H(c,b) - H(b) - H(a,b,c), where
    # a accumulates all preceding variables.
    rels = LinRel[]
    a = 0
    for i in 1:length(mc.parts) - 2
        a |= subset(index, mc.parts[i])
        b = subset(index, mc.parts[i+1])
        c = subset(index, mc.parts[i+2])
        d = Dict{Int,Coef}()
        inc!(d, a | b, 1)
        inc!(d, c | b, 1)
        inc!(d, b, -1)
        inc!(d, a | b | c, -1)
        push!(rels, LinRel(d, true))
    end
    return rels
end

function linrels(index, fo::FunctionOf)
    # 0 = H(func|of) = H(func,of) - H(of)
    f, o = subset(index, fo.func), subset(index, fo.of)
    d = Dict{Int,Coef}()
    inc!(d, f | o, 1)
    inc!(d, o, -1)
    return [LinRel(d, true)]
end

struct Problem
    var_names::Vector{String}
    inquiries::Vector{LinRel}       # the statement to prove (first line)
    constraints::Vector{LinRel}     # all further lines
end

function Problem(stmts::Vector{Statement})
    names = variables(stmts)
    length(names) > MAX_VARS &&
        throw(XitipError("Too many variables! At most $MAX_VARS are allowed."))
    index = Dict(v => i for (i, v) in enumerate(names))
    clean(r, row) = LinRel(filter(kv -> !iszero(kv.second), r.coefs),
                           r.equality, row)
    rels = [[clean(r, row) for r in linrels(index, s)]
            for (row, s) in enumerate(stmts)]
    return Problem(names, rels[1], reduce(vcat, rels[2:end]; init=LinRel[]))
end
