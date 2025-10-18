require "ISUI/ISInventoryPaneContextMenu"

-- Names must match the Fixing entry names exactly.
-- These are ALWAYS hidden, regardless of sandbox option.
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
    "Fix DAMN Trunk Welding", -- KI5
}

-- Optional: also ALWAYS hide by required item fullType(s)
local HIDE_BY_REQUIRE_FULLTYPE = {
    -- e.g., "Base.EngineDoor1",
}

-- Optional: ALWAYS hide with custom predicates
local HIDE_PREDICATES = {
    -- function(fixing, brokenObject) return false end,
}

-- Vanilla "Fixing" recipes that correspond to OUR Lua recipes.
-- These are hidden ONLY when we prefer Lua (i.e., vanilla should be hidden).
local OURS_BY_NAME = {
    "VRO Fix Gas Tank Welding",
    "VRO Fix Gas Tank",
    "VRO Fix Gas Tank Small Welding",
    "VRO Fix Gas Tank Small",
    "VRO Fix Trailer Welding",
    "VRO Fix Trailer",
    "VRO Fix Trailer 1",
    "VRO Fix Trailer Lids Welding",
    "VRO Fix Trailer Lids",
    "VRO Fix Trailer Lids 1",
    "VRO Fix Hood Welding",
    "VRO Fix Hood",
    "VRO Fix Military Hood Welding",
    "VRO Fix Military Hood",
    "VRO Fix KI5 Wood Parts",
    "VRO Fix Small Trunk Welding",
    "VRO Fix Small Trunk",
    "VRO Fix Small Trunk 1",
    "VRO Fix Trunk Welding",
    "VRO Fix Trunk",
    "VRO Fix Trunk 1",
    "VRO Fix Trunk Welding Military",
    "VRO Fix Trunk Military",
    "VRO Fix Trunk Door Welding",
    "VRO Fix Trunk Door",
    "VRO Fix Trunk Door Welding Military",
    "VRO Fix Trunk Door Military",
    "VRO Fix Door Welding",
    "VRO Fix Door",
    "VRO Fix Door 1",
    "VRO Fix Door Welding Military",
    "VRO Fix Door Military",
    "VRO Fix Glove box",
    "VRO Fix Glove box 1",
    "VRO Fix Glove Box Welding",
    "VRO Fix Car seat",
    "VRO Fix Car seat 1",
    "VRO Fix Car seat 2",
    "VRO Fix Car seat 4",
    "VRO Fix Tire",
    "VRO Fix Military Tire",
    "VRO Fix Small Brake",
    "VRO Fix Small Brake Welding",
    "VRO Fix Brake",
    "VRO Fix Brake Welding",
    "VRO Fix Military Brake Welding",
    "VRO Fix Battery",
    "VRO Fix Large Battery",
    "VRO Fix Small Suspension Welding",
    "VRO Fix Small Suspension 1",
    "VRO Fix Suspension Welding",
    "VRO Fix Suspension 1",
    "VRO Fix Military Suspension Welding",
    "VRO Fix Military Suspension 1",
    "VRO Fix Muffler Small Welding",
    "VRO Fix Muffler Small",
    "VRO Fix Muffler Small 1",
    "VRO Fix Muffler Welding",
    "VRO Fix Muffler",
    "VRO Fix Muffler 1",
    "VRO Fix Window Welding",
    "VRO Fix Window",
    "VRO Fix Window 1",
    "VRO Fix Military Windows Welding",
    "VRO Fix Radio",
    "VRO Fix Light",
    "VRO Fix Roof Rack Welding",
    "VRO Fix Roof Rack",
    "VRO Fix Roof Rack 1",
    "VRO Fix Bullbar Welding",
    "VRO Fix Bullbar",
    "VRO Fix Bullbar 1",
    "VRO Fix Saddlebags Hard",
    "VRO Fix Saddlebags Hard 1",
    "VRO Fix SoftTops",
    "VRO Fix SoftTops 1",
    "VRO Fix Panels Welding",
    "VRO Fix Panels",
    "VRO Fix Panels 1",
    "VRO Fix Tank Containers",
    "VRO Fix Vehicle Shovel",
    "VRO Fix Tire FixAFlat",
}

