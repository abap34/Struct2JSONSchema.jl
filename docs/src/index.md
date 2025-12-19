# Struct2JSONSchema.jl

Struct2JSONSchema.jl is a Julia package that automatically generates JSON Schema draft 2020-12 compliant schema documents from Julia type definitions.

## Quick Start

```julia
using Struct2JSONSchema
using JSON

struct User
    id::Int
    name::String
    email::Union{String, Nothing}
end

doc, unknowns = generate_schema(User)
JSON.json(doc)
```

## Concepts

**Non-invasive**
In many cases, struct definitions exist first, and JSON Schema is needed secondarily. In such cases, it is undesirable to modify the struct definition to generate a JSON Schema. Struct2JSONSchema.jl generates JSON Schema without any changes to existing struct definitions.

**Robust**
Struct2JSONSchema.jl generates JSON Schema for all types. Unknown types fall back to `Any`, but never throw errors.

**Extensible**
Struct2JSONSchema.jl is customizable to express user-defined types and constraints.

**Future-proof**
The implementation is concise, does not depend on Julia's internal APIs, and has minimal dependencies. See [Project.toml](https://github.com/abap34/Struct2JSONSchema.jl/blob/main/Project.toml).

## Basic Usage

The core function is `generate_schema`, which accepts a Julia type and returns a named tuple containing the schema document and a set of unknown types.

```julia
using Struct2JSONSchema

struct Person
    name::String
    age::Int
end

result = generate_schema(Person)
println(result.doc)  # JSON Schema document
println(result.unknowns)  # Set of types that couldn't be represented (empty in this case)
```

When types cannot be represented in JSON Schema, they are tracked in the `unknowns` set:

```julia
struct CInterface
    name::String
    ptr::Ptr{Cvoid}  # Ptr cannot be represented in JSON Schema
end

result = generate_schema(CInterface)
println(result.unknowns)  # Set{Tuple{DataType, Tuple{Vararg{Symbol}}}}((Ptr{Nothing}, (:ptr,)))
```

Types in `unknowns` fall back to an empty schema (`{}`), allowing generation to continue without errors.

## Customization

Struct2JSONSchema.jl is fully customizable using `SchemaContext`. The core customization mechanism is `register_override!`, which allows you to define custom schema generators for any type. Additionally, we provide convenient helper functions for common customization patterns.

### Custom Type Overrides

The `register_override!` function is the foundation of customization in Struct2JSONSchema.jl. It allows you to replace the default schema generation logic for any specific type with your own custom generator.

**How it works:**
- Takes a type and a generator function that accepts a `SchemaContext` and returns a `Dict{String, Any}` representing the JSON Schema
- The generator function is called whenever the specified type is encountered during schema generation
- This allows you to handle types that aren't supported by default, or customize the schema for built-in types

**Example: Adding support for UUID types**

```julia
using UUIDs

struct User
    id::UUID
    name::String
end

ctx = SchemaContext()
register_override!(ctx, UUID) do ctx
    return Dict("type" => "string", "format" => "uuid")
end

result = generate_schema(User; ctx=ctx)
# Now UUID fields will be represented as strings with uuid format
```

**Example: Adding validation constraints**

```julia
struct Product
    name::String
    price::Float64
end

ctx = SchemaContext()
register_override!(ctx, Float64) do ctx
    return Dict(
        "type" => "number",
        "minimum" => 0.0,
        "exclusiveMinimum" => true
    )
end

result = generate_schema(Product; ctx=ctx)
# All Float64 fields will have a minimum constraint of 0.0
```

### Field-Level Overrides

For finer control, you can override schema generation for individual fields using `register_field_override!`:

```julia
ctx = SchemaContext()
register_field_override!(ctx, User, :email) do ctx
    return Dict("type" => "string", "format" => "email")
end

generate_schema(User; ctx=ctx)
```

### Abstract Types with Discriminators

For abstract types with concrete subtypes, use `register_abstract!` to define discriminator-based schemas:

```julia
abstract type Animal end

struct Cat <: Animal
    meow_volume::Int
    kind::String
end

struct Dog <: Animal
    bark_volume::Int
    kind::String
end

ctx = SchemaContext()
register_abstract!(ctx, Animal;
    variants = [Cat, Dog],
    discr_key = "kind",
    tag_value = Dict(Cat => "cat", Dog => "dog"),
)

generate_schema(Animal; ctx=ctx)
```

### Convenient Helpers for Common Patterns

For common customization patterns, we provide convenient helper functions:

**Treating `Union{T, Nothing}` as optional fields:**

```julia
ctx = SchemaContext()
treat_union_nothing_as_optional!(ctx)

generate_schema(User; ctx=ctx)
```

**Treating `Union{T, Missing}` as optional fields:**

```julia
treat_union_missing_as_optional!(ctx)
```

**Treating both `Union{T, Nothing}` and `Union{T, Missing}` as optional:**

```julia
treat_null_as_optional!(ctx)
```

## Examples

For more detailed examples, see the [examples directory](https://github.com/abap34/Struct2JSONSchema.jl/tree/main/examples).

## API Reference

See the [API Reference](api.md) for detailed documentation of all exported functions.
