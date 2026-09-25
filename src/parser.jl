#----------------------------------------------------------------------------
# Parser (recursive descent)
#----------------------------------------------------------------------------
#
#   statement    := <empty> | relation | markov_chain | mutual_indep | function_of
#   relation     := expr REL expr
#   markov_chain := var_list '/' var_list '/' var_list ('/' var_list)*
#   mutual_indep := var_list '.' var_list ('.' var_list)*
#   function_of  := var_list ':' var_list
#   expr         := [SIGN] term (SIGN term)*
#   term         := NUM quantity | quantity | NUM
#   quantity     := 'H' '(' var_list ['|' var_list] ')'
#                 | 'I' '(' var_list (colon var_list)+ ['|' var_list] ')'
#   colon        := ':' | ';'
#   var_list     := NAME (',' NAME)*

const VarList = Vector{String}

struct Quantity
    parts::Vector{VarList}      # H: one part; I: two or more parts
    cond::VarList
end

struct Term
    coef::Coef
    quantity::Union{Quantity,Nothing}   # nothing = constant term
end

struct Relation
    left::Vector{Term}
    rel::Symbol                 # :eq :le :ge
    right::Vector{Term}
end

struct MarkovChain
    parts::Vector{VarList}
end

struct MutualIndependence
    parts::Vector{VarList}
end

struct FunctionOf
    func::VarList
    of::VarList
end

const Statement = Union{Relation,MarkovChain,MutualIndependence,FunctionOf}

mutable struct Parser
    toks::Vector{Token}
    pos::Int
end

peek(p::Parser) = p.toks[p.pos]
function advance!(p::Parser)
    t = p.toks[p.pos]
    t.kind == :eof || (p.pos += 1)
    return t
end
islit(t::Token, s::AbstractString) = t.kind == :lit && t.text == s
iscolon(t::Token) = islit(t, ":") || islit(t, ";")

function describe(t::Token)
    t.kind == :eof  && return "end of input"
    t.kind == :name && return "name '$(t.text)'"
    t.kind == :num  && return "number $(t.text)"
    return "'$(t.text)'"
end

function unexpected(p::Parser, expecting::AbstractString)
    t = peek(p)
    throw(SyntaxError("unexpected $(describe(t)), expecting $expecting",
                      t.col, t.len))
end

function expect_lit!(p::Parser, s::AbstractString, expecting="'$s'")
    islit(peek(p), s) || unexpected(p, expecting)
    advance!(p)
end

function parse_number(s::AbstractString)
    i = findfirst('.', s)
    i === nothing && return Coef(parse(BigInt, s))
    int, frac = s[1:i-1], s[i+1:end]
    return parse(BigInt, int * frac) // big(10)^length(frac)
end

function parse_var_list!(p::Parser)
    peek(p).kind == :name || unexpected(p, "a variable name")
    names = [advance!(p).text]
    while islit(peek(p), ",")
        advance!(p)
        peek(p).kind == :name || unexpected(p, "a variable name")
        push!(names, advance!(p).text)
    end
    return names
end

function parse_quantity!(p::Parser)
    kw = advance!(p).text                   # "H" or "I"
    expect_lit!(p, "(")
    parts = [parse_var_list!(p)]
    if kw == "I"
        iscolon(peek(p)) || unexpected(p, "',', ';' or ':'")
        while iscolon(peek(p))
            advance!(p)
            push!(parts, parse_var_list!(p))
        end
    end
    cond = String[]
    if islit(peek(p), "|")
        advance!(p)
        cond = parse_var_list!(p)
    end
    expect_lit!(p, ")", kw == "H" ? "',', '|' or ')'" : "',', ';', '|' or ')'")
    return Quantity(parts, cond)
end

isquantity(t::Token) = islit(t, "H") || islit(t, "I")

function parse_term!(p::Parser, sign::Int)
    t = peek(p)
    if t.kind == :num
        coef = sign * parse_number(advance!(p).text)
        isquantity(peek(p)) && return Term(coef, parse_quantity!(p))
        return Term(coef, nothing)
    elseif isquantity(t)
        return Term(Coef(sign), parse_quantity!(p))
    end
    unexpected(p, "a number, H(...) or I(...)")
end

readsign!(p::Parser) = advance!(p).text == "-" ? -1 : 1

function parse_expr!(p::Parser)
    sign = peek(p).kind == :sign ? readsign!(p) : 1
    terms = [parse_term!(p, sign)]
    while peek(p).kind == :sign
        sign = readsign!(p)
        push!(terms, parse_term!(p, sign))
    end
    return terms
end

const RELATIONS = Dict("=" => :eq, "<=" => :le, ">=" => :ge)

function parse_relation!(p::Parser)
    left = parse_expr!(p)
    peek(p).kind == :rel || unexpected(p, "'+', '-', '<=', '>=' or '='")
    rel = RELATIONS[advance!(p).text]
    right = parse_expr!(p)
    return Relation(left, rel, right)
end

function parse_var_statement!(p::Parser)
    first = parse_var_list!(p)
    t = peek(p)
    if islit(t, "/") || islit(t, ".")
        sep = t.text
        parts = [first]
        while islit(peek(p), sep)
            advance!(p)
            push!(parts, parse_var_list!(p))
        end
        if sep == "/"
            length(parts) >= 3 || unexpected(p, "'/'")
            return MarkovChain(parts)
        end
        return MutualIndependence(parts)
    elseif islit(t, ":")
        advance!(p)
        return FunctionOf(first, parse_var_list!(p))
    end
    unexpected(p, "',', '/', '.' or ':'")
end

"""
    parse_statement(line) -> Statement or nothing

Parse one line. Returns `nothing` for empty or comment-only lines.
"""
function parse_statement(line::AbstractString)
    p = Parser(tokenize(line), 1)
    peek(p).kind == :eof && return nothing
    stmt = peek(p).kind == :name ? parse_var_statement!(p) : parse_relation!(p)
    peek(p).kind == :eof || unexpected(p, "end of input")
    return stmt
end

"""
    parse_statements(lines) -> (statements, sources)

Parse all lines, dropping empty and comment-only ones and keeping the text
each statement came from. Syntax errors are annotated with the offending
line and a marker.
"""
function parse_statements(lines)
    stmts = Statement[]
    sources = String[]
    for (row, line) in enumerate(lines)
        stmt = try
            parse_statement(line)
        catch e
            e isa SyntaxError || rethrow()
            msg = string("syntax error, ", e.msg, "\n",
                         "in row ", row, " col ", e.col, ":\n\n",
                         "    ", line, "\n",
                         "    ", " "^(e.col - 1), "^"^max(1, e.len))
            throw(SyntaxError(msg, e.col, e.len))
        end
        if stmt !== nothing
            push!(stmts, stmt)
            push!(sources, strip(split(line, "#")[1]))
        end
    end
    isempty(stmts) && throw(XitipError("no information expression given"))
    return stmts, sources
end

"""Statements of `lines`; see [`parse_statements`](@ref)."""
parse_lines(lines) = first(parse_statements(lines))
