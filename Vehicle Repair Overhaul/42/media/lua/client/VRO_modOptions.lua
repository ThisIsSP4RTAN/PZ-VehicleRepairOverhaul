local VRO = {}

VRO.Options = {
    HideVanillaRepair = false
    }



local config = {
    HideVanillaRepair = nil,
}

local function applyOptions()
    local options = PZAPI.ModOptions:getOptions("HideVanillaRepair")

    if options then
        VRO.Options.HideVanillaRepair = options:getOption("HideVanillaRepair"):getValue()
    end
end
    VRO.initConfig = function()
        local PZOptions = PZAPI.ModOptions:create("HideVanillaRepair", getText("UI_VRO_Options_Title"))

        config.HideVanillaRepair = PZOptions:addTickBox("HideVanillaRepair", getText("UI_VRO_ELR_Options"), VRO.Options.HideVanillaRepair, getText("UI_VRO_ELR_Options_Tooltip"))

        PZOptions.apply = function ()
            applyOptions()
        end
    end

    VRO.initConfig()

    Events.OnMainMenuEnter.Add(function()
        applyOptions()
    end)

return VRO