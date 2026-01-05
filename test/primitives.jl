using Test
using Dates
using Struct2JSONSchema: SchemaContext, generate_schema, k, UnknownEntry

struct PrimitiveRecord
    id::Int64
    visits::UInt16
    score::Float32
    ratio::Float64
    flag::Bool
    note::String
    letter::Char
    label::Symbol
    day::Date
    timestamp::DateTime
    schedule::Time
    pattern::Regex
    fraction::Rational{Int}
    version::VersionNumber
end

struct NullAndAnyRecord
    maybe_id::Union{Int64, Nothing}
    maybe_text::Union{Missing, String}
    payload::Any
end

struct RawVectorWrapper
    values::Vector
end

const _KEY_CTX = SchemaContext()

schema_key(T) = k(T, _KEY_CTX)
ref_for(T) = "#/\$defs/$(schema_key(T))"

def_for(defs, T) = defs[schema_key(T)]

function resolve_reference(entry::AbstractDict{String, <:Any}, defs::AbstractDict{String, <:Any})
    if haskey(entry, "\$ref")
        key = split(entry["\$ref"], '/')[end]
        return defs[key]
    end
    return entry
end

@testset "Primitive schema generation" begin
    ctx = SchemaContext()
    result = generate_schema(PrimitiveRecord; ctx = ctx, simplify = false)
    doc = result.doc
    defs = doc["\$defs"]
    schema = def_for(defs, PrimitiveRecord)

    @test doc["\$schema"] == "https://json-schema.org/draft/2020-12/schema"
    @test doc["\$ref"] == ref_for(PrimitiveRecord)
    @test schema["type"] == "object"
    @test schema["additionalProperties"] == false

    props = schema["properties"]
    @test props["id"]["\$ref"] == ref_for(Int64)
    @test props["visits"]["\$ref"] == ref_for(UInt16)
    @test props["score"]["\$ref"] == ref_for(Float32)
    @test props["ratio"]["\$ref"] == ref_for(Float64)
    @test props["flag"]["\$ref"] == ref_for(Bool)
    @test props["note"]["\$ref"] == ref_for(String)
    @test props["letter"]["\$ref"] == ref_for(Char)
    @test props["label"]["\$ref"] == ref_for(Symbol)
    @test props["day"]["\$ref"] == ref_for(Date)
    @test props["timestamp"]["\$ref"] == ref_for(DateTime)
    @test props["schedule"]["\$ref"] == ref_for(Time)
    @test props["pattern"]["\$ref"] == ref_for(Regex)
    @test props["fraction"]["\$ref"] == ref_for(Rational{Int})
    @test props["version"]["\$ref"] == ref_for(VersionNumber)

    @test def_for(defs, Bool) == Dict("type" => "boolean")

    int_def = def_for(defs, Int64)
    @test int_def["type"] == "integer"
    @test int_def["minimum"] == typemin(Int64)
    @test int_def["maximum"] == typemax(Int64)

    uint_def = def_for(defs, UInt16)
    @test uint_def["minimum"] == typemin(UInt16)
    @test uint_def["maximum"] == typemax(UInt16)

    float32_def = def_for(defs, Float32)
    @test float32_def == Dict("type" => "number")

    float64_def = def_for(defs, Float64)
    @test float64_def == Dict("type" => "number")

    str_def = def_for(defs, String)
    @test str_def == Dict("type" => "string")

    char_def = def_for(defs, Char)
    @test char_def["type"] == "string"
    @test char_def["minLength"] == 1
    @test char_def["maxLength"] == 1

    sym_def = def_for(defs, Symbol)
    @test sym_def["type"] == "string"

    date_def = def_for(defs, Date)
    @test date_def["type"] == "string"
    @test date_def["format"] == "date"

    datetime_def = def_for(defs, DateTime)
    @test datetime_def["format"] == "date-time"

    time_def = def_for(defs, Time)
    @test time_def["format"] == "time"

    regex_def = def_for(defs, Regex)
    @test regex_def == Dict("type" => "string", "format" => "regex")

    version_def = def_for(defs, VersionNumber)
    @test version_def["type"] == "string"
    @test haskey(version_def, "pattern")

    rational_def = def_for(defs, Rational{Int})
    @test rational_def == Dict("type" => "number")
end

