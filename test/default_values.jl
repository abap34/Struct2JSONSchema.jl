using Test
using Struct2JSONSchema: SchemaContext, generate_schema, defaultvalue!, k, override_field!, override_type!, describe!, defaultvalue_field_serializer!, defaultvalue_type_serializer!, defaultvalue_serializer!, auto_optional_nothing!, override_abstract!, skip!, RepresentableScalar
using Dates
import Base: UUID

const _DEFAULT_KEY_CTX = SchemaContext()
default_key(T) = k(T, _DEFAULT_KEY_CTX)

@testset "Default values - basic primitives" begin
    struct BasicTypes
        str::String
        num::Int
        flt::Float64
        flag::Bool
    end

    ctx = SchemaContext()
    default_val = BasicTypes("hello", 42, 3.14, true)
    defaultvalue!(ctx, default_val)

    result = generate_schema(BasicTypes; ctx = ctx, simplify = false)
    defs = result.doc["\$defs"]
    schema = defs[default_key(BasicTypes)]

    @test schema["properties"]["str"]["default"] == "hello"
    @test schema["properties"]["num"]["default"] == 42
    @test schema["properties"]["flt"]["default"] == 3.14
    @test schema["properties"]["flag"]["default"] == true
end

@testset "Default values - standard types" begin
    struct StandardTypes
        dt::DateTime
        d::Date
        t::Time
        u::UUID
        s::Symbol
        c::Char
    end

    ctx = SchemaContext()
    default_val = StandardTypes(
        DateTime(2024, 1, 1, 12, 30, 45),
        Date(2024, 1, 1),
        Time(12, 30, 45),
        UUID("550e8400-e29b-41d4-a716-446655440000"),
        :test_symbol,
        'A'
    )
    defaultvalue!(ctx, default_val)

    result = generate_schema(StandardTypes; ctx = ctx, simplify = false)
    defs = result.doc["\$defs"]
    schema = defs[default_key(StandardTypes)]

    @test schema["properties"]["dt"]["default"] == "2024-01-01T12:30:45"
    @test schema["properties"]["d"]["default"] == "2024-01-01"
    @test schema["properties"]["t"]["default"] == "12:30:45"
    @test schema["properties"]["u"]["default"] == "550e8400-e29b-41d4-a716-446655440000"
    @test schema["properties"]["s"]["default"] == "test_symbol"
    @test schema["properties"]["c"]["default"] == "A"
end

@testset "Default values - collections" begin
    struct CollectionTypes
        vec::Vector{Int}
        dict::Dict{String, Int}
    end

    ctx = SchemaContext()
    default_val = CollectionTypes(
        [1, 2, 3],
        Dict("a" => 1, "b" => 2)
    )
    defaultvalue!(ctx, default_val)

    result = generate_schema(CollectionTypes; ctx = ctx, simplify = false)
    defs = result.doc["\$defs"]
    schema = defs[default_key(CollectionTypes)]

    @test schema["properties"]["vec"]["default"] == [1, 2, 3]
    @test schema["properties"]["dict"]["default"] == Dict("a" => 1, "b" => 2)
end

@testset "Default values - priority with override" begin
    struct ConfigValue
        port::Int
        host::String
    end

    ctx = SchemaContext()

    # Override で default を設定
    override_field!(ctx, ConfigValue, :port) do ctx
        Dict("type" => "integer", "minimum" => 1024, "default" => 8080)
    end

    # defaultvalue! で別の値を登録
    default_val = ConfigValue(3000, "localhost")
    defaultvalue!(ctx, default_val)

    result = generate_schema(ConfigValue; ctx = ctx, simplify = false)
    defs = result.doc["\$defs"]
    schema = defs[default_key(ConfigValue)]

    # Override の default が優先される
    @test schema["properties"]["port"]["default"] == 8080
    # host は defaultvalue! の値が使われる
    @test schema["properties"]["host"]["default"] == "localhost"
end

@testset "Default values - no override on default" begin
    struct SimpleConfig
        timeout::Float64
    end

    ctx = SchemaContext()

    # Override で制約のみ設定（default なし）
    override_field!(ctx, SimpleConfig, :timeout) do ctx
        Dict("type" => "number", "minimum" => 0)
    end

    # defaultvalue! で設定
    default_val = SimpleConfig(30.0)
    defaultvalue!(ctx, default_val)

    result = generate_schema(SimpleConfig; ctx = ctx, simplify = false)
    defs = result.doc["\$defs"]
    schema = defs[default_key(SimpleConfig)]

    # defaultvalue! の値が設定される
    @test schema["properties"]["timeout"]["default"] == 30.0
    @test schema["properties"]["timeout"]["minimum"] == 0
end

