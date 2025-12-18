using Test
using Struct2JSONSchema: SchemaContext, generate_schema

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
