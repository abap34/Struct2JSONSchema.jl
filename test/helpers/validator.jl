function resolve_schema_entry(schema::AbstractDict, doc::AbstractDict)
    current = schema
    while haskey(current, "\$ref")
        ref = current["\$ref"]
        parts = split(ref, '/')
        key = parts[end]
        defs = get(doc, "\$defs", Dict())
        if haskey(defs, key)
            current = defs[key]
        else
            # If $defs doesn't exist or doesn't have the key,
            # the schema might be inlined - return current
            return current
        end
    end
    return current
end

function validate_schema_entry(schema::AbstractDict, data, doc::AbstractDict)::Bool
    current = resolve_schema_entry(schema, doc)

    if haskey(current, "oneOf")
        return any(sub -> validate_schema_entry(sub, data, doc), current["oneOf"])
    end

    if haskey(current, "anyOf")
        return any(sub -> validate_schema_entry(sub, data, doc), current["anyOf"])
    end

    if haskey(current, "allOf")
        return all(sub -> validate_schema_entry(sub, data, doc), current["allOf"])
    end

    if haskey(current, "enum")
        return any(val -> data == val, current["enum"])
    end

    if haskey(current, "not")
        return !validate_schema_entry(current["not"], data, doc)
    end

    schema_type = get(current, "type", nothing)
    if schema_type === nothing
        return true
    elseif schema_type == "object"
        return validate_object(current, data, doc)
    elseif schema_type == "array"
        return validate_array(current, data, doc)
    elseif schema_type == "string"
        return validate_string(current, data)
    elseif schema_type == "integer"
        return validate_integer(current, data)
    elseif schema_type == "number"
        return validate_number(current, data)
    elseif schema_type == "boolean"
        return isa(data, Bool)
    elseif schema_type == "null"
        return data === nothing
    else
        return false
    end
end

function validate_object(schema::AbstractDict, data, doc)
    isa(data, AbstractDict) || return false
    properties = haskey(schema, "properties") ? schema["properties"] : Dict{String, Any}()

    for (name, subschema) in properties
        if haskey(data, name)
            validate_schema_entry(subschema, data[name], doc) || return false
        end
    end

    required = haskey(schema, "required") ? schema["required"] : String[]
    for field in required
        haskey(data, field) || return false
    end

    if haskey(schema, "additionalProperties")
        additional = schema["additionalProperties"]
        if additional === false
            allowed = Set(keys(properties))
            for key in keys(data)
                key in allowed || return false
            end
        elseif additional isa AbstractDict
            for (key, value) in data
                if !(haskey(properties, key))
                    validate_schema_entry(additional, value, doc) || return false
                end
            end
        end
    end

    return true
end

function validate_array(schema::AbstractDict, data, doc)
    isa(data, AbstractVector) || return false

    if haskey(schema, "prefixItems")
        prefix = schema["prefixItems"]
        length(data) == length(prefix) || return false
        for (value, subschema) in zip(data, prefix)
            validate_schema_entry(subschema, value, doc) || return false
        end
        return true
    end

    if haskey(schema, "items")
        for value in data
            validate_schema_entry(schema["items"], value, doc) || return false
        end
    end

    if haskey(schema, "minItems")
        length(data) >= schema["minItems"] || return false
    end

    if haskey(schema, "maxItems")
        length(data) <= schema["maxItems"] || return false
    end

    return true
end

function validate_string(schema::AbstractDict, data)
    isa(data, AbstractString) || return false
    if haskey(schema, "minLength")
        length(data) >= schema["minLength"] || return false
    end
    if haskey(schema, "maxLength")
        length(data) <= schema["maxLength"] || return false
    end
    return true
end

function validate_integer(schema::AbstractDict, data)
    isa(data, Integer) || return false
    if haskey(schema, "minimum")
        data >= schema["minimum"] || return false
    end
    if haskey(schema, "maximum")
        data <= schema["maximum"] || return false
    end
    return true
end

function validate_number(schema::AbstractDict, data)
    isa(data, Real) || return false
    if haskey(schema, "minimum")
        data >= schema["minimum"] || return false
    end
    if haskey(schema, "maximum")
        data <= schema["maximum"] || return false
    end
    return true
end

function validate_payload(doc, data)
    # If doc has a $ref at root, use it; otherwise validate against the root schema directly
    if haskey(doc, "\$ref")
        return validate_schema_entry(Dict("\$ref" => doc["\$ref"]), data, doc)
    else
        return validate_schema_entry(doc, data, doc)
    end
end