@testset "Default values - partial fields" begin
    struct MixedTypes
        name::String
        value::Int
        callback::Function
    end

    ctx = SchemaContext(verbose = false)

    default_val = MixedTypes("test", 123, () -> nothing)
    defaultvalue!(ctx, default_val)

    result = generate_schema(MixedTypes; ctx = ctx, simplify = false)
    defs = result.doc["\$defs"]
    schema = defs[default_key(MixedTypes)]

    # Serializable fields have defaults
    @test schema["properties"]["name"]["default"] == "test"
    @test schema["properties"]["value"]["default"] == 123

    # Function field has no default
    @test !haskey(schema["properties"]["callback"], "default")

    # unknowns should contain the Function type (with abstract_no_discriminator reason from schema generation)
    @test any(e -> e.type == Function && e.reason == "abstract_no_discriminator", result.unknowns)
end

@testset "Default values - error on invalid instance" begin
    abstract type AbstractBase end

    ctx = SchemaContext()

    # Abstract type should error
    @test_throws ArgumentError defaultvalue!(ctx, AbstractBase)

    # Union type should error
    @test_throws ArgumentError defaultvalue!(ctx, Union{Int, String})
end

@testset "Default values - number normalization" begin
    struct NumberTypes
        i8::Int8
        i16::Int16
        i32::Int32
        f32::Float32
    end

    ctx = SchemaContext()
    default_val = NumberTypes(Int8(10), Int16(20), Int32(30), Float32(1.5))
    defaultvalue!(ctx, default_val)

    result = generate_schema(NumberTypes; ctx = ctx, simplify = false)
    defs = result.doc["\$defs"]
    schema = defs[default_key(NumberTypes)]

    # All integers should be normalized to Int
    @test schema["properties"]["i8"]["default"] isa Int
    @test schema["properties"]["i16"]["default"] isa Int
    @test schema["properties"]["i32"]["default"] isa Int

    # Float32 should be normalized to Float64
    @test schema["properties"]["f32"]["default"] isa Float64
end

@testset "Default values - custom serializer (type)" begin
    struct Color
        r::UInt8
        g::UInt8
        b::UInt8
    end

    struct Theme
        primary::Color
        secondary::Color
    end

    ctx = SchemaContext()

    # Register custom serializer for Color
    defaultvalue_type_serializer!(ctx, Color) do value, ctx
        r = string(value.r, base = 16, pad = 2)
        g = string(value.g, base = 16, pad = 2)
        b = string(value.b, base = 16, pad = 2)
        "#$(r)$(g)$(b)"
    end

    # Register type override for Color
    override_type!(ctx, Color) do ctx
        Dict("type" => "string", "pattern" => "^#[0-9a-f]{6}\$")
    end

    default_theme = Theme(
        Color(0x00, 0x7b, 0xff),
        Color(0x6c, 0x75, 0x7d)
    )
    defaultvalue!(ctx, default_theme)

    result = generate_schema(Theme; ctx = ctx, simplify = false)
    defs = result.doc["\$defs"]
    schema = defs[default_key(Theme)]

    # Colors should be serialized as hex strings
    @test schema["properties"]["primary"]["default"] == "#007bff"
    @test schema["properties"]["secondary"]["default"] == "#6c757d"
end

@testset "Default values - custom serializer (field)" begin
    struct Metrics
        created_at::DateTime
        updated_at::DateTime
    end

    ctx = SchemaContext()

    # created_at as Unix timestamp
    defaultvalue_field_serializer!(ctx, Metrics, :created_at) do value, ctx
        Int(datetime2unix(value))
    end

    override_field!(ctx, Metrics, :created_at) do ctx
        Dict("type" => "integer", "description" => "Unix timestamp")
    end

    default_metrics = Metrics(
        DateTime(2024, 1, 1, 0, 0, 0),
        DateTime(2024, 1, 2, 0, 0, 0)
    )
    defaultvalue!(ctx, default_metrics)

    result = generate_schema(Metrics; ctx = ctx, simplify = false)
    defs = result.doc["\$defs"]
    schema = defs[default_key(Metrics)]

    # created_at should be Unix timestamp
    @test schema["properties"]["created_at"]["default"] == 1704067200

    # updated_at should be ISO string (no custom serializer)
    @test schema["properties"]["updated_at"]["default"] == "2024-01-02T00:00:00"
end

@testset "Default values - with optional fields" begin
    struct UserConfig
        username::String
        email::Union{String, Nothing}
        bio::String
    end

    ctx = SchemaContext()
    auto_optional_nothing!(ctx)

    default_config = UserConfig("guest", nothing, "")
    defaultvalue!(ctx, default_config)

    result = generate_schema(UserConfig; ctx = ctx, simplify = false)
    defs = result.doc["\$defs"]
    schema = defs[default_key(UserConfig)]

    # Required fields with defaults
    @test schema["properties"]["username"]["default"] == "guest"
    @test schema["properties"]["bio"]["default"] == ""

    # Optional field: nothing serializes to null
    @test schema["properties"]["email"]["default"] === nothing

    # email should not be in required
    @test "email" ∉ schema["required"]
end

@testset "Default values - with field descriptions" begin
    struct Product
        name::String
        price::Float64
    end

    ctx = SchemaContext()

    describe!(ctx, Product, :price, "Product price in USD")

    default_product = Product("Widget", 9.99)
    defaultvalue!(ctx, default_product)

    result = generate_schema(Product; ctx = ctx, simplify = false)
    defs = result.doc["\$defs"]
    schema = defs[default_key(Product)]

    # Both default and description should be present
    @test schema["properties"]["price"]["default"] == 9.99
    @test schema["properties"]["price"]["description"] == "Product price in USD"
