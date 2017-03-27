# Unrolled

[![Build Status](https://travis-ci.org/cstjean/Unrolled.jl.svg?branch=master)](https://travis-ci.org/cstjean/Unrolled.jl)

[![Coverage Status](https://coveralls.io/repos/cstjean/Unrolled.jl/badge.svg?branch=master&service=github)](https://coveralls.io/github/cstjean/Unrolled.jl?branch=master)

[![codecov.io](http://codecov.io/github/cstjean/Unrolled.jl/coverage.svg?branch=master)](http://codecov.io/github/cstjean/Unrolled.jl?branch=master)

Unrolled.jl provides a macro to unroll loops where the type-length is known at
compile-time. This can significantly improve performance and type-stability. For example, 

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

`@unroll` works by generating a separate function for each type (this may sound expensive,
but it's what Julia does all the time anyway). This is why we need (at least) two
`@unroll`:
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
function my_sum_but_last(seq)
    return _do_sum(seq[1:end-1])
end

my_sum_but_last((1,20,3))    # 21
```
