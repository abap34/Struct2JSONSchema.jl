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
    result = generate_schema(DocStructSample; ctx = ctx)
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
    result = generate_schema!(DocStructSample; ctx = ctx)
    doc_defs = result.doc["\$defs"]
    root_key = k(DocStructSample, ctx)

    doc_defs[root_key]["type"] = "array"
    @test ctx.defs[root_key]["type"] == "object"
end

struct DocTest1
    id::Int
    name::String
end

struct DocTest2
    inner::DocTest1
    value::Float64
end

@testset "document structure tests - nested types" begin
    ctx = SchemaContext()
    result = generate_schema(DocTest2; ctx = ctx)
    doc = result.doc

    @test doc["\$schema"] == "https://json-schema.org/draft/2020-12/schema"
    @test haskey(doc, "\$ref")
    @test haskey(doc, "\$defs")

    defs = doc["\$defs"]
    root_key = def_key_from_ref(doc["\$ref"])
    @test haskey(defs, root_key)
end

struct SimpleDoc1
    value::String
end

struct SimpleDoc2
    count::Int
end

struct SimpleDoc3
    flag::Bool
end

@testset "document structure tests - multiple simple types" begin
    for T in [SimpleDoc1, SimpleDoc2, SimpleDoc3]
        ctx = SchemaContext()
        result = generate_schema(T; ctx = ctx)
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
    end
end

struct DeepNest1
    value::Int
end

struct DeepNest2
    inner::DeepNest1
end

struct DeepNest3
    inner::DeepNest2
end

@testset "document structure tests - deeply nested" begin
    ctx = SchemaContext()
    result = generate_schema(DeepNest3; ctx = ctx)
    doc = result.doc
    defs = doc["\$defs"]

    @test haskey(defs, def_key_from_ref(doc["\$ref"]))

    for T in [DeepNest1, DeepNest2, DeepNest3]
        key = k(T, ctx)
        @test haskey(defs, key)
    end
end

struct BangTest1
    field::String
end

struct BangTest2
    data::Int
end

@testset "document structure tests - bang version independence" begin
    ctx = SchemaContext()

    result1 = generate_schema!(BangTest1; ctx = ctx)
    doc_defs1 = result1.doc["\$defs"]
    root_key1 = k(BangTest1, ctx)

    doc_defs1[root_key1]["type"] = "modified"
    @test ctx.defs[root_key1]["type"] == "object"

    result2 = generate_schema!(BangTest2; ctx = ctx)
    doc_defs2 = result2.doc["\$defs"]
    root_key2 = k(BangTest2, ctx)

    doc_defs2[root_key2]["type"] = "modified"
    @test ctx.defs[root_key2]["type"] == "object"
end
