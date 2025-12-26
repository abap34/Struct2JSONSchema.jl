include("context.jl")
using REPL

# Normalize unions and `UnionAll` types before looking up schema definitions.
function normalize_type(T::Type, ctx::SchemaContext)::Type
    if T isa UnionAll
        record_unknown!(ctx, T; message = "UnionAll type $T encountered. Using Any")
        return Any
    elseif T isa Union
        return T
    end
    return T
end

# Define `T` if it has not been seen yet, wiring recursion guards along the way.
function define!(T::Type, ctx::SchemaContext)
    Tn = normalize_type(T, ctx)
    key = k(Tn, ctx)
    if haskey(ctx.defs, key)
        if Tn in ctx.unknown_types
            record_unknown!(ctx, Tn)
        end
        return Tn
    end

    ctx.defs[key] = Dict{String, Any}()
    push!(ctx.visited, Tn)
    try
        ctx.defs[key] = build_def_safe(Tn, ctx)
    catch err
        ctx.defs[key] = Dict{String, Any}()
        record_unknown!(ctx, Tn; message = "Unexpected error generating schema for $Tn ($err)")
        if ctx.verbose
            @warn "Unexpected error generating schema for $Tn at path $(path_to_string(ctx.path))" exception = (err, catch_backtrace())
        end
    finally
        delete!(ctx.visited, Tn)
    end
    return Tn
end

# Try every registered override until one returns a schema `Dict`.
function apply_overrides(ctx::SchemaContext; location::Union{Nothing, String} = nothing)
    for override_fn in ctx.overrides
        try
            result = override_fn(ctx)
            if result !== nothing
                return result
            end
        catch err
            if ctx.verbose
                loc = location === nothing ? path_to_string(ctx.path) : location
                @warn "Override threw an error at $loc. Falling back to default." exception = (err, catch_backtrace())
            end
        end
    end
    return nothing
end

# Build the definition for `T`, honoring overrides and falling back to defaults.
function build_def_safe(T::Type, ctx::SchemaContext)
    old_type = ctx.current_type
    ctx.current_type = T
    try
        override = apply_overrides(ctx; location = "type $(repr(T))")
        if override !== nothing
            return override
        end

        if isabstracttype(T)
            record_unknown!(ctx, T; message = "Abstract type $T has no registered discriminator. Using empty schema")
            return Dict{String, Any}()
        end

        return default_generate(T, ctx)
    finally
        ctx.current_type = old_type
    end
end

function string_schema(;
        format::Union{Nothing, String} = nothing,
        min_length::Union{Nothing, Int} = nothing,
        max_length::Union{Nothing, Int} = nothing
    )::Dict{String, Any}
    schema = Dict{String, Any}("type" => "string")
    if format !== nothing
        schema["format"] = format
    end
    if min_length !== nothing
        schema["minLength"] = min_length
    end
    if max_length !== nothing
        schema["maxLength"] = max_length
    end
    return schema
end

function number_schema()::Dict{String, Any}
    return Dict{String, Any}("type" => "number")
end

function schema_for_array(elem_type::Type, ctx::SchemaContext; unique::Bool = false)
    items_schema = with_path(ctx, Symbol("<items>")) do
        normalized = define!(elem_type, ctx)
        reference(normalized, ctx)
    end
    schema = Dict(
        "type" => "array",
        "items" => items_schema
    )
    if unique
        schema["uniqueItems"] = true
    end
    return schema
end

function fixed_tuple_schema(params_raw, ctx::SchemaContext)
    n = length(params_raw)
    items = Vector{Dict{String, Any}}(undef, n)
    for (idx, elem_type) in enumerate(params_raw)
        items[idx] = with_path(ctx, Symbol("<tuple[$idx]>")) do
            normalized = define!(elem_type, ctx)
            reference(normalized, ctx)
        end
    end
    return Dict(
        "type" => "array",
        "prefixItems" => items,
        "minItems" => n,
        "maxItems" => n
    )
end

function ntuple_schema(N::Int, elem_type::Type, ctx::SchemaContext)
    items_schema = with_path(ctx, Symbol("<items>")) do
        normalized = define!(elem_type, ctx)
        reference(normalized, ctx)
    end
    return Dict(
        "type" => "array",
        "items" => items_schema,
        "minItems" => N,
        "maxItems" => N
    )
end

function dict_schema(T::Type, ctx::SchemaContext)
    values_schema = with_path(ctx, Symbol("<values>")) do
        val_type = T.parameters[2]
        normalized = define!(val_type, ctx)
        reference(normalized, ctx)
    end
    return Dict("type" => "object", "additionalProperties" => values_schema)
