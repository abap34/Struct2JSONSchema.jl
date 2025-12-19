const JSONScalar = Union{String, Int, Float64, Bool, Nothing}
const SymbolPath = Tuple{Vararg{Symbol}}

struct AbstractSpec
    variants::Vector{DataType}
    discr_key::String
    tag_value::Dict{DataType, JSONScalar}
    require_discr::Bool
end

"""
    SchemaContext

Mutable container that tracks schema definitions, overrides, and diagnostic
state while generating JSON Schemas.
"""
mutable struct SchemaContext
    defs::Dict{String, Dict{String, Any}}
    key_of::IdDict{Any, String}
    visited::Set{Any}
    abstract_specs::IdDict{DataType, AbstractSpec}
    overrides::IdDict{DataType, Function}
    field_overrides::IdDict{Tuple{DataType, Symbol}, Function}
    optional_fields::IdDict{DataType, Set{Symbol}}
    path::Vector{Symbol}
    unknowns::Set{Tuple{Any, SymbolPath}}
    auto_optional_union_nothing::Bool
    auto_optional_union_missing::Bool
    verbose::Bool
end

"""
    SchemaContext(; auto_optional_union_nothing=false,
                   auto_optional_union_missing=false,
                   verbose=false)

Create a new schema generation context. Contexts are safe to reuse across
multiple calls to `generate_schema!` and hold globally registered overrides and
discriminator metadata.

# Keyword Arguments
- `auto_optional_union_nothing`: treat `Union{T, Nothing}` fields as optional.
- `auto_optional_union_missing`: treat `Union{T, Missing}` fields as optional.
- `verbose`: emit informational logs for unknown types or override failures.
"""
function SchemaContext(;
        auto_optional_union_nothing::Bool = false,
        auto_optional_union_missing::Bool = false,
        verbose::Bool = false
    )
    return SchemaContext(
        Dict{String, Dict{String, Any}}(),
        IdDict{Any, String}(),
        Set{Any}(),
        IdDict{DataType, AbstractSpec}(),
        IdDict{DataType, Function}(),
        IdDict{Tuple{DataType, Symbol}, Function}(),
        IdDict{DataType, Set{Symbol}}(),
        Symbol[],
        Set{Tuple{Any, SymbolPath}}(),
        auto_optional_union_nothing,
        auto_optional_union_missing,
        verbose
    )
end

# Clone `ctx`, preserving overrides but clearing definitions and diagnostics.
function clone_context(ctx::SchemaContext)
    return SchemaContext(
        Dict{String, Dict{String, Any}}(),
        ctx.key_of,
        Set{Any}(),
        ctx.abstract_specs,
        ctx.overrides,
        ctx.field_overrides,
        ctx.optional_fields,
        Symbol[],
        Set{Tuple{Any, SymbolPath}}(),
        ctx.auto_optional_union_nothing,
        ctx.auto_optional_union_missing,
        ctx.verbose
    )
end

path_to_string(path::Union{Vector{Symbol}, SymbolPath}) = isempty(path) ? "<root>" : join(string.(path), ".")

# Track that `T` could not be represented under the current path, optionally logging.
function record_unknown!(ctx::SchemaContext, T; message::Union{Nothing, String} = nothing)
    if T === Any
        return
    end
    push!(ctx.unknowns, (T, Tuple(ctx.path)))
    return if message !== nothing && ctx.verbose
        msg = "$(message) at path $(path_to_string(ctx.path))"
        @info msg
    end
end

h(T::Type) = string(hash(T), base = 16, pad = 16)

function k(T::Type, ctx::SchemaContext)
    return get!(ctx.key_of, T) do
        "$(repr(T))__$(h(T)[1:16])"
    end
end

reference(T::Type, ctx::SchemaContext) = Dict("\$ref" => "#/\$defs/$(k(T, ctx))")

# Temporarily push `sym` onto the path stack while evaluating `f`.
function with_path(f::Function, ctx::SchemaContext, sym::Symbol)
    push!(ctx.path, sym)
    try
        return f()
    finally
        pop!(ctx.path)
    end
end
