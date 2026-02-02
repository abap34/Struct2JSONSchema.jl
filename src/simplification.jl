# Apply all simplification transformations to a schema document
function simplify_schema(doc::Dict)
    return doc |> simplify_single_element_combinators |> remove_empty_required |> inline_single_use_refs |> simplify_single_element_combinators |> remove_unused_defs |> sort_defs
end

# Remove definitions from $defs that are not referenced from the root or other definitions
function remove_unused_defs(doc::Dict)::Dict
    defs = get(doc, SCHEMA_DEFS_KEY, Dict())
    isempty(defs) && return doc

    used_keys = Set{String}()

    if haskey(doc, SCHEMA_REF_KEY)
        ref = doc[SCHEMA_REF_KEY]
        if ref isa String && is_schema_ref(ref)
            key = extract_ref_key(ref)
            collect_used_keys!(key, defs, used_keys)
        end
    end

    new_defs = Dict{String, Any}(
        key => defs[key] for key in used_keys if haskey(defs, key)
    )

    result = copy(doc)
    if isempty(new_defs)
        delete!(result, SCHEMA_DEFS_KEY)
    else
        result[SCHEMA_DEFS_KEY] = new_defs
    end
    return result
end

function collect_used_keys!(key::String, defs::AbstractDict, used::Set{String})
    key in used && return
    push!(used, key)

    haskey(defs, key) || return
    schema = defs[key]

    return collect_refs_in_schema!(schema, defs, used)
end

function collect_refs_in_schema!(schema::Any, defs::AbstractDict, used::Set{String})
    return if schema isa Dict
        for (k, v) in schema
            if k == SCHEMA_REF_KEY && v isa String && is_schema_ref(v)
                ref_key = extract_ref_key(v)
                collect_used_keys!(ref_key, defs, used)
            else
                collect_refs_in_schema!(v, defs, used)
            end
        end
    elseif schema isa Vector
        for item in schema
            collect_refs_in_schema!(item, defs, used)
        end
    end
end

# Replace {"anyOf": [x]} with x, and {"allOf": [x]} with x (only when there are no other keys)
function simplify_single_element_combinators(schema::Any)::Any
    if !(schema isa Dict)
        return schema
    end

    result = Dict{String, Any}(
        k => simplify_single_element_combinators(v) for (k, v) in schema
    )

    if length(result) == 1
        if haskey(result, "anyOf") && result["anyOf"] isa Vector && length(result["anyOf"]) == 1
            return result["anyOf"][1]
        elseif haskey(result, "allOf") && result["allOf"] isa Vector && length(result["allOf"]) == 1
            return result["allOf"][1]
        end
    end

    return result
end

# Remove "required": [] entries from schemas
function remove_empty_required(schema::Any)::Any
    if !(schema isa Dict)
        return schema
    end

    return Dict{String, Any}(
        k => remove_empty_required(v)
            for (k, v) in schema
            if !(k == "required" && v isa Vector && isempty(v))
    )
end

# Inline definitions that are referenced exactly once, are not recursive, and are not simple primitive types
function inline_single_use_refs(doc::Dict)::Dict
    defs = get(doc, SCHEMA_DEFS_KEY, Dict())
    isempty(defs) && return doc

    root_ref_key = nothing
    if haskey(doc, SCHEMA_REF_KEY)
        ref = doc[SCHEMA_REF_KEY]
        if ref isa String && is_schema_ref(ref)
            root_ref_key = extract_ref_key(ref)
        end
    end

    ref_counts = count_references_in_defs(defs)

    recursive_keys = find_recursive_defs(defs)

    inline_targets = Set(
        key for (key, count) in ref_counts
            if key != root_ref_key &&
            count == 1 &&
            !(key in recursive_keys) &&
            !is_simple_primitive(get(defs, key, Dict()))
    )

    result = inline_refs_in_doc(doc, defs, inline_targets)

    if haskey(result, SCHEMA_DEFS_KEY)
        new_defs = Dict{String, Any}(
            k => v for (k, v) in result[SCHEMA_DEFS_KEY] if !(k in inline_targets)
        )
        if isempty(new_defs)
            delete!(result, SCHEMA_DEFS_KEY)
        else
            result[SCHEMA_DEFS_KEY] = new_defs
        end
    end

    return result
end

function count_references_in_defs(defs::AbstractDict)::Dict{String, Int}
    counts = Dict{String, Int}(key => 0 for key in keys(defs))

    for (_, schema) in defs
        count_refs_in_schema!(schema, counts)
    end
    return counts
end

function count_refs_in_schema!(schema::Any, counts::Dict{String, Int})
    return if schema isa Dict
        for (k, v) in schema
            if k == SCHEMA_REF_KEY && v isa String && is_schema_ref(v)
                ref_key = extract_ref_key(v)
                if haskey(counts, ref_key)
                    counts[ref_key] += 1
                end
            else
                count_refs_in_schema!(v, counts)
            end
        end
    elseif schema isa Vector
        for item in schema
            count_refs_in_schema!(item, counts)
        end
    end
end

