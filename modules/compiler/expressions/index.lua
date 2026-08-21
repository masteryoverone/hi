local Ast = require("modules.utils.ast");

return function(self, expression, funcDepth, numReturns)
    local scope = self.activeBlock.scope;
    local regs = {};
    for i = 1, numReturns do
        regs[i] = self:allocRegister();
        if i == 1 then
            local baseReg = self:compileExpression(expression.base, funcDepth, 1)[1];
            local indexReg = self:compileExpression(expression.index, funcDepth, 1)[1];



            local baseExpr = self:register(scope, baseReg)
            local indexExpr = self:register(scope, indexReg)
            self:addStatement(self:setRegister(scope, regs[i], Ast.IndexExpression(baseExpr, indexExpr)), { regs[i] },
                { baseReg, indexReg }, true);

            self:freeRegister(baseReg, false);
            self:freeRegister(indexReg, false);
        else
            self:addStatement(self:setRegister(scope, regs[i], Ast.NilExpression()), { regs[i] }, {}, false);
        end
    end
    return regs;
end;
