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

struct EmptyTupleRecord
    empty::Tuple{}
end

const _COLLECTION_KEY_CTX = SchemaContext()

c_schema_key(T) = k(T, _COLLECTION_KEY_CTX)
c_ref_for(T) = "#/\$defs/$(c_schema_key(T))"
c_def(defs, T) = defs[c_schema_key(T)]

@testset "Collection schema generation" begin
    ctx = SchemaContext()
    result = generate_schema(CollectionRecord; ctx=ctx)
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
end

@testset "Empty tuple schema" begin
    ctx = SchemaContext()
    result = generate_schema(EmptyTupleRecord; ctx=ctx)
    defs = result.doc["\$defs"]
    tuple_def = c_def(defs, Tuple{})

    @test tuple_def["type"] == "array"
    @test tuple_def["minItems"] == 0
    @test tuple_def["maxItems"] == 0
end
