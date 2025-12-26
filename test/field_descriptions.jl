using Test
using Struct2JSONSchema: SchemaContext, generate_schema, register_field_description!, k
using REPL

const _FIELD_DESC_KEY_CTX = SchemaContext()
field_desc_key(T) = k(T, _FIELD_DESC_KEY_CTX)

@testset "Field descriptions - basic registration" begin
    struct BasicUser
        id::Int
        name::String
        email::String
    end

    ctx = SchemaContext()
    register_field_description!(ctx, BasicUser, :email, "User's primary email address")
    register_field_description!(ctx, BasicUser, :id, "Unique user identifier")

    result = generate_schema(BasicUser; ctx = ctx, simplify = false)
    defs = result.doc["\$defs"]
    schema = defs[field_desc_key(BasicUser)]

    # Check that descriptions are added
    @test haskey(schema["properties"]["email"], "description")
    @test schema["properties"]["email"]["description"] == "User's primary email address"
    @test haskey(schema["properties"]["id"], "description")
    @test schema["properties"]["id"]["description"] == "Unique user identifier"

    # Field without description should not have it
    @test !haskey(schema["properties"]["name"], "description")
end

@testset "Field descriptions - allOf structure with \$ref" begin
    struct Product
        id::Int
        price::Float64
    end

    ctx = SchemaContext()
    register_field_description!(ctx, Product, :id, "Product identifier")

    result = generate_schema(Product; ctx = ctx, simplify = false)
    defs = result.doc["\$defs"]
    schema = defs[field_desc_key(Product)]

    # Should use allOf when description is added to a $ref
    prop = schema["properties"]["id"]
    @test haskey(prop, "allOf")
    @test haskey(prop, "description")
    @test length(prop["allOf"]) == 1
    @test haskey(prop["allOf"][1], "\$ref")
    @test prop["description"] == "Product identifier"
end

@testset "Field descriptions - multiple fields" begin
    struct Article
        id::Int
        title::String
        content::String
        author::String
    end

    ctx = SchemaContext()

    descriptions = Dict(
        :id => "Article unique identifier",
        :title => "Article title",
        :content => "Article main content"
    )

    for (field, desc) in descriptions
        register_field_description!(ctx, Article, field, desc)
    end

    result = generate_schema(Article; ctx = ctx, simplify = false)
    defs = result.doc["\$defs"]
    schema = defs[field_desc_key(Article)]

    @test schema["properties"]["id"]["description"] == "Article unique identifier"
    @test schema["properties"]["title"]["description"] == "Article title"
    @test schema["properties"]["content"]["description"] == "Article main content"
    @test !haskey(schema["properties"]["author"], "description")
end

@testset "Field descriptions - auto extraction from docstring" begin
    """
    User information
    """
    struct DocumentedUser
        """User's unique identifier"""
        id::Int

        """User's full name"""
        name::String

        email::String  # No docstring
    end

    ctx = SchemaContext(auto_fielddoc = true)
    result = generate_schema(DocumentedUser; ctx = ctx, simplify = false)
    defs = result.doc["\$defs"]
    schema = defs[field_desc_key(DocumentedUser)]

    # Descriptions from docstrings
    @test haskey(schema["properties"]["id"], "description")
    @test schema["properties"]["id"]["description"] == "User's unique identifier"
    @test haskey(schema["properties"]["name"], "description")
    @test schema["properties"]["name"]["description"] == "User's full name"

    # No docstring, no description
    @test !haskey(schema["properties"]["email"], "description")
end

@testset "Field descriptions - manual registration overrides docstring" begin
    """
    Event data
    """
    struct EventData
        """Event identifier from docstring"""
        id::Int

        """Event timestamp"""
        timestamp::String
    end

    ctx = SchemaContext(auto_fielddoc = true)
    register_field_description!(ctx, EventData, :id, "Event unique ID (overridden)")

    result = generate_schema(EventData; ctx = ctx, simplify = false)
    defs = result.doc["\$defs"]
    schema = defs[field_desc_key(EventData)]

    # Manual registration should override docstring
    @test schema["properties"]["id"]["description"] == "Event unique ID (overridden)"
    # Docstring should still work for non-overridden fields
    @test schema["properties"]["timestamp"]["description"] == "Event timestamp"
end

@testset "Field descriptions - auto_fielddoc=false" begin
    """
    Configuration struct
    """
    struct Config
        """Port number"""
        port::Int

        """Host address"""
        host::String
    end

    ctx = SchemaContext(auto_fielddoc = false)
    result = generate_schema(Config; ctx = ctx, simplify = false)
    defs = result.doc["\$defs"]
    schema = defs[field_desc_key(Config)]

    # With auto_fielddoc=false, docstrings should not be extracted
    @test !haskey(schema["properties"]["port"], "description")
    @test !haskey(schema["properties"]["host"], "description")
end

