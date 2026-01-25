using Dates


serialize_primitive(_) = nothing
serialize_primitive(value::Number) = value
serialize_primitive(value::AbstractString) = value
serialize_primitive(value::Bool) = value
serialize_primitive(::Nothing) = "null"
serialize_primitive(value::UUID) = string(value)
serialize_primitive(value::Symbol) = string(value)
serialize_primitive(value::Char) = string(value)
serialize_primitive(value::VersionNumber) = string(value)
serialize_primitive(value::DateTime) = Dates.format(value, "yyyy-mm-ddTHH:MM:SS")
serialize_primitive(value::Date) = Dates.format(value, "yyyy-mm-dd")
serialize_primitive(value::Time) = Dates.format(value, "HH:MM:SS")

function try_custom_serializer(serializer::Function, field_type::Type, value, ctx::SchemaContext)
    try
        result = serializer(field_type, value, ctx)
        result !== nothing && return result
    catch e
        is_verbose(ctx) && @warn "Default serializer threw error" exception = (e, catch_backtrace())
    end
    return nothing
end

function try_custom_serializers(ctx::SchemaContext, field_type::Type, value)
    for serializer in ctx.defaultvalue_custom_serializers
        result = try_custom_serializer(serializer, field_type, value, ctx)
        result !== nothing && return result
    end
    return nothing
end


is_serializable_struct(value) =
    isstructtype(typeof(value)) &&
    !isabstracttype(typeof(value)) &&
    !(value isa Function) &&
    !(value isa Type)


function serialize(
        ctx::SchemaContext,
        field_type::Type,
        value;
        register_defaults::Bool = false
    )
    # 1. Custom serializers (highest priority)
    result = try_custom_serializers(ctx, field_type, value)
    result !== nothing && return result

    # 2. Primitives
    result = serialize_primitive(value)
    result !== nothing && return result

    # 3. Collections
    value isa AbstractVector && return [serialize(ctx, typeof(v), v; register_defaults) for v in value]
    value isa AbstractDict && return Dict(k => serialize(ctx, typeof(v), v; register_defaults) for (k, v) in value)

    # 4. Structs
    is_serializable_struct(value) && return serialize_struct(ctx, value, register_defaults)

    # 5. Unsupported type
    record_unknown!(
        ctx, typeof(value), "default_serialization_failed";
        message = "Cannot serialize $(typeof(value)) for $(current_field(ctx))"
    )
    return nothing
end

function serialize_struct(ctx::SchemaContext, value, register_defaults::Bool)
    T = typeof(value)
    skip_set = get(skip_fields(ctx), T, Set{Symbol}())
    result = Dict{String, Any}()

    for (idx, field) in enumerate(fieldnames(T))
        field in skip_set && continue

        field_value = getfield(value, field)
        field_type = fieldtype(T, idx)

        serialized = with_field_context(ctx, T, field) do
            serialize(ctx, field_type, field_value; register_defaults)
        end

        if serialized !== nothing
            result[string(field)] = serialized
            # Only register defaults for leaf values (not nested structs)
            # A nested struct serializes to Dict{String, Any}, so skip those
            if register_defaults && !(serialized isa Dict{String, Any})
                ctx.field_metadata.default_values[(T, field)] = serialized
            end
        end
    end
    return result
end

"""
    defaultvalue!(ctx::SchemaContext, instance) -> Nothing

Register default values for all fields of a struct instance (recursively).

# Example
```julia
ctx = SchemaContext()
defaultvalue!(ctx, ServerConfig("localhost", 8080))
```
"""
function defaultvalue!(ctx::SchemaContext, instance::T)::Nothing where {T}
    serialize(ctx, T, instance; register_defaults = true)
    return nothing
end

"""
    defaultvalue_serializer!(ctx::SchemaContext, serializer::Function) -> Nothing

Register a custom serializer for default values.

Serializers are evaluated in FIFO order. Return `nothing` to fall through.

# Example
```julia
defaultvalue_serializer!(ctx) do field_type, value, ctx
    value isa MyType ? serialize_my_type(value) : nothing
end
```
"""
function defaultvalue_serializer!(serializer::Function, ctx::SchemaContext)::Nothing
    push!(ctx.defaultvalue_custom_serializers, serializer)
    return nothing
end

"""
    defaultvalue_type_serializer!(ctx::SchemaContext, T::Type, serializer::Function) -> Nothing

Register a custom serializer for all values of type `T`.

# Example
```julia
defaultvalue_type_serializer!(ctx, Color) do value, ctx
    "#" * join(string.(value.r, value.g, value.b), base=16, pad=2)
end
```
"""
function defaultvalue_type_serializer!(serializer::Function, ctx::SchemaContext, T::Type)::Nothing
    return defaultvalue_serializer!(ctx) do field_type, value, ctx
        typeof(value) === T ? serializer(value, ctx) : nothing
    end
end

"""
    defaultvalue_field_serializer!(ctx::SchemaContext, Parent::Type, field::Symbol, serializer::Function) -> Nothing

Register a custom serializer for a specific field.

# Example
```julia
defaultvalue_field_serializer!(ctx, Metrics, :created_at) do value, ctx
    Int(datetime2unix(value))
end
```
"""
function defaultvalue_field_serializer!(
        serializer::Function,
        ctx::SchemaContext,
        Parent::Type,
        field::Symbol
    )::Nothing
    return defaultvalue_serializer!(ctx) do field_type, value, ctx
        (current_parent(ctx) === Parent && current_field(ctx) === field) ? serializer(value, ctx) : nothing
    end
end
