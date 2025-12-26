const JSONScalar = Union{String, Int, Float64, Bool, Nothing}
const SymbolPath = Tuple{Vararg{Symbol}}

"""
    SchemaContext

Holds all state required while generating JSON Schemas.
The context tracks `\$defs`, previously computed keys, the
current traversal path, override registrations, and knobs
for auto-detecting optional fields. Construct a context
with [`SchemaContext()`](@ref) and pass it to the API helpers.
"""
mutable struct SchemaContext
    defs::Dict{String, Dict{String, Any}}            # accumulated $defs entries
    key_of::IdDict{Any, String}                      # stable type→key cache
    visited::Set{Any}                                # recursion guard for define!
    optional_fields::IdDict{DataType, Set{Symbol}}   # explicit optional field hints
    field_descriptions::IdDict{Tuple{DataType,Symbol},String}  # field descriptions
    auto_fielddoc::Bool                              # auto extract REPL.fielddoc?
    path::Vector{Symbol}                             # current traversal path
    unknowns::Set{Tuple{Any, SymbolPath}}            # unsupported type traces
    unknown_types::Set{Any}                          # cache of types that yielded empty schemas
    auto_optional_union_nothing::Bool                # auto Union{T,Nothing}? flag
    auto_optional_union_missing::Bool                # auto Union{T,Missing}? flag
    verbose::Bool                                    # emit @info/@warn logs?
    current_type::Union{Nothing, Type}               # type currently being emitted
    current_parent::Union{Nothing, Type}             # parent struct during field walk
    current_field::Union{Nothing, Symbol}            # field currently being emitted
    overrides::Vector{Function}                      # registered override predicates
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
        IdDict{DataType, Set{Symbol}}(),
        IdDict{Tuple{DataType,Symbol},String}(),
        auto_fielddoc,
        Symbol[],
        Set{Tuple{Any, SymbolPath}}(),
        Set{Any}(),
        auto_optional_union_nothing,
        auto_optional_union_missing,
        verbose,
        nothing,
        nothing,
        nothing,
        Function[]
    )
end

function clone_context(ctx::SchemaContext)
    return SchemaContext(
        Dict{String, Dict{String, Any}}(),
        ctx.key_of,
        Set{Any}(),
        ctx.optional_fields,
        ctx.field_descriptions,
        ctx.auto_fielddoc,
        Symbol[],
        Set{Tuple{Any, SymbolPath}}(),
        Set{Any}(),
        ctx.auto_optional_union_nothing,
        ctx.auto_optional_union_missing,
        ctx.verbose,
        nothing,
        nothing,
        nothing,
        ctx.overrides
    )
end

path_to_string(path::Union{Vector{Symbol}, SymbolPath}) = isempty(path) ? "<root>" : join(string.(path), ".")

function record_unknown!(ctx::SchemaContext, T; message::Union{Nothing, String} = nothing)
    if T === Any
        return
    end
    push!(ctx.unknowns, (T, Tuple(ctx.path)))
    push!(ctx.unknown_types, T)
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

function with_path(f::Function, ctx::SchemaContext, sym::Symbol)
    push!(ctx.path, sym)
    try
        return f()
    finally
        pop!(ctx.path)
    end
end
