local Ast = require("modules.utils.ast");
local Scope = require("modules.utils.scope");
local util = require("modules.utils.util");
local constants = require("modules.compiler.constants");
local AstKind = Ast.AstKind;
local MAX_REGS = constants.MAX_REGS;
return function(Compiler)
    local function hasAnyEntries(tbl)
        return type(tbl) == "table" and next(tbl) ~= nil;
    end
    local function unionLookupTables(a, b)
        local out = {};
        for k, v in pairs(a or {}) do
            out[k] = v;
        end
        for k, v in pairs(b or {}) do
            out[k] = v;
        end
        return out;
    end
    local function canMergeParallelAssignmentStatements(statA, statB)
        if type(statA) ~= "table" or type(statB) ~= "table" then
            return false;
        end
        if statA.usesUpvals or statB.usesUpvals then
            return false;
        end
        local a = statA.statement;
        local b = statB.statement;
        if type(a) ~= "table" or type(b) ~= "table" then
            return false;
        end
        if a.kind ~= AstKind.AssignmentStatement or b.kind ~= AstKind.AssignmentStatement then
            return false;
        end
        if type(a.lhs) ~= "table" or type(a.rhs) ~= "table" or type(b.lhs) ~= "table" or type(b.rhs) ~= "table" then
            return false;
        end
        if # a.lhs ~= # a.rhs or # b.lhs ~= # b.rhs then
            return false;
        end

        local function hasUnsafeRhs(rhsList)
            for _, rhsExpr in ipairs(rhsList) do
                if type(rhsExpr) ~= "table" then
                    return true;
                end
                local kind = rhsExpr.kind;
                if kind == AstKind.FunctionCallExpression or kind == AstKind.PassSelfFunctionCallExpression or kind == AstKind.VarargExpression then
                    return true;
                end
            end
            return false;
        end
        if hasUnsafeRhs(a.rhs) or hasUnsafeRhs(b.rhs) then
            return false;
        end
        local aReads = type(statA.reads) == "table" and statA.reads or {};
        local aWrites = type(statA.writes) == "table" and statA.writes or {};
        local bReads = type(statB.reads) == "table" and statB.reads or {};
        local bWrites = type(statB.writes) == "table" and statB.writes or {};

        if not hasAnyEntries(aWrites) and not hasAnyEntries(bWrites) then
            return false;
        end
        for r in pairs(aReads) do
            if bWrites[r] then
                return false;
            end
        end
        for r, b in pairs(aWrites) do
            if bWrites[r] or bReads[r] then
                return false;
            end
        end
        return true;
    end
    local function mergeParallelAssignmentStatements(statA, statB)
        local lhs = {};
        local rhs = {};
        local aLhs, bLhs = statA.statement.lhs, statB.statement.lhs;
        local aRhs, bRhs = statA.statement.rhs, statB.statement.rhs;
        for i = 1, # aLhs do
            lhs[i] = aLhs[i];
        end
        for i = 1, # bLhs do
            lhs[# aLhs + i] = bLhs[i];
        end
        for i = 1, # aRhs do
            rhs[i] = aRhs[i];
        end
        for i = 1, # bRhs do
            rhs[# aRhs + i] = bRhs[i];
        end
        return {
            statement = Ast.AssignmentStatement(lhs, rhs),
            writes = unionLookupTables(statA.writes, statB.writes),
            reads = unionLookupTables(statA.reads, statB.reads),
            usesUpvals = statA.usesUpvals or statB.usesUpvals,
        };
    end
    local function mergeAdjacentParallelAssignments(blockstats)
        local merged = {};
        local i = 1;
        while i <= # blockstats do
            local stat = blockstats[i];
            i = i + 1;
            while i <= # blockstats and canMergeParallelAssignmentStatements(stat, blockstats[i]) do
                stat = mergeParallelAssignmentStatements(stat, blockstats[i]);
                i = i + 1;
            end
            table.insert(merged, stat);
        end
        return merged;
    end
    function Compiler:emitContainerFuncBody()
        local blocks = {};
        for i, block in ipairs(self.blocks) do
            local id = block.id;
            local blockstats = block.statements;
            local mergedBlockStats = mergeAdjacentParallelAssignments(blockstats);
            blockstats = {};
            for _, stat in ipairs(mergedBlockStats) do
                table.insert(blockstats, stat.statement);
            end
            local block = {
                id = id,
                index = i,
                block = Ast.Block(blockstats, block.scope)
            }
            table.insert(blocks, block);
        end
        table.sort(blocks, function(a, b)
            return a.id < b.id
        end);

        -- Per-build random factors that make every VM structurally unique and
        -- defeat interpreter-semantic-testing (LuaHunt-style opcode recovery).
        local vmRNG = math.random(1, 2 ^ 31 - 1);
        local function vmRand()
            vmRNG = ((vmRNG * 1103515245 + 12345) % 2147483648);
            return vmRNG;
        end
        local opqA = math.random(1, 1000);

        -- Position decoding with an additive-obfuscation wrapper. (pos + A) - (A + key)
        -- evaluates to pos - key at runtime (== the raw block id), but the extra
        -- constants make the decode less immediately readable.
        local function posDecoded(scope)
            return Ast.SubExpression(
                Ast.AddExpression(self:pos(scope), Ast.NumberExpression(opqA)),
                Ast.NumberExpression(opqA + self.posKey));
        end

        -- Correct binary-search dispatch over the sorted block list. Blocks are
        -- entered with pos = blockId + posKey, so posDecoded() == blockId. Each
        -- split uses a bound between adjacent ids, so a position always routes to
        -- exactly one block. Randomization: split point + which side each branch
        -- takes (comparison direction), so the tree shape varies per build while
        -- remaining correct.
        local function buildDispatch(tb, l, r, pScope)
            if r < l then
                local emptyScope = Scope:new(pScope);
                return Ast.Block({}, emptyScope);
            end
            local len = r - l + 1;
            if len == 1 then
                tb[l].block.scope:setParent(pScope);
                return tb[l].block;
            end
            local mid = l + 1 + (vmRand() % (len - 1));  -- split in (l, r] so both sides non-empty
            local bound = math.floor((tb[mid - 1].id + tb[mid].id) / 2);
            local ifScope = Scope:new(pScope);
            local lBlock = buildDispatch(tb, l, mid - 1, ifScope);
            local rBlock = buildDispatch(tb, mid, r, ifScope);
            local condition = Ast.LessThanOrEqualsExpression(posDecoded(ifScope), Ast.NumberExpression(bound));
            if vmRand() % 2 == 0 then
                return Ast.Block({
                    Ast.IfStatement(condition, lBlock, {}, rBlock),
                }, ifScope);
            end
            return Ast.Block({
                Ast.IfStatement(Ast.GreaterThanExpression(posDecoded(ifScope), Ast.NumberExpression(bound)), rBlock, {}, lBlock),
            }, ifScope);
        end
        local whileBody = buildDispatch(blocks, 1, # blocks, self.containerFuncScope);
        if self.whileScope then
            self.whileScope:setParent(self.containerFuncScope);
        end
        self.whileScope:addReferenceToHigherScope(self.containerFuncScope, self.returnVar, 1);
        self.whileScope:addReferenceToHigherScope(self.containerFuncScope, self.posVar);
        self.containerFuncScope:addReferenceToHigherScope(self.scope, self.unpackVar);
        local declarations = {
            self.returnVar,
        }
        for i, var in pairs(self.registerVars) do
            if (i ~= MAX_REGS) then
                table.insert(declarations, var);
            end
        end
        local stats = {}
        if self.maxUsedRegister >= MAX_REGS then
            table.insert(stats, Ast.LocalVariableDeclaration(self.containerFuncScope, {
                self.registerVars[MAX_REGS]
            }, {
                Ast.TableConstructorExpression({})
            }));
        end
        table.insert(stats, Ast.LocalVariableDeclaration(self.containerFuncScope, util.shuffle(declarations), {}));
        table.insert(stats, Ast.WhileStatement(whileBody, Ast.VariableExpression(self.containerFuncScope, self.posVar)));
        table.insert(stats, Ast.AssignmentStatement({
            Ast.AssignmentVariable(self.containerFuncScope, self.posVar)
        }, {
            Ast.LenExpression(Ast.VariableExpression(self.containerFuncScope, self.detectGcCollectVar))
        }));
        table.insert(stats, Ast.ReturnStatement {
            Ast.FunctionCallExpression(Ast.VariableExpression(self.scope, self.unpackVar), {
                Ast.VariableExpression(self.containerFuncScope, self.returnVar)
            }),
        });
        return Ast.Block(stats, self.containerFuncScope);
    end
end
