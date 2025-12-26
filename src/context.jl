const JSONScalar = Union{String, Int, Float64, Bool, Nothing}
const SymbolPath = Tuple{Vararg{Symbol}}

mutable struct GenerationOptions
    auto_fielddoc::Bool
    auto_optional_union_nothing::Bool
    auto_optional_union_missing::Bool
    verbose::Bool
end

struct FieldMetadata
    optional_fields::IdDict{DataType, Set{Symbol}}
    skip_fields::IdDict{DataType, Set{Symbol}}
    descriptions::IdDict{Tuple{DataType, Symbol}, String}
end

FieldMetadata() = FieldMetadata(
    IdDict{DataType, Set{Symbol}}(),
    IdDict{DataType, Set{Symbol}}(),
    IdDict{Tuple{DataType, Symbol}, String}()
)

mutable struct CurrentState
    type::Union{Nothing, Type}
    parent::Union{Nothing, Type}
    field::Union{Nothing, Symbol}
end

CurrentState() = CurrentState(nothing, nothing, nothing)

"""
    SchemaContext

Holds all state required while generating JSON Schemas.
The context tracks `\$defs`, previously computed keys, the
current traversal path, override registrations, and knobs
for auto-detecting optional fields. Construct a context
with [`SchemaContext()`](@ref) and pass it to the API helpers.
"""
mutable struct SchemaContext
    defs::Dict{String, Dict{String, Any}}
    key_of::IdDict{Any, String}
    visited::Set{Any}
    path::Vector{Symbol}
    unknowns::Set{Tuple{Any, SymbolPath}}
    field_metadata::FieldMetadata
    options::GenerationOptions
    current::CurrentState
    overrides::Vector{Function}
end

"""
    SchemaContext(; auto_optional_union_nothing=false,
                    auto_optional_union_missing=false,
                    auto_fielddoc=true,
                    verbose=false)

Create a fresh schema generation context. Optional fields can
be inferred when `auto_optional_union_nothing` or
`auto_optional_union_missing` is true. When `auto_fielddoc` is true
(default), field docstrings are automatically extracted using
`REPL.fielddoc`. When `verbose` is true the generator emits
`@info`/`@warn` logs for unknown types and failed overrides.
"""
function SchemaContext(;
        auto_optional_union_nothing::Bool = false,
        auto_optional_union_missing::Bool = false,
        auto_fielddoc::Bool = true,
        verbose::Bool = false
    )
    return SchemaContext(
        Dict{String, Dict{String, Any}}(),
        IdDict{Any, String}(),
        Set{Any}(),
        Symbol[],
        Set{Tuple{Any, SymbolPath}}(),
        FieldMetadata(),
        GenerationOptions(auto_fielddoc, auto_optional_union_nothing, auto_optional_union_missing, verbose),
        CurrentState(),
        Function[]
    )
end

function clone_context(ctx::SchemaContext)
    return SchemaContext(
        Dict{String, Dict{String, Any}}(),
        ctx.key_of,
        Set{Any}(),
        Symbol[],
        Set{Tuple{Any, SymbolPath}}(),
        ctx.field_metadata,
        ctx.options,
        CurrentState(),
        ctx.overrides
    )
end

# Accessor utilities for backward compatibility and convenience
current_type(ctx::SchemaContext) = ctx.current.type
current_parent(ctx::SchemaContext) = ctx.current.parent
current_field(ctx::SchemaContext) = ctx.current.field

set_current_type!(ctx::SchemaContext, T) = (ctx.current.type = T)
set_current_parent!(ctx::SchemaContext, T) = (ctx.current.parent = T)
set_current_field!(ctx::SchemaContext, f) = (ctx.current.field = f)

optional_fields(ctx::SchemaContext) = ctx.field_metadata.optional_fields
skip_fields(ctx::SchemaContext) = ctx.field_metadata.skip_fields
field_descriptions(ctx::SchemaContext) = ctx.field_metadata.descriptions

is_verbose(ctx::SchemaContext) = ctx.options.verbose
auto_fielddoc(ctx::SchemaContext) = ctx.options.auto_fielddoc
auto_optional_union_nothing(ctx::SchemaContext) = ctx.options.auto_optional_union_nothing
auto_optional_union_missing(ctx::SchemaContext) = ctx.options.auto_optional_union_missing

path_to_string(path::Union{Vector{Symbol}, SymbolPath}) = isempty(path) ? "<root>" : join(string.(path), ".")

function record_unknown!(ctx::SchemaContext, T; message::Union{Nothing, String} = nothing)
    if T === Any
        return
    end
    push!(ctx.unknowns, (T, Tuple(ctx.path)))
    return if message !== nothing && is_verbose(ctx)
        msg = "$(message) at path $(path_to_string(ctx.path))"
        @info msg
    end
end

# Check if a type has been recorded as unknown
is_unknown_type(ctx::SchemaContext, T) = any(entry[1] === T for entry in ctx.unknowns)

h(T::Type) = string(hash(T), base = 16, pad = 16)

function k(T::Type, ctx::SchemaContext)
    return get!(ctx.key_of, T) do
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
