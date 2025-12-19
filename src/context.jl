const JSONScalar = Union{String, Int, Float64, Bool, Nothing}
const SymbolPath = Tuple{Vararg{Symbol}}

mutable struct SchemaContext
    defs::Dict{String, Dict{String, Any}}
    key_of::IdDict{Any, String}
    visited::Set{Any}
    optional_fields::IdDict{DataType, Set{Symbol}}
    path::Vector{Symbol}
    unknowns::Set{Tuple{Any, SymbolPath}}
    auto_optional_union_nothing::Bool
    auto_optional_union_missing::Bool
    verbose::Bool
    current_type::Union{Nothing, Type}
    current_parent::Union{Nothing, Type}
    current_field::Union{Nothing, Symbol}
    overrides::Vector{Function}
end

function SchemaContext(;
        auto_optional_union_nothing::Bool = false,
        auto_optional_union_missing::Bool = false,
        verbose::Bool = false
    )
    return SchemaContext(
        Dict{String, Dict{String, Any}}(),
        IdDict{Any, String}(),
        Set{Any}(),
        IdDict{DataType, Set{Symbol}}(),
        Symbol[],
        Set{Tuple{Any, SymbolPath}}(),
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
        Symbol[],
        Set{Tuple{Any, SymbolPath}}(),
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