end

@testset "Default values - override with description priority" begin
    struct Settings
        timeout::Int
    end

    ctx = SchemaContext()

    # Override with description
    override_field!(ctx, Settings, :timeout) do ctx
        Dict(
            "type" => "integer",
            "minimum" => 0,
            "description" => "Timeout from override"
        )
    end

    # Try to set description via registration (should be ignored)
    describe!(ctx, Settings, :timeout, "Timeout from registration")

    default_settings = Settings(30)
    defaultvalue!(ctx, default_settings)

    result = generate_schema(Settings; ctx = ctx, simplify = false)
    defs = result.doc["\$defs"]
    schema = defs[default_key(Settings)]

    # Override description should win
    @test schema["properties"]["timeout"]["description"] == "Timeout from override"
    @test schema["properties"]["timeout"]["default"] == 30
end

@testset "Default values - empty collections" begin
    struct EmptyCollections
        items::Vector{String}
        metadata::Dict{String, Int}
    end

    ctx = SchemaContext()

    default_val = EmptyCollections(String[], Dict{String, Int}())
    defaultvalue!(ctx, default_val)

    result = generate_schema(EmptyCollections; ctx = ctx, simplify = false)
    defs = result.doc["\$defs"]
    schema = defs[default_key(EmptyCollections)]

    @test schema["properties"]["items"]["default"] == []
    @test schema["properties"]["metadata"]["default"] == Dict()
end

@testset "Default values - nested collections" begin
    struct NestedData
        matrix::Vector{Vector{Int}}
        nested_dict::Dict{String, Dict{String, Int}}
    end

    ctx = SchemaContext()

    default_val = NestedData(
        [[1, 2], [3, 4]],
        Dict("a" => Dict("x" => 1, "y" => 2))
    )
    defaultvalue!(ctx, default_val)

    result = generate_schema(NestedData; ctx = ctx, simplify = false)
    defs = result.doc["\$defs"]
    schema = defs[default_key(NestedData)]

    @test schema["properties"]["matrix"]["default"] == [[1, 2], [3, 4]]
    @test schema["properties"]["nested_dict"]["default"] == Dict("a" => Dict("x" => 1, "y" => 2))
end

@testset "Default values - unknowns tracking" begin
    struct WithUnknown
        name::String
        func::Function
        type_ref::Type
    end

    ctx = SchemaContext(verbose = false)

    default_val = WithUnknown("test", () -> nothing, Int)
    defaultvalue!(ctx, default_val)

    result = generate_schema(WithUnknown; ctx = ctx, simplify = false)

    # Should have unknowns for unsupported types
    # Function gets "abstract_no_discriminator" from schema generation
    # Type gets "unionall_type" from schema generation (Type is a UnionAll)
    @test any(e -> e.type == Function && e.path == (:func,) && e.reason == "abstract_no_discriminator", result.unknowns)
    @test any(e -> e.type == Type && e.path == (:type_ref,) && e.reason == "unionall_type", result.unknowns)
end

@testset "Default values - serializer evaluation order" begin
    struct OrderTest
        value::Int
    end

    ctx = SchemaContext()

    # Register multiple serializers in order
    defaultvalue_serializer!(ctx) do field_type, value, ctx
        if field_type == Int
            return 100  # First serializer
        end
        return nothing
    end

    defaultvalue_serializer!(ctx) do field_type, value, ctx
        if field_type == Int
            return 200  # Second serializer (should not be reached)
        end
        return nothing
    end

    default_val = OrderTest(42)
    defaultvalue!(ctx, default_val)

    result = generate_schema(OrderTest; ctx = ctx, simplify = false)
    defs = result.doc["\$defs"]
    schema = defs[default_key(OrderTest)]

    # First serializer should win
    @test schema["properties"]["value"]["default"] == 100
end

@testset "Default values - serializer fallback" begin
    struct FallbackTest
        name::String
    end

    ctx = SchemaContext()

    # Register serializer that returns nothing
    defaultvalue_serializer!(ctx) do field_type, value, ctx
        return nothing  # Fall through
    end

    default_val = FallbackTest("test")
    defaultvalue!(ctx, default_val)

    result = generate_schema(FallbackTest; ctx = ctx, simplify = false)
    defs = result.doc["\$defs"]
    schema = defs[default_key(FallbackTest)]

    # Should fall back to defaultvalue_serialize
    @test schema["properties"]["name"]["default"] == "test"
end

# ===== 複合的なテスト =====

