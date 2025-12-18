using Test
using Dates
using Struct2JSONSchema: SchemaContext, generate_schema, k

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
    result = generate_schema(PrimitiveRecord; ctx = ctx)
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

    rational_def = def_for(defs, Rational{Int})
    @test rational_def == Dict("type" => "number")
end

@testset "Null-likes and Any" begin
    ctx = SchemaContext()
    result = generate_schema(NullAndAnyRecord; ctx = ctx)
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
    result = generate_schema(RawVectorWrapper; ctx = ctx)
    defs = result.doc["\$defs"]
    schema = def_for(defs, RawVectorWrapper)
    value_schema = schema["properties"]["values"]

    @test value_schema["\$ref"] == ref_for(Any)
    @test result.unknowns == Set([(Vector, (:values,))])
end
