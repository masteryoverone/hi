local Step = require("modules.utils.step");
local Ast = require("modules.utils.ast");
local Scope = require("modules.utils.scope");
local Watermark = Step:extend();
Watermark.Description = "Injects watermark text at the top of the obfuscated script.";
Watermark.Name = "Watermark";
Watermark.SettingsDescriptor = {
	Content = {
		name = "Content",
		description = "The watermark text to embed.",
		type = "string",
		default = "",
	},
	CustomVariable = {
		name = "CustomVariable",
		description = "The global variable used to store the resolved watermark string.",
		type = "string",
		default = "_WATERMARK",
	},
}
function Watermark:init(_)
end
function Watermark:apply(ast)
	if string.len(self.Content) == 0 then
		return
	end

	local body = ast.body;
	local scope = body.scope;
	local watermarkVar = scope:addVariable();
	local statement = Ast.LocalVariableDeclaration(scope, {
		watermarkVar
	}, {
		Ast.StringExpression(self.Content)
	});
	table.insert(body.statements, 1, statement);
	return ast;
end
return Watermark;