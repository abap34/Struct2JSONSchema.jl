using Test
using Struct2JSONSchema: SchemaContext, generate_schema, treat_union_nothing_as_optional!, treat_union_missing_as_optional!, treat_null_as_optional!, register_optional_fields!, k

const _OPTIONAL_KEY_CTX = SchemaContext()
optional_key(T) = k(T, _OPTIONAL_KEY_CTX)

struct ExplicitOptionalRecord
    id::Int
    name::String
    notes::String
end

struct ExplicitOptionalMerge
    id::Int
    title::String
    description::String
    alias::String
end

@testset "Optional fields - explicit registration API" begin
    ctx_vector = SchemaContext()
    register_optional_fields!(ctx_vector, ExplicitOptionalRecord, :notes)
    result_vector = generate_schema(ExplicitOptionalRecord; ctx = ctx_vector)
    defs_vector = result_vector.doc["\$defs"]
    schema_vector = defs_vector[optional_key(ExplicitOptionalRecord)]
    @test Set(schema_vector["required"]) == Set(["id", "name"])
    @test "notes" ∉ schema_vector["required"]
    @test haskey(schema_vector["properties"], "notes")

    ctx_varargs = SchemaContext()
    register_optional_fields!(ctx_varargs, ExplicitOptionalMerge, :description, :alias)
    result_varargs = generate_schema(ExplicitOptionalMerge; ctx = ctx_varargs)
    defs_varargs = result_varargs.doc["\$defs"]
    schema_varargs = defs_varargs[optional_key(ExplicitOptionalMerge)]
    @test Set(schema_varargs["required"]) == Set(["id", "title"])
    @test "description" ∉ schema_varargs["required"]
    @test "alias" ∉ schema_varargs["required"]

    ctx_union = SchemaContext()
    register_optional_fields!(ctx_union, ExplicitOptionalMerge, :description)
    register_optional_fields!(ctx_union, ExplicitOptionalMerge, :alias)
    result_union = generate_schema(ExplicitOptionalMerge; ctx = ctx_union)
    defs_union = result_union.doc["\$defs"]
    schema_union = defs_union[optional_key(ExplicitOptionalMerge)]
    @test Set(schema_union["required"]) == Set(["id", "title"])

    ctx_error = SchemaContext()
    @test_throws ArgumentError register_optional_fields!(ctx_error, ExplicitOptionalRecord, :unknown)
    @test_throws ArgumentError register_optional_fields!(ctx_error, Union{String, Nothing}, :notes)
end

@testset "Optional fields - Union{T, Nothing}" begin
    struct UserWithNullableEmail
        id::Int
        name::String
        email::Union{String, Nothing}
    end

    # Test default behavior (nullable, required)
    ctx_default = SchemaContext()
    result_default = generate_schema(UserWithNullableEmail; ctx = ctx_default)
    defs_default = result_default.doc["\$defs"]
    schema_default = defs_default[optional_key(UserWithNullableEmail)]

    @test Set(schema_default["required"]) == Set(["id", "name", "email"])
    # email should reference Union{String, Nothing} with anyOf
    email_schema_ref = schema_default["properties"]["email"]
    @test haskey(email_schema_ref, "\$ref")
    union_key = email_schema_ref["\$ref"][9:end]  # Remove "#/$defs/" prefix
    union_schema = defs_default[union_key]
    @test haskey(union_schema, "anyOf")
    @test length(union_schema["anyOf"]) == 2

    # Test with treat_union_nothing_as_optional (optional, not nullable)
    ctx_optional = SchemaContext()
    treat_union_nothing_as_optional!(ctx_optional)
    result_optional = generate_schema(UserWithNullableEmail; ctx = ctx_optional)
    defs_optional = result_optional.doc["\$defs"]
    schema_optional = defs_optional[optional_key(UserWithNullableEmail)]

    @test Set(schema_optional["required"]) == Set(["id", "name"])
    @test "email" ∉ schema_optional["required"]
    @test haskey(schema_optional["properties"], "email")

    # email should reference String directly, NOT Union{String, Nothing}
    email_schema_ref_opt = schema_optional["properties"]["email"]
    @test haskey(email_schema_ref_opt, "\$ref")
    string_key = email_schema_ref_opt["\$ref"][9:end]  # Remove "#/$defs/" prefix
    string_schema = defs_optional[string_key]
    # Should be a simple string schema, not anyOf
    @test !haskey(string_schema, "anyOf")
    @test string_schema["type"] == "string"
end

