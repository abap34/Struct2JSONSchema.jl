# Bug report: `simplify` option removes field descriptions

## Summary

When using `simplify=true` (default) with `treat_union_nothing_as_optional!`, field descriptions registered via `register_field_description!` are lost during schema simplification.

## Reproduction

```julia
using Struct2JSONSchema
using JSON

struct Inner
    value::Int
end

struct Outer
    inner::Union{Nothing, Inner}
end

ctx = SchemaContext()
treat_union_nothing_as_optional!(ctx)
register_field_description!(ctx, Outer, :inner, "Description for inner field")

# With simplify=true (default)
schema_simplified = generate_schema(Outer; ctx = ctx, simplify = true)
println("=== simplify=true (default) ===")
println(JSON.json(schema_simplified.doc, 2))

# With simplify=false
schema_not_simplified = generate_schema(Outer; ctx = ctx, simplify = false)
println("\n=== simplify=false ===")
println(JSON.json(schema_not_simplified.doc, 2))
```

## Output

### With `simplify=true` (default) - DESCRIPTION LOST

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "$ref": "#/$defs/Outer__1fc19aaafc04a831",
  "$defs": {
    "Outer__1fc19aaafc04a831": {
      "properties": {
        "inner": {
          "properties": {
            "value": {
              "minimum": -9223372036854775808,
              "type": "integer",
              "maximum": 9223372036854775807
            }
          },
          "required": [
            "value"
          ],
          "additionalProperties": false,
          "type": "object"
        }
      },
      "additionalProperties": false,
      "type": "object"
    }
  }
}
```

Note: The `"description": "Description for inner field"` is missing from the `inner` field.

### With `simplify=false` - DESCRIPTION PRESERVED

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "$ref": "#/$defs/Outer__1fc19aaafc04a831",
  "$defs": {
    "Int64__de86221664f86785": {
      "minimum": -9223372036854775808,
      "type": "integer",
      "maximum": 9223372036854775807
    },
    "Inner__5cb871ee54ab462d": {
      "properties": {
        "value": {
          "$ref": "#/$defs/Int64__de86221664f86785"
        }
      },
      "required": [
        "value"
      ],
      "additionalProperties": false,
      "type": "object"
    },
    "Outer__1fc19aaafc04a831": {
      "properties": {
        "inner": {
          "$ref": "#/$defs/Inner__5cb871ee54ab462d",
          "description": "Description for inner field"
        }
      },
      "required": [],
      "additionalProperties": false,
      "type": "object"
    }
  }
}
```

Note: The `"description": "Description for inner field"` is correctly present.

## Root cause

When `simplify=true`, the schema simplification process inlines schema definitions. During this inlining, the `description` field that was attached to the `$ref` wrapper is lost.

Before simplification (with description):
```json
{
  "$ref": "#/$defs/Inner__...",
  "description": "Description for inner field"
}
```

After simplification (description lost):
```json
{
  "properties": { ... },
  "required": [...],
  "additionalProperties": false,
  "type": "object"
}
```

The simplification logic replaces the entire schema object (including the description) with the inlined definition, discarding any additional metadata like `description`.

## Expected behavior

When simplifying schemas, any metadata (such as `description`) attached to the `$ref` wrapper should be preserved and merged into the inlined schema.

Expected output with `simplify=true`:
```json
{
  "properties": {
    "inner": {
      "properties": { ... },
      "required": [...],
      "additionalProperties": false,
      "type": "object",
      "description": "Description for inner field"
    }
  }
}
```

## Impact

This affects all fields with `Union{Nothing, T}` types when using `treat_union_nothing_as_optional!`, which is a common pattern for optional configuration fields.

## Workaround

Use `simplify=false` when generating schemas:

```julia
schema = generate_schema(MyType; ctx = ctx, simplify = false)
```

However, this produces larger schemas with many `$ref` indirections, which may not be ideal for some use cases.

## Related code

The simplification logic is likely in the schema generation or post-processing phase. The issue occurs when a `$ref` with additional properties (like `description`) is replaced with its target definition.
