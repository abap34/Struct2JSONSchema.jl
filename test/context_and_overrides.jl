using Test
using Struct2JSONSchema: SchemaContext, generate_schema, generate_schema!, register_abstract!, register_override!, k, define!
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
    safe_result = generate_schema(WithFunctionField; ctx=ctx)
    @test isempty(ctx.defs)
    @test isempty(ctx.unknowns)

    bang_ctx = SchemaContext()
    result = generate_schema!(WithFunctionField; ctx=bang_ctx)
    @test !isempty(bang_ctx.defs)
    @test result.unknowns == Set([(Function, (:handler,))])

    second = generate_schema!(WithFunctionField; ctx=bang_ctx)
    @test isempty(second.unknowns)
end

@testset "register_abstract! validation" begin
    ctx = SchemaContext()
    @test_throws ArgumentError register_abstract!(ctx, PlainType;
        variants = DataType[],
        discr_key = "kind",
        tag_value = Dict{DataType,Union{String,Int,Float64,Bool,Nothing}}(),
        require_discr = true)
end

@testset "Overrides customize definitions" begin
    ctx = SchemaContext()

    register_override!(ctx, DateTime) do ctx
        Dict(
            "type" => "string",
            "format" => "date-time",
            "description" => "custom date-time"
        )
    end

    register_override!(ctx, OverrideDemo) do ctx
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

    timestamp = generate_schema(TimestampRecord; ctx=ctx)
    defs = timestamp.doc["\$defs"]
    datetime_def = defs[ctx_key(DateTime)]
    @test datetime_def["description"] == "custom date-time"

    demo = generate_schema(OverrideDemo; ctx=ctx)
    demo_defs = demo.doc["\$defs"]
    schema = demo_defs[ctx_key(OverrideDemo)]
    @test schema["properties"]["amount"]["type"] == "number"
    @test schema["properties"]["amount"]["minimum"] == 0
end

@testset "Verbose mode logging" begin
    # verbose=false (default): no logs should be emitted at any level
    ctx = SchemaContext()
    @test_logs min_level=Logging.Debug begin
        generate_schema(VerboseVectorHolder; ctx=ctx)
    end

    # verbose=true: info logs should be emitted
    verbose_ctx = SchemaContext(verbose=true)
    @test_logs (:info, r"UnionAll type Vector encountered") min_level=Logging.Debug begin
        generate_schema(VerboseVectorHolder; ctx=verbose_ctx)
    end
end