@testset "Complex - defaults with abstract types and discriminator" begin
    abstract type Vehicle end

    struct Car <: Vehicle
        brand::String
        seats::Int
    end

    struct Bike <: Vehicle
        brand::String
        gears::Int
    end

    struct Garage
        name::String
        vehicles::Vector{Vehicle}
    end

    ctx = SchemaContext()

    # 抽象型の登録
    override_abstract!(
        ctx, Vehicle;
        variants = [Car, Bike],
        discr_key = "vehicle_type",
        tag_value = Dict{DataType, RepresentableScalar}(
            Car => "car",
            Bike => "bike"
        )
    )

    # 各バリアントのデフォルト値を登録
    defaultvalue!(ctx, Car("Toyota", 5))
    defaultvalue!(ctx, Bike("Giant", 21))
    defaultvalue!(ctx, Garage("My Garage", Vehicle[]))

    # Garage のスキーマを生成
    result = generate_schema(Garage; ctx = ctx, simplify = false)
    defs = result.doc["\$defs"]

    # Garage のデフォルト値を確認
    garage_schema = defs[default_key(Garage)]
    @test garage_schema["properties"]["name"]["default"] == "My Garage"
    @test garage_schema["properties"]["vehicles"]["default"] == []

    # Car のデフォルト値を確認
    car_schema = defs[default_key(Car)]
    @test car_schema["properties"]["brand"]["default"] == "Toyota"
    @test car_schema["properties"]["seats"]["default"] == 5

    # Bike のデフォルト値を確認
    bike_schema = defs[default_key(Bike)]
    @test bike_schema["properties"]["brand"]["default"] == "Giant"
    @test bike_schema["properties"]["gears"]["default"] == 21
end

@testset "Complex - nested structs with custom serializers and defaults" begin
    struct Point
        x::Float64
        y::Float64
    end

    struct Rectangle
        top_left::Point
        bottom_right::Point
        color::String
    end

    ctx = SchemaContext()

    # Point をカスタムフォーマットにシリアライズ（配列として）
    defaultvalue_type_serializer!(ctx, Point) do value, ctx
        [value.x, value.y]
    end

    override_type!(ctx, Point) do ctx
        Dict(
            "type" => "array",
            "items" => Dict("type" => "number"),
            "minItems" => 2,
            "maxItems" => 2
        )
    end

    # デフォルト値を登録
    default_rect = Rectangle(
        Point(0.0, 100.0),
        Point(100.0, 0.0),
        "#FF0000"
    )
    defaultvalue!(ctx, default_rect)

    result = generate_schema(Rectangle; ctx = ctx, simplify = false)
    defs = result.doc["\$defs"]
    rect_schema = defs[default_key(Rectangle)]

    # ネストした構造体のデフォルト値が正しくシリアライズされているか確認
    @test rect_schema["properties"]["top_left"]["default"] == [0.0, 100.0]
    @test rect_schema["properties"]["bottom_right"]["default"] == [100.0, 0.0]
    @test rect_schema["properties"]["color"]["default"] == "#FF0000"
end

@testset "Complex - defaults with skip, optional, override, and description" begin
    struct ComplexConfig
        # 通常のフィールド（デフォルト値あり）
        app_name::String
        # オプショナルフィールド（デフォルト値 = nothing）
        database_url::Union{String, Nothing}
        # スキップするフィールド（スキーマに含まれない）
        internal_state::Int
        # オーバーライド + デフォルト値
        port::Int
        # 説明 + デフォルト値
        timeout::Float64
    end

    ctx = SchemaContext()
    auto_optional_nothing!(ctx)

    # フィールドのスキップ
    skip!(ctx, ComplexConfig, :internal_state)

    # ポートのオーバーライド（制約を追加）
    override_field!(ctx, ComplexConfig, :port) do ctx
        Dict(
            "type" => "integer",
            "minimum" => 1024,
            "maximum" => 65535
        )
    end

    # タイムアウトの説明
    describe!(ctx, ComplexConfig, :timeout, "Request timeout in seconds")

    # デフォルト値を登録
    default_config = ComplexConfig(
        "MyApp",
        nothing,
        12345,  # このフィールドはスキップされる
        8080,
        30.0
    )
    defaultvalue!(ctx, default_config)

    result = generate_schema(ComplexConfig; ctx = ctx, simplify = false)
    defs = result.doc["\$defs"]
    schema = defs[default_key(ComplexConfig)]

    # 通常のフィールド
    @test schema["properties"]["app_name"]["default"] == "MyApp"

    # オプショナルフィールド
    @test schema["properties"]["database_url"]["default"] === nothing
    @test "database_url" ∉ schema["required"]

    # スキップしたフィールドはスキーマに存在しない
    @test !haskey(schema["properties"], "internal_state")

    # オーバーライド + デフォルト値
    @test schema["properties"]["port"]["default"] == 8080
    @test schema["properties"]["port"]["minimum"] == 1024
    @test schema["properties"]["port"]["maximum"] == 65535

    # 説明 + デフォルト値
    @test schema["properties"]["timeout"]["default"] == 30.0
    @test schema["properties"]["timeout"]["description"] == "Request timeout in seconds"
end

