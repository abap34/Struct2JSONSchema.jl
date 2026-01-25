# User Guide

This guide covers customization options and advanced features of Struct2JSONSchema.jl.

## Customization

[`generate_schema`](@ref) recursively generates schemas while updating a [`SchemaContext`](@ref).
By using [`override!`](@ref), users can hook into this process and customize the generated schema.

```julia
# Customize the generation so that UUID is represented as a string with format: uuid
using UUIDs
using JSON

struct User
    id::UUID
    name::String
end

ctx = SchemaContext()
override!(ctx) do ctx
    if current_type(ctx) === UUID
        return Dict("type" => "string", "format" => "uuid")
    end
    return nothing
end

result = generate_schema(User; ctx=ctx)
println(JSON.json(result.doc, 4))
```

[`SchemaContext`](@ref) provides the following accessor functions for customization:

* `current_type(ctx)` — the type currently being generated
* `current_parent(ctx)` — the parent struct, when generating a field
* `current_field(ctx)` — the field name, when generating a field

[`override!`](@ref) accepts a hook function that takes a `SchemaContext` object and returns either a schema `Dict`, or `nothing` to indicate that default generation should continue.

In practice, most customizations follow common patterns.
For this reason, several helper functions are provided.
Following customization are can be achieved using `override!`, but are more conveniently done using helper functions.

### Whole-type overrides: [`override_type!`](@ref)

Using [`override_type!`](@ref), a specific type can always be overridden for generation with the given `ctx`.
The following code is equivalent to the previous example.

```julia
using UUIDs

struct User
    id::UUID
    name::String
end

ctx = SchemaContext()
override_type!(ctx, UUID) do ctx
    Dict("type" => "string", "format" => "uuid")
end

result = generate_schema(User; ctx=ctx)
```

### Field-specific overrides: [`override_field!`](@ref)

Using [`override_field!`](@ref), an override can be applied only to a specific field of a specific struct.

```julia
struct User
    id::Int
    email::String
end

ctx = SchemaContext()
override_field!(ctx, User, :email) do ctx
    Dict("type" => "string", "format" => "email")
end

result = generate_schema(User; ctx=ctx)
```

### Abstract types: [`override_abstract!`](@ref)

Using [`override_abstract!`](@ref), an identifier-based schema can be generated for abstract types with concrete subtypes.

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

[`override_abstract!`](@ref) automatically generates such identifier-based schemas.

```julia
ctx = SchemaContext()

override_abstract!(
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

* [`optional!`](@ref) — explicitly mark fields as optional regardless of their type
* [`auto_optional_nothing!`](@ref) — treat `Union{T, Nothing}` fields as optional
* [`auto_optional_missing!`](@ref) — treat `Union{T, Missing}` fields as optional
* [`auto_optional_null!`](@ref) — treat both `Union{T, Nothing}` and `Union{T, Missing}` fields as optional

```julia
struct User
    id::Int
    name::String
    birthdate::Union{Date, Nothing}
    nickname::String
end

ctx = SchemaContext()
optional!(ctx, User, :nickname)
auto_optional_nothing!(ctx)
generate_schema(User; ctx=ctx)
```

With this configuration, both `birthdate` and `nickname` are treated as optional.

### Understanding Optional vs Nullable

There is an important distinction between **optional fields** and **nullable fields**:

**Without `auto_optional_nothing!`** (default behavior):
```julia
struct User
    name::String
    email::Union{String, Nothing}
end

