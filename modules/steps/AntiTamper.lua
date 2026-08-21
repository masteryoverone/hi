local Step = require("modules.utils.step")
local Parser = require("modules.utils.parser")
local Enums = require("modules.utils.enums")
local logger = require("src.logger")

local AntiTamper = Step:extend()
AntiTamper.Description = "A Anti Env which prevents malicous attempts of tampering the script."
AntiTamper.Name = "Anti Tamper"
AntiTamper.SettingsDescriptor = {}

local function getInjectedCode()
    return [=[
do
	local _c = pcall
	local _cx = xpcall
	local _s = type
	local _d = debug
	local _f = getfenv
	local _os = os
	local _0 = false
	local function _ck(fn)
		if _s(fn) ~= "function" then
			return nil
		end
		local a, b = _c(_d.getinfo, fn, "u")
		if not a or _s(b) ~= "table" then
			return nil
		end
		if b.what == "C" then
			return true
		end
		if b.what == "Lua" then
			return false
		end
		return nil
	end
	local function _t1()
		if _s(_c) ~= "function" then
			return true
		end
		if _s(_cx) ~= "function" then
			return true
		end
		local a, b = _c(function(x)
			return x
		end, 1)
		if a ~= true or b ~= 1 then
			return true
		end
		local d = _c(function()
			error("e")
		end, function(e)
			return e
		end)
		if d ~= false then
			return true
		end
		local g, h = _c(function()
			return 1 + 1
		end)
		if g ~= true or h ~= 2 then
			return true
		end
		if _ck(_c) ~= true then
			return true
		end
		return false
	end
	local function _t2()
		local a, b = _c(_os.clock)
		local d, e = _c(_os.clock)
		if a and d then
			if e < b then
				return true
			end
			if _s(b) ~= "number" or _s(e) ~= "number" then
				return true
			end
		end
		return false
	end
	local function _t3()
		local a, b = _c(function()
			return workspace
		end)
		if a and _s(b) ~= "userdata" then
			return true
		end
		local d, e = _c(function()
			return game
		end)
		if d and _s(e) ~= "userdata" then
			return true
		end
		return false
	end
	local function _t4()
		local a, b = _c(function()
			return Instance
		end)
		if a then
			if _s(b) ~= "userdata" and _s(b) ~= "table" then
				return true
			end
			if _s(b) == "table" then
				local d, e = _c(function()
					return b.new
				end)
				if d and _s(e) == "function" and _ck(e) == false then
					return true
				end
			end
		end
		local g, h = _c(function()
			return type(task)
		end)
		if g and (h == "table" or h == "userdata") then
			local j, k = _c(function()
				return task.spawn
			end)
			if j and _s(k) == "function" and _ck(k) == false then
				return true
			end
			local l, n = _c(function()
				return task.wait
			end)
			if l and _s(n) == "function" and _ck(n) == false then
				return true
			end
		end
		return false
	end
	local function _t5()
		if _s(_f) ~= "function" then
			return true
		end
		local a, b = _c(_f, function()
		end)
		if a and _s(b) ~= "table" then
			return true
		end
		local d, e = _c(_f, 0)
		if d and _s(e) ~= "table" then
			return true
		end
		return false
	end
	local function _t6()
		if _s(_d) ~= "table" then
			return true
		end
		if _s(_d.getinfo) ~= "function" then
			return true
		end
		return false
	end
	local function _t7()
		local a, b = _c(function()
			return workspace
		end)
		if a and b ~= nil then
			local c, d = _c(function()
				local v = workspace.__heph_probe_xyz_999
				return v ~= nil
			end)
			if c and d == true then
				return true
			end
		end
		local e, f = _c(function()
			return game
		end)
		if e and f ~= nil then
			local g, h = _c(function()
				local v = game.__heph_probe_xyz_999
				return v ~= nil
			end)
			if g and h == true then
				return true
			end
		end
		return false
	end
	local function _t8()
		local a, b = _c(function()
			local p = newproxy(true)
			local mt = getmetatable(p)
			if mt and mt.__index and _s(mt.__index) == "function" then
				return true
			end
			return false
		end)
		if a and b == true then
			return true
		end
		return false
	end
	local function _t9()
		local _di = _d.getinfo
		local _dl = _d.getlocal
		local _dsl = _d.setlocal
		local _gr = _d.getregistry
		local _tb = _d.traceback
		if _s(_dl) == "function" and _ck(_dl) == false then
			return true
		end
		if _s(_dsl) == "function" and _ck(_dsl) == false then
			return true
		end
		if _s(_gr) == "function" and _ck(_gr) == false then
			return true
		end
		if _s(_tb) == "function" and _ck(_tb) == false then
			return true
		end
		if _s(_di) ~= "function" then
			return true
		end
		if _ck(_di) == false then
			return true
		end
		return false
	end
	if not _0 then
		_0 = _t1()
	end
	if not _0 then
		_0 = _t2()
	end
	if not _0 then
		_0 = _t3()
	end
	if not _0 then
		_0 = _t4()
	end
	if not _0 then
		_0 = _t5()
	end
	if not _0 then
		_0 = _t6()
	end
	if not _0 then
		_0 = _t7()
	end
	if not _0 then
		_0 = _t8()
	end
	if not _0 then
		_0 = _t9()
	end
	if _0 then
		print("Heph : Detected Tampering")
		return
	end
end
]=]
end

function AntiTamper:init(_)
end

function AntiTamper:apply(ast, pipeline)
    if pipeline.PrettyPrint then
        logger:warn(string.format('"%s" cannot be used with PrettyPrint, ignoring "%s"', self.Name, self.Name))
        return ast
    end
    local code = getInjectedCode()
    local parsed = Parser:new({
        LuaVersion = Enums.LuaVersion.Lua51
    }):parse(code)
    local doStat = parsed.body.statements[1]
    doStat.body.scope:setParent(ast.body.scope)
    table.insert(ast.body.statements, 1, doStat)
    return ast
end

return AntiTamper