@testset "Complex - self-referencing type with defaults" begin
    struct TreeNode
        value::Int
        children::Vector{TreeNode}
    end

    ctx = SchemaContext()

    # 再帰的な構造のデフォルト値
    default_tree = TreeNode(1, TreeNode[])
    defaultvalue!(ctx, default_tree)

    result = generate_schema(TreeNode; ctx = ctx, simplify = false)
    defs = result.doc["\$defs"]
    schema = defs[default_key(TreeNode)]

    # デフォルト値が設定されているか確認
    @test schema["properties"]["value"]["default"] == 1
    @test schema["properties"]["children"]["default"] == []

    # 再帰的な参照が正しく処理されているか確認
    @test haskey(result.doc, "\$defs")
    @test !isempty(result.doc["\$defs"])
end

@testset "Complex - multiple field serializers with nested types" begin
    struct Timestamp
        unix_time::Int
    end

    struct LogEntry
        id::UUID
        message::String
        created::DateTime
        modified::DateTime
        metadata::Dict{String, String}
    end

    ctx = SchemaContext()

    # id フィールドは大文字のUUIDとして
    defaultvalue_field_serializer!(ctx, LogEntry, :id) do value, ctx
        uppercase(string(value))
    end

    # created は Unix タイムスタンプとして
    defaultvalue_field_serializer!(ctx, LogEntry, :created) do value, ctx
        Int(datetime2unix(value))
    end

    override_field!(ctx, LogEntry, :created) do ctx
        Dict("type" => "integer", "description" => "Unix timestamp")
    end

    # modified は ISO 8601 のまま（デフォルトシリアライザ）

    default_entry = LogEntry(
        UUID("550e8400-e29b-41d4-a716-446655440000"),
        "System started",
        DateTime(2024, 1, 1, 0, 0, 0),
        DateTime(2024, 1, 1, 1, 0, 0),
        Dict("level" => "info", "component" => "main")
    )
    defaultvalue!(ctx, default_entry)

    result = generate_schema(LogEntry; ctx = ctx, simplify = false)
    defs = result.doc["\$defs"]
    schema = defs[default_key(LogEntry)]

    # フィールド固有のシリアライザが適用されているか確認
    @test schema["properties"]["id"]["default"] == "550E8400-E29B-41D4-A716-446655440000"
    @test schema["properties"]["message"]["default"] == "System started"
    @test schema["properties"]["created"]["default"] == 1704067200  # Unix timestamp
    @test schema["properties"]["modified"]["default"] == "2024-01-01T01:00:00"  # ISO 8601
    @test schema["properties"]["metadata"]["default"] == Dict("level" => "info", "component" => "main")
end

@testset "Complex - deeply nested structures with mixed serialization" begin
    struct Address
        street::String
        city::String
        zip::String
    end

    struct Contact
        email::Union{String, Nothing}
        phone::Union{String, Nothing}
    end

    struct Person
        name::String
        age::Int
        address::Address
        contact::Contact
        tags::Vector{String}
    end

    ctx = SchemaContext()
    auto_optional_nothing!(ctx)

    # Address をカンマ区切り文字列としてシリアライズ
    defaultvalue_type_serializer!(ctx, Address) do value, ctx
        "$(value.street), $(value.city), $(value.zip)"
    end

    override_type!(ctx, Address) do ctx
        Dict("type" => "string", "description" => "Address in format: street, city, zip")
    end

    # Contact をJSON文字列としてシリアライズ
    defaultvalue_type_serializer!(ctx, Contact) do value, ctx
        parts = String[]
        if value.email !== nothing
            push!(parts, "email:$(value.email)")
        end
        if value.phone !== nothing
            push!(parts, "phone:$(value.phone)")
        end
        isempty(parts) ? "no contact" : join(parts, ";")
    end

    override_type!(ctx, Contact) do ctx
        Dict("type" => "string", "description" => "Contact info")
    end

    # Person のデフォルト値を登録
    default_person = Person(
        "Guest",
        0,
        Address("", "", ""),
        Contact(nothing, nothing),
        String[]
    )
    defaultvalue!(ctx, default_person)

    result = generate_schema(Person; ctx = ctx, simplify = false)
    defs = result.doc["\$defs"]

    # Person のデフォルト値を確認
    person_schema = defs[default_key(Person)]
    @test person_schema["properties"]["name"]["default"] == "Guest"
    @test person_schema["properties"]["age"]["default"] == 0
    @test person_schema["properties"]["address"]["default"] == ", , "  # カスタムシリアライザ
    @test person_schema["properties"]["contact"]["default"] == "no contact"  # カスタムシリアライザ
    @test person_schema["properties"]["tags"]["default"] == []

    # 別の Person のデフォルト値を登録して確認
    default_person2 = Person(
        "Alice",
        30,
        Address("123 Main St", "Tokyo", "100-0001"),
        Contact("alice@example.com", "+81-90-1234-5678"),
        ["developer", "team-lead"]
    )
    defaultvalue!(ctx, default_person2)

    result2 = generate_schema(Person; ctx = ctx, simplify = false)
    defs2 = result2.doc["\$defs"]
    person_schema2 = defs2[default_key(Person)]

    @test person_schema2["properties"]["name"]["default"] == "Alice"
    @test person_schema2["properties"]["age"]["default"] == 30
    @test person_schema2["properties"]["address"]["default"] == "123 Main St, Tokyo, 100-0001"
    @test person_schema2["properties"]["contact"]["default"] == "email:alice@example.com;phone:+81-90-1234-5678"
    @test person_schema2["properties"]["tags"]["default"] == ["developer", "team-lead"]
