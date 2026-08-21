local Ast = require("modules.utils.ast");
local Scope = require("modules.utils.scope");
local util = require("modules.utils.util");
local lookupify = util.lookupify;
local AstKind = Ast.AstKind;
local unpack = unpack or table.unpack;
local blockModule = require("modules.compiler.block");
local registerModule = require("modules.compiler.register");
local upvalueModule = require("modules.compiler.upvalue");
local emitModule = require("modules.compiler.emit");
local compileCoreModule = require("modules.compiler.compile_core");
local Compiler = {};
function Compiler:new()
    local compiler = {
        blocks = {},
        registers = {},
        activeBlock = nil,
        registersForVar = {},
        usedRegisters = 0,
        maxUsedRegister = 0,
        registerVars = {},
        VAR_REGISTER = newproxy(false),
        RETURN_ALL = newproxy(false),
        POS_REGISTER = newproxy(false),
        RETURN_REGISTER = newproxy(false),
        UPVALUE = newproxy(false),
        BIN_OPS = lookupify {
            AstKind.LessThanExpression,
            AstKind.GreaterThanExpression,
            AstKind.LessThanOrEqualsExpression,
            AstKind.GreaterThanOrEqualsExpression,
            AstKind.NotEqualsExpression,
            AstKind.EqualsExpression,
            AstKind.StrCatExpression,
            AstKind.AddExpression,
            AstKind.SubExpression,
            AstKind.MulExpression,
            AstKind.DivExpression,
            AstKind.ModExpression,
            AstKind.PowExpression,
        },
    };
    setmetatable(compiler, self);
    self.__index = self;
    return compiler;
end

blockModule(Compiler);
registerModule(Compiler);
upvalueModule(Compiler);
emitModule(Compiler);
compileCoreModule(Compiler);
function Compiler:pushRegisterUsageInfo()
    table.insert(self.registerUsageStack, {
        usedRegisters = self.usedRegisters,
        registers = self.registers,
    });
    self.usedRegisters = 0;
    self.registers = {};
end

function Compiler:popRegisterUsageInfo()
    local info = table.remove(self.registerUsageStack);
    self.usedRegisters = info.usedRegisters;
    self.registers = info.registers;
end

