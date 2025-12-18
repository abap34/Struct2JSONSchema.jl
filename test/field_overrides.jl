using Test
using Struct2JSONSchema: SchemaContext, generate_schema, register_field_override!, register_override!, treat_union_nothing_as_optional!, k
using Dates

const _FIELD_OVERRIDE_KEY_CTX = SchemaContext()
field_override_key(T) = k(T, _FIELD_OVERRIDE_KEY_CTX)

@testset "Field-level overrides - basic usage" begin
    struct EventWithTimestamp
        id::Int
        timestamp::DateTime
        description::String
    end

    ctx = SchemaContext()
    register_field_override!(ctx, EventWithTimestamp, :timestamp) do ctx
        Dict(
            "type" => "string",
            "format" => "date-time"
        )
    end

    result = generate_schema(EventWithTimestamp; ctx = ctx)
    defs = result.doc["\$defs"]
    schema = defs[field_override_key(EventWithTimestamp)]

    @test schema["properties"]["timestamp"]["type"] == "string"
    @test schema["properties"]["timestamp"]["format"] == "date-time"
    @test haskey(schema["properties"]["id"], "\$ref")
    @test haskey(schema["properties"]["description"], "\$ref")
end

@testset "Field-level overrides - email format" begin
    struct UserWithEmail
        id::Int
        email::String
        name::String
    end

    ctx = SchemaContext()
    register_field_override!(ctx, UserWithEmail, :email) do ctx
        Dict(
            "type" => "string",
            "format" => "email",
            "pattern" => "^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}\$"
        )
    end

    result = generate_schema(UserWithEmail; ctx = ctx)
    defs = result.doc["\$defs"]
    schema = defs[field_override_key(UserWithEmail)]

    @test schema["properties"]["email"]["format"] == "email"
    @test haskey(schema["properties"]["email"], "pattern")
    @test schema["properties"]["email"]["type"] == "string"
end

@testset "Field-level overrides - multiple fields" begin
    struct Article
        id::Int
        created_at::DateTime
        updated_at::DateTime
        content::String
    end

    ctx = SchemaContext()

    for field in [:created_at, :updated_at]
        register_field_override!(ctx, Article, field) do ctx
            Dict(
                "type" => "string",
                "format" => "date-time"
            )
        end
    end

    result = generate_schema(Article; ctx = ctx)
    defs = result.doc["\$defs"]
    schema = defs[field_override_key(Article)]

    @test schema["properties"]["created_at"]["format"] == "date-time"
    @test schema["properties"]["updated_at"]["format"] == "date-time"
    @test haskey(schema["properties"]["content"], "\$ref")
end

@testset "Field-level overrides - priority over type-level" begin
    struct Product
        id::Int
        price::Float64
        discounted_price::Float64
    end

    ctx = SchemaContext()

    register_override!(ctx, Float64) do ctx
        Dict("type" => "number", "minimum" => 0)
    end

    register_field_override!(ctx, Product, :discounted_price) do ctx
        Dict(
            "type" => "number",
            "minimum" => 0,
            "maximum" => 1000000,
            "description" => "Discounted price with cap"
        )
    end

    result = generate_schema(Product; ctx = ctx)
    defs = result.doc["\$defs"]

    float_schema = defs[field_override_key(Float64)]
    @test float_schema["type"] == "number"
    @test float_schema["minimum"] == 0
    @test !haskey(float_schema, "maximum")

    product_schema = defs[field_override_key(Product)]
    @test product_schema["properties"]["discounted_price"]["maximum"] == 1000000
    @test product_schema["properties"]["discounted_price"]["description"] == "Discounted price with cap"
end

@testset "Field-level overrides - with nested types" begin
    struct Metadata
        version::String
        author::String
    end

    struct Document
        id::Int
        metadata::Metadata
        content::String
    end

    ctx = SchemaContext()

    register_field_override!(ctx, Document, :metadata) do ctx
        Dict(
            "type" => "object",
            "description" => "Document metadata with custom validation"
        )
    end

    result = generate_schema(Document; ctx = ctx)
    defs = result.doc["\$defs"]
    schema = defs[field_override_key(Document)]

    @test schema["properties"]["metadata"]["type"] == "object"
    @test schema["properties"]["metadata"]["description"] == "Document metadata with custom validation"
end

@testset "Field-level overrides - alternate syntax" begin
    struct Config
        timeout::Int
        retries::Int
    end

    ctx = SchemaContext()

    timeout_gen = ctx -> Dict("type" => "integer", "minimum" => 1, "maximum" => 3600)
    register_field_override!(timeout_gen, ctx, Config, :timeout)

    result = generate_schema(Config; ctx = ctx)
    defs = result.doc["\$defs"]
    schema = defs[field_override_key(Config)]

    @test schema["properties"]["timeout"]["minimum"] == 1
    @test schema["properties"]["timeout"]["maximum"] == 3600
end

@testset "Field-level overrides - combined with optional fields" begin
    struct OptionalTimestampRecord
        id::Int
        timestamp::Union{DateTime, Nothing}
        note::Union{String, Nothing}
    end

    ctx = SchemaContext()
    treat_union_nothing_as_optional!(ctx)

    register_field_override!(ctx, OptionalTimestampRecord, :timestamp) do ctx
        Dict(
            "anyOf" => [
                Dict("type" => "string", "format" => "date-time"),
                Dict("type" => "null"),
            ]
        )
    end

    result = generate_schema(OptionalTimestampRecord; ctx = ctx)
    defs = result.doc["\$defs"]
    schema = defs[field_override_key(OptionalTimestampRecord)]

    @test Set(schema["required"]) == Set(["id"])
    @test haskey(schema["properties"]["timestamp"], "anyOf")
    @test schema["properties"]["timestamp"]["anyOf"][1]["format"] == "date-time"
end

@testset "Type-level overrides - alternate syntax" begin
    struct MyCustomType
        value::Int
    end

    ctx = SchemaContext()

    custom_gen = ctx -> Dict("type" => "object", "description" => "Custom schema")
    register_override!(custom_gen, ctx, MyCustomType)

    result = generate_schema(MyCustomType; ctx = ctx)
    defs = result.doc["\$defs"]
    schema = defs[field_override_key(MyCustomType)]

    @test schema["description"] == "Custom schema"
end
