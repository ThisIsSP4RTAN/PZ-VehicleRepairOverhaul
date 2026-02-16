VRO = VRO or {}
-- Default ON.
function VRO.IsFullVehicleSalvagingEnabled()
    if not SandboxVars then return true end

    -- normal (top-level) sandbox var
    if SandboxVars.VRO_EnableFullVehicleSalvaging ~= nil then
        return SandboxVars.VRO_EnableFullVehicleSalvaging == true
    end

    -- backward-compat if someone shipped a nested "VRO" table
    if SandboxVars.VRO and SandboxVars.VRO.EnableFullVehicleSalvaging ~= nil then
        return SandboxVars.VRO.EnableFullVehicleSalvaging == true
    end

    return true
end
