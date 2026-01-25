using Test
using Struct2JSONSchema: SchemaContext, generate_schema, generate_schema!, register_abstract!, register_override!, register_type_override!, register_field_override!, k, define!, current_type, current_parent, current_field, UnknownEntry
using Dates
import Logging

struct WithFunctionField
    handler::Function
end

struct TimestampRecord
    happened_at::DateTime
end

struct PlainType end

struct OverrideDemo
    amount::Int64
end

struct VerboseVectorHolder
    data::Vector
end

const _CTX_KEY_CTX = SchemaContext()
ctx_key(T) = k(T, _CTX_KEY_CTX)

@testset "generate_schema context isolation" begin
    ctx = SchemaContext()
    safe_result = generate_schema(WithFunctionField; ctx = ctx, simplify = false)
    @test isempty(ctx.defs)
    @test isempty(ctx.unknowns)

    bang_ctx = SchemaContext()
    result = generate_schema!(WithFunctionField; ctx = bang_ctx, simplify = false)
    @test !isempty(bang_ctx.defs)
    @test result.unknowns == Set([UnknownEntry(Function, (:handler,), "abstract_no_discriminator")])

    second = generate_schema!(WithFunctionField; ctx = bang_ctx, simplify = false)
    @test isempty(second.unknowns)
end

@testset "register_abstract! validation" begin
    ctx = SchemaContext()
    @test_throws ArgumentError register_abstract!(
        ctx, PlainType;
        variants = DataType[],
        discr_key = "kind",
        tag_value = Dict{DataType, Union{String, Int, Float64, Bool, Nothing}}(),
        require_discr = true
    )
end

@testset "Overrides customize definitions" begin
    ctx = SchemaContext()

    register_type_override!(ctx, DateTime) do ctx
        Dict(
            "type" => "string",
            "format" => "date-time",
            "description" => "custom date-time"
        )
    end

    register_type_override!(ctx, OverrideDemo) do ctx
        push!(ctx.path, :amount)
        define!(Int64, ctx)
        pop!(ctx.path)
        Dict(
            "type" => "object",
            "properties" => Dict(
                "amount" => Dict(
                    "type" => "number",
                    "minimum" => 0
                )
            ),
            "required" => ["amount"],
            "additionalProperties" => false
        )
    end

    timestamp = generate_schema(TimestampRecord; ctx = ctx, simplify = false)
    defs = timestamp.doc["\$defs"]
    datetime_def = defs[ctx_key(DateTime)]
    @test datetime_def["description"] == "custom date-time"

    demo = generate_schema(OverrideDemo; ctx = ctx, simplify = false)
    demo_defs = demo.doc["\$defs"]
    schema = demo_defs[ctx_key(OverrideDemo)]
    @test schema["properties"]["amount"]["type"] == "number"
    @test schema["properties"]["amount"]["minimum"] == 0
end

@testset "Verbose mode logging" begin
    # verbose=false (default): no logs should be emitted at any level
    ctx = SchemaContext()
    @test_logs min_level = Logging.Debug begin
        generate_schema(VerboseVectorHolder; ctx = ctx, simplify = false)
    end

    # verbose=true: info logs should be emitted
    verbose_ctx = SchemaContext(verbose = true)
    @test_logs (:info, r"UnionAll type Vector encountered") min_level = Logging.Debug begin
        generate_schema(VerboseVectorHolder; ctx = verbose_ctx, simplify = false)
    end
end

struct SimpleStruct1
    value::Int
end

struct SimpleStruct2
    name::String
end

@testset "context isolation tests" begin
    ctx = SchemaContext()
    result1 = generate_schema(SimpleStruct1; ctx = ctx, simplify = false)
    @test isempty(ctx.defs)
    @test isempty(ctx.unknowns)

    result2 = generate_schema(SimpleStruct2; ctx = ctx, simplify = false)
    @test isempty(ctx.defs)
    @test isempty(ctx.unknowns)
end

struct BangTestStruct1
    field::String
end

struct BangTestStruct2
    field::Int
end

@testset "generate_schema! tests" begin
    bang_ctx = SchemaContext()
    result1 = generate_schema!(BangTestStruct1; ctx = bang_ctx, simplify = false)
    @test !isempty(bang_ctx.defs)

    result2 = generate_schema!(BangTestStruct2; ctx = bang_ctx, simplify = false)
    @test length(bang_ctx.defs) > 1
end

struct OverrideTarget1
    value::Int
end

struct OverrideTarget2
    data::String