function find_recursive_defs(defs::AbstractDict)::Set{String}
    return Set(key for key in keys(defs) if is_recursive(key, defs, Set{String}()))
end

function is_recursive(key::String, defs::AbstractDict, visiting::Set{String})::Bool
    key in visiting && return true
    haskey(defs, key) || return false

    push!(visiting, key)
    schema = defs[key]
    # Check if any $ref in this schema leads to a cycle
    result = has_cycle_in_refs(schema, defs, visiting)
    delete!(visiting, key)

    return result
end

function has_cycle_in_refs(schema::Any, defs::AbstractDict, visiting::Set{String})::Bool
    if schema isa Dict
        for (k, v) in schema
            if k == SCHEMA_REF_KEY && v isa String && is_schema_ref(v)
                ref_key = extract_ref_key(v)
                # If ref_key is currently being visited, we have a cycle
                if ref_key in visiting
                    return true
                end
                # Only follow the reference to check for cycles in the same path
                # Don't mark a type as recursive just because it references another recursive type
                if haskey(defs, ref_key)
                    # Temporarily add ref_key to visiting and check its schema
                    push!(visiting, ref_key)
                    if has_cycle_in_refs(defs[ref_key], defs, visiting)
                        delete!(visiting, ref_key)
                        return true
                    end
                    delete!(visiting, ref_key)
                end
            else
                if has_cycle_in_refs(v, defs, visiting)
                    return true
                end
            end
        end
    elseif schema isa Vector
        for item in schema
            if has_cycle_in_refs(item, defs, visiting)
                return true
            end
        end
    end
    return false
end

# Legacy function kept for backwards compatibility
function check_refs_for_key(schema::Any, target_key::String, defs::AbstractDict, visiting::Set{String})::Bool
    if schema isa Dict
        for (k, v) in schema
            if k == SCHEMA_REF_KEY && v isa String && is_schema_ref(v)
                ref_key = extract_ref_key(v)
                if ref_key == target_key
                    return true
                end
            else
                if check_refs_for_key(v, target_key, defs, visiting)
                    return true
                end
            end
        end
    elseif schema isa Vector
        for item in schema
            if check_refs_for_key(item, target_key, defs, visiting)
                return true
            end
        end
    end
    return false
end

function is_simple_primitive(schema::Dict)::Bool
    haskey(schema, "type") || return false
    type_val = schema["type"]
    type_val in ["string", "integer", "number", "boolean", "null", "array"] || return false

    constraint_keys = [
        "minLength", "maxLength", "minimum", "maximum", "pattern",
        "format", "minItems", "maxItems", "items", "enum", "const",
    ]

    any(key -> haskey(schema, key), constraint_keys) && return false

    return length(schema) == 1
end

function inline_refs_in_doc(doc::Dict, defs::AbstractDict, inline_targets::Set{String})::Dict
    result = Dict{String, Any}()

    for (k, v) in doc
        if k == SCHEMA_DEFS_KEY
            result[k] = Dict{String, Any}(
                def_key => inline_refs_in_schema(def_schema, defs, inline_targets)
                    for (def_key, def_schema) in v
            )
        else
            result[k] = inline_refs_in_schema(v, defs, inline_targets)
        end
    end

    return result
end

function inline_refs_in_schema(schema::Any, defs::AbstractDict, inline_targets::Set{String})::Any
    # Handle non-Dict types
    schema isa Dict || return schema isa Vector ?
        map(item -> inline_refs_in_schema(item, defs, inline_targets), schema) : schema

    # Try to inline $ref if applicable
    ref_key = extract_inlinable_ref_key(schema, inline_targets, defs)
    if !isnothing(ref_key)
        return inline_ref_with_metadata(schema, ref_key, defs, inline_targets)
    end

    # Normal recursive processing
    return Dict{String, Any}(k => inline_refs_in_schema(v, defs, inline_targets) for (k, v) in schema)
end

# Extract the ref key if this schema contains an inlinable $ref
function extract_inlinable_ref_key(schema::Dict, inline_targets::Set{String}, defs::AbstractDict)::Union{String, Nothing}
    haskey(schema, SCHEMA_REF_KEY) || return nothing

    ref = schema[SCHEMA_REF_KEY]
    ref isa String && is_schema_ref(ref) || return nothing

    ref_key = extract_ref_key(ref)
    return ref_key in inline_targets && haskey(defs, ref_key) ? ref_key : nothing
end

# Inline a $ref and merge any additional metadata from the wrapper schema
function inline_ref_with_metadata(schema::Dict, ref_key::String, defs::AbstractDict, inline_targets::Set{String})::Any
    # Recursively inline the referenced definition
    inlined = inline_refs_in_schema(defs[ref_key], defs, inline_targets)

    # Collect metadata: all properties except $ref, recursively processed
    metadata = Dict{String, Any}(
        k => inline_refs_in_schema(v, defs, inline_targets)
            for (k, v) in schema if k != SCHEMA_REF_KEY
    )

    # Merge: metadata takes precedence over inlined properties
    return inlined isa Dict ? merge(inlined, metadata) : inlined
end

