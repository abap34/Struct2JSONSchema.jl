function register_abstract!(ctx::SchemaContext, A::DataType;
        variants::Vector{DataType},
        discr_key::String,
        tag_value,
        require_discr::Bool=true)
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

register_override!(ctx::SchemaContext, T::DataType, generator::Function) = (ctx.overrides[T] = generator; nothing)

register_override!(generator::Function, ctx::SchemaContext, T::DataType) = register_override!(ctx, T, generator)

# Field-level overrides
register_field_override!(ctx::SchemaContext, T::DataType, field::Symbol, generator::Function) = (ctx.field_overrides[(T, field)] = generator; nothing)

register_field_override!(generator::Function, ctx::SchemaContext, T::DataType, field::Symbol) = register_field_override!(ctx, T, field, generator)

# Optional field helpers
treat_union_nothing_as_optional!(ctx::SchemaContext) = (ctx.auto_optional_union_nothing = true; nothing)

treat_union_missing_as_optional!(ctx::SchemaContext) = (ctx.auto_optional_union_missing = true; nothing)

function treat_null_as_optional!(ctx::SchemaContext)
    ctx.auto_optional_union_nothing = true
    ctx.auto_optional_union_missing = true
    nothing
end

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
    (doc=doc, unknowns=setdiff(ctx.unknowns, unknowns_before))
end

function generate_schema(T::Type; ctx::SchemaContext = SchemaContext())
    ctx_clone = clone_context(ctx)
    generate_schema!(T; ctx=ctx_clone)
end