@testset "Optional fields - Union{T, Missing}" begin
    struct DataRowWithMissingValue
        id::Int
        value::Union{Float64, Missing}
    end

    # Test default behavior (nullable with Missing, required)
    ctx_default = SchemaContext()
    result_default = generate_schema(DataRowWithMissingValue; ctx = ctx_default)
    defs_default = result_default.doc["\$defs"]
    schema_default = defs_default[optional_key(DataRowWithMissingValue)]

    @test Set(schema_default["required"]) == Set(["id", "value"])
    # value should reference Union{Float64, Missing} with anyOf
    value_schema_ref = schema_default["properties"]["value"]
    @test haskey(value_schema_ref, "\$ref")
    union_key = value_schema_ref["\$ref"][9:end]
    union_schema = defs_default[union_key]
    @test haskey(union_schema, "anyOf")
    @test length(union_schema["anyOf"]) == 2

    # Test with treat_union_missing_as_optional (optional, not nullable)
    ctx_optional = SchemaContext()
    treat_union_missing_as_optional!(ctx_optional)
    result_optional = generate_schema(DataRowWithMissingValue; ctx = ctx_optional)
    defs_optional = result_optional.doc["\$defs"]
    schema_optional = defs_optional[optional_key(DataRowWithMissingValue)]

    @test Set(schema_optional["required"]) == Set(["id"])
    @test "value" ∉ schema_optional["required"]
    @test haskey(schema_optional["properties"], "value")

    # value should reference Float64 directly, NOT Union{Float64, Missing}
    value_schema_ref_opt = schema_optional["properties"]["value"]
    @test haskey(value_schema_ref_opt, "\$ref")
    float_key = value_schema_ref_opt["\$ref"][9:end]
    float_schema = defs_optional[float_key]
    # Should be a simple number schema, not anyOf
    @test !haskey(float_schema, "anyOf")
    @test float_schema["type"] == "number"
end

@testset "Optional fields - treat_null_as_optional!" begin
    struct RecordWithBoth
        id::Int
        notes::Union{String, Nothing}
        score::Union{Float64, Missing}
        active::Bool
    end

    ctx = SchemaContext()
    treat_null_as_optional!(ctx)
    result = generate_schema(RecordWithBoth; ctx = ctx)
    defs = result.doc["\$defs"]
    schema = defs[optional_key(RecordWithBoth)]

    @test Set(schema["required"]) == Set(["id", "active"])
    @test "notes" ∉ schema["required"]
    @test "score" ∉ schema["required"]
    @test haskey(schema["properties"], "notes")
    @test haskey(schema["properties"], "score")
end

@testset "Optional fields - Union with more than 2 types" begin
    struct FlexibleField
        id::Int
        data::Union{String, Int, Nothing}
    end

    ctx = SchemaContext()
    treat_union_nothing_as_optional!(ctx)
    result = generate_schema(FlexibleField; ctx = ctx)
    defs = result.doc["\$defs"]
    schema = defs[optional_key(FlexibleField)]

    @test Set(schema["required"]) == Set(["id", "data"])
end

@testset "Optional fields - nested structs" begin
    struct Address
        street::String
        city::String
        zipcode::Union{String, Nothing}
    end

    struct PersonWithAddress
        name::String
        address::Address
        phone::Union{String, Nothing}
    end

    ctx = SchemaContext()
    treat_union_nothing_as_optional!(ctx)
    result = generate_schema(PersonWithAddress; ctx = ctx)
    defs = result.doc["\$defs"]

    person_schema = defs[optional_key(PersonWithAddress)]
    @test Set(person_schema["required"]) == Set(["name", "address"])

    address_schema = defs[optional_key(Address)]
    @test Set(address_schema["required"]) == Set(["street", "city"])
    @test "zipcode" ∉ address_schema["required"]
end

@testset "Optional fields - constructor parameters" begin
    ctx1 = SchemaContext(auto_optional_union_nothing = true)
    @test ctx1.auto_optional_union_nothing == true
    @test ctx1.auto_optional_union_missing == false

    ctx2 = SchemaContext(auto_optional_union_missing = true)
    @test ctx2.auto_optional_union_nothing == false
    @test ctx2.auto_optional_union_missing == true

    ctx3 = SchemaContext(
        auto_optional_union_nothing = true,
        auto_optional_union_missing = true
    )
    @test ctx3.auto_optional_union_nothing == true
    @test ctx3.auto_optional_union_missing == true
end

struct ExtendedUser
    id::Int
    username::String
    email::Union{String, Nothing}
    phone::Union{String, Nothing}
    bio::Union{String, Nothing}
end

@testset "optional fields - multiple Nothing unions" begin
    ctx = SchemaContext()
    treat_union_nothing_as_optional!(ctx)
    result = generate_schema(ExtendedUser; ctx = ctx)
    defs = result.doc["\$defs"]
    schema = defs[optional_key(ExtendedUser)]

    @test Set(schema["required"]) == Set(["id", "username"])
    @test "email" ∉ schema["required"]
    @test "phone" ∉ schema["required"]
    @test "bio" ∉ schema["required"]
    @test haskey(schema["properties"], "email")
    @test haskey(schema["properties"], "phone")
    @test haskey(schema["properties"], "bio")
end

struct SensorData
    timestamp::Int
    temperature::Union{Float64, Missing}
    humidity::Union{Float64, Missing}
    pressure::Union{Float64, Missing}
end

@testset "optional fields - multiple Missing unions" begin
    ctx = SchemaContext()
    treat_union_missing_as_optional!(ctx)
    result = generate_schema(SensorData; ctx = ctx)
    defs = result.doc["\$defs"]
    schema = defs[optional_key(SensorData)]

    @test Set(schema["required"]) == Set(["timestamp"])
    @test "temperature" ∉ schema["required"]
    @test "humidity" ∉ schema["required"]
    @test "pressure" ∉ schema["required"]
