include("context.jl")

function normalize_type(T::Type, ctx::SchemaContext)::Type
    if T isa UnionAll
        record_unknown!(ctx, T; message = "UnionAll type $T encountered. Using Any")
        return Any
    elseif T isa Union
        types = Base.uniontypes(T)
        if isempty(types)
            return Union{}
        elseif length(types) == 1
            return normalize_type(types[1], ctx)
        else
            return T
        end
    end
    return T
end

function define!(T::Type, ctx::SchemaContext)
    Tn = normalize_type(T, ctx)
    key = k(Tn, ctx)
    if haskey(ctx.defs, key)
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

function build_def_safe(T::Type, ctx::SchemaContext)
    if T isa DataType && haskey(ctx.overrides, T)
        try
            return ctx.overrides[T](ctx)
        catch err
            if ctx.verbose
                @warn "Override for $T at path $(path_to_string(ctx.path)) threw an error. Falling back to default." exception = (err, catch_backtrace())
            end
        end
    end

    if isabstracttype(T)
        if haskey(ctx.abstract_specs, T)
            return generate_abstract_schema(T, ctx)
        else
            record_unknown!(ctx, T; message = "Abstract type $T has no registered discriminator. Using empty schema")
            return Dict{String, Any}()
        end
    end

    return default_generate(T, ctx)
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

function number_schema(;
        minimum::Union{Nothing, Real} = nothing,
        maximum::Union{Nothing, Real} = nothing
    )::Dict{String, Any}
    schema = Dict{String, Any}("type" => "number")
    if minimum !== nothing
        schema["minimum"] = minimum
    end
    if maximum !== nothing
        schema["maximum"] = maximum
    end
    return schema
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

function vararg_tuple_schema(elem_type::Type, ctx::SchemaContext)
    items_schema = with_path(ctx, Symbol("<items>")) do
        normalized = define!(elem_type, ctx)
        reference(normalized, ctx)
    end
    return Dict("type" => "array", "items" => items_schema)
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
    if isempty(types)
        return Dict("not" => Dict{String, Any}())
    end
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

function struct_schema(T::Type, ctx::SchemaContext)
    properties = Dict{String, Any}()
    required = String[]
    names = fieldnames(T)
    for (idx, name) in enumerate(names)
        field_type = fieldtype(T, idx)

        # Check for field-level override
        if haskey(ctx.field_overrides, (T, name))
            prop = with_path(ctx, name) do
                ctx.field_overrides[(T, name)](ctx)
            end
        else
            prop = with_path(ctx, name) do
                normalized = define!(field_type, ctx)
                reference(normalized, ctx)
            end
        end

        properties[string(name)] = prop

        # Check if field should be optional
        if !should_be_optional(T, name, field_type, ctx)
            push!(required, string(name))
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
        return Dict("type" => "number")
    elseif T <: Rational
        return Dict("type" => "number")
    elseif T <: Irrational
        return Dict("type" => "number")
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
        if isempty(params)
            return Dict("type" => "array", "minItems" => 0, "maxItems" => 0)
        elseif any(Base.isvarargtype, params)
            vararg_param = params[end]
            base = Base.unwrap_unionall(vararg_param)
            elem_type = base.parameters[1]
            return vararg_tuple_schema(elem_type, ctx)
        elseif T <: NTuple && length(params) >= 1 && allequal(params)
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

function generate_abstract_schema(T::DataType, ctx::SchemaContext)
    spec = ctx.abstract_specs[T]
    n = length(spec.variants)
    options = Vector{Dict{String, Any}}(undef, n)
    for (idx, variant) in enumerate(spec.variants)
        normalized = define!(variant, ctx)
        base_ref = reference(normalized, ctx)
        discr_schema = Dict(
            "type" => "object",
            "properties" => Dict(spec.discr_key => Dict("const" => spec.tag_value[variant]))
        )
        if spec.require_discr
            discr_schema["required"] = [spec.discr_key]
        end
        options[idx] = Dict("allOf" => [base_ref, discr_schema])
    end
    return Dict("anyOf" => options)
end
