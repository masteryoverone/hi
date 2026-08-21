local Enums = require("modules.utils.enums");
local util = require("modules.utils.util");
local Parser = require("modules.utils.parser");
local Unparser = require("modules.utils.unparser");
local logger = require("src.logger");

local NameGenerators = require("modules.utils.namegenerators");

local Steps = require("modules.utils.steps");
local LuaVersion = Enums.LuaVersion;

local isWindows = package and package.config and type(package.config) == "string" and package.config:sub(1, 1) == "\\";
local function gettime()
    if isWindows then
        return os.clock();
    else
        return os.time();
    end
end

local Pipeline = {
    NameGenerators = NameGenerators,
    Steps = Steps,
    DefaultSettings = {
        LuaVersion = LuaVersion.Lua51,
        PrettyPrint = false,
        Seed = 0,
        VarNamePrefix = "",
    }
}

local STEP_ORDER = {
    "NumbersToExpressions",
    "AntiTamper",
    "Vmify",
    "EncryptStrings",
    "ProxifyLocals",
    "AddVararg",
    "WrapInFunction",
}

function Pipeline:new(settings)
    local luaVersion = settings.luaVersion or settings.LuaVersion or Pipeline.DefaultSettings.LuaVersion;
    local conventions = Enums.Conventions[luaVersion];
    if (not conventions) then
        logger:error("The Lua Version \"" .. luaVersion
            ..
            "\" is not recognized by the Tokenizer! Please use one of the following: \"" ..
            table.concat(util.keys(Enums.Conventions), "\",\"") .. "\"");
    end

    local prettyPrint = settings.PrettyPrint or Pipeline.DefaultSettings.PrettyPrint;
    local prefix = settings.VarNamePrefix or Pipeline.DefaultSettings.VarNamePrefix;
    local seed = settings.Seed or 0;

    local pipeline = {
        LuaVersion = luaVersion,
        PrettyPrint = prettyPrint,
        VarNamePrefix = prefix,
        Seed = seed,
        parser = Parser:new({
            LuaVersion = luaVersion,
        }),
        unparser = Unparser:new({
            LuaVersion = luaVersion,
            PrettyPrint = prettyPrint,
            Highlight = settings.Highlight,
        }),
        namegenerator = Pipeline.NameGenerators.Il,
        conventions = conventions,
        steps = {},
    }

    setmetatable(pipeline, self);
    self.__index = self;

    return pipeline;
end

function Pipeline:fromConfig(config)
    config = config or {};
    local pipeline = Pipeline:new({
        LuaVersion = config.LuaVersion or LuaVersion.Lua51,
        PrettyPrint = config.PrettyPrint or false,
        VarNamePrefix = config.VarNamePrefix or "",
        Seed = config.Seed or 0,
    });

    pipeline:setNameGenerator(config.NameGenerator or "Il")

    local stepFlags = config.Steps or {};
    for _, name in ipairs(STEP_ORDER) do
        if stepFlags[name] then
            local constructor = pipeline.Steps[name];
            if not constructor then
                logger:error(string.format("The Step \"%s\" was not found!", name));
            end
            pipeline:addStep(constructor:new({ LuaVersion = pipeline.LuaVersion }));
        end
    end

    local watermark = config.Watermark;
    if type(watermark) == "string" and #watermark > 0 then
        local WatermarkStep = pipeline.Steps.Watermark;
        if WatermarkStep then
            pipeline:addStep(WatermarkStep:new({ Content = watermark }));
        end
    end

    return pipeline;
end

function Pipeline:addStep(step)
    table.insert(self.steps, step);
end

function Pipeline:resetSteps(_)
    self.steps = {};
end

function Pipeline:getSteps()
    return self.steps;
end

function Pipeline:setLuaVersion(luaVersion)
    local conventions = Enums.Conventions[luaVersion];
    if (not conventions) then
        logger:error("The Lua Version \"" .. luaVersion
            ..
            "\" is not recognized by the Tokenizer! Please use one of the following: \"" ..
            table.concat(util.keys(Enums.Conventions), "\",\"") .. "\"");
    end

    self.parser = Parser:new({
        luaVersion = luaVersion,
    });
    self.unparser = Unparser:new({
        luaVersion = luaVersion,
    });
    self.conventions = conventions;
end

function Pipeline:getLuaVersion()
    return self.luaVersion;
end

function Pipeline:setNameGenerator(nameGenerator)
    if (type(nameGenerator) == "string") then
        nameGenerator = Pipeline.NameGenerators[nameGenerator];
    end

    if (type(nameGenerator) == "function" or type(nameGenerator) == "table") then
        self.namegenerator = nameGenerator;
        return;
    else
        logger:error(
            "The Argument to Pipeline:setNameGenerator must be a valid NameGenerator function or function name e.g: \"mangled\"")
    end
end

function Pipeline:apply(code, filename)
    local startTime = gettime();
    filename = filename or "Anonymous Script";
    logger:info(string.format("Applying Obfuscation Pipeline to %s ...", filename));

    math.randomseed(self.Seed)

    logger:info("Parsing ...");
    local parserStartTime = gettime();

    local sourceLen = string.len(code);
    local ast = self.parser:parse(code);

    local parserTimeDiff = gettime() - parserStartTime;
    logger:info(string.format("Parsing Done in %.2f seconds", parserTimeDiff));

    for i, step in ipairs(self.steps) do
        local stepStartTime = gettime();
        logger:info(string.format("Applying Step \"%s\" ...", step.Name or "Unnamed"));
        local stepOptions = step._options or {};
        local newAst = step:apply(ast, stepOptions);
        if type(newAst) == "string" then
            logger:info(string.format("Step \"%s\" returned string", step.Name or "Unnamed"));
            return newAst;
        elseif type(newAst) == "table" then
            ast = newAst;
        end
        logger:info(string.format("Step \"%s\" Done in %.2f seconds", step.Name or "Unnamed", gettime() - stepStartTime));
    end

    self:renameVariables(ast);

    code = self:unparse(ast);

    local timeDiff = gettime() - startTime;
    logger:info(string.format("Obfuscation Done in %.2f seconds", timeDiff));

    logger:info(string.format("Generated Code size is %.2f%% of the Source Code size", (string.len(code) / sourceLen) *
        100))

    return code;
end

function Pipeline:unparse(ast)
    local startTime = gettime();
    logger:info("Generating Code ...");

    local unparsed = self.unparser:unparse(ast);

    local timeDiff = gettime() - startTime;
    logger:info(string.format("Code Generation Done in %.2f seconds", timeDiff));

    return unparsed;
end

function Pipeline:renameVariables(ast)
    local startTime = gettime();
    logger:info("Renaming Variables ...");


    local generatorFunction = self.namegenerator or Pipeline.NameGenerators.mangled;
    if (type(generatorFunction) == "table") then
        if (type(generatorFunction.prepare) == "function") then
            generatorFunction.prepare(ast);
        end
        generatorFunction = generatorFunction.generateName;
    end

    if not self.unparser:isValidIdentifier(self.VarNamePrefix) and #self.VarNamePrefix ~= 0 then
        logger:error(string.format("The Prefix \"%s\" is not a valid Identifier in %s", self.VarNamePrefix,
            self.LuaVersion));
    end

    local globalScope = ast.globalScope;
    globalScope:renameVariables({
        Keywords = self.conventions.Keywords,
        generateName = generatorFunction,
        prefix = self.VarNamePrefix,
    });

    local timeDiff = gettime() - startTime;
    logger:info(string.format("Renaming Done in %.2f seconds", timeDiff));
end

return Pipeline;