@testset "Null-likes and Any" begin
    ctx = SchemaContext()
    result = generate_schema(NullAndAnyRecord; ctx = ctx, simplify = false)
    defs = result.doc["\$defs"]
    schema = def_for(defs, NullAndAnyRecord)
    props = schema["properties"]

    maybe_id = resolve_reference(props["maybe_id"], defs)
    @test length(maybe_id["anyOf"]) == 2
    @test Set(row["\$ref"] for row in maybe_id["anyOf"]) == Set([ref_for(Int64), ref_for(Nothing)])

    maybe_text = resolve_reference(props["maybe_text"], defs)
    @test length(maybe_text["anyOf"]) == 2
    @test Set(row["\$ref"] for row in maybe_text["anyOf"]) == Set([ref_for(String), ref_for(Missing)])

    any_schema = props["payload"]
    @test any_schema["\$ref"] == ref_for(Any)
    @test isempty(def_for(defs, Any))

    nothing_def = def_for(defs, Nothing)
    @test nothing_def == Dict("type" => "null")

    missing_def = def_for(defs, Missing)
    @test missing_def == Dict("type" => "null")
end

@testset "UnionAll recording" begin
    ctx = SchemaContext()
    result = generate_schema(RawVectorWrapper; ctx = ctx, simplify = false)
    defs = result.doc["\$defs"]
    schema = def_for(defs, RawVectorWrapper)
    value_schema = schema["properties"]["values"]

    @test value_schema["\$ref"] == ref_for(Any)
    @test result.unknowns == Set([UnknownEntry(Vector, (:values,), "unionall_type")])
end

struct PrimitiveRecord2
    id::Int32
    visits::UInt32
    score::Float16
    counter::UInt8
    large_num::Int128
    flag::Bool
end

@testset "integer types" begin
    ctx = SchemaContext()
    result = generate_schema(PrimitiveRecord2; ctx = ctx, simplify = false)
    defs = result.doc["\$defs"]
    schema = def_for(defs, PrimitiveRecord2)
    props = schema["properties"]

    @test props["id"]["\$ref"] == ref_for(Int32)
    @test props["visits"]["\$ref"] == ref_for(UInt32)
    @test props["score"]["\$ref"] == ref_for(Float16)
    @test props["counter"]["\$ref"] == ref_for(UInt8)
    @test props["large_num"]["\$ref"] == ref_for(Int128)

    int32_def = def_for(defs, Int32)
    @test int32_def["type"] == "integer"
    @test int32_def["minimum"] == typemin(Int32)
    @test int32_def["maximum"] == typemax(Int32)

    uint32_def = def_for(defs, UInt32)
    @test uint32_def["minimum"] == typemin(UInt32)
    @test uint32_def["maximum"] == typemax(UInt32)

    uint8_def = def_for(defs, UInt8)
    @test uint8_def["minimum"] == typemin(UInt8)
    @test uint8_def["maximum"] == typemax(UInt8)

    float16_def = def_for(defs, Float16)
    @test float16_def == Dict("type" => "number")

    int128_def = def_for(defs, Int128)
    @test int128_def["type"] == "integer"
end

struct PrimitiveRecord3
    a::Int8
    b::Int16
    c::UInt64
    d::UInt128
end

@testset "More integer type variations" begin
    ctx = SchemaContext()
    result = generate_schema(PrimitiveRecord3; ctx = ctx, simplify = false)
    defs = result.doc["\$defs"]
    schema = def_for(defs, PrimitiveRecord3)
    props = schema["properties"]

    @test props["a"]["\$ref"] == ref_for(Int8)
    @test props["b"]["\$ref"] == ref_for(Int16)
    @test props["c"]["\$ref"] == ref_for(UInt64)
    @test props["d"]["\$ref"] == ref_for(UInt128)

    int8_def = def_for(defs, Int8)
    @test int8_def["type"] == "integer"
    @test int8_def["minimum"] == typemin(Int8)
    @test int8_def["maximum"] == typemax(Int8)

    int16_def = def_for(defs, Int16)
    @test int16_def["minimum"] == typemin(Int16)
    @test int16_def["maximum"] == typemax(Int16)

    uint64_def = def_for(defs, UInt64)
    @test uint64_def["minimum"] == typemin(UInt64)
    @test uint64_def["maximum"] == typemax(UInt64)

    uint128_def = def_for(defs, UInt128)
    @test uint128_def["type"] == "integer"
end

struct StringVariations
    text::String
    letter1::Char
    letter2::Char
    symbol1::Symbol
    symbol2::Symbol
end

@testset "String-like type variations" begin
    ctx = SchemaContext()
    result = generate_schema(StringVariations; ctx = ctx, simplify = false)
    defs = result.doc["\$defs"]
    schema = def_for(defs, StringVariations)
    props = schema["properties"]

    @test props["text"]["\$ref"] == ref_for(String)
    @test props["letter1"]["\$ref"] == ref_for(Char)
    @test props["letter2"]["\$ref"] == ref_for(Char)
    @test props["symbol1"]["\$ref"] == ref_for(Symbol)
    @test props["symbol2"]["\$ref"] == ref_for(Symbol)

    str_def = def_for(defs, String)
    @test str_def == Dict("type" => "string")

    char_def = def_for(defs, Char)
    @test char_def["type"] == "string"
    @test char_def["minLength"] == 1
    @test char_def["maxLength"] == 1

    sym_def = def_for(defs, Symbol)
    @test sym_def["type"] == "string"
