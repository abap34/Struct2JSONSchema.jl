using Struct2JSONSchema
using JSON
using Dates
using UUIDs

abstract type Event end

struct Deployment <: Event
    id::UUID
    started_at::DateTime
end

struct Alert <: Event
    id::UUID
    severity::Int
    acknowledged::Union{Bool, Nothing}
end

struct EventEnvelope
    event::Event
    received_at::DateTime
end

ctx = SchemaContext()

register_override!(ctx, UUID) do _
    Dict("type" => "string", "format" => "uuid")
end

register_field_override!(ctx, Alert, :severity) do _
    Dict(
        "type" => "integer",
        "minimum" => 1,
        "maximum" => 5,
        "description" => "Alert severity on a five point scale"
    )
end

treat_union_nothing_as_optional!(ctx)

register_abstract!(
    ctx,
    Event;
    variants = [Deployment, Alert],
    discr_key = "kind",
    tag_value = Dict(
        Deployment => "deployment",
        Alert => "alert"
    )
)

schema = generate_schema(EventEnvelope; ctx = ctx)
println(JSON.json(schema.doc, 4))