end

function namedtuple_schema(T::Type, ctx::SchemaContext)
    names, types = T.parameters
    n = length(names)
    properties = Dict{String, Any}()
    required = Vector{String}(undef, n)
    for (i, name) in enumerate(names)
        prop = with_path(ctx, name) do
            field_type = types.parameters[i]
            normalized = define!(field_type, ctx)
            reference(normalized, ctx)
        end
        properties[string(name)] = prop
        required[i] = string(name)
    end
    return Dict(
        "type" => "object",
        "properties" => properties,
        "required" => required,
        "additionalProperties" => false
    )
end

function union_schema(T::Type, ctx::SchemaContext)
    types = Base.uniontypes(T)
    n = length(types)
    schemas = Vector{Dict{String, Any}}(undef, n)
    for (i, U) in enumerate(types)
        schemas[i] = with_path(ctx, Symbol("<union[$i]>")) do
            normalized = define!(U, ctx)
            reference(normalized, ctx)
        end
    end
    return Dict("anyOf" => schemas)
end

function enum_schema(T::Type)
    values = [string(instance) for instance in instances(T)]
    return Dict("enum" => values)
end

# Get field description from manual registration or REPL.fielddoc auto-extraction
function get_field_description(T::Type, field::Symbol, ctx::SchemaContext)::Union{String,Nothing}
    # 1. Check explicit registration
    if haskey(ctx.field_descriptions, (T, field))
        return ctx.field_descriptions[(T, field)]
    end

    # 2. If auto_fielddoc disabled, return nothing
    if !ctx.auto_fielddoc
        return nothing
    end

    # 3. Try REPL.fielddoc extraction
    try
        doc = REPL.fielddoc(T, field)
        doc_str = string(doc)
        # Skip default messages
        if occursin("has field", doc_str) || occursin("has fields", doc_str)
            return nothing
        end
        return strip(doc_str)
    catch
        return nothing
    end
end

# Generate an object schema for `T`, evaluating overrides per field as needed.
function struct_schema(T::Type, ctx::SchemaContext)
    properties = Dict{String, Any}()
    required = String[]
    names = fieldnames(T)
    for (idx, name) in enumerate(names)
        field_type = fieldtype(T, idx)
        old_parent = ctx.current_parent
        old_field = ctx.current_field
        old_type = ctx.current_type
        ctx.current_parent = T
        ctx.current_field = name
        ctx.current_type = field_type
        try
            prop = with_path(ctx, name) do
                override = apply_overrides(ctx; location = "$(repr(T)).$(name)")
                if override !== nothing
                    return override
                end
                saved_parent = ctx.current_parent
                saved_field = ctx.current_field
                ctx.current_parent = nothing
                ctx.current_field = nothing
                try
                    # If field is optional and is Union{T, Nothing/Missing},
                    # generate schema for T only, not the full Union
                    schema_type = field_type
                    if should_be_optional(T, name, field_type, ctx)
                        schema_type = unwrap_optional_union(field_type)
                    end
                    normalized = define!(schema_type, ctx)
                    reference(normalized, ctx)
                finally
                    ctx.current_parent = saved_parent
                    ctx.current_field = saved_field
                end
            end

            # Check for field description
            description = get_field_description(T, name, ctx)
            if description !== nothing
                # If prop is just a $ref, wrap it in allOf to add description
                if haskey(prop, "\$ref") && length(prop) == 1
                    prop = Dict(
                        "allOf" => [prop],
                        "description" => description
                    )
                else
                    # Otherwise, add description directly
                    prop["description"] = description
                end
            end

            properties[string(name)] = prop

            if !should_be_optional(T, name, field_type, ctx)
                push!(required, string(name))
            end
        finally
            ctx.current_parent = old_parent
            ctx.current_field = old_field
            ctx.current_type = old_type
        end
    end
    return Dict(
        "type" => "object",
        "properties" => properties,
        "required" => required,
        "additionalProperties" => false
    )
end

function should_be_optional(T::DataType, field::Symbol, field_type::Type, ctx::SchemaContext)::Bool
    # 1. Explicit registration via ctx.optional_fields
    if haskey(ctx.optional_fields, T) && field in ctx.optional_fields[T]
        return true
    end

    # 2. Union{T, Nothing} auto-detection
    if ctx.auto_optional_union_nothing && is_union_with_nothing(field_type)
        return true
    end

    # 3. Union{T, Missing} auto-detection
    if ctx.auto_optional_union_missing && is_union_with_missing(field_type)
        return true
    end

    return false
