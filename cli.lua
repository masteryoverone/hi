local function script_path()
    local source
    if debug.getinfo then
        source = debug.getinfo(2, "S").source
    elseif debug.info then
        source = debug.info(2, "s")
    else
        return "./"
    end
    local str = source:sub(source:find("^@") and 2 or 1)
    return str:match("(.*[/%\\])") or "./"
end
if type(package) == "table" and type(package.path) == "string" then
    package.path = script_path() .. "?.lua;" .. package.path
end



local _real_require = require
require = function(mod)
    if type(mod) ~= "string" then
        return _real_require(mod)
    end
    if mod:sub(1, 1) == "@" then
        return _real_require(mod)
    end
    local path = mod:gsub("%.", "/")
    if path:sub(1, 1) ~= "." then
        path = "./" .. path
    end
    return _real_require(path)
end

local function get_version()
    local version = os.getenv("HEPHAESTUS_VERSION")
    if version and version ~= "" then
        return version
    end
    return "dev"
end

local function print_help()
    print("Hephaestus Lua CLI")
    print("Usage: hephaestus [options] <input.lua>")
    print("")
    print("Options:")
    print("  --config, --c <file>   Use a custom config Lua file")
    print("  --out, --o <file>      Set output path")
    print("  --Lua51                Force Lua 5.1 target")
    print("  --LuaU                 Force LuaU target")
    print("  --pretty               Pretty print output")
    print("  --nocolors             Disable colored logs")
    print("  --saveerrors           Save parser errors to file")
    print("  --silent              Suppress non-error output")
    print("  --version, -v          Print CLI version")
    print("  --help, -h             Show this help text")
end

if arg[1] == "--version" or arg[1] == "-v" then
    print(get_version())
    os.exit(0)
end

if arg[1] == "--help" or arg[1] == "-h" or arg[1] == "help" then
    print_help()
    os.exit(0)
end

local Hephaestus = require("src.Hephaestus")
Hephaestus.Logger.logLevel = Hephaestus.Logger.LogLevel.Info
Hephaestus.Logger.errorCallback = function(...)
    local args = { ... }
    local message = table.concat(args, " ")
    io.stderr:write(Hephaestus.colors(Hephaestus.Config.NameUpper .. ": " .. message, "red") .. "\n")
    os.exit(1)
end

local function file_exists(file)
    local f = io.open(file, "rb")
    if f then
        f:close()
    end
    return f ~= nil
end

pcall(function()
    string.split = function(str, sep)
        local fields = {}
        local pattern = string.format("([^%s]+)", sep)
        str:gsub(pattern, function(c)
            fields[#fields + 1] = c
        end)
        return fields
    end
end)

local function lines_from(file)
    if not file_exists(file) then
        return {}
    end
    local lines = {}
    for line in io.lines(file) do
        lines[#lines + 1] = line
    end
    return lines
end

local function load_chunk(content, chunkName, environment)
    if type(loadstring) == "function" then
        local func, err = loadstring(content, chunkName)
        if not func then
            return nil, err
        end
        if environment and type(setfenv) == "function" then
            setfenv(func, environment)
        elseif environment and type(load) == "function" then
            return load(content, chunkName, "t", environment)
        end
        return func
    end

    if type(load) ~= "function" then
        return nil, "No load function available"
    end

    return load(content, chunkName, "t", environment)
end

local function load_config_file(filename)
    if not file_exists(filename) then
        Hephaestus.Logger:error(string.format('Config file "%s" not found', filename))
    end

    local content = table.concat(lines_from(filename), "\n")
    local func, err = load_chunk(content, "@" .. filename)
    if not func then
        Hephaestus.Logger:error(string.format('Failed to parse config "%s": %s', filename, tostring(err)))
    end

    local ok, result = pcall(func)
    if not ok then
        Hephaestus.Logger:error(string.format('Failed to run config "%s": %s', filename, tostring(result)))
    end
    if type(result) ~= "table" then
        Hephaestus.Logger:error(string.format('Config "%s" must return a table', filename))
    end

    return result
end

local function format_time(ms)
    if ms < 1 then
        return string.format("%.2fms", ms)
    elseif ms < 1000 then
        return string.format("%.0fms", ms)
    else
        return string.format("%.2fs", ms / 1000)
    end
end

local function format_size(size)
    if size < 1024 then
        return size .. "B"
    elseif size < 1024 * 1024 then
        return string.format("%.1fKB", size / 1024)
    else
        return string.format("%.1fMB", size / (1024 * 1024))
    end
end

local function run_cli()
    local config, sourceFile, outFile, luaVersion, prettyPrint, configFile, silent

    for _, v in ipairs(arg) do
        if v == "--silent" then
            silent = true
            break
        end
    end

    if silent then
        Hephaestus.Logger.logLevel = Hephaestus.Logger.LogLevel.Error
    else
        Hephaestus.colors.enabled = true
    end

    local i = 1
    while i <= #arg do
        local curr = arg[i]
        if curr:sub(1, 2) == "--" then
            if curr == "--config" or curr == "--c" then
                i = i + 1
                configFile = tostring(arg[i])
            elseif curr == "--out" or curr == "--o" then
                i = i + 1
                if outFile then
                    Hephaestus.Logger:warn("Output file specified multiple times")
                end
                outFile = arg[i]
            elseif curr == "--nocolors" then
                Hephaestus.colors.enabled = false
            elseif curr == "--silent" then
                silent = true
            elseif curr == "--Lua51" then
                luaVersion = "Lua51"
            elseif curr == "--LuaU" then
                luaVersion = "LuaU"
            elseif curr == "--pretty" then
                prettyPrint = true
            elseif curr == "--saveerrors" then
                Hephaestus.Logger.errorCallback = function(...)
                    local args = { ... }
                    local message = table.concat(args, " ")
                    io.stderr:write(Hephaestus.colors(Hephaestus.Config.NameUpper .. ": " .. message, "red") .. "\n")

                    local fileName = sourceFile and sourceFile:sub(-4) == ".lua" and
                        sourceFile:sub(0, -5) .. ".error.txt"
                        or (sourceFile or "input") .. ".error.txt"
                    local handle = io.open(fileName, "w")
                    if handle then
                        handle:write(message)
                        handle:close()
                    end

                    os.exit(1)
                end
            elseif curr == "--CI" or curr == "--FullVersion" then
            else
                Hephaestus.Logger:warn(string.format('Unknown option "%s"', curr))
            end
        else
            if sourceFile then
                Hephaestus.Logger:error(string.format('Unexpected argument "%s"', arg[i]))
            end
            sourceFile = tostring(arg[i])
        end
        i = i + 1
    end

    if not sourceFile then
        Hephaestus.Logger:error("No input file specified")
    end

    if not file_exists(sourceFile) then
        Hephaestus.Logger:error(string.format('Input file "%s" not found', sourceFile))
    end

    if configFile then
        config = load_config_file(configFile)
    else
        local defaultConfig = script_path() .. "config.lua"
        if file_exists(defaultConfig) then
            config = load_config_file(defaultConfig)
        else
            config = {}
            for k, v in pairs(Hephaestus.Config) do
                config[k] = v
            end
        end
    end

    config.LuaVersion = luaVersion or config.LuaVersion
    config.PrettyPrint = prettyPrint ~= nil and prettyPrint or config.PrettyPrint

    if not outFile then
        if sourceFile:sub(-4) == ".lua" then
            outFile = sourceFile:sub(0, -5) .. ".obfuscated.lua"
        else
            outFile = sourceFile .. ".obfuscated.lua"
        end
    end

    local startTime = os.clock() * 1000

    if not silent then
        print(Hephaestus.colors("[Hephaestus]", "green"))
    end

    local source = table.concat(lines_from(sourceFile), "\n")
    local sourceSize = #source
    local pipeline = Hephaestus.Pipeline:fromConfig(config)
    local out = pipeline:apply(source, sourceFile)

    local elapsed = (os.clock() * 1000) - startTime
    local outSize = #out

    if not silent then
        local percent = sourceSize > 0 and string.format("%.0f", (outSize / sourceSize) * 100) or "0"
        print(Hephaestus.colors("[DONE]", "green") ..
            " " ..
            format_time(elapsed) ..
            " | " .. format_size(sourceSize) .. " -> " .. format_size(outSize) .. " (" .. percent .. "%)")
        print(Hephaestus.colors("[OUT]", "green") .. " " .. outFile)
    end

    local handle = io.open(outFile, "w")
    handle:write(out)
    handle:close()
end

local ok, err = xpcall(run_cli, function(e)
    return tostring(e)
end)
if not ok then
    local message = tostring(err):gsub("^.-:%d+:%s*", "")
    io.stderr:write(Hephaestus.colors(Hephaestus.Config.NameUpper .. ": " .. message, "red") .. "\n")
    os.exit(1)
end
