using Test
using Struct2JSONSchema: SchemaContext, generate_schema
using Struct2JSONSchema: Struct2JSONSchema.expand_all_defs

# Tests for expand_all_defs function - complete inline expansion

@testset "expand_all_defs - basic case" begin
    doc = Dict(
        "\$schema" => "https://json-schema.org/draft/2020-12/schema",
        "\$ref" => "#/\$defs/Person",
        "\$defs" => Dict(
            "Person" => Dict(
                "type" => "object",
                "properties" => Dict(
                    "name" => Dict("type" => "string"),
                    "age" => Dict("type" => "integer")
                ),
                "required" => ["name", "age"],
                "additionalProperties" => false
            )
        )
    )

    result = expand_all_defs(doc)

    # Expected complete schema
    expected = Dict(
        "\$schema" => "https://json-schema.org/draft/2020-12/schema",
        "type" => "object",
        "properties" => Dict(
            "name" => Dict("type" => "string"),
            "age" => Dict("type" => "integer")
        ),
        "required" => ["name", "age"],
        "additionalProperties" => false
    )

    @test result == expected
end

@testset "expand_all_defs - nested structs" begin
    doc = Dict(
        "\$ref" => "#/\$defs/Person",
        "\$defs" => Dict(
            "Person" => Dict(
                "type" => "object",
                "properties" => Dict(
                    "name" => Dict("type" => "string"),
                    "address" => Dict("\$ref" => "#/\$defs/Address")
                ),
                "required" => ["name"]
            ),
            "Address" => Dict(
                "type" => "object",
                "properties" => Dict(
                    "city" => Dict("type" => "string"),
                    "zip" => Dict("type" => "string")
                ),
                "required" => ["city"]
            )
        )
    )

    result = expand_all_defs(doc)

    # Expected complete schema
    expected = Dict(
        "type" => "object",
        "properties" => Dict(
            "name" => Dict("type" => "string"),
            "address" => Dict(
                "type" => "object",
                "properties" => Dict(
                    "city" => Dict("type" => "string"),
                    "zip" => Dict("type" => "string")
                ),
                "required" => ["city"]
            )
        ),
        "required" => ["name"]
    )

    @test result == expected
end

@testset "expand_all_defs - recursive definition preserved" begin
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

    result = expand_all_defs(doc)

    # Recursive definition must remain in $defs
    @test haskey(result, "\$defs")
    @test haskey(result["\$defs"], "Node")
    @test haskey(result, "\$ref")
    @test result["\$ref"] == "#/\$defs/Node"
end

@testset "expand_all_defs - preserves metadata" begin
    doc = Dict(
        "\$ref" => "#/\$defs/Person",
        "\$defs" => Dict(
            "Person" => Dict(
                "type" => "object",
                "properties" => Dict(
                    "email" => Dict(
                        "\$ref" => "#/\$defs/Email",
                        "description" => "User's email address"
                    )
                )
            ),
            "Email" => Dict(
                "type" => "string",
                "format" => "email"
            )
        )
    )

    result = expand_all_defs(doc)

    # Expected complete schema with preserved metadata
    expected = Dict(
        "type" => "object",
        "properties" => Dict(
            "email" => Dict(
                "type" => "string",
                "format" => "email",
                "description" => "User's email address"
            )
        )
    )

    @test result == expected
end

@testset "expand_all_defs - multiple nesting levels" begin
    doc = Dict(
        "\$ref" => "#/\$defs/A",
        "\$defs" => Dict(
            "A" => Dict(
                "type" => "object",
                "properties" => Dict(
                    "b" => Dict("\$ref" => "#/\$defs/B")
                )
            ),
            "B" => Dict(
                "type" => "object",
                "properties" => Dict(
                    "c" => Dict("\$ref" => "#/\$defs/C")
                )
            ),
            "C" => Dict(
                "type" => "string",
                "minLength" => 1
            )
        )
    )

    result = expand_all_defs(doc)

    # Expected complete schema
    expected = Dict(
        "type" => "object",
        "properties" => Dict(
            "b" => Dict(
                "type" => "object",
                "properties" => Dict(
                    "c" => Dict(
                        "type" => "string",
                        "minLength" => 1
                    )
                )
            )
        )
    )

    @test result == expected
end

