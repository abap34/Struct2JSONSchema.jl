const JS_MAX_SAFE_INTEGER = (Int64(1) << 53) - 1

"""
    JavaScriptCompatibilityError

Raised when `javascript_safe_numbers=true` encounters a value that cannot be
represented safely in an ECMAScript-compatible JSON document.

# Fields
- `path::String`: JSON Pointer or registration path for the incompatible value
- `value::Any`: original value
- `reason::String`: reason the value is incompatible
"""
struct JavaScriptCompatibilityError <: Exception
    path::String
    value::Any
    reason::String
end

function Base.showerror(io::IO, err::JavaScriptCompatibilityError)
    location = isempty(err.path) ? "<root>" : err.path
    print(
        io,
        "JavaScript-incompatible value at ", location, ": ", err.reason,
        " (value: ", repr(err.value), ")"
    )
end

function is_javascript_safe_integer(value::Integer)::Bool
    return -JS_MAX_SAFE_INTEGER <= BigInt(value) <= JS_MAX_SAFE_INTEGER
end

json_pointer_escape(value::AbstractString) =
    replace(replace(value, "~" => "~0"), "/" => "~1")

function json_pointer(path::Vector{String})::String
    isempty(path) && return ""
    return "/" * join(json_pointer_escape.(path), "/")
end

function javascript_compatibility_error(value, path::Vector{String}, reason::String)
    throw(JavaScriptCompatibilityError(json_pointer(path), value, reason))
end

function normalize_javascript_number(value::Integer, path::Vector{String})::Int64
    if !is_javascript_safe_integer(value)
        javascript_compatibility_error(
            value,
            path,
            "integer exceeds the ECMAScript safe integer range"
        )
    end
    return Int64(value)
end

function normalize_javascript_number(
        value::Union{Float16, Float32, Float64},
        path::Vector{String}
    )
    isfinite(value) || javascript_compatibility_error(
        value,
        path,
        "non-finite numbers are not valid JSON values"
    )
    widened = Float64(value)
    if isinteger(widened) && -JS_MAX_SAFE_INTEGER <= widened <= JS_MAX_SAFE_INTEGER
        return Int64(widened)
    end
    return widened
end

function normalize_javascript_number(value::BigFloat, path::Vector{String})
    isfinite(value) || javascript_compatibility_error(
        value,
        path,
        "non-finite numbers are not valid JSON values"
    )
    widened = Float64(value)
    exact = isfinite(widened) && setprecision(max(precision(value), 64)) do
        BigFloat(widened) == value
    end
    if !exact
        javascript_compatibility_error(
            value,
            path,
            "BigFloat cannot be represented exactly as an ECMAScript Number"
        )
    end
    return normalize_javascript_number(widened, path)
end

function normalize_javascript_number(value::Rational, path::Vector{String})
    widened = Float64(value)
    exact = isfinite(widened) &&
        Rational{BigInt}(widened) == BigInt(numerator(value)) // BigInt(denominator(value))
    if !exact
        javascript_compatibility_error(
            value,
            path,
            "rational cannot be represented exactly as an ECMAScript Number"
        )
    end
    return normalize_javascript_number(widened, path)
end

function normalize_javascript_number(value::Number, path::Vector{String})
    return javascript_compatibility_error(
        value,
        path,
        "number type $(typeof(value)) is not supported by ECMAScript Number"
    )
end

normalize_javascript_value(value, path::Vector{String}) =
    normalize_javascript_value(value, path, Base.IdSet{Any}())

normalize_javascript_value(value::Nothing, _path::Vector{String}, _active) = value
normalize_javascript_value(value::Bool, _path::Vector{String}, _active) = value
normalize_javascript_value(value::AbstractString, _path::Vector{String}, _active) =
    String(value)
normalize_javascript_value(value::Number, path::Vector{String}, _active) =
    normalize_javascript_number(value, path)

function normalize_javascript_value(
        value::AbstractDict,
        path::Vector{String},
        active::Base.IdSet{Any}
    )
    value in active && javascript_compatibility_error(
        value,
        path,
        "cyclic containers are not representable in JSON"
    )
    push!(active, value)
    try
        result = value isa OrderedDict ?
            OrderedDict{String, Any}() : Dict{String, Any}()
        for (key, item) in value
            if !(key isa AbstractString)
                javascript_compatibility_error(
                    key,
                    path,
                    "JSON object keys must be strings"
                )
            end
            string_key = String(key)
            result[string_key] = normalize_javascript_value(
                item,
                [path; string_key],
                active
            )
        end
        return result
    finally
        delete!(active, value)
    end
end

function normalize_javascript_value(
        value::AbstractVector,
        path::Vector{String},
        active::Base.IdSet{Any}
    )
    value in active && javascript_compatibility_error(
        value,
        path,
        "cyclic containers are not representable in JSON"
    )
    push!(active, value)
    try
        return Any[
            normalize_javascript_value(item, [path; string(index - 1)], active)
            for (index, item) in enumerate(value)
        ]
    finally
        delete!(active, value)
    end
end

function normalize_javascript_value(
        value::Tuple,
        path::Vector{String},
        active::Base.IdSet{Any}
    )
    return Any[
        normalize_javascript_value(item, [path; string(index - 1)], active)
        for (index, item) in enumerate(value)
    ]
end

function normalize_javascript_value(value, path::Vector{String}, _active)
    return javascript_compatibility_error(
        value,
        path,
        "value of type $(typeof(value)) is not representable in JSON"
    )
end

function normalize_javascript_scalar(value, path::Vector{String})
    normalized = normalize_javascript_value(value, path)
    if normalized isa AbstractDict || normalized isa AbstractVector
        javascript_compatibility_error(value, path, "expected a JSON scalar")
    end
    return normalized
end

function normalize_javascript_schema(doc::AbstractDict)::Dict{String, Any}
    return Dict{String, Any}(normalize_javascript_value(doc, String[]))
end
