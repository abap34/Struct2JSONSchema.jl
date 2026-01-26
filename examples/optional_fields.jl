using Struct2JSONSchema
using JSON

struct FullName
    first::String
    middle::Union{String, Nothing}
    last::String
end

struct UserProfile
    id::Int
    handle::String
    nickname::Union{String, FullName, Nothing}
    timezone::Union{String, Missing}
end

ctx = SchemaContext()
auto_optional_nothing!(ctx)
auto_optional_missing!(ctx)

doc, _ = generate_schema(UserProfile; ctx = ctx)
println(JSON.json(doc, 4))
