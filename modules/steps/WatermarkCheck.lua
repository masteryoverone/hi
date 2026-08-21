local Step = require("modules.utils.step");
local Ast = require("modules.utils.ast");
local Scope = require("modules.utils.scope");
local Watermark = require("modules.steps.Watermark");

local WatermarkCheck = Step:extend();
WatermarkCheck.Description = "Adds a runtime check that aborts execution when the watermark is removed.";
WatermarkCheck.Name = "WatermarkCheck";

WatermarkCheck.SettingsDescriptor = {
	Content = {
		name = "Content",
		description = "The watermark text used both for embedding and verification.",
		type = "string",
		default = "Obfuscated By Hephaestus",
	},
}

local function callNameGenerator(generatorFunction, ...)
	if(type(generatorFunction) == "table") then
		generatorFunction = generatorFunction.generateName;
	end
	return generatorFunction(...);
end

function WatermarkCheck:init(_) end

function WatermarkCheck:apply(ast, pipeline)
	if string.len(self.Content) == 0 then
		return
	end

	self.CustomVariable = "_" .. callNameGenerator(pipeline.namegenerator, 10000000000);
	pipeline:addStep(Watermark:new(self));

	local body = ast.body;
	local watermarkExpression = Ast.StringExpression(self.Content);
	local _, variable = ast.globalScope:resolve(self.CustomVariable);
	local watermark = Ast.VariableExpression(ast.globalScope, variable);
	local notEqualsExpression = Ast.NotEqualsExpression(watermark, watermarkExpression);
	local ifBody = Ast.Block({Ast.ReturnStatement({})}, Scope:new(ast.body.scope));

	table.insert(body.statements, 1, Ast.IfStatement(notEqualsExpression, ifBody, {}, nil));
end

return WatermarkCheck;