result = generate_schema(User)
```

Generated schema:
- `email` is **required** (in `required` array)
- `email` accepts **both `String` and `null`** (via `anyOf`)

Valid JSON:
```json
{"name": "Alice", "email": "alice@example.com"}
{"name": "Bob", "email": null}
```

Invalid JSON:
```json
{"name": "Charlie"}  // email is missing
```

**With `auto_optional_nothing!`**:
```julia
ctx = SchemaContext()
auto_optional_nothing!(ctx)
result = generate_schema(User; ctx=ctx)
```

Generated schema:
- `email` is **not required** (not in `required` array)
- `email` accepts **only `String`** (no `null`, no `anyOf`)

Valid JSON:
```json
{"name": "Alice", "email": "alice@example.com"}
{"name": "Bob"}  // email can be omitted
```

Invalid JSON:
```json
{"name": "Charlie", "email": null}  // null is not allowed when field is present
```

In other words, when using `auto_optional_nothing!`, the `Nothing` in `Union{T, Nothing}` is treated as a marker for optionality in Julia, not as a nullable value in JSON.

## Skipping Fields

Use [`skip!`](@ref) to exclude fields or [`only!`](@ref) to include only specified fields:

```julia
struct User
    id::Int
    name::String
    _cache::Dict
end

ctx = SchemaContext()
skip!(ctx, User, :_cache)
# or equivalently:
# only!(ctx, User, :id, :name)

result = generate_schema(User; ctx=ctx)
```

Skipped fields are excluded from both `properties` and `required`.

## Field Descriptions

Struct2JSONSchema.jl can automatically extract field docstrings and add them as `description` properties in the JSON Schema.

### Automatic Extraction from Docstrings

By default, field docstrings are automatically extracted:

```julia
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

result = generate_schema(User)
# id and name fields will have "description" in the schema
```

This feature is controlled by the `auto_fielddoc` parameter in `SchemaContext` (default: `true`).

Note: Field docstrings can only be extracted if the struct itself also has a docstring. Without a docstring on the struct definition, field docstrings are not stored by Julia and cannot be automatically extracted.

### Manual Registration

You can manually register field descriptions using [`describe!`](@ref):

```julia
struct Product
    id::Int
    name::String
    price::Float64
end

ctx = SchemaContext()
describe!(ctx, Product, :price, "Product price in USD")

result = generate_schema(Product; ctx=ctx)
```

### Integration with Field Overrides

Field descriptions work together with field overrides:

```julia
struct Product
    id::Int
    price::Float64
end

ctx = SchemaContext()

# Override adds constraint
override_field!(ctx, Product, :price) do ctx
    Dict("type" => "number", "minimum" => 0)
end

# Description is added to the overridden schema
describe!(ctx, Product, :price, "Product price in USD")

result = generate_schema(Product; ctx=ctx)
# price field will be:
# {
#   "type": "number",
#   "minimum": 0,
#   "description": "Product price in USD"
# }
```

## Default Values

Use [`defaultvalue!`](@ref) to register default values for struct fields from an instance:

```julia
using Dates

struct ServerConfig
    host::String
    port::Int
    timeout::Float64
    started_at::DateTime
end

ctx = SchemaContext()

default_config = ServerConfig(
    "localhost",
    8080,
    30.0,
    DateTime(2024, 1, 1)
)

defaultvalue!(ctx, default_config)

result = generate_schema(ServerConfig; ctx=ctx)
# Each field will have a "default" property:
# - host: "localhost"
# - port: 8080
# - timeout: 30.0
# - started_at: "2024-01-01T00:00:00"
```

Nested structs are processed recursively, registering defaults at the leaf level:

```julia
struct Address
    street::String
    city::String
end

struct Profile
    name::String
    address::Address
end

ctx = SchemaContext()
default_profile = Profile("Alice", Address("Main St", "Metropolis"))
defaultvalue!(ctx, default_profile)

# Profile.name has default: "Alice"
# Profile.address does NOT have a default (it's a nested struct)
# Address.street has default: "Main St"
# Address.city has default: "Metropolis"
```

This ensures that default values are only set at the deepest level (leaf fields),
which is the correct behavior according to JSON Schema semantics.

### Custom Serializers

For custom types, register a serializer:

```julia
struct Color
    r::UInt8
    g::UInt8
    b::UInt8
end

struct Theme
    primary::Color
    secondary::Color
end

ctx = SchemaContext()

