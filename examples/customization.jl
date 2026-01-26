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

override_type!(ctx, UUID) do _
    Dict("type" => "string", "format" => "uuid")
end

override_field!(ctx, Alert, :severity) do _
    Dict(
        "type" => "integer",
        "minimum" => 1,
        "maximum" => 5,
        "description" => "Alert severity on a five point scale"
    )
end

auto_optional_nothing!(ctx)

override_abstract!(
    ctx,
    Event;
    variants = [Deployment, Alert],
    discr_key = "kind",
    tag_value = Dict(
        Deployment => "deployment",
        Alert => "alert"
    )
)

doc, _ = generate_schema(EventEnvelope; ctx = ctx)
println(JSON.json(doc, 4))
