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

function VRO.GetSalvageTime(varName, default)
    local fallback = tonumber(default) or 100

    if not SandboxVars or not varName then
        return fallback
    end

    local v = SandboxVars[varName]

    if v == nil and SandboxVars.VRO then
        local nestedKey = tostring(varName):gsub("^VRO_", "")
        v = SandboxVars.VRO[nestedKey]
    end

    v = tonumber(v)
    if v and v >= 1 then
        return math.floor(v)
    end

    return fallback
end