end

@testset "Complex - simplification with defaults" begin
    struct Config
        name::String
        port::Int
        enabled::Bool
    end

    ctx = SchemaContext()
    defaultvalue!(ctx, Config("app", 8080, true))

    # simplify=true でもデフォルト値が保持されるか
    result = generate_schema(Config; ctx = ctx, simplify = true)

    # simplify により $defs が削除されインライン化される可能性がある
    # デフォルト値が正しく保持されているか確認
    @test haskey(result.doc, "properties") || haskey(result.doc, "\$defs")

    # トップレベルまたは $defs 内のスキーマを確認
    if haskey(result.doc, "properties")
        # インライン化された場合
        @test result.doc["properties"]["name"]["default"] == "app"
        @test result.doc["properties"]["port"]["default"] == 8080
        @test result.doc["properties"]["enabled"]["default"] == true
    else
        # $defs に残っている場合
        @test !isempty(result.doc["\$defs"])
    end
end

@testset "Complex - enum with defaults" begin
    @enum Status begin
        PENDING
        RUNNING
        COMPLETED
        FAILED
    end

    struct Task
        name::String
        status::Status
        priority::Int
    end

    ctx = SchemaContext()

    # Enum 型のカスタムシリアライザー
    defaultvalue_type_serializer!(ctx, Status) do value, ctx
        string(value)
    end

    # Enum 型を含む構造体のデフォルト値
    default_task = Task("My Task", PENDING, 1)
    defaultvalue!(ctx, default_task)

    result = generate_schema(Task; ctx = ctx, simplify = false)
    defs = result.doc["\$defs"]
    task_schema = defs[default_key(Task)]

    @test task_schema["properties"]["name"]["default"] == "My Task"
    @test task_schema["properties"]["status"]["default"] == "PENDING"
    @test task_schema["properties"]["priority"]["default"] == 1

    # Status の enum スキーマが正しく生成されているか
    status_key = k(Status, ctx)
    @test haskey(defs, status_key)
    @test defs[status_key]["enum"] == ["PENDING", "RUNNING", "COMPLETED", "FAILED"]
end

@testset "Complex - tuple and namedtuple with defaults" begin
    struct Coordinate
        point::Tuple{Float64, Float64}
        meta::NamedTuple{(:label, :color), Tuple{String, String}}
    end

    ctx = SchemaContext()

    # Tuple と NamedTuple のカスタムシリアライザー
    defaultvalue_field_serializer!(ctx, Coordinate, :point) do value, ctx
        [value[1], value[2]]
    end

    defaultvalue_field_serializer!(ctx, Coordinate, :meta) do value, ctx
        Dict("label" => value.label, "color" => value.color)
    end

    default_coord = Coordinate(
        (1.5, 2.5),
        (label = "origin", color = "red")
    )
    defaultvalue!(ctx, default_coord)

    result = generate_schema(Coordinate; ctx = ctx, simplify = false)
    defs = result.doc["\$defs"]
    schema = defs[default_key(Coordinate)]

    # Tuple のデフォルト値
    @test schema["properties"]["point"]["default"] == [1.5, 2.5]

    # NamedTuple のデフォルト値
    @test schema["properties"]["meta"]["default"] == Dict("label" => "origin", "color" => "red")
end

@testset "Complex - context cloning preserves defaults" begin
    struct Service
        name::String
        port::Int
    end

    ctx = SchemaContext()
    defaultvalue!(ctx, Service("api", 3000))

    # コンテキストをクローンしてもデフォルト値が保持されるか
    result1 = generate_schema(Service; ctx = ctx, simplify = false)
    result2 = generate_schema(Service; ctx = ctx, simplify = false)

    defs1 = result1.doc["\$defs"]
    defs2 = result2.doc["\$defs"]

    schema1 = defs1[default_key(Service)]
    schema2 = defs2[default_key(Service)]

    # 両方のスキーマが同じデフォルト値を持つ
    @test schema1["properties"]["name"]["default"] == "api"
    @test schema2["properties"]["name"]["default"] == "api"
    @test schema1["properties"]["port"]["default"] == 3000
    @test schema2["properties"]["port"]["default"] == 3000
end

@testset "Complex - serializer error handling" begin
    struct Data
        value::Int
        timestamp::DateTime
    end

    ctx = SchemaContext(verbose = false)

    # エラーを投げるシリアライザーを登録
    defaultvalue_serializer!(ctx) do field_type, value, ctx
        if field_type == Int
            error("Intentional error")
        end
        return nothing
    end

    # エラーが発生してもクラッシュせず、フォールバックする
    default_data = Data(42, DateTime(2024, 1, 1))
    defaultvalue!(ctx, default_data)

    result = generate_schema(Data; ctx = ctx, simplify = false)
    defs = result.doc["\$defs"]
    schema = defs[default_key(Data)]

    # エラーが発生したフィールドはフォールバックシリアライザーを使用
    @test schema["properties"]["value"]["default"] == 42
    @test schema["properties"]["timestamp"]["default"] == "2024-01-01T00:00:00"
