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

# Core types and generation
export SchemaContext, UnknownEntry
export generate_schema, generate_schema!

# Override system
export override!, override_type!, override_field!, override_abstract!

# Field configuration
export optional!, describe!, skip!, only!

# Auto-optional options
export auto_optional_nothing!, auto_optional_missing!, auto_optional_null!

# Default values
export defaultvalue!, defaultvalue_serializer!, defaultvalue_type_serializer!, defaultvalue_field_serializer!, defaultvalue_serialize

end
