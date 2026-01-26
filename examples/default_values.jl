using Struct2JSONSchema
using JSON
using Dates

# Example 1: Basic default value registration
struct ServerConfig
    host::String
    port::Int
    timeout::Float64
end

ctx1 = SchemaContext()
defaultvalue!(ctx1, ServerConfig("localhost", 8080, 30.0))

doc1, _ = generate_schema(ServerConfig; ctx = ctx1)
println("=== Basic default values ===")
println(JSON.json(doc1, 4))
println()

# Example 2: Custom type serializer for DateTime
struct LogEntry
    message::String
    timestamp::DateTime
    level::Int
end

ctx2 = SchemaContext()
# Convert DateTime to Unix timestamp
defaultvalue_type_serializer!(ctx2, DateTime) do value, ctx
    Int(datetime2unix(value))
end
defaultvalue!(ctx2, LogEntry("System started", DateTime(2024, 1, 1, 12, 0, 0), 1))

doc2, _ = generate_schema(LogEntry; ctx = ctx2)
println("=== Custom type serializer ===")
println(JSON.json(doc2, 4))
println()

# Example 3: Custom field serializer
struct UserSettings
    username::String
    theme::String
    created_at::DateTime
end

ctx3 = SchemaContext()
# Format created_at as ISO 8601 string
defaultvalue_field_serializer!(ctx3, UserSettings, :created_at) do value, ctx
    Dates.format(value, "yyyy-mm-ddTHH:MM:SSZ")
end
defaultvalue!(ctx3, UserSettings("alice", "dark", DateTime(2024, 1, 15, 9, 30, 0)))

doc3, _ = generate_schema(UserSettings; ctx = ctx3)
println("=== Custom field serializer ===")
println(JSON.json(doc3, 4))
