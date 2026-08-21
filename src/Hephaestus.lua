if type(package) == "table" and type(package.path) == "string" then
    local source
    if debug.getinfo then
        source = debug.getinfo(2, "S").source
    elseif debug.info then
        source = debug.info(2, "s")
    end
    if source then
        local str = source:sub(source:find("^@") and 2 or 1)
        local dir = str:match("(.*[/%\\])") or "./"
        package.path = dir .. "?.lua;" .. package.path;
    end
end
do
    local ok = pcall(function()
        return math.random(1, 2 ^ 40);
    end)
    if not ok then
        local oldMathRandom = math.random;
        local ok2 = pcall(function()
            math.random = function(a, b)
                if not a and b then
                    return oldMathRandom();
                end
                if not b then
                    return math.random(1, a);
                end
                if a > b then
                    a, b = b, a;
                end
                local diff = b - a;
                assert(diff >= 0);
                if diff > 2 ^ 31 - 1 then
                    return math.floor(oldMathRandom() * diff + a);
                else
                    return oldMathRandom(a, b);
                end
            end
        end)
    end
end
if type(newproxy) ~= "function" then
    pcall(function()
        _G.newproxy = function(arg)
            if arg then
                return setmetatable({}, {});
            end
            return {};
        end
    end)
    if type(newproxy) ~= "function" then
        newproxy = function(arg)
            if arg then
                return setmetatable({}, {});
            end
            return {};
        end
    end
end
local Pipeline = require("modules.utils.pipeline");
local highlight = require("src.highlightlua");
local colors = require("src.colors");
local Logger = require("src.logger");
local Config = require("src.config");
local util = require("modules.utils.util");
if oldPkgPath then
	package.path = oldPkgPath;
end
return {
    Pipeline = Pipeline;
    colors = colors;
    Config = util.readonly(Config);
    Logger = Logger;
    highlight = highlight;
}