end

@testset "Complex - multiple type overrides with defaults" begin
    struct Point2D
        x::Float64
        y::Float64
    end

    struct Point3D
        x::Float64
        y::Float64
        z::Float64
    end

    struct Shape
        center2d::Point2D
        center3d::Point3D
        radius::Float64
    end

    ctx = SchemaContext()

    # 複数の型オーバーライド
    override_type!(ctx, Point2D) do ctx
        Dict("type" => "array", "items" => Dict("type" => "number"), "minItems" => 2, "maxItems" => 2)
    end

    override_type!(ctx, Point3D) do ctx
        Dict("type" => "array", "items" => Dict("type" => "number"), "minItems" => 3, "maxItems" => 3)
    end

    # カスタムシリアライザー
    defaultvalue_type_serializer!(ctx, Point2D) do value, ctx
        [value.x, value.y]
    end

    defaultvalue_type_serializer!(ctx, Point3D) do value, ctx
        [value.x, value.y, value.z]
    end

    default_shape = Shape(
        Point2D(1.0, 2.0),
        Point3D(1.0, 2.0, 3.0),
        5.0
    )
    defaultvalue!(ctx, default_shape)

    result = generate_schema(Shape; ctx = ctx, simplify = false)
    defs = result.doc["\$defs"]
    schema = defs[default_key(Shape)]

    @test schema["properties"]["center2d"]["default"] == [1.0, 2.0]
    @test schema["properties"]["center3d"]["default"] == [1.0, 2.0, 3.0]
    @test schema["properties"]["radius"]["default"] == 5.0
end

@testset "Complex - deeply nested optionals with defaults" begin
    struct Inner
        value::Union{Int, Nothing}
    end

    struct Middle
        inner::Union{Inner, Nothing}
        name::Union{String, Nothing}
    end

    struct Outer
        middle::Union{Middle, Nothing}
        id::Int
    end

    ctx = SchemaContext()
    auto_optional_nothing!(ctx)

    # ネストした optional フィールド
    default_outer = Outer(
        Middle(
            Inner(42),
            "test"
        ),
        1
    )
    defaultvalue!(ctx, default_outer)

    # Inner のデフォルト値も登録
    defaultvalue!(ctx, Inner(nothing))

    # Middle のデフォルト値も登録
    defaultvalue!(ctx, Middle(nothing, nothing))

    result = generate_schema(Outer; ctx = ctx, simplify = false)
    defs = result.doc["\$defs"]

    # Outer のデフォルト値確認
    outer_schema = defs[default_key(Outer)]
    @test outer_schema["properties"]["id"]["default"] == 1
    # middle フィールドは optional
    @test "middle" ∉ outer_schema["required"]

    # Inner のデフォルト値確認
    inner_schema = defs[default_key(Inner)]
    @test inner_schema["properties"]["value"]["default"] === nothing
    @test "value" ∉ inner_schema["required"]
end

@testset "Complex - versionnumber and rational defaults" begin
    struct Package
        name::String
        version::VersionNumber
        ratio::Rational{Int}
    end

    ctx = SchemaContext()

    # Rational のカスタムシリアライザー（浮動小数点数に変換）
    defaultvalue_type_serializer!(ctx, Rational{Int}) do value, ctx
        Float64(value)
    end

    default_pkg = Package(
        "MyPackage",
        v"1.2.3",
        1//2
    )
    defaultvalue!(ctx, default_pkg)

    result = generate_schema(Package; ctx = ctx, simplify = false)
    defs = result.doc["\$defs"]
    schema = defs[default_key(Package)]

    @test schema["properties"]["name"]["default"] == "MyPackage"
    @test schema["properties"]["version"]["default"] == "1.2.3"
    @test schema["properties"]["ratio"]["default"] == 0.5
end

@testset "Complex - mixed skip and defaults" begin
    struct FullConfig
        # 通常フィールド（デフォルト値あり）
        name::String
        port::Int
        # スキップするフィールド（デフォルト値も無視される）
        internal_cache::Dict{String, Any}
        internal_state::Int
        # オプショナル（デフォルト値あり）
        description::Union{String, Nothing}
    end

    ctx = SchemaContext()
    auto_optional_nothing!(ctx)

    # スキップするフィールドを登録
    skip!(ctx, FullConfig, :internal_cache, :internal_state)

    # すべてのフィールドのデフォルト値を登録
    default_config = FullConfig(
        "MyApp",
        8080,
        Dict("key" => "value"),  # このフィールドはスキップされる
        12345,                    # このフィールドもスキップされる
        "A description"
    )
    defaultvalue!(ctx, default_config)

    result = generate_schema(FullConfig; ctx = ctx, simplify = false)
    defs = result.doc["\$defs"]
    schema = defs[default_key(FullConfig)]

    # 通常フィールドにデフォルト値がある
    @test schema["properties"]["name"]["default"] == "MyApp"
    @test schema["properties"]["port"]["default"] == 8080

    # スキップしたフィールドはスキーマに存在しない
    @test !haskey(schema["properties"], "internal_cache")
    @test !haskey(schema["properties"], "internal_state")

    # オプショナルフィールドにデフォルト値がある
    @test schema["properties"]["description"]["default"] == "A description"
    @test "description" ∉ schema["required"]
