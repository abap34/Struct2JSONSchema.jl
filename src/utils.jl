function is_union_with_nothing(T::Type)::Bool
    T isa Union || return false
    return Nothing ∈ Base.uniontypes(T)
end

function is_union_with_missing(T::Type)::Bool
    T isa Union || return false
    return Missing ∈ Base.uniontypes(T)
end

# Extract T from Union{T, Nothing, Missing}
function unwrap_optional_union(T::Type)::Type
    @assert is_union_with_nothing(T) || is_union_with_missing(T)
    types = Base.uniontypes(T)
    return Union{filter(t -> t !== Nothing && t !== Missing, types)...}
end
