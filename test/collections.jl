using Test
using Struct2JSONSchema: SchemaContext, generate_schema, k

struct CollectionRecord
    ints::Vector{Int64}
    nested::Vector{Vector{Float64}}
    tags::Set{String}
    pair::Tuple{String, Int64}
    metadata::Dict{String, Vector{Int64}}
    coords::NamedTuple{(:lat, :lon), Tuple{Float64, Float64}}
    samples::NTuple{3, Float64}
end


const _COLLECTION_KEY_CTX = SchemaContext()

c_schema_key(T) = k(T, _COLLECTION_KEY_CTX)
c_ref_for(T) = "#/\$defs/$(c_schema_key(T))"
c_def(defs, T) = defs[c_schema_key(T)]

@testset "Collection schema generation" begin
    ctx = SchemaContext()
    result = generate_schema(CollectionRecord; ctx = ctx, simplify = false)
    defs = result.doc["\$defs"]
    schema = c_def(defs, CollectionRecord)
    props = schema["properties"]

    @test props["ints"]["\$ref"] == c_ref_for(Vector{Int64})
    vector_def = c_def(defs, Vector{Int64})
    @test vector_def["type"] == "array"
    @test vector_def["items"]["\$ref"] == c_ref_for(Int64)

    @test props["nested"]["\$ref"] == c_ref_for(Vector{Vector{Float64}})
    nested_def = c_def(defs, Vector{Vector{Float64}})
    @test nested_def["items"]["\$ref"] == c_ref_for(Vector{Float64})

    @test props["tags"]["\$ref"] == c_ref_for(Set{String})
    set_def = c_def(defs, Set{String})
    @test set_def["uniqueItems"] == true
    @test set_def["items"]["\$ref"] == c_ref_for(String)

    @test props["pair"]["\$ref"] == c_ref_for(Tuple{String, Int64})
    tuple_schema = c_def(defs, Tuple{String, Int64})
    @test tuple_schema["type"] == "array"
    @test tuple_schema["minItems"] == 2
    @test tuple_schema["maxItems"] == 2
    refs = [entry["\$ref"] for entry in tuple_schema["prefixItems"]]
    @test refs == [c_ref_for(String), c_ref_for(Int64)]

    @test props["coords"]["\$ref"] == c_ref_for(NamedTuple{(:lat, :lon), Tuple{Float64, Float64}})
    namedtuple_def = c_def(defs, NamedTuple{(:lat, :lon), Tuple{Float64, Float64}})
    @test namedtuple_def["type"] == "object"
    @test namedtuple_def["required"] == ["lat", "lon"]
    @test namedtuple_def["properties"]["lat"]["\$ref"] == c_ref_for(Float64)

    @test props["metadata"]["\$ref"] == c_ref_for(Dict{String, Vector{Int64}})
    dict_def = c_def(defs, Dict{String, Vector{Int64}})
    @test dict_def["type"] == "object"
    @test dict_def["additionalProperties"]["\$ref"] == c_ref_for(Vector{Int64})

    @test props["samples"]["\$ref"] == c_ref_for(NTuple{3, Float64})
    ntuple_def = c_def(defs, NTuple{3, Float64})
    @test ntuple_def["type"] == "array"
    @test ntuple_def["items"]["\$ref"] == c_ref_for(Float64)
    @test ntuple_def["minItems"] == 3
    @test ntuple_def["maxItems"] == 3
end


struct CollectionRecord2
    strings::Vector{String}
    bools::Vector{Bool}
    floats::Vector{Float32}
end

@testset "Vector types" begin
    ctx = SchemaContext()
    result = generate_schema(CollectionRecord2; ctx = ctx, simplify = false)
    defs = result.doc["\$defs"]
    schema = c_def(defs, CollectionRecord2)
    props = schema["properties"]

    @test props["strings"]["\$ref"] == c_ref_for(Vector{String})
    vector_string_def = c_def(defs, Vector{String})
    @test vector_string_def["type"] == "array"
    @test vector_string_def["items"]["\$ref"] == c_ref_for(String)

    @test props["bools"]["\$ref"] == c_ref_for(Vector{Bool})
    vector_bool_def = c_def(defs, Vector{Bool})
    @test vector_bool_def["type"] == "array"
    @test vector_bool_def["items"]["\$ref"] == c_ref_for(Bool)

    @test props["floats"]["\$ref"] == c_ref_for(Vector{Float32})
    vector_float_def = c_def(defs, Vector{Float32})
    @test vector_float_def["type"] == "array"
    @test vector_float_def["items"]["\$ref"] == c_ref_for(Float32)
