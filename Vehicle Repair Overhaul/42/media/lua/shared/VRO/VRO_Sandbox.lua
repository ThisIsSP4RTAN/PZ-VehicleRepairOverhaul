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
    -- top-level key
    if SandboxVars.VRO_IsEngineRebuildEnabled ~= nil then
        SandboxVars.VRO_IsEngineRebuildEnabled = false
    end
    -- nested table key (back-compat)
    if SandboxVars.VRO and SandboxVars.VRO.IsEngineRebuildEnabled ~= nil then
        SandboxVars.VRO.IsEngineRebuildEnabled = false
    end
end

if Events and Events.OnGameStart     then Events.OnGameStart.Add(_forceDisableEngineRebuildSandbox) end
if Events and Events.OnServerStarted then Events.OnServerStarted.Add(_forceDisableEngineRebuildSandbox) end

-- Returns true if the Engine Rebuild feature is enabled (default OFF)
function VRO.IsEngineRebuildEnabled()
    -- Hard gate: conflicting mod(s) active → OFF
    if _isAnyConflictingModActive() then
        return false
    end

    if not SandboxVars then return false end
    if SandboxVars.VRO_IsEngineRebuildEnabled ~= nil then
        return SandboxVars.VRO_IsEngineRebuildEnabled == true
    end
    if SandboxVars.VRO and SandboxVars.VRO.IsEngineRebuildEnabled ~= nil then
        return SandboxVars.VRO.IsEngineRebuildEnabled == true
    end
    return false
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