end

function is_union_with_nothing(T::Type)::Bool
    T isa Union || return false
    types = Base.uniontypes(T)
    return Nothing in types && length(types) == 2
end

function is_union_with_missing(T::Type)::Bool
    T isa Union || return false
    types = Base.uniontypes(T)
    return Missing in types && length(types) == 2
end

function unwrap_optional_union(T::Type)::Type
    # Extract T from Union{T, Nothing} or Union{T, Missing}
    T isa Union || return T
    types = Base.uniontypes(T)
    length(types) == 2 || return T

    if Nothing in types
        return types[types .!== Nothing][1]
    elseif Missing in types
        return types[types .!== Missing][1]
    end

    return T
end

function primitive_schema(T::Type, _::SchemaContext)
    if T === Union{}
        return Dict("not" => Dict{String, Any}())
    elseif T === Tuple{}
        return Dict("type" => "array", "maxItems" => 0)
    elseif T isa Union
        return nothing
    elseif T === Bool
        return Dict("type" => "boolean")
    elseif T <: Integer && T !== Integer && T !== BigInt
        return Dict(
            "type" => "integer",
            "minimum" => typemin(T),
            "maximum" => typemax(T)
        )
    elseif T === BigInt || T === Integer
        return Dict("type" => "integer")
    elseif T <: AbstractFloat && !(T isa UnionAll)
        return number_schema()
    elseif T <: Rational
        return number_schema()
    elseif T <: Irrational
        return number_schema()
    elseif T <: AbstractString
        return string_schema()
    elseif T === Char
        return string_schema(min_length = 1, max_length = 1)
    elseif T === Symbol
        return string_schema()
    elseif T === Date
        return string_schema(format = "date")
    elseif T === DateTime
        return string_schema(format = "date-time")
    elseif T === Time
        return string_schema(format = "time")
    elseif T === Regex
        return string_schema(format = "regex")
    elseif T === VersionNumber
        return Dict("type" => "string", "pattern" => "^\\d+\\.\\d+\\.\\d+.*\$")
    elseif T === Nothing || T === Missing
        return Dict("type" => "null")
    elseif T === Any
        return Dict{String, Any}()
    end
    return nothing
end

function collection_schema(T::Type, ctx::SchemaContext)
    if T <: AbstractArray && !(T isa UnionAll)
        return schema_for_array(eltype(T), ctx)
    elseif T <: AbstractSet && !(T isa UnionAll)
        return schema_for_array(eltype(T), ctx; unique = true)
    elseif T <: Tuple && !(T isa UnionAll)
        params = T.parameters
        @assert length(params) >= 1 # Tuple{} is handled above
        if T <: NTuple && allequal(params)
            N = length(params)
            elem_type = params[1]
            return ntuple_schema(N, elem_type, ctx)
        else
            return fixed_tuple_schema(params, ctx)
        end
    elseif T <: NamedTuple && !(T isa UnionAll)
        return namedtuple_schema(T, ctx)
    elseif T <: AbstractDict && !(T isa UnionAll)
        return dict_schema(T, ctx)
    end
    return nothing
end

function composite_schema(T::Type, ctx::SchemaContext)
    if T isa Union
        return union_schema(T, ctx)
    elseif T <: Enum
        return enum_schema(T)
    elseif isconcretetype(T) && isstructtype(T)
        return struct_schema(T, ctx)
    end
    return nothing
end

function default_generate(T::Type, ctx::SchemaContext)::Dict{String, Any}
    schema = primitive_schema(T, ctx)
    schema !== nothing && return schema

    schema = collection_schema(T, ctx)
    schema !== nothing && return schema

    schema = composite_schema(T, ctx)
    schema !== nothing && return schema

    record_unknown!(ctx, T; message = "Type $T cannot be represented. Using empty schema")
    return Dict{String, Any}()
end

function generate_abstract_schema(
        variants::Vector{DataType},
        discr_key::String,
        tag_value::Dict{DataType, JSONScalar},
        require_discr::Bool,
        ctx::SchemaContext
    )
    n = length(variants)
    options = Vector{Dict{String, Any}}(undef, n)
    for (idx, variant) in enumerate(variants)
        normalized = define!(variant, ctx)
        base_ref = reference(normalized, ctx)
        discr_schema = Dict(
            "type" => "object",
            "properties" => Dict(discr_key => Dict("const" => tag_value[variant]))
        )
        if require_discr
            discr_schema["required"] = [discr_key]
        end
        options[idx] = Dict("allOf" => [base_ref, discr_schema])
    end
    return Dict("anyOf" => options)
end
