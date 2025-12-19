using Struct2JSONSchema
using JSON
using Dates

"""
Example showcasing the flexible override contexts:
  * register_type_override!  -- replace DateTime with string/date-time
  * register_field_override! -- cap retry count on ServiceEndpoint.retries
  * register_override!       -- path-sensitive override for any label entry
"""
struct ServiceEndpoint
    url::String
    retries::Int
end

struct DeploymentLabel
    key::String
    value::String
end

struct ApplicationConfig
    name::String
    deployed_at::DateTime
    endpoint::ServiceEndpoint
    labels::Vector{DeploymentLabel}
end

ctx = SchemaContext()

# Type-wide override: treat DateTime as an ISO 8601 string.
register_type_override!(ctx, DateTime) do _
    Dict("type" => "string", "format" => "date-time")
end

# Field-specific override: keep retries within a sane range.
register_field_override!(ctx, ServiceEndpoint, :retries) do _
    Dict("type" => "integer", "minimum" => 0, "maximum" => 5)
end

# Contextual override: whenever we are inside ApplicationConfig.labels.*,
# tighten the schema for individual label keys/values.
register_override!(ctx) do ctx
    if ctx.current_parent === DeploymentLabel && ctx.current_field === :key
        return Dict("type" => "string", "minLength" => 2, "maxLength" => 32)
    elseif ctx.current_parent === DeploymentLabel && ctx.current_field === :value
        return Dict("type" => "string", "minLength" => 1)
    end
    return nothing
end

schema = generate_schema(ApplicationConfig; ctx = ctx)
println(JSON.json(schema.doc, 4))
