using Test
using Struct2JSONSchema: SchemaContext, generate_schema, register_field_override!, treat_union_nothing_as_optional!
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
        open(schema_path, "w") do io
            JSON3.write(io, schema.doc)
        end

        valids = JSON3.read(read(valids_path, String))
        for (idx, valid_data) in enumerate(valids)
            open(data_path, "w") do io
                JSON3.write(io, valid_data)
            end
            success, log_output = validate_py(schema_path, data_path)
            if !success
                @error "Python validation failed for valid data" test_name = test_name index = idx data = valid_data reason = format_reason(log_output)
            end
            @test success
        end

        invalids = JSON3.read(read(invalids_path, String))
        for (idx, invalid_data) in enumerate(invalids)
            open(data_path, "w") do io
                JSON3.write(io, invalid_data)
            end
            success, log_output = validate_py(schema_path, data_path)
            if success
                @error "Python validation unexpectedly accepted invalid data" test_name = test_name index = idx data = invalid_data reason = format_reason(log_output)
            end
            @test !success
        end
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

@enum Status pending approved rejected

struct Request
    id::Int
    status::Status
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

@testset "Python validator - basic_person" begin
    run_validation_tests("basic_person", BasicPerson, () -> generate_schema(BasicPerson))
end

@testset "Python validator - optional_email" begin
    run_validation_tests(
        "optional_email", PersonWithOptionalEmail, () -> begin
            ctx = SchemaContext()
            treat_union_nothing_as_optional!(ctx)
            generate_schema(PersonWithOptionalEmail; ctx = ctx)
        end
    )
end

@testset "Python validator - nested_address" begin
    run_validation_tests("nested_address", PersonWithAddress, () -> generate_schema(PersonWithAddress))
end

@testset "Python validator - array_items" begin
    run_validation_tests("array_items", TodoList, () -> generate_schema(TodoList))
end

@testset "Python validator - enum_status" begin
    run_validation_tests("enum_status", Request, () -> generate_schema(Request))
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
            generate_schema(Event; ctx = ctx)
        end
    )
end

@testset "Python validator - numeric_constraints" begin
    run_validation_tests("numeric_constraints", Product, () -> generate_schema(Product))
end

@testset "Python validator - union_types" begin
    run_validation_tests("union_types", FlexibleValue, () -> generate_schema(FlexibleValue))
end
