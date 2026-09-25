#----------------------------------------------------------------------------
# Lexer
#----------------------------------------------------------------------------
#
# Tokens:  NAME    [A-Za-z][A-Za-z0-9_]*
#          NUM     [0-9]+ | [0-9]*\.[0-9]+
#          SIGN    + -
#          REL     = == <= >=
#          'H' 'I' only when followed by '(' (otherwise they are names)
#          everything else is a single character literal
#
# '#' starts a comment; spaces, tabs and CR are ignored.

struct Token
    kind::Symbol        # :name :num :sign :rel :lit :eof
    text::String
    col::Int            # 1-based column of the first character
    len::Int
end

isdig(c::Char) = '0' <= c <= '9'
isalpha_ascii(c::Char) = ('a' <= c <= 'z') || ('A' <= c <= 'Z')
isnamechar(c::Char) = isalpha_ascii(c) || isdig(c) || c == '_'
isblank_(c::Char) = c == ' ' || c == '\t' || c == '\r'

function tokenize(line::AbstractString)
    cs = collect(line)
    n = length(cs)
    toks = Token[]
    i = 1
    while i <= n
        c = cs[i]
        next = i < n ? cs[i+1] : '\0'
        if c == '#'
            break
        elseif isblank_(c)
            i += 1
        elseif (c == 'H' || c == 'I') && begin
                    j = i + 1
                    while j <= n && isblank_(cs[j]); j += 1; end
                    j <= n && cs[j] == '('
                end
            push!(toks, Token(:lit, string(c), i, 1))
            i += 1
        elseif isalpha_ascii(c)
            j = i
            while j < n && isnamechar(cs[j+1]); j += 1; end
            push!(toks, Token(:name, String(cs[i:j]), i, j - i + 1))
            i = j + 1
        elseif isdig(c) || (c == '.' && isdig(next))
            j = i
            while j <= n && isdig(cs[j]); j += 1; end
            if j < n && cs[j] == '.' && isdig(cs[j+1])
                j += 1
                while j <= n && isdig(cs[j]); j += 1; end
            end
            push!(toks, Token(:num, String(cs[i:j-1]), i, j - i))
            i = j
        elseif c == '+' || c == '-'
            push!(toks, Token(:sign, string(c), i, 1))
            i += 1
        elseif c == '='
            len = next == '=' ? 2 : 1
            push!(toks, Token(:rel, "=", i, len))
            i += len
        elseif (c == '<' || c == '>') && next == '='
            push!(toks, Token(:rel, c * "=", i, 2))
            i += 2
        else
            push!(toks, Token(:lit, string(c), i, 1))
            i += 1
        end
    end
    push!(toks, Token(:eof, "", n + 1, 1))
    return toks
end
