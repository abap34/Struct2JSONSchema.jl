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
treat_union_nothing_as_optional!(ctx)
treat_union_missing_as_optional!(ctx)

schema = generate_schema(UserProfile, ctx = ctx)
println(JSON.json(schema.doc, 4))
