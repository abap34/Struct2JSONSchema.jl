# Struct2JSONSchema.jl

Struct2JSONSchema.jl is a Julia package that converts Julia structs into JSON Schema documents compliant with draft 2020-12.

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
JSON.json(doc, 4)
```

## Concepts

### Non-invasive

In many cases, struct definitions already exist and JSON Schema is needed afterward.
In such situations, modifying existing struct definitions solely to generate JSON Schema is undesirable.
Struct2JSONSchema.jl generates JSON Schema without making any changes to existing struct definitions.

### Extensibility

Struct2JSONSchema.jl is designed to be customizable, allowing users to represent user-defined types and constraints.

### Robustness

Struct2JSONSchema.jl generates JSON Schema for all types.
If a type cannot be represented, it falls back to `Any`, but it never raises an error.

### Long-term maintainability

The implementation is simple, does not rely on Julia internal APIs, and has minimal dependencies.
See [Project.toml](https://github.com/abap34/Struct2JSONSchema.jl/blob/main/Project.toml).

### Non-goals

For these reasons, the following are explicitly not goals:

* Automatically reflecting detailed semantics available on the Julia side into JSON Schema.

  * Such implementations tend to require significant effort for limited benefit and are fragile against future changes in Julia.
    Therefore, if such behavior is desired, users are expected to implement it manually via customization.
    Sufficient extensibility is provided for this purpose.
* Advanced performance optimization.

  * Programs that take type definitions as input can often be highly optimized.
    However, schema generation is typically performed only once, with small inputs, and is unlikely to be a performance bottleneck.
    Simplicity of implementation is therefore prioritized.

## Basic Usage

[`generate_schema`](@ref) takes a Julia type and returns a named tuple containing the schema document and a set of types that could not be represented.

```julia
using Struct2JSONSchema

struct Person
    name::String
    age::Int
end

result = generate_schema(Person)
println(result.doc)        # The document representing the JSON Schema
println(result.unknowns)   # The set of unrepresentable types (empty in this case)
```

If a type cannot be represented in JSON Schema, it is recorded in `unknowns`:

```julia
struct CInterface
    name::String
    ptr::Ptr{Cvoid}  # Ptr cannot be represented in JSON Schema
end

result = generate_schema(CInterface)
println(result.unknowns)  # Set{Tuple{DataType, Tuple{Vararg{Symbol}}}}((Ptr{Nothing}, (:ptr,)))
```

## Next Steps

- [User Guide](guide.md) — Customization, optional fields, field descriptions, default values
- [Reference](reference.md) — Type mappings and API reference
