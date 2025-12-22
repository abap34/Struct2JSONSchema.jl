using Test
using Struct2JSONSchema: SchemaContext, generate_schema
using Struct2JSONSchema: Struct2JSONSchema.simplify_schema, Struct2JSONSchema.remove_unused_defs, Struct2JSONSchema.simplify_single_element_combinators,
    Struct2JSONSchema.remove_empty_required, Struct2JSONSchema.inline_single_use_refs, Struct2JSONSchema.sort_defs


@testset "remove_unused_defs - basic" begin
    doc = Dict(
        "\$schema" => "https://json-schema.org/draft/2020-12/schema",
        "\$ref" => "#/\$defs/Used",
        "\$defs" => Dict(
            "Used" => Dict("type" => "string"),
            "Unused" => Dict("type" => "integer")
        )
    )

    result = remove_unused_defs(doc)
    @test haskey(result, "\$defs")
    @test haskey(result["\$defs"], "Used")
    @test !haskey(result["\$defs"], "Unused")
end

@testset "remove_unused_defs - chain reference" begin
    doc = Dict(
        "\$ref" => "#/\$defs/A",
        "\$defs" => Dict(
            "A" => Dict(
                "type" => "object",
                "properties" => Dict("b" => Dict("\$ref" => "#/\$defs/B"))
            ),
            "B" => Dict(
                "type" => "object",
                "properties" => Dict("c" => Dict("\$ref" => "#/\$defs/C"))
            ),
            "C" => Dict("type" => "string"),
            "D" => Dict("type" => "integer")
        )
    )

    result = remove_unused_defs(doc)
    @test haskey(result["\$defs"], "A")
    @test haskey(result["\$defs"], "B")
    @test haskey(result["\$defs"], "C")
    @test !haskey(result["\$defs"], "D")
end

@testset "remove_unused_defs - circular reference" begin
    doc = Dict(
        "\$ref" => "#/\$defs/A",
        "\$defs" => Dict(
            "A" => Dict(
                "type" => "object",
                "properties" => Dict("b" => Dict("\$ref" => "#/\$defs/B"))
            ),
            "B" => Dict(
                "type" => "object",
                "properties" => Dict("a" => Dict("\$ref" => "#/\$defs/A"))
            ),
            "C" => Dict("type" => "string")
        )
    )

    result = remove_unused_defs(doc)
    @test haskey(result["\$defs"], "A")
    @test haskey(result["\$defs"], "B")
    @test !haskey(result["\$defs"], "C")
end

@testset "remove_unused_defs - all unused" begin
    doc = Dict(
        "\$defs" => Dict(
            "A" => Dict("type" => "string"),
            "B" => Dict("type" => "integer")
        )
    )

    result = remove_unused_defs(doc)
    @test !haskey(result, "\$defs")
end

@testset "simplify_single_element_combinators - anyOf" begin
    schema = Dict(
        "anyOf" => [Dict("type" => "string")]
    )

    result = simplify_single_element_combinators(schema)
    @test result == Dict("type" => "string")
end

@testset "simplify_single_element_combinators - allOf" begin
    schema = Dict(
        "allOf" => [Dict("type" => "integer")]
    )

    result = simplify_single_element_combinators(schema)
    @test result == Dict("type" => "integer")
end

@testset "simplify_single_element_combinators - with other keys" begin
    schema = Dict(
        "anyOf" => [Dict("type" => "string")],
        "title" => "My String"
    )

    result = simplify_single_element_combinators(schema)
    @test result == schema
end

@testset "simplify_single_element_combinators - nested" begin
    schema = Dict(
        "properties" => Dict(
            "field1" => Dict("anyOf" => [Dict("type" => "string")]),
            "field2" => Dict("allOf" => [Dict("type" => "integer")])
        )
    )

    result = simplify_single_element_combinators(schema)
    @test result["properties"]["field1"] == Dict("type" => "string")
    @test result["properties"]["field2"] == Dict("type" => "integer")
end

@testset "simplify_single_element_combinators - multiple elements" begin
    schema = Dict(
        "anyOf" => [
            Dict("type" => "string"),
            Dict("type" => "integer"),
        ]
    )

    result = simplify_single_element_combinators(schema)
    @test result == schema
end

@testset "remove_empty_required - basic" begin
    schema = Dict(
        "type" => "object",
        "properties" => Dict("a" => Dict("type" => "string")),
        "required" => String[],
        "additionalProperties" => false
    )

    result = remove_empty_required(schema)
    @test !haskey(result, "required")
    @test haskey(result, "type")
    @test haskey(result, "properties")
end

@testset "remove_empty_required - non-empty" begin
    schema = Dict(
        "type" => "object",
        "properties" => Dict("a" => Dict("type" => "string")),
        "required" => ["a"]
    )

    result = remove_empty_required(schema)
    @test haskey(result, "required")
    @test result["required"] == ["a"]
end

