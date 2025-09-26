require "Vehicles/ISUI/ISVehicleMechanics"

----------------------------------------------------------------------
-- 0) One-time normalization: ensure every Fixing has a non-nil RequiredItem list.
----------------------------------------------------------------------

local function VRO_NormalizeAllFixingsOnce()
    if VRO__FixingsNormalized then return end
    VRO__FixingsNormalized = true

    local list = ArrayList.new()
    ScriptManager.instance:getAllFixing(list)

    local fixedCount, total = 0, list:size()
    for i = 0, total - 1 do
        local fx = list:get(i)
        if fx and fx:getRequiredItem() == nil then
            fx:addRequiredItem("__VRO_init__")
            local req = fx:getRequiredItem()
            if req then req:clear() end
            fixedCount = fixedCount + 1
        end
    end
    print(string.format("[VRO] Normalized Fixing Require lists: %d of %d", fixedCount, total))
end

Events.OnGameBoot.Add(VRO_NormalizeAllFixingsOnce)
Events.OnInitWorld.Add(VRO_NormalizeAllFixingsOnce)
Events.OnGameStart.Add(VRO_NormalizeAllFixingsOnce)

----------------------------------------------------------------------
-- 1) Repair-toggle wrapper: dynamically enable if fixes exist, else use patterns.
----------------------------------------------------------------------

local vanilla_doPartContextMenu = ISVehicleMechanics.doPartContextMenu

-- Exact IDs from vanilla that we always consider repairable (fast path).
local REPAIRABLE_IDS = {
    GloveBox = true, Battery = true, Brake = true, Door = true,
    EngineDoor = true, GasTank = true, Tire = true, Trunk = true, TrunkDoor = true,
    Headlight = true, Seat = true, Window = true, Muffler = true, Radio = true,
    Suspension = true, Windshield = true, TowBar = true,
}

-- Broad patterns to catch modded IDs: e.g., "DoorFrontLeft", "WindowRearRight", "TailLightLeft", etc.
local REPAIRABLE_PATTERNS = {
    "Door", "Window", "Windshield", "Headlight", "TailLight", "Light", "Mirror",
    "Bumper", "Fender", "Bonnet", "Hood", "Trunk", "Boot", "Tailgate", "Muffler",
    "Exhaust", "Suspension", "Brake", "Tire", "Wheel", "Seat", "Radio", "Tow",
    "Armor", "Bullbar", "Grille", "Rack", "Roof",
}

local function idMatchesPattern(id)
    if not id then return false end
    if REPAIRABLE_IDS[id] then return true end
    for i = 1, #REPAIRABLE_PATTERNS do
        if string.find(id, REPAIRABLE_PATTERNS[i]) then
            return true
        end
    end
    return false
end

-- Safely check if an ArrayList-like object has elements.
local function listHasElements(list)
    if not list then return false end
    -- Java lists exposed to Lua usually have :isEmpty() / :size()
    if list.isEmpty then return not list:isEmpty() end
    if list.size then return (list:size() or 0) > 0 end
    return false
end

function ISVehicleMechanics:doPartContextMenu(part, x, y)
    local playerObj = getSpecificPlayer(self.playerNum)
    -- Keep vanilla restriction if player is inside a vehicle (unless debug/admin).
    if playerObj and playerObj:getVehicle() ~= nil
       and not (isDebugEnabled() or (isClient() and (isAdmin and isAdmin())))
    then
        return
    end

    local id = part and part:getId()
    local sp = part and part:getScriptPart()
    if sp then
        local hasFixes = false
        local invItem = part:getInventoryItem()  -- nil when NOT installed

        -- Only query FixingManager if something is actually installed
        if invItem ~= nil then
            local ok, fixes = pcall(FixingManager.getFixes, invItem)
            if ok and listHasElements(fixes) then
                hasFixes = true
            end

            -- Fallback: broaden by id patterns, but only if installed
            if not hasFixes and idMatchesPattern(id) then
                hasFixes = true
            end
        end

        -- Toggle based on condition & our decision.
        if part:getCondition() < 100 then
            if hasFixes then
                sp:setRepairMechanic(true)
            end
        elseif sp:isRepairMechanic() then
            sp:setRepairMechanic(false)
        end
    end

    -- Defer to vanilla; normalization ensures no NPEs in tooltips/menus.
    return vanilla_doPartContextMenu(self, part, x, y)
end