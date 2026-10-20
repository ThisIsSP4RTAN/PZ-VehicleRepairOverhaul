VRO = VRO or {}
-- Mods that force Engine Rebuild OFF while active
local DISABLE_ENGINE_REBUILD_WHEN_MODS = {
    "ProjectSummerCar",
    "Ivmakk_RestoreEngineQuality",
    "MaskaradsSummerCar",
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

-- Disable diminishing repairs: when ON, repairing a part does NOT increase its
-- HaveBeenRepaired counter, so repairs never get progressively harder/weaker.
-- Default OFF (repairs diminish as normal).
function VRO.IsDiminishingRepairsDisabled()
    if not SandboxVars then return false end
    -- normal (top-level) sandbox var
    if SandboxVars.VRO_DisableDiminishingRepairs ~= nil then
        return SandboxVars.VRO_DisableDiminishingRepairs == true
    end
    -- backward-compat if someone shipped a nested "VRO" table
    if SandboxVars.VRO and SandboxVars.VRO.DisableDiminishingRepairs ~= nil then
        return SandboxVars.VRO.DisableDiminishingRepairs == true
    end
    return false
end

-- Allow repairing fully broken (0 condition) parts, whether loose or installed 
-- on a vehicle. Default OFF. (Windows/tires/fix-a-flat parts are excluded from 
-- this in the fixing UI regardless of this setting.)
function VRO.CanRepairFullyBrokenParts()
    if not SandboxVars then return false end
    -- normal (top-level) sandbox var
    if SandboxVars.VRO_RepairFullyBrokenParts ~= nil then
        return SandboxVars.VRO_RepairFullyBrokenParts == true
    end
    -- backward-compat if someone shipped a nested "VRO" table
    if SandboxVars.VRO and SandboxVars.VRO.RepairFullyBrokenParts ~= nil then
        return SandboxVars.VRO.RepairFullyBrokenParts == true
    end
    return false
end

-- Disable the "uninstall another part first" requirement for repairs (a tire over
-- the brakes/suspension, armor over a window, etc.). When ON, such parts can be
-- repaired with the blocking part still installed and the tooltip warning is
-- hidden. Default OFF (the requirement applies, mirroring vanilla's uninstall rules).
function VRO.IsUninstallRequirementDisabled()
    if not SandboxVars then return false end
    -- normal (top-level) sandbox var
    if SandboxVars.VRO_DisableUninstallRequirement ~= nil then
        return SandboxVars.VRO_DisableUninstallRequirement == true
    end
    -- backward-compat if someone shipped a nested "VRO" table
    if SandboxVars.VRO and SandboxVars.VRO.DisableUninstallRequirement ~= nil then
        return SandboxVars.VRO.DisableUninstallRequirement == true
    end
    return false
end

-- Draw repair materials/tools from nearby containers. Default ON.
function VRO.UseNearbyContainers()
    if not SandboxVars then return true end
    -- normal (top-level) sandbox var
    if SandboxVars.VRO_UseNearbyContainers ~= nil then
        return SandboxVars.VRO_UseNearbyContainers == true
    end
    -- backward-compat if someone shipped a nested "VRO" table
    if SandboxVars.VRO and SandboxVars.VRO.UseNearbyContainers ~= nil then
        return SandboxVars.VRO.UseNearbyContainers == true
    end
    return true
end

-- Also draw from items lying on the ground within reach. Default ON.
function VRO.SearchNearbyGroundItems()
    if not SandboxVars then return true end
    -- normal (top-level) sandbox var
    if SandboxVars.VRO_SearchNearbyGroundItems ~= nil then
        return SandboxVars.VRO_SearchNearbyGroundItems == true
    end
    -- backward-compat if someone shipped a nested "VRO" table
    if SandboxVars.VRO and SandboxVars.VRO.SearchNearbyGroundItems ~= nil then
        return SandboxVars.VRO.SearchNearbyGroundItems == true
    end
    return true
end