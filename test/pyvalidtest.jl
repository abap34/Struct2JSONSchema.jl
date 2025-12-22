using Test
using Struct2JSONSchema: SchemaContext, generate_schema, register_field_override!, register_optional_fields!, treat_union_nothing_as_optional!, Struct2JSONSchema.simplify_schema
using JSON3
using Dates

function validate_py(schema_path::String, data_path::String)
    base_cmd = `python3 $(joinpath(@__DIR__, "helpers", "validator.py")) $schema_path $data_path`
    output = IOBuffer()
    cmd = pipeline(base_cmd; stdout = output, stderr = output)
    success = true
    try
        run(cmd)
    catch e
        if e isa ProcessFailedException
            success = false
        else
            rethrow(e)
        end
    end
    return success, String(take!(output))
end

format_reason(output::AbstractString) = isempty(output) ? "Python validator produced no output" : output

function run_validation_tests(test_name::String, struct_type::Type, schema_generator)
    data_dir = joinpath(@__DIR__, "data", test_name)
    valids_path = joinpath(data_dir, "valids.json")
    invalids_path = joinpath(data_dir, "invalids.json")

    if !isfile(valids_path) || !isfile(invalids_path)
        @warn "Test data not found for $test_name"
        return
    end

    return mktempdir() do tmp
        schema_path = joinpath(tmp, "schema.json")
        data_path = joinpath(tmp, "data.json")

        schema = schema_generator()
        schema_variants = [
            ("original", schema.doc),
            ("simplified", simplify_schema(schema.doc))
        ]

        valids = JSON3.read(read(valids_path, String))
        invalids = JSON3.read(read(invalids_path, String))

        for (variant_name, schema_doc) in schema_variants
            @testset "$test_name - schema=$variant_name" begin
                open(schema_path, "w") do io
                    JSON3.write(io, schema_doc)
                end

                for (idx, valid_data) in enumerate(valids)
                    open(data_path, "w") do io
                        JSON3.write(io, valid_data)
                    end
                    success, log_output = validate_py(schema_path, data_path)
                    if !success
                        @error "Python validation failed for valid data" test_name = test_name variant = variant_name index = idx data = valid_data reason = format_reason(log_output)
                    end
                    @test success
                end

                for (idx, invalid_data) in enumerate(invalids)
                    open(data_path, "w") do io
                        JSON3.write(io, invalid_data)
                    end
                    success, log_output = validate_py(schema_path, data_path)
                    if success
                        @error "Python validation unexpectedly accepted invalid data" test_name = test_name variant = variant_name index = idx data = invalid_data reason = format_reason(log_output)
                    end
                    @test !success
                end
            end
        end
    end
end

@testset "Python validator smoke test" begin
    mktempdir() do tmp
        schema_path = joinpath(tmp, "schema.json")
        data_path = joinpath(tmp, "data.json")

        schema_doc = Dict(
            "\$schema" => "https://json-schema.org/draft/2020-12/schema",
            "type" => "object",
            "properties" => Dict("name" => Dict("type" => "string")),
            "required" => ["name"],
            "additionalProperties" => false
        )
        open(schema_path, "w") do io
            JSON3.write(io, schema_doc)
        end

        open(data_path, "w") do io
            JSON3.write(io, Dict("name" => "Alice"))
        end
        success_valid, log_valid = validate_py(schema_path, data_path)
        if !success_valid
            @error "Python validator rejected valid smoke-test payload" reason = format_reason(log_valid)
        end
        @test success_valid

        open(data_path, "w") do io
            JSON3.write(io, Dict("name" => 123))
        end
        success_invalid, log_invalid = validate_py(schema_path, data_path)
        if success_invalid
            @error "Python validator accepted invalid smoke-test payload" reason = format_reason(log_invalid)
        end
        @test !success_invalid
    end
end

struct BasicPerson
    name::String
    age::Int
end

struct PersonWithOptionalEmail
    name::String
    age::Int
    email::Union{String, Nothing}
end

struct Address
    street::String
    city::String
    zipcode::String
end

struct PersonWithAddress
    name::String
    address::Address
end

struct TodoList
    title::String
    items::Vector{String}
end

@enum RequestStatus pending approved rejected

struct Request
    id::Int
    status::RequestStatus
end

struct Event
    id::Int
    timestamp::DateTime
    message::String
end

struct Product
    id::Int
    price::Float64
    quantity::Int32
end

struct FlexibleValue
    id::Int
    value::Union{String, Int}
end

struct SupportTicket
    id::Int
    summary::String
    assignee::String
    internal_notes::String
    followup::Union{String, Nothing}
end
@testset "Python validator - basic_person" begin
    run_validation_tests("basic_person", BasicPerson, () -> generate_schema(BasicPerson; simplify = false))
end

@testset "Python validator - optional_email" begin
    run_validation_tests(
        "optional_email", PersonWithOptionalEmail, () -> begin
            ctx = SchemaContext()
            treat_union_nothing_as_optional!(ctx)
            generate_schema(PersonWithOptionalEmail; ctx = ctx, simplify = false)
        end
    )
end

