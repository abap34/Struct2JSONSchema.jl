using Test
using Struct2JSONSchema: JavaScriptCompatibilityError, SchemaContext,
    defaultvalue!, defaultvalue_serializer!, generate_schema, k,
    normalize_javascript_value, override_abstract!, override_type!

const _JS_COMPAT_KEY_CTX = SchemaContext()
js_compat_key(T) = k(T, _JS_COMPAT_KEY_CTX)

function get_compatibility_error(f::Function)
    try
        f()
    catch err
        @test err isa JavaScriptCompatibilityError
        return err
    end
    @test false
    return nothing
end

struct JSCompatNumbers
    safe_integer::Int64
    unsigned_integer::UInt32
    float16::Float16
    float32::Float32
    fractional::Float64
    whole::Float64
    large_whole::Float64
    negative_zero::Float64
    boolean::Bool
    bigfloat::BigFloat
    rational::Rational{Int}
end

@testset "JavaScript-compatible number normalization" begin
    ctx = SchemaContext(javascript_safe_numbers = true)
    value = JSCompatNumbers(
        9_007_199_254_740_991,
        typemax(UInt32),
        Float16(0.1),
        Float32(0.1),
        1.0e-6,
        2.0,
        2.0^53,
        -0.0,
        true,
        BigFloat(0.5),
        1 // 2
    )
    defaultvalue!(ctx, value)

    result = generate_schema(JSCompatNumbers; ctx = ctx, simplify = false)
    props = result.doc["\$defs"][js_compat_key(JSCompatNumbers)]["properties"]

    @test props["safe_integer"]["default"] === Int64(9_007_199_254_740_991)
    @test props["unsigned_integer"]["default"] === Int64(typemax(UInt32))
    @test props["float16"]["default"] === Float64(Float16(0.1))
    @test props["float32"]["default"] === Float64(Float32(0.1))
    @test props["fractional"]["default"] === 1.0e-6
    @test props["whole"]["default"] === Int64(2)
    @test props["large_whole"]["default"] === Float64(2.0^53)
    @test props["negative_zero"]["default"] === Int64(0)
    @test props["boolean"]["default"] === true
    @test props["bigfloat"]["default"] === 0.5
    @test props["rational"]["default"] === 0.5
end

struct JSCompatDefault{T}
    value::T
end

function generate_js_default(value)
    T = JSCompatDefault{typeof(value)}
    ctx = SchemaContext(javascript_safe_numbers = true)
    defaultvalue!(ctx, T(value))
    return generate_schema(T; ctx = ctx, simplify = false)
end