end

@testset "override tests" begin
    ctx = SchemaContext()

    register_type_override!(ctx, OverrideTarget1) do ctx
        Dict("type" => "object", "description" => "Override 1")
    end

    register_type_override!(ctx, OverrideTarget2) do ctx
        Dict("type" => "object", "description" => "Override 2")
    end

    result1 = generate_schema(OverrideTarget1; ctx = ctx, simplify = false)
    schema1 = result1.doc["\$defs"][ctx_key(OverrideTarget1)]
    @test schema1["description"] == "Override 1"

    result2 = generate_schema(OverrideTarget2; ctx = ctx, simplify = false)
    schema2 = result2.doc["\$defs"][ctx_key(OverrideTarget2)]
    @test schema2["description"] == "Override 2"
end

struct CustomInt32
    value::Int32
end

struct CustomInt64
    value::Int64
end

@testset "primitive type override tests" begin
    ctx = SchemaContext()

    register_type_override!(ctx, Int32) do ctx
        Dict("type" => "integer", "description" => "Custom Int32")
    end

    register_type_override!(ctx, Int64) do ctx
        Dict("type" => "integer", "description" => "Custom Int64")
    end

    result32 = generate_schema(CustomInt32; ctx = ctx, simplify = false)
    int32_def = result32.doc["\$defs"][ctx_key(Int32)]
    @test int32_def["description"] == "Custom Int32"

    result64 = generate_schema(CustomInt64; ctx = ctx, simplify = false)
    int64_def = result64.doc["\$defs"][ctx_key(Int64)]
    @test int64_def["description"] == "Custom Int64"
end

struct UnknownHolder1
    data::Vector
end

struct UnknownHolder2
    items::Vector
end

@testset "unknown type tracking tests" begin
    ctx = SchemaContext()

    result1 = generate_schema(UnknownHolder1; ctx = ctx, simplify = false)
    @test result1.unknowns == Set([UnknownEntry(Vector, (:data,), "unionall_type")])

    result2 = generate_schema(UnknownHolder2; ctx = ctx, simplify = false)
    @test result2.unknowns == Set([UnknownEntry(Vector, (:items,), "unionall_type")])
end

struct URLContainer
    homepage::String
    api_endpoint::String
end

@testset "field override - multiple fields" begin
    ctx = SchemaContext()

    register_field_override!(ctx, URLContainer, :homepage) do ctx
        Dict(
            "type" => "string",
            "format" => "uri",
            "description" => "Homepage URL"
        )
    end

    register_field_override!(ctx, URLContainer, :api_endpoint) do ctx
        Dict(
            "type" => "string",
            "format" => "uri",
            "pattern" => "^https://.*"
        )
    end

    result = generate_schema(URLContainer; ctx = ctx, simplify = false)
    schema = result.doc["\$defs"][ctx_key(URLContainer)]

    @test schema["properties"]["homepage"]["format"] == "uri"
    @test schema["properties"]["homepage"]["description"] == "Homepage URL"
    @test schema["properties"]["api_endpoint"]["format"] == "uri"
    @test schema["properties"]["api_endpoint"]["pattern"] == "^https://.*"
end

struct EmailContainer
    primary::String
    secondary::String
end

@testset "field override - same override for multiple fields" begin
    ctx = SchemaContext()

    register_field_override!(ctx, EmailContainer, :primary) do ctx
        Dict(
            "type" => "string",
            "format" => "email"
        )
    end

    register_field_override!(ctx, EmailContainer, :secondary) do ctx
        Dict(
            "type" => "string",
            "format" => "email"
        )
    end

    result = generate_schema(EmailContainer; ctx = ctx, simplify = false)
    schema = result.doc["\$defs"][ctx_key(EmailContainer)]

    @test schema["properties"]["primary"]["format"] == "email"
    @test schema["properties"]["secondary"]["format"] == "email"
end

struct ScoreRecord
    id::Int
    score::Float64
end

@testset "field override - numeric constraints" begin
    ctx = SchemaContext()

    register_field_override!(ctx, ScoreRecord, :score) do ctx
        Dict(
            "type" => "number",
            "minimum" => 0.0,
            "maximum" => 100.0,
            "description" => "Score between 0 and 100"
        )
    end

    result = generate_schema(ScoreRecord; ctx = ctx, simplify = false)
    schema = result.doc["\$defs"][ctx_key(ScoreRecord)]

    @test schema["properties"]["score"]["minimum"] == 0.0
    @test schema["properties"]["score"]["maximum"] == 100.0
    @test schema["properties"]["score"]["description"] == "Score between 0 and 100"
