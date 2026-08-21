local Step = require("modules.utils.step");
local Ast = require("modules.utils.ast");
local visitAst = require("modules.utils.visitast");
local Parser = require("modules.utils.parser");
local util = require("modules.utils.util");
local enums = require("modules.utils.enums")
local LuaVersion = enums.LuaVersion;
local SplitStrings = Step:extend();
SplitStrings.Description = "SplitStrings around the obfuscation";
SplitStrings.Name = "Split Strings";
SplitStrings.SettingsDescriptor = {
	Threshold = {
		name = "Threshold",
		description = "The relative amount of nodes that will be affected",
		type = "number",
		default = 1,
	},
	MinLength = {
		name = "MinLength",
		description = "The minimal length for the chunks in that the Strings are splitted",
		type = "number",
		default = 5,
	},
	MaxLength = {
		name = "MaxLength",
		description = "The maximal length for the chunks in that the Strings are splitted",
		type = "number",
		default = 5,
	},
	ConcatenationType = {
		name = "ConcatenationType",
		description = "The Functions used for Concatenation. Note that when using custom, the String Array will also be Shuffled",
		type = "enum",
		values = {
			"strcat",
			"table",
			"custom",
		},
		default = "custom",
	},
	CustomFunctionType = {
		name = "CustomFunctionType",
		description = "The Type of Function code injection This Option only applies when custom Concatenation is selected.\
Note that when choosing inline, the code size may increase significantly!",
		type = "enum",
		values = {
			"global",
			"local",
			"inline",
		},
		default = "global",
	},
	CustomLocalFunctionsCount = {
		name = "CustomLocalFunctionsCount",
		description = "The number of local functions per scope. This option only applies when CustomFunctionType = local",
		type = "number",
		default = 2,
	}
}
function SplitStrings:init(settings)
end
local function generateTableConcatNode(chunks, data)
	local chunkNodes = {};
	for i, chunk in ipairs(chunks) do
		table.insert(chunkNodes, Ast.TableEntry(Ast.StringExpression(chunk)));
	end
	local tb = Ast.TableConstructorExpression(chunkNodes);
	data.scope:addReferenceToHigherScope(data.tableConcatScope, data.tableConcatId);
	return Ast.FunctionCallExpression(Ast.VariableExpression(data.tableConcatScope, data.tableConcatId), {
		tb
	});
end
local function generateStrCatNode(chunks)
	local generatedNode = nil;
	for i, chunk in ipairs(chunks) do
		if generatedNode then
			generatedNode = Ast.StrCatExpression(generatedNode, Ast.StringExpression(chunk));
		else
			generatedNode = Ast.StringExpression(chunk);
		end
	end
	return generatedNode
