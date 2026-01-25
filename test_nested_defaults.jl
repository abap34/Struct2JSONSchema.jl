using Struct2JSONSchema

struct Address
    street::String
    city::String
end

struct Profile
    name::String
    address::Address
end

ctx = SchemaContext()
defaultvalue!(ctx, Profile("Alice", Address("Main St", "Metropolis")))

result = generate_schema(Profile; ctx = ctx, simplify = false)

println(ctx.field_metadata.default_values)

using JSON
println(JSON.json(result.doc, 2))
