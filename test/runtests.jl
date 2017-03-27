using Unrolled
using Base.Test
using StaticArrays

# write your own tests here
@unroll function my_sum(ss)
    total = zero(eltype(ss))
    @unroll for x in ss
        total += x
    end
    return total
end

@test my_sum((1,2,3)) == 6
@test my_sum([1,2,3]) == 6
@test my_sum(SVector(1,2,3)) == 6

@test_throws AssertionError @eval @unroll function my_sum(ss)
    total = zero(eltype(ss))
    @unroll for x in ss[1:end-1]
        total += x
    end
    return total
end

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
