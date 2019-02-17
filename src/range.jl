export FixedRange, FixedEnd, @fixed_range

""" `FixedRange{A, B}()` is like `UnitRange{Int64}(A, B)`, but the bounds are encoded
in the type. """
struct FixedRange{A, B} end
""" `FixedRange{2, FixedEnd()}()` behaves like a type-stable 2:end """
struct FixedEnd{N} end
FixedEnd() = FixedEnd{0}()

Unrolled.type_length(::Type{FixedRange{A, B}}) where {A, B} = B - A + 1
Base.length(fr::FixedRange{A, B}) where {A, B} = B - A + 1
Base.maximum(fr::FixedRange{A, B}) where {A, B} = B::Int
Base.minimum(fr::FixedRange{A, B}) where {A, B} = A::Int
Base.getindex(fr::FixedRange, i::Int) = minimum(fr) + i - 1

Base.iterate(fr::FixedRange, state=minimum(fr)) =
    state > maximum(fr) ? nothing : (state, state+1)
Base.lastindex(fr::FixedRange) = length(fr)

replace_end(::FixedEnd{N}, ::Type{SEQ}) where {N, SEQ} = type_length(SEQ) - N
replace_end(n::Int, ::Type) = n

@generated Base.getindex(seq, ::FixedRange{A, B}) where {A, B} =
    :(tuple($((:(seq[$i]) for i in replace_end(A, seq):replace_end(B, seq))...)))

""" `@fixed_range 3:10` behaves like the standard range `3:10`, but is stored within
the type system, so that `some_tuple[@fixed_range 3:10]` is type-stable. Also supports
`some_tuple[@fixed_range 3:end-5]` """
macro fixed_range(r::Expr)
    process(x::Int) = x
    process(x::Symbol) = x === :end ? :($Unrolled.FixedEnd()) : x
    function process(x::Expr)
        @assert @capture(x, en_-m_) "`@fixed_range` macro cannot handle $x"
        @assert en === :end
        :(FixedEnd{$m}())
    end
    expand(a, b) = 
        :($Unrolled.FixedRange{$(process(a)), $(process(b))}())
    @match r begin
        a_:b_ => esc(expand(a, b))
        s_[a_:b_] => esc(:($s[$(expand(a, b))]))
        any_ => error("Bad @fixed_range")
    end
end
