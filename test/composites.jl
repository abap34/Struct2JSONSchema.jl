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

struct OptionalProfile2
    name::String
    age::Union{Int, Nothing}
    email::Union{String, Nothing}
end

@testset "Union handling - multiple optional fields" begin
    ctx = SchemaContext()
    profile = generate_schema(OptionalProfile2; ctx = ctx)
    defs = profile.doc["\$defs"]
    profile_schema = comp_def(defs, OptionalProfile2)

    age_anyof = resolve_anyof(profile_schema["properties"]["age"], defs)
    @test length(age_anyof) == 2
    @test Set(entry["\$ref"] for entry in age_anyof) == Set([comp_ref(Nothing), comp_ref(Int)])

    email_anyof = resolve_anyof(profile_schema["properties"]["email"], defs)
    @test length(email_anyof) == 2
    @test Set(entry["\$ref"] for entry in email_anyof) == Set([comp_ref(Nothing), comp_ref(String)])
end

struct FlexibleUnion2
    value::Union{Bool, String, Float64}
end

@testset "Union handling - bool, string, float" begin
    union = generate_schema(FlexibleUnion2; ctx = SchemaContext())
    union_defs = union.doc["\$defs"]
    union_schema = comp_def(union_defs, FlexibleUnion2)
    value_anyof = resolve_anyof(union_schema["properties"]["value"], union_defs)
    @test length(value_anyof) == 3
    @test Set(entry["\$ref"] for entry in value_anyof) == Set([comp_ref(Bool), comp_ref(String), comp_ref(Float64)])
end

struct FlexibleUnion3
    value::Union{Int32, Int64, UInt32}
end

@testset "Union handling - multiple integer types" begin
    union = generate_schema(FlexibleUnion3; ctx = SchemaContext())
    union_defs = union.doc["\$defs"]
    union_schema = comp_def(union_defs, FlexibleUnion3)
    value_anyof = resolve_anyof(union_schema["properties"]["value"], union_defs)
    @test length(value_anyof) == 3
    @test Set(entry["\$ref"] for entry in value_anyof) == Set([comp_ref(Int32), comp_ref(Int64), comp_ref(UInt32)])
end

struct WarningPayload
    severity::String
end

struct InfoPayload
    details::String
end

struct LogEntry
    entry::Union{WarningPayload, InfoPayload}
end

@testset "Union handling - different payload types" begin
    log = generate_schema(LogEntry; ctx = SchemaContext())
    log_defs = log.doc["\$defs"]
    log_schema = comp_def(log_defs, LogEntry)
    payloads = resolve_anyof(log_schema["properties"]["entry"], log_defs)
    @test Set(entry["\$ref"] for entry in payloads) == Set([comp_ref(WarningPayload), comp_ref(InfoPayload)])
end

struct TreeNode
    value::String
    left::Union{TreeNode, Nothing}
    right::Union{TreeNode, Nothing}
end

@testset "recursive schemas - binary tree" begin
    ctx = SchemaContext()
    tree_result = generate_schema(TreeNode; ctx = ctx)
    defs = tree_result.doc["\$defs"]
    tree_schema = comp_def(defs, TreeNode)

    left_anyof = resolve_anyof(tree_schema["properties"]["left"], defs)
    @test Set(entry["\$ref"] for entry in left_anyof) == Set([comp_ref(Nothing), comp_ref(TreeNode)])

    right_anyof = resolve_anyof(tree_schema["properties"]["right"], defs)
    @test Set(entry["\$ref"] for entry in right_anyof) == Set([comp_ref(Nothing), comp_ref(TreeNode)])
end

struct LinkedListNode
    data::Int
    next::Union{LinkedListNode, Nothing}
end

@testset "recursive schemas - linked list" begin
    ctx = SchemaContext()
    list_result = generate_schema(LinkedListNode; ctx = ctx)
    defs = list_result.doc["\$defs"]
    list_schema = comp_def(defs, LinkedListNode)
    next_anyof = resolve_anyof(list_schema["properties"]["next"], defs)
    @test Set(entry["\$ref"] for entry in next_anyof) == Set([comp_ref(Nothing), comp_ref(LinkedListNode)])
end

@enum Color begin
    red
    green
    blue
end

struct ColoredItem
    color::Color
end

@testset "enum schemas - Color" begin
    item = generate_schema(ColoredItem; ctx = SchemaContext())
    enum_def = comp_def(item.doc["\$defs"], Color)
    @test enum_def["enum"] == ["red", "green", "blue"]
end

@enum Priority begin
    low
    medium
    high
    urgent
end

struct Task
    priority::Priority
end

@testset "enum schemas - Priority" begin
    task = generate_schema(Task; ctx = SchemaContext())
    enum_def = comp_def(task.doc["\$defs"], Priority)
    @test enum_def["enum"] == ["low", "medium", "high", "urgent"]
