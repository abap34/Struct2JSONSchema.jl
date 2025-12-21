using Test
using Struct2JSONSchema: SchemaContext, generate_schema, register_optional_fields!, treat_union_nothing_as_optional!

include("./helpers/validator.jl")

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
    result = generate_schema(PurchaseOrderE2E; ctx = ctx)
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

    @test validate_payload(doc, valid_payload)

    with_note = deepcopy(valid_payload)
    with_note["notes"] = "Deliver after 5 PM"
    @test validate_payload(doc, with_note)

    other_status = deepcopy(valid_payload)
    other_status["status"] = "shipped"
    @test validate_payload(doc, other_status)

    missing_order_id = deepcopy(valid_payload)
    delete!(missing_order_id, "order_id")
    @test !validate_payload(doc, missing_order_id)

    missing_customer = deepcopy(valid_payload)
    delete!(missing_customer, "customer")
    @test !validate_payload(doc, missing_customer)

    invalid_quantity = deepcopy(valid_payload)
    invalid_quantity["lines"][1]["quantity"] = "two"
    @test !validate_payload(doc, invalid_quantity)

    extra_customer_field = deepcopy(valid_payload)
    extra_customer_field["customer"]["vip"] = true
    @test !validate_payload(doc, extra_customer_field)
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
    result = generate_schema(UserAccount; ctx = ctx)
    doc = result.doc

    valid = Dict(
        "username" => "john_doe",
        "contact" => Dict(
            "email" => "john@example.com",
            "phone" => "+1234567890"
        ),
        "age" => 30
    )
    @test validate_payload(doc, valid)

    missing_email = deepcopy(valid)
    delete!(missing_email["contact"], "email")
    @test !validate_payload(doc, missing_email)

    invalid_age = deepcopy(valid)
    invalid_age["age"] = "thirty"
    @test !validate_payload(doc, invalid_age)

    extra_field = deepcopy(valid)
    extra_field["premium"] = true
    @test !validate_payload(doc, extra_field)
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
    result = generate_schema(Store; ctx = ctx)
    doc = result.doc

    valid = Dict{String, Any}(
        "name" => "Main Store",
        "location" => Dict{String, Any}(
            "latitude" => 37.7749,
            "longitude" => -122.4194
        )
    )
    @test validate_payload(doc, valid)

    missing_lat = deepcopy(valid)
    delete!(missing_lat["location"], "latitude")
    @test !validate_payload(doc, missing_lat)

    invalid_lon = deepcopy(valid)
    invalid_lon["location"]["longitude"] = "west"
    @test !validate_payload(doc, invalid_lon)
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
    result = generate_schema(Invoice; ctx = ctx)
    doc = result.doc

    valid = Dict(
        "invoice_id" => "INV-001",
        "items" => [
            Dict("sku" => "ITEM1", "quantity" => 3),
            Dict("sku" => "ITEM2", "quantity" => 1),
        ],
        "total" => 99.99
    )
    @test validate_payload(doc, valid)

    empty_items = deepcopy(valid)
    empty_items["items"] = []
    @test validate_payload(doc, empty_items)

    missing_sku = deepcopy(valid)
    delete!(missing_sku["items"][1], "sku")
    @test !validate_payload(doc, missing_sku)

    invalid_total = deepcopy(valid)
    invalid_total["total"] = "ninety-nine"
    @test !validate_payload(doc, invalid_total)
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
    result = generate_schema(NotificationPreferencesE2E; ctx = ctx)
    doc = result.doc

    valid = Dict(
        "user_id" => "user-1",
        "push_enabled" => true,
        "email" => "alerts@example.com",
        "sms" => "+1-555-1234"
    )
    @test validate_payload(doc, valid)

    missing_optional = deepcopy(valid)
    delete!(missing_optional, "email")
    delete!(missing_optional, "sms")
    @test validate_payload(doc, missing_optional)

    with_remarks = deepcopy(valid)
    with_remarks["remarks"] = "Do not send overnight"
    @test validate_payload(doc, with_remarks)

    # Optional fields should not accept null when treat_union_nothing_as_optional is enabled
    with_null_sms = Dict(
        "user_id" => "user-1",
        "push_enabled" => true,
        "sms" => nothing
    )
    @test !validate_payload(doc, with_null_sms)

    missing_required = deepcopy(valid)
    delete!(missing_required, "push_enabled")
    @test !validate_payload(doc, missing_required)

    wrong_email_type = deepcopy(valid)
    wrong_email_type["email"] = 12345
    @test !validate_payload(doc, wrong_email_type)

    wrong_remarks_type = deepcopy(valid)
    wrong_remarks_type["remarks"] = 7
    @test !validate_payload(doc, wrong_remarks_type)
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
    result = generate_schema(Project; ctx = ctx)
    doc = result.doc

    valid = Dict(
        "name" => "Build Feature",
        "status" => "todo",
        "priority" => 1
    )
    @test validate_payload(doc, valid)

    with_done = deepcopy(valid)
    with_done["status"] = "done"
    @test validate_payload(doc, with_done)

    invalid_status = deepcopy(valid)
    invalid_status["status"] = "unknown"
    @test !validate_payload(doc, invalid_status)

    missing_name = deepcopy(valid)
    delete!(missing_name, "name")
    @test !validate_payload(doc, missing_name)
end
