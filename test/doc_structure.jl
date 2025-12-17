using Test
using Struct2JSONSchema: SchemaContext, generate_schema, generate_schema!, k

struct DocStructInner
    code::Int
end

struct DocStructSample
    name::String
    inner::DocStructInner
end

function def_key_from_ref(ref::AbstractString)
    parts = split(ref, '/')
    return parts[end]
end

@testset "Document structure" begin
    ctx = SchemaContext()
    result = generate_schema(DocStructSample; ctx=ctx)
    doc = result.doc

    @test doc["\$schema"] == "https://json-schema.org/draft/2020-12/schema"
    @test haskey(doc, "\$ref")
    @test haskey(doc, "\$defs")

    defs = doc["\$defs"]
    root_key = def_key_from_ref(doc["\$ref"])
    @test haskey(defs, root_key)

    root_schema = defs[root_key]
    @test root_schema["type"] == "object"
    @test root_schema["additionalProperties"] == false

    for value in values(root_schema["properties"])
        @test haskey(value, "\$ref")
        referenced_key = def_key_from_ref(value["\$ref"])
        @test haskey(defs, referenced_key)
    end
end

@testset "generate_schema! produces independent defs copy" begin
    ctx = SchemaContext()
    result = generate_schema!(DocStructSample; ctx=ctx)
    doc_defs = result.doc["\$defs"]
    root_key = k(DocStructSample, ctx)

    doc_defs[root_key]["type"] = "array"
    @test ctx.defs[root_key]["type"] == "object"
end
