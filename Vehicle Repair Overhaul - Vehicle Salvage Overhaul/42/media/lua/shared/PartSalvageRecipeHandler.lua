local function SalvageVehicleDoors()
    local recipe = ScriptManager.instance:getCraftRecipe("Salvage Vehicle Doors")
    local inputString
    if not recipe then
        print("[VRO] Recipe not found")
        return
    end

    local itemList = { "Base.fhqFusFleaSupDoor", "Base.81deloreanDMC12FrontDoor3", "Base.85gmBbodyRearDoor1" }
    local validItems = {}

    for _, itemType in ipairs(itemList) do
        if ScriptManager.instance:getItem(itemType) then
            table.insert(validItems, itemType)
            print("[VRO] Found item:", itemType)
            inputString = "{ inputs { item 1 [" .. table.concat(validItems, ";") .. "] mode:destroy, } }"
            print("[VRO] Injected recipe input:", inputString)
        else
            print("[VRO] Missing item (skipped):", itemType)
        end
    end

    if validItems then
        recipe:Load("Salvage Vehicle Doors", inputString)
    else
        print("[VRO] No valid inputs found, recipe unchanged.")
    end
end

Events.OnInitWorld.Add(SalvageVehicleDoors)
if isServer() then Events.OnGameBoot.Add(SalvageVehicleDoors) end