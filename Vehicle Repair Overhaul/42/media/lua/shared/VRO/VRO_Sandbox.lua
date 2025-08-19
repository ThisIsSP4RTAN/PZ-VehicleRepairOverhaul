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
