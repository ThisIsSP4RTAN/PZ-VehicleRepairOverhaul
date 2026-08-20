VRO = VRO or {}
-- Mods that force Engine Rebuild OFF while active
local DISABLE_ENGINE_REBUILD_WHEN_MODS = {
    "ProjectSummerCar",
    "Ivmakk_RestoreEngineQuality",
}

local function _isAnyConflictingModActive()
    local mods = getActivatedMods and getActivatedMods()
    if not mods then return false end
    for i = 1, #DISABLE_ENGINE_REBUILD_WHEN_MODS do
        if mods:contains(DISABLE_ENGINE_REBUILD_WHEN_MODS[i]) then
            return true
        end
    end
    return false
end

-- If a conflicting mod is active, force the sandbox var(s) OFF at load
local function _forceDisableEngineRebuildSandbox()
    if not _isAnyConflictingModActive() or not SandboxVars then return end
    -- old key
    if SandboxVars.VRO_IsEngineRebuildEnabled ~= nil then
        SandboxVars.VRO_IsEngineRebuildEnabled = false
    end
    if SandboxVars.VRO and SandboxVars.VRO.IsEngineRebuildEnabled ~= nil then
        SandboxVars.VRO.IsEngineRebuildEnabled = false
    end
    -- new key
    if SandboxVars.VRO_EnableEngineRebuild ~= nil then
        SandboxVars.VRO_EnableEngineRebuild = false
    end
    if SandboxVars.VRO and SandboxVars.VRO.EnableEngineRebuild ~= nil then
        SandboxVars.VRO.EnableEngineRebuild = false
    end
end

if Events and Events.OnGameStart     then Events.OnGameStart.Add(_forceDisableEngineRebuildSandbox) end
if Events and Events.OnServerStarted then Events.OnServerStarted.Add(_forceDisableEngineRebuildSandbox) end

-- Returns true if the Engine Rebuild feature is enabled (default OFF)
function VRO.IsEngineRebuildEnabled()
    -- Hard gate: conflicting mod(s) active → OFF
    if _isAnyConflictingModActive() then return false end
    if not SandboxVars then return false end

    local sv = SandboxVars
    -- Accept BOTH naming styles (top-level and nested):
    local v =
        (sv.VRO_IsEngineRebuildEnabled ~= nil and sv.VRO_IsEngineRebuildEnabled)
        or (sv.VRO and sv.VRO.IsEngineRebuildEnabled ~= nil and sv.VRO.IsEngineRebuildEnabled)
        or (sv.VRO_EnableEngineRebuild ~= nil and sv.VRO_EnableEngineRebuild)
        or (sv.VRO and sv.VRO.EnableEngineRebuild ~= nil and sv.VRO.EnableEngineRebuild)
        or false

    return v == true
end

-- Prefer vanilla fixing (script recipes) vs our Lua ones (default OFF)
function VRO.UseVanillaFixingRecipes()
    if not SandboxVars then return false end
    -- normal (top-level) sandbox var
    if SandboxVars.VRO_UseVanillaFixingRecipes ~= nil then
        return SandboxVars.VRO_UseVanillaFixingRecipes == true
    end
    -- backward-compat if someone shipped a nested "VRO" table
    if SandboxVars.VRO and SandboxVars.VRO.UseVanillaFixingRecipes ~= nil then
        return SandboxVars.VRO.UseVanillaFixingRecipes == true
    end
    return false
end

-- Read B42's live option object instead of the SandboxVars table, which is a
-- startup snapshot.  SandboxVars remains the fallback for older builds and for
-- the short period before the live options object is available.
local function _getLiveSandboxValue(name)
    if not getSandboxOptions then return nil end

    local ok, sandboxOptions = pcall(getSandboxOptions)
    if not (ok and sandboxOptions and sandboxOptions.getOptionByName) then return nil end

    local optionOk, option = pcall(function()
        return sandboxOptions:getOptionByName(name)
    end)
    if not (optionOk and option and option.getValue) then return nil end

    local valueOk, value = pcall(function() return option:getValue() end)
    if valueOk then return value end
    return nil
end

local function _getNearbySandboxValue(name, legacyKey)
    local value = _getLiveSandboxValue(name)
    if value ~= nil then return value end
    if not SandboxVars then return nil end
    if SandboxVars[name] ~= nil then return SandboxVars[name] end
    if SandboxVars.VRO and SandboxVars.VRO[legacyKey] ~= nil then
        return SandboxVars.VRO[legacyKey]
    end
    return nil
end

-- Nearby-material options are resolved on each menu/action build, so changing
-- them during a running B42 game takes effect without reloading Lua.
function VRO.UseNearbyContainers()
    local value = _getNearbySandboxValue("VRO_UseNearbyContainers", "UseNearbyContainers")
    return value == nil or value == true
end

function VRO.GetNearbySearchRadius()
    local value = _getNearbySandboxValue("VRO_NearbySearchRadius", "NearbySearchRadius")
    value = tonumber(value) or 2
    return math.max(1, math.min(10, math.floor(value)))
end

function VRO.SearchNearbyGroundItems()
    local value = _getNearbySandboxValue("VRO_SearchNearbyGroundItems", "SearchNearbyGroundItems")
    return value == nil or value == true
end
