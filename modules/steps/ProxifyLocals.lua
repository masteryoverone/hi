local Step = require("modules.utils.step")
local Ast = require("modules.utils.ast")
local Scope = require("modules.utils.scope")
local Parser = require("modules.utils.parser")
local Enums = require("modules.utils.enums")
local visitast = require("modules.utils.visitast")
local RandomLiterals = require("modules.utils.randomLiterals")
local AstKind = Ast.AstKind
local ProxifyLocals = Step:extend()
ProxifyLocals.Description = "Wraps locals into proxy objects with MBA key recovery, additive name encryption, control-flow-flattened access, a shuffled metamethod pool and optional proxy nesting."
ProxifyLocals.Name = "Proxify Locals"
ProxifyLocals.SettingsDescriptor = {
	LiteralType = {
		name = "LiteralType",
		description = "The type of the randomly generated decoy literals",
		type = "enum",
		values = { "dictionary", "number", "string", "any" },
		default = "string",
	},
	NestDepth = {
		name = "NestDepth",
		description = "Maximum proxy nesting depth (1 or 2)",
		type = "number",
		default = 1,
	},
}

-- Metamethod pool. __index is kept out of the setter pool because it is a
-- read-only metamethod; it is reserved for the getter pool only.
local BASE_POOL = {
	{ constructor = Ast.AddExpression, key = "__add" },
	{ constructor = Ast.SubExpression, key = "__sub" },
	{ constructor = Ast.MulExpression, key = "__mul" },
	{ constructor = Ast.DivExpression, key = "__div" },
	{ constructor = Ast.PowExpression, key = "__pow" },
	{ constructor = Ast.StrCatExpression, key = "__concat" },
}
local LUAU_POOL = {
	{ constructor = Ast.BitwiseAndExpression, key = "__band" },
	{ constructor = Ast.BitwiseOrExpression, key = "__bor" },
	{ constructor = Ast.BitwiseXorExpression, key = "__bxor" },
	{ constructor = Ast.ShiftLeftExpression, key = "__shl" },
	{ constructor = Ast.ShiftRightExpression, key = "__shr" },
}

