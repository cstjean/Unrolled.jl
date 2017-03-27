module Unrolled

using MacroTools
using MacroTools: prewalk, postwalk

export @unroll, @code_unrolled

const expansion_funs = Dict{Function, Function}()

macro unroll_loop(niter_type::Type, loop)
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
    exprs = [:(let $var = $seq[$i]; $(loopbody...) end) for i in 1:niter]
    return esc(quote $(exprs...) end)
end

type_length{T<:Tuple}(tup::Type{T}) = length(tup.parameters)
# Default fall-back
type_length(typ::Type) = length(typ)

""" `function_argument_name(arg_expr)`

Returns the name (as a symbol) of this argument, where arg_expr is whatever can
be put in a function definition's argument list (eg. `len::Int=5`) """
function function_argument_name(arg_expr)
    if isa(arg_expr, Expr) && arg_expr.head == :kw
        name = arg_expr.args[1]
    elseif @capture(arg_expr, name_::type_)
        name
    else
        name = arg_expr
    end
    @assert isa(name, Symbol)
    name
end

macro unroll(fundef)
    # This macro will turn the function definition into a generated function.
    @assert(@capture(fundef, function fname_(args__) body__ end),
            "`@unroll` must precede a function definition")
    function seq_type(seq_var)
        @assert(any([function_argument_name(arg) == seq_var for arg in args]),
                "Can only unroll a loop over one of the function's arguments")
        return Expr(:($), seq_var)
    end
    function process(expr)
        if @capture(expr, @unroll(what_))
            @match what begin
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
    new_body = [postwalk(process, bexpr) for bexpr in body]
    expansion = :(begin $(new_body...) end)
    exp_fun = Symbol(fname, :_unrolled_expansion_)
    return esc(quote
        # The expansion function (for easy calling)
        function $exp_fun($(args...))
            $(Expr(:quote, expansion))
        end
        @generated function $fname($(args...))
            $exp_fun($(args...))
        end
        $Unrolled.expansion_funs[$fname] = $exp_fun
    end)
end

macro code_unrolled(expr)
    @assert(@capture(expr, f_(args__)))
    ar = gensym()
    esc(quote
        $ar = [$(args...)]
        macroexpand($Unrolled.expansion_funs[$f](map(typeof, $ar)...))
    end)
end

end # module
