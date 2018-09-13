# Unrolled

[![Build Status](https://travis-ci.org/cstjean/Unrolled.jl.svg?branch=master)](https://travis-ci.org/cstjean/Unrolled.jl)

[![Coverage Status](https://coveralls.io/repos/cstjean/Unrolled.jl/badge.svg?branch=master&service=github)](https://coveralls.io/github/cstjean/Unrolled.jl?branch=master)

[![codecov.io](http://codecov.io/github/cstjean/Unrolled.jl/coverage.svg?branch=master)](http://codecov.io/github/cstjean/Unrolled.jl?branch=master)

Unrolled.jl provides functions to unroll loops on sequences whose length is known at
compile-time (mostly `Tuple` and [`StaticArrays`](https://github.com/JuliaArrays/StaticArrays.jl)). This can significantly improve performance and type-stability.

# The `@unroll` macro

```julia
julia> using Unrolled

julia> @unroll function my_sum(seq)
       	   # More on why we need @unroll twice later.
	   total = zero(eltype(seq))
           @unroll for x in seq
               total += x
           end
           return total
       end
my_sum_unrolled_expansion_ (generic function with 1 method)

julia> my_sum((1, 2, 3))
6
```

To see what code will be executed,

```julia
# Tuples are unrolled
julia> @code_unrolled my_sum((1,2,3))
quote  
    total = zero(eltype(seq))
    begin  
        let x = seq[1]
            total += x
        end
        let x = seq[2]
            total += x
        end
        let x = seq[3]
            total += x
        end
    end
    return total
end

# But not vectors, since their length is not part of Vector{Int}
julia> @code_unrolled my_sum([1,2,3])
quote
    total = zero(eltype(seq))
    for x = seq
        total += x
    end
    return total
end
```

All types for which `length` is implemented will be unrolled (this includes the fixed-size
vectors from [StaticArrays.jl](https://github.com/JuliaArrays/StaticArrays.jl) and
[FixedSizeArrays.jl](https://github.com/SimonDanisch/FixedSizeArrays.jl))

## Usage

`@unroll` works by generating (at compile-time) a separate function for each type
combination. This is why we need (at least) two `@unroll`:
 - One in front of the `function` definition
 - One in front of each `for` loop to be unrolled

`@unroll` can only unroll loops over the arguments of the function. For instance, this
is an error:

```julia
# Sum every number in seq except the last one
@unroll function my_sum_but_last(seq)
    total = zero(eltype(seq))
    @unroll for x in seq[1:end-1]   # Bad!
        total += x
    end
    return total
end
```

An easy work-around is to use a helper function

```julia
@unroll function _do_sum(sub_seq) # helper for my_sum_but_last
    total = zero(eltype(sub_seq))
    @unroll for x in sub_seq
        total += x
    end
    return total
end

# Sum every number in seq except the last one
my_sum_but_last(seq) = _do_sum(seq[1:end-1])

my_sum_but_last((1,20,3))    # 21
```

As a special case, `@unroll` also supports iteration over `1:some_argument`

```julia
@unroll function foo(tup)
    @unroll for x in 1:length(tup)
        println(x)
    end
end
foo((:a, :b, :c))
> 1
> 2
> 3
```

# Unrolled functions

Unrolled.jl also provides the following unrolled functions, defined on `Tuple`s only.

```
unrolled_map, unrolled_reduce, unrolled_in, unrolled_any, unrolled_all, unrolled_foreach
```

and

```
unrolled_filter, unrolled_intersect, unrolled_union, unrolled_setdiff
```

The functions in this second group will only perform well when the computations can be
performed entirely at compile-time (using the types). For example,
`unrolled_filter(x->isa(x, Int), some_tuple)`.

In this other example, `unrolled_filter` is compiled to a constant:

```julia
using Unrolled, Base.Test

@generated positive{N}(::Val{N}) = N > 0
@inferred unrolled_filter(positive, (Val{1}(), Val{3}(), Val{-1}(), Val{5}()))
```

# Note on `Val`

In my experience, `Val` objects are more type-stable than `Val` types. Favor
`Val{:x}()` over `Val{:x}`.