@testset "remove_empty_required - nested" begin
    schema = Dict(
        "type" => "object",
        "properties" => Dict(
            "inner" => Dict(
                "type" => "object",
                "properties" => Dict("b" => Dict("type" => "integer")),
                "required" => []
            )
        ),
        "required" => ["inner"]
    )

    result = remove_empty_required(schema)
    @test !haskey(result["properties"]["inner"], "required")
    @test haskey(result, "required")
end

@testset "inline_single_use_refs - basic" begin
    doc = Dict(
        "\$ref" => "#/\$defs/Person",
        "\$defs" => Dict(
            "Person" => Dict(
                "type" => "object",
                "properties" => Dict(
                    "email" => Dict("\$ref" => "#/\$defs/Email")
                )
            ),
            "Email" => Dict(
                "type" => "string",
                "format" => "email"
            )
        )
    )

    result = inline_single_use_refs(doc)

    @test !haskey(result["\$defs"], "Email")
    @test result["\$defs"]["Person"]["properties"]["email"] == Dict(
        "type" => "string",
        "format" => "email"
    )
end

@testset "inline_single_use_refs - multiple uses" begin
    doc = Dict(
        "\$ref" => "#/\$defs/Person",
        "\$defs" => Dict(
            "Person" => Dict(
                "type" => "object",
                "properties" => Dict(
                    "name" => Dict("\$ref" => "#/\$defs/String"),
                    "email" => Dict("\$ref" => "#/\$defs/String")
                )
            ),
            "String" => Dict("type" => "string")
        )
    )

    result = inline_single_use_refs(doc)

    @test haskey(result["\$defs"], "String")
    @test result["\$defs"]["Person"]["properties"]["name"] == Dict("\$ref" => "#/\$defs/String")
end

@testset "inline_single_use_refs - simple primitive not inlined" begin
    doc = Dict(
        "\$ref" => "#/\$defs/Person",
        "\$defs" => Dict(
            "Person" => Dict(
                "type" => "object",
                "properties" => Dict(
                    "name" => Dict("\$ref" => "#/\$defs/String")
                )
            ),
            "String" => Dict("type" => "string")
        )
    )

    result = inline_single_use_refs(doc)

    @test haskey(result["\$defs"], "String")
end

@testset "inline_single_use_refs - constrained primitive inlined" begin
    doc = Dict(
        "\$ref" => "#/\$defs/Person",
        "\$defs" => Dict(
            "Person" => Dict(
                "type" => "object",
                "properties" => Dict(
                    "age" => Dict("\$ref" => "#/\$defs/PositiveInt")
                )
            ),
            "PositiveInt" => Dict(
                "type" => "integer",
                "minimum" => 0
            )
        )
    )

    result = inline_single_use_refs(doc)

    @test !haskey(result["\$defs"], "PositiveInt")
    @test result["\$defs"]["Person"]["properties"]["age"] == Dict(
        "type" => "integer",
        "minimum" => 0
    )
end

@testset "inline_single_use_refs - recursive not inlined" begin
    doc = Dict(
        "\$ref" => "#/\$defs/Node",
        "\$defs" => Dict(
            "Node" => Dict(
                "type" => "object",
                "properties" => Dict(
                    "value" => Dict("type" => "integer"),
                    "next" => Dict("\$ref" => "#/\$defs/Node")
                )
            )
        )
    )

    result = inline_single_use_refs(doc)

    @test haskey(result["\$defs"], "Node")
end

@testset "sort_defs - primitives first" begin
    doc = Dict(
        "\$defs" => Dict(
            "Person" => Dict(
                "type" => "object",
                "properties" => Dict("name" => Dict("\$ref" => "#/\$defs/String"))
            ),
            "String" => Dict("type" => "string"),
            "Int64" => Dict("type" => "integer")
        )
    )

    result = sort_defs(doc)
    keys_list = collect(keys(result["\$defs"]))

    primitive_idx = findfirst(k -> k in ["String", "Int64"], keys_list)
    person_idx = findfirst(k -> k == "Person", keys_list)
    @test primitive_idx < person_idx
end

@testset "sort_defs - dependency order" begin
    doc = Dict(
        "\$defs" => Dict(
            "C" => Dict(
                "type" => "object",
                "properties" => Dict(
                    "a" => Dict("\$ref" => "#/\$defs/A"),
                    "b" => Dict("\$ref" => "#/\$defs/B")
                )
            ),
            "B" => Dict(
                "type" => "object",
                "properties" => Dict("a" => Dict("\$ref" => "#/\$defs/A"))
            ),
            "A" => Dict("type" => "string")
        )
    )

    result = sort_defs(doc)
    keys_list = collect(keys(result["\$defs"]))

    a_idx = findfirst(k -> k == "A", keys_list)
    b_idx = findfirst(k -> k == "B", keys_list)
    c_idx = findfirst(k -> k == "C", keys_list)

    @test a_idx < b_idx
    @test b_idx < c_idx
end

