using Unrolled
using Test
using StaticArrays
using MacroTools
using QuickTypes: type_parameters

# Check that we can extract argument names
@capture(:(function foo(a, b::Int, c=2; d::Int=4) end),
         (function foo(args__; kwargs__) end))
@test map(Unrolled.function_argument_name, vcat(args, kwargs)) == [:a, :b, :c, :d]

@unroll function my_sum(ss)
    total = zero(eltype(ss))
    @unroll for x in ss
        total += x
    end
    return total
end
@unroll function my_sum(; ss::Tuple=1)  # test kwargs
    total = zero(eltype(ss))
    @unroll for x in ss
        total += x
    end
    return total
end

@test my_sum((1,2,3)) == 6
@test my_sum([1,2,3]) == 6
@test my_sum(SVector(1,2,3)) == 6
@test my_sum(; ss=(1,2,3)) == 6

# Had to disable this test on 0.7. @test_throws looks broken?
# @test_throws AssertionError @eval @unroll function my_sum(ss)
#     total = zero(eltype(ss))
#     @unroll for x in ss[1:end-1]
#         total += x
#     end
#     return total
# end

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

@test my_sum_but_last((1,20,3)) == 21

# Check that unrolled_union & co are correct and type-stable
struct MyVal{T} end
# Otherwise it's not type-stable. Perhaps it should defined in Base for all singleton
# types.
@generated Base.in(val::MyVal, tup::Tuple) = val in type_parameters(tup)

@test (@inferred(unrolled_union((MyVal{1}(), MyVal{2}()), (MyVal{2}(), MyVal{0}()))) ==
       (MyVal{1}(), MyVal{2}(), MyVal{0}()))
@test (@inferred(unrolled_intersect((MyVal{1}(), MyVal{2}()), (MyVal{2}(), MyVal{0}())))==
       (MyVal{2}(),))
@test (@inferred(unrolled_setdiff((MyVal{1}(), MyVal{2}()), (MyVal{2}(), MyVal{0}()))) ==
       (MyVal{1}(),))
@test (@inferred(unrolled_union((MyVal{1}(), MyVal{2}()),
                                (MyVal{2}(), MyVal{0}()),
                                (MyVal{10}(),))) ==
       (MyVal{10}(), MyVal{2}(), MyVal{0}(), MyVal{1}()))
@test @inferred(unrolled_reduce((+), 0, unrolled_map(abs, (1,2,-3,7)))) == 13

const tupl = (1,2,3,4,5.0,6,7...)
@test @inferred(getindex(tupl, FixedRange{4, 5}())) == (4, 5.0)
@test @inferred(getindex(tupl, FixedRange{4, FixedEnd{1}()}())) == (4, 5.0, 6)

f(tupl) = @fixed_range(tupl[4:end-1])
@test @inferred(f(tupl)) == (4, 5.0, 6)

@unroll function summer(tup, t::Type{T}) where T
    s = zero(T)
    @unroll for x in tup
        s += x
    end
    s
end

@test summer((1,2,3), Float64) === 6.0

x = [0.0]
unrolled_foreach((1,2,3, 1.0)) do y
    x[1] += y
end
@test x[1] == 7.0

# Issue #6
@unroll function sim_gbm(state, sim_T, drift, vol, ts::Tuple, ::Val{log_scale}) where log_scale
    log_scale && (state = log.(state))
    @unroll for _ in 1:length(ts)
        if log_scale
            state = sim_gbm_euler_step(state, drift, vol_matrix, dt(ts))
        else
            state = sim_gbm_log_scale_euler_step(state, drift, vol_matrix, dt(ts))
        end
    end
    return log_scale ? exp.(state) : state
end

# Unrolling with a sized argument
struct CartesianIndexSpace{dims} <: AbstractArray{Int, 2}; end
Base.size(cis::Type{CartesianIndexSpace{dims}}) where {dims} = dims
Base.size(cis::Type{<:CartesianIndexSpace}, i::Integer) = size(cis)[i]
Base.size(cis::CartesianIndexSpace) = size(typeof(cis))

@unroll function do_count(cis)
    n = 0
    @unroll for i = 1:size(cis, 2)
        n += 1
    end
    n
end
@test do_count(CartesianIndexSpace{(1,4)}()) == 4
