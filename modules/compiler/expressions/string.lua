local Ast = require("modules.utils.ast");

local function encodeString(compiler, scope, str)
    if #str == 0 then
        return Ast.StringExpression("");
    end
    local bytes = {};
    for j = 1, #str do
        bytes[j] = Ast.NumberExpression(string.byte(str, j));
    end
    return Ast.FunctionCallExpression(
        Ast.IndexExpression(
            Ast.IndexExpression(compiler:env(scope), Ast.StringExpression("string")),
            Ast.StringExpression("char")
        ),
        bytes
    );
end

return function(self, expression, funcDepth, numReturns)
    local scope = self.activeBlock.scope;
    local regs = {};
    for i = 1, numReturns, 1 do
        regs[i] = self:allocRegister();
        if i == 1 then
            local val = encodeString(self, scope, expression.value);
            self:addStatement(self:setRegister(scope, regs[i], val), {regs[i]}, {}, false);
        else
            self:addStatement(self:setRegister(scope, regs[i], Ast.NilExpression()), {regs[i]}, {}, false);
        end
    end
    return regs;
end;

