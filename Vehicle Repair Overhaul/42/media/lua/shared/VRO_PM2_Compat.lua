--[[
VRO <-> Preventative Maintenance 2 (PM2) compatibility.

When PM2 is installed and VRO is using its own (new) repair system, VRO hands
the WHOLE repair outcome to PM2 and keeps only the wrapper around it:

  PM2 owns : condition change, crit/success/partial/failure/fumble +
             preventative, repair stacks, halo text, and Maintenance XP.
  VRO keeps: the menu, the, material/tool requirements and their
             consumption, the animations, sounds and timing.

To match that, when PM2 is active VRO also:
  * suppresses its own skill-XP award (PM2 grants Maintenance XP instead), and
  * hides its own repair prediction line in the fixer tooltips (PM2's
    "Repair Stats" submenu shows the real chances).

Under VRO's "Old Repair System" option this stays dormant: VRO defers to the
vanilla fixing scripts there, which PM2 already intercepts via ISFixAction.
]]--

VRO_PM2 = VRO_PM2 or {}

-- True when PM2 is installed AND VRO is on its own repair system.
function VRO_PM2.active()
    -- Old Repair System -> VRO uses vanilla fixings, which PM2 handles itself.
    if VRO and VRO.UseVanillaFixingRecipes and VRO.UseVanillaFixingRecipes() then
        return false
    end
    -- Use the activated-mods list so this is consistent on client and server
    -- (PM2's PMTwoServer API only exists server-side).
    local mods = getActivatedMods and getActivatedMods() or nil
    if not mods then return false end
    return mods:contains("PreventativeMaintenanceTwo")
end

-- Map a VRO recipe (its conditionModifier + which fixer tier was used) onto
-- PM2's recipe_bonus, mirroring PM2's own GetRecipeBonus so magnitudes stay
-- consistent with PM2's native recipes:
--   base factor by fixer tier (VRO is 1-based): 1 -> 1.5, 2 -> 1.0, 3+ -> 0.5
--   recipe_bonus = base_factor * conditionModifier
function VRO_PM2.recipeBonus(condMod, fixerIndex)
    condMod = tonumber(condMod) or 1.0
    local idx0 = (tonumber(fixerIndex) or 1) - 1            -- VRO 1-based -> PM2 0-based
    local base_factor = math.max(1.0, 3.0 - idx0) / 2.0     -- 1.5 / 1.0 / 0.5 / 0.5 ...
    return base_factor * condMod
end

-- Hand one repair to PM2 (server-side only; PMTwoServer lives in PM2's server/).
-- `item` is the broken InventoryItem (a loose item, or an installed part's
-- inventory item). Returns true if PM2 handled it (condition, repair stacks,
-- halo text, XP and syncItemFields all done by PM2); false means the caller
-- should fall back to VRO's own math.
function VRO_PM2.applyItemRepair(player, item, condMod, fixerIndex)
    if not VRO_PM2.active() then return false end
    if not (PMTwoServer and PMTwoServer.DoRepair) then return false end
    if not (item and item.getCondition and item.getConditionMax) then return false end
    -- pcall so any PM2-side error can't break a VRO repair; on failure we report
    -- "not handled" and VRO's own formula runs instead.
    local ok = pcall(function()
        PMTwoServer.DoRepair(player, item, VRO_PM2.recipeBonus(condMod, fixerIndex), nil, nil)
    end)
    return ok == true
end

return VRO_PM2