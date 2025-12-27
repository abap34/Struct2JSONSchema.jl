using Test
using Struct2JSONSchema: SchemaContext, generate_schema, register_optional_fields!, treat_union_nothing_as_optional!, Struct2JSONSchema.simplify_schema

include("./helpers/validator.jl")

schema_variants(doc) = [
    ("original", doc),
    ("simplified", simplify_schema(doc)),
]

struct ShippingAddressE2E
    line1::String
    city::String
    postal_code::String
end

struct CustomerProfileE2E
    id::String
    email::String
    address::ShippingAddressE2E
end

struct OrderLineE2E
    sku::String
    quantity::Int
    price::Float64
end

@enum OrderStatusE2E begin
    pending
    processing
    shipped
    delivered
    cancelled
end

struct PurchaseOrderE2E
    order_id::String
    customer::CustomerProfileE2E
    lines::Vector{OrderLineE2E}
    status::OrderStatusE2E
    notes::Union{Nothing, String}
end

@testset "End-to-end schema validation" begin
    ctx = SchemaContext()
    result = generate_schema(PurchaseOrderE2E; ctx = ctx, simplify = false)
    doc = result.doc
    @test isempty(result.unknowns)

    valid_payload = Dict(
        "order_id" => "PO-2025-0001",
        "customer" => Dict(
            "id" => "CUST-42",
            "email" => "customer@example.com",
            "address" => Dict(
                "line1" => "1 Infinite Loop",
                "city" => "Cupertino",
                "postal_code" => "95014"
            )
        ),
        "lines" => [
            Dict("sku" => "SKU-BOOK", "quantity" => 2, "price" => 19.99),
            Dict("sku" => "SKU-PEN", "quantity" => 5, "price" => 1.25),
        ],
        "status" => "pending",
        "notes" => nothing
    )

    with_note = deepcopy(valid_payload)
    with_note["notes"] = "Deliver after 5 PM"
    other_status = deepcopy(valid_payload)
    other_status["status"] = "shipped"
    missing_order_id = deepcopy(valid_payload)
    delete!(missing_order_id, "order_id")
    missing_customer = deepcopy(valid_payload)
    delete!(missing_customer, "customer")
    invalid_quantity = deepcopy(valid_payload)
    invalid_quantity["lines"][1]["quantity"] = "two"
    extra_customer_field = deepcopy(valid_payload)
    extra_customer_field["customer"]["vip"] = true
    for (variant_name, schema_doc) in schema_variants(doc)
        @testset "schema=$variant_name" begin
            @test validate_payload(schema_doc, valid_payload)
            @test validate_payload(schema_doc, with_note)
            @test validate_payload(schema_doc, other_status)
            @test !validate_payload(schema_doc, missing_order_id)
            @test !validate_payload(schema_doc, missing_customer)
            @test !validate_payload(schema_doc, invalid_quantity)
            @test !validate_payload(schema_doc, extra_customer_field)
        end
    end
end

struct ContactInfo
    email::String
    phone::String
end

struct UserAccount
    username::String
    contact::ContactInfo
    age::Int
end

@testset "end-to-end validation - user account" begin
    ctx = SchemaContext()
    result = generate_schema(UserAccount; ctx = ctx, simplify = false)
    doc = result.doc

    valid = Dict(
        "username" => "john_doe",
        "contact" => Dict(
            "email" => "john@example.com",
            "phone" => "+1234567890"
        ),
        "age" => 30
    )
    missing_email = deepcopy(valid)
    delete!(missing_email["contact"], "email")
    invalid_age = deepcopy(valid)
    invalid_age["age"] = "thirty"
    extra_field = deepcopy(valid)
    extra_field["premium"] = true
    for (variant_name, schema_doc) in schema_variants(doc)
        @testset "schema=$variant_name" begin
            @test validate_payload(schema_doc, valid)
            @test !validate_payload(schema_doc, missing_email)
            @test !validate_payload(schema_doc, invalid_age)
            @test !validate_payload(schema_doc, extra_field)
        end
    end
end

struct Location
    latitude::Float64
    longitude::Float64
end

struct Store
    name::String
    location::Location
end

@testset "end-to-end validation - store location" begin
    ctx = SchemaContext()
    result = generate_schema(Store; ctx = ctx, simplify = false)
    doc = result.doc

    valid = Dict{String, Any}(
        "name" => "Main Store",
        "location" => Dict{String, Any}(
            "latitude" => 37.7749,
            "longitude" => -122.4194
        )
    )
    missing_lat = deepcopy(valid)
    delete!(missing_lat["location"], "latitude")
    invalid_lon = deepcopy(valid)
    invalid_lon["location"]["longitude"] = "west"
    for (variant_name, schema_doc) in schema_variants(doc)
        @testset "schema=$variant_name" begin
            @test validate_payload(schema_doc, valid)
            @test !validate_payload(schema_doc, missing_lat)
            @test !validate_payload(schema_doc, invalid_lon)
        end
    end
end

struct Item
    sku::String
    quantity::Int
end

struct Invoice
    invoice_id::String
    items::Vector{Item}
    total::Float64
end

