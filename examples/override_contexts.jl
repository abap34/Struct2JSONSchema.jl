using Struct2JSONSchema
using JSON
using Dates

"""
Example showcasing the flexible override contexts:
  * override_type!  -- replace DateTime with string/date-time
  * override_field! -- cap retry count on ServiceEndpoint.retries
  * override!       -- path-sensitive override for any label entry
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
override_type!(ctx, DateTime) do _
    Dict("type" => "string", "format" => "date-time")
end

# Field-specific override: keep retries within a sane range.
override_field!(ctx, ServiceEndpoint, :retries) do _
    Dict("type" => "integer", "minimum" => 0, "maximum" => 5)
end

# Contextual override: whenever we are inside ApplicationConfig.labels.*,
# tighten the schema for individual label keys/values.
override!(ctx) do ctx
    if current_parent(ctx) === DeploymentLabel && current_field(ctx) === :key
        return Dict("type" => "string", "minLength" => 2, "maxLength" => 32)
    elseif current_parent(ctx) === DeploymentLabel && current_field(ctx) === :value
        return Dict("type" => "string", "minLength" => 1)
    end
    return nothing
end

doc, _ = generate_schema(ApplicationConfig; ctx = ctx)
println(JSON.json(doc, 4))