# Sort $defs keys: primitives first (alphabetically), then by dependency order, then alphabetically
function sort_defs(doc::Dict)::Dict
    haskey(doc, SCHEMA_DEFS_KEY) || return doc
    defs = doc[SCHEMA_DEFS_KEY]
    isempty(defs) && return doc

    sorted_keys = sort_defs_keys(defs)

    sorted_defs = OrderedDict{String, Any}(key => defs[key] for key in sorted_keys)

    return Dict{String, Any}(
        k => (k == SCHEMA_DEFS_KEY ? sorted_defs : v) for (k, v) in doc
    )
end

function sort_defs_keys(defs::AbstractDict)::Vector{String}
    keys_list = collect(keys(defs))

    primitive_keys = sort!(filter(key -> is_primitive_def(defs[key]), keys_list))
    non_primitive_keys = filter(key -> !is_primitive_def(defs[key]), keys_list)

    if !isempty(non_primitive_keys)
        sorted_non_primitives = topological_sort_keys(non_primitive_keys, defs)
        return vcat(primitive_keys, sorted_non_primitives)
    else
        return primitive_keys
    end
end

function is_primitive_def(schema::Dict)::Bool
    haskey(schema, "enum") && return true

    if haskey(schema, "type")
        type_val = schema["type"]
        if type_val in ["string", "integer", "number", "boolean", "null"]
            return true
        elseif type_val == "array" && !haskey(schema, "items")
            return true
        end
    end

    return false
end

function topological_sort_keys(keys::Vector{String}, defs::AbstractDict)::Vector{String}
    deps = Dict{String, Vector{String}}(
        key => find_dependencies(defs[key], keys) for key in keys
    )

    reverse_deps = Dict{String, Vector{String}}(key => String[] for key in keys)

    for (from_key, dep_list) in deps
        for dep_key in dep_list
            if haskey(reverse_deps, dep_key)
                push!(reverse_deps[dep_key], from_key)
            end
        end
    end

    in_degree = Dict{String, Int}(key => length(deps[key]) for key in keys)

    queue = sort!([key for key in keys if in_degree[key] == 0])

    result = String[]
    while !isempty(queue)
        current = popfirst!(queue)
        push!(result, current)

        next_level = String[]
        for dependent_key in reverse_deps[current]
            in_degree[dependent_key] -= 1
            if in_degree[dependent_key] == 0
                push!(next_level, dependent_key)
            end
        end
        sort!(next_level)
        append!(queue, next_level)
    end

    return result
end

function find_dependencies(schema::Any, valid_keys::Vector{String})::Vector{String}
    deps = String[]
    find_dependencies_recursive!(schema, deps, valid_keys)
    return unique(deps)
end

function find_dependencies_recursive!(schema::Any, deps::Vector{String}, valid_keys::Vector{String})
    return if schema isa Dict
        for (k, v) in schema
            if k == SCHEMA_REF_KEY && v isa String && is_schema_ref(v)
                ref_key = extract_ref_key(v)
                if ref_key in valid_keys
                    push!(deps, ref_key)
                end
            else
                find_dependencies_recursive!(v, deps, valid_keys)
            end
        end
    elseif schema isa Vector
        for item in schema
            find_dependencies_recursive!(item, deps, valid_keys)
        end
    end
end

# Expand all $refs inline, removing the $defs section entirely
# Recursive definitions remain in $defs; others are fully inlined
function expand_all_defs(doc::Dict)::Dict
    defs = get(doc, SCHEMA_DEFS_KEY, Dict())
    if isempty(defs)
        # Remove empty $defs if it exists
        result = copy(doc)
        delete!(result, SCHEMA_DEFS_KEY)
        return result
    end

    # Find recursive definitions - these must stay in $defs
    recursive_keys = find_recursive_defs(defs)

    # All non-recursive keys can be inlined
    inline_targets = Set(key for key in keys(defs) if !(key in recursive_keys))

    # Inline all non-recursive refs
    result = inline_refs_in_doc(doc, defs, inline_targets)

    # Expand root $ref if it's non-recursive
    if haskey(result, SCHEMA_REF_KEY)
        ref = result[SCHEMA_REF_KEY]
        if ref isa String && is_schema_ref(ref)
            ref_key = extract_ref_key(ref)
            if ref_key in inline_targets && haskey(defs, ref_key)
                # Replace root $ref with the expanded definition
                expanded = inline_refs_in_schema(defs[ref_key], defs, inline_targets)
                delete!(result, SCHEMA_REF_KEY)
                # Merge expanded schema into result (preserving $schema and other metadata)
                for (k, v) in expanded
                    if k != SCHEMA_DEFS_KEY
                        result[k] = v
                    end
                end
            end
        end
    end

    # Remove inlined definitions from $defs
    if haskey(result, SCHEMA_DEFS_KEY)
        new_defs = Dict{String, Any}(
            k => v for (k, v) in result[SCHEMA_DEFS_KEY] if !(k in inline_targets)
        )
        if isempty(new_defs)
            delete!(result, SCHEMA_DEFS_KEY)
        else
            result[SCHEMA_DEFS_KEY] = new_defs
        end
    end

    return result
end
