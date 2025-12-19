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

## Customization

[`generate_schema`](@ref) recursively generates schemas while updating a [`SchemaContext`](@ref).
By using [`register_override!`](@ref), users can hook into this process and customize the generated schema.

```julia
# Customize the generation so that UUID is represented as a string with format: uuid
using UUIDs
using JSON

struct User
    id::UUID
    name::String
end

ctx = SchemaContext()
register_override!(ctx) do ctx
    if ctx.current_type === UUID
        return Dict("type" => "string", "format" => "uuid")
    end
    return nothing
end

result = generate_schema(User; ctx=ctx)
println(JSON.json(result.doc, 4))
```

[`SchemaContext`](@ref) has the following fields, which can be used for customization:

* `current_type` — the type currently being generated
* `current_parent` — the parent struct, when generating a field
* `current_field` — the field name, when generating a field
* `path` — the hierarchical path in the schema

[`register_override!`](@ref) accepts a hook function that takes a `SchemaContext` object and returns either a schema `Dict`, or `nothing` to indicate that default generation should continue.

In practice, most customizations follow common patterns.
For this reason, several helper functions are provided.

### Whole-type overrides: [`register_type_override!`](@ref)

Using [`register_type_override!`](@ref), a specific type can always be overridden for generation with the given `ctx`.
The following code is equivalent to the previous example.

```julia
using UUIDs

struct User
    id::UUID
    name::String
end

ctx = SchemaContext()
register_type_override!(ctx, UUID) do ctx
    Dict("type" => "string", "format" => "uuid")
end

result = generate_schema(User; ctx=ctx)
```

### Field-specific overrides: [`register_field_override!`](@ref)

Using [`register_field_override!`](@ref), an override can be applied only to a specific field of a specific struct.

```julia
struct User
    id::Int
    email::String
end

ctx = SchemaContext()
register_field_override!(ctx, User, :email) do ctx
    Dict("type" => "string", "format" => "email")
end

result = generate_schema(User; ctx=ctx)
```

### Abstract types: [`register_abstract!`](@ref)

Using [`register_abstract!`](@ref), an identifier-based schema can be generated for abstract types with concrete subtypes.

```julia
abstract type Event end

struct Deployment <: Event
    id::Int
    started_at::DateTime
end

struct Alert <: Event
    id::Int
    acknowledged::Bool
end

struct EventEnvelope
    event::Event
    received_at::DateTime
end
```

In this situation, an abstract type may appear as a field type.
A commonly desired schema is one where the `event` field of `EventEnvelope` takes the following form.

**valid:**

```json
[
    { "kind": "deployment", "id": 123, "started_at": "2024-01-01T12:00:00Z" },
    { "kind": "alert", "id": 456, "acknowledged": false }
]
```

**invalid:**

```json
[
    { "id": 123, "started_at": "2024-01-01T12:00:00Z" },
    { "id": 456, "acknowledged": false }
]
```

[`register_abstract!`](@ref) automatically generates such identifier-based schemas.

```julia
ctx = SchemaContext()

register_abstract!(
    ctx,
    Event;
    variants = [Deployment, Alert],
    discr_key = "kind",
    tag_value = Dict(
        Deployment => "deployment",
        Alert => "alert"
    )
)

schema = generate_schema(EventEnvelope; ctx = ctx)
println(JSON.json(schema.doc, 4))
```

## Optional Fields

**By default, Struct2JSONSchema.jl treats all fields as required.**

However, many users want fields of the following types to be treated as optional:

* `Union{T, Nothing}`
* `Union{T, Missing}`

For this purpose, the following helper functions are provided:

* [`treat_union_nothing_as_optional!`](@ref) — treat `Union{T, Nothing}` fields as optional
* [`treat_union_missing_as_optional!`](@ref) — treat `Union{T, Missing}` fields as optional
* [`treat_null_as_optional!`](@ref) — treat both `Union{T, Nothing}` and `Union{T, Missing}` fields as optional

```julia
struct User
    id::Int
    name::String
    birthdate::Union{Date, Nothing}
end

ctx = SchemaContext()
treat_union_nothing_as_optional!(ctx)
generate_schema(User; ctx=ctx)
```

With this configuration, the `birthdate` field is treated as optional.

## Default Type Mappings

Currently, the following types are mapped to JSON Schema.

| Julia Type                            | JSON Schema Type                                                    |
| ------------------------------------- | ------------------------------------------------------------------- |
| `Union{}`                             | `{"not": {}}`                                                       |
| `Tuple{}`                             | `{"type": "array", "maxItems": 0 }`                                 |
| `Bool`                                | `{"type": "boolean"}`                                               |
| Subtypes of `Integer` except `BigInt` | `{"type": "integer", "minimum": typemin(T), "maximum": typemax(T)}` |
| `BigInt`, `Integer`                   | `{"type": "integer"}`                                               |
| Subtypes of `AbstractFloat`           | `{"type": "number" }`                                               |
| Subtypes of `Rational`                | `{"type": "number" }`                                               |
| Subtypes of `Irrational`              | `{"type": "number" }`                                               |
| Subtypes of `AbstractString`          | `{"type": "string" }`                                               |
| `Char`                                | `{"type": "string", "minLength": 1, "maxLength": 1 }`               |
| `Symbol`                              | `{"type": "string" }`                                               |
| `Date`                                | `{"type": "string", "format": "date" }`                             |
| `DateTime`                            | `{"type": "string", "format": "date-time" }`                        |
| `Time`                                | `{"type": "string", "format": "time" }`                             |
| `Regex`                               | `{"type": "string", "format": "regex" }`                            |
| `VersionNumber`                       | `{"type": "string", "pattern": "^\\d+\\.\\d+\\.\\d+.*$" }`          |
| `Nothing`                             | `{"type": "null" }`                                                 |
| `Missing`                             | `{"type": "null" }`                                                 |
| `Any`                                 | `{}`                                                                |

### Collection Type Mappings

Here, `schema(T)` denotes the schema generated for type `T` (which becomes a `$ref`).

| Julia Type                                  | JSON Schema Type                                                                                               |
| ------------------------------------------- | -------------------------------------------------------------------------------------------------------------- |
| Subtypes of `AbstractArray`                 | `{"type": "array", "items": schema(eltype(T)) }`                                                               |
| Subtypes of `AbstractSet`                   | `{"type": "array", "items": schema(eltype(T)), "uniqueItems": true }`                                          |
| `Tuple{T1, T2, …, TN}` (no Vararg)          | `{"type": "array", "prefixItems": [schema(T1), …, schema(TN)], "minItems": N, "maxItems": N }`                 |
| `NTuple{N, T}`                              | `{"type": "array", "items": schema(T), "minItems": N, "maxItems": N }`                                         |
| `Tuple{Vararg{T}}` or `Tuple{Vararg{T, N}}` | `{"type": "array", "items": schema(T) }`                                                                       |
| `NamedTuple{(:a, :b, …), Tuple{TA, TB, …}}` | `{"type": "object", "properties": {"a": schema(TA), …}, "required": ["a", …], "additionalProperties": false }` |
| Subtypes of `AbstractDict{K, V}`            | `{"type": "object", "additionalProperties": schema(V) }`                                                       |

## Examples

For more detailed examples, see the [examples directory](https://github.com/abap34/Struct2JSONSchema.jl/tree/main/examples).

## API Reference

See the [API Reference](api.md) for detailed documentation of all exported functions.
