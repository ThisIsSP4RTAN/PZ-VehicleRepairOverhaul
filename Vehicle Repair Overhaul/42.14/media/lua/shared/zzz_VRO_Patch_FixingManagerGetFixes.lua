if isClient() then return end

if FixingManager and FixingManager.getFixes and not FixingManager._VRO_orig_getFixes then
    FixingManager._VRO_orig_getFixes = FixingManager.getFixes

    local function _VRO_safeGetFixes_Fallback(item)
        if not item or not item.getFullType then
            return nil
        end

        local ft = item:getFullType()
        if not ft then
            return nil
        end

        if not (ScriptManager and ScriptManager.instance and ScriptManager.instance.getAllFixing) then
            return nil
        end

        if not ArrayList then
            return nil
        end

        local sm = ScriptManager.instance

        local all = ArrayList.new()
        local okAll = pcall(function()
            sm:getAllFixing(all)
        end)
        if not okAll then
            return nil
        end

        local out = ArrayList.new()

        for i = 0, all:size() - 1 do
            local fixing = all:get(i)
            if fixing and fixing.getRequiredItem then
                local req = fixing:getRequiredItem()
                if req and req.contains and req:contains(ft) then
                    out:add(fixing)
                end
            end
        end

        return out
    end

    FixingManager.getFixes = function(item)
        if not item then
            return nil
        end

        local ok, res = pcall(FixingManager._VRO_orig_getFixes, item)
        if ok and res then
            return res
        end

        return _VRO_safeGetFixes_Fallback(item)
    end
end