@testset "sort_defs - lexicographic within same level" begin
    doc = Dict(
        "\$defs" => Dict(
            "String" => Dict("type" => "string"),
            "Bool" => Dict("type" => "boolean"),
            "Int64" => Dict("type" => "integer")
        )
    )

    result = sort_defs(doc)
    keys_list = collect(keys(result["\$defs"]))

    @test keys_list == sort(keys_list)
end

@testset "simplify_schema - integration" begin
    doc = Dict(
        "\$ref" => "#/\$defs/Person",
        "\$defs" => Dict(
            "Person" => Dict(
                "type" => "object",
                "properties" => Dict(
                    "name" => Dict("anyOf" => [Dict("\$ref" => "#/\$defs/String")]),
                    "email" => Dict("\$ref" => "#/\$defs/Email")
                ),
                "required" => ["name"]
            ),
            "String" => Dict("type" => "string"),
            "Email" => Dict("type" => "string", "format" => "email"),
            "Unused" => Dict("type" => "integer")
        )
    )

    result = simplify_schema(doc)

    @test result["\$defs"]["Person"]["properties"]["name"] == Dict("\$ref" => "#/\$defs/String")

    @test !haskey(result["\$defs"], "Email")
    @test result["\$defs"]["Person"]["properties"]["email"] == Dict(
        "type" => "string",
        "format" => "email"
    )

    @test !haskey(result["\$defs"], "Unused")

    keys_list = collect(keys(result["\$defs"]))
    string_idx = findfirst(k -> k == "String", keys_list)
    person_idx = findfirst(k -> k == "Person", keys_list)
    @test string_idx < person_idx
end

@testset "simplify_schema - idempotence" begin
    doc = Dict(
        "\$ref" => "#/\$defs/A",
        "\$defs" => Dict(
            "A" => Dict("anyOf" => [Dict("type" => "string")]),
            "B" => Dict("type" => "integer")
        )
    )

    result1 = simplify_schema(doc)
    result2 = simplify_schema(result1)

    @test result1 == result2
end

@testset "simplify_schema - empty defs removal" begin
    doc = Dict(
        "\$schema" => "https://json-schema.org/draft/2020-12/schema",
        "\$defs" => Dict(
            "Unused" => Dict("type" => "string")
        )
    )

    result = simplify_schema(doc)
    @test !haskey(result, "\$defs")
end

@testset "simplify_schema - complex nested case" begin
    doc = Dict(
        "\$ref" => "#/\$defs/Root",
        "\$defs" => Dict(
            "Root" => Dict(
                "type" => "object",
                "properties" => Dict(
                    "field1" => Dict(
                        "allOf" => [
                            Dict(
                                "anyOf" => [Dict("\$ref" => "#/\$defs/Inner")]
                            ),
                        ]
                    )
                ),
                "required" => []
            ),
            "Inner" => Dict("type" => "string", "minLength" => 1),
            "Orphan" => Dict("type" => "number")
        )
    )

    result = simplify_schema(doc)

    @test result["\$defs"]["Root"]["properties"]["field1"] == Dict(
        "type" => "string",
        "minLength" => 1
    )

    @test !haskey(result["\$defs"]["Root"], "required")

    @test !haskey(result["\$defs"], "Orphan")

    @test !haskey(result["\$defs"], "Inner")
end

@testset "inline_single_use_refs - all defs inlined" begin
    doc = Dict(
        "\$ref" => "#/\$defs/Root",
        "\$defs" => Dict(
            "Root" => Dict(
                "type" => "object",
                "properties" => Dict(
                    "field" => Dict("\$ref" => "#/\$defs/Inline")
                )
            ),
            "Inline" => Dict("type" => "string", "minLength" => 1)
        )
    )

    result = inline_single_use_refs(doc)

    @test !haskey(result, "\$defs") || !haskey(result["\$defs"], "Inline")
end

@testset "is_recursive - anyOf with recursive ref" begin
    # Test recursive detection in anyOf combinator
    doc = Dict(
        "\$ref" => "#/\$defs/Node",
        "\$defs" => Dict(
            "Node" => Dict(
                "anyOf" => [
                    Dict("type" => "null"),
                    Dict(
                        "type" => "object",
                        "properties" => Dict(
                            "next" => Dict("\$ref" => "#/\$defs/Node")
                        )
                    )
                ]
            )
        )
    )

    result = inline_single_use_refs(doc)

    # Node is recursive so should not be inlined
    @test haskey(result["\$defs"], "Node")
end

@testset "sort_defs - array without items" begin
    doc = Dict(
        "\$defs" => Dict(
            "Object" => Dict(
                "type" => "object",
                "properties" => Dict("arr" => Dict("\$ref" => "#/\$defs/Array"))
            ),
            "Array" => Dict("type" => "array")
        )
    )

    result = sort_defs(doc)
    keys_list = collect(keys(result["\$defs"]))

    array_idx = findfirst(k -> k == "Array", keys_list)
    object_idx = findfirst(k -> k == "Object", keys_list)
    @test array_idx < object_idx
end
