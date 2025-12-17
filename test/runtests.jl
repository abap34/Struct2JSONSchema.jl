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


@testset "end to end" begin
    include("end_to_end.jl")
end

@testset "optional fields" begin
    include("optional_fields.jl")
end

@testset "field overrides" begin
    include("field_overrides.jl")
end

if success(`python3 --version`)
    @testset "python validator" begin
        include("pyvalidtest.jl")
    end
else
    @warn "python3 not found, skipping Python validator tests"
end