end

@enum Status begin
    active
    inactive
    pending
    archived
end

struct Record
    status::Status
end

@testset "enum schemas - Status" begin
    record = generate_schema(Record; ctx = SchemaContext())
    enum_def = comp_def(record.doc["\$defs"], Status)
    @test enum_def["enum"] == ["active", "inactive", "pending", "archived"]
end

abstract type Vehicle end
struct Car <: Vehicle
    doors::Int
end

struct Motorcycle <: Vehicle
    has_sidecar::Bool
end

struct Garage
    vehicle::Vehicle
end

@testset "abstract discriminator - Vehicle types" begin
    ctx = SchemaContext()
    register_abstract!(
        ctx, Vehicle;
        variants = [Car, Motorcycle],
        discr_key = "type",
        tag_value = Dict(Car => "car", Motorcycle => "motorcycle"),
        require_discr = true
    )
    garage = generate_schema(Garage; ctx = ctx)
    defs = garage.doc["\$defs"]
    garage_schema = comp_def(defs, Garage)
    @test garage_schema["properties"]["vehicle"]["\$ref"] == comp_ref(Vehicle)

    abstract_def = comp_def(defs, Vehicle)
    @test length(abstract_def["anyOf"]) == 2
    for (variant, tag) in zip([Car, Motorcycle], ["car", "motorcycle"])
        match = nothing
        for option in abstract_def["anyOf"]
            if option["allOf"][1]["\$ref"] == comp_ref(variant)
                match = option
                break
            end
        end
        @test match !== nothing
        constraint = match["allOf"][2]
        @test constraint["properties"]["type"]["const"] == tag
        @test constraint["required"] == ["type"]
    end
end

abstract type Shape end
struct Circle <: Shape
    radius::Float64
end

struct Square <: Shape
    side::Float64
end

struct Triangle <: Shape
    base::Float64
    height::Float64
end

struct Drawing
    shape::Shape
end

@testset "abstract discriminator - Shape types" begin
    ctx = SchemaContext()
    register_abstract!(
        ctx, Shape;
        variants = [Circle, Square, Triangle],
        discr_key = "shape_type",
        tag_value = Dict(Circle => "circle", Square => "square", Triangle => "triangle"),
        require_discr = true
    )
    drawing = generate_schema(Drawing; ctx = ctx)
    defs = drawing.doc["\$defs"]
    drawing_schema = comp_def(defs, Drawing)
    @test drawing_schema["properties"]["shape"]["\$ref"] == comp_ref(Shape)

    abstract_def = comp_def(defs, Shape)
    @test length(abstract_def["anyOf"]) == 3
    for (variant, tag) in zip([Circle, Square, Triangle], ["circle", "square", "triangle"])
        match = nothing
        for option in abstract_def["anyOf"]
            if option["allOf"][1]["\$ref"] == comp_ref(variant)
                match = option
                break
            end
        end
        @test match !== nothing
        constraint = match["allOf"][2]
        @test constraint["properties"]["shape_type"]["const"] == tag
        @test constraint["required"] == ["shape_type"]
    end
end

struct EventHandler
    on_click::Function
    on_hover::Function
end

@testset "Function fields - multiple handlers" begin
    ctx = SchemaContext()
    result = generate_schema(EventHandler; ctx = ctx)
    defs = result.doc["\$defs"]
    handler_schema = comp_def(defs, EventHandler)

    @test handler_schema["properties"]["on_click"]["\$ref"] == comp_ref(Function)
    @test handler_schema["properties"]["on_hover"]["\$ref"] == comp_ref(Function)
    @test isempty(comp_def(defs, Function))
    @test result.unknowns == Set([(Function, (:on_click,))])
end

struct Processor
    transform::Function
end

@testset "Function fields - processor" begin
    ctx = SchemaContext()
    result = generate_schema(Processor; ctx = ctx)
    defs = result.doc["\$defs"]
    processor_schema = comp_def(defs, Processor)

    @test processor_schema["properties"]["transform"]["\$ref"] == comp_ref(Function)
    @test isempty(comp_def(defs, Function))
    @test result.unknowns == Set([(Function, (:transform,))])
end

struct ComplexUnion
    value::Union{String, Int, Float64, Bool, Nothing}
end

@testset "Complex Union handling - five types" begin
    ctx = SchemaContext()
    complex = generate_schema(ComplexUnion; ctx = ctx)
    defs = complex.doc["\$defs"]
    complex_schema = comp_def(defs, ComplexUnion)
    value_anyof = resolve_anyof(complex_schema["properties"]["value"], defs)
    @test length(value_anyof) == 5
    @test Set(entry["\$ref"] for entry in value_anyof) == Set([
        comp_ref(String), comp_ref(Int), comp_ref(Float64), comp_ref(Bool), comp_ref(Nothing)
    ])
end
