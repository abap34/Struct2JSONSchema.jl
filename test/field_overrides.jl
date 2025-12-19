using Test
using Struct2JSONSchema: SchemaContext, generate_schema, register_field_override!, register_type_override!, treat_union_nothing_as_optional!, k
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

    register_type_override!(ctx, Float64) do ctx
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
    register_type_override!(custom_gen, ctx, MyCustomType)

    result = generate_schema(MyCustomType; ctx = ctx)
    defs = result.doc["\$defs"]
    schema = defs[field_override_key(MyCustomType)]

    @test schema["description"] == "Custom schema"
end

struct ApiRequest
    method::String
    url::String
    headers::Dict{String, String}
    body::String
end

@testset "field overrides - multiple fields with format" begin
    ctx = SchemaContext()

    register_field_override!(ctx, ApiRequest, :url) do ctx
        Dict(
            "type" => "string",
            "format" => "uri",
            "pattern" => "^https?://"
        )
    end

    register_field_override!(ctx, ApiRequest, :method) do ctx
        Dict(
            "type" => "string",
            "enum" => ["GET", "POST", "PUT", "DELETE", "PATCH"]
        )
    end

    result = generate_schema(ApiRequest; ctx = ctx)
    defs = result.doc["\$defs"]
    schema = defs[field_override_key(ApiRequest)]

    @test schema["properties"]["url"]["format"] == "uri"
    @test haskey(schema["properties"]["url"], "pattern")
    @test schema["properties"]["method"]["enum"] == ["GET", "POST", "PUT", "DELETE", "PATCH"]
end

struct Coordinates
    latitude::Float64
    longitude::Float64
end

@testset "field overrides - range constraints" begin
    ctx = SchemaContext()

    register_field_override!(ctx, Coordinates, :latitude) do ctx
        Dict(
            "type" => "number",
            "minimum" => -90,
            "maximum" => 90
        )
    end

    register_field_override!(ctx, Coordinates, :longitude) do ctx
        Dict(
            "type" => "number",
            "minimum" => -180,
            "maximum" => 180
        )
    end

    result = generate_schema(Coordinates; ctx = ctx)
    defs = result.doc["\$defs"]
    schema = defs[field_override_key(Coordinates)]

    @test schema["properties"]["latitude"]["minimum"] == -90
    @test schema["properties"]["latitude"]["maximum"] == 90
    @test schema["properties"]["longitude"]["minimum"] == -180
    @test schema["properties"]["longitude"]["maximum"] == 180
end

struct StringValidation
    username::String
    password::String
    zipcode::String
end

@testset "field overrides - string length constraints" begin
    ctx = SchemaContext()

    register_field_override!(ctx, StringValidation, :username) do ctx
        Dict(
            "type" => "string",
            "minLength" => 3,
            "maxLength" => 20
        )
    end

    register_field_override!(ctx, StringValidation, :password) do ctx
        Dict(
            "type" => "string",
            "minLength" => 8
        )
    end

    register_field_override!(ctx, StringValidation, :zipcode) do ctx
        Dict(
            "type" => "string",
            "pattern" => "^\\d{5}(-\\d{4})?\$"
        )
    end

    result = generate_schema(StringValidation; ctx = ctx)
    defs = result.doc["\$defs"]
    schema = defs[field_override_key(StringValidation)]

    @test schema["properties"]["username"]["minLength"] == 3
    @test schema["properties"]["username"]["maxLength"] == 20
    @test schema["properties"]["password"]["minLength"] == 8
    @test haskey(schema["properties"]["zipcode"], "pattern")
end

struct Pagination
    page::Int
    page_size::Int
    total::Int
end

@testset "field overrides - integer constraints" begin
    ctx = SchemaContext()

    register_field_override!(ctx, Pagination, :page) do ctx
        Dict(
            "type" => "integer",
            "minimum" => 1
        )
    end

    register_field_override!(ctx, Pagination, :page_size) do ctx
        Dict(
            "type" => "integer",
            "minimum" => 1,
            "maximum" => 100
        )
    end

    result = generate_schema(Pagination; ctx = ctx)
    defs = result.doc["\$defs"]
    schema = defs[field_override_key(Pagination)]

    @test schema["properties"]["page"]["minimum"] == 1
    @test schema["properties"]["page_size"]["minimum"] == 1
    @test schema["properties"]["page_size"]["maximum"] == 100
end

struct MediaFile
    filename::String
    content_type::String
    size_bytes::Int
end

@testset "field overrides - MIME type validation" begin
    ctx = SchemaContext()

    register_field_override!(ctx, MediaFile, :content_type) do ctx
        Dict(
            "type" => "string",
            "pattern" => "^[a-z]+/[a-z0-9\\-\\+\\.]+\$",
            "examples" => ["image/png", "video/mp4", "application/json"]
        )
    end

    result = generate_schema(MediaFile; ctx = ctx)
    defs = result.doc["\$defs"]
    schema = defs[field_override_key(MediaFile)]

    @test haskey(schema["properties"]["content_type"], "pattern")
    @test haskey(schema["properties"]["content_type"], "examples")
end

struct AccountInfo
    account_id::String
    balance::Float64
    currency::String
end

@testset "field overrides - currency and UUID" begin
    ctx = SchemaContext()

    register_field_override!(ctx, AccountInfo, :account_id) do ctx
        Dict(
            "type" => "string",
            "format" => "uuid"
        )
    end

    register_field_override!(ctx, AccountInfo, :currency) do ctx
        Dict(
            "type" => "string",
            "enum" => ["USD", "EUR", "GBP", "JPY"]
        )
    end

    result = generate_schema(AccountInfo; ctx = ctx)
    defs = result.doc["\$defs"]
    schema = defs[field_override_key(AccountInfo)]

    @test schema["properties"]["account_id"]["format"] == "uuid"
    @test schema["properties"]["currency"]["enum"] == ["USD", "EUR", "GBP", "JPY"]
end

struct ReviewData
    rating::Int
    comment::String
    created_at::String
end

@testset "field overrides - rating and timestamp" begin
    ctx = SchemaContext()

    register_field_override!(ctx, ReviewData, :rating) do ctx
        Dict(
            "type" => "integer",
            "minimum" => 1,
            "maximum" => 5
        )
    end

    register_field_override!(ctx, ReviewData, :created_at) do ctx
        Dict(
            "type" => "string",
            "format" => "date-time"
        )
    end

    result = generate_schema(ReviewData; ctx = ctx)
    defs = result.doc["\$defs"]
    schema = defs[field_override_key(ReviewData)]

    @test schema["properties"]["rating"]["minimum"] == 1
    @test schema["properties"]["rating"]["maximum"] == 5
    @test schema["properties"]["created_at"]["format"] == "date-time"
end