end

struct NestedCollections
    matrix::Vector{Vector{Int}}
    cube::Vector{Vector{Vector{Float64}}}
end

@testset "Deeply nested collections" begin
    ctx = SchemaContext()
    result = generate_schema(NestedCollections; ctx = ctx, simplify = false)
    defs = result.doc["\$defs"]
    schema = c_def(defs, NestedCollections)
    props = schema["properties"]

    @test props["matrix"]["\$ref"] == c_ref_for(Vector{Vector{Int}})
    matrix_def = c_def(defs, Vector{Vector{Int}})
    @test matrix_def["items"]["\$ref"] == c_ref_for(Vector{Int})

    @test props["cube"]["\$ref"] == c_ref_for(Vector{Vector{Vector{Float64}}})
    cube_def = c_def(defs, Vector{Vector{Vector{Float64}}})
    @test cube_def["items"]["\$ref"] == c_ref_for(Vector{Vector{Float64}})
end

struct SetCollections
    ids::Set{Int}
    codes::Set{String}
    flags::Set{Bool}
end

@testset "Multiple Set types" begin
    ctx = SchemaContext()
    result = generate_schema(SetCollections; ctx = ctx, simplify = false)
    defs = result.doc["\$defs"]
    schema = c_def(defs, SetCollections)
    props = schema["properties"]

    @test props["ids"]["\$ref"] == c_ref_for(Set{Int})
    set_int_def = c_def(defs, Set{Int})
    @test set_int_def["uniqueItems"] == true
    @test set_int_def["items"]["\$ref"] == c_ref_for(Int)

    @test props["codes"]["\$ref"] == c_ref_for(Set{String})
    set_string_def = c_def(defs, Set{String})
    @test set_string_def["uniqueItems"] == true
    @test set_string_def["items"]["\$ref"] == c_ref_for(String)

    @test props["flags"]["\$ref"] == c_ref_for(Set{Bool})
    set_bool_def = c_def(defs, Set{Bool})
    @test set_bool_def["uniqueItems"] == true
    @test set_bool_def["items"]["\$ref"] == c_ref_for(Bool)
end

struct TupleVariations
    pair1::Tuple{Int, String}
    pair2::Tuple{Float64, Bool}
    triple::Tuple{String, Int, Float64}
    quad::Tuple{Int, Int, Int, Int}
end

@testset "Various Tuple types" begin
    ctx = SchemaContext()
    result = generate_schema(TupleVariations; ctx = ctx, simplify = false)
    defs = result.doc["\$defs"]
    schema = c_def(defs, TupleVariations)
    props = schema["properties"]

    @test props["pair1"]["\$ref"] == c_ref_for(Tuple{Int, String})
    pair1_schema = c_def(defs, Tuple{Int, String})
    @test pair1_schema["type"] == "array"
    @test pair1_schema["minItems"] == 2
    @test pair1_schema["maxItems"] == 2
    refs1 = [entry["\$ref"] for entry in pair1_schema["prefixItems"]]
    @test refs1 == [c_ref_for(Int), c_ref_for(String)]

    @test props["pair2"]["\$ref"] == c_ref_for(Tuple{Float64, Bool})
    pair2_schema = c_def(defs, Tuple{Float64, Bool})
    @test pair2_schema["minItems"] == 2
    @test pair2_schema["maxItems"] == 2
    refs2 = [entry["\$ref"] for entry in pair2_schema["prefixItems"]]
    @test refs2 == [c_ref_for(Float64), c_ref_for(Bool)]

    @test props["triple"]["\$ref"] == c_ref_for(Tuple{String, Int, Float64})
    triple_schema = c_def(defs, Tuple{String, Int, Float64})
    @test triple_schema["minItems"] == 3
    @test triple_schema["maxItems"] == 3
    refs3 = [entry["\$ref"] for entry in triple_schema["prefixItems"]]
    @test refs3 == [c_ref_for(String), c_ref_for(Int), c_ref_for(Float64)]

    @test props["quad"]["\$ref"] == c_ref_for(Tuple{Int, Int, Int, Int})
    quad_schema = c_def(defs, Tuple{Int, Int, Int, Int})
    @test quad_schema["type"] == "array"
    @test quad_schema["items"]["\$ref"] == c_ref_for(Int)
    @test quad_schema["minItems"] == 4
    @test quad_schema["maxItems"] == 4