@testset "expand_all_defs - array types" begin
    doc = Dict(
        "\$ref" => "#/\$defs/Team",
        "\$defs" => Dict(
            "Team" => Dict(
                "type" => "object",
                "properties" => Dict(
                    "members" => Dict(
                        "type" => "array",
                        "items" => Dict("\$ref" => "#/\$defs/String")
                    )
                )
            ),
            "String" => Dict("type" => "string")
        )
    )

    result = expand_all_defs(doc)

    # Expected complete schema
    expected = Dict(
        "type" => "object",
        "properties" => Dict(
            "members" => Dict(
                "type" => "array",
                "items" => Dict("type" => "string")
            )
        )
    )

    @test result == expected
end

@testset "expand_all_defs - union types (anyOf)" begin
    doc = Dict(
        "\$ref" => "#/\$defs/Config",
        "\$defs" => Dict(
            "Config" => Dict(
                "type" => "object",
                "properties" => Dict(
                    "value" => Dict(
                        "anyOf" => [
                            Dict("\$ref" => "#/\$defs/StringType"),
                            Dict("\$ref" => "#/\$defs/IntType")
                        ]
                    )
                )
            ),
            "StringType" => Dict("type" => "string"),
            "IntType" => Dict("type" => "integer")
        )
    )

    result = expand_all_defs(doc)

    # Expected complete schema
    expected = Dict(
        "type" => "object",
        "properties" => Dict(
            "value" => Dict(
                "anyOf" => [
                    Dict("type" => "string"),
                    Dict("type" => "integer")
                ]
            )
        )
    )

    @test result == expected
end

@testset "expand_all_defs - empty defs" begin
    doc = Dict(
        "\$schema" => "https://json-schema.org/draft/2020-12/schema",
        "\$defs" => Dict{String, Any}()
    )

    result = expand_all_defs(doc)

    # Expected complete schema
    expected = Dict(
        "\$schema" => "https://json-schema.org/draft/2020-12/schema"
    )

    @test result == expected
end

@testset "expand_all_defs - preserves \$schema" begin
    doc = Dict(
        "\$schema" => "https://json-schema.org/draft/2020-12/schema",
        "\$ref" => "#/\$defs/Simple",
        "\$defs" => Dict(
            "Simple" => Dict("type" => "string")
        )
    )

    result = expand_all_defs(doc)

    # Expected complete schema
    expected = Dict(
        "\$schema" => "https://json-schema.org/draft/2020-12/schema",
        "type" => "string"
    )

    @test result == expected
end

@testset "expand_all_defs - circular reference (mutual recursion)" begin
    doc = Dict(
        "\$ref" => "#/\$defs/A",
        "\$defs" => Dict(
            "A" => Dict(
                "type" => "object",
                "properties" => Dict(
                    "b" => Dict("\$ref" => "#/\$defs/B")
                )
            ),
            "B" => Dict(
                "type" => "object",
                "properties" => Dict(
                    "a" => Dict("\$ref" => "#/\$defs/A")
                )
            )
        )
    )

    result = expand_all_defs(doc)

    # Both A and B are mutually recursive, so both must remain in $defs
    @test haskey(result, "\$defs")
    @test haskey(result["\$defs"], "A")
    @test haskey(result["\$defs"], "B")
    @test haskey(result, "\$ref")
end

@testset "expand_all_defs - mixed recursive and non-recursive" begin
    doc = Dict(
        "\$ref" => "#/\$defs/Root",
        "\$defs" => Dict(
            "Root" => Dict(
                "type" => "object",
                "properties" => Dict(
                    "simple" => Dict("\$ref" => "#/\$defs/Simple"),
                    "count" => Dict("type" => "integer")
                )
            ),
            "Simple" => Dict("type" => "string")
        )
    )

    result = expand_all_defs(doc)

    # Expected complete schema
    expected = Dict(
        "type" => "object",
        "properties" => Dict(
            "simple" => Dict("type" => "string"),
            "count" => Dict("type" => "integer")
        )
    )

    @test result == expected
end

@testset "expand_all_defs - preserves additional properties" begin
    doc = Dict(
        "\$ref" => "#/\$defs/Person",
        "\$defs" => Dict(
            "Person" => Dict(
                "type" => "object",
                "properties" => Dict(
                    "name" => Dict("type" => "string")
                ),
                "required" => ["name"],
                "additionalProperties" => false
            )
        )
    )

    result = expand_all_defs(doc)

    # All properties should be preserved
    @test result["type"] == "object"
    @test result["required"] == ["name"]
    @test result["additionalProperties"] == false
end