end

struct StringLengthRecord
    username::String
    bio::String
end

@testset "field override - string length constraints" begin
    ctx = SchemaContext()

    register_field_override!(ctx, StringLengthRecord, :username) do ctx
        Dict(
            "type" => "string",
            "minLength" => 3,
            "maxLength" => 20,
            "pattern" => "^[a-zA-Z0-9_]+\$"
        )
    end

    register_field_override!(ctx, StringLengthRecord, :bio) do ctx
        Dict(
            "type" => "string",
            "maxLength" => 500
        )
    end

    result = generate_schema(StringLengthRecord; ctx = ctx, simplify = false)
    schema = result.doc["\$defs"][ctx_key(StringLengthRecord)]

    @test schema["properties"]["username"]["minLength"] == 3
    @test schema["properties"]["username"]["maxLength"] == 20
    @test schema["properties"]["username"]["pattern"] == "^[a-zA-Z0-9_]+\$"
    @test schema["properties"]["bio"]["maxLength"] == 500
end

struct DateTimeRecord
    created_at::DateTime
    updated_at::DateTime
end

@testset "type override - DateTime custom format" begin
    ctx = SchemaContext()

    register_type_override!(ctx, DateTime) do ctx
        Dict(
            "type" => "string",
            "format" => "date-time",
            "description" => "ISO 8601 datetime"
        )
    end

    result = generate_schema(DateTimeRecord; ctx = ctx, simplify = false)
    datetime_def = result.doc["\$defs"][ctx_key(DateTime)]

    @test datetime_def["format"] == "date-time"
    @test datetime_def["description"] == "ISO 8601 datetime"
end

struct FloatRecord
    value1::Float64
    value2::Float64
end

@testset "type override - Float64 custom representation" begin
    ctx = SchemaContext()

    register_type_override!(ctx, Float64) do ctx
        Dict(
            "type" => "number",
            "description" => "Custom float representation"
        )
    end

    result = generate_schema(FloatRecord; ctx = ctx, simplify = false)
    float_def = result.doc["\$defs"][ctx_key(Float64)]

    @test float_def["type"] == "number"
    @test float_def["description"] == "Custom float representation"
end

struct StringRecord
    field1::String
    field2::String
end

@testset "type override - String custom constraints" begin
    ctx = SchemaContext()

    register_type_override!(ctx, String) do ctx
        Dict(
            "type" => "string",
            "minLength" => 1,
            "description" => "Non-empty string"
        )
    end

    result = generate_schema(StringRecord; ctx = ctx, simplify = false)
    string_def = result.doc["\$defs"][ctx_key(String)]

    @test string_def["minLength"] == 1
    @test string_def["description"] == "Non-empty string"
end

struct NestedOverride
    inner::ScoreRecord
    name::String
end

@testset "field override - nested struct with overrides" begin
    ctx = SchemaContext()

    register_field_override!(ctx, ScoreRecord, :score) do ctx
        Dict(
            "type" => "number",
            "minimum" => 0.0,
            "maximum" => 100.0
        )
    end

    register_field_override!(ctx, NestedOverride, :name) do ctx
        Dict(
            "type" => "string",
            "minLength" => 1
        )
    end

    result = generate_schema(NestedOverride; ctx = ctx, simplify = false)

    nested_schema = result.doc["\$defs"][ctx_key(NestedOverride)]
    @test nested_schema["properties"]["name"]["minLength"] == 1

    score_schema = result.doc["\$defs"][ctx_key(ScoreRecord)]
    @test score_schema["properties"]["score"]["minimum"] == 0.0
    @test score_schema["properties"]["score"]["maximum"] == 100.0
end

struct IntRangeRecord
    small::Int8
    medium::Int32
    large::Int64
end

@testset "type override - multiple integer types" begin
    ctx = SchemaContext()

    register_type_override!(ctx, Int8) do ctx
        Dict(
            "type" => "integer",
            "minimum" => -128,
            "maximum" => 127,
            "description" => "8-bit integer"
        )
    end

    register_type_override!(ctx, Int32) do ctx
        Dict(
            "type" => "integer",
            "description" => "32-bit integer"
        )
    end

    result = generate_schema(IntRangeRecord; ctx = ctx, simplify = false)

    int8_def = result.doc["\$defs"][ctx_key(Int8)]
    @test int8_def["description"] == "8-bit integer"

    int32_def = result.doc["\$defs"][ctx_key(Int32)]
    @test int32_def["description"] == "32-bit integer"
