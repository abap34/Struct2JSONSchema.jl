"""
    register_abstract!(ctx, A;
                       variants,
                       discr_key,
                       tag_value,
                       require_discr=true)

Register discriminator metadata for the abstract type `A`. Each `variant` must
be a concrete subtype of `A`, and `tag_value` maps the variant to the JSON
scalar that should appear under `discr_key` in serialized data. When the
discriminator is registered, schemas for the variants will automatically
include the discriminator constraint.

# Arguments
- `ctx::SchemaContext`: context that stores the discriminator definition.
- `A::DataType`: abstract type whose variants are being described.

# Keyword Arguments
- `variants::Vector{DataType}`: concrete subtypes that can appear in place of `A`.
- `discr_key::String`: property name used to carry the discriminator.
- `tag_value`: dictionary mapping each variant to a unique JSON scalar.
- `require_discr`: whether the discriminator property must be present.

# Examples
```julia
ctx = SchemaContext()
register_abstract!(ctx, Animal;
    variants = [Cat, Dog],
    discr_key = "kind",
    tag_value = Dict(Cat => "cat", Dog => "dog"),
)
```
"""
function register_abstract!(
        ctx::SchemaContext, A::DataType;
        variants::Vector{DataType},
        discr_key::String,
        tag_value,
        require_discr::Bool = true
    )
    if !(tag_value isa AbstractDict)
        throw(ArgumentError("tag_value must be a dictionary of variant => discriminator"))
    end

    if !isabstracttype(A)
        throw(ArgumentError("Type $A is not abstract"))
    end

    for V in variants
        if !(V <: A)
            throw(ArgumentError("Variant $V is not a subtype of $A"))
        end
        if !isconcretetype(V)
            throw(ArgumentError("Variant $V must be concrete"))
        end
    end

    provided = Set{DataType}()
    for key in keys(tag_value)
        push!(provided, key)
    end
    if provided != Set(variants)
        throw(ArgumentError("tag_value keys must match provided variants"))
    end

    values_seen = Set{JSONScalar}()
    for (variant, val) in tag_value
        if !(val isa JSONScalar)
            throw(ArgumentError("Discriminator value for $variant must be a JSON scalar"))
        end
        push!(values_seen, val)
    end
    if length(values_seen) != length(tag_value)
        throw(ArgumentError("tag_value contains duplicate discriminator values"))
    end

    ctx.abstract_specs[A] = AbstractSpec(copy(variants), discr_key, Dict(tag_value), require_discr)
    return nothing
end

"""
    register_override!(ctx, T, generator)

Register a custom schema generator for the concrete type `T`. The `generator`
is a function that accepts a `SchemaContext` and returns a JSON schema `Dict`.
Overrides are used before the default generation logic and allow integration
with hand-written schemas.

# Examples
```julia
register_override!(ctx, UUID) do ctx
    return Dict("type" => "string", "format" => "uuid")
end
```
"""
register_override!(ctx::SchemaContext, T::DataType, generator::Function) = (ctx.overrides[T] = generator; nothing)

register_override!(generator::Function, ctx::SchemaContext, T::DataType) = register_override!(ctx, T, generator)

"""
    register_field_override!(ctx, T, field, generator)

Provide a schema override for an individual field on type `T`. `generator`
receives the active context and should return a JSON schema fragment for the
field located at `field`.
"""
register_field_override!(ctx::SchemaContext, T::DataType, field::Symbol, generator::Function) = (ctx.field_overrides[(T, field)] = generator; nothing)

register_field_override!(generator::Function, ctx::SchemaContext, T::DataType, field::Symbol) = register_field_override!(ctx, T, field, generator)

"""
    treat_union_nothing_as_optional!(ctx)

Enable automatic detection of `Union{T, Nothing}` fields as optional within the
provided context.
"""
treat_union_nothing_as_optional!(ctx::SchemaContext) = (ctx.auto_optional_union_nothing = true; nothing)

"""
    treat_union_missing_as_optional!(ctx)

Enable automatic detection of `Union{T, Missing}` fields as optional within the
provided context.
"""
treat_union_missing_as_optional!(ctx::SchemaContext) = (ctx.auto_optional_union_missing = true; nothing)

"""
    treat_null_as_optional!(ctx)

Enable both `treat_union_nothing_as_optional!` and
`treat_union_missing_as_optional!` for the given context.
"""
function treat_null_as_optional!(ctx::SchemaContext)
    ctx.auto_optional_union_nothing = true
    ctx.auto_optional_union_missing = true
    return nothing
end

"""
    generate_schema!(T; ctx=SchemaContext()) -> NamedTuple

Generate a JSON Schema for the Julia type `T`, storing intermediate definitions
in `ctx`. Returns a named tuple containing the complete schema document and any
unknown types encountered during generation. Because this function mutates the
context, it is well suited for incremental generation across many types.

# Returns
`(doc, unknowns)` where `doc` is a schema dictionary and `unknowns` is a set of
`(Type, path)` tuples that could not be represented.

# Examples
```julia
ctx = SchemaContext()
result = generate_schema!(MyStruct; ctx = ctx)
json_doc = result.doc
```
"""
function generate_schema!(T::Type; ctx::SchemaContext = SchemaContext())
    unknowns_before = copy(ctx.unknowns)
    Tn = normalize_type(T, ctx)
    define!(Tn, ctx)
    key = k(Tn, ctx)
    doc = Dict(
        "\$schema" => "https://json-schema.org/draft/2020-12/schema",
        "\$ref" => "#/\$defs/$key",
        "\$defs" => deepcopy(ctx.defs)
    )
    return (doc = doc, unknowns = setdiff(ctx.unknowns, unknowns_before))
end

"""
    generate_schema(T; ctx=SchemaContext()) -> NamedTuple

Generate a JSON Schema for `T` without mutating `ctx`. A clone of the supplied
context is created before delegating to `generate_schema!`, making this helper
suitable when you want to reuse `ctx` without sharing cached definitions.
"""
function generate_schema(T::Type; ctx::SchemaContext = SchemaContext())
    ctx_clone = clone_context(ctx)
    return generate_schema!(T; ctx = ctx_clone)
end
