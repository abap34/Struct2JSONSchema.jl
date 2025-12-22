using Test
using Struct2JSONSchema: SchemaContext, generate_schema, k

const _EDGE_CASES_KEY_CTX = SchemaContext()
edge_case_key(T) = k(T, _EDGE_CASES_KEY_CTX)

@testset "Edge cases" begin
    @testset "Union{}" begin
        ctx = SchemaContext()
        result = generate_schema(Union{}; ctx = ctx, simplify = false)
        defs = result.doc["\$defs"]
        schema = defs[edge_case_key(Union{})]

        @test haskey(schema, "not")
        @test isempty(schema["not"])
        # Union{} is treated as a primitive, so no unknowns
        @test isempty(result.unknowns)
    end

    @testset "Empty struct" begin
        struct EmptyStruct end

        ctx = SchemaContext()
        result = generate_schema(EmptyStruct; ctx = ctx, simplify = false)
        defs = result.doc["\$defs"]
        schema = defs[edge_case_key(EmptyStruct)]

        @test schema["type"] == "object"
        @test isempty(schema["properties"])
        @test isempty(schema["required"])
        @test schema["additionalProperties"] == false
    end

    @testset "UnionAll types (Vector)" begin
        ctx = SchemaContext()
        result = generate_schema(Vector; ctx = ctx, simplify = false)
        defs = result.doc["\$defs"]

        # Vector is normalized to Any
        any_schema = defs[edge_case_key(Any)]
        @test isempty(any_schema)

        # Vector is recorded as unknown
        @test any(u -> u[1] === Vector, result.unknowns)
    end

    @testset "Zero-sized Tuple" begin
        ctx = SchemaContext()
        result = generate_schema(Tuple{}; ctx = ctx, simplify = false)
        defs = result.doc["\$defs"]
        schema = defs[edge_case_key(Tuple{})]

        @test schema["type"] == "array"
        @test schema["maxItems"] == 0
        @test !haskey(schema, "minItems")
        @test !haskey(schema, "prefixItems")
    end
end
