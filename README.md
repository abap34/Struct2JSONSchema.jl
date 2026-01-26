# Struct2JSONSchema.jl

[![Documentation](https://img.shields.io/badge/docs-dev-blue.svg)](https://abap34.github.io/Struct2JSONSchema.jl/dev/)
[![codecov](https://codecov.io/gh/abap34/Struct2JSONSchema.jl/graph/badge.svg?token=BCPD8253CO)](https://codecov.io/gh/abap34/Struct2JSONSchema.jl)
[![Build Status](https://github.com/abap34/Struct2JSONSchema.jl/actions/workflows/CI.yml/badge.svg?branch=main)](https://github.com/abap34/Struct2JSONSchema.jl/actions/workflows/CI.yml?query=branch%3Amain)

Struct2JSONSchema.jl is a Julia package that converts Julia structs into JSON Schema documents compliant with JSON Schema draft 2020-12.

## Concepts

* **Non-invasive**: Generate JSON Schema without modifying existing struct definitions.
* **Extensibility**: Allow customization of schema generation for user-defined types and constraints.
* **Robustness**: Never raises an error; unrepresentable types are conservatively handled as `Any`.
* **Long-term maintainability**: Simple implementation with minimal dependencies.

For the design principles behind this package, see
[https://abap34.github.io/Struct2JSONSchema.jl/dev/#Concepts](https://abap34.github.io/Struct2JSONSchema.jl/dev/#Concepts)

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
println(JSON.json(doc, 4))
# {
#    "$schema": "https://json-schema.org/draft/2020-12/schema",
#    "$ref": "#/$defs/User__2fe39a6325a38198",
#  ...
```

## Customization

We provide both a hook mechanism for expressive schema generation and a set of utility functions designed to make common customizations straightforward.

This allows users to define desirable constraints and formats for any type definition.


```julia
using UUIDs
using JSON

struct User
    id::UUID
    name::String
end

ctx = SchemaContext()

# Hooking into the generation process
override!(ctx) do ctx
    if current_parent(ctx) == User && current_field(ctx) == :id
        return Dict("type" => "string", "format" => "uuid")
    else
        return nothing
    end
end
```

The same behavior can be expressed more concisely using a utility function:

```julia
struct User
    id::Int
    email::String
end

ctx = SchemaContext()

# Using a convenience utility function
override_field!(ctx, User, :email) do ctx
    Dict("type" => "string", "format" => "email")
end
```

Additional utilities are provided for tasks such as:

* Marking specific fields as optional or skipped.
* Treating `Union{T, Nothing}` and `Union{T, Missing}` as optional fields.
* Registering custom expansion strategies for abstract types.
* Adding field descriptions from docstrings or manual registration.
* Setting default values for fields.

For detailed customization options, see
[https://abap34.github.io/Struct2JSONSchema.jl/dev/#Customization](https://abap34.github.io/Struct2JSONSchema.jl/dev/#Customization)

## Examples

See the [examples directory](examples/) for additional usage examples.