@testset "expand_all_defs - deep nesting" begin
    doc = Dict(
        "\$ref" => "#/\$defs/Level1",
        "\$defs" => Dict(
            "Level1" => Dict(
                "type" => "object",
                "properties" => Dict(
                    "level2" => Dict("\$ref" => "#/\$defs/Level2")
                )
            ),
            "Level2" => Dict(
                "type" => "object",
                "properties" => Dict(
                    "level3" => Dict("\$ref" => "#/\$defs/Level3")
                )
            ),
            "Level3" => Dict(
                "type" => "object",
                "properties" => Dict(
                    "level4" => Dict("\$ref" => "#/\$defs/Level4")
                )
            ),
            "Level4" => Dict("type" => "string")
        )
    )

    result = expand_all_defs(doc)

    # All levels should be fully expanded
    @test !haskey(result, "\$defs")
    @test !haskey(result, "\$ref")

    # Navigate through all levels
    level2 = result["properties"]["level2"]
    @test level2["type"] == "object"
    level3 = level2["properties"]["level3"]
    @test level3["type"] == "object"
    level4 = level3["properties"]["level4"]
    @test level4["type"] == "string"
end

@testset "expand_all_defs - preserves default values" begin
    doc = Dict(
        "\$ref" => "#/\$defs/Config",
        "\$defs" => Dict(
            "Config" => Dict(
                "type" => "object",
                "properties" => Dict(
                    "enabled" => Dict(
                        "type" => "boolean",
                        "default" => true
                    )
                ),
                "default" => Dict("enabled" => true)
            )
        )
    )

    result = expand_all_defs(doc)

    # Default values should be preserved
    @test result["default"] == Dict("enabled" => true)
    @test result["properties"]["enabled"]["default"] == true
end

@testset "expand_all_defs - recursive with anyOf" begin
    doc = Dict(
        "\$ref" => "#/\$defs/Node",
        "\$defs" => Dict(
            "Node" => Dict(
                "anyOf" => [
                    Dict("type" => "null"),
                    Dict(
                        "type" => "object",
                        "properties" => Dict(
                            "value" => Dict("type" => "integer"),
                            "next" => Dict("\$ref" => "#/\$defs/Node")
                        )
                    )
                ]
            )
        )
    )

    result = expand_all_defs(doc)

    # Node is recursive, so it should remain in $defs
    @test haskey(result, "\$defs")
    @test haskey(result["\$defs"], "Node")
    @test haskey(result, "\$ref")
    @test result["\$ref"] == "#/\$defs/Node"
end

# Integration test with generate_schema
@testset "expand_all_defs - integration with generate_schema" begin
    struct SimpleStruct
        name::String
        value::Int
    end

    doc, _ = generate_schema(SimpleStruct; inline_all_defs=true)

    # Should have no $defs section
    @test !haskey(doc, "\$defs")

    # Should have no $ref
    @test !haskey(doc, "\$ref")

    # Should have properties directly
    @test doc["type"] == "object"
    @test haskey(doc, "properties")
    @test doc["properties"]["name"]["type"] == "string"
    @test doc["properties"]["value"]["type"] == "integer"
end

@testset "expand_all_defs - integration with nested structs" begin
    struct InnerStruct
        value::String
    end

    struct OuterStruct
        inner::InnerStruct
        count::Int
    end

    doc, _ = generate_schema(OuterStruct; inline_all_defs=true)

    # Should have no $defs section
    @test !haskey(doc, "\$defs")
    @test !haskey(doc, "\$ref")

    # Inner struct should be fully expanded
    @test doc["type"] == "object"
    inner_schema = doc["properties"]["inner"]
    @test inner_schema["type"] == "object"
    @test inner_schema["properties"]["value"]["type"] == "string"
end

@testset "expand_all_defs - integration with Union types" begin
    struct ConfigStruct
        value::Union{String, Int}
    end

    doc, _ = generate_schema(ConfigStruct; inline_all_defs=true)

    # Should have no $defs section
    @test !haskey(doc, "\$defs")

    # Union should be expanded inline
    @test doc["properties"]["value"]["anyOf"] isa Vector
end

@testset "expand_all_defs - integration with arrays" begin
    struct TeamStruct
        members::Vector{String}
    end

    doc, _ = generate_schema(TeamStruct; inline_all_defs=true)

    # Should have no $defs section
    @test !haskey(doc, "\$defs")

    # Array should be fully inline
    members_schema = doc["properties"]["members"]
    @test members_schema["type"] == "array"
    @test members_schema["items"]["type"] == "string"
end