end

@testset "Complex - circular type dependencies" begin
    # Node -> NodeList -> Node の循環参照
    struct Node
        value::Int
        children::Vector{Node}
    end

    ctx = SchemaContext()

    # 空の子ノードリストを持つノード
    default_node = Node(1, Node[])
    defaultvalue!(ctx, default_node)

    result = generate_schema(Node; ctx = ctx, simplify = false)
    defs = result.doc["\$defs"]
    schema = defs[default_key(Node)]

    # デフォルト値が正しく設定されている
    @test schema["properties"]["value"]["default"] == 1
    @test schema["properties"]["children"]["default"] == []

    # 循環参照が正しく処理されている（$ref が使われている）
    @test haskey(result.doc, "\$defs")
end

@testset "Complex - all features combined" begin
    # すべての機能を組み合わせた総合テスト

    abstract type Asset end

    struct Stock <: Asset
        symbol::String
        shares::Int
        price::Float64
        purchased::Date
    end

    struct Bond <: Asset
        issuer::String
        face_value::Float64
        maturity::Date
    end

    struct Portfolio
        name::String
        owner::String
        assets::Vector{Asset}
        notes::Union{String, Nothing}
        internal_id::UUID
        risk_level::Int  # 1-10
    end

    ctx = SchemaContext(auto_fielddoc = true)
    auto_optional_nothing!(ctx)

    # 抽象型の登録
    override_abstract!(
        ctx, Asset;
        variants = [Stock, Bond],
        discr_key = "asset_type",
        tag_value = Dict{DataType, RepresentableScalar}(
            Stock => "stock",
            Bond => "bond"
        )
    )

    # risk_level にオーバーライドと説明を追加
    override_field!(ctx, Portfolio, :risk_level) do ctx
        Dict("type" => "integer", "minimum" => 1, "maximum" => 10)
    end

    describe!(ctx, Portfolio, :risk_level, "Risk level from 1 (low) to 10 (high)")

    # Date をカスタムフォーマットでシリアライズ
    defaultvalue_field_serializer!(ctx, Stock, :purchased) do value, ctx
        Dates.format(value, "yyyy/mm/dd")
    end

    override_field!(ctx, Stock, :purchased) do ctx
        Dict("type" => "string", "pattern" => "^\\d{4}/\\d{2}/\\d{2}\$")
    end

    # デフォルト値を登録
    defaultvalue!(ctx, Stock("AAPL", 100, 150.0, Date(2024, 1, 1)))
    defaultvalue!(ctx, Bond("US Treasury", 1000.0, Date(2034, 1, 1)))
    defaultvalue!(ctx, Portfolio(
        "My Portfolio",
        "John Doe",
        Asset[],
        nothing,
        UUID("550e8400-e29b-41d4-a716-446655440000"),
        5
    ))

    result = generate_schema(Portfolio; ctx = ctx, simplify = false)
    defs = result.doc["\$defs"]

    # Portfolio のデフォルト値確認
    portfolio_schema = defs[default_key(Portfolio)]
    @test portfolio_schema["properties"]["name"]["default"] == "My Portfolio"
    @test portfolio_schema["properties"]["owner"]["default"] == "John Doe"
    @test portfolio_schema["properties"]["assets"]["default"] == []
    @test portfolio_schema["properties"]["notes"]["default"] === nothing
    @test portfolio_schema["properties"]["internal_id"]["default"] == "550e8400-e29b-41d4-a716-446655440000"
    @test portfolio_schema["properties"]["risk_level"]["default"] == 5
    @test portfolio_schema["properties"]["risk_level"]["minimum"] == 1
    @test portfolio_schema["properties"]["risk_level"]["maximum"] == 10
    @test portfolio_schema["properties"]["risk_level"]["description"] == "Risk level from 1 (low) to 10 (high)"

    # notes は optional
    @test "notes" ∉ portfolio_schema["required"]

    # Stock のデフォルト値確認
    stock_schema = defs[default_key(Stock)]
    @test stock_schema["properties"]["symbol"]["default"] == "AAPL"
    @test stock_schema["properties"]["shares"]["default"] == 100
    @test stock_schema["properties"]["price"]["default"] == 150.0
    @test stock_schema["properties"]["purchased"]["default"] == "2024/01/01"  # カスタムフォーマット

    # Bond のデフォルト値確認
    bond_schema = defs[default_key(Bond)]
    @test bond_schema["properties"]["issuer"]["default"] == "US Treasury"
    @test bond_schema["properties"]["face_value"]["default"] == 1000.0
    @test bond_schema["properties"]["maturity"]["default"] == "2034-01-01"  # デフォルトフォーマット
end
