using Struct2JSONSchema
using JSON

# Example 1: Auto-extraction from docstrings
"""
User information
"""
struct User
    """User's unique identifier"""
    id::Int

    """User's full name"""
    name::String

    email::String  # No docstring
end

# By default, auto_fielddoc=true, so docstrings are automatically extracted
ctx1 = SchemaContext()
schema1 = generate_schema(User, ctx = ctx1)
println("=== Auto-extraction from docstrings ===")
println(JSON.json(schema1.doc, 4))
println()

# Example 2: Manual registration with register_field_description!
struct Product
    id::Int
    name::String
    price::Float64
end

ctx2 = SchemaContext()
register_field_description!(ctx2, Product, :id, "Product unique identifier")
register_field_description!(ctx2, Product, :name, "Product display name")
register_field_description!(ctx2, Product, :price, "Product price in USD")

schema2 = generate_schema(Product, ctx = ctx2)
println("=== Manual registration ===")
println(JSON.json(schema2.doc, 4))
println()

# Example 3: Manual registration overrides docstring
"""
Event data
"""
struct Event
    """Event ID from docstring"""
    id::Int

    """Event timestamp"""
    timestamp::String
end

ctx3 = SchemaContext()
register_field_description!(ctx3, Event, :id, "Event unique ID (overridden)")

schema3 = generate_schema(Event, ctx = ctx3)
println("=== Manual registration overrides docstring ===")
println(JSON.json(schema3.doc, 4))