end

struct DateTimeVariations
    date1::Date
    date2::Date
    datetime1::DateTime
    datetime2::DateTime
    time1::Time
    time2::Time
end

@testset "Date and time type variations" begin
    ctx = SchemaContext()
    result = generate_schema(DateTimeVariations; ctx = ctx, simplify = false)
    defs = result.doc["\$defs"]
    schema = def_for(defs, DateTimeVariations)
    props = schema["properties"]

    @test props["date1"]["\$ref"] == ref_for(Date)
    @test props["date2"]["\$ref"] == ref_for(Date)
    @test props["datetime1"]["\$ref"] == ref_for(DateTime)
    @test props["datetime2"]["\$ref"] == ref_for(DateTime)
    @test props["time1"]["\$ref"] == ref_for(Time)
    @test props["time2"]["\$ref"] == ref_for(Time)

    date_def = def_for(defs, Date)
    @test date_def["type"] == "string"
    @test date_def["format"] == "date"

    datetime_def = def_for(defs, DateTime)
    @test datetime_def["format"] == "date-time"

    time_def = def_for(defs, Time)
    @test time_def["format"] == "time"
end

struct BooleanVariations
    flag1::Bool
    flag2::Bool
    flag3::Bool
    enabled::Bool
    active::Bool
end

@testset "Boolean type variations" begin
    ctx = SchemaContext()
    result = generate_schema(BooleanVariations; ctx = ctx, simplify = false)
    defs = result.doc["\$defs"]
    schema = def_for(defs, BooleanVariations)
    props = schema["properties"]

    @test props["flag1"]["\$ref"] == ref_for(Bool)
    @test props["flag2"]["\$ref"] == ref_for(Bool)
    @test props["flag3"]["\$ref"] == ref_for(Bool)
    @test props["enabled"]["\$ref"] == ref_for(Bool)
    @test props["active"]["\$ref"] == ref_for(Bool)

    bool_def = def_for(defs, Bool)
    @test bool_def == Dict("type" => "boolean")
end

struct RationalAndRegexVariations
    ratio1::Rational{Int}
    ratio2::Rational{Int64}
    pattern1::Regex
    pattern2::Regex
end

@testset "Rational and Regex type variations" begin
    ctx = SchemaContext()
    result = generate_schema(RationalAndRegexVariations; ctx = ctx, simplify = false)
    defs = result.doc["\$defs"]
    schema = def_for(defs, RationalAndRegexVariations)
    props = schema["properties"]

    @test props["ratio1"]["\$ref"] == ref_for(Rational{Int})
    @test props["ratio2"]["\$ref"] == ref_for(Rational{Int64})
    @test props["pattern1"]["\$ref"] == ref_for(Regex)
    @test props["pattern2"]["\$ref"] == ref_for(Regex)

    rational_def = def_for(defs, Rational{Int})
    @test rational_def == Dict("type" => "number")

    rational64_def = def_for(defs, Rational{Int64})
    @test rational64_def == Dict("type" => "number")

    regex_def = def_for(defs, Regex)
    @test regex_def == Dict("type" => "string", "format" => "regex")
end

struct MixedNullableTypes
    maybe_int::Union{Int64, Nothing}
    maybe_float::Union{Float64, Nothing}
    maybe_string::Union{String, Nothing}
    maybe_bool::Union{Bool, Nothing}
end

@testset "More nullable type combinations" begin
    ctx = SchemaContext()
    result = generate_schema(MixedNullableTypes; ctx = ctx, simplify = false)
    defs = result.doc["\$defs"]
    schema = def_for(defs, MixedNullableTypes)
    props = schema["properties"]

    maybe_int = resolve_reference(props["maybe_int"], defs)
    @test length(maybe_int["anyOf"]) == 2
    @test Set(row["\$ref"] for row in maybe_int["anyOf"]) == Set([ref_for(Int64), ref_for(Nothing)])

    maybe_float = resolve_reference(props["maybe_float"], defs)
    @test length(maybe_float["anyOf"]) == 2
    @test Set(row["\$ref"] for row in maybe_float["anyOf"]) == Set([ref_for(Float64), ref_for(Nothing)])

    maybe_string = resolve_reference(props["maybe_string"], defs)
    @test length(maybe_string["anyOf"]) == 2
    @test Set(row["\$ref"] for row in maybe_string["anyOf"]) == Set([ref_for(String), ref_for(Nothing)])

    maybe_bool = resolve_reference(props["maybe_bool"], defs)
    @test length(maybe_bool["anyOf"]) == 2
    @test Set(row["\$ref"] for row in maybe_bool["anyOf"]) == Set([ref_for(Bool), ref_for(Nothing)])
