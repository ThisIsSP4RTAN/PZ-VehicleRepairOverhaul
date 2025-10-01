-- Vehicle Repair Overhaul — Sandbox helper

VRO = VRO or {}

-- Returns true if the Engine Rebuild feature is enabled (default ON)
function VRO.IsEngineRebuildEnabled()
    -- SandboxVars exists once a game is loading/loaded.
    if SandboxVars and SandboxVars.VRO_EnableEngineRebuild ~= nil then
        return SandboxVars.VRO_EnableEngineRebuild == true
    end
    return true
end

-- NEW: Prefer vanilla fixing (script recipes) vs our Lua ones (default OFF)
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