-- Build a per-obfuscation shuffled metamethod pool (#7). The arithmetic/bitwise
-- ops are shuffled and split; __index is always reserved for the getters.
local function buildPool(isLuau)
	local arith = {}
	for _, e in ipairs(BASE_POOL) do arith[#arith + 1] = e end
	if isLuau then for _, e in ipairs(LUAU_POOL) do arith[#arith + 1] = e end end
	for i = #arith, 2, -1 do
		local j = math.random(1, i)
		arith[i], arith[j] = arith[j], arith[i]
	end
	local mid = math.floor(#arith / 2)
	local setters = {}
	for i = 1, mid do setters[#setters + 1] = arith[i] end
	local getters = { { constructor = Ast.IndexExpression, key = "__index" } }
	for i = mid + 1, #arith do getters[#getters + 1] = arith[i] end
	return getters, setters
end

-- One encryption layer: a single-byte value name is hidden behind an additive
-- XOR-style mask key (#5). nameByte in 1..200, keyByte in 1..(255-nameByte) so
-- the sum never wraps past 256 and stays a valid byte.
local function makeLayer()
	local nameByte = math.random(1, 200)
	local keyByte = math.random(1, 255 - nameByte)
	return { nameByte = nameByte, keyByte = keyByte, encByte = nameByte + keyByte }
end

local metatableIdx = 0
local function generateLocalMetatableInfo(getters, setters, nestDepth)
	metatableIdx = metatableIdx + 1
	local info = {}
	info.setValue = setters[(metatableIdx % #setters) + 1]
	info.getValue = getters[(metatableIdx % #getters) + 1]
	info.index = getters[(metatableIdx % #getters) + 1]
	info.layers = {}
	local depth = math.random(1, math.max(1, math.min(2, nestDepth or 1)))
	for _ = 1, depth do
		info.layers[#info.layers + 1] = makeLayer()
	end
	return info
end

-- Build the flattened getter function source (#6). Each layer decrypts its
-- name byte via MBA key recovery then indexes into the current container.
local function buildGetterSrc(layers)
	local lines = { "function(self, _lit)" }
	lines[#lines + 1] = "    local _s = 1"
	lines[#lines + 1] = "    local _out"
	lines[#lines + 1] = "    while _s ~= 0 do"
	local cur = "self"
	for i, layer in ipairs(layers) do
		lines[#lines + 1] = "        if _s == " .. i .. " then"
		lines[#lines + 1] = "            local _r = #" .. cur
		lines[#lines + 1] = "            local _k = (" .. layer.keyByte .. " + _r) - _r"
		if i < #layers then
			local nxt = "_c" .. i
			lines[#lines + 1] = "            local " .. nxt .. " = rawget(" .. cur .. ", string.char(" .. layer.encByte .. " - _k))"
			cur = nxt
		else
			lines[#lines + 1] = "            _out = rawget(" .. cur .. ", string.char(" .. layer.encByte .. " - _k))"
		end
		lines[#lines + 1] = "            _s = " .. (i < #layers and (i + 1) or 0)
	end
	lines[#lines + 1] = "        end"
	lines[#lines + 1] = "    end"
	lines[#lines + 1] = "    return _out"
	lines[#lines + 1] = "end"
	return table.concat(lines, "\n")
end

-- Build the flattened setter function source (#6).
local function buildSetterSrc(layers, valArg)
	local lines = { "function(self, " .. valArg .. ")" }
	lines[#lines + 1] = "    local _s = 1"
	lines[#lines + 1] = "    while _s ~= 0 do"
	local cur = "self"
	for i, layer in ipairs(layers) do
		lines[#lines + 1] = "        if _s == " .. i .. " then"
		lines[#lines + 1] = "            local _r = #" .. cur
		lines[#lines + 1] = "            local _k = (" .. layer.keyByte .. " + _r) - _r"
		if i < #layers then
			local nxt = "_c" .. i
			lines[#lines + 1] = "            local " .. nxt .. " = " .. cur .. "[string.char(" .. layer.encByte .. " - _k)]"
			cur = nxt
		else
			lines[#lines + 1] = "            " .. cur .. "[string.char(" .. layer.encByte .. " - _k)] = " .. valArg
		end
		lines[#lines + 1] = "            _s = " .. (i < #layers and (i + 1) or 0)
	end
	lines[#lines + 1] = "        end"
	lines[#lines + 1] = "    end"
	lines[#lines + 1] = "end"
	return table.concat(lines, "\n")
end

-- Parse a generated function source and return the function literal AST node.
local function parseFunc(source)
	local wrapped = "_G_PROXY_FN = " .. source
	local ast = Parser:new({ LuaVersion = Enums.LuaVersion.Lua51 }):parse(wrapped)
	local stat = ast.body.statements[1]
	if stat.kind == AstKind.AssignmentStatement then
		return stat.rhs[1]
	end
	return stat.expressions[1]
end

function ProxifyLocals:init(_)
end

function ProxifyLocals:apply(ast, pipeline)
	local isLuau = (self._options.LuaVersion == Enums.LuaVersion.LuaU)
	local getters, setters = buildPool(isLuau)

	local localMetatableInfos = {}
	local function getLocalMetatableInfo(scope, id)
		if scope.isGlobal then return nil end
		localMetatableInfos[scope] = localMetatableInfos[scope] or {}
		if localMetatableInfos[scope][id] then
			if localMetatableInfos[scope][id].locked then return nil end
			return localMetatableInfos[scope][id]
		end
		localMetatableInfos[scope][id] = generateLocalMetatableInfo(getters, setters, self.NestDepth)
		return localMetatableInfos[scope][id]
	end
	local function disableMetatableInfo(scope, id)
		if scope.isGlobal then return nil end
		localMetatableInfos[scope] = localMetatableInfos[scope] or {}
		localMetatableInfos[scope][id] = { locked = true }
	end

	self.setMetatableVarScope = ast.body.scope
	self.setMetatableVarId = ast.body.scope:addVariable()

	self.emptyFunctionScope = ast.body.scope
	self.emptyFunctionId = ast.body.scope:addVariable()
	self.emptyFunctionUsed = false

	table.insert(ast.body.statements, 1, Ast.LocalVariableDeclaration(self.emptyFunctionScope, {
		self.emptyFunctionId
	}, {
		Ast.FunctionLiteralExpression({}, Ast.Block({}, Scope:new(ast.body.scope)));
	}))

	visitast(ast, function(node, data)
		if node.kind == AstKind.ForStatement then
			disableMetatableInfo(node.scope, node.id)
		end
		if node.kind == AstKind.ForInStatement then
			for _, id in ipairs(node.ids) do
				disableMetatableInfo(node.scope, id)
			end
		end
		if node.kind == AstKind.FunctionDeclaration or node.kind == AstKind.LocalFunctionDeclaration or node.kind == AstKind.FunctionLiteralExpression then
			for _, expr in ipairs(node.args) do
				if expr.kind == AstKind.VariableExpression then
					disableMetatableInfo(expr.scope, expr.id)
				end
			end
		end

		if node.kind == AstKind.AssignmentStatement then
			if (#node.lhs == 1 and node.lhs[1].kind == AstKind.AssignmentVariable) then
				local variable = node.lhs[1]
				local info = getLocalMetatableInfo(variable.scope, variable.id)
				if info then
					local args = {}
					for _, v in ipairs(node.rhs) do args[#args + 1] = v end
					local vexp = Ast.VariableExpression(variable.scope, variable.id)
					vexp.__ignoreProxifyLocals = true
					args[1] = info.setValue.constructor(vexp, args[1])
					self.emptyFunctionUsed = true
					data.scope:addReferenceToHigherScope(self.emptyFunctionScope, self.emptyFunctionId)
					return Ast.FunctionCallStatement(Ast.VariableExpression(self.emptyFunctionScope, self.emptyFunctionId), args)
				end
			end
		end
	end, nil)

	visitast(ast, nil, function(node, data)
		if node.kind == AstKind.LocalVariableDeclaration then
			for i, id in ipairs(node.ids) do
				local expr = node.expressions[i] or Ast.NilExpression()
				local info = getLocalMetatableInfo(node.scope, id)
				if info then
					local newExpr = self:CreateAssignmentExpression(info, expr, node.scope)
					node.expressions[i] = newExpr
				end
			end
		end

		if node.kind == AstKind.VariableExpression and not node.__ignoreProxifyLocals then
			local info = getLocalMetatableInfo(node.scope, node.id)
			if info then
				local literal
				if self.LiteralType == "dictionary" then
					literal = RandomLiterals.Dictionary()
				elseif self.LiteralType == "number" then
					literal = RandomLiterals.Number()
				elseif self.LiteralType == "string" then
					literal = RandomLiterals.String(pipeline)
				else
					literal = RandomLiterals.Any(pipeline)
				end
				if info.getValue.key == "__index" then
					return Ast.IndexExpression(node, literal)
				end
				return info.getValue.constructor(node, literal)
			end
		end

		if node.kind == AstKind.AssignmentVariable then
			local info = getLocalMetatableInfo(node.scope, node.id)
			if info then
				return Ast.AssignmentIndexing(node, Ast.StringExpression(string.char(info.layers[1].nameByte)))
			end
		end

		if node.kind == AstKind.LocalFunctionDeclaration then
			local info = getLocalMetatableInfo(node.scope, node.id)
			if info then
				local funcLiteral = Ast.FunctionLiteralExpression(node.args, node.body)
				local newExpr = self:CreateAssignmentExpression(info, funcLiteral, node.scope)
				return Ast.LocalVariableDeclaration(node.scope, { node.id }, { newExpr })
			end
		end

		if node.kind == AstKind.FunctionDeclaration then
			local info = getLocalMetatableInfo(node.scope, node.id)
			if info then
				table.insert(node.indices, 1, string.char(info.layers[1].nameByte))
			end
		end
	end)

	table.insert(ast.body.statements, 1, Ast.LocalVariableDeclaration(self.setMetatableVarScope, {
		self.setMetatableVarId
	}, {
		Ast.VariableExpression(self.setMetatableVarScope:resolveGlobal("setmetatable"))
	}))

	return ast
end

function ProxifyLocals:CreateAssignmentExpression(info, expr, parentScope)
	local layers = info.layers
	local depth = #layers

	-- Build the proxy's initial data table: a single layer is {name = value}; a
	-- nested layer (#4) is {outerName = {innerName = value}}.
	local function buildData(layerIndex)
		local layer = layers[layerIndex]
		local key = Ast.StringExpression(string.char(layer.nameByte))
		if layerIndex == depth then
			return Ast.TableConstructorExpression({ Ast.KeyedTableEntry(key, expr) })
		end
		return Ast.TableConstructorExpression({ Ast.KeyedTableEntry(key, buildData(layerIndex + 1)) })
	end

	-- Getter: flattened state machine that walks down through each layer.
	local getterSrc = buildGetterSrc(layers)
	local getterFunc = parseFunc(getterSrc)

	-- Setter: flattened state machine that walks down and assigns at the leaf.
	local setterSrc = buildSetterSrc(layers, "_v")
	local setterFunc = parseFunc(setterSrc)

	local metatableVals = {
		Ast.KeyedTableEntry(Ast.StringExpression(info.getValue.key), getterFunc),
		Ast.KeyedTableEntry(Ast.StringExpression(info.setValue.key), setterFunc),
	}

	parentScope:addReferenceToHigherScope(self.setMetatableVarScope, self.setMetatableVarId)
	return Ast.FunctionCallExpression(
		Ast.VariableExpression(self.setMetatableVarScope, self.setMetatableVarId), {
			buildData(1),
			Ast.TableConstructorExpression(metatableVals)
		})
end

return ProxifyLocals
