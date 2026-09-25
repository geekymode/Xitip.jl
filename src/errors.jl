#----------------------------------------------------------------------------
# Errors
#----------------------------------------------------------------------------

"""Invalid input or unsolvable problem (reported to the user, exit code 2)."""
struct XitipError <: Exception
    msg::String
end
Base.showerror(io::IO, e::XitipError) = print(io, e.msg)

"""Syntax error; `msg` includes the offending line and a location marker."""
struct SyntaxError <: Exception
    msg::String
    col::Int
    len::Int
end
Base.showerror(io::IO, e::SyntaxError) = print(io, e.msg)
