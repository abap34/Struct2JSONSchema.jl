using Test
using Struct2JSONSchema: SchemaContext, generate_schema, override_abstract!, optional!, RepresentableScalar, UnknownEntry

# Test types for validation errors
struct ConcreteType
    value::Int
end

abstract type TestAbstractType end

struct ConcreteVariant1 <: TestAbstractType
    field::String
end

struct ConcreteVariant2 <: TestAbstractType
    field::Int
end

abstract type OtherAbstractType end

struct UnrelatedVariant <: OtherAbstractType
    data::String
end

@testset "override_abstract! - non-abstract type error" begin
    ctx = SchemaContext()
    @test_throws ArgumentError override_abstract!(
        ctx, ConcreteType;
        variants = DataType[],
        discr_key = "kind",
        tag_value = Dict{DataType, RepresentableScalar}()
    )
end

@testset "override_abstract! - variant not subtype of parent" begin
    ctx = SchemaContext()
    @test_throws ArgumentError override_abstract!(
        ctx, TestAbstractType;
        variants = [ConcreteVariant1, UnrelatedVariant],
        discr_key = "type",
        tag_value = Dict{DataType, RepresentableScalar}(
            ConcreteVariant1 => "variant1",
            UnrelatedVariant => "unrelated"
        )
    )
end

@testset "override_abstract! - non-concrete variant" begin
    ctx = SchemaContext()
    @test_throws ArgumentError override_abstract!(
        ctx, TestAbstractType;
        variants = [TestAbstractType],
        discr_key = "type",
        tag_value = Dict{DataType, RepresentableScalar}(TestAbstractType => "abstract")
    )
end

@testset "override_abstract! - tag_value keys mismatch variants" begin
    ctx = SchemaContext()
    @test_throws ArgumentError override_abstract!(
        ctx, TestAbstractType;
        variants = [ConcreteVariant1, ConcreteVariant2],
        discr_key = "type",
        tag_value = Dict{DataType, RepresentableScalar}(ConcreteVariant1 => "variant1")
    )
end

@testset "override_abstract! - duplicate tag values" begin
    ctx = SchemaContext()
    @test_throws ArgumentError override_abstract!(
        ctx, TestAbstractType;
        variants = [ConcreteVariant1, ConcreteVariant2],
        discr_key = "type",
        tag_value = Dict{DataType, RepresentableScalar}(
            ConcreteVariant1 => "same",
            ConcreteVariant2 => "same"
        )
    )
end

@testset "override_abstract! - non-RepresentableScalar tag value" begin
    ctx = SchemaContext()
    @test_throws ArgumentError override_abstract!(
        ctx, TestAbstractType;
        variants = [ConcreteVariant1],
        discr_key = "type",
        tag_value = Dict(ConcreteVariant1 => [1, 2, 3])
    )
end

@testset "override_abstract! - tag_value not a dict" begin
    ctx = SchemaContext()
    @test_throws ArgumentError override_abstract!(
        ctx, TestAbstractType;
        variants = [ConcreteVariant1],
        discr_key = "type",
        tag_value = "not a dict"
    )
end

@testset "optional! - non-struct type" begin
    ctx = SchemaContext()
    @test_throws ArgumentError optional!(ctx, Int, :field)
end

@testset "optional! - abstract type" begin
    ctx = SchemaContext()
    @test_throws ArgumentError optional!(ctx, TestAbstractType, :field)
end

@testset "optional! - non-existent field" begin
    ctx = SchemaContext()
    @test_throws ArgumentError optional!(ctx, ConcreteType, :nonexistent)
end

@testset "optional! - UnionAll type" begin
    ctx = SchemaContext()
    @test_throws ArgumentError optional!(ctx, Vector, :field)
end

@testset "optional! - multiple non-existent fields" begin
    ctx = SchemaContext()
    @test_throws ArgumentError optional!(ctx, ConcreteType, :value, :fake)
end

struct SelfReferencing
    value::Int
    children::Vector{SelfReferencing}
end

@testset "self-referencing type" begin
    ctx = SchemaContext()
    result = generate_schema(SelfReferencing; ctx = ctx, simplify = false)
    @test haskey(result.doc, "\$defs")
    @test !isempty(result.doc["\$defs"])
end

abstract type AnimalBase end

struct Cat <: AnimalBase
    name::String
end

struct Dog <: AnimalBase
    name::String
    breed::String
end

@testset "override_abstract! - all validations pass" begin
    ctx = SchemaContext()
    @test override_abstract!(
        ctx, AnimalBase;
        variants = [Cat, Dog],
        discr_key = "animal_type",
        tag_value = Dict{DataType, RepresentableScalar}(
            Cat => "cat",
            Dog => "dog"
        ),
        require_discr = true
    ) === nothing

    result = generate_schema(AnimalBase; ctx = ctx, simplify = false)
    @test haskey(result.doc, "\$defs")
end

@testset "override_abstract! - numeric tag values" begin
    ctx = SchemaContext()
    @test override_abstract!(
        ctx, AnimalBase;
        variants = [Cat, Dog],
        discr_key = "type_id",
        tag_value = Dict{DataType, RepresentableScalar}(
            Cat => 1,
            Dog => 2
        )
    ) === nothing
end

@testset "override_abstract! - boolean tag values" begin
    ctx = SchemaContext()
    @test override_abstract!(
        ctx, AnimalBase;
        variants = [Cat],
        discr_key = "is_cat",
        tag_value = Dict{DataType, RepresentableScalar}(Cat => true)
    ) === nothing
end

@testset "override_abstract! - nothing tag value" begin
    ctx = SchemaContext()
    @test override_abstract!(
        ctx, AnimalBase;
        variants = [Cat],
        discr_key = "marker",
        tag_value = Dict{DataType, RepresentableScalar}(Cat => nothing)
    ) === nothing
end

struct TypeWithUnsupportedField
    func::Function
end

@testset "unsupported field type generates unknowns" begin
    ctx = SchemaContext()
    result = generate_schema(TypeWithUnsupportedField; ctx = ctx, simplify = false)
    @test !isempty(result.unknowns)
    @test any(e -> e.type == Function && e.path == (:func,) && e.reason == "abstract_no_discriminator", result.unknowns)
end

struct TypeWithMultipleUnsupported
    func1::Function
    func2::Function
    value::Int
end

@testset "multiple unsupported fields" begin
    ctx = SchemaContext()
    result = generate_schema(TypeWithMultipleUnsupported; ctx = ctx, simplify = false)
    # Function is recorded once, not multiple times for different fields
    @test length(result.unknowns) == 1
    @test any(e -> e.type == Function && e.reason == "abstract_no_discriminator", result.unknowns)
end

struct TypeWithUnionAll
    data::Vector
end

@testset "UnionAll type generates unknowns" begin
    ctx = SchemaContext()
    result = generate_schema(TypeWithUnionAll; ctx = ctx, simplify = false)
    @test !isempty(result.unknowns)
    @test any(e -> e.type == Vector && e.path == (:data,) && e.reason == "unionall_type", result.unknowns)
end

@testset "override_abstract! - extra keys in tag_value" begin
    ctx = SchemaContext()
    @test_throws ArgumentError override_abstract!(
        ctx, AnimalBase;
        variants = [Cat],
        discr_key = "type",
        tag_value = Dict{DataType, RepresentableScalar}(
            Cat => "cat",
            Dog => "dog"
        )
    )
end
