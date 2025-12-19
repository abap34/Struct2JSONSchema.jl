"""
    register_abstract!(ctx, A; variants, discr_key, tag_value, require_discr=true)

Register a discriminator schema for the abstract type `A`. `variants`
must be a vector of concrete subtypes, `discr_key` the discriminator field
name, and `tag_value` a `Dict` mapping each variant to a JSON scalar tag.
When `require_discr` is true the discriminator field is marked as required.
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

    tags = Dict{DataType, JSONScalar}(tag_value)
    variants_copy = copy(variants)

    register_override!(ctx) do ctx
        if ctx.current_type === A && ctx.current_field === nothing
            return generate_abstract_schema(variants_copy, discr_key, tags, require_discr, ctx)
        end
        return nothing
    end
    return nothing
end

"""
    register_override!(ctx, generator)

Append a generic override function. `generator` receives the live
`SchemaContext` and must return a replacement schema `Dict` or
`nothing` to allow later overrides/default generation to run. Exceptions
are caught; when `ctx.verbose` is true a warning is logged before
falling back to the next candidate.
"""
function register_override!(generator::Function, ctx::SchemaContext)
    push!(ctx.overrides, generator)
    return nothing
end

"""
    register_type_override!(ctx, T, generator)

Convenience wrapper over [`register_override!`](@ref) that only fires
when the currently generated type is exactly `T`. The supplied `generator`
should return the full replacement schema for that type.
"""
function register_type_override!(generator::Function, ctx::SchemaContext, T::DataType)
    register_override!(ctx) do ctx
        if ctx.current_type === T && ctx.current_field === nothing
            return generator(ctx)
        end
        return nothing
    end
    return nothing
end

"""
    register_field_override!(ctx, T, field, generator)

Register a context-aware override for the field `field` on struct `T`.
The override runs while the field is visited and may return any schema
`Dict`. Returning `nothing` falls back to downstream overrides or the
default `\$ref`.
"""
function register_field_override!(generator::Function, ctx::SchemaContext, T::DataType, field::Symbol)
    register_override!(ctx) do ctx
        if ctx.current_parent === T && ctx.current_field === field
            return generator(ctx)
        end
        return nothing
    end
    return nothing
end

"""Enable automatic `Union{T,Nothing}` → optional field detection."""
treat_union_nothing_as_optional!(ctx::SchemaContext) = (ctx.auto_optional_union_nothing = true; nothing)

"""Enable automatic `Union{T,Missing}` → optional field detection."""
treat_union_missing_as_optional!(ctx::SchemaContext) = (ctx.auto_optional_union_missing = true; nothing)

"""
    treat_null_as_optional!(ctx)

Helper that enables both `Union{T,Nothing}` and `Union{T,Missing}`
detection in one call.
"""
function treat_null_as_optional!(ctx::SchemaContext)
    ctx.auto_optional_union_nothing = true
    ctx.auto_optional_union_missing = true
    return nothing
end

"""
    generate_schema!(T; ctx=SchemaContext())

Materialize a schema for `T` using the provided mutable context.
`ctx` is updated in-place and the function returns a named tuple
with `doc` (the JSON schema document) and `unknowns`
(newly encountered unsupported types).
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
    generate_schema(T; ctx=SchemaContext())

Variant of [`generate_schema!`](@ref) that clones the
provided context before generation. The original `ctx` is unaffected.
"""
function generate_schema(T::Type; ctx::SchemaContext = SchemaContext())
    ctx_clone = clone_context(ctx)
    return generate_schema!(T; ctx = ctx_clone)
end
