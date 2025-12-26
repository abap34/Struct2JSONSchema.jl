module Struct2JSONSchema

using SHA
using Logging
using OrderedCollections: OrderedDict
import Dates: Date, DateTime, Time
import Base: isstructtype

include("generation.jl")
include("api.jl")
include("simplification.jl")

export SchemaContext, generate_schema, generate_schema!, register_abstract!, register_override!, register_type_override!, register_field_override!, register_optional_fields!, register_field_description!, treat_union_nothing_as_optional!, treat_union_missing_as_optional!, treat_null_as_optional!

end
