using Struct2JSONSchema
using Test
using Dates


@testset "primitive" begin
    include("primitives.jl")
end

@testset "collections" begin
    include("collections.jl")
end

@testset "composite" begin
    include("composites.jl")
end

@testset "context and overrides" begin
    include("context_and_overrides.jl")
end

@testset "API behaviors" begin
    include("api_behaviors.jl")
end

@testset "doc structure" begin
    include("doc_structure.jl")
end

@testset "edge cases" begin
    include("edge_cases.jl")
end


@testset "end to end" begin
    include("end_to_end.jl")
end

@testset "optional fields" begin
    include("optional_fields.jl")
end

@testset "field overrides" begin
    include("field_overrides.jl")
end

@testset "error handling" begin
    include("error_handling.jl")
end

@testset "simplification" begin
    include("simplification.jl")
end

@testset "field descriptions" begin
    include("field_descriptions.jl")
end

@testset "skip fields" begin
    include("skip_fields.jl")
end

@testset "default values" begin
    include("default_values.jl")
end

py_exec = Sys.which("python3") !== nothing ? "python3" : Sys.which("python") !== nothing ? "python" : nothing

if py_exec !== nothing
    @testset "python validator" begin
        include("pyvalidtest.jl")
    end
else
    @warn "Python executable not found; skipping python validator tests"
end
