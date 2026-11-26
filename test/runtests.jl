using Struct2JSONSchema
using Test
using Dates

include("find_python_validator.jl")

@testset "Struct2JSONSchema" begin
    @testset "primitive" include("primitives.jl")

    @testset "collections" include("collections.jl")

    @testset "composite" include("composites.jl")

    @testset "context and overrides" include("context_and_overrides.jl")

    @testset "API behaviors" include("api_behaviors.jl")

    @testset "doc structure" include("doc_structure.jl")

    @testset "edge cases" include("edge_cases.jl")

    @testset "end to end" include("end_to_end.jl")

    @testset "optional fields" include("optional_fields.jl")

    @testset "field overrides" include("field_overrides.jl")

    @testset "error handling" include("error_handling.jl")

    @testset "simplification" include("simplification.jl")

    @testset "expand_all_defs" include("expand_all_defs.jl")

    @testset "field descriptions" include("field_descriptions.jl")

    @testset "skip fields" include("skip_fields.jl")

    @testset "default values" include("default_values.jl")

    @testset "JavaScript compatibility" include("javascript_compatibility.jl")

    if isempty(find_python_validator())
        if get(ENV, "CI", "") == "true"
            error("Python with jsonschema is required in CI. Run `python3 -m pip install jsonschema`.")
        end
        @warn "Python with jsonschema not found; skipping python validator tests" install =
            "python3 -m pip install jsonschema"
    else
        @testset "python validator" include("pyvalidtest.jl")
    end
end