end

struct ArrayOverrideRecord
    items::Vector{Int}
end

@testset "field override - array constraints" begin
    ctx = SchemaContext()

    register_field_override!(ctx, ArrayOverrideRecord, :items) do ctx
        Dict(
            "type" => "array",
            "items" => Dict("type" => "integer"),
            "minItems" => 1,
            "maxItems" => 10
        )
    end

    result = generate_schema(ArrayOverrideRecord; ctx = ctx, simplify = false)
    schema = result.doc["\$defs"][ctx_key(ArrayOverrideRecord)]

    @test schema["properties"]["items"]["minItems"] == 1
    @test schema["properties"]["items"]["maxItems"] == 10
end

struct EnumOverrideRecord
    color::String
end

@testset "field override - enum values" begin
    ctx = SchemaContext()

    register_field_override!(ctx, EnumOverrideRecord, :color) do ctx
        Dict(
            "type" => "string",
            "enum" => ["red", "green", "blue"]
        )
    end

    result = generate_schema(EnumOverrideRecord; ctx = ctx, simplify = false)
    schema = result.doc["\$defs"][ctx_key(EnumOverrideRecord)]

    @test schema["properties"]["color"]["enum"] == ["red", "green", "blue"]
end

struct PatternRecord
    phone::String
    zipcode::String
end

@testset "override contexts - field override" begin
    struct UnifiedFieldTarget
        value::Int
        label::String
    end

    ctx = SchemaContext()

    register_override!(ctx) do ctx
        if current_parent(ctx) === UnifiedFieldTarget && current_field(ctx) === :value
            return Dict("type" => "integer", "minimum" => 0)
        end
        return nothing
    end

    result = generate_schema(UnifiedFieldTarget; ctx = ctx, simplify = false)
    schema = result.doc["\$defs"][ctx_key(UnifiedFieldTarget)]

    @test schema["properties"]["value"]["minimum"] == 0
    @test haskey(schema["properties"]["label"], "\$ref")
end

@testset "override contexts - type override" begin
    struct UnifiedTypeTarget
        data::String
    end

    ctx = SchemaContext()

    register_override!(ctx) do ctx
        if current_type(ctx) === UnifiedTypeTarget && current_field(ctx) === nothing
            return Dict("type" => "object", "description" => "custom type override")
        end
        return nothing
    end

    result = generate_schema(UnifiedTypeTarget; ctx = ctx, simplify = false)
    schema = result.doc["\$defs"][ctx_key(UnifiedTypeTarget)]

    @test schema["description"] == "custom type override"
    @test schema["type"] == "object"
end

@testset "override contexts - path aware" begin
    struct ServiceConfig
        endpoint::String
        retries::Int
    end

    struct ConfigWrapper
        config::ServiceConfig
        label::String
    end

    ctx = SchemaContext()

    register_override!(ctx) do ctx
        if current_type(ctx) === String && :config in ctx.path
            return Dict("type" => "string", "minLength" => 1)
        end
        return nothing
    end

    result = generate_schema(ConfigWrapper; ctx = ctx, simplify = false)
    defs = result.doc["\$defs"]

    config_schema = defs[ctx_key(ServiceConfig)]
    @test config_schema["properties"]["endpoint"]["minLength"] == 1

    wrapper_schema = defs[ctx_key(ConfigWrapper)]
    @test !haskey(wrapper_schema["properties"]["label"], "minLength")
end

@testset "override contexts - helper APIs" begin
    struct TypeOverrideHolder
        price::Float64
    end

    ctx = SchemaContext()

    register_type_override!(ctx, Float64) do ctx
        Dict("type" => "number", "minimum" => 0)
    end

    result = generate_schema(TypeOverrideHolder; ctx = ctx, simplify = false)
    float_def = result.doc["\$defs"][ctx_key(Float64)]

    @test float_def["minimum"] == 0
    @test float_def["type"] == "number"
end

@testset "override contexts - field helper" begin
    struct FieldOverrideHolder
        email::String
        name::String
    end

    ctx = SchemaContext()

    register_field_override!(ctx, FieldOverrideHolder, :email) do ctx
        Dict("type" => "string", "format" => "email")
    end

    result = generate_schema(FieldOverrideHolder; ctx = ctx, simplify = false)
    schema = result.doc["\$defs"][ctx_key(FieldOverrideHolder)]

    @test schema["properties"]["email"]["format"] == "email"
    @test haskey(schema["properties"]["name"], "\$ref")
