using Struct2JSONSchema
using JSON

struct TodoItem
    title::String
    completed::Bool
    priority::Int
    tags::Vector{String}
end

schema = generate_schema(TodoItem)
println(JSON.json(schema.doc, 4))
