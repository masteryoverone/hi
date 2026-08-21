local Step = require("modules.utils.step");
local Ast = require("modules.utils.ast");
local Scope = require("modules.utils.scope");

local WrapInFunction = Step:extend();
WrapInFunction.Description = "Wraps the entire script into an IIFE to encapsulate scope and break external access.";
WrapInFunction.Name = "Wrap in Function";

WrapInFunction.SettingsDescriptor = {
	Iterations = {
		name = "Iterations",
		description = "Number of nested wrapper layers",
		type = "number",
		default = 1,
	},
	PaddingCount = {
		name = "PaddingCount",
		description = "Number of nil arguments to pad the IIFE call with",
		type = "number",
		default = 36,
	},
}

function WrapInFunction:init(_) end

function WrapInFunction:apply(ast)
	for _ = 1, self.Iterations do
		local scope = Scope:new(ast.globalScope);
		ast.body.scope:setParent(scope);

		local callArgs = {};
		for _ = 1, self.PaddingCount do
			table.insert(callArgs, Ast.NilExpression());
		end
		table.insert(callArgs, Ast.VarargExpression());

		ast.body = Ast.Block({
			Ast.ReturnStatement({
				Ast.FunctionCallExpression(
					Ast.FunctionLiteralExpression(
						{ Ast.VarargExpression() },
						ast.body
					),
					callArgs
				)
			})
		}, scope);
	end
end

return WrapInFunction;