@testset "Python validator - nested_address" begin
    run_validation_tests("nested_address", PersonWithAddress, () -> generate_schema(PersonWithAddress; simplify = false))
end

@testset "Python validator - array_items" begin
    run_validation_tests("array_items", TodoList, () -> generate_schema(TodoList; simplify = false))
end

@testset "Python validator - enum_status" begin
    run_validation_tests("enum_status", Request, () -> generate_schema(Request; simplify = false))
end

@testset "Python validator - field_override_datetime" begin
    run_validation_tests(
        "field_override_datetime", Event, () -> begin
            ctx = SchemaContext()
            register_field_override!(ctx, Event, :timestamp) do ctx
                Dict(
                    "type" => "string",
                    "format" => "date-time"
                )
            end
            generate_schema(Event; ctx = ctx, simplify = false)
        end
    )
end

@testset "Python validator - numeric_constraints" begin
    run_validation_tests("numeric_constraints", Product, () -> generate_schema(Product; simplify = false))
end

@testset "Python validator - optional_registry" begin
    run_validation_tests(
        "optional_registry",
        SupportTicket,
        () -> begin
            ctx = SchemaContext()
            register_optional_fields!(ctx, SupportTicket, :internal_notes)
            treat_union_nothing_as_optional!(ctx)
            generate_schema(SupportTicket; ctx = ctx, simplify = false)
        end
    )
end

@testset "Python validator - union_types" begin
    run_validation_tests("union_types", FlexibleValue, () -> generate_schema(FlexibleValue; simplify = false))
end

struct Coordinates
    point::NTuple{3, Float64}
end

@testset "Python validator - ntuple_fixed_length" begin
    run_validation_tests("ntuple_fixed_length", Coordinates, () -> generate_schema(Coordinates; simplify = false))
end

struct TaggedPost
    tags::Set{String}
    title::String
end

@testset "Python validator - set_unique_items" begin
    run_validation_tests("set_unique_items", TaggedPost, () -> generate_schema(TaggedPost; simplify = false))
end

struct Company
    name::String
    employees::Vector{BasicPerson}
end

@testset "Python validator - nested_array_objects" begin
    run_validation_tests("nested_array_objects", Company, () -> generate_schema(Company; simplify = false))
end

struct DeepNested
    level1::Address
    level2::PersonWithAddress
end

@testset "Python validator - deep_nesting" begin
    run_validation_tests("deep_nesting", DeepNested, () -> generate_schema(DeepNested; simplify = false))
end

struct MultiUnion
    value::Union{String, Int, Float64, Bool}
end

@testset "Python validator - complex_union" begin
    run_validation_tests("complex_union", MultiUnion, () -> generate_schema(MultiUnion; simplify = false))
end

struct RangeConstraint
    id::Int
    score::Int32
end

@testset "Python validator - range_validation" begin
    run_validation_tests(
        "range_validation", RangeConstraint, () -> begin
            ctx = SchemaContext()
            register_field_override!(ctx, RangeConstraint, :score) do ctx
                Dict(
                    "type" => "integer",
                    "minimum" => 0,
                    "maximum" => 100
                )
            end
            generate_schema(RangeConstraint; ctx = ctx, simplify = false)
        end
    )
end

struct EmailRecord
    id::Int
    email::String
end

@testset "Python validator - email_format" begin
    run_validation_tests(
        "email_format", EmailRecord, () -> begin
            ctx = SchemaContext()
            register_field_override!(ctx, EmailRecord, :email) do ctx
                Dict(
                    "type" => "string",
                    "format" => "email"
                )
            end
            generate_schema(EmailRecord; ctx = ctx, simplify = false)
        end
    )
end

struct URLRecord
    id::Int
    website::String
end

@testset "Python validator - url_format" begin
    run_validation_tests(
        "url_format", URLRecord, () -> begin
            ctx = SchemaContext()
            register_field_override!(ctx, URLRecord, :website) do ctx
                Dict(
                    "type" => "string",
                    "format" => "uri"
                )
            end
            generate_schema(URLRecord; ctx = ctx, simplify = false)
        end
    )
end

struct NamedTupleRecord
    point::NamedTuple{(:x, :y), Tuple{Float64, Float64}}
end

@testset "Python validator - named_tuple" begin
    run_validation_tests("named_tuple", NamedTupleRecord, () -> generate_schema(NamedTupleRecord; simplify = false))
end

struct DictRecord
    metadata::Dict{String, String}
end

@testset "Python validator - dict_properties" begin
    run_validation_tests("dict_properties", DictRecord, () -> generate_schema(DictRecord; simplify = false))
end

struct BooleanRecord
    id::Int
    active::Bool
    verified::Bool
end

@testset "Python validator - boolean_fields" begin
    run_validation_tests("boolean_fields", BooleanRecord, () -> generate_schema(BooleanRecord; simplify = false))
end

struct MixedTypes
    id::Int
    name::String
    score::Float64
    active::Bool
    tags::Vector{String}
end

@testset "Python validator - mixed_types" begin
    run_validation_tests("mixed_types", MixedTypes, () -> generate_schema(MixedTypes; simplify = false))
end