@testset "JavaScript-incompatible defaults" begin
    for value in (
            Int64(9_007_199_254_740_992),
            UInt64(9_007_199_254_740_992),
            big"9007199254740992"
        )
        err = get_compatibility_error() do
            generate_js_default(value)
        end
        @test occursin("/properties/value/default", err.path)
        @test occursin("safe integer range", err.reason)
    end

    for value in (NaN, Inf, -Inf)
        err = get_compatibility_error() do
            generate_js_default(value)
        end
        @test occursin("non-finite", err.reason)
    end

    exact_bigfloat = setprecision(256) do
        BigFloat(0.1)
    end
    exact_result = setprecision(24) do
        generate_js_default(exact_bigfloat)
    end
    exact_type = JSCompatDefault{BigFloat}
    exact_props = exact_result.doc["\$defs"][js_compat_key(exact_type)]["properties"]
    @test exact_props["value"]["default"] === 0.1

    inexact_bigfloat = setprecision(256) do
        BigFloat("0.1")
    end
    err = get_compatibility_error() do
        generate_js_default(inexact_bigfloat)
    end
    @test occursin("BigFloat", err.reason)

    err = get_compatibility_error() do
        generate_js_default(1 // 10)
    end
    @test occursin("rational", err.reason)
end

struct JSCompatCustomDefault
    value::String
end

@testset "Custom serializer results are checked recursively" begin
    ctx = SchemaContext(javascript_safe_numbers = true)
    defaultvalue_serializer!(ctx) do field_type, _value, _ctx
        field_type === String || return nothing
        return Any[1, Int64(9_007_199_254_740_992)]
    end
    defaultvalue!(ctx, JSCompatCustomDefault("value"))

    err = get_compatibility_error() do
        generate_schema(JSCompatCustomDefault; ctx = ctx, simplify = false)
    end
    @test endswith(err.path, "/properties/value/default/1")
end

struct JSCompatOverride end

@testset "Override results use the selected number profile" begin
    unsafe = Int64(9_007_199_254_740_992)

    native_ctx = SchemaContext()
    override_type!(native_ctx, JSCompatOverride) do _ctx
        Dict("type" => "integer", "minimum" => unsafe)
    end
    native = generate_schema(JSCompatOverride; ctx = native_ctx, simplify = false)
    native_def = native.doc["\$defs"][js_compat_key(JSCompatOverride)]
    @test native_def["minimum"] === unsafe

    js_ctx = SchemaContext(javascript_safe_numbers = true)
    override_type!(js_ctx, JSCompatOverride) do _ctx
        Dict("type" => "integer", "minimum" => unsafe)
    end
    err = get_compatibility_error() do
        generate_schema(JSCompatOverride; ctx = js_ctx, simplify = false)
    end
    @test endswith(err.path, "/minimum")

    cycle = Any[]
    push!(cycle, cycle)
    cycle_ctx = SchemaContext(javascript_safe_numbers = true)
    override_type!(cycle_ctx, JSCompatOverride) do _ctx
        Dict("examples" => cycle)
    end
    err = get_compatibility_error() do
        generate_schema(JSCompatOverride; ctx = cycle_ctx)
    end
    @test endswith(err.path, "/examples/0")
    @test occursin("cyclic", err.reason)
end

abstract type JSCompatVariant end
struct JSCompatVariantA <: JSCompatVariant end
struct JSCompatVariantB <: JSCompatVariant end

@testset "Discriminator values are normalized before validation" begin
    ctx = SchemaContext(javascript_safe_numbers = true)
    @test_throws ArgumentError override_abstract!(
        ctx,
        JSCompatVariant;
        variants = [JSCompatVariantA, JSCompatVariantB],
        discr_key = "kind",
        tag_value = Dict(JSCompatVariantA => 1, JSCompatVariantB => 1.0)
    )

    exact_ctx = SchemaContext(javascript_safe_numbers = true)
    @test override_abstract!(
        exact_ctx,
        JSCompatVariant;
        variants = [JSCompatVariantA, JSCompatVariantB],
        discr_key = "kind",
        tag_value = Dict(JSCompatVariantA => 1 // 2, JSCompatVariantB => true)
    ) === nothing
    exact_result = generate_schema(
        JSCompatVariant;
        ctx = exact_ctx,
        simplify = false
    )
    abstract_def = exact_result.doc["\$defs"][js_compat_key(JSCompatVariant)]
    first_tag = abstract_def["anyOf"][1]["allOf"][2]["properties"]["kind"]
    second_tag = abstract_def["anyOf"][2]["allOf"][2]["properties"]["kind"]
    @test first_tag["const"] === 0.5
    @test second_tag["const"] === true

    err = get_compatibility_error() do
        override_abstract!(
            ctx,
            JSCompatVariant;
            variants = [JSCompatVariantA, JSCompatVariantB],
            discr_key = "kind",
            tag_value = Dict(
                JSCompatVariantA => 1,
                JSCompatVariantB => Int64(9_007_199_254_740_992)
            )
        )
    end
    @test occursin("/tag_value/", err.path)

    err = get_compatibility_error() do
        override_abstract!(
            ctx,
            JSCompatVariant;
            variants = [JSCompatVariantA, JSCompatVariantB],
            discr_key = "kind",
            tag_value = Dict(JSCompatVariantA => 1, JSCompatVariantB => 1 + 2im)
        )
    end
    @test occursin("not supported", err.reason)
end

@testset "JSON Pointer paths" begin
    err = get_compatibility_error() do
        normalize_javascript_value(Int64(9_007_199_254_740_992), String[])
    end
    @test isempty(err.path)
    @test occursin("at <root>", sprint(showerror, err))
end

@testset "Non-JSON override values are rejected" begin
    ctx = SchemaContext(javascript_safe_numbers = true)
    override_type!(ctx, JSCompatOverride) do _ctx
        Dict("examples" => [Dict(1 => "value")])
    end
    err = get_compatibility_error() do
        generate_schema(JSCompatOverride; ctx = ctx, simplify = false)
    end
    @test occursin("/examples/0", err.path)
    @test occursin("keys must be strings", err.reason)
end