@testset "Field descriptions - auto_fielddoc=false with manual registration" begin
    """
    Server settings
    """
    struct ServerSettings
        """Server port"""
        port::Int

        timeout::Int
    end

    ctx = SchemaContext(auto_fielddoc = false)
    register_field_description!(ctx, ServerSettings, :port, "Manual port description")

    result = generate_schema(ServerSettings; ctx = ctx, simplify = false)
    defs = result.doc["\$defs"]
    schema = defs[field_desc_key(ServerSettings)]

    # Manual registration should work even with auto_fielddoc=false
    @test haskey(schema["properties"]["port"], "description")
    @test schema["properties"]["port"]["description"] == "Manual port description"
    @test !haskey(schema["properties"]["timeout"], "description")
end

@testset "Field descriptions - struct without type-level docstring" begin
    struct NoTypeDoc
        """Field doc"""
        value::Int
    end

    ctx = SchemaContext(auto_fielddoc = true)
    result = generate_schema(NoTypeDoc; ctx = ctx, simplify = false)
    defs = result.doc["\$defs"]
    schema = defs[field_desc_key(NoTypeDoc)]

    # REPL.fielddoc won't work without type-level docstring
    # So description should not be present
    @test !haskey(schema["properties"]["value"], "description")
end

@testset "Field descriptions - error on non-existent field" begin
    struct TestStruct
        field1::Int
    end

    ctx = SchemaContext()

    @test_throws ArgumentError register_field_description!(
        ctx, TestStruct, :nonexistent, "Description"
    )
end

@testset "Field descriptions - error on non-struct type" begin
    ctx = SchemaContext()

    @test_throws ArgumentError register_field_description!(
        ctx, Int, :value, "Description"
    )
end

@testset "Field descriptions - combined with field overrides" begin
    using Dates

    struct EventWithOverride
        id::Int
        timestamp::DateTime
        description::String
    end

    ctx = SchemaContext()

    # Register field override for timestamp
    register_field_override!(ctx, EventWithOverride, :timestamp) do ctx
        Dict(
            "type" => "string",
            "format" => "date-time"
        )
    end

    # Register description for timestamp
    register_field_description!(ctx, EventWithOverride, :timestamp, "ISO 8601 timestamp")
    register_field_description!(ctx, EventWithOverride, :id, "Event identifier")

    result = generate_schema(EventWithOverride; ctx = ctx, simplify = false)
    defs = result.doc["\$defs"]
    schema = defs[field_desc_key(EventWithOverride)]

    # Override should apply
    @test schema["properties"]["timestamp"]["type"] == "string"
    @test schema["properties"]["timestamp"]["format"] == "date-time"

    # Description should be added
    @test haskey(schema["properties"]["timestamp"], "description")
    @test schema["properties"]["timestamp"]["description"] == "ISO 8601 timestamp"

    # Regular field with description
    @test schema["properties"]["id"]["description"] == "Event identifier"
end

@testset "Field descriptions - empty description handling" begin
    struct EmptyDescTest
        field1::Int
    end

    ctx = SchemaContext()
    register_field_description!(ctx, EmptyDescTest, :field1, "")

    result = generate_schema(EmptyDescTest; ctx = ctx, simplify = false)
    defs = result.doc["\$defs"]
    schema = defs[field_desc_key(EmptyDescTest)]

    # Empty description should still be added (user's choice)
    @test haskey(schema["properties"]["field1"], "description")
    @test schema["properties"]["field1"]["description"] == ""
end

@testset "Field descriptions - unicode and special characters" begin
    struct UnicodeTest
        field1::String
        field2::String
    end

    ctx = SchemaContext()
    register_field_description!(ctx, UnicodeTest, :field1, "ユーザー名 (Japanese)")
    register_field_description!(ctx, UnicodeTest, :field2, "Field with \"quotes\" and\nnewlines")

    result = generate_schema(UnicodeTest; ctx = ctx, simplify = false)
    defs = result.doc["\$defs"]
    schema = defs[field_desc_key(UnicodeTest)]

    @test schema["properties"]["field1"]["description"] == "ユーザー名 (Japanese)"
    @test schema["properties"]["field2"]["description"] == "Field with \"quotes\" and\nnewlines"
end

@testset "Field descriptions - clone_context preserves descriptions" begin
    struct CloneTest
        field1::Int
    end

    ctx = SchemaContext()
    register_field_description!(ctx, CloneTest, :field1, "Original description")

    # Use generate_schema (safe version, which clones context)
    result = generate_schema(CloneTest; ctx = ctx, simplify = false)
    defs = result.doc["\$defs"]
    schema = defs[field_desc_key(CloneTest)]

    @test schema["properties"]["field1"]["description"] == "Original description"

    # Original context should still have the description
    @test haskey(ctx.field_metadata.descriptions, (CloneTest, :field1))
    @test ctx.field_metadata.descriptions[(CloneTest, :field1)] == "Original description"
end
