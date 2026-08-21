local Ast = require("modules.utils.ast");
local Scope = require("modules.utils.scope");
local util = require("modules.utils.util");
local unpack = unpack or table.unpack;
return function(Compiler)
    function Compiler:createUpvaluesGcFunc()
        local scope = Scope:new(self.scope);
        local selfVar = scope:addVariable();
        local iteratorVar = scope:addVariable();
        local valueVar = scope:addVariable();
        local whileScope = Scope:new(scope);
        whileScope:addReferenceToHigherScope(self.scope, self.upvaluesReferenceCountsTable, 3);
        whileScope:addReferenceToHigherScope(scope, valueVar, 3);
        whileScope:addReferenceToHigherScope(scope, iteratorVar, 3);
        local ifScope = Scope:new(whileScope);
        ifScope:addReferenceToHigherScope(self.scope, self.upvaluesReferenceCountsTable, 1);
        ifScope:addReferenceToHigherScope(self.scope, self.upvaluesTable, 1);
        return Ast.FunctionLiteralExpression({
            Ast.VariableExpression(scope, selfVar)
        }, Ast.Block({
            Ast.LocalVariableDeclaration(scope, {
                iteratorVar,
                valueVar
            }, {
                Ast.NumberExpression(1),
                Ast.IndexExpression(Ast.VariableExpression(scope, selfVar), Ast.NumberExpression(1))
            }),
            Ast.WhileStatement(Ast.Block({
                Ast.AssignmentStatement({
                    Ast.AssignmentIndexing(Ast.VariableExpression(self.scope, self.upvaluesReferenceCountsTable), Ast.VariableExpression(scope, valueVar)),
                    Ast.AssignmentVariable(scope, iteratorVar),
                }, {
                    Ast.SubExpression(Ast.IndexExpression(Ast.VariableExpression(self.scope, self.upvaluesReferenceCountsTable), Ast.VariableExpression(scope, valueVar)), Ast.NumberExpression(1)),
                    Ast.AddExpression(unpack(util.shuffle{
                        Ast.VariableExpression(scope, iteratorVar),
                        Ast.NumberExpression(1)
                    })),
                }),
                Ast.IfStatement(Ast.EqualsExpression(unpack(util.shuffle{
                    Ast.IndexExpression(Ast.VariableExpression(self.scope, self.upvaluesReferenceCountsTable), Ast.VariableExpression(scope, valueVar)),
                    Ast.NumberExpression(0)
                })), Ast.Block({
                    Ast.AssignmentStatement({
                        Ast.AssignmentIndexing(Ast.VariableExpression(self.scope, self.upvaluesReferenceCountsTable), Ast.VariableExpression(scope, valueVar)),
                        Ast.AssignmentIndexing(Ast.VariableExpression(self.scope, self.upvaluesTable), Ast.VariableExpression(scope, valueVar)),
                    }, {
                        Ast.NilExpression(),
                        Ast.NilExpression(),
                    })
                }, ifScope), {}, nil),
                Ast.AssignmentStatement({
                    Ast.AssignmentVariable(scope, valueVar),
                }, {
                    Ast.IndexExpression(Ast.VariableExpression(scope, selfVar), Ast.VariableExpression(scope, iteratorVar)),
                }),
            }, whileScope), Ast.VariableExpression(scope, valueVar), scope);
        }, scope));
    end
    function Compiler:createFreeUpvalueFunc()
        local scope = Scope:new(self.scope);
        local argVar = scope:addVariable();
        local ifScope = Scope:new(scope);
        ifScope:addReferenceToHigherScope(scope, argVar, 3);
        scope:addReferenceToHigherScope(self.scope, self.upvaluesReferenceCountsTable, 2);
        return Ast.FunctionLiteralExpression({
            Ast.VariableExpression(scope, argVar)
        }, Ast.Block({
            Ast.AssignmentStatement({
                Ast.AssignmentIndexing(Ast.VariableExpression(self.scope, self.upvaluesReferenceCountsTable), Ast.VariableExpression(scope, argVar))
            }, {
                Ast.SubExpression(Ast.IndexExpression(Ast.VariableExpression(self.scope, self.upvaluesReferenceCountsTable), Ast.VariableExpression(scope, argVar)), Ast.NumberExpression(1));
            }),
            Ast.IfStatement(Ast.EqualsExpression(unpack(util.shuffle{
                Ast.IndexExpression(Ast.VariableExpression(self.scope, self.upvaluesReferenceCountsTable), Ast.VariableExpression(scope, argVar)),
                Ast.NumberExpression(0)
            })), Ast.Block({
                Ast.AssignmentStatement({
                    Ast.AssignmentIndexing(Ast.VariableExpression(self.scope, self.upvaluesReferenceCountsTable), Ast.VariableExpression(scope, argVar)),
                    Ast.AssignmentIndexing(Ast.VariableExpression(self.scope, self.upvaluesTable), Ast.VariableExpression(scope, argVar)),
                }, {
                    Ast.NilExpression(),
                    Ast.NilExpression(),
                })
            }, ifScope), {}, nil)
        }, scope))
    end
    function Compiler:createUpvaluesProxyFunc()
        local scope = Scope:new(self.scope);
        scope:addReferenceToHigherScope(self.scope, self.newproxyVar);
        local entriesVar = scope:addVariable();
        local ifScope = Scope:new(scope);
        local proxyVar = ifScope:addVariable();
        local metatableVar = ifScope:addVariable();
        local elseScope = Scope:new(scope);
        ifScope:addReferenceToHigherScope(self.scope, self.newproxyVar);
        ifScope:addReferenceToHigherScope(self.scope, self.getmetatableVar);
        ifScope:addReferenceToHigherScope(self.scope, self.upvaluesGcFunctionVar);
        ifScope:addReferenceToHigherScope(self.scope, self.rawgetVar);
        ifScope:addReferenceToHigherScope(scope, entriesVar);
        elseScope:addReferenceToHigherScope(self.scope, self.setmetatableVar);
        elseScope:addReferenceToHigherScope(scope, entriesVar);
        elseScope:addReferenceToHigherScope(self.scope, self.upvaluesGcFunctionVar);
        elseScope:addReferenceToHigherScope(self.scope, self.rawgetVar);
        local forScope = Scope:new(scope);
        local forArg = forScope:addVariable();
        forScope:addReferenceToHigherScope(self.scope, self.upvaluesReferenceCountsTable, 2);
        forScope:addReferenceToHigherScope(scope, entriesVar, 2);
        -- Build a function-based __index: function(self, k) return rawget(entries, k) end
        -- This prevents dumpers from extracting the entries table via getmetatable(proxy).__index
        local indexFuncScope = Scope:new(ifScope);
        local indexFuncSelfArg = indexFuncScope:addVariable();
        local indexFuncKeyArg = indexFuncScope:addVariable();
        indexFuncScope:addReferenceToHigherScope(scope, entriesVar);
        indexFuncScope:addReferenceToHigherScope(self.scope, self.rawgetVar);
        local indexFunc = Ast.FunctionLiteralExpression({
            Ast.VariableExpression(indexFuncScope, indexFuncSelfArg),
            Ast.VariableExpression(indexFuncScope, indexFuncKeyArg),
        }, Ast.Block({
            Ast.ReturnStatement({
                Ast.FunctionCallExpression(Ast.VariableExpression(self.scope, self.rawgetVar), {
                    Ast.VariableExpression(scope, entriesVar),
                    Ast.VariableExpression(indexFuncScope, indexFuncKeyArg),
                })
            })
        }, indexFuncScope));
        return Ast.FunctionLiteralExpression({
            Ast.VariableExpression(scope, entriesVar)
        }, Ast.Block({
            Ast.ForStatement(forScope, forArg, Ast.NumberExpression(1), Ast.LenExpression(Ast.VariableExpression(scope, entriesVar)), Ast.NumberExpression(1), Ast.Block({
                Ast.AssignmentStatement({
                    Ast.AssignmentIndexing(Ast.VariableExpression(self.scope, self.upvaluesReferenceCountsTable), Ast.IndexExpression(Ast.VariableExpression(scope, entriesVar), Ast.VariableExpression(forScope, forArg)))
                }, {
                    Ast.AddExpression(unpack(util.shuffle{
                        Ast.IndexExpression(Ast.VariableExpression(self.scope, self.upvaluesReferenceCountsTable), Ast.IndexExpression(Ast.VariableExpression(scope, entriesVar), Ast.VariableExpression(forScope, forArg))),
                        Ast.NumberExpression(1),
                    }))
                })
            }, forScope), scope);
            Ast.IfStatement(Ast.VariableExpression(self.scope, self.newproxyVar), Ast.Block({
                Ast.LocalVariableDeclaration(ifScope, {
                    proxyVar
                }, {
                    Ast.FunctionCallExpression(Ast.VariableExpression(self.scope, self.newproxyVar), {
                        Ast.BooleanExpression(true)
                    });
                });
                Ast.LocalVariableDeclaration(ifScope, {
                    metatableVar
                }, {
                    Ast.FunctionCallExpression(Ast.VariableExpression(self.scope, self.getmetatableVar), {
                        Ast.VariableExpression(ifScope, proxyVar);
                    });
                });
                Ast.AssignmentStatement({
                    Ast.AssignmentIndexing(Ast.VariableExpression(ifScope, metatableVar), Ast.StringExpression("__index")),
                    Ast.AssignmentIndexing(Ast.VariableExpression(ifScope, metatableVar), Ast.StringExpression("__gc")),
                    Ast.AssignmentIndexing(Ast.VariableExpression(ifScope, metatableVar), Ast.StringExpression("__len")),
                }, {
                    indexFunc,
                    Ast.VariableExpression(self.scope, self.upvaluesGcFunctionVar),
                    Ast.FunctionLiteralExpression({}, Ast.Block({
                        Ast.ReturnStatement({
                            Ast.NumberExpression(self.upvalsProxyLenReturn)
                        })
                    }, Scope:new(ifScope)));
                });
                Ast.ReturnStatement({
                    Ast.VariableExpression(ifScope, proxyVar)
                })
            }, ifScope), {}, Ast.Block({
                Ast.ReturnStatement({
                    Ast.FunctionCallExpression(Ast.VariableExpression(self.scope, self.setmetatableVar), {
                        Ast.TableConstructorExpression({}),
                        Ast.TableConstructorExpression({
                            Ast.KeyedTableEntry(Ast.StringExpression("__gc"), Ast.VariableExpression(self.scope, self.upvaluesGcFunctionVar)),
                            Ast.KeyedTableEntry(Ast.StringExpression("__index"), indexFunc),
                            Ast.KeyedTableEntry(Ast.StringExpression("__len"), Ast.FunctionLiteralExpression({}, Ast.Block({
                                Ast.ReturnStatement({
                                    Ast.NumberExpression(self.upvalsProxyLenReturn)
                                })
                            }, Scope:new(ifScope)))),
                        })
                    })
                })
            }, elseScope));
        }, scope));
    end
    function Compiler:createAllocUpvalFunction()
        local scope = Scope:new(self.scope);
        scope:addReferenceToHigherScope(self.scope, self.currentUpvalId, 4);
        scope:addReferenceToHigherScope(self.scope, self.upvaluesReferenceCountsTable, 1);
        return Ast.FunctionLiteralExpression({}, Ast.Block({
            Ast.AssignmentStatement({
                Ast.AssignmentVariable(self.scope, self.currentUpvalId),
            }, {
                Ast.AddExpression(unpack(util.shuffle({
                    Ast.VariableExpression(self.scope, self.currentUpvalId),
                    Ast.NumberExpression(1),
                }))),
            }),
            Ast.AssignmentStatement({
                Ast.AssignmentIndexing(Ast.VariableExpression(self.scope, self.upvaluesReferenceCountsTable), Ast.VariableExpression(self.scope, self.currentUpvalId)),
            }, {
                Ast.NumberExpression(1),
            }),
            Ast.ReturnStatement({
                Ast.VariableExpression(self.scope, self.currentUpvalId),
            })
        }, scope));
    end
end