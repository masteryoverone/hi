local Step = require("modules.utils.step");
local Ast = require("modules.utils.ast");
local Scope = require("modules.utils.scope");
local visitast = require("modules.utils.visitast");
local AstKind = Ast.AstKind;
local AddVararg = Step:extend();
AddVararg.Description = "This Step Adds Vararg to all Functions and anchors it with a capture so it cannot be trivially stripped";
AddVararg.Name = "Add Vararg";
AddVararg.SettingsDescriptor = {
	CaptureVararg = {
		name = "CaptureVararg",
		description = "Inject an anchored {...} capture at the top of each function so the newly added vararg is actually referenced (a dead vararg param is otherwise trivially removed by deobfuscators).",
		type = "boolean",
		default = true,
	},
}
function AddVararg:init(_)
end
function AddVararg:apply(ast)
	visitast(ast, nil, function(node)
		if node.kind == AstKind.FunctionDeclaration or node.kind == AstKind.LocalFunctionDeclaration or node.kind == AstKind.FunctionLiteralExpression then
			if #node.args < 1 or node.args[#node.args].kind ~= AstKind.VarargExpression then
				node.args[#node.args + 1] = Ast.VarargExpression();

				if self.CaptureVararg and node.body and node.body.scope then
					local scope = node.body.scope;
					local captureId = scope:addVariable();

					local capture = Ast.LocalVariableDeclaration(scope, { captureId }, {
						Ast.TableConstructorExpression({ Ast.TableEntry(Ast.VarargExpression()) })
					});

					local anchor = Ast.IfStatement(
						Ast.NotEqualsExpression(
							Ast.VariableExpression(scope, captureId),
							Ast.VariableExpression(scope, captureId)
						),
						Ast.Block({}, Scope:new(scope)),
						{}, nil);

					table.insert(node.body.statements, 1, anchor);
					table.insert(node.body.statements, 1, capture);
				end
			end
		end
	end)
end
return AddVararg;
