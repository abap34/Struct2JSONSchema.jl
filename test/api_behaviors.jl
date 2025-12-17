using Test
using Struct2JSONSchema: SchemaContext, generate_schema, generate_schema!, register_override!, k
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
    result1 = generate_schema!(VerboseCheck; ctx=ctx)
    @test result1.unknowns == Set([(Vector, (:items,))])

    result2 = generate_schema!(SimpleRecord; ctx=ctx)
    @test isempty(result2.unknowns)

    safe_ctx = SchemaContext()
    safe_result = generate_schema(SimpleRecord; ctx=safe_ctx)
    @test isempty(safe_ctx.defs)
    root_key = split(safe_result.doc["\$ref"], '/')[end]
    @test haskey(safe_result.doc["\$defs"], root_key)

    ctx_override = SchemaContext()
    register_override!(ctx_override, OverrideTarget) do ctx
        Dict(
            "type" => "object",
            "properties" => Dict("field" => Dict("type" => "string")),
            "required" => ["field"],
            "description" => "overridden schema"
        )
    end
    override_doc = generate_schema(OverrideTarget; ctx=ctx_override).doc
    override_def = override_doc["\$defs"][k(OverrideTarget, ctx_override)]
    @test override_def["description"] == "overridden schema"
    @test override_def["required"] == ["field"]

    verbose_ctx = SchemaContext(verbose=true)
    cloned = clone_context(verbose_ctx)
    @test cloned.verbose
end
