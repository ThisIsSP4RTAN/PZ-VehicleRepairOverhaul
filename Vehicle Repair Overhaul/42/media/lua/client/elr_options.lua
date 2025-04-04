local ELR = {}

ELR.Options = {
    HideVanillaRepair = false
    }

local PZOptions

local config = {
    HideVanillaRepair = nil,
}

local function applyOptions()
    local options = PZAPI.ModOptions:getOptions("HideVanillaRepair")

    if options then
        ELR.Options.HideVanillaRepair = options:getOption("HideVanillaRepair"):getValue()
    end
end
    local function initConfig()
        PZOptions = PZAPI.ModOptions:create("HideVanillaRepair", getText("UI_VRO_Options_Title"))

        config.HideVanillaRepair = PZOptions:addTickBox("HideVanillaRepair", getText("UI_VRO_ELR_Options"), ELR.Options.HideVanillaRepair, getText("UI_VRO_ELR_Options_Tooltip"))

        PZOptions.apply = function ()
            applyOptions()
        end
    end

    initConfig()

    Events.OnMainMenuEnter.Add(function()
        applyOptions()
    end)

return ELR