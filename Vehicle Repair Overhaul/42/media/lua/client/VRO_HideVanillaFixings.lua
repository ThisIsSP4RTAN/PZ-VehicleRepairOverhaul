require "ISUI/ISInventoryPaneContextMenu"

-- Names must match the Fixing entry names exactly.
local HIDE_BY_NAME = {
    "Fix Gas Tank Welding",
    "Fix Trailer Welding",
    "Fix Trunk Welding",
    "Fix Hood Welding",
    "Fix Hood",
    "Fix Trunk Lid Welding",
    "Fix Trunk Lid",
    "Fix Door Welding",
    "Fix Glove box",
    "Fix Car seat",
}

-- Optional: also hide by required item fullType(s)
local HIDE_BY_REQUIRE_FULLTYPE = {
    -- e.g., "Base.EngineDoor1",
}

local HIDE_PREDICATES = {
    -- function(fixing, brokenObject) return false end,
}

-- Internals
local _nameSet = {}
for _, n in ipairs(HIDE_BY_NAME) do _nameSet[n] = true end

local _reqSet = {}
for _, ft in ipairs(HIDE_BY_REQUIRE_FULLTYPE) do _reqSet[ft] = true end

local function _shouldHideFixing(fixing, brokenObject)
    local name = fixing and fixing:getName() or nil
    if name and _nameSet[name] then return true end

    if fixing and fixing.getRequiredItem then
        local req = fixing:getRequiredItem()
        if req and req.size then
            for i = 0, req:size()-1 do
                local ft = req:get(i)
                if _reqSet[ft] then return true end
            end
        end
    end

    for _, pred in ipairs(HIDE_PREDICATES) do
        local ok, res = pcall(function() return pred(fixing, brokenObject) end)
        if ok and res then return true end
    end
    return false
end

-- Wrap vanilla so hidden recipes never get added
local _orig_buildFixingMenu = ISInventoryPaneContextMenu.buildFixingMenu
if _orig_buildFixingMenu then
    ISInventoryPaneContextMenu.buildFixingMenu = function(brokenObject, player, fixing, fixingNum, fixOption, subMenuFix, vehiclePart)
        if _shouldHideFixing(fixing, brokenObject) then return end
        return _orig_buildFixingMenu(brokenObject, player, fixing, fixingNum, fixOption, subMenuFix, vehiclePart)
    end
end

-- Tiny runtime API
VRO_HideVanillaFixings = VRO_HideVanillaFixings or {}
function VRO_HideVanillaFixings.hideByName(name) _nameSet[name] = true end
function VRO_HideVanillaFixings.hideByRequire(fullType) _reqSet[fullType] = true end
function VRO_HideVanillaFixings.hideIf(fn) table.insert(HIDE_PREDICATES, fn) end