end

struct MixedMissingTypes
    maybe_int::Union{Int64, Missing}
    maybe_float::Union{Float64, Missing}
    maybe_string::Union{String, Missing}
    maybe_char::Union{Char, Missing}
end

@testset "More Missing type combinations" begin
    ctx = SchemaContext()
    result = generate_schema(MixedMissingTypes; ctx = ctx, simplify = false)
    defs = result.doc["\$defs"]
    schema = def_for(defs, MixedMissingTypes)
    props = schema["properties"]

    maybe_int = resolve_reference(props["maybe_int"], defs)
    @test length(maybe_int["anyOf"]) == 2
    @test Set(row["\$ref"] for row in maybe_int["anyOf"]) == Set([ref_for(Int64), ref_for(Missing)])

    maybe_float = resolve_reference(props["maybe_float"], defs)
    @test length(maybe_float["anyOf"]) == 2
    @test Set(row["\$ref"] for row in maybe_float["anyOf"]) == Set([ref_for(Float64), ref_for(Missing)])

    maybe_string = resolve_reference(props["maybe_string"], defs)
    @test length(maybe_string["anyOf"]) == 2
    @test Set(row["\$ref"] for row in maybe_string["anyOf"]) == Set([ref_for(String), ref_for(Missing)])

    maybe_char = resolve_reference(props["maybe_char"], defs)
    @test length(maybe_char["anyOf"]) == 2
    @test Set(row["\$ref"] for row in maybe_char["anyOf"]) == Set([ref_for(Char), ref_for(Missing)])
end

struct AnyPayloadVariations
    payload1::Any
    payload2::Any
    data::Any
end

@testset "Multiple Any type fields" begin
    ctx = SchemaContext()
    result = generate_schema(AnyPayloadVariations; ctx = ctx, simplify = false)
    defs = result.doc["\$defs"]
    schema = def_for(defs, AnyPayloadVariations)
    props = schema["properties"]

    @test props["payload1"]["\$ref"] == ref_for(Any)
    @test props["payload2"]["\$ref"] == ref_for(Any)
    @test props["data"]["\$ref"] == ref_for(Any)
    @test isempty(def_for(defs, Any))
end

struct FloatVariations
    f32_1::Float32
    f32_2::Float32
    f64_1::Float64
    f64_2::Float64
    f16_1::Float16
end

@testset "More Float type variations" begin
    ctx = SchemaContext()
    result = generate_schema(FloatVariations; ctx = ctx, simplify = false)
    defs = result.doc["\$defs"]
    schema = def_for(defs, FloatVariations)
    props = schema["properties"]

    @test props["f32_1"]["\$ref"] == ref_for(Float32)
    @test props["f32_2"]["\$ref"] == ref_for(Float32)
    @test props["f64_1"]["\$ref"] == ref_for(Float64)
    @test props["f64_2"]["\$ref"] == ref_for(Float64)
    @test props["f16_1"]["\$ref"] == ref_for(Float16)

    float32_def = def_for(defs, Float32)
    @test float32_def == Dict("type" => "number")

    float64_def = def_for(defs, Float64)
    @test float64_def == Dict("type" => "number")

    float16_def = def_for(defs, Float16)
    @test float16_def == Dict("type" => "number")
end

struct UnsupportedTypeWrapper
    intrinsic_fn::Core.IntrinsicFunction
    ptr::Ptr{Nothing}
end

@testset "Unsupported primitive types generate unknowns" begin
    ctx = SchemaContext()
    result = generate_schema(UnsupportedTypeWrapper; ctx = ctx, simplify = false)
    defs = result.doc["\$defs"]
    schema = def_for(defs, UnsupportedTypeWrapper)
    
    # Both fields should reference empty schemas
    @test haskey(schema["properties"], "intrinsic_fn")
    @test haskey(schema["properties"], "ptr")
    
    # Check that unknowns were recorded
    @test length(result.unknowns) == 2
    @test any(e -> e.type == Core.IntrinsicFunction && e.reason == "type_not_representable", result.unknowns)
    @test any(e -> e.type == Ptr{Nothing} && e.reason == "type_not_representable", result.unknowns)
    
    # Schemas for unsupported types should be empty
    intrinsic_def = def_for(defs, Core.IntrinsicFunction)
    @test isempty(intrinsic_def)
    
    ptr_def = def_for(defs, Ptr{Nothing})
    @test isempty(ptr_def)
end
