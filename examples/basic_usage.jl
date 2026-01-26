using Struct2JSONSchema
using JSON

struct TodoItem
    title::String
    completed::Bool
    priority::Int
    tags::Vector{String}
end

doc, unknowns = generate_schema(TodoItem)
println(JSON.json(doc, 4))
