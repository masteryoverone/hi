local NAME = "Hephaestus ";
local REVISION = "Alpha";
local VERSION = "v0.2";
if type(arg) == "table" then
    for _, currArg in pairs(arg) do
        if currArg == "--CI" then
            local releaseName = string.gsub(string.format("%s %s %s", NAME, REVISION, VERSION), "%s", "-")
            print(releaseName)
        end
        if currArg == "--FullVersion" then
            print(VERSION)
        end
    end
end
return {
    Name = NAME,
    NameUpper = string.upper(NAME),
    NameAndVersion = string.format("%s %s", NAME, VERSION),
    Version = VERSION,
    Revision = REVISION,
    IdentPrefix = "__hephaestus_",
    SPACE = " ",
    TAB = "\t",

    Watermark = "Hephaestus [[1]]",

    VarNamePrefix = "",
    NameGenerator = "Il",

    PrettyPrint = false,
    Seed = 0,

    Steps = {
        EncryptStrings = true,
        NumbersToExpressions = true,
        AntiTamper = true,
        Vmify = true,
        ProxifyLocals = true,
        AddVararg = true,
        WrapInFunction = true,
    },
}
