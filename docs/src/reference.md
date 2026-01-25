# Reference

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

## Collection Type Mappings

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