# Serialize Color as hex string
defaultvalue_type_serializer!(ctx, Color) do value, ctx
    r = string(value.r, base=16, pad=2)
    g = string(value.g, base=16, pad=2)
    b = string(value.b, base=16, pad=2)
    "#$(r)$(g)$(b)"
end

# Also customize the schema
override_type!(ctx, Color) do ctx
    Dict("type" => "string", "pattern" => "^#[0-9a-f]{6}\$")
end

default_theme = Theme(
    Color(0x00, 0x7b, 0xff),
    Color(0x6c, 0x75, 0x7d)
)

defaultvalue!(ctx, default_theme)
# primary.default: "#007bff"
# secondary.default: "#6c757d"
```

### Override Priority for Default Values

When an override sets a `"default"` property, it takes precedence over `defaultvalue!`:

```julia
struct Config
    formatter::String
end

ctx = SchemaContext()

# Override sets default
override_field!(ctx, Config, :formatter) do ctx
    Dict(
        "type" => "string",
        "enum" => ["JuliaFormatter", "Runic"],
        "default" => "JuliaFormatter"  # Override sets default
    )
end

# This will be ignored because override already set default
defaultvalue!(ctx, Config("Runic"))

result = generate_schema(Config; ctx=ctx)
# formatter.default: "JuliaFormatter" (from override, not "Runic")
```

## Registration Priorities

### Priority Summary

When multiple features are used together, the following priorities apply:

| Feature                  | Priority                                  |
| ------------------------ | ----------------------------------------- |
| Schema structure         | Override > Default generation             |
| `"default"` property     | Override > `defaultvalue!`                |
| `"description"` property | Override > `describe!` > Auto-extraction  |
| `required` array         | Independent: `optional!` > Auto-detection |

### Field Description Priority

Manual registration takes priority over automatic extraction:

1. Manual registration via `describe!` (highest priority)
2. Automatic extraction from field docstrings (if `auto_fielddoc=true`)
3. None (no description added)

Example:

```julia
"""
Event data
"""
struct Event
    """Event ID from docstring"""
    id::Int
end

ctx = SchemaContext()
describe!(ctx, Event, :id, "Event unique ID (overridden)")

result = generate_schema(Event; ctx=ctx)
# id will have "Event unique ID (overridden)" as description
```

### Override Evaluation Order

All `register_*_override!` functions internally call [`override!`](@ref), adding functions to `ctx.overrides` in FIFO (first-in, first-out) order.

```julia
ctx = SchemaContext()

override_type!(ctx, TypeA, gen1)      # 1st
override_field!(ctx, TypeB, :f, gen2) # 2nd
override_abstract!(ctx, AbstractType, ...)     # 3rd
```

When generating a schema:
1. The first registered function is evaluated
   - If it returns a `Dict`: use that result (stop evaluation)
   - If it returns `nothing`: continue to next
2. The second function is evaluated, and so on
3. First match wins

### How Different Systems Interact

The following are separate systems that can be used together:

- `ctx.overrides` — override mechanism
- `optional_fields(ctx)` — optional field management
- `field_descriptions(ctx)` — field description management
- `default_values(ctx)` — default value management

During field generation, they are processed in the following order:

1. Override evaluation → determines the field schema structure
2. Default value addition → adds `"default"` property if available and not set by override
3. Description addition → adds `"description"` property if available and not set by override
4. Optional fields check → determines if the field goes in `required` array (independent system)

### Example: All Features Combined

```julia
struct User
    id::Int
    email::String
end

ctx = SchemaContext()

# All four systems work together:
override_field!(ctx, User, :email) do ctx
    Dict("type" => "string", "format" => "email")
end

defaultvalue!(ctx, User(1, "user@example.com"))

optional!(ctx, User, :email)

describe!(ctx, User, :email, "User's email address")

result = generate_schema(User; ctx=ctx)
# email field will be:
# {
#   "type": "string",
#   "format": "email",           // from override
#   "default": "user@example.com", // from defaultvalue!
#   "description": "User's email address" // from describe!
# }
# - not in required array (from optional_fields)
```
