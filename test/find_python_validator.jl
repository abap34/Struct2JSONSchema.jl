function find_python_validator()
    for name in ("python3", "python")
        executable = Sys.which(name)
        executable === nothing && continue
        cmd = Cmd([
            executable,
            "-c",
            "from jsonschema import Draft202012Validator"
        ])
        available = try
            success(pipeline(cmd; stdout = devnull, stderr = devnull))
        catch
            false
        end
        available && return executable
    end
    return ""
end
