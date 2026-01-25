# API Reference

## Core Functions

```@docs
generate_schema
generate_schema!
```

## Context Management

```@docs
SchemaContext
UnknownEntry
```

## Type Registration

```@docs
register_abstract!
register_override!
register_type_override!
register_field_override!
register_optional_fields!
register_field_description!
```

## Optional Fields

```@docs
treat_union_nothing_as_optional!
treat_union_missing_as_optional!
treat_null_as_optional!
```

## Field Filtering

```@docs
register_skip_fields!
register_only_fields!
```

## Default Values

```@docs
register_defaults!
register_default_serializer!
register_default_type_serializer!
register_default_field_serializer!
default_serialize_for_schema
```

## Index

```@index
```
