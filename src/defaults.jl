using Dates

struct SerializationFailed end
const SERIALIZATION_FAILED = SerializationFailed()

is_json_primitive(value)::Bool = value isa Union{String, Int, Float64, Bool, Nothing}

function serialize_number_for_default(value)::Union{Int, Float64, Nothing}
    value isa Integer && return Int(value)
    value isa AbstractFloat && return Float64(value)
    return nothing
end

function serialize_datetime_for_default(value)::Union{String, Nothing}
    value isa DateTime && return Dates.format(value, "yyyy-mm-ddTHH:MM:SS")
    value isa Date && return Dates.format(value, "yyyy-mm-dd")
    value isa Time && return Dates.format(value, "HH:MM:SS")
    return nothing
end

function serialize_stringlike_for_default(value)::Union{String, Nothing}
    value isa Union{Base.UUID, Symbol, Char, VersionNumber} && return string(value)
    return nothing
end

function serialize_array_for_default(value, field_type::Type)::Union{Vector, Nothing}
    value isa AbstractArray || return nothing
    elem_type = eltype(value)

    serialized = [defaultvalue_serialize(elem_type, item) for item in value]
    any(isnothing, serialized) && return nothing

    return serialized
end

function serialize_dict_for_default(value, field_type::Type)::Union{Dict{String, Any}, Nothing}
    value isa AbstractDict || return nothing
    val_type = valtype(value)

    result = Dict{String, Any}()
    for (k, v) in value
        serialized = defaultvalue_serialize(val_type, v)
        serialized === nothing && return nothing
        result[string(k)] = serialized
    end

    return result
end

"""
    defaultvalue_serialize(field_type::Type, value) -> Union{RepresentableValue, Nothing}

Serialize a Julia value to a JSON-compatible representation for use as a default value
in JSON Schema. Returns `nothing` if the value cannot be serialized.

This is the default fallback serializer. Users can register custom serializers using
`defaultvalue_serializer!`, `defaultvalue_type_serializer!`, or `defaultvalue_field_serializer!`.

# Supported Types
- Primitives: `String`, `Int`, `Float64`, `Bool`, `Nothing` → as-is
- Numbers: `Integer` → `Int`, `AbstractFloat` → `Float64`
- DateTime types: `DateTime`, `Date`, `Time` → ISO 8601 strings
- String-convertible: `UUID`, `Symbol`, `Char`, `VersionNumber` → strings
- Collections: `AbstractArray`, `AbstractDict` → recursively serialized

# Examples
```julia
defaultvalue_serialize(DateTime, DateTime(2024, 1, 1))  # "2024-01-01T00:00:00"
defaultvalue_serialize(Int, 42)  # 42
defaultvalue_serialize(Function, () -> nothing)  # nothing (unsupported)
```
"""
function defaultvalue_serialize(field_type::Type, value)::Union{RepresentableValue, Nothing}
    is_json_primitive(value) && return value

    for serializer in [
        serialize_number_for_default,
        serialize_datetime_for_default,
        serialize_stringlike_for_default
    ]
        result = serializer(value)
        result !== nothing && return result
    end

    for serializer in [serialize_array_for_default, serialize_dict_for_default]
        result = serializer(value, field_type)
        result !== nothing && return result
    end

    return nothing
end

function with_field_context(f::Function, ctx::SchemaContext, T::Type, field::Symbol)
    old_path = copy(ctx.path)
    old_parent = current_parent(ctx)
    old_field = current_field(ctx)

    push!(ctx.path, field)
    set_current_parent!(ctx, T)
    set_current_field!(ctx, field)

    try
        return f()
    finally
        ctx.path = old_path
        set_current_parent!(ctx, old_parent)
        set_current_field!(ctx, old_field)
    end
end

function try_custom_serializer(
    serializer::Function,
    field_type::Type,
    value,
    ctx::SchemaContext
)
    try
        result = serializer(field_type, value, ctx)
        result !== nothing && return result
    catch e
        if is_verbose(ctx)
            @warn "Default serializer threw error" exception=(e, catch_backtrace())
        end
    end
    return nothing
end

function defaultvalue_try_serialize(
    ctx::SchemaContext,
    field_type::Type,
    value
)
    for serializer in ctx.default_serializers
        result = try_custom_serializer(serializer, field_type, value, ctx)
        result !== nothing && return result
    end

    result = defaultvalue_serialize(field_type, value)

    if result === nothing && value !== nothing
        record_unknown!(
            ctx,
            typeof(value),
            "default_serialization_failed";
            message = "Cannot serialize default value of type $(typeof(value)) for field type $field_type"
        )
        return SERIALIZATION_FAILED
    end

    return result
