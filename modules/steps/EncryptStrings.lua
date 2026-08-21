local Step = require("modules.utils.step")
local Ast = require("modules.utils.ast")
local Parser = require("modules.utils.parser")
local Enums = require("modules.utils.enums")
local visitast = require("modules.utils.visitast")
local AstKind = Ast.AstKind

local unpack = unpack or table.unpack

local function bxor(a, b)
	local r, c = 0, 1
	while a > 0 or b > 0 do
		local aa, bb = a % 2, b % 2
		if aa ~= bb then r = r + c end
		a, b, c = (a - aa) / 2, (b - bb) / 2, c * 2
	end
	return r
end

local function rotR1(k)
	return math.floor(k / 2) + (k % 2) * 128
end

local EncryptStrings = Step:extend()
EncryptStrings.Description =
"This Step encrypts string literals into tables of 8-bit byte values and emits a control-flow-flattened decryptor that reassembles them through a runtime-built 256-entry character lookup table, using native bitwise operators (`~`, `&`, `|`, `<<`, `>>`). Requires Lua 5.3+ / LuaU at runtime."
EncryptStrings.Name = "Encrypt Strings"
EncryptStrings.SettingsDescriptor = {
	Rounds = {
		name = "Rounds",
		description = "The number of encryption rounds",
		type = "number",
		default = 1,
	},
}

function EncryptStrings:init(_)
end

local DECRYPTOR_TEMPLATE = [==[
local _L = {}
for _j = 0, 255 do
	_L[_j] = string.char(_j)
end
local function _w(re)
	local _ke = __KEY__
	local _o, _s, _b, _i, _n, _l, _k = {}, 1, 0, 1, #re, #_ke, 0
	_l = #_ke
	while _s ~= 0 do
		if _s == 2 then
			_k = _ke[((_i - 1) % _l) + 1]
			_k = (_k >> 1) | ((_k & 1) << 7)
			_b = re[_i] ~ _k
			_o[_i] = _L[_b]
			_i = _i + 1
			_s = 1
		elseif _s == 1 then
			if _i > _n then
				_s = 0
			else
				_s = 2
			end
		end
	end
	return table.concat(_o)
end
]==]

local DECRYPTOR_TEMPLATE_51 = [==[
local function _bxor(a, b)
	local r, c = 0, 1
	while a > 0 or b > 0 do
		local aa, bb = a % 2, b % 2
		if aa ~= bb then r = r + c end
		a, b, c = (a - aa) / 2, (b - bb) / 2, c * 2
	end
	return r
end
local function _w(re)
	local _ke = __KEY__
	local _o, _s, _b, _i, _n, _l, _k = {}, 1, 0, 1, #re, #_ke, 0
	_l = #_ke
	while _s ~= 0 do
		if _s == 2 then
			_k = _ke[((_i - 1) % _l) + 1]
			_k = math.floor(_k / 2) + (_k % 2) * 128
			_b = _bxor(re[_i], _k)
			_o[_i] = string.char(_b)
			_i = _i + 1
			_s = 1
		elseif _s == 1 then
			if _i > _n then
				_s = 0
			else
				_s = 2
			end
		end
	end
	return table.concat(_o)
end
]==]

local function bytesToTable(bytes)
	return "{" .. table.concat(bytes, ", ") .. "}"
end

function EncryptStrings:CreateEncryptionService(template)
	template = template or DECRYPTOR_TEMPLATE
	local keyBytes = {}
	local keyLen = math.random(2, 6)
	for i = 1, keyLen do
		keyBytes[i] = math.random(1, 255)
	end

	local function encrypt(str)
		local bytes = {}
		local kl = #keyBytes
		for i = 1, #str do
			local byte = string.byte(str, i)
			local k = rotR1(keyBytes[((i - 1) % kl) + 1])
			bytes[i] = bxor(byte, k)
		end
		return bytes
	end

	local function genCode()
		return template:gsub("__KEY__", bytesToTable(keyBytes), 1)
	end

	return {
		keyBytes = keyBytes,
		encrypt = encrypt,
		genCode = genCode,
	}
end

function EncryptStrings:apply(ast)
	local rounds = self.Rounds or 1

	local isLuau = (self._options.LuaVersion == Enums.LuaVersion.LuaU)
	local template = isLuau and DECRYPTOR_TEMPLATE or DECRYPTOR_TEMPLATE_51
	local parseVersion = isLuau and Enums.LuaVersion.LuaU or Enums.LuaVersion.Lua51

	for r = 1, rounds do
		local Encryptor = self:CreateEncryptionService(template)
		local code = Encryptor.genCode()
		local newAst = Parser:new({
			LuaVersion = parseVersion
		}):parse(code)

		if not newAst or not newAst.body then
			return ast
		end

		local scope = ast.body.scope
		local decryptVar = scope:addVariable()
		local encryptedCount = 0

		if newAst.body and newAst.body.scope then
			newAst.body.scope:setParent(scope)
		end

		visitast(newAst, nil, function(node, _)
			if node.kind == AstKind.LocalFunctionDeclaration then
				if node.scope and node.id then
					local varName = node.scope:getVariableName(node.id)
					if varName == "_w" then
						node.scope = scope
						node.id = decryptVar
					end
				end
			end
			if node.kind == AstKind.VariableExpression or node.kind == AstKind.AssignmentVariable then
				if node.scope and node.id then
					local varName = node.scope:getVariableName(node.id)
					if varName == "_w" then
						node.id = decryptVar
						node.scope = scope
					end
				end
			end
		end)

		visitast(ast, nil, function(node, data)
			if node.kind == AstKind.StringExpression then
				encryptedCount = encryptedCount + 1
				data.scope:addReferenceToHigherScope(scope, decryptVar)

				local encrypted = Encryptor.encrypt(node.value)
				local entries = {}
				for i = 1, #encrypted do
					entries[i] = Ast.TableEntry(Ast.NumberExpression(encrypted[i]))
				end

				return Ast.FunctionCallExpression(
					Ast.VariableExpression(scope, decryptVar),
					{ Ast.TableConstructorExpression(entries) }
				)
			end
		end)

		if encryptedCount == 0 then
			return ast
		end

		if newAst.body and newAst.body.statements then
			for i = #newAst.body.statements, 1, -1 do
				table.insert(ast.body.statements, 1, newAst.body.statements[i])
			end
		end
	end

	return ast
end

return EncryptStrings
