using Test
using Struct2JSONSchema: SchemaContext, generate_schema, register_abstract!, register_optional_fields!, JSONScalar

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

@testset "register_abstract! - non-abstract type error" begin
    ctx = SchemaContext()
    @test_throws ArgumentError register_abstract!(
        ctx, ConcreteType;
        variants = DataType[],
        discr_key = "kind",
        tag_value = Dict{DataType, JSONScalar}()
    )
end

@testset "register_abstract! - variant not subtype of parent" begin
    ctx = SchemaContext()
    @test_throws ArgumentError register_abstract!(
        ctx, TestAbstractType;
        variants = [ConcreteVariant1, UnrelatedVariant],
        discr_key = "type",
        tag_value = Dict{DataType, JSONScalar}(
            ConcreteVariant1 => "variant1",
            UnrelatedVariant => "unrelated"
        )
    )
end

@testset "register_abstract! - non-concrete variant" begin
    ctx = SchemaContext()
    @test_throws ArgumentError register_abstract!(
        ctx, TestAbstractType;
        variants = [TestAbstractType],
        discr_key = "type",
        tag_value = Dict{DataType, JSONScalar}(TestAbstractType => "abstract")
    )
end

@testset "register_abstract! - tag_value keys mismatch variants" begin
    ctx = SchemaContext()
    @test_throws ArgumentError register_abstract!(
        ctx, TestAbstractType;
        variants = [ConcreteVariant1, ConcreteVariant2],
        discr_key = "type",
        tag_value = Dict{DataType, JSONScalar}(ConcreteVariant1 => "variant1")
    )
end

@testset "register_abstract! - duplicate tag values" begin
    ctx = SchemaContext()
    @test_throws ArgumentError register_abstract!(
        ctx, TestAbstractType;
        variants = [ConcreteVariant1, ConcreteVariant2],
        discr_key = "type",
        tag_value = Dict{DataType, JSONScalar}(
            ConcreteVariant1 => "same",
            ConcreteVariant2 => "same"
        )
    )
end

@testset "register_abstract! - non-JSONScalar tag value" begin
    ctx = SchemaContext()
    @test_throws ArgumentError register_abstract!(
        ctx, TestAbstractType;
        variants = [ConcreteVariant1],
        discr_key = "type",
        tag_value = Dict(ConcreteVariant1 => [1, 2, 3])
    )
end

@testset "register_abstract! - tag_value not a dict" begin
    ctx = SchemaContext()
    @test_throws ArgumentError register_abstract!(
        ctx, TestAbstractType;
        variants = [ConcreteVariant1],
        discr_key = "type",
        tag_value = "not a dict"
    )
end

@testset "register_optional_fields! - non-struct type" begin
    ctx = SchemaContext()
    @test_throws ArgumentError register_optional_fields!(ctx, Int, :field)
end

@testset "register_optional_fields! - abstract type" begin
    ctx = SchemaContext()
    @test_throws ArgumentError register_optional_fields!(ctx, TestAbstractType, :field)
end

@testset "register_optional_fields! - non-existent field" begin
    ctx = SchemaContext()
    @test_throws ArgumentError register_optional_fields!(ctx, ConcreteType, :nonexistent)
end

@testset "register_optional_fields! - UnionAll type" begin
    ctx = SchemaContext()
    @test_throws ArgumentError register_optional_fields!(ctx, Vector, :field)
end

@testset "register_optional_fields! - multiple non-existent fields" begin
    ctx = SchemaContext()
    @test_throws ArgumentError register_optional_fields!(ctx, ConcreteType, :value, :fake)
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

@testset "register_abstract! - all validations pass" begin
    ctx = SchemaContext()
    @test register_abstract!(
        ctx, AnimalBase;
        variants = [Cat, Dog],
        discr_key = "animal_type",
        tag_value = Dict{DataType, JSONScalar}(
            Cat => "cat",
            Dog => "dog"
        ),
        require_discr = true
    ) === nothing

    result = generate_schema(AnimalBase; ctx = ctx, simplify = false)
    @test haskey(result.doc, "\$defs")
end

@testset "register_abstract! - numeric tag values" begin
    ctx = SchemaContext()
    @test register_abstract!(
        ctx, AnimalBase;
        variants = [Cat, Dog],
        discr_key = "type_id",
        tag_value = Dict{DataType, JSONScalar}(
            Cat => 1,
            Dog => 2
        )
    ) === nothing
end

@testset "register_abstract! - boolean tag values" begin
    ctx = SchemaContext()
    @test register_abstract!(
        ctx, AnimalBase;
        variants = [Cat],
        discr_key = "is_cat",
        tag_value = Dict{DataType, JSONScalar}(Cat => true)
    ) === nothing
end

@testset "register_abstract! - nothing tag value" begin
    ctx = SchemaContext()
    @test register_abstract!(
        ctx, AnimalBase;
        variants = [Cat],
        discr_key = "marker",
        tag_value = Dict{DataType, JSONScalar}(Cat => nothing)
    ) === nothing
end

struct TypeWithUnsupportedField
    func::Function
end

@testset "unsupported field type generates unknowns" begin
    ctx = SchemaContext()
    result = generate_schema(TypeWithUnsupportedField; ctx = ctx, simplify = false)
    @test !isempty(result.unknowns)
    @test (Function, (:func,)) in result.unknowns
end

struct TypeWithMultipleUnsupported
    func1::Function
    func2::Function
    value::Int
end

@testset "multiple unsupported fields" begin
    ctx = SchemaContext()
    result = generate_schema(TypeWithMultipleUnsupported; ctx = ctx, simplify = false)
    @test length(result.unknowns) == 2 # Ensure both are recorded
    @test (Function, (:func1,)) in result.unknowns
    @test (Function, (:func2,)) in result.unknowns
end

struct TypeWithUnionAll
    data::Vector
end

@testset "UnionAll type generates unknowns" begin
    ctx = SchemaContext()
    result = generate_schema(TypeWithUnionAll; ctx = ctx, simplify = false)
    @test !isempty(result.unknowns)
    @test (Vector, (:data,)) in result.unknowns
end

@testset "register_abstract! - extra keys in tag_value" begin
    ctx = SchemaContext()
    @test_throws ArgumentError register_abstract!(
        ctx, AnimalBase;
        variants = [Cat],
        discr_key = "type",
        tag_value = Dict{DataType, JSONScalar}(
            Cat => "cat",
            Dog => "dog"
        )
    )
end
