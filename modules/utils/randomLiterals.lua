local Ast = require("modules.utils.ast");
local RandomLiterals = {};
function RandomLiterals.String(pipeline)
	return Ast.StringExpression("value");
end
function RandomLiterals.Dictionary()
	return Ast.StringExpression("default");
end
function RandomLiterals.Number()
	return Ast.NumberExpression(0);
end
function RandomLiterals.Any(pipeline)
	return RandomLiterals.String(pipeline);
end
return RandomLiterals;