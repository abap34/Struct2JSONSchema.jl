using Test
using Struct2JSONSchema

@testset "Skip Fields" begin
    @testset "Basic skip functionality" begin
        struct SimpleSkip
            id::Int
            name::String
            _internal::String
        end

        ctx = SchemaContext()
        register_skip_fields!(ctx, SimpleSkip, :_internal)

        result = generate_schema(SimpleSkip; ctx = ctx)
        key = ctx.key_of[SimpleSkip]
        schema = result.doc["\$defs"][key]

        @test haskey(schema, "properties")
        @test haskey(schema["properties"], "id")
        @test haskey(schema["properties"], "name")
        @test !haskey(schema["properties"], "_internal")

        @test schema["required"] == ["id", "name"]
    end

    @testset "Multiple fields skip" begin
        struct MultiSkip
            keep1::Int
            skip1::String
            keep2::Bool
            skip2::Float64
            skip3::Vector{Int}
        end

        ctx = SchemaContext()
        register_skip_fields!(ctx, MultiSkip, :skip1, :skip2, :skip3)

        result = generate_schema(MultiSkip; ctx = ctx)
        key = ctx.key_of[MultiSkip]
        schema = result.doc["\$defs"][key]

        @test Set(keys(schema["properties"])) == Set(["keep1", "keep2"])
        @test schema["required"] == ["keep1", "keep2"]
    end

    @testset "Skip with optional fields" begin
        struct SkipOptional
            id::Int
            optional_field::Union{String, Nothing}
            _skip_me::Dict
        end

        ctx = SchemaContext()
        treat_union_nothing_as_optional!(ctx)
        register_skip_fields!(ctx, SkipOptional, :_skip_me)

        result = generate_schema(SkipOptional; ctx = ctx)
        key = ctx.key_of[SkipOptional]
        schema = result.doc["\$defs"][key]

        @test haskey(schema["properties"], "id")
        @test haskey(schema["properties"], "optional_field")
        @test !haskey(schema["properties"], "_skip_me")
        @test schema["required"] == ["id"]
    end

    @testset "Error on non-existent field" begin
        struct ErrorTest
            field1::Int
        end

        ctx = SchemaContext()
        @test_throws ArgumentError register_skip_fields!(ctx, ErrorTest, :nonexistent)
    end

    @testset "Error on non-struct type" begin
        ctx = SchemaContext()
        @test_throws ArgumentError register_skip_fields!(ctx, Int, :field)
    end

    @testset "Skip all fields except one" begin
        struct AlmostEmpty
            keep::Int
            skip1::String
            skip2::Bool
        end

        ctx = SchemaContext()
        register_skip_fields!(ctx, AlmostEmpty, :skip1, :skip2)

        result = generate_schema(AlmostEmpty; ctx = ctx)
        key = ctx.key_of[AlmostEmpty]
        schema = result.doc["\$defs"][key]

        @test length(schema["properties"]) == 1
        @test haskey(schema["properties"], "keep")
        @test schema["required"] == ["keep"]
    end

    @testset "Empty skip list" begin
        struct NoSkip
            field1::Int
            field2::String
        end

        ctx = SchemaContext()
        register_skip_fields!(ctx, NoSkip)  # No fields specified

        result = generate_schema(NoSkip; ctx = ctx)
        key = ctx.key_of[NoSkip]
        schema = result.doc["\$defs"][key]

        @test length(schema["properties"]) == 2
        @test schema["required"] == ["field1", "field2"]
    end

    @testset "Cumulative skip registration" begin
        struct Cumulative
            f1::Int
            f2::String
            f3::Bool
            f4::Float64
        end

        ctx = SchemaContext()
        register_skip_fields!(ctx, Cumulative, :f2)
        register_skip_fields!(ctx, Cumulative, :f4)  # Add more

        result = generate_schema(Cumulative; ctx = ctx)
        key = ctx.key_of[Cumulative]
        schema = result.doc["\$defs"][key]

        @test Set(keys(schema["properties"])) == Set(["f1", "f3"])
        @test Set(schema["required"]) == Set(["f1", "f3"])
    end

    @testset "Skip with field descriptions" begin
        struct SkipDescription
            id::Int
            name::String
            _internal::String
        end

        ctx = SchemaContext()
        register_skip_fields!(ctx, SkipDescription, :_internal)
        register_field_description!(ctx, SkipDescription, :id, "User ID")
        register_field_description!(ctx, SkipDescription, :_internal, "Should be ignored")

        result = generate_schema(SkipDescription; ctx = ctx, simplify = false)
        key = ctx.key_of[SkipDescription]
        schema = result.doc["\$defs"][key]

        @test !haskey(schema["properties"], "_internal")
        @test haskey(schema["properties"]["id"], "description")
    end

    @testset "register_only_fields! basic" begin
        struct OnlyBasic
            keep1::Int
            keep2::String
            skip1::Bool
            skip2::Float64
        end

        ctx = SchemaContext()
        register_only_fields!(ctx, OnlyBasic, :keep1, :keep2)

        result = generate_schema(OnlyBasic; ctx = ctx)
        key = ctx.key_of[OnlyBasic]
        schema = result.doc["\$defs"][key]

        @test Set(keys(schema["properties"])) == Set(["keep1", "keep2"])
        @test Set(schema["required"]) == Set(["keep1", "keep2"])
        @test !haskey(schema["properties"], "skip1")
        @test !haskey(schema["properties"], "skip2")
    end

    @testset "register_only_fields! single field" begin
        struct OnlySingle
            important::String
            noise1::Int
            noise2::Bool
        end

        ctx = SchemaContext()
        register_only_fields!(ctx, OnlySingle, :important)

        result = generate_schema(OnlySingle; ctx = ctx)
        key = ctx.key_of[OnlySingle]
        schema = result.doc["\$defs"][key]

        @test length(schema["properties"]) == 1
        @test haskey(schema["properties"], "important")
        @test schema["required"] == ["important"]
    end

    @testset "register_only_fields! all fields" begin
        struct OnlyAll
            f1::Int
            f2::String
        end

        ctx = SchemaContext()
        register_only_fields!(ctx, OnlyAll, :f1, :f2)

        result = generate_schema(OnlyAll; ctx = ctx)
        key = ctx.key_of[OnlyAll]
        schema = result.doc["\$defs"][key]

        @test length(schema["properties"]) == 2
        @test Set(schema["required"]) == Set(["f1", "f2"])
    end

    @testset "register_only_fields! error on non-existent field" begin
        struct OnlyError
            f1::Int
        end

        ctx = SchemaContext()
        @test_throws ArgumentError register_only_fields!(ctx, OnlyError, :nonexistent)
    end

    @testset "Skip all fields" begin
        struct AllSkipped
            f1::Int
            f2::String
            f3::Bool
        end

        ctx = SchemaContext()
        register_skip_fields!(ctx, AllSkipped, :f1, :f2, :f3)

        result = generate_schema(AllSkipped; ctx = ctx)
        key = ctx.key_of[AllSkipped]
        schema = result.doc["\$defs"][key]

        @test length(schema["properties"]) == 0
        @test get(schema, "required", []) == []
    end

    @testset "Skip with field override" begin
        struct SkipOverride
            id::Int
            email::String
            _cache::Dict
        end

        ctx = SchemaContext()
        register_field_override!(ctx, SkipOverride, :email) do ctx
            Dict("type" => "string", "format" => "email")
        end
        register_skip_fields!(ctx, SkipOverride, :_cache)

        result = generate_schema(SkipOverride; ctx = ctx)
        key = ctx.key_of[SkipOverride]
        schema = result.doc["\$defs"][key]

        @test haskey(schema["properties"], "email")
        @test schema["properties"]["email"]["format"] == "email"
        @test !haskey(schema["properties"], "_cache")
    end

    @testset "Skip and optional on same field prioritizes skip" begin
        struct SkipOptionalConflict
            id::Int
            maybe_skip::Union{String, Nothing}
        end

        ctx = SchemaContext()
        register_optional_fields!(ctx, SkipOptionalConflict, :maybe_skip)
        register_skip_fields!(ctx, SkipOptionalConflict, :maybe_skip)

        result = generate_schema(SkipOptionalConflict; ctx = ctx)
        key = ctx.key_of[SkipOptionalConflict]
        schema = result.doc["\$defs"][key]

        @test !haskey(schema["properties"], "maybe_skip")
        @test schema["required"] == ["id"]
    end

    @testset "Nested struct with skip" begin
        struct NestedInner
            value::Int
            _internal::String
        end

        struct NestedOuter
            inner::NestedInner
            name::String
            _metadata::Dict
        end

        ctx = SchemaContext()
        register_skip_fields!(ctx, NestedInner, :_internal)
        register_skip_fields!(ctx, NestedOuter, :_metadata)

        result = generate_schema(NestedOuter; ctx = ctx, simplify = false)

        outer_key = ctx.key_of[NestedOuter]
        outer_schema = result.doc["\$defs"][outer_key]
        @test !haskey(outer_schema["properties"], "_metadata")
        @test haskey(outer_schema["properties"], "inner")

        inner_key = ctx.key_of[NestedInner]
        inner_schema = result.doc["\$defs"][inner_key]
        @test !haskey(inner_schema["properties"], "_internal")
        @test haskey(inner_schema["properties"], "value")
    end

    @testset "Skipped field type still defined if used elsewhere" begin
        struct UsedElsewhere
            data::Vector{Int}
        end

        struct Container
            used::UsedElsewhere
            skipped::UsedElsewhere
        end

        ctx = SchemaContext()
        register_skip_fields!(ctx, Container, :skipped)

        result = generate_schema(Container; ctx = ctx, simplify = false)

        # UsedElsewhere should still be in $defs because 'used' field references it
        @test haskey(ctx.key_of, UsedElsewhere)
        used_key = ctx.key_of[UsedElsewhere]
        @test haskey(result.doc["\$defs"], used_key)
    end

    @testset "Combining skip and only on same type" begin
        struct CombineSkipOnly
            f1::Int
            f2::String
            f3::Bool
            f4::Float64
        end

        ctx = SchemaContext()
        register_only_fields!(ctx, CombineSkipOnly, :f1, :f2, :f3)
        register_skip_fields!(ctx, CombineSkipOnly, :f3)  # Further restrict

        result = generate_schema(CombineSkipOnly; ctx = ctx)
        key = ctx.key_of[CombineSkipOnly]
        schema = result.doc["\$defs"][key]

        # f4 skipped by only, f3 skipped by skip, so only f1 and f2 remain
        @test Set(keys(schema["properties"])) == Set(["f1", "f2"])
    end
end
