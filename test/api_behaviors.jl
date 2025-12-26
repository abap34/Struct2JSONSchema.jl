using Test
using Struct2JSONSchema: SchemaContext, generate_schema, generate_schema!, register_type_override!, k
import Struct2JSONSchema: clone_context

struct VerboseCheck
    items::Vector
end

struct SimpleRecord
    value::Int
end

struct OverrideTarget
    field::String
end

@testset "Schema API behaviors" begin
    ctx = SchemaContext()
    result1 = generate_schema!(VerboseCheck; ctx = ctx, simplify = false)
    @test result1.unknowns == Set([(Vector, (:items,))])

    result2 = generate_schema!(SimpleRecord; ctx = ctx, simplify = false)
    @test isempty(result2.unknowns)

    safe_ctx = SchemaContext()
    safe_result = generate_schema(SimpleRecord; ctx = safe_ctx, simplify = false)
    @test isempty(safe_ctx.defs)
    root_key = split(safe_result.doc["\$ref"], '/')[end]
    @test haskey(safe_result.doc["\$defs"], root_key)

    ctx_override = SchemaContext()
    register_type_override!(ctx_override, OverrideTarget) do ctx
        Dict(
            "type" => "object",
            "properties" => Dict("field" => Dict("type" => "string")),
            "required" => ["field"],
            "description" => "overridden schema"
        )
    end
    override_doc = generate_schema(OverrideTarget; ctx = ctx_override, simplify = false).doc
    override_def = override_doc["\$defs"][k(OverrideTarget, ctx_override)]
    @test override_def["description"] == "overridden schema"
    @test override_def["required"] == ["field"]

    verbose_ctx = SchemaContext(verbose = true)
    cloned = clone_context(verbose_ctx)
    @test cloned.options.verbose
end

struct TestRecord1
    id::Int
end

struct TestRecord2
    name::String
end

struct TestRecord3
    value::Float64
end

@testset "API behavior tests - multiple schemas" begin
    ctx = SchemaContext()

    result1 = generate_schema!(TestRecord1; ctx = ctx, simplify = false)
    @test !isempty(ctx.defs)

    result2 = generate_schema!(TestRecord2; ctx = ctx, simplify = false)
    @test length(ctx.defs) > 1

    result3 = generate_schema!(TestRecord3; ctx = ctx, simplify = false)
    @test length(ctx.defs) > 2
end

struct VectorHolder1
    data::Vector
end

struct VectorHolder2
    items::Vector
end

@testset "API behavior tests - unknown types" begin
    ctx = SchemaContext()

    result1 = generate_schema!(VectorHolder1; ctx = ctx, simplify = false)
    @test result1.unknowns == Set([(Vector, (:data,))])

    result2 = generate_schema!(VectorHolder2; ctx = ctx, simplify = false)
    @test result2.unknowns == Set([(Vector, (:items,))])
end

struct IsolatedRecord1
    field1::String
end

struct IsolatedRecord2
    field2::Int
end

@testset "API behavior tests - context isolation" begin
    ctx1 = SchemaContext()
    result1 = generate_schema(IsolatedRecord1; ctx = ctx1, simplify = false)
    @test isempty(ctx1.defs)

    ctx2 = SchemaContext()
    result2 = generate_schema(IsolatedRecord2; ctx = ctx2, simplify = false)
    @test isempty(ctx2.defs)
end

struct CustomOverride1
    data::String
end

struct CustomOverride2
    value::Int
end

@testset "API behavior tests - multiple overrides" begin
    ctx = SchemaContext()

    register_type_override!(ctx, CustomOverride1) do ctx
        Dict("type" => "object", "description" => "Custom 1")
    end

    register_type_override!(ctx, CustomOverride2) do ctx
        Dict("type" => "object", "description" => "Custom 2")
    end

    doc1 = generate_schema(CustomOverride1; ctx = ctx, simplify = false).doc
    def1 = doc1["\$defs"][k(CustomOverride1, ctx)]
    @test def1["description"] == "Custom 1"

    doc2 = generate_schema(CustomOverride2; ctx = ctx, simplify = false).doc
    def2 = doc2["\$defs"][k(CustomOverride2, ctx)]
    @test def2["description"] == "Custom 2"
end

struct CloneTestStruct
    field::String
end

@testset "API behavior tests - context cloning" begin
    original = SchemaContext(verbose = true)
    cloned = clone_context(original)

    @test cloned.options.verbose == original.options.verbose
    @test cloned !== original
end
