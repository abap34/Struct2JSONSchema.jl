"""
    override_abstract!(ctx, A; variants, discr_key, tag_value, require_discr=true)

Register a discriminator schema for the abstract type `A`. `variants`
must be a vector of concrete subtypes, `discr_key` the discriminator field
name, and `tag_value` a `Dict` mapping each variant to a JSON scalar tag.
When `require_discr` is true the discriminator field is marked as required.
"""
function override_abstract!(
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

    provided = Set{DataType}(keys(tag_value))
    if provided != Set(variants)
        throw(ArgumentError("tag_value keys must match provided variants"))
    end

    values_seen = Set{RepresentableScalar}()
    for (variant, val) in tag_value
        if !(val isa RepresentableScalar)
            throw(ArgumentError("Discriminator value for $variant must be a representable scalar"))
        end
        push!(values_seen, val)
    end
    if length(values_seen) != length(tag_value)
        throw(ArgumentError("tag_value contains duplicate discriminator values"))
    end

    tags = Dict{DataType, RepresentableScalar}(tag_value)
    variants_copy = copy(variants)

    override!(ctx) do ctx
        if current_type(ctx) === A && current_field(ctx) === nothing
            return generate_abstract_schema(variants_copy, discr_key, tags, require_discr, ctx)
        end
        return nothing
    end
    return nothing
end

"""
    override!(generator, ctx)

Append a generic override function. `generator` receives the live
`SchemaContext` and must return a replacement schema `Dict` or
`nothing` to allow later overrides/default generation to run. Exceptions
are caught; when `ctx.verbose` is true a warning is logged before
falling back to the next candidate.
"""
function override!(generator::Function, ctx::SchemaContext)
    push!(ctx.overrides, generator)
    return nothing
end

"""
    override_type!(generator, ctx, T)

Convenience wrapper over [`override!`](@ref) that only fires
when the currently generated type is exactly `T`. The supplied `generator`
should return the full replacement schema for that type.
"""
function override_type!(generator::Function, ctx::SchemaContext, T::DataType)
    override!(ctx) do ctx
        if current_type(ctx) === T && current_field(ctx) === nothing
            return generator(ctx)
        end
        return nothing
    end
    return nothing
end

"""
    override_field!(generator, ctx, T, field)

Register a context-aware override for the field `field` on struct `T`.
The override runs while the field is visited and may return any schema
`Dict`. Returning `nothing` falls back to downstream overrides or the
default `\$ref`.
"""
function override_field!(generator::Function, ctx::SchemaContext, T::DataType, field::Symbol)
    override!(ctx) do ctx
        if current_parent(ctx) === T && current_field(ctx) === field
            return generator(ctx)
        end
        return nothing
    end
    return nothing
end

# Common validation helper for field registration APIs
function validate_struct_fields(T::Type, fields, context::String)
    if !(T isa DataType) || !isstructtype(T) || isabstracttype(T)
        throw(ArgumentError("Type $T must be a concrete struct when $context"))
    end
    allowed = Set(fieldnames(T))
    for field in fields
        if !(field in allowed)
            throw(ArgumentError("Type $T has no field $field"))
        end
    end
    return allowed
end

# Common registration helper for adding fields to IdDict{DataType, Set{Symbol}}
function register_to_field_set!(dict::IdDict, T::Type, fields)
    entry = get!(dict, T) do
        Set{Symbol}()
    end
    for field in fields
        push!(entry, field)
    end
    return nothing
end

"""
    optional!(ctx, T, fields...)

Mark specific fields on `T` as optional regardless of their declared types.
`fields` may be supplied as a collection of `Symbol`s or as varargs.
"""
function optional!(ctx::SchemaContext, T::Type, fields::Symbol...)
    isempty(fields) && return nothing
    validate_struct_fields(T, fields, "registering optional fields")
    register_to_field_set!(optional_fields(ctx), T, fields)
    return nothing
end

"""
    describe!(ctx, T, field, description)

Register a description for the field `field` on struct `T`.
The description will be added to the JSON Schema as the `description` property.
Manual registration takes priority over automatic extraction via `REPL.fielddoc`.
"""
function describe!(ctx::SchemaContext, T::Type, field::Symbol, description::String)
    validate_struct_fields(T, (field,), "registering field descriptions")
    field_descriptions(ctx)[(T, field)] = description
    return nothing
end

"""
    skip!(ctx, T, fields...)

Mark specific fields on `T` to be completely skipped (excluded from schema generation).
Skipped fields will not appear in `properties` or `required`.
`fields` may be supplied as a collection of `Symbol`s or as varargs.
"""
function skip!(ctx::SchemaContext, T::Type, fields::Symbol...)
    isempty(fields) && return nothing
    validate_struct_fields(T, fields, "registering skip fields")
    register_to_field_set!(skip_fields(ctx), T, fields)
    return nothing
end

"""
    only!(ctx, T, fields...)

Mark that only the specified fields on `T` should be included in the schema.
All other fields will be skipped. This is the inverse of `skip!`.
`fields` may be supplied as a collection of `Symbol`s or as varargs.
"""
function only!(ctx::SchemaContext, T::Type, fields::Symbol...)
    isempty(fields) && return nothing
    all_fields = validate_struct_fields(T, fields, "registering only fields")
    fields_to_skip = setdiff(all_fields, Set(fields))
    register_to_field_set!(skip_fields(ctx), T, fields_to_skip)
    return nothing
end

"""Enable automatic `Union{T,Nothing}` → optional field detection."""
auto_optional_nothing!(ctx::SchemaContext) = (ctx.options.auto_optional_union_nothing = true; nothing)

"""Enable automatic `Union{T,Missing}` → optional field detection."""
auto_optional_missing!(ctx::SchemaContext) = (ctx.options.auto_optional_union_missing = true; nothing)

"""
    auto_optional_null!(ctx)

Helper that enables both `Union{T,Nothing}` and `Union{T,Missing}`
detection in one call.
"""
function auto_optional_null!(ctx::SchemaContext)
    ctx.options.auto_optional_union_nothing = true
    ctx.options.auto_optional_union_missing = true
    return nothing
end

"""
    generate_schema!(T; ctx=SchemaContext(), simplify=true, inline_all_defs=false)

Materialize a schema for `T` using the provided mutable context.
`ctx` is updated in-place and the function returns a named tuple
with `doc` (the JSON schema document) and `unknowns`
(newly encountered unsupported types).

If `simplify=true` (default), the schema is simplified by removing unused definitions,
inlining single-use references, and sorting definitions.

If `inline_all_defs=true`, all `\$ref` references are expanded inline and the `\$defs`
section is removed entirely (except for recursive definitions which must remain in `\$defs`).
This option takes precedence over `simplify`.
"""
function generate_schema!(T::Type; ctx::SchemaContext = SchemaContext(), simplify::Bool = true, inline_all_defs::Bool = false)
    unknowns_before = copy(ctx.unknowns)
    Tn = normalize_type(T, ctx)
    define!(Tn, ctx)
    key = k(Tn, ctx)
    doc = Dict(
        "\$schema" => "https://json-schema.org/draft/2020-12/schema",
        "\$ref" => "#/\$defs/$key",
        "\$defs" => deepcopy(ctx.defs)
    )
    if inline_all_defs
        doc = expand_all_defs(doc)
    elseif simplify
        doc = simplify_schema(doc)
    end
    return (doc = doc, unknowns = setdiff(ctx.unknowns, unknowns_before))
end

"""
    generate_schema(T; ctx=SchemaContext(), simplify=true, inline_all_defs=false)

Variant of [`generate_schema!`](@ref) that clones the
provided context before generation. The original `ctx` is unaffected.

If `simplify=true` (default), the schema is simplified by removing unused definitions,
inlining single-use references, and sorting definitions.

If `inline_all_defs=true`, all `\$ref` references are expanded inline and the `\$defs`
section is removed entirely (except for recursive definitions which must remain in `\$defs`).
This option takes precedence over `simplify`.
"""
function generate_schema(T::Type; ctx::SchemaContext = SchemaContext(), simplify::Bool = true, inline_all_defs::Bool = false)
    ctx_clone = clone_context(ctx)
    return generate_schema!(T; ctx = ctx_clone, simplify = simplify, inline_all_defs = inline_all_defs)
end

# ===== Default Values API =====
# See src/defaults.jl for implementation details