end

struct MixedOptional
    id::Int
    field1::Union{String, Nothing}
    field2::Union{Int, Nothing}
    field3::Union{Float64, Nothing}
    field4::Union{Bool, Nothing}
end

@testset "optional fields - various types with Nothing" begin
    ctx = SchemaContext()
    treat_union_nothing_as_optional!(ctx)
    result = generate_schema(MixedOptional; ctx = ctx)
    defs = result.doc["\$defs"]
    schema = defs[optional_key(MixedOptional)]

    @test Set(schema["required"]) == Set(["id"])
    @test "field1" ∉ schema["required"]
    @test "field2" ∉ schema["required"]
    @test "field3" ∉ schema["required"]
    @test "field4" ∉ schema["required"]
end

struct Department
    name::String
    manager::Union{String, Nothing}
    budget::Union{Float64, Nothing}
end

struct Company
    name::String
    departments::Vector{Department}
    ceo::Union{String, Nothing}
end

@testset "optional fields - deeply nested with optionals" begin
    ctx = SchemaContext()
    treat_union_nothing_as_optional!(ctx)
    result = generate_schema(Company; ctx = ctx)
    defs = result.doc["\$defs"]

    company_schema = defs[optional_key(Company)]
    @test Set(company_schema["required"]) == Set(["name", "departments"])
    @test "ceo" ∉ company_schema["required"]

    dept_schema = defs[optional_key(Department)]
    @test Set(dept_schema["required"]) == Set(["name"])
    @test "manager" ∉ dept_schema["required"]
    @test "budget" ∉ dept_schema["required"]
end

struct BlogPost
    title::String
    content::String
    author::Union{String, Nothing}
    tags::Union{Vector{String}, Nothing}
    published_at::Union{String, Nothing}
end

@testset "optional fields - complex types as optional" begin
    ctx = SchemaContext()
    treat_union_nothing_as_optional!(ctx)
    result = generate_schema(BlogPost; ctx = ctx)
    defs = result.doc["\$defs"]
    schema = defs[optional_key(BlogPost)]

    @test Set(schema["required"]) == Set(["title", "content"])
    @test "author" ∉ schema["required"]
    @test "tags" ∉ schema["required"]
    @test "published_at" ∉ schema["required"]
end

struct Config
    host::String
    port::Int
    username::Union{String, Nothing}
    password::Union{String, Nothing}
    ssl_enabled::Union{Bool, Nothing}
    timeout::Union{Int, Nothing}
end

@testset "optional fields - configuration schema" begin
    ctx = SchemaContext()
    treat_union_nothing_as_optional!(ctx)
    result = generate_schema(Config; ctx = ctx)
    defs = result.doc["\$defs"]
    schema = defs[optional_key(Config)]

    @test Set(schema["required"]) == Set(["host", "port"])
    @test "username" ∉ schema["required"]
    @test "password" ∉ schema["required"]
    @test "ssl_enabled" ∉ schema["required"]
    @test "timeout" ∉ schema["required"]
end

struct OptionalWithMissing
    id::Int
    data1::Union{String, Missing}
    data2::Union{Int, Missing}
    data3::Union{Bool, Missing}
end

@testset "optional fields - Missing with various types" begin
    ctx = SchemaContext()
    treat_union_missing_as_optional!(ctx)
    result = generate_schema(OptionalWithMissing; ctx = ctx)
    defs = result.doc["\$defs"]
    schema = defs[optional_key(OptionalWithMissing)]

    @test Set(schema["required"]) == Set(["id"])
    @test "data1" ∉ schema["required"]
    @test "data2" ∉ schema["required"]
    @test "data3" ∉ schema["required"]
end

struct AllOptional
    maybe1::Union{String, Nothing}
    maybe2::Union{Int, Nothing}
    maybe3::Union{Float64, Nothing}
end

@testset "optional fields - all fields optional" begin
    ctx = SchemaContext()
    treat_union_nothing_as_optional!(ctx)
    result = generate_schema(AllOptional; ctx = ctx)
    defs = result.doc["\$defs"]
    schema = defs[optional_key(AllOptional)]

    @test isempty(schema["required"])
    @test haskey(schema["properties"], "maybe1")
    @test haskey(schema["properties"], "maybe2")
    @test haskey(schema["properties"], "maybe3")
end

struct MixedNullTypes
    id::Int
    field_nothing::Union{String, Nothing}
    field_missing::Union{Int, Missing}
    field_both::Union{Float64, Nothing, Missing}
end

@testset "optional fields - mix of Nothing and Missing" begin
    ctx = SchemaContext()
    treat_null_as_optional!(ctx)
    result = generate_schema(MixedNullTypes; ctx = ctx)
    defs = result.doc["\$defs"]
    schema = defs[optional_key(MixedNullTypes)]

    @test Set(schema["required"]) == Set(["id", "field_both"])
    @test "field_nothing" ∉ schema["required"]
    @test "field_missing" ∉ schema["required"]
    @test "field_both" ∈ schema["required"]
end
