return {
    WrapInFunction = require("modules.steps.WrapInFunction"),
    Vmify = require("modules.steps.Vmify"),
    ProxifyLocals = require("modules.steps.ProxifyLocals"),
    AntiTamper = require("modules.steps.AntiTamper"),

    EncryptStrings = require("modules.steps.EncryptStrings"),
    NumbersToExpressions = require("modules.steps.NumbersToExpressions"),
    AddVararg = require("modules.steps.AddVararg"),
    WatermarkCheck = require("modules.steps.WatermarkCheck"),
    Watermark = require("modules.steps.Watermark"),
}
