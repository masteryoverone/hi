local Ast = require("modules.utils.ast")
local charset = {"a","b","c","d","e","f","g","h","i","j","k","l","m","n","o","p","q","r","s","t","u","v","w","x","y","z"}
local idx = 0
local function randomString(wordsOrLen)
	if type(wordsOrLen) == "table" then
		return wordsOrLen[1];
	end
	wordsOrLen = wordsOrLen or 6
	local result = ""
	for i = 1, wordsOrLen do
		idx = idx + 1
		result = result .. charset[(idx % #charset) + 1]
	end
	return result
end
local function randomStringNode(wordsOrLen)
	return Ast.StringExpression(randomString(wordsOrLen))
end
return {
	randomString = randomString,
	randomStringNode = randomStringNode,
}