end

struct NamedTupleVariations
    point2d::NamedTuple{(:x, :y), Tuple{Float64, Float64}}
    point3d::NamedTuple{(:x, :y, :z), Tuple{Float64, Float64, Float64}}
    person::NamedTuple{(:name, :age), Tuple{String, Int}}
end

@testset "Various NamedTuple types" begin
    ctx = SchemaContext()
    result = generate_schema(NamedTupleVariations; ctx = ctx, simplify = false)
    defs = result.doc["\$defs"]
    schema = c_def(defs, NamedTupleVariations)
    props = schema["properties"]

    @test props["point2d"]["\$ref"] == c_ref_for(NamedTuple{(:x, :y), Tuple{Float64, Float64}})
    point2d_def = c_def(defs, NamedTuple{(:x, :y), Tuple{Float64, Float64}})
    @test point2d_def["type"] == "object"
    @test point2d_def["required"] == ["x", "y"]
    @test point2d_def["properties"]["x"]["\$ref"] == c_ref_for(Float64)
    @test point2d_def["properties"]["y"]["\$ref"] == c_ref_for(Float64)

    @test props["point3d"]["\$ref"] == c_ref_for(NamedTuple{(:x, :y, :z), Tuple{Float64, Float64, Float64}})
    point3d_def = c_def(defs, NamedTuple{(:x, :y, :z), Tuple{Float64, Float64, Float64}})
    @test point3d_def["required"] == ["x", "y", "z"]
    @test point3d_def["properties"]["z"]["\$ref"] == c_ref_for(Float64)

    @test props["person"]["\$ref"] == c_ref_for(NamedTuple{(:name, :age), Tuple{String, Int}})
    person_def = c_def(defs, NamedTuple{(:name, :age), Tuple{String, Int}})
    @test person_def["required"] == ["name", "age"]
    @test person_def["properties"]["name"]["\$ref"] == c_ref_for(String)
    @test person_def["properties"]["age"]["\$ref"] == c_ref_for(Int)
end

struct DictVariations
    str_to_int::Dict{String, Int}
    str_to_bool::Dict{String, Bool}
    str_to_float::Dict{String, Float64}
end

@testset "Various Dict types" begin
    ctx = SchemaContext()
    result = generate_schema(DictVariations; ctx = ctx, simplify = false)
    defs = result.doc["\$defs"]
    schema = c_def(defs, DictVariations)
    props = schema["properties"]

    @test props["str_to_int"]["\$ref"] == c_ref_for(Dict{String, Int})
    dict_int_def = c_def(defs, Dict{String, Int})
    @test dict_int_def["type"] == "object"
    @test dict_int_def["additionalProperties"]["\$ref"] == c_ref_for(Int)

    @test props["str_to_bool"]["\$ref"] == c_ref_for(Dict{String, Bool})
    dict_bool_def = c_def(defs, Dict{String, Bool})
    @test dict_bool_def["additionalProperties"]["\$ref"] == c_ref_for(Bool)

    @test props["str_to_float"]["\$ref"] == c_ref_for(Dict{String, Float64})
    dict_float_def = c_def(defs, Dict{String, Float64})
    @test dict_float_def["additionalProperties"]["\$ref"] == c_ref_for(Float64)
end

struct NTupleVariations
    pair::NTuple{2, Int}
    quad::NTuple{4, String}
    five::NTuple{5, Bool}
end

@testset "Various NTuple types" begin
    ctx = SchemaContext()
    result = generate_schema(NTupleVariations; ctx = ctx, simplify = false)
    defs = result.doc["\$defs"]
    schema = c_def(defs, NTupleVariations)
    props = schema["properties"]

    @test props["pair"]["\$ref"] == c_ref_for(NTuple{2, Int})
    pair_def = c_def(defs, NTuple{2, Int})
    @test pair_def["type"] == "array"
    @test pair_def["items"]["\$ref"] == c_ref_for(Int)
    @test pair_def["minItems"] == 2
    @test pair_def["maxItems"] == 2

    @test props["quad"]["\$ref"] == c_ref_for(NTuple{4, String})
    quad_def = c_def(defs, NTuple{4, String})
    @test quad_def["items"]["\$ref"] == c_ref_for(String)
    @test quad_def["minItems"] == 4
    @test quad_def["maxItems"] == 4

    @test props["five"]["\$ref"] == c_ref_for(NTuple{5, Bool})
    five_def = c_def(defs, NTuple{5, Bool})
    @test five_def["items"]["\$ref"] == c_ref_for(Bool)
    @test five_def["minItems"] == 5
    @test five_def["maxItems"] == 5
end

struct ComplexNestedCollections
    nested_dict::Dict{String, Vector{Int}}
    dict_of_tuples::Dict{String, Tuple{Int, String}}
    vector_of_sets::Vector{Set{String}}
end

@testset "Complex nested collection combinations" begin
    ctx = SchemaContext()
    result = generate_schema(ComplexNestedCollections; ctx = ctx, simplify = false)
    defs = result.doc["\$defs"]
    schema = c_def(defs, ComplexNestedCollections)
    props = schema["properties"]

    @test props["nested_dict"]["\$ref"] == c_ref_for(Dict{String, Vector{Int}})
    nested_dict_def = c_def(defs, Dict{String, Vector{Int}})
    @test nested_dict_def["type"] == "object"
    @test nested_dict_def["additionalProperties"]["\$ref"] == c_ref_for(Vector{Int})

    @test props["dict_of_tuples"]["\$ref"] == c_ref_for(Dict{String, Tuple{Int, String}})
    dict_tuples_def = c_def(defs, Dict{String, Tuple{Int, String}})
    @test dict_tuples_def["additionalProperties"]["\$ref"] == c_ref_for(Tuple{Int, String})

    @test props["vector_of_sets"]["\$ref"] == c_ref_for(Vector{Set{String}})
    vec_sets_def = c_def(defs, Vector{Set{String}})
    @test vec_sets_def["items"]["\$ref"] == c_ref_for(Set{String})
end

struct MixedCollections
    ints1::Vector{Int32}
    ints2::Vector{Int64}
    ints3::Vector{Int8}
    uints::Vector{UInt64}
end

@testset "Collections of different integer types" begin
    ctx = SchemaContext()
    result = generate_schema(MixedCollections; ctx = ctx, simplify = false)
    defs = result.doc["\$defs"]
    schema = c_def(defs, MixedCollections)
    props = schema["properties"]

    @test props["ints1"]["\$ref"] == c_ref_for(Vector{Int32})
    @test props["ints2"]["\$ref"] == c_ref_for(Vector{Int64})
    @test props["ints3"]["\$ref"] == c_ref_for(Vector{Int8})
    @test props["uints"]["\$ref"] == c_ref_for(Vector{UInt64})
end

struct LargeNTuples
    ten::NTuple{10, Float64}
    twenty::NTuple{20, Int}
end

@testset "Large NTuple types" begin
    ctx = SchemaContext()
    result = generate_schema(LargeNTuples; ctx = ctx, simplify = false)
    defs = result.doc["\$defs"]
    schema = c_def(defs, LargeNTuples)
    props = schema["properties"]

    @test props["ten"]["\$ref"] == c_ref_for(NTuple{10, Float64})
    ten_def = c_def(defs, NTuple{10, Float64})
    @test ten_def["type"] == "array"
    @test ten_def["items"]["\$ref"] == c_ref_for(Float64)
    @test ten_def["minItems"] == 10
    @test ten_def["maxItems"] == 10

    @test props["twenty"]["\$ref"] == c_ref_for(NTuple{20, Int})
    twenty_def = c_def(defs, NTuple{20, Int})
    @test twenty_def["type"] == "array"
    @test twenty_def["items"]["\$ref"] == c_ref_for(Int)
    @test twenty_def["minItems"] == 20
    @test twenty_def["maxItems"] == 20
end
