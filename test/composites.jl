using Test
using Struct2JSONSchema: SchemaContext, generate_schema, register_abstract!, k

struct OptionalProfile
    name::String
    nickname::Union{Nothing, String}
end

struct FlexibleUnion
    value::Union{String, Int64, Float64}
end

struct SuccessPayload
    message::String
end

struct ErrorPayload
    code::Int64
end

struct ApiResponse
    result::Union{SuccessPayload, ErrorPayload}
end

struct RecursiveNode
    value::Int64
    next::Union{RecursiveNode, Nothing}
end

@enum WorkflowState begin
    awaiting
    running
    done
end

struct Workflow
    state::WorkflowState
end

abstract type AnimalKind end
struct DogKind <: AnimalKind
    name::String
end

struct CatKind <: AnimalKind
    indoor::Bool
end

struct Shelter
    resident::AnimalKind
end

struct Handler
    callback::Function
end

const _COMPOSITES_KEY_CTX = SchemaContext()
comp_key(T) = k(T, _COMPOSITES_KEY_CTX)
comp_ref(T) = "#/\$defs/$(comp_key(T))"
comp_def(defs, T) = defs[comp_key(T)]

function resolve_anyof(entry, defs)::Vector
    schema = entry
    while haskey(schema, "\$ref")
        key = split(schema["\$ref"], '/')[end]
        schema = defs[key]
    end
    return schema["anyOf"]
end

@testset "Union handling" begin
    ctx = SchemaContext()
    profile = generate_schema(OptionalProfile; ctx = ctx)
    defs = profile.doc["\$defs"]
    profile_schema = comp_def(defs, OptionalProfile)
    nickname = resolve_anyof(profile_schema["properties"]["nickname"], defs)
    @test length(nickname) == 2
    @test Set(entry["\$ref"] for entry in nickname) == Set([comp_ref(Nothing), comp_ref(String)])

    union = generate_schema(FlexibleUnion; ctx = SchemaContext())
    union_defs = union.doc["\$defs"]
    union_schema = comp_def(union_defs, FlexibleUnion)
    value_anyof = resolve_anyof(union_schema["properties"]["value"], union_defs)
    @test length(value_anyof) == 3
    @test Set(entry["\$ref"] for entry in value_anyof) == Set([comp_ref(String), comp_ref(Int64), comp_ref(Float64)])
    api = generate_schema(ApiResponse; ctx = SchemaContext())
    api_defs = api.doc["\$defs"]
    api_schema = comp_def(api_defs, ApiResponse)
    payloads = resolve_anyof(api_schema["properties"]["result"], api_defs)
    @test Set(entry["\$ref"] for entry in payloads) == Set([comp_ref(SuccessPayload), comp_ref(ErrorPayload)])
end

@testset "Recursive and enum schemas" begin
    ctx = SchemaContext()
    node_result = generate_schema(RecursiveNode; ctx = ctx)
    defs = node_result.doc["\$defs"]
    node_schema = comp_def(defs, RecursiveNode)
    next_anyof = resolve_anyof(node_schema["properties"]["next"], defs)
    @test Set(entry["\$ref"] for entry in next_anyof) == Set([comp_ref(Nothing), comp_ref(RecursiveNode)])

    workflow = generate_schema(Workflow; ctx = SchemaContext())
    enum_def = comp_def(workflow.doc["\$defs"], WorkflowState)
    @test enum_def["enum"] == ["awaiting", "running", "done"]
end

@testset "Abstract discriminator" begin
    ctx = SchemaContext()
    register_abstract!(
        ctx, AnimalKind;
        variants = [DogKind, CatKind],
        discr_key = "kind",
        tag_value = Dict(DogKind => "dog", CatKind => "cat"),
        require_discr = true
    )
    shelter = generate_schema(Shelter; ctx = ctx)
    defs = shelter.doc["\$defs"]
    shelter_schema = comp_def(defs, Shelter)
    @test shelter_schema["properties"]["resident"]["\$ref"] == comp_ref(AnimalKind)

    abstract_def = comp_def(defs, AnimalKind)
    @test length(abstract_def["anyOf"]) == 2
    for (variant, tag) in zip([DogKind, CatKind], ["dog", "cat"])
        match = nothing
        for option in abstract_def["anyOf"]
            if option["allOf"][1]["\$ref"] == comp_ref(variant)
                match = option
                break
            end
        end
        @test match !== nothing
        constraint = match["allOf"][2]
        @test constraint["properties"]["kind"]["const"] == tag
        @test constraint["required"] == ["kind"]
    end
end

@testset "Function fields" begin
    ctx = SchemaContext()
    result = generate_schema(Handler; ctx = ctx)
    defs = result.doc["\$defs"]
    handler_schema = comp_def(defs, Handler)

    @test handler_schema["properties"]["callback"]["\$ref"] == comp_ref(Function)
    @test isempty(comp_def(defs, Function))
    @test result.unknowns == Set([(Function, (:callback,))])
end
