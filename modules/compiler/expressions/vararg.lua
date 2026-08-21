local Ast = require("modules.utils.ast");

return function(self, expression, funcDepth, numReturns)
    local scope = self.activeBlock.scope;
    if numReturns == self.RETURN_ALL then
        return {self.varargReg};
    end
    local regs = {};
    for i = 1, numReturns do
        regs[i] = self:allocRegister(false);
        self:addStatement(self:setRegister(scope, regs[i], Ast.IndexExpression(self:register(scope, self.varargReg), Ast.NumberExpression(i))), {regs[i]}, {self.varargReg}, false);
    end
    return regs;
end;

