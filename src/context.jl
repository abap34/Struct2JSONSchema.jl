const JSONScalar = Union{String,Int,Float64,Bool,Nothing}
const SymbolPath = Tuple{Vararg{Symbol}}

struct AbstractSpec
    variants::Vector{DataType}
    discr_key::String
    tag_value::Dict{DataType,JSONScalar}
    require_discr::Bool
end

mutable struct SchemaContext
    defs::Dict{String,Dict{String,Any}}
    key_of::IdDict{Any,String}
    visited::Set{Any}
    abstract_specs::IdDict{DataType,AbstractSpec}
    overrides::IdDict{DataType,Function}
    field_overrides::IdDict{Tuple{DataType,Symbol},Function}
    optional_fields::IdDict{DataType,Set{Symbol}}
    path::Vector{Symbol}
    unknowns::Set{Tuple{Any,SymbolPath}}
    auto_optional_union_nothing::Bool
    auto_optional_union_missing::Bool
    verbose::Bool
end

function SchemaContext(;
    auto_optional_union_nothing::Bool=false,
    auto_optional_union_missing::Bool=false,
    verbose::Bool=false
)
    SchemaContext(
        Dict{String,Dict{String,Any}}(),
        IdDict{Any,String}(),
        Set{Any}(),
        IdDict{DataType,AbstractSpec}(),
        IdDict{DataType,Function}(),
        IdDict{Tuple{DataType,Symbol},Function}(),
        IdDict{DataType,Set{Symbol}}(),
        Symbol[],
        Set{Tuple{Any,SymbolPath}}(),
        auto_optional_union_nothing,
        auto_optional_union_missing,
        verbose
    )
end

function clone_context(ctx::SchemaContext)
    SchemaContext(
        Dict{String,Dict{String,Any}}(),
        ctx.key_of,
        Set{Any}(),
        ctx.abstract_specs,
        ctx.overrides,
        ctx.field_overrides,
        ctx.optional_fields,
        Symbol[],
        Set{Tuple{Any,SymbolPath}}(),
        ctx.auto_optional_union_nothing,
        ctx.auto_optional_union_missing,
        ctx.verbose
    )
end

path_to_string(path::Union{Vector{Symbol},SymbolPath}) = isempty(path) ? "<root>" : join(string.(path), ".")

function record_unknown!(ctx::SchemaContext, T; message::Union{Nothing,String}=nothing)
    if T === Any
        return
    end
    push!(ctx.unknowns, (T, Tuple(ctx.path)))
    if message !== nothing
        msg = "$(message) at path $(path_to_string(ctx.path))"
        if ctx.verbose
            @info msg
        else
            @warn msg
        end
    end
end

function h(T::Type)::String
    repr_bytes = collect(codeunits(repr(T)))
    hash_value = UInt64(hash(T))
    hash_bytes = reinterpret(UInt8, [hash_value])
    combined = Vector{UInt8}(undef, length(hash_bytes) + length(repr_bytes))
    copyto!(combined, 1, hash_bytes, 1, length(hash_bytes))
    copyto!(combined, length(hash_bytes) + 1, repr_bytes, 1, length(repr_bytes))
    bytes2hex(sha256(combined))
end

function k(T::Type, ctx::SchemaContext)::String
    get!(ctx.key_of, T) do
        "$(repr(T))__$(h(T)[1:16])"
    end
end

reference(T::Type, ctx::SchemaContext) = Dict("\$ref" => "#/\$defs/$(k(T, ctx))")

function with_path(f::Function, ctx::SchemaContext, sym::Symbol)
    push!(ctx.path, sym)
    try
        return f()
    finally
        pop!(ctx.path)
    end
end