function Compiler:compile(ast)
    self.blocks = {};
    self.registers = {};
    self.activeBlock = nil;
    self.registersForVar = {};
    self.scopeFunctionDepths = {};
    self.maxUsedRegister = 0;
    self.usedRegisters = 0;
    self.registerVars = {};
    self.usedBlockIds = {};
    self.upvalVars = {};
    self.registerUsageStack = {};
    self.upvalsProxyLenReturn = -(math.random(1000000, 9999999));
    self.posKey = math.random(500000, 1500000);
    local newGlobalScope = Scope:newGlobal();
    local psc = Scope:new(newGlobalScope, nil);
    local _, getfenvVar = newGlobalScope:resolve("getfenv");
    local _, tableVar = newGlobalScope:resolve("table");
    local _, unpackVar = newGlobalScope:resolve("unpack");
    local _, envVar = newGlobalScope:resolve("_ENV");
    local _, newproxyVar = newGlobalScope:resolve("newproxy");
    local _, setmetatableVar = newGlobalScope:resolve("setmetatable");
    local _, getmetatableVar = newGlobalScope:resolve("getmetatable");
    local _, selectVar = newGlobalScope:resolve("select");
    local _, rawgetVar = newGlobalScope:resolve("rawget");
    local _, rawsetVar = newGlobalScope:resolve("rawset");
    psc:addReferenceToHigherScope(newGlobalScope, getfenvVar, 2);
    psc:addReferenceToHigherScope(newGlobalScope, tableVar);
    psc:addReferenceToHigherScope(newGlobalScope, unpackVar);
    psc:addReferenceToHigherScope(newGlobalScope, envVar);
    psc:addReferenceToHigherScope(newGlobalScope, newproxyVar);
    psc:addReferenceToHigherScope(newGlobalScope, setmetatableVar);
    psc:addReferenceToHigherScope(newGlobalScope, getmetatableVar);
    psc:addReferenceToHigherScope(newGlobalScope, rawgetVar);
    psc:addReferenceToHigherScope(newGlobalScope, rawsetVar);
    self.scope = Scope:new(psc);
    self.envVar = self.scope:addVariable();
    self.containerFuncVar = self.scope:addVariable();
    self.unpackVar = self.scope:addVariable();
    self.newproxyVar = self.scope:addVariable();
    self.setmetatableVar = self.scope:addVariable();
    self.getmetatableVar = self.scope:addVariable();
    self.selectVar = self.scope:addVariable();
    self.rawgetVar = self.scope:addVariable();
    self.rawsetVar = self.scope:addVariable();
    local argVar = self.scope:addVariable();
    self.containerFuncScope = Scope:new(self.scope);
    self.whileScope = Scope:new(self.containerFuncScope);
    self.posVar = self.containerFuncScope:addVariable();
    self.argsVar = self.containerFuncScope:addVariable();
    self.currentUpvaluesVar = self.containerFuncScope:addVariable();
    self.detectGcCollectVar = self.containerFuncScope:addVariable();
    self.returnVar = self.containerFuncScope:addVariable();
    self.upvaluesTable = self.scope:addVariable();
    self.upvaluesReferenceCountsTable = self.scope:addVariable();
    self.allocUpvalFunction = self.scope:addVariable();
    self.currentUpvalId = self.scope:addVariable();
    self.upvaluesProxyFunctionVar = self.scope:addVariable();
    self.upvaluesGcFunctionVar = self.scope:addVariable();
    self.freeUpvalueFunc = self.scope:addVariable();
    self.createClosureVars = {};
    self.createVarargClosureVar = self.scope:addVariable();
    local createClosureScope = Scope:new(self.scope);
    local createClosurePosArg = createClosureScope:addVariable();
    local createClosureUpvalsArg = createClosureScope:addVariable();
    local createClosureProxyObject = createClosureScope:addVariable();
    local createClosureFuncVar = createClosureScope:addVariable();
    local createClosureSubScope = Scope:new(createClosureScope);
    local upvalEntries = {};
    local upvalueIds = {};
    self.getUpvalueId = function(self, scope, id)
        local expression;
        local scopeFuncDepth = self.scopeFunctionDepths[scope];
        if (scopeFuncDepth == 0) then
            if upvalueIds[id] then
                return upvalueIds[id];
            end
            expression = Ast.FunctionCallExpression(Ast.VariableExpression(self.scope, self.allocUpvalFunction), {});
        else
            require("src.logger"):error("Unresolved Upvalue, this error should not occur!");
        end
        table.insert(upvalEntries, Ast.TableEntry(expression));
        local uid = # upvalEntries;
        upvalueIds[id] = uid;
        return uid;
    end
    createClosureSubScope:addReferenceToHigherScope(self.scope, self.containerFuncVar);
    createClosureSubScope:addReferenceToHigherScope(createClosureScope, createClosurePosArg)
    createClosureSubScope:addReferenceToHigherScope(createClosureScope, createClosureUpvalsArg, 1)
    createClosureScope:addReferenceToHigherScope(self.scope, self.upvaluesProxyFunctionVar)
    createClosureSubScope:addReferenceToHigherScope(createClosureScope, createClosureProxyObject);
    self.scopeFunctionDepths[self.scope] = 0;
    self:compileTopNode(ast);
    local functionNodeAssignments = {
        {
            var = Ast.AssignmentVariable(self.scope, self.containerFuncVar),
            val = Ast.FunctionLiteralExpression({
                Ast.VariableExpression(self.containerFuncScope, self.posVar),
                Ast.VariableExpression(self.containerFuncScope, self.argsVar),
                Ast.VariableExpression(self.containerFuncScope, self.currentUpvaluesVar),
                Ast.VariableExpression(self.containerFuncScope, self.detectGcCollectVar)
            }, self:emitContainerFuncBody()),
        },
        {
            var = Ast.AssignmentVariable(self.scope, self.createVarargClosureVar),
            val = Ast.FunctionLiteralExpression({
                Ast.VariableExpression(createClosureScope, createClosurePosArg),
                Ast.VariableExpression(createClosureScope, createClosureUpvalsArg),
            }, Ast.Block({
                Ast.LocalVariableDeclaration(createClosureScope, {
                    createClosureProxyObject
                }, {
                    Ast.FunctionCallExpression(Ast.VariableExpression(self.scope, self.upvaluesProxyFunctionVar), {
                        Ast.VariableExpression(createClosureScope, createClosureUpvalsArg)
                    })
                }),
                Ast.LocalVariableDeclaration(createClosureScope, {
                    createClosureFuncVar
                }, {
                    Ast.FunctionLiteralExpression({
                        Ast.VarargExpression(),
                    }, Ast.Block({
                        Ast.ReturnStatement {
                            Ast.FunctionCallExpression(Ast.VariableExpression(self.scope, self.containerFuncVar), {
                                Ast.VariableExpression(createClosureScope, createClosurePosArg),
                                Ast.TableConstructorExpression({
                                    Ast.TableEntry(Ast.VarargExpression())
                                }),
                                Ast.VariableExpression(createClosureScope, createClosureUpvalsArg),
                                Ast.VariableExpression(createClosureScope, createClosureProxyObject)
                            })
                        }
                    }, createClosureSubScope)),
                }),
                Ast.ReturnStatement {
                    Ast.VariableExpression(createClosureScope, createClosureFuncVar)
                },
            }, createClosureScope)),
        },
        {
            var = Ast.AssignmentVariable(self.scope, self.upvaluesTable),
            val = Ast.TableConstructorExpression({}),
        },
        {
            var = Ast.AssignmentVariable(self.scope, self.upvaluesReferenceCountsTable),
            val = Ast.TableConstructorExpression({}),
        },
        {
            var = Ast.AssignmentVariable(self.scope, self.allocUpvalFunction),
            val = self:createAllocUpvalFunction(),
        },
        {
            var = Ast.AssignmentVariable(self.scope, self.currentUpvalId),
            val = Ast.NumberExpression(0),
        },
        {
            var = Ast.AssignmentVariable(self.scope, self.upvaluesProxyFunctionVar),
            val = self:createUpvaluesProxyFunc(),
        },
        {
            var = Ast.AssignmentVariable(self.scope, self.upvaluesGcFunctionVar),
            val = self:createUpvaluesGcFunc(),
        },
        {
            var = Ast.AssignmentVariable(self.scope, self.freeUpvalueFunc),
            val = self:createFreeUpvalueFunc(),
        },
    }
    local tbl = {
        Ast.VariableExpression(self.scope, self.containerFuncVar),
        Ast.VariableExpression(self.scope, self.createVarargClosureVar),
        Ast.VariableExpression(self.scope, self.upvaluesTable),
        Ast.VariableExpression(self.scope, self.upvaluesReferenceCountsTable),
        Ast.VariableExpression(self.scope, self.allocUpvalFunction),
        Ast.VariableExpression(self.scope, self.currentUpvalId),
        Ast.VariableExpression(self.scope, self.upvaluesProxyFunctionVar),
        Ast.VariableExpression(self.scope, self.upvaluesGcFunctionVar),
        Ast.VariableExpression(self.scope, self.freeUpvalueFunc),
    };
    for i, entry in pairs(self.createClosureVars) do
        table.insert(functionNodeAssignments, entry);
        table.insert(tbl, Ast.VariableExpression(entry.var.scope, entry.var.id));
    end
    local assignmentStatLhs, assignmentStatRhs = {}, {};
    for i, v in ipairs(functionNodeAssignments) do
        assignmentStatLhs[i] = v.var;
        assignmentStatRhs[i] = v.val;
    end

    local items = {
        Ast.VariableExpression(self.scope, self.envVar),
        Ast.VariableExpression(self.scope, self.unpackVar),
        Ast.VariableExpression(self.scope, self.newproxyVar),
        Ast.VariableExpression(self.scope, self.setmetatableVar),
        Ast.VariableExpression(self.scope, self.getmetatableVar),
        Ast.VariableExpression(self.scope, self.selectVar),
        Ast.VariableExpression(self.scope, argVar),
        Ast.VariableExpression(self.scope, self.rawgetVar),
        Ast.VariableExpression(self.scope, self.rawsetVar),
    }
    local astItems = {
        Ast.OrExpression(
            Ast.AndExpression(Ast.VariableExpression(newGlobalScope, getfenvVar),
                Ast.FunctionCallExpression(Ast.VariableExpression(newGlobalScope, getfenvVar), {})),
            Ast.VariableExpression(newGlobalScope, envVar)),
        Ast.OrExpression(Ast.VariableExpression(newGlobalScope, unpackVar),
            Ast.IndexExpression(Ast.VariableExpression(newGlobalScope, tableVar), Ast.StringExpression("unpack"))),
        Ast.VariableExpression(newGlobalScope, newproxyVar),
        Ast.VariableExpression(newGlobalScope, setmetatableVar),
        Ast.VariableExpression(newGlobalScope, getmetatableVar),
        Ast.VariableExpression(newGlobalScope, selectVar),
        Ast.TableConstructorExpression({
            Ast.TableEntry(Ast.VarargExpression()),
        }),
        Ast.VariableExpression(newGlobalScope, rawgetVar),
        Ast.VariableExpression(newGlobalScope, rawsetVar),
    }
    local getfenvWrapperScope = Scope:new(self.scope);
    local getfenvWrapperFunc = Ast.FunctionLiteralExpression({}, Ast.Block({
        Ast.ReturnStatement {
            Ast.VariableExpression(self.scope, self.envVar)
        }
    }, getfenvWrapperScope));
    local setfenvWrapperScope = Scope:new(self.scope);
    local setfenvWrapperFunc = Ast.FunctionLiteralExpression({ Ast.VarargExpression() }, Ast.Block({
        Ast.ReturnStatement {
            Ast.VariableExpression(self.scope, self.envVar)
        }
    }, setfenvWrapperScope));
    local getmetatableWrapperScope = Scope:new(self.scope);
    local getmetatableWrapperArg = getmetatableWrapperScope:addVariable();
    getmetatableWrapperScope:addReferenceToHigherScope(self.scope, self.getmetatableVar);
    getmetatableWrapperScope:addReferenceToHigherScope(self.scope, self.rawgetVar);
    local getmetatableWrapperFunc = Ast.FunctionLiteralExpression({
        Ast.VariableExpression(getmetatableWrapperScope, getmetatableWrapperArg)
    }, Ast.Block({
        Ast.ReturnStatement {
            Ast.FunctionCallExpression(Ast.VariableExpression(self.scope, self.getmetatableVar), {
                Ast.VariableExpression(getmetatableWrapperScope, getmetatableWrapperArg)
            })
        }
    }, getmetatableWrapperScope));
    local functionNode = Ast.FunctionLiteralExpression({
        items[1],
        items[2],
        items[3],
        items[4],
        items[5],
        items[6],
        items[7],
        items[8],
        items[9],
        unpack(tbl)
    }, Ast.Block({
        Ast.AssignmentStatement({
            Ast.AssignmentVariable(self.scope, self.envVar)
        }, {
            Ast.FunctionCallExpression(Ast.VariableExpression(self.scope, self.setmetatableVar), {
                Ast.TableConstructorExpression({}),
                Ast.TableConstructorExpression({
                    Ast.KeyedTableEntry(Ast.StringExpression("__index"), Ast.VariableExpression(self.scope, self.envVar))
                })
            })
        }),
        Ast.AssignmentStatement({
            Ast.AssignmentIndexing(Ast.VariableExpression(self.scope, self.envVar), Ast.StringExpression("getfenv"))
        }, {
            getfenvWrapperFunc
        }),
        Ast.AssignmentStatement({
            Ast.AssignmentIndexing(Ast.VariableExpression(self.scope, self.envVar), Ast.StringExpression("setfenv"))
        }, {
            setfenvWrapperFunc
        }),
        Ast.AssignmentStatement({
            Ast.AssignmentIndexing(Ast.VariableExpression(self.scope, self.envVar), Ast.StringExpression("getmetatable"))
        }, {
            getmetatableWrapperFunc
        }),
        Ast.AssignmentStatement(assignmentStatLhs, assignmentStatRhs),
        Ast.ReturnStatement {
            Ast.FunctionCallExpression(Ast.FunctionCallExpression(Ast.VariableExpression(self.scope, self.createVarargClosureVar), {
                Ast.NumberExpression(self.startBlockId + self.posKey),
                Ast.TableConstructorExpression(upvalEntries),
            }), {
                Ast.FunctionCallExpression(Ast.VariableExpression(self.scope, self.unpackVar), {
                    Ast.VariableExpression(self.scope, argVar)
                })
            }),
        }
    }, self.scope));
    return Ast.TopNode(Ast.Block({
        Ast.ReturnStatement {
            Ast.FunctionCallExpression(functionNode, {
                astItems[1],
                astItems[2],
                astItems[3],
                astItems[4],
                astItems[5],
                astItems[6],
                astItems[7],
                astItems[8],
                astItems[9],
            })
        },
    }, psc), newGlobalScope);