end

@testset "override contexts - register_abstract!" begin
    abstract type UnifiedAnimal end

    struct UnifiedCat <: UnifiedAnimal
        kind::String
        name::String
    end

    struct UnifiedDog <: UnifiedAnimal
        kind::String
        name::String
    end

    ctx = SchemaContext()

    register_abstract!(
        ctx, UnifiedAnimal;
        variants = [UnifiedCat, UnifiedDog],
        discr_key = "kind",
        tag_value = Dict(UnifiedCat => "cat", UnifiedDog => "dog")
    )

    result = generate_schema(UnifiedAnimal; ctx = ctx, simplify = false)
    schema = result.doc["\$defs"][ctx_key(UnifiedAnimal)]

    @test haskey(schema, "anyOf")
    @test length(schema["anyOf"]) == 2
    for variant_schema in schema["anyOf"]
        @test haskey(variant_schema, "allOf")
        discr = only(filter(s -> haskey(s, "properties"), variant_schema["allOf"]))
        @test haskey(discr["properties"], "kind")
    end
end

@testset "override contexts - precedence and failures" begin
    struct PrecedenceHolder
        value::Int
    end

    ctx = SchemaContext()

    register_type_override!(ctx, Int) do _
        Dict("type" => "integer", "minimum" => 5)
    end

    register_field_override!(ctx, PrecedenceHolder, :value) do _
        Dict("type" => "integer", "minimum" => 0, "maximum" => 10)
    end

    result = generate_schema(PrecedenceHolder; ctx = ctx, simplify = false)
    defs = result.doc["\$defs"]
    holder_schema = defs[ctx_key(PrecedenceHolder)]
    @test holder_schema["properties"]["value"]["minimum"] == 0
    @test holder_schema["properties"]["value"]["maximum"] == 10

    int_result = generate_schema(Int; ctx = ctx, simplify = false)
    int_schema = int_result.doc["\$defs"][ctx_key(Int)]
    @test int_schema["minimum"] == 5

    struct BrokenOverride
        data::Int
    end

    verbose_ctx = SchemaContext(verbose = true)
    register_override!(verbose_ctx) do ctx
        if current_type(ctx) === BrokenOverride
            error("boom")
        end
        return nothing
    end

    @test_logs (:warn, r"Override threw an error at type BrokenOverride") begin
        result = generate_schema(BrokenOverride; ctx = verbose_ctx, simplify = false)
        schema = result.doc["\$defs"][ctx_key(BrokenOverride)]
        @test haskey(schema["properties"], "data")
    end
end

@testset "override contexts - ordering" begin
    struct OrderingTarget
        x::Int
    end

    ctx = SchemaContext()
    first_hit = Ref(false)
    register_override!(ctx) do ctx
        if current_type(ctx) === OrderingTarget
            first_hit[] = true
            return Dict(
                "type" => "object",
                "properties" => Dict("x" => Dict("type" => "integer")),
                "required" => ["x"],
                "additionalProperties" => false
            )
        end
        return nothing
    end

    second_hit = Ref(false)
    register_override!(ctx) do ctx
        if current_type(ctx) === OrderingTarget
            second_hit[] = true
            return Dict("type" => "object")
        end
        return nothing
    end

    result = generate_schema(OrderingTarget; ctx = ctx, simplify = false)
    schema = result.doc["\$defs"][ctx_key(OrderingTarget)]
    @test schema["required"] == ["x"]
    @test first_hit[]
    @test !second_hit[]
end

@testset "field override - regex patterns" begin
    ctx = SchemaContext()

    register_field_override!(ctx, PatternRecord, :phone) do ctx
        Dict(
            "type" => "string",
            "pattern" => "^\\+?[1-9]\\d{1,14}\$"
        )
    end

    register_field_override!(ctx, PatternRecord, :zipcode) do ctx
        Dict(
            "type" => "string",
            "pattern" => "^\\d{5}(-\\d{4})?\$"
        )
    end

    result = generate_schema(PatternRecord; ctx = ctx, simplify = false)
    schema = result.doc["\$defs"][ctx_key(PatternRecord)]

    @test schema["properties"]["phone"]["pattern"] == "^\\+?[1-9]\\d{1,14}\$"
    @test schema["properties"]["zipcode"]["pattern"] == "^\\d{5}(-\\d{4})?\$"
end
