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

const SCHEMA_REF_KEY = "\$ref"
const SCHEMA_DEFS_KEY = "\$defs"
const SCHEMA_DEFS_PREFIX = "#/\$defs/"

function is_schema_ref(s::AbstractString)::Bool
    return startswith(s, SCHEMA_DEFS_PREFIX)
end

function extract_ref_key(ref::AbstractString)::String
    @assert is_schema_ref(ref) "Reference must start with $(SCHEMA_DEFS_PREFIX)"
    return ref[9:end]
end

function make_ref(key::AbstractString)::String
    return SCHEMA_DEFS_PREFIX * key
end

function has_schema_ref(d::AbstractDict)::Bool
    return haskey(d, SCHEMA_REF_KEY) && d[SCHEMA_REF_KEY] isa String && is_schema_ref(d[SCHEMA_REF_KEY])
end

function get_ref_key(d::AbstractDict)::Union{String, Nothing}
    return has_schema_ref(d) ? extract_ref_key(d[SCHEMA_REF_KEY]) : nothing
end
