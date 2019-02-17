__precompile__()
module Unrolled

using MacroTools
using MacroTools: prewalk, postwalk

export @unroll, @code_unrolled
export unrolled_reduce, unrolled_filter, unrolled_intersect, unrolled_setdiff,
       unrolled_union, unrolled_in, unrolled_any, unrolled_all, unrolled_map,
       unrolled_foreach

function unrolled_filter end
""" `type_length(::Type)` returns the length of sequences of that type (only makes sense
for sequence-like types, obviously. """
function type_length end

"""
`type_size(::Type, dim)` returns the size of an array in the specified dimension.
"""
function type_size end


include("range.jl")

const expansion_funs = Dict{Function, Function}()

macro unroll_loop(niter_type::Type, loop)
    local niter
    @assert(@capture(loop, for var_ in seq_ loopbody__ end),
            "Internal error in @unroll_loop")
    try
        niter = type_length(niter_type)
    catch e
        # Don't unroll the loop, we can't figure out its length
        if isa(e, MethodError)
            return esc(loop)
        else rethrow() end
    end
    esc(:($Unrolled.@unroll_loop($niter, for $var in $seq
          $(loopbody...)
          end)))
end
macro unroll_loop(niter::Int, loop)
    @assert(@capture(loop, for var_ in seq_ loopbody__ end),
            "Internal error in @unroll_loop")
    esc(quote
        $([:(let $var = $seq[$i]; $(loopbody...) end) for i in 1:niter]...)
        nothing
        end)
end

macro unroll_loop(loop::Expr)
    @assert(@capture(loop, for var_ in 1:niter_ loopbody__ end),
            "Internal error in @unroll_loop")
    esc(quote $([:(let $var = $i; $(loopbody...) end) for i in 1:niter]...) end)
end

type_length(tup::Type{T}) where {T<:Tuple} = length(tup.parameters)
# Default fall-back
type_length(typ::Type) = length(typ)
type_size(typ::Type, i) = size(typ, i)

""" `function_argument_name(arg_expr)`

Returns the name (as a symbol) of this argument, where arg_expr is whatever can
be put in a function definition's argument list (eg. `len::Int=5`) """
function_argument_name(arg_expr) = MacroTools.splitarg(arg_expr)[1]

macro unroll(fundef)
    # This macro will turn the function definition into a generated function.
    di = splitdef(fundef)
    @assert !haskey(di, :params) "`@unroll` only supports parametric functions using `where ...` notation"
    fname = di[:name]
    args = di[:args]
    kwargs = get(di, :kwargs, [])
    body = di[:body]
    arg_vars = [a===nothing ? gensym() : a for a in map(function_argument_name, args)]
    kwarg_vars = map(function_argument_name, kwargs)
    all_args = [arg_vars; kwarg_vars]
    function seq_type(seq_var)
        @assert(seq_var in all_args,
                "Can only unroll a loop over one of the function's arguments")
        return Expr(:($), seq_var)
    end
    function seq_type_length(seq_var)
        @assert(seq_var in all_args,
                "Can only unroll a loop over one of the function's arguments")
        return Expr(:($), Expr(:call, :($Unrolled.type_length), seq_var))
    end
    function seq_type_size(seq_var, dim)
        @assert(seq_var in all_args,
                "Can only unroll a loop over one of the function's arguments")
        @assert(dim isa Integer,
                "Dimension argument must be an integer")
        return Expr(:($), Expr(:call, :($Unrolled.type_size), seq_var, dim))
    end
    process(x) = x
    function process(expr::Expr)
        if expr.args[1]==Symbol("@unroll")
            what = expr.args[3]
            @match what begin
                for var_ in 1:length(seq_) loopbody__ end =>
                    :($Unrolled.@unroll_loop(for $var in 1:$(seq_type_length(seq));
                                             $(loopbody...) end))
                for var_ in 1:size(seq_, dim_) loopbody__ end =>
                    :($Unrolled.@unroll_loop(for $var in 1:$(seq_type_size(seq, dim));
                                          $(loopbody...) end))
                for var_ in seq_ loopbody__ end =>
                    :($Unrolled.@unroll_loop($(seq_type(seq)),
                                             for $var in $seq; $(loopbody...) end))
                any_ => error("Cannot @unroll $what")
            end
        else
            expr
        end
    end
    # We walk over every expression in the function body, and replace the `@unroll`
    # loops with macros that will perform the actual unrolling (we use intermediate macros
    # for sanity)
    expansion = postwalk(process, body)
    exp_fun = Symbol(fname, :_unrolled_expansion_)
    return esc(quote
        # The expansion function (for easy calling)
        Base.@__doc__ function $exp_fun($(all_args...))
            $(Expr(:quote, expansion))
        end
        @generated function $fname($(args...); $(kwargs...)) where {$(di[:whereparams]...)}
            $exp_fun($(all_args...))
        end
        $Unrolled.expansion_funs[$fname] = $exp_fun
    end)
end

macro code_unrolled(expr)
    @assert(@capture(expr, f_(args__)))
    ar = gensym()
    esc(quote
        $ar = [$(args...)]
        macroexpand(@__MODULE__, $Unrolled.expansion_funs[$f](map(typeof, $ar)...))
    end)
end

################################################################################

@generated function unrolled_map(f, seq) 
    :(tuple($((:(f(seq[$i])) for i in 1:type_length(seq))...)))
end
@generated function unrolled_map(f::F, seq1, seq2) where F
    @assert type_length(seq1) == type_length(seq2)
    :(tuple($((:(f(seq1[$i], seq2[$i])) for i in 1:type_length(seq1))...)))
end

@unroll function unrolled_foreach(f, seq)
    @unroll for x in seq; f(x) end
end

@generated function unrolled_reduce(f, v0, seq) 
    niter = type_length(seq)
    expand(i) = i == 0 ? :v0 : :(f(seq[$i], $(expand(i-1))))
    return expand(niter)
end

function _unrolled_filter(f, tup)
    :($([Expr(:(...), :(f(tup[$i]) ? (tup[$i],) : ()))
         for i in 1:type_length(tup)]...),)
end
@generated unrolled_filter(f, tup) = _unrolled_filter(f, tup)
unrolled_intersect(tup1, tup2) = unrolled_filter(x->x in tup2, tup1)
unrolled_setdiff(tup1, tup2) = unrolled_filter(!(x->x in tup2), tup1)
unrolled_union() = ()
unrolled_union(tup1) = tup1
unrolled_union(tup1, tup2) = (tup1..., unrolled_setdiff(tup2, tup1)...)
unrolled_union(tup1, tup2, tupn...) =
    unrolled_reduce(unrolled_union, tup1, (tup2, tupn...))
""" `unrolled_in(obj, tup)` is like `in`. Beware that its return type is not
always known - see #21322 """
@inline @unroll function unrolled_in(obj, tup)
    @unroll for x in tup
        if obj == x
            return true
        end
    end
    return false
end

@unroll function unrolled_all(f, tup)
    @unroll for x in tup
        if !f(x)
            return false
        end
    end
    return true
end

@unroll function unrolled_any(f, tup)
    @unroll for x in tup
        if f(x)
            return true
        end
    end
    return false
end
    

end # module
