module Struct2JSONSchema

using SHA
using Logging
using OrderedCollections: OrderedDict
import Dates
import Dates: Date, DateTime, Time, datetime2unix
import Base: isstructtype

include("generation.jl")
include("api.jl")
include("defaults.jl")
include("simplification.jl")

export SchemaContext, UnknownEntry, generate_schema, generate_schema!, register_abstract!, register_override!, register_type_override!, register_field_override!, register_optional_fields!, register_field_description!, register_skip_fields!, register_only_fields!, treat_union_nothing_as_optional!, treat_union_missing_as_optional!, treat_null_as_optional!, register_defaults!, register_default_serializer!, register_default_type_serializer!, register_default_field_serializer!, default_serialize_for_schema

end