end

function Compiler:getCreateClosureVar(argCount)
    if not self.createClosureVars[argCount] then
        local var = Ast.AssignmentVariable(self.scope, self.scope:addVariable());
        local createClosureScope = Scope:new(self.scope);
        local createClosureSubScope = Scope:new(createClosureScope);
        local createClosurePosArg = createClosureScope:addVariable();
        local createClosureUpvalsArg = createClosureScope:addVariable();
        local createClosureProxyObject = createClosureScope:addVariable();
        local createClosureFuncVar = createClosureScope:addVariable();
        createClosureSubScope:addReferenceToHigherScope(self.scope, self.containerFuncVar);
        createClosureSubScope:addReferenceToHigherScope(createClosureScope, createClosurePosArg)
        createClosureSubScope:addReferenceToHigherScope(createClosureScope, createClosureUpvalsArg, 1)
        createClosureScope:addReferenceToHigherScope(self.scope, self.upvaluesProxyFunctionVar)
        createClosureSubScope:addReferenceToHigherScope(createClosureScope, createClosureProxyObject);
        local argsTb, argsTb2 = {}, {};
        for i = 1, argCount do
            local arg = createClosureSubScope:addVariable()
            argsTb[i] = Ast.VariableExpression(createClosureSubScope, arg);
            argsTb2[i] = Ast.TableEntry(Ast.VariableExpression(createClosureSubScope, arg));
        end
        local val = Ast.FunctionLiteralExpression({
            Ast.VariableExpression(createClosureScope, createClosurePosArg),
            Ast.VariableExpression(createClosureScope, createClosureUpvalsArg),
        }, Ast.Block({
            Ast.LocalVariableDeclaration(createClosureScope, {
                createClosureProxyObject
            }, {
                Ast.FunctionCallExpression(Ast.VariableExpression(self.scope, self.upvaluesProxyFunctionVar), {
                    Ast.VariableExpression(createClosureScope, createClosureUpvalsArg)
                })
            }),
            Ast.LocalVariableDeclaration(createClosureScope, {
                createClosureFuncVar
            }, {
                Ast.FunctionLiteralExpression(argsTb, Ast.Block({
                    Ast.ReturnStatement {
                        Ast.FunctionCallExpression(Ast.VariableExpression(self.scope, self.containerFuncVar), {
                            Ast.VariableExpression(createClosureScope, createClosurePosArg),
                            Ast.TableConstructorExpression(argsTb2),
                            Ast.VariableExpression(createClosureScope, createClosureUpvalsArg),
                            Ast.VariableExpression(createClosureScope, createClosureProxyObject)
                        })
                    }
                }, createClosureSubScope)),
            }),
            Ast.ReturnStatement {
                Ast.VariableExpression(createClosureScope, createClosureFuncVar)
            }
        }, createClosureScope));
        self.createClosureVars[argCount] = {
            var = var,
            val = val,
        }
    end
    local var = self.createClosureVars[argCount].var;
    return var.scope, var.id;
end

return Compiler;