end

function process_field_default!(
    ctx::SchemaContext,
    T::Type,
    field::Symbol,
    field_type::Type,
    value
)::Nothing
    with_field_context(ctx, T, field) do
        json_value = defaultvalue_try_serialize(ctx, field_type, value)

        if json_value !== SERIALIZATION_FAILED
            default_values(ctx)[(T, field)] = json_value
        end
    end

    return nothing
end

function validate_instance_type(instance)::Type
    if instance isa Type
        throw(ArgumentError("instance must be a concrete struct instance, not a Type"))
    end

    T = typeof(instance)

    if !isstructtype(T) || isabstracttype(T)
        throw(ArgumentError("instance must be a concrete struct"))
    end

    return T
end

"""
    defaultvalue!(ctx::SchemaContext, instance) -> Nothing

Register default values for all fields of a struct instance.

# Arguments
- `ctx::SchemaContext`: The schema context
- `instance`: A concrete struct instance (not a Type!)

# Throws
- `ArgumentError` if `instance` is a Type rather than an instance
- `ArgumentError` if `instance` is not a concrete struct

# Examples
```julia
struct ServerConfig
    host::String
    port::Int
end

ctx = SchemaContext()
defaultvalue!(ctx, ServerConfig("localhost", 8080))

result = generate_schema(ServerConfig; ctx=ctx)
```

# Notes
- Override-defined defaults take precedence over registered defaults
- Fields that cannot be serialized are skipped and recorded in `unknowns`
- Use `defaultvalue_type_serializer!` or `defaultvalue_field_serializer!` for custom serialization
"""
function defaultvalue!(ctx::SchemaContext, instance)::Nothing
    T = validate_instance_type(instance)

    for (idx, field) in enumerate(fieldnames(T))
        field_type = fieldtype(T, idx)
        value = getfield(instance, field)

        process_field_default!(ctx, T, field, field_type, value)
    end

    return nothing
end

"""
    defaultvalue_serializer!(serializer::Function, ctx::SchemaContext) -> Nothing

Register a custom serializer for default values.

# Arguments
- `serializer::Function`: Function with signature `(field_type::Type, value, ctx::SchemaContext) -> Union{RepresentableValue, Nothing}`
- `ctx::SchemaContext`: The schema context

Serializers are evaluated in FIFO (registration) order.
Return `nothing` to fall through to the next serializer.

# Examples
```julia
ctx = SchemaContext()

defaultvalue_serializer!(ctx) do field_type, value, ctx
    if value isa MyCustomType
        return Dict("custom" => value.data)
    end
    return nothing
end
```
"""
function defaultvalue_serializer!(serializer::Function, ctx::SchemaContext)::Nothing
    push!(ctx.default_serializers, serializer)
    return nothing
end

"""
    defaultvalue_type_serializer!(serializer::Function, ctx::SchemaContext, T::Type) -> Nothing

Register a custom serializer for default values of a specific type.

# Arguments
- `serializer::Function`: Function with signature `(value, ctx::SchemaContext) -> Union{RepresentableValue, Nothing}`
- `ctx::SchemaContext`: The schema context
- `T::Type`: The type to serialize

# Examples
```julia
struct Color
    r::UInt8
    g::UInt8
    b::UInt8
end

ctx = SchemaContext()
defaultvalue_type_serializer!(ctx, Color) do value, ctx
    r = string(value.r, base=16, pad=2)
    g = string(value.g, base=16, pad=2)
    b = string(value.b, base=16, pad=2)
    "#\$(r)\$(g)\$(b)"
end
```
"""
function defaultvalue_type_serializer!(serializer::Function, ctx::SchemaContext, T::Type)::Nothing
    defaultvalue_serializer!(ctx) do field_type, value, ctx
        if typeof(value) === T
            return serializer(value, ctx)
        end
        return nothing
    end
    return nothing
end

"""
    defaultvalue_field_serializer!(serializer::Function, ctx::SchemaContext, Parent::Type, field::Symbol) -> Nothing

Register a custom serializer for the default value of a specific field.

# Arguments
- `serializer::Function`: Function with signature `(value, ctx::SchemaContext) -> Union{RepresentableValue, Nothing}`
- `ctx::SchemaContext`: The schema context
- `Parent::Type`: The parent struct type
- `field::Symbol`: The field name

# Examples
```julia
struct Metrics
    created_at::DateTime
    updated_at::DateTime
end

ctx = SchemaContext()

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
    defaultvalue_serializer!(ctx) do field_type, value, ctx
        if current_parent(ctx) === Parent && current_field(ctx) === field
            return serializer(value, ctx)
        end
        return nothing
    end
    return nothing
end