@testset "end-to-end validation - invoice" begin
    ctx = SchemaContext()
    result = generate_schema(Invoice; ctx = ctx, simplify = false)
    doc = result.doc

    valid = Dict(
        "invoice_id" => "INV-001",
        "items" => [
            Dict("sku" => "ITEM1", "quantity" => 3),
            Dict("sku" => "ITEM2", "quantity" => 1),
        ],
        "total" => 99.99
    )
    empty_items = deepcopy(valid)
    empty_items["items"] = []
    missing_sku = deepcopy(valid)
    delete!(missing_sku["items"][1], "sku")
    invalid_total = deepcopy(valid)
    invalid_total["total"] = "ninety-nine"
    for (variant_name, schema_doc) in schema_variants(doc)
        @testset "schema=$variant_name" begin
            @test validate_payload(schema_doc, valid)
            @test validate_payload(schema_doc, empty_items)
            @test !validate_payload(schema_doc, missing_sku)
            @test !validate_payload(schema_doc, invalid_total)
        end
    end
end

struct NotificationPreferencesE2E
    user_id::String
    email::Union{String, Nothing}
    sms::Union{String, Nothing}
    push_enabled::Bool
    remarks::String
end

@testset "end-to-end validation - optional preferences" begin
    ctx = SchemaContext()
    register_optional_fields!(ctx, NotificationPreferencesE2E, :remarks)
    treat_union_nothing_as_optional!(ctx)
    result = generate_schema(NotificationPreferencesE2E; ctx = ctx, simplify = false)
    doc = result.doc

    valid = Dict(
        "user_id" => "user-1",
        "push_enabled" => true,
        "email" => "alerts@example.com",
        "sms" => "+1-555-1234"
    )
    missing_optional = deepcopy(valid)
    delete!(missing_optional, "email")
    delete!(missing_optional, "sms")
    with_remarks = deepcopy(valid)
    with_remarks["remarks"] = "Do not send overnight"
    # Optional fields should not accept null when treat_union_nothing_as_optional is enabled
    with_null_sms = Dict(
        "user_id" => "user-1",
        "push_enabled" => true,
        "sms" => nothing
    )
    missing_required = deepcopy(valid)
    delete!(missing_required, "push_enabled")
    wrong_email_type = deepcopy(valid)
    wrong_email_type["email"] = 12345
    wrong_remarks_type = deepcopy(valid)
    wrong_remarks_type["remarks"] = 7
    for (variant_name, schema_doc) in schema_variants(doc)
        @testset "schema=$variant_name" begin
            @test validate_payload(schema_doc, valid)
            @test validate_payload(schema_doc, missing_optional)
            @test validate_payload(schema_doc, with_remarks)
            @test !validate_payload(schema_doc, with_null_sms)
            @test !validate_payload(schema_doc, missing_required)
            @test !validate_payload(schema_doc, wrong_email_type)
            @test !validate_payload(schema_doc, wrong_remarks_type)
        end
    end
end

@enum TaskStatus begin
    todo
    in_progress
    done
end

struct Project
    name::String
    status::TaskStatus
    priority::Int
end

@testset "end-to-end validation - project with enum" begin
    ctx = SchemaContext()
    result = generate_schema(Project; ctx = ctx, simplify = false)
    doc = result.doc

    valid = Dict(
        "name" => "Build Feature",
        "status" => "todo",
        "priority" => 1
    )
    with_done = deepcopy(valid)
    with_done["status"] = "done"
    invalid_status = deepcopy(valid)
    invalid_status["status"] = "unknown"
    missing_name = deepcopy(valid)
    delete!(missing_name, "name")
    for (variant_name, schema_doc) in schema_variants(doc)
        @testset "schema=$variant_name" begin
            @test validate_payload(schema_doc, valid)
            @test validate_payload(schema_doc, with_done)
            @test !validate_payload(schema_doc, invalid_status)
            @test !validate_payload(schema_doc, missing_name)
        end
    end
end

struct LogLevel
    severity::Int
end

@testset "end-to-end validation - oneOf with description" begin
    using Struct2JSONSchema: register_field_override!, register_field_description!

    ctx = SchemaContext()

    register_field_override!(ctx, LogLevel, :severity) do ctx
        Dict(
            "oneOf" => [
                Dict("type" => "integer", "minimum" => 0, "maximum" => 5),
                Dict("type" => "string", "enum" => ["debug", "info", "warn", "error", "fatal"]),
            ]
        )
    end

    register_field_description!(ctx, LogLevel, :severity, "Log severity level")

    result = generate_schema(LogLevel; ctx = ctx, simplify = false)
    doc = result.doc
    @test isempty(result.unknowns)

    valid_int = Dict("severity" => 3)
    valid_str = Dict("severity" => "warn")
    invalid_range = Dict("severity" => 10)
    invalid_enum = Dict("severity" => "critical")

    for (variant_name, schema_doc) in schema_variants(doc)
        @testset "schema=$variant_name" begin
            @test validate_payload(schema_doc, valid_int)
            @test validate_payload(schema_doc, valid_str)
            @test !validate_payload(schema_doc, invalid_range)
            @test !validate_payload(schema_doc, invalid_enum)
        end
    end
end

