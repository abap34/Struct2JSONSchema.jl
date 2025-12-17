using Test
using Struct2JSONSchema: SchemaContext, generate_schema, treat_union_nothing_as_optional!, treat_union_missing_as_optional!, treat_null_as_optional!, k

const _OPTIONAL_KEY_CTX = SchemaContext()
optional_key(T) = k(T, _OPTIONAL_KEY_CTX)

@testset "Optional fields - Union{T, Nothing}" begin
    struct UserWithNullableEmail
        id::Int
        name::String
        email::Union{String, Nothing}
    end

    ctx_default = SchemaContext()
    result_default = generate_schema(UserWithNullableEmail; ctx=ctx_default)
    defs_default = result_default.doc["\$defs"]
    schema_default = defs_default[optional_key(UserWithNullableEmail)]

    @test Set(schema_default["required"]) == Set(["id", "name", "email"])

    ctx_optional = SchemaContext()
    treat_union_nothing_as_optional!(ctx_optional)
    result_optional = generate_schema(UserWithNullableEmail; ctx=ctx_optional)
    defs_optional = result_optional.doc["\$defs"]
    schema_optional = defs_optional[optional_key(UserWithNullableEmail)]

    @test Set(schema_optional["required"]) == Set(["id", "name"])
    @test "email" ∉ schema_optional["required"]
    @test haskey(schema_optional["properties"], "email")
end

@testset "Optional fields - Union{T, Missing}" begin
    struct DataRowWithMissingValue
        id::Int
        value::Union{Float64, Missing}
    end

    ctx_default = SchemaContext()
    result_default = generate_schema(DataRowWithMissingValue; ctx=ctx_default)
    defs_default = result_default.doc["\$defs"]
    schema_default = defs_default[optional_key(DataRowWithMissingValue)]

    @test Set(schema_default["required"]) == Set(["id", "value"])

    ctx_optional = SchemaContext()
    treat_union_missing_as_optional!(ctx_optional)
    result_optional = generate_schema(DataRowWithMissingValue; ctx=ctx_optional)
    defs_optional = result_optional.doc["\$defs"]
    schema_optional = defs_optional[optional_key(DataRowWithMissingValue)]

    @test Set(schema_optional["required"]) == Set(["id"])
    @test "value" ∉ schema_optional["required"]
    @test haskey(schema_optional["properties"], "value")
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
    result = generate_schema(RecordWithBoth; ctx=ctx)
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
    result = generate_schema(FlexibleField; ctx=ctx)
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
    result = generate_schema(PersonWithAddress; ctx=ctx)
    defs = result.doc["\$defs"]

    person_schema = defs[optional_key(PersonWithAddress)]
    @test Set(person_schema["required"]) == Set(["name", "address"])

    address_schema = defs[optional_key(Address)]
    @test Set(address_schema["required"]) == Set(["street", "city"])
    @test "zipcode" ∉ address_schema["required"]
end

@testset "Optional fields - constructor parameters" begin
    ctx1 = SchemaContext(auto_optional_union_nothing=true)
    @test ctx1.auto_optional_union_nothing == true
    @test ctx1.auto_optional_union_missing == false

    ctx2 = SchemaContext(auto_optional_union_missing=true)
    @test ctx2.auto_optional_union_nothing == false
    @test ctx2.auto_optional_union_missing == true

    ctx3 = SchemaContext(
        auto_optional_union_nothing=true,
        auto_optional_union_missing=true
    )
    @test ctx3.auto_optional_union_nothing == true
    @test ctx3.auto_optional_union_missing == true
end