end
local customVariants = 2;
local custom1Code = [=[
function custom(table)
    local stringTable, str = table[#table], "";
    for i=1,#stringTable, 1 do
        str = str .. stringTable[table[i]];
	end
	return str
end
]=];
local custom2Code = [=[
function custom(tb)
	local str = "";
	for i=1, #tb / 2, 1 do
		str = str .. tb[#tb / 2 + tb[i]];
	end
	return str
end
]=];
local function sanitizeChunk(chunk)
	if chunk == nil then
		return ""
	end
	return tostring(chunk)
end
local function generateCustomNodeArgs(chunks, data, variant)
	local chunkItems = {};
	for i = 1, #chunks, 1 do
		chunkItems[i] = {
			index = i,
			value = sanitizeChunk(chunks[i])
		};
	end
	util.shuffle(chunkItems);
	local args = {};
	local tbNodes = {};
	for _, item in ipairs(chunkItems) do
		table.insert(args, Ast.TableEntry(Ast.NumberExpression(item.index)));
	end
	for _, item in ipairs(chunkItems) do
		table.insert(tbNodes, Ast.TableEntry(Ast.StringExpression(item.value)));
	end
	local tb = Ast.TableConstructorExpression(tbNodes);
	if variant == 1 then
		table.insert(args, Ast.TableEntry(tb));
	end
	return {
		Ast.TableConstructorExpression(args)
	};
end
local function generateCustomFunctionLiteral(parentScope, variant)
	local parser = Parser:new({
		LuaVersion = LuaVersion.Lua52;
	});

	if variant == 1 then
		local funcDeclNode = parser:parse(custom1Code).body.statements[1];
		local funcBody = funcDeclNode.body;
		local funcArgs = funcDeclNode.args;
		funcBody.scope:setParent(parentScope);
		return Ast.FunctionLiteralExpression(funcArgs, funcBody);

	else
		local funcDeclNode = parser:parse(custom2Code).body.statements[1];
		local funcBody = funcDeclNode.body;
		local funcArgs = funcDeclNode.args;
		funcBody.scope:setParent(parentScope);
		return Ast.FunctionLiteralExpression(funcArgs, funcBody);
	end
end
local function generateGlobalCustomFunctionDeclaration(ast, data)
	local parser = Parser:new({
		LuaVersion = LuaVersion.Lua52;
	});
	if data.customFunctionVariant == 1 then
		local astScope = ast.body.scope;
		local funcDeclNode = parser:parse(custom1Code).body.statements[1];
		local funcBody = funcDeclNode.body;
		local funcArgs = funcDeclNode.args;
		funcBody.scope:setParent(astScope);
		return Ast.LocalVariableDeclaration(astScope, {
			data.customFuncId
		}, {
			Ast.FunctionLiteralExpression(funcArgs, funcBody)
		});
	else
		local astScope = ast.body.scope;
		local funcDeclNode = parser:parse(custom2Code).body.statements[1];
		local funcBody = funcDeclNode.body;
		local funcArgs = funcDeclNode.args;
		funcBody.scope:setParent(astScope);
		return Ast.LocalVariableDeclaration(data.customFuncScope, {
			data.customFuncId
		}, {
			Ast.FunctionLiteralExpression(funcArgs, funcBody)
		});
	end
end
function SplitStrings:apply(ast, pipeline)
	local data = {};
	if (self.ConcatenationType == "table") then
		local scope = ast.body.scope;
		local id = scope:addVariable();
		data.tableConcatScope = scope;
		data.tableConcatId = id;
	elseif (self.ConcatenationType == "custom") then
		data.customFunctionType = self.CustomFunctionType;
		if data.customFunctionType == "global" then
			local scope = ast.body.scope;
			local id = scope:addVariable();
			data.customFuncScope = scope;
			data.customFuncId = id;
			data.customFunctionVariant = 1;
		end
	end
	local customLocalFunctionsCount = self.CustomLocalFunctionsCount;
	visitAst(ast, function(node, data)
		if (self.ConcatenationType == "custom" and data.customFunctionType == "local" and node.kind == Ast.AstKind.Block and node.isFunctionBlock) then
			data.functionData.localFunctions = {};
			for i = 1, customLocalFunctionsCount, 1 do
				local scope = data.scope;
				local id = scope:addVariable();
				table.insert(data.functionData.localFunctions, {
					scope = scope,
					id = id,
					variant = 1,
					used = false,
				});
			end
		end
	end, function(node, data)
		if (self.ConcatenationType == "custom" and data.customFunctionType == "local" and node.kind == Ast.AstKind.Block and node.isFunctionBlock) then
			for i, func in ipairs(data.functionData.localFunctions) do
				if func.used then
					local literal = generateCustomFunctionLiteral(func.scope, func.variant);
					table.insert(node.statements, 1, Ast.LocalVariableDeclaration(func.scope, {
						func.id
					}, {
						literal
					}));
				end
			end
		end
		if (node.kind == Ast.AstKind.StringExpression) then
			local str = node.value;
			local lowerStr = string.lower(str);
			local luaKeywords = {
				["getfenv"] = true, ["setfenv"] = true, ["getmetatable"] = true, ["setmetatable"] = true,
				["unpack"] = true, ["table"] = true, ["concat"] = true, ["insert"] = true, ["remove"] = true,
				["pcall"] = true, ["xpcall"] = true, ["rawequal"] = true, ["rawget"] = true, ["rawset"] = true, ["rawlen"] = true,
				["pairs"] = true, ["ipairs"] = true, ["next"] = true, ["type"] = true, ["tostring"] = true,
				["tonumber"] = true, ["select"] = true, ["format"] = true, ["char"] = true, ["byte"] = true,
				["find"] = true, ["match"] = true, ["gmatch"] = true, ["gsub"] = true, ["lower"] = true, ["upper"] = true,
["rep"] = true, ["reverse"] = true, ["sub"] = true, ["len"] = true,
				["debug"] = true, ["getinfo"] = true, ["getregistry"] = true, ["gethook"] = true, ["sethook"] = true,
				["getupvalue"] = true, ["setupvalue"] = true, ["upvaluejoin"] = true,
				["loadstring"] = true, ["load"] = true, ["assert"] = true, ["error"] = true,
				["print"] = true, ["io"] = true, ["os"] = true, ["math"] = true, ["string"] = true,
				["coroutine"] = true, ["require"] = true, ["module"] = true, ["package"] = true
			};
			if string.sub(str, 1, 2) == "__" or luaKeywords[lowerStr] or string.find(lowerStr, "getfenv") or string.find(lowerStr, "setfenv") or string.find(lowerStr, "concat") or string.find(lowerStr, "index") or string.find(lowerStr, "newindex") or string.find(lowerStr, "unpack") or string.find(lowerStr, "upvalue") or string.find(lowerStr, "upval") or string.find(lowerStr, "debug") or string.find(lowerStr, "registry") or string.find(lowerStr, "hook") or string.find(lowerStr, "traceback") or string.find(lowerStr, "getinfo") or string.find(lowerStr, "sethook") or string.find(lowerStr, "gethook") or string.find(lowerStr, "getupvalue") or string.find(lowerStr, "setupvalue") or string.find(lowerStr, "pcall") or string.find(lowerStr, "xpcall") or string.find(lowerStr, "rawequal") or string.find(lowerStr, "rawset") or string.find(lowerStr, "rawlen") or string.find(lowerStr, "env") or string.find(lowerStr, "_zym") then
			else
			local chunks = {};
			local i = 1;
			while i <= string.len(str) do
				local len = self.MinLength;
				table.insert(chunks, string.sub(str, i, i + len - 1));
				i = i + len;
			end
			if (# chunks > 1) then
				if self.ConcatenationType == "strcat" then
					node = generateStrCatNode(chunks);
				elseif self.ConcatenationType == "table" then
					node = generateTableConcatNode(chunks, data);
				elseif self.ConcatenationType == "custom" then
					if self.CustomFunctionType == "global" then
						local args = generateCustomNodeArgs(chunks, data, data.customFunctionVariant);
						data.scope:addReferenceToHigherScope(data.customFuncScope, data.customFuncId);
						node = Ast.FunctionCallExpression(Ast.VariableExpression(data.customFuncScope, data.customFuncId), args);
					elseif self.CustomFunctionType == "local" then
						local lfuncs = data.functionData.localFunctions;
						local func = lfuncs[1];
						local args = generateCustomNodeArgs(chunks, data, func.variant);
						func.used = true;
						data.scope:addReferenceToHigherScope(func.scope, func.id);
						node = Ast.FunctionCallExpression(Ast.VariableExpression(func.scope, func.id), args);
					elseif self.CustomFunctionType == "inline" then
						local args = generateCustomNodeArgs(chunks, data, 1);
						local literal = generateCustomFunctionLiteral(data.scope, 1);
						node = Ast.FunctionCallExpression(literal, args);
					end
				end
			end
			end
			return node, true;
		end
	end, data)
	if (self.ConcatenationType == "table") then
		local globalScope = data.globalScope;
		local tableScope, tableId = globalScope:resolve("table")
		ast.body.scope:addReferenceToHigherScope(globalScope, tableId);
		table.insert(ast.body.statements, 1, Ast.LocalVariableDeclaration(data.tableConcatScope, {
			data.tableConcatId
		}, {
			Ast.IndexExpression(Ast.VariableExpression(tableScope, tableId), Ast.StringExpression("concat"))
		}));
	elseif (self.ConcatenationType == "custom" and self.CustomFunctionType == "global") then
		table.insert(ast.body.statements, 1, generateGlobalCustomFunctionDeclaration(ast, data));
	end
end
return SplitStrings;