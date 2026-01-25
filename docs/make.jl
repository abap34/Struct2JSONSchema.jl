using Documenter
using Struct2JSONSchema

makedocs(
    sitename = "Struct2JSONSchema.jl",
    format = Documenter.HTML(
        prettyurls = get(ENV, "CI", nothing) == "true",
        canonical = "https://abap34.github.io/Struct2JSONSchema.jl",
        edit_link = "main",
        assets = String[],
    ),
    modules = [Struct2JSONSchema],
    pages = [
        "Home" => "index.md",
        "User Guide" => "guide.md",
        "Reference" => "reference.md",
        "API Reference" => "api.md",
    ],
)

deploydocs(
    repo = "github.com/abap34/Struct2JSONSchema.jl.git",
    devbranch = "main",
)
