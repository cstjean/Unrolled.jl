export FixedRange

""" `FixedRange{A, B}()` is like `UnitRange{Int64}(A, B)`, but the bounds are encoded
in the type. """
struct FixedRange{A, B} end

Unrolled.type_length{A, B}(::Type{FixedRange{A, B}}) = B - A + 1
Base.length{A, B}(fr::FixedRange{A, B}) = B - A + 1
Base.maximum{A, B}(fr::FixedRange{A, B}) = B::Int
Base.minimum{A, B}(fr::FixedRange{A, B}) = A::Int
Base.getindex(fr::FixedRange, i::Int) = minimum(fr) + i - 1

Base.start(fr::FixedRange) = minimum(fr)
Base.done(fr::FixedRange, i::Int) = i > maximum(fr)
Base.next(fr::FixedRange, i::Int) = (i, i+1)