-- Optional: hide these ONLY when using Lua recipes, by required item fullType
local OURS_BY_REQUIRE_FULLTYPE = {
    -- e.g., "Base.NormalGasTank1",
}

-- Optional: predicates that hide ONLY when using Lua recipes
local OURS_PREDICATES = {
    -- function(fixing, brokenObject) return false end,
}

-- Internals
local _alwaysNameSet = {}
for _, n in ipairs(HIDE_BY_NAME) do _alwaysNameSet[n] = true end

local _alwaysReqSet = {}
for _, ft in ipairs(HIDE_BY_REQUIRE_FULLTYPE) do _alwaysReqSet[ft] = true end

local _oursNameSet = {}
for _, n in ipairs(OURS_BY_NAME) do _oursNameSet[n] = true end

local _oursReqSet = {}
for _, ft in ipairs(OURS_BY_REQUIRE_FULLTYPE) do _oursReqSet[ft] = true end

local function _inReqSet(fixing, reqSet)
    if not (fixing and fixing.getRequiredItem) then return false end
    local req = fixing:getRequiredItem()
    if not (req and req.size) then return false end
    for i = 0, req:size()-1 do
        local ft = req:get(i)
        if reqSet[ft] then return true end
    end
    return false
end

local function _anyTrue(preds, fixing, brokenObject)
    for _, pred in ipairs(preds) do
        local ok, res = pcall(function() return pred(fixing, brokenObject) end)
        if ok and res then return true end
    end
    return false
end

-- Prefer Lua when the sandbox toggle is OFF.
-- Read via helper if available; otherwise support both var shapes.
local function _preferLuaRecipes()
    if VRO and VRO.UseVanillaFixingRecipes then
        return not VRO.UseVanillaFixingRecipes()
    end
    if SandboxVars then
        if SandboxVars.VRO_UseVanillaFixingRecipes ~= nil then
            return not SandboxVars.VRO_UseVanillaFixingRecipes
        end
        if SandboxVars.VRO and SandboxVars.VRO.UseVanillaFixingRecipes ~= nil then
            return not SandboxVars.VRO.UseVanillaFixingRecipes
        end
    end
    return true
end

local function _shouldHideFixing(fixing, brokenObject)
    local name = fixing and fixing.getName and fixing:getName() or nil

    -- ALWAYS hidden group
    if name and _alwaysNameSet[name] then return true end
    if _inReqSet(fixing, _alwaysReqSet) then return true end
    if _anyTrue(HIDE_PREDICATES, fixing, brokenObject) then return true end

    -- OURS group (only when preferring Lua)
    if _preferLuaRecipes() then
        if name and _oursNameSet[name] then return true end
        if _inReqSet(fixing, _oursReqSet) then return true end
        if _anyTrue(OURS_PREDICATES, fixing, brokenObject) then return true end
    end

    return false
end

-- Wrap vanilla so hidden recipes never get added
if not _G.VRO_HIDEVANILLA_WRAPPED then
    local _orig_buildFixingMenu = ISInventoryPaneContextMenu.buildFixingMenu
    if _orig_buildFixingMenu then
        ISInventoryPaneContextMenu.buildFixingMenu = function(brokenObject, player, fixing, fixingNum, fixOption, subMenuFix, vehiclePart)
            if _shouldHideFixing(fixing, brokenObject) then return end
            return _orig_buildFixingMenu(brokenObject, player, fixing, fixingNum, fixOption, subMenuFix, vehiclePart)
        end
    end
    _G.VRO_HIDEVANILLA_WRAPPED = true
end

-- Tiny runtime API
VRO_HideVanillaFixings = VRO_HideVanillaFixings or {}

-- ALWAYS hide
function VRO_HideVanillaFixings.hideByName(name) _alwaysNameSet[name] = true end
function VRO_HideVanillaFixings.hideByRequire(fullType) _alwaysReqSet[fullType] = true end
function VRO_HideVanillaFixings.hideIf(fn) table.insert(HIDE_PREDICATES, fn) end

-- Hide ONLY when preferring Lua
function VRO_HideVanillaFixings.hideOursByName(name) _oursNameSet[name] = true end
function VRO_HideVanillaFixings.hideOursByRequire(fullType) _oursReqSet[fullType] = true end
function VRO_HideVanillaFixings.hideOursIf(fn) table.insert(OURS_PREDICATES, fn) end