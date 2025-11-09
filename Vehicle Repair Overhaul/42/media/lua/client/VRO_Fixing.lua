---@diagnostic disable: undefined-field, param-type-mismatch, redundant-parameter

require "Vehicles/ISUI/ISVehicleMechanics"
require "ISUI/ISToolTip"
require "ISUI/ISInventoryPaneContextMenu"
require "TimedActions/ISBaseTimedAction"
require "TimedActions/ISPathFindAction"
require "TimedActions/ISEquipWeaponAction"
require "TimedActions/ISUnequipAction"
require "VRO_DoFixAction"

local VRO = require "VRO/Core"
VRO.__index = VRO
VRO.Recipes = VRO.Recipes or {}
--[[  (recipes injected via VRO_Recipes.lua)  ]]

----------------------------------------------------------------
-- Sandbox toggle (hide our Lua options if vanilla-only is selected)
----------------------------------------------------------------
local function VRO_UseVanillaFixingRecipes()
  if VRO and VRO.UseVanillaFixingRecipes then
    return VRO.UseVanillaFixingRecipes()
  end
  if SandboxVars then
    if SandboxVars.VRO_UseVanillaFixingRecipes ~= nil then
      return SandboxVars.VRO_UseVanillaFixingRecipes == true
    end
    if SandboxVars.VRO and SandboxVars.VRO.UseVanillaFixingRecipes ~= nil then
      return SandboxVars.VRO.UseVanillaFixingRecipes == true
    end
  end
  return false
end

----------------------------------------------------------------
-- A) Helpers
----------------------------------------------------------------
-- Does this fullType exist in ScriptManager?
local function isScriptedItem(fullType)
  if not fullType then return false end
  local sm = ScriptManager and ScriptManager.instance
  if not sm then return false end
  if sm.FindItem then return sm:FindItem(fullType) ~= nil end
  if sm.getItem  then return sm:getItem(fullType)  ~= nil end
  return false
end

-- Remove any fixer entries whose 'item' isn't a real scripted item.
local function VRO_PruneMissingFixers()
  for ri = 1, #VRO.Recipes do
    local fixing = VRO.Recipes[ri]
    local fxr = fixing and fixing.fixers
    if type(fxr) == "table" and #fxr > 0 then
      local kept = {}
      for i = 1, #fxr do
        local f = fxr[i]
        -- keep only valid fixer entries
        if f and f.item and isScriptedItem(f.item) then
          kept[#kept + 1] = f
        end
      end
      fixing.fixers = kept
    end
  end
end

-- Optional external recipe loader (keeps existing list; append from another file if present)
local function _appendRecipesFrom(source)
  local out = VRO.Recipes
  if type(source) == "table" then
    local list = source.recipes
    if type(list) == "table" and list[1] ~= nil then
      for i = 1, #list do out[#out + 1] = list[i] end
    elseif source[1] ~= nil then
      for i = 1, #source do out[#out + 1] = source[i] end
    elseif source.name ~= nil then
      out[#out + 1] = source
    end
  elseif type(source) == "function" then
    local ok, tbl = pcall(source)
    if ok and type(tbl) == "table" then _appendRecipesFrom(tbl) end
  end
end

local function VRO_LoadExternalRecipes()

  local ok, mod = pcall(require, "VRO/Recipes")
  if ok and mod then _appendRecipesFrom(mod) end

  ok, mod = pcall(require, "VRO_Recipes")
  if ok and mod then _appendRecipesFrom(mod) end
end
VRO_LoadExternalRecipes()

-- Named Part Lists (optional external file): define lists once, reuse in recipes
-- File format suggestion: media/lua/client/VRO_PartLists.lua -> return { ListName = { "Base.Foo", ... }, ... }
VRO.PartLists = VRO.PartLists or {}
local function VRO_LoadPartLists()
  local ok, mod = pcall(require, "VRO_PartLists")
  if ok and type(mod) == "table" then
    for k,v in pairs(mod) do VRO.PartLists[k] = v end
  end
end
VRO_LoadPartLists()
VRO_PruneMissingFixers()

-- === Access Overrides loader (module-first, no globals) ===
VRO.AccessOverrides = VRO.AccessOverrides or {}

local function _merge(dst, src)
  if type(dst) ~= "table" or type(src) ~= "table" then return end
  for k, v in pairs(src) do dst[k] = v end
end

local function VRO_LoadAccessOverrides()
  -- Prefer namespaced path; fall back to legacy filename if you haven’t moved it yet
  local ok, mod = pcall(require, "VRO/AccessOverrides")
  if not ok or type(mod) ~= "table" then
    ok, mod = pcall(require, "VRO_AccessOverrides")
  end
  if ok and type(mod) == "table" then
    _merge(VRO.AccessOverrides, mod)
    return
  end
end
VRO_LoadAccessOverrides()

-- Expand a single "require" entry into a set of full types.
-- Supports:
--   "Base.Something"
--   "@ListName"                       -- pulls from VRO.PartLists[ListName]
--   { list="ListName" } / { requireList="ListName" }
--   { "@ListName", "Base.Other", ... }  (nested arrays)
local function _expandRequireEntry(entry, out_set, seenLists)
  seenLists = seenLists or {}
  local t = type(entry)

  if t == "string" then
    if string.sub(entry,1,1) == "@" then
      local key = string.sub(entry,2)
      if key ~= "" and not seenLists[key] then
        seenLists[key] = true
        local lst = VRO.PartLists[key]
        if type(lst) == "table" then
          for i = 1, #lst do
          local ft = lst[i]
          out_set[ft] = true
        end
        else
          print("[VRO] Part list not found: " .. tostring(key))
        end
      end
    else
      out_set[entry] = true
    end
    return
  end

  if t == "table" then
    local key = entry.list or entry.requireList
    if type(key) == "string" then
      _expandRequireEntry("@"..key, out_set, seenLists)
      return
    end
    local n = #entry
    if n > 0 then
      for i = 1, n do _expandRequireEntry(entry[i], out_set, seenLists) end
      return
    end
  end
end

-- Returns a set { fullType=true, ... } for recipe's require/requireLists
local function resolveRequireSet(fixing)
  local set = {}
  if fixing then
    if fixing.require ~= nil then
      _expandRequireEntry(fixing.require, set)
    end
    if fixing.requireLists ~= nil then
      if type(fixing.requireLists) == "string" then
        _expandRequireEntry("@"..fixing.requireLists, set)
      elseif type(fixing.requireLists) == "table" then
        local rl = fixing.requireLists
        for i = 1, #rl do
          _expandRequireEntry("@"..tostring(rl[i]), set)
        end
      end
    end
  end
  return set
end

local function isDrainable(it) return it and instanceof(it,"DrainableComboItem") end
local function drainableUses(it)
  if not it then return 0 end
  if isDrainable(it) then
    if it.getDrainableUsesInt then return it:getDrainableUsesInt() end
    if it.getCurrentUses then return it:getCurrentUses() end
    if it.getUsedDelta and it.getUseDelta then
      local used, step = it:getUsedDelta(), it:getUseDelta()
      if step and step > 0 then return math.max(0, math.floor((1.0 - used) / step + 0.0001)) end
    end
    return 0
  end
  return 1
end

local function findFirstTypeRecurse(inv, fullType)
  local bagged = ArrayList.new()
  inv:getAllTypeRecurse(fullType, bagged)
  if bagged:isEmpty() then return nil end
  return bagged:get(0)
end

local function countTypeRecurse(inv, fullType)
  local bagged = ArrayList.new()
  inv:getAllTypeRecurse(fullType, bagged)
  return bagged:size()
end

local function gatherRequiredItems(inv, fullType, needUses)
  local bagged = ArrayList.new()
  inv:getAllTypeRecurse(fullType, bagged)
  if bagged:isEmpty() then return nil end
  local list, total = {}, 0
  for i = 1, bagged:size() do
    local it = bagged:get(i-1)
    local u  = drainableUses(it)
    if u>0 then
      local take = math.min(u, needUses-total)
      list[#list+1] = { item=it, takeUses=take }
      total = total + take
      if total >= needUses then return list end
    end
  end
  return nil
end

-- Tag helpers
local function firstTagItem(inv, tag) return inv:getFirstTagRecurse(tag) end
local function hasTag(inv, tag) return inv:containsTag(tag) end

-- NEW: multi-tag helpers
local function _splitTagsString(s)
  local out = {}
  for t in string.gmatch(s, "([^,%s]+)") do out[#out+1] = t end
  return out
end

local function normalizeTagsField(gi)
  if not gi then return nil end
  if gi.tags ~= nil then
    if type(gi.tags) == "string" then
      local arr = _splitTagsString(gi.tags)
      return (#arr > 0) and arr or nil
    elseif type(gi.tags) == "table" then
      -- assume array of strings
      if gi.tags[1] then return gi.tags end
    end
  end
  if gi.tag ~= nil and type(gi.tag) == "string" then
    return { gi.tag }
  end
  return nil
end

local function itemHasAnyTag(it, tags)
  if not (it and it.hasTag and tags) then return false end
  for i = 1, #tags do
  local t = tags[i]
  if it:hasTag(t) then return true end
end
  return false
end

-- Best single item by *one* tag (favor meeting needUses for drainables; else fullest)
local function findBestByTag(inv, tag, needUses)
  needUses = needUses or 1
  if inv.getFirstEvalRecurse then
    local it = inv:getFirstEvalRecurse(function(item)
      return item and item.hasTag and item:hasTag(tag) and (not isDrainable(item) or drainableUses(item) >= needUses)
    end)
    if it then return it end
  end
  if inv.getBestEvalRecurse then
    local best = inv:getBestEvalRecurse(
      function(item) return item and item.hasTag and item:hasTag(tag) end,
      function(a,b)
        local ua = isDrainable(a) and drainableUses(a) or 1
        local ub = isDrainable(b) and drainableUses(b) or 1
        return ua - ub
      end)
    if best then return best end
  end
  return firstTagItem(inv, tag)
end

-- NEW: best item by ANY of multiple tags
local function findBestByTags(inv, tags, needUses)
  needUses = needUses or 1
  if inv.getFirstEvalRecurse then
    local it = inv:getFirstEvalRecurse(function(item)
      return item and item.hasTag and itemHasAnyTag(item, tags) and (not isDrainable(item) or drainableUses(item) >= needUses)
    end)
    if it then return it end
  end
  if inv.getBestEvalRecurse then
    local best = inv:getBestEvalRecurse(
      function(item) return item and item.hasTag and itemHasAnyTag(item, tags) end,
      function(a,b)
        local ua = isDrainable(a) and drainableUses(a) or 1
        local ub = isDrainable(b) and drainableUses(b) or 1
        return ua - ub
      end
    )
    if best then return best end
  end
  for i = 1, #tags do
    local t = tags[i]
    local it = firstTagItem(inv, t)
    if it then return it end
  end
  return nil
end

local function displayNameFromFullType(fullType)
  if getItemNameFromFullType then
    local nm = getItemNameFromFullType(fullType)
    if nm and nm ~= "" then return nm end
  end
  return fullType
end

local function displayNameForTag(inv, tag)
  local it = firstTagItem(inv, tag)
  return (it and it.getDisplayName and it:getDisplayName()) or tag
end

-- NEW: display for multi-tags (first present wins; else Tag1/Tag2)
local function displayNameForTags(inv, tags)
  if not (tags and tags[1] ~= nil) then
    return nil
  end
  for i = 1, #tags do
    local t  = tags[i]
    local it = firstTagItem(inv, t)
    if it and it.getDisplayName then
      return it:getDisplayName()
    end
  end
  return table.concat(tags, "/")
end

local function humanizeForMenuLabel(name)
  if string.sub(name,1,6) == "Small " then return string.sub(name,7) .. " - Small" end
  return name
end

-- HaveBeenRepaired persistence
local function getHBR(part, invItem)
  if invItem and invItem.getHaveBeenRepaired then return invItem:getHaveBeenRepaired() end
  local md = part and part:getModData() or {}
  return md.VRO_HaveBeenRepaired or 0
end

-- Tooltip icon from script data (vanilla-style)
local function setTooltipIconFromFullType(tip, fullType)
  if not (tip and fullType) then return end

  -- Resolve the ScriptItem (global getItem works well for mod items)
  local si = (getItem and getItem(fullType))
          or (ScriptManager and ScriptManager.instance and (
                (ScriptManager.instance.FindItem and ScriptManager.instance:FindItem(fullType)) or
                (ScriptManager.instance.getItem  and ScriptManager.instance:getItem(fullType))
             ))
  if not si then return end

  -- Preferred: use the actual Texture object
  local tex = si.getNormalTexture and si:getNormalTexture() or nil
  if tex then
    if tip.setTextureDirectly then
      tip:setTextureDirectly(tex)     -- << correct: pass Texture object
    else
      -- very old fall-back if setTextureDirectly isn't present
      local name = tex.getName and tex:getName() or nil
      if name then tip:setTexture(name) end
    end
    return
  end

  -- Fallback: use icon name -> "Item_<icon>"
  local icon = (si.getIcon and si:getIcon()) or (si.getTextureName and si:getTextureName())
  if icon and icon ~= "" then
    if not icon:find("^Item_") then icon = "Item_" .. icon end
    tip:setTexture(icon)              -- here we pass a string as expected
  end
end

local function fallbackNameForTag(tag)
  if tag == "WeldingMask" then return "Welder Mask" end
  return tag
end

-- Blowtorch helpers
local function isTorchItem(it)
  if not it then return false end
  if it.hasTag and it:hasTag("BlowTorch") then return true end
  local t = it.getType and it:getType() or ""
  if t == "BlowTorch" then return true end
  local ft = it.getFullType and it:getFullType() or ""
  return ft == "Base.BlowTorch"
end

-- Item must be NOT broken and strictly below max condition to be repairable from inventory
local function isRepairableFromInventory(it)
  if not it then return false end
  if it.isBroken and it:isBroken() then return false end
  local max = it.getConditionMax and it:getConditionMax() or 100
  local cur = it.getCondition   and it:getCondition()    or max
  return cur < max
end

-- Keep-flag helper: array-of-strings → set { flag=true, ... }
local function normalizeFlags(f)
  if f == nil then return nil end

  -- Only handle array form here (map-like tables are ignored as before)
  if type(f) == "table" and f[1] ~= nil then
    local m, n = {}, 0
    for i = 1, #f do
      local k = f[i]
      if type(k) == "string" and m[k] ~= true then
        m[k] = true
        n = n + 1
      end
    end
    return (n > 0) and m or nil
  end
  return nil
end

local function hasFlag(flags, name)
  return flags and flags[name] == true
end

-- Always prefer direct API; fall back to sharpness values
local function isItemDull(it)
  if not it then return false end

  -- Preferred: direct API
  if it.isDull then
    local ok, res = pcall(function() return it:isDull() end)
    if ok then return res == true end
  end

  -- Fallback: infer from sharpness values
  local getS = it.getSharpness
  local getM = it.getMaxSharpness
  if getS then
    local s = 0
    local okS, valS = pcall(function() return it:getSharpness() end)
    if okS then s = tonumber(valS) or 0 end

    if getM then
      local okM, maxS = pcall(function() return it:getMaxSharpness() end)
      if okM and tonumber(maxS) and tonumber(maxS) > 0 then
        return s <= 0
      end
    end
    -- If max is unavailable, zero still means dull
    return s <= 0
  end

  -- Items with no sharpness concept aren’t “dull”
  return false
end

-- Return the best non-dull item that satisfies a single tag.
-- Prefers items with enough drainable uses; otherwise the fullest non-empty.
local function findBestByTagNotDull(inv, tag, needUses)
  needUses = needUses or 1

  -- Fast path: first match that is not dull and has enough uses (if drainable)
  if inv.getFirstEvalRecurse then
    local it = inv:getFirstEvalRecurse(function(item)
      return item
        and item.hasTag and item:hasTag(tag)
        and not isItemDull(item)
        and (not isDrainable(item) or drainableUses(item) >= needUses)
    end)
    if it then return it end
  end

  -- Best path: among non-dull matches, pick the one with most usable “uses”
  if inv.getBestEvalRecurse then
    local best = inv:getBestEvalRecurse(
      function(item)
        return item and item.hasTag and item:hasTag(tag) and not isItemDull(item)
      end,
      function(a, b)
        local ua = isDrainable(a) and drainableUses(a) or 1
        local ub = isDrainable(b) and drainableUses(b) or 1
        return ua - ub
      end
    )
    if best then return best end
  end

  -- Nothing non-dull for this tag
  return nil
end

-- Return the best non-dull item that satisfies ANY of multiple tags.
-- Looks across all tags as a set, then falls back to searching each tag individually.
local function findBestByTagsNotDull(inv, tags, needUses)
  needUses = needUses or 1

  -- Fast path: first non-dull that satisfies any tag and has enough uses
  if inv.getFirstEvalRecurse then
    local it = inv:getFirstEvalRecurse(function(item)
      return item
        and item.hasTag and itemHasAnyTag(item, tags)
        and not isItemDull(item)
        and (not isDrainable(item) or drainableUses(item) >= needUses)
    end)
    if it then return it end
  end

  -- Best path: among non-dull matches for ANY tag, pick fullest
  if inv.getBestEvalRecurse then
    local best = inv:getBestEvalRecurse(
      function(item)
        return item and item.hasTag and itemHasAnyTag(item, tags) and not isItemDull(item)
      end,
      function(a, b)
        local ua = isDrainable(a) and drainableUses(a) or 1
        local ub = isDrainable(b) and drainableUses(b) or 1
        return ua - ub
      end
    )
    if best then return best end
  end

  -- Per-tag fallback: *within the same tag* keep searching for a non-dull candidate
  for i = 1, #tags do
    local t = tags[i]
    local it = findBestByTagNotDull(inv, t, needUses)
    if it then return it end
  end
  return nil
end

-- For NOT-consumed globals (actual tools): only exclude dull items
-- when the flags include IsNotDull. Final post-check guarantees correctness.
local function _pickNonConsumedChoice(inv, gi)
  if not gi then return nil, nil end
  local flags = normalizeFlags(gi.flags)
  local need  = gi.uses or 1
  local tags  = normalizeTagsField(gi)
  local enforceNotDull = hasFlag(flags, "IsNotDull")

  local chosen = nil

  if tags then
    chosen = enforceNotDull and findBestByTagsNotDull(inv, tags, need) or findBestByTags(inv, tags, need)

  elseif gi.tag then
    chosen = findBestByTag(inv, gi.tag, need)
    if enforceNotDull and chosen and isItemDull(chosen) then
      chosen = nil
    end

  elseif gi.item then
    chosen = findFirstTypeRecurse(inv, gi.item)
    if enforceNotDull and chosen and isItemDull(chosen) then
      chosen = nil
    end
  end

  -- Final safety: if the flag demands it, never allow dull
  if chosen and enforceNotDull and isItemDull(chosen) then
    chosen = nil
  end

  return chosen, flags
end

-- check if player has ONE blowtorch with at least N uses
local function hasTorchWithUses(inv, need)
  need = need or 1

  -- fast: recursive evaluator
  if inv.getFirstEvalRecurse then
    local found = inv:getFirstEvalRecurse(function(item)
      return item and isTorchItem(item) and drainableUses(item) >= need
    end)
    if found then return true end
  end

  -- fallback: scan for Base.BlowTorch
  local bag = ArrayList.new()
  inv:getAllTypeRecurse("Base.BlowTorch", bag)
  for i = 0, bag:size() - 1 do
    local it = bag:get(i)
    if drainableUses(it) >= need then
      return true
    end
  end

  return false
end

----------------------------------------------------------------
-- B) Perks + math
----------------------------------------------------------------
local function resolvePerk(perkName)
  if Perks then
    if Perks[perkName] then return Perks[perkName] end
    if Perks.FromString then return Perks.FromString(perkName) end
  end
  return nil
end

local function perkLevel(chr, perkName)
  local perk = resolvePerk(perkName)
  if not perk then return 0 end
  return chr:getPerkLevel(perk)
end

local function chanceOfFail(brokenItem, chr, fixing, fixer, hbr)
  local fail = 3.0
  if fixer.skills then
    for name,req in pairs(fixer.skills) do
      local lvl = perkLevel(chr, name)
      if lvl < req then fail = fail + (req - lvl) * 30
      else              fail = fail - (lvl - req) * 5 end
    end
  end
  fail = fail + (hbr + 1) * 2
  if chr:HasTrait("Lucky")   then fail = fail - 5 end
  if chr:HasTrait("Unlucky") then fail = fail + 5 end
  if fail < 0 then fail = 0 elseif fail > 100 then fail = 100 end
  return fail
end

local function condRepairedPercent(brokenItem, chr, fixing, fixer, hbr, fixerIndex)
  local base = (fixerIndex == 1) and 50.0 or ((fixerIndex == 2) and 20.0 or 10.0)
  base = base * (1.0 / (hbr + 1))
  if fixer.skills then
    for name,req in pairs(fixer.skills) do
      local lvl = perkLevel(chr, name)
      if lvl > req then base = base + math.min((lvl - req) * 5, 25)
      else              base = base - (req - lvl) * 15 end
    end
  end
  base = base * (fixing.conditionModifier or 1.0)
  if base < 0 then base = 0 elseif base > 100 then base = 100 end
  return base
end

local function _getScriptsForTag(tag)
  local sm = ScriptManager and ScriptManager.instance
  if not sm then return nil end
  -- PZ exposes one of these depending on build; try both gracefully
  if sm.getItemsTag then
    return sm:getItemsTag(tag)              -- ArrayList<ScriptItem>
  elseif sm.getAllItemsWithTag then
    return sm:getAllItemsWithTag(tag)       -- ArrayList<ScriptItem>
  end
  return nil
end

local function _scriptFullType(si)
  return (si and si.getFullName) and si:getFullName() or nil
end

local function _scriptDispName(si)
  local ft = _scriptFullType(si)
  if ft and getItemNameFromFullType then
    return getItemNameFromFullType(ft)
  end
  if si and si.getDisplayName then return si:getDisplayName() end
  if si and si.getName then return si:getName() end
  return ft or "?"
end

-- Build a "One of:" block for the given tags, showing the true need amount.
-- Header color:
--   GREEN  = we have at least one eligible non-dull item
--   YELLOW = we have items but all of them are dull
--   RED    = we have none
-- Each line shows "(Dull)" after the "X/Y" count when applicable.
local dullTooltip = getText("Tooltip_dull")
local function _appendOneOfTagsList(desc, inv, tags, need, _unused_forceHeader)
  need = math.max(1, tonumber(need) or 1)

  local added        = {}   -- fullType -> true (avoid dupes across tags)
  local lines        = {}
  local anyHave      = false
  local anyEligible  = false

  local function _disp(si)
    local ft = _scriptFullType(si)
    if ft and getItemNameFromFullType then
      local nm = getItemNameFromFullType(ft)
      if nm and nm ~= "" then return nm end
    end
    return _scriptDispName(si)
  end

  for i = 1, #tags do
    local tag = tags[i]
    local arr = _getScriptsForTag(tag)
    if arr and arr.size and arr:size() > 0 then
      for j = 1, arr:size() do
        local si = arr:get(j - 1)
        local ft = _scriptFullType(si)
        if ft and not added[ft] then
          added[ft] = true
          local have = countTypeRecurse(inv, ft) > 0
          local item = have and findFirstTypeRecurse(inv, ft) or nil
          local dull = item and isItemDull(item) or false

          anyHave     = anyHave     or have
          anyEligible = anyEligible or (have and not dull)

          local rgb = (have and (dull and "1,1,0" or "0,1,0")) or "1,0,0"
          local name = _disp(si)
          local haveStr = (have and "1" or "0") .. "/" .. tostring(need)
          local suffix  = dull and (" (" .. dullTooltip .. ")") or ""

          lines[#lines + 1] = string.format(
            " <INDENT:20> <RGB:%s>%s %s%s <LINE> <INDENT:0> ",
            rgb, name, haveStr, suffix)
        end
      end
    end
  end

  if #lines > 0 then
    local headerRGB = anyEligible and "0,1,0" or (anyHave and "1,1,0" or "1,0,0")
    desc = desc .. string.format(" <RGB:%s>%s <LINE> ", headerRGB, getText("IGUI_CraftUI_OneOf"))
    for i = 1, #lines do
      local L = lines[i]
      desc = desc .. L
    end
  end
  return desc
end

-- Pick an inventory item that satisfies a spec { item=..., tag=..., tags={...} }
-- Respects flags (e.g., IsNotDull).
function VRO_PickFromSpec(inv, spec, needUses)
  if not (inv and spec) then return nil end
  local flags = normalizeFlags(spec.flags)
  local need  = needUses or 1
  local enforceNotDull = hasFlag(flags, "IsNotDull")

  local chosen = nil
  if spec.tags then
    chosen = enforceNotDull and findBestByTagsNotDull(inv, spec.tags, need) or findBestByTags(inv, spec.tags, need)

  elseif spec.tag then
    chosen = findBestByTag(inv, spec.tag, need)
    if enforceNotDull and chosen and isItemDull(chosen) then chosen = nil end

  elseif spec.item then
    chosen = findFirstTypeRecurse(inv, spec.item)
    if enforceNotDull and chosen and isItemDull(chosen) then chosen = nil end
  end
  return chosen
end

----------------------------------------------------------------
-- C) Path & facing
----------------------------------------------------------------
-- Resolve the area we should path to for a given part, with override support.
local function _prettyPartId(id)
  if not id or type(id) ~= "string" then return nil end
  -- Convert camel-case IDs like "GloveBox" -> "Glove Box"
  return id:gsub("(%l)(%u)", "%1 %2")
end

local function _resolveRepairAreaForPart(part)
  -- Default to whatever the part says, else Engine
  local area = (part and part.getArea and part:getArea()) or "Engine"
  local veh  = part and part.getVehicle and part:getVehicle() or nil
  if not veh then return tostring(area) end

  local script   = veh.getScript and veh:getScript() or nil
  local vFull    = script and script.getFullName and script:getFullName() or nil  -- e.g. "Base.97bushAmbulance"
  local vName    = script and script.getName and script:getName() or nil          -- e.g. "97bushAmbulance"

  local partId   = part.getId and part:getId() or nil                              -- e.g. "GloveBox"
  local partPretty = _prettyPartId(partId)                                         -- e.g. "Glove Box"

  local ov = VRO.AccessOverrides or {}
  -- find the right vehicle bucket or the wildcard
  local bucket = ov[vFull] or ov[vName] or ov["*"]
  if not bucket then return tostring(area) end

  -- look for exact part id, then pretty name, then wildcard
  local forced = (partId and bucket[partId]) or (partPretty and bucket[partPretty]) or bucket["*"]
  if forced and type(forced) == "string" and forced ~= "" then
    area = forced
  end
  return tostring(area)
end

local function queuePathToPartArea(playerObj, part)
  local vehicle = part and part:getVehicle()
  if not playerObj or not vehicle then return end
  local targetArea = _resolveRepairAreaForPart(part)
  ISTimedActionQueue.add(ISPathFindAction:pathToVehicleArea(playerObj, vehicle, targetArea))
end

----------------------------------------------------------------
-- D) Tooltip (dynamic color + icon)
----------------------------------------------------------------
local function interpColorTag(frac)
  local c = ColorInfo.new(0,0,0,1)
  getCore():getBadHighlitedColor():interp(getCore():getGoodHighlitedColor(), math.max(0, math.min(1, frac or 0)), c)
  return string.format("<RGB:%s,%s,%s>", c:getR(), c:getG(), c:getB())
end

-- Merge helpers: fixer overrides recipe
local function pick(a,b) if a ~= nil then return a else return b end end
local function mergeEquip(fixEq, recEq)
  local out = {}
  fixEq = fixEq or {}; recEq = recEq or {}
  out.primary      = pick(fixEq.primary,      recEq.primary)
  out.secondary    = pick(fixEq.secondary,    recEq.secondary)
  out.primaryTag   = pick(fixEq.primaryTag,   recEq.primaryTag)
  out.secondaryTag = pick(fixEq.secondaryTag, recEq.secondaryTag)
  out.wearTag      = pick(fixEq.wearTag,      recEq.wearTag)
  out.wear         = pick(fixEq.wear,         recEq.wear)
  out.showModel    = pick(fixEq.showModel,    recEq.showModel)
  return out
end
local function resolveAnim(fixer, fixing) return pick(fixer.anim, fixing.anim) end
local function resolveSound(fixer, fixing) return pick(fixer.sound, fixing.sound) end
local function resolveSuccessSound(fixer, fixing) return pick(fixer.successSound, fixing.successSound) end
local function resolveShowModel(fixer, fixing)
  local f = (fixer.equip and fixer.equip.showModel)
  if f == nil and fixing.equip then f = fixing.equip.showModel end
  if f ~= nil then return f end

  -- If neither primary/secondary (nor tags) nor wear are requested, hide hand models.
  local eq = mergeEquip(fixer.equip, fixing.equip)
  local noHands = not (eq.primary or eq.primaryTag or eq.secondary or eq.secondaryTag)
  local noWear  = not (eq.wear or eq.wearTag)
  return not (noHands and noWear)  -- => false when nothing is specified
end
local function resolveTime(fixer, fixing, player, broken)
  local t = (fixer.time ~= nil) and fixer.time or fixing.time
  if type(t) == "function" then return t(player, broken) end
  if type(t) == "number" then return t end
  return 160
end

local function resolveInvAnim(fixer, fixing)
  -- Per-fixer beats per-recipe; if neither is set, fall back to the base anim.
  return (fixer and fixer.invAnim)
      or (fixing and fixing.invAnim)
      or resolveAnim(fixer, fixing)
end

local function addFixerTooltip(tip, player, part, fixing, fixer, fixerIndex, brokenItem)
  tip:initialise(); tip:setVisible(false)
  setTooltipIconFromFullType(tip, fixer.item)
  tip:setName(displayNameFromFullType(fixer.item))

  local hbr     = getHBR(part, brokenItem)
  local pot     = math.ceil(condRepairedPercent(brokenItem, player, fixing, fixer, hbr, fixerIndex))
  local success = 100 - math.ceil(chanceOfFail(brokenItem, player, fixing, fixer, hbr))

  local c1 = interpColorTag((pot or 0)/100)
  local c2 = interpColorTag((success or 0)/100)

  -- Buckets we stitch together at the end
  local reqLines, oneOfBlocks, skillLines = {}, {}, {}
  local function lineStr(rgb, name, have, need, isDull)
    local suffix = isDull and (" (" .. dullTooltip .. ")") or ""
    return string.format(" <RGB:%s>%s %d/%d%s <LINE> ", rgb, name, have, need, suffix)
  end
  local function pushReq(rgb, name, have, need, isDull)
    reqLines[#reqLines+1] = lineStr(rgb, name, have, need, isDull)
  end
  local function pushSkill(rgb, name, have, need)
    skillLines[#skillLines+1] = lineStr(rgb, name, have, need, false)
  end
  local function pushOneOfBlock(textBlock)
    if textBlock and textBlock ~= "" then oneOfBlocks[#oneOfBlocks+1] = textBlock end
  end

  -- De-dup against items we already listed (e.g., blowtorch shown only once)
  local seenFull = {}
  local function markSeenItemFT(ft) if ft then seenFull[ft] = true end end
  local function wasSeenFT(ft) return ft and seenFull[ft] == true end

  local inv = player:getInventory()

  -- count total "uses" for a fullType (cap at need)
  local function invHaveForFullType(fullType, capTo)
    local bagged = ArrayList.new()
    inv:getAllTypeRecurse(fullType, bagged)
    if bagged:isEmpty() then return 0 end
    local have, cap = 0, capTo or math.huge
    for i = 1, bagged:size() do
      local it = bagged:get(i-1)
      local u  = drainableUses(it)
      if u > 0 then
        if isDrainable(it) then have = have + u else have = have + 1 end
        if have >= cap then break end
      end
    end
    return have
  end

  -- Prefer the currently worn item if it matches a tag
  local function getWornMatchingTag(chr, tag)
    local worn = chr and chr:getWornItems()
    if not worn then return nil end
    for i = 0, worn:size()-1 do
      local wi = worn:get(i)
      local it = wi and wi:getItem() or nil
      if it and it.hasTag and it:hasTag(tag) then return it end
    end
    return nil
  end

  -- Prefer current hand item if it satisfies a tag/fullType (primary or secondary)
  local function preferHandForTag(chr, tag, which) -- which = "primary"|"secondary"
    local cur = (which == "primary") and chr:getPrimaryHandItem() or chr:getSecondaryHandItem()
    if cur and cur.hasTag and cur:hasTag(tag) then return cur end
    return nil
  end
  local function preferHandForItem(chr, fullType, which)
    local cur = (which == "primary") and chr:getPrimaryHandItem() or chr:getSecondaryHandItem()
    if cur and cur.getFullType and cur:getFullType() == fullType then return cur end
    return nil
  end

  -- Header
  local desc = ""
  desc = desc .. " " .. c1 .. " " .. getText("Tooltip_potentialRepair") .. " " .. (pot or 0) .. "%"
  desc = desc .. " <LINE> " .. c2 .. " " .. getText("Tooltip_chanceSuccess") .. " " .. (success or 0) .. "%"
  desc = desc .. " <LINE> <LINE> <RGB:1,1,1> " .. getText("Tooltip_craft_Needs") .. ": <LINE> <LINE>"

  -- 1) Fixer item (consumed)
  do
    local need = fixer.uses or 1
    local have = invHaveForFullType(fixer.item, need)
    local nm   = displayNameFromFullType(fixer.item)
    local rgb  = (have >= need) and "0,1,0" or "1,0,0"
    pushReq(rgb, nm, have, need, false)

    local eq = mergeEquip(fixer.equip, fixing and fixing.equip or nil)
    local sameAsEquip = false
    if eq then
      if eq.primary   and eq.primary   == fixer.item then sameAsEquip = true end
      if eq.secondary and eq.secondary == fixer.item then sameAsEquip = true end
    end
    if sameAsEquip or (have >= need) then
      markSeenItemFT(fixer.item)
    end
  end

  -- 2) Global items (respect non-consumed tags + flags via _pickNonConsumedChoice)
  do
    -- Support recipe- or fixer-level single/multi globals; defer to helper used by menus
    local function _normalizeGlobals(fixr, fixg)
      local giList = (fixr and fixr.globalItems) or (fixg and fixg.globalItems)
      if giList and type(giList) == "table" then
        if giList[1] then return giList else return { giList } end
      end
      local single = (fixr and fixr.globalItem) or (fixg and fixg.globalItem)
      if single then return { single } end
      return nil
    end

    local effList = _normalizeGlobals(fixer, fixing)
    if effList and type(effList) == "table" then
      for i = 1, #effList do
        local gi   = effList[i]
        local tags = normalizeTagsField(gi)
        local need = gi.uses or 1

        -- De-dupe: pre-mark torch & explicit items so equip lines won't echo them
        if gi.item then markSeenItemFT(gi.item) end
        if gi.tag == "BlowTorch" then markSeenItemFT("Base.BlowTorch") end
        if tags and tags[1] ~= nil then
          for j = 1, #tags do
            if tags[j] == "BlowTorch" then
              markSeenItemFT("Base.BlowTorch")
              break
            end
          end
        end

        if gi.consume == false then
          -- Choose exactly what the action would choose (handles IsNotDull / SharpnessCheck)
          local chosen = _pickNonConsumedChoice(inv, gi)
          if chosen then
            local nm = (chosen.getDisplayName and chosen:getDisplayName())
                       or (tags and displayNameForTags(inv, tags))
                       or (gi.tag and displayNameForTag(inv, gi.tag))
                       or (gi.item and displayNameFromFullType(gi.item))
                       or getText("IGUI_CraftUI_OneOf")
            pushReq("0,1,0", nm, 1, 1, isItemDull(chosen) or false)
            markSeenItemFT(chosen.getFullType and chosen:getFullType() or nil)
          else
            -- Missing: only show the One-of block (let it decide header color; pass nil)
            if tags then
              pushOneOfBlock(_appendOneOfTagsList("", inv, tags, need, false))
            elseif gi.tag then
              pushOneOfBlock(_appendOneOfTagsList("", inv, { gi.tag }, need, false))
            elseif gi.item then
              pushReq("1,0,0", displayNameFromFullType(gi.item), 0, 1, false)
            end
          end
        else
          -- Consumed requirement
          if tags then
            local it = findBestByTags(inv, tags, need)
            if it then
              local have = (isDrainable(it) and math.min(drainableUses(it), need)) or 1
              local nm   = (it.getDisplayName and it:getDisplayName()) or displayNameForTags(inv, tags)
              pushReq((have >= need) and "0,1,0" or "1,0,0", nm, have, need, isItemDull(it))
              if have >= need and it.getFullType then markSeenItemFT(it:getFullType()) end
            else
              pushOneOfBlock(_appendOneOfTagsList("", inv, tags, need, false))
            end
            elseif gi.tag then
            local it = findBestByTag(inv, gi.tag, need)
            if it then
              local have = (isDrainable(it) and math.min(drainableUses(it), need)) or 1
              local nm   = (it.getDisplayName and it:getDisplayName()) or displayNameForTag(inv, gi.tag)
              pushReq((have >= need) and "0,1,0" or "1,0,0", nm, have, need, isItemDull(it))
              if have >= need and it.getFullType then markSeenItemFT(it:getFullType()) end
            else
              pushOneOfBlock(_appendOneOfTagsList("", inv, { gi.tag }, need, false))
            end
            elseif gi.item then
              local nm   = displayNameFromFullType(gi.item)

              -- SPECIAL CASE: blowtorch should show the *best single* torch, not total
              if gi.item == "Base.BlowTorch" then
                -- find the blowtorch with the most usable fuel
                local bagged = ArrayList.new()
                inv:getAllTypeRecurse("Base.BlowTorch", bagged)
                local bestUses = 0
                for bi = 0, bagged:size() - 1 do
                  local it = bagged:get(bi)
                  local u  = drainableUses(it)
                  if u > bestUses then
                    bestUses = u
                  end
                end

                local have = math.min(bestUses, need)
                local rgb  = (bestUses >= need) and "0,1,0" or "1,0,0"
                pushReq(rgb, nm, have, need, false)
                -- don’t mark seen by fullType here; it’s fine either way
              else
                -- normal (non-blowtorch) item: keep existing behavior
                local have = invHaveForFullType(gi.item, need)
                local rgb  = (have >= need) and "0,1,0" or "1,0,0"
                pushReq(rgb, nm, have, need, false)
                if have >= need then markSeenItemFT(gi.item) end
              end
            end
          end
        end
      end
    end

  -- 3) Wear requirement — prefer already-worn items that satisfy the spec
  do
    local eq = mergeEquip(fixer.equip, fixing.equip)
    if eq.wearTag then
      local worn = getWornMatchingTag(player, eq.wearTag)
      if worn then
        local nm = worn:getDisplayName() or fallbackNameForTag(eq.wearTag)
        pushReq("0,1,0", nm, 1, 1, false)
        markSeenItemFT(worn.getFullType and worn:getFullType() or nil)
      else
        -- not worn: show present from inventory if any, else OneOf block only
        local it = findBestByTag(inv, eq.wearTag, 1)
        if it then
          pushReq("0,1,0", it:getDisplayName() or fallbackNameForTag(eq.wearTag), 1, 1, isItemDull(it))
          markSeenItemFT(it.getFullType and it:getFullType() or nil)
        else
          pushOneOfBlock(_appendOneOfTagsList("", inv, { eq.wearTag }, 1, false))
        end
      end
    elseif eq.wear then
      -- specific wearable by fullType
      local worn = getWornMatchingTag(player, displayNameFromFullType(eq.wear)) -- unlikely; keep inventory check
      local it   = worn or findFirstTypeRecurse(inv, eq.wear)
      local nm   = (it and it.getDisplayName and it:getDisplayName()) or displayNameFromFullType(eq.wear)
      pushReq(it and "0,1,0" or "1,0,0", nm, it and 1 or 0, 1, it and isItemDull(it))
      if it and it.getFullType then markSeenItemFT(it:getFullType()) end
    end
  end

  -- 4) Primary / Secondary — prefer current hands when they satisfy the spec
  do
    local eq = mergeEquip(fixer.equip, fixing.equip)

    local function showPrimaryByItem(fullType)
      if not fullType then return end
      if wasSeenFT(fullType) then return end
      local cur = preferHandForItem(player, fullType, "primary")
      local it  = cur or findFirstTypeRecurse(inv, fullType)
      local nm  = (it and it.getDisplayName and it:getDisplayName()) or displayNameFromFullType(fullType)
      pushReq(it and "0,1,0" or "1,0,0", nm, it and 1 or 0, 1, it and isItemDull(it))
      if it and it.getFullType then markSeenItemFT(it:getFullType()) end
    end

    local function showPrimaryByTag(tag)
      if not tag then return end
      local cur = preferHandForTag(player, tag, "primary")
      local it  = cur or findBestByTag(inv, tag, 1)
      if it and wasSeenFT(it:getFullType()) then return end
      if it then
        pushReq("0,1,0", it:getDisplayName() or fallbackNameForTag(tag), 1, 1, isItemDull(it))
        markSeenItemFT(it:getFullType())
      else
        pushOneOfBlock(_appendOneOfTagsList("", inv, { tag }, 1, false))
      end
    end

    local function showSecondaryByItem(fullType)
      if not fullType then return end
      if wasSeenFT(fullType) then return end
      local cur = preferHandForItem(player, fullType, "secondary")
      local it  = cur or findFirstTypeRecurse(inv, fullType)
      local nm  = (it and it.getDisplayName and it:getDisplayName()) or displayNameFromFullType(fullType)
      pushReq(it and "0,1,0" or "1,0,0", nm, it and 1 or 0, 1, it and isItemDull(it))
      if it and it.getFullType then markSeenItemFT(it:getFullType()) end
    end

    local function showSecondaryByTag(tag)
      if not tag then return end
      local cur = preferHandForTag(player, tag, "secondary")
      local it  = cur or findBestByTag(inv, tag, 1)
      if it and wasSeenFT(it:getFullType()) then return end
      if it then
        pushReq("0,1,0", it:getDisplayName() or fallbackNameForTag(tag), 1, 1, isItemDull(it))
        markSeenItemFT(it:getFullType())
      else
        pushOneOfBlock(_appendOneOfTagsList("", inv, { tag }, 1, false))
      end
    end

    if eq.primary then showPrimaryByItem(eq.primary)
    elseif eq.primaryTag then showPrimaryByTag(eq.primaryTag) end

    if eq.secondary and eq.secondary ~= eq.primary then
      showSecondaryByItem(eq.secondary)
    elseif eq.secondaryTag and eq.secondaryTag ~= eq.primaryTag then
      showSecondaryByTag(eq.secondaryTag)
    end
  end

  -- 5) Skills (always last)
  if fixer.skills then
    for name, req in pairs(fixer.skills) do
      local lvl = perkLevel(player, name)
      local ok  = lvl >= req
      local perkLabel = (getText and getText("IGUI_perks_" .. name)) or name
      if perkLabel == ("IGUI_perks_" .. name) then perkLabel = name end
      pushSkill(ok and "0,1,0" or "1,0,0", perkLabel, lvl, req)
    end
  end

  -- Stitch all sections together
  desc = desc .. table.concat(reqLines)

  if oneOfBlocks and oneOfBlocks[1] ~= nil then
    for i = 1, #oneOfBlocks do
      desc = desc .. " " .. oneOfBlocks[i]
    end
  end

  desc = desc .. table.concat(skillLines)
  tip.description = desc
end

----------------------------------------------------------------
-- E) Context Menu Injection (attach to vanilla "Repair")
----------------------------------------------------------------
local function toPlayerInventory(playerObj, it)
  if not it then return end
  if it:getContainer() ~= playerObj:getInventory() then
    if ISVehiclePartMenu and ISVehiclePartMenu.toPlayerInventory then
      ISVehiclePartMenu.toPlayerInventory(playerObj, it)
    else
      playerObj:getInventory():AddItem(it)
    end
  end
end

-- does an already-held / already-worn item satisfy a spec { item=..., tag=..., tags=... } ?
local function _equippedSatisfies(it, spec, needUses)
  if not (it and spec) then return false end
  -- if this is a drainable (torch), make sure it has enough
  if needUses and needUses > 0 then
    local u = drainableUses(it)
    if u < needUses then
      return false
    end
  end

  -- tags array
  if spec.tags and spec.tags[1] then
    for i = 1, #spec.tags do
      local t = spec.tags[i]
      if it.hasTag and it:hasTag(t) then
        return true
      end
    end
    return false
  end

  -- single tag
  if spec.tag then
    return it.hasTag and it:hasTag(spec.tag)
  end

  -- explicit item fullType
  if spec.item then
    local ft = it.getFullType and it:getFullType()
    return ft == spec.item
  end

  -- nothing to check against
  return false
end

-- returns (chosenPrimary, chosenSecondary, equipKeep[, err])
local function queueEquipActions(playerObj, eq, torchHint)
  if not eq then return nil, nil, nil end

  local inv        = playerObj:getInventory()
  local equipKeep  = {}

  -- make sure an item is actually in the player inventory (not in a bag)
  local function _ensureInPlayerInv(it)
    if not it then return end
    if it:getContainer() ~= inv then
      toPlayerInventory(playerObj, it)
    end
  end

  -- how many blowtorch uses this repair really needs
    local needTorchUses = 0
    local torchIsTorch  = false
    if torchHint then
      -- item form
      if torchHint.item == "Base.BlowTorch" then
        torchIsTorch = true
      end
      -- single tag form
      if torchHint.tag == "BlowTorch" then
        torchIsTorch = true
      end
      -- multi-tag form
      local ttags = normalizeTagsField(torchHint)
      if ttags then
        for i = 1, #ttags do
          if ttags[i] == "BlowTorch" then
            torchIsTorch = true
            break
          end
        end
      end
      if torchIsTorch then
        needTorchUses = tonumber(torchHint.uses) or 0
      end
    end

  ----------------------------------------------------------------
  -- 1) If the recipe needs torch uses, make sure we have ONE torch
  --    with at least that many uses. If we don't, tell the caller
  --    to stop.
  ----------------------------------------------------------------
  local forcedTorch = nil
  if torchIsTorch and needTorchUses > 0 then
    -- check hands first
    local curP = playerObj:getPrimaryHandItem()
    local curS = playerObj:getSecondaryHandItem()
    if curP and isTorchItem(curP) and drainableUses(curP) >= needTorchUses then
      forcedTorch = curP
    elseif curS and isTorchItem(curS) and drainableUses(curS) >= needTorchUses then
      forcedTorch = curS
    else
      -- search inventory for ANY torch that has enough uses
      if inv.getFirstEvalRecurse then
        forcedTorch = inv:getFirstEvalRecurse(function(item)
          return item and isTorchItem(item) and drainableUses(item) >= needTorchUses
        end)
      end
      if not forcedTorch then
        -- small fallback for Base.BlowTorch
        local maybe = findFirstTypeRecurse(inv, "Base.BlowTorch")
        if maybe and drainableUses(maybe) >= needTorchUses then
          forcedTorch = maybe
        end
      end
    end

    -- still nothing? then we can't do this repair
    if not forcedTorch then
      return nil, nil, nil, "need_torch_uses"
    end

    -- make sure it’s in main inventory so we can equip it
    _ensureInPlayerInv(forcedTorch)
  end

  ----------------------------------------------------------------
  -- build specs from merged equip
  ----------------------------------------------------------------
  local pSpec = nil
  if eq.primary or eq.primaryTag then
    pSpec = { item = eq.primary, tag = eq.primaryTag, flags = eq.flags }
  end
  local sSpec = nil
  if eq.secondary or eq.secondaryTag then
    sSpec = { item = eq.secondary, tag = eq.secondaryTag, flags = eq.flags }
  end
  local wSpec = nil
  if eq.wear or eq.wearTag then
    wSpec = { item = eq.wear, tag = eq.wearTag, flags = eq.flags }
  end

  ----------------------------------------------------------------
  -- 2) PRIMARY
  ----------------------------------------------------------------
  local chosenPrimary = nil
  if pSpec then
    local curP = playerObj:getPrimaryHandItem()
    local preferTorchP = isTorchItem(forcedTorch) and pSpec.tag == nil and pSpec.item == nil

    -- if the equip spec itself is "a torch" and we already picked a torch, just use it
    if forcedTorch and (pSpec.tag == "BlowTorch" or pSpec.item == "Base.BlowTorch" or preferTorchP) then
      chosenPrimary = forcedTorch
    elseif curP and _equippedSatisfies(curP, pSpec, (needTorchUses > 0) and needTorchUses or nil) then
      chosenPrimary = curP
    else
      chosenPrimary = VRO_PickFromSpec(inv, pSpec, (needTorchUses > 0) and needTorchUses or 1)
    end

    if chosenPrimary and chosenPrimary ~= curP then
      _ensureInPlayerInv(chosenPrimary)
      ISTimedActionQueue.add(ISEquipWeaponAction:new(playerObj, chosenPrimary, 50, true, false))
    end

    if chosenPrimary then
      equipKeep[#equipKeep+1] = { item = chosenPrimary, flags = normalizeFlags(pSpec.flags) }
    end
  elseif forcedTorch then
    -- recipe didn't ask to hold anything, but we DO need a torch in hand
    if playerObj:getPrimaryHandItem() ~= forcedTorch then
      ISTimedActionQueue.add(ISEquipWeaponAction:new(playerObj, forcedTorch, 50, true, false))
    end
    equipKeep[#equipKeep+1] = { item = forcedTorch, flags = nil }
    chosenPrimary = forcedTorch
  end

  ----------------------------------------------------------------
  -- 3) SECONDARY (don’t reuse same object as primary)
  ----------------------------------------------------------------
  local chosenSecondary = nil
  if sSpec then
    local curS = playerObj:getSecondaryHandItem()
    local function _sameAsPrimary(it) return chosenPrimary and it and it == chosenPrimary end

    if curS and _equippedSatisfies(curS, sSpec, nil) and not _sameAsPrimary(curS) then
      chosenSecondary = curS
    else
      chosenSecondary = VRO_PickFromSpec(inv, sSpec, 1)
      if _sameAsPrimary(chosenSecondary) then
        chosenSecondary = nil
      end
    end

    if chosenSecondary and chosenSecondary ~= curS then
      _ensureInPlayerInv(chosenSecondary)
      ISTimedActionQueue.add(ISEquipWeaponAction:new(playerObj, chosenSecondary, 50, false, false))
    end

    if chosenSecondary then
      equipKeep[#equipKeep+1] = { item = chosenSecondary, flags = normalizeFlags(sSpec.flags) }
    end
  end

  ----------------------------------------------------------------
  -- 4) WEAR  (this is the one that was biting you)
  ----------------------------------------------------------------
  if wSpec then
    -- prefer something already worn that matches
    local worn = (function(chr, spec)
      local wornList = chr:getWornItems()
      if not wornList then return nil end
      for i = 0, wornList:size() - 1 do
        local wi = wornList:get(i)
        local wItem = wi and wi:getItem() or nil
        if wItem and _equippedSatisfies(wItem, spec, nil) then
          return wItem
        end
      end
      return nil
    end)(playerObj, wSpec)

    if worn then
      -- it's already worn, just keep it
      equipKeep[#equipKeep+1] = { item = worn, flags = normalizeFlags(wSpec.flags) }
    else
      -- pull it from ANY container, move to player inv, then wear it
      local wItem = VRO_PickFromSpec(inv, wSpec, 1)
      if wItem and ISInventoryPaneContextMenu and ISInventoryPaneContextMenu.wearItem then
        _ensureInPlayerInv(wItem)                 -- <== this is the important part
        ISInventoryPaneContextMenu.wearItem(wItem, playerObj:getPlayerNum())
        equipKeep[#equipKeep+1] = { item = wItem, flags = normalizeFlags(wSpec.flags) }
      end
    end
  end

  if #equipKeep == 0 then equipKeep = nil end
  return chosenPrimary, chosenSecondary, equipKeep
end

local function findRepairParentOption(context, matcherFn)
  local opts = context and context.options or nil
  if not opts then return nil end
  for i=1,#opts do
    local opt = opts[i]
    if opt and opt.name and matcherFn(opt.name) then
      return opt
    end
  end
  return nil
end

local function ensureSubMenu(context, parent)
  if not (context and parent) then return nil end
  local sub = parent.subOption
  if sub and type(sub.addOption) == "function" then
    return sub
  end
  local newSub = ISContextMenu:getNew(context)
  context:addSubMenu(parent, newSub)
  return newSub
end

local function isSubmenuEmpty(parent)
  if not (parent and parent.subOption) then return true end
  local sub  = parent.subOption
  local opts = sub and sub.options or nil

  -- Java ArrayList-style
  if opts and opts.size then
    return opts:size() == 0
  end
  return true
end

----------------------------------------------------------------
-- F) Mechanics window (vanilla-style submenu; attach to existing)
----------------------------------------------------------------
local old_doPart = ISVehicleMechanics.doPartContextMenu
function ISVehicleMechanics:doPartContextMenu(part, x, y)
  old_doPart(self, part, x, y)

  if VRO_UseVanillaFixingRecipes() then return end
  local playerObj = getSpecificPlayer(self.playerNum)
  if not playerObj or not part then return end

  -- ALLOW nil itemType (e.g., TruckBed, GloveBox, etc.)
  -- if not part:getItemType() or part:getItemType():isEmpty() then return end

  local broken = part:getInventoryItem()  -- may be nil for parts with no inventory item
  if part:getCondition() >= 100 then return end

  -- Keys we can match against recipe 'require':
  local ft = broken and broken.getFullType and broken:getFullType() or nil
  local partId = part.getId and part:getId() or nil

  -- Helper: does a given recipe target this item fullType OR this part ID?
  local function recipeMatchesTarget(fixing)
    local set = resolveRequireSet(fixing)
    if ft and set[ft] then return true end
    if partId and set[partId] then return true end
    return false
  end

  -- Do we have any recipes at all that target this item or part?
  local any = false
  for __ri = 1, #VRO.Recipes do
    local fx = VRO.Recipes[__ri]
    if recipeMatchesTarget(fx) then any = true; break end
  end
  if not any then return end

  self.context = self.context or ISContextMenu.get(self.playerNum, x + self:getAbsoluteX(), y + self:getAbsoluteY())
  local repairTxt = getText("ContextMenu_Repair")
  local parent = findRepairParentOption(self.context, function(n) return n == repairTxt end)
  if not parent then parent = self.context:addOption(repairTxt, nil, nil) end
  local sub = ensureSubMenu(self.context, parent); if not sub then return end

  -- normalize single-or-list globals to an array
  local function _normalizeGlobals(fixr, fixg)
    local giList = (fixr and fixr.globalItems) or (fixg and fixg.globalItems)
    if giList and type(giList) == "table" then
      if giList[1] then return giList else return { giList } end
    end
    local single = (fixr and fixr.globalItem) or (fixg and fixg.globalItem)
    if single then return { single } end
    return nil
  end

  local function _gatherMultiGlobals(inv, list)
    if not list then return true, nil, nil end
    if type(list) == "table" and not list[1] and (list.item or list.tag or list.tags) then
      list = { list }
    end
    if type(list) ~= "table" or #list == 0 then return true, nil, nil end

    local allOK, consumeFlat, keepFlat = true, {}, {}

    for i = 1, #list do
      local gi = list[i]; if type(gi) ~= "table" then allOK = false; break end

      if gi.consume == false then
        -- use _pickNonConsumedChoice to select the actual tool and carry flags
        local chosen, flags = _pickNonConsumedChoice(inv, gi)
        if chosen then
          keepFlat[#keepFlat+1] = { item = chosen, flags = flags }
        else
          allOK = false; break
        end
      else
        local need = gi.uses or 1
        local tags = normalizeTagsField(gi)
        if tags then
          local it = findBestByTags(inv, tags, need)
          if it and (not isDrainable(it) or drainableUses(it) >= need) then
            consumeFlat[#consumeFlat+1] = { item = it, takeUses = isDrainable(it) and need or 1 }
          else allOK = false; break end
        elseif gi.tag then
          local it = findBestByTag(inv, gi.tag, need)
          if it and (not isDrainable(it) or drainableUses(it) >= need) then
            consumeFlat[#consumeFlat+1] = { item = it, takeUses = isDrainable(it) and need or 1 }
          else allOK = false; break end
        elseif gi.item then
          local b = gatherRequiredItems(inv, gi.item, need)
          if b then
            for i2 = 1, #b do
              consumeFlat[#consumeFlat + 1] = b[i2]
            end
          else
            allOK = false; break
          end
        else
          allOK = false; break
        end
      end
    end

    if #consumeFlat == 0 then consumeFlat = nil end
    if #keepFlat    == 0 then keepFlat    = nil end
    return allOK, consumeFlat, keepFlat
  end

  local function _equipRequirementsOK(inv, eq)
    if not eq then return true end
    local ok = true

    -- WEAR (already fixed to be recursive)
    if eq.wearTag then
      local hasWear = (inv.getFirstTagRecurse and inv:getFirstTagRecurse(eq.wearTag)) or hasTag(inv, eq.wearTag)
      ok = ok and (hasWear ~= nil)
    elseif eq.wear then
      ok = ok and (findFirstTypeRecurse(inv, eq.wear) ~= nil)
    end

    -- PRIMARY (make tag check recursive too)
    if eq.primaryTag then
      local hasPrim = (inv.getFirstTagRecurse and inv:getFirstTagRecurse(eq.primaryTag)) or hasTag(inv, eq.primaryTag)
      ok = ok and (hasPrim ~= nil)
    elseif eq.primary then
      ok = ok and (findFirstTypeRecurse(inv, eq.primary) ~= nil)
    end

    -- SECONDARY (make tag check recursive too, and don’t recheck same tag)
    if eq.secondaryTag and eq.secondaryTag ~= eq.primaryTag then
      local hasSec = (inv.getFirstTagRecurse and inv:getFirstTagRecurse(eq.secondaryTag)) or hasTag(inv, eq.secondaryTag)
      ok = ok and (hasSec ~= nil)
    elseif eq.secondary and eq.secondary ~= eq.primary then
      ok = ok and (findFirstTypeRecurse(inv, eq.secondary) ~= nil)
    end
    return ok
  end

  local function _pickTorchGlobal(list, fallbackSingle)
    if list and list[1] ~= nil then
      for i = 1, #list do
        local gi = list[i]
        if gi then
          -- direct tag
          if gi.tag == "BlowTorch" then return gi end

          -- tags array
          local gTags = normalizeTagsField(gi)
          if gTags and gTags[1] ~= nil then
            for j = 1, #gTags do
              if gTags[j] == "BlowTorch" then return gi end
            end
          end

          -- item full type / name contains "BlowTorch"
          local it = gi.item
          if it and (it == "Base.BlowTorch" or (type(it) == "string" and string.find(it, "BlowTorch", 1, true))) then
            return gi
          end
        end
      end
    end
    return fallbackSingle
  end

  local rendered = false
  for __ri = 1, #VRO.Recipes do
    local fixing = VRO.Recipes[__ri]
    if recipeMatchesTarget(fixing) then
      local fixers = fixing.fixers or {}
      for idx = 1, #fixers do
        local fixer = fixers[idx]
        local inv = playerObj:getInventory()
        local fxBundle = gatherRequiredItems(inv, fixer.item, fixer.uses or 1)
        local multiList = _normalizeGlobals(fixer, fixing)
        local glOK, glBundle, glKeep = true, nil, nil

        if multiList then
          glOK, glBundle, glKeep = _gatherMultiGlobals(inv, multiList)
        else
          local gi = (fixer and fixer.globalItem) or (fixing and fixing.globalItem)
          if gi then
            if gi.consume == false then
              local chosen, flags = _pickNonConsumedChoice(inv, gi)
              glOK   = chosen ~= nil
              glKeep = chosen and { { item = chosen, flags = flags } } or nil
            else
              local need = gi.uses or 1
              local tags = normalizeTagsField(gi)
              if tags then
                local it = findBestByTags(inv, tags, need)
                if it and (not isDrainable(it) or drainableUses(it) >= need) then
                  glBundle = { { item = it, takeUses = isDrainable(it) and need or 1 } }
                  glOK = true
                else glOK = false end
              elseif gi.tag then
                local it = findBestByTag(inv, gi.tag, need)
                if it and (not isDrainable(it) or drainableUses(it) >= need) then
                  glBundle = { { item = it, takeUses = isDrainable(it) and need or 1 } }
                  glOK = true
                else glOK = false end
              else
                glBundle = gatherRequiredItems(inv, gi.item, need)
                glOK = (glBundle ~= nil)
              end
            end
          end
        end

        local skillsOK = true
        if fixer.skills then
          for name,req in pairs(fixer.skills) do
            if perkLevel(playerObj, name) < req then skillsOK=false; break end
          end
        end

        local eq = mergeEquip(fixer.equip, fixing.equip)
        local wearOK = true
        if eq.wearTag then
          local hasWear = (inv.getFirstTagRecurse and inv:getFirstTagRecurse(eq.wearTag)) or hasTag(inv, eq.wearTag)
          wearOK = (hasWear ~= nil)
        elseif eq.wear then
          wearOK = (findFirstTypeRecurse(inv, eq.wear) ~= nil)
        end

        if glKeep and glKeep[1] ~= nil then
          for i = 1, #glKeep do
            local k = glKeep[i]
            if k and hasFlag(k.flags, "IsNotDull") and isItemDull(k.item) then
              glOK = false
              break
            end
          end
        end

        local equipOK = _equipRequirementsOK(inv, eq)

        -- figure out if THIS recipe actually wants a blowtorch and if we have one torch
        -- with enough uses right now
        local singleFallback = (fixer and fixer.globalItem) or (fixing and fixing.globalItem)
        local torchGlobal    = _pickTorchGlobal(multiList, singleFallback)

        -- only enforce torch if this global is ACTUALLY a blowtorch
        local torchOK = true
        if torchGlobal then
          local isTorch = false

          -- item form
          if torchGlobal.item == "Base.BlowTorch" then
            isTorch = true
          end

          -- single tag form
          if torchGlobal.tag == "BlowTorch" then
            isTorch = true
          end

          -- multi-tag form
          local gtags = normalizeTagsField(torchGlobal)
          if gtags then
            for i = 1, #gtags do
              if gtags[i] == "BlowTorch" then
                isTorch = true
                break
              end
            end
          end

          if isTorch and torchGlobal.uses and torchGlobal.uses > 0 then
            torchOK = hasTorchWithUses(inv, torchGlobal.uses)
          end
        end

        local haveAll = fxBundle and glOK and skillsOK and wearOK and equipOK and torchOK
        local raw   = displayNameFromFullType(fixer.item)
        local label = tostring(fixer.uses or 1) .. " " .. humanizeForMenuLabel(raw)

        local option
        if haveAll then
          rendered = true
          -- we already have torchGlobal above; pass it through
          option = sub:addOption(label, playerObj, function(p, prt, fixg, fixr, idx_, brk, fxB, glB, glK, torchHint)
            queuePathToPartArea(p, prt)
            local chosenP, chosenS, equipKeep, err =
              queueEquipActions(p, mergeEquip(fixr.equip, fixg.equip), torchHint)
            if err == "need_torch_uses" then
              return
            end

            local tm    = resolveTime(fixr, fixg, p, brk)
            local anim  = resolveAnim(fixr, fixg)
            local sfx   = resolveSound(fixr, fixg)
            local sfxOK = resolveSuccessSound(fixr, fixg)
            local showM = resolveShowModel(fixr, fixg)
            local noHands = not (eq.primary or eq.primaryTag or eq.secondary or eq.secondaryTag)
            if noHands then showM = false end
            ISTimedActionQueue.add(VRO.DoFixAction:new{
              character=p, part=prt, fixing=fixg, fixer=fixr, fixerIndex=idx_,
              brokenItem=brk, fixerBundle=fxB, globalBundle=glB, globalKeep=glK,
              equipKeep=equipKeep,time=tm, anim=anim, sfx=sfx, successSfx=sfxOK,
              showModel=showM, expectedPrimary=chosenP, expectedSecondary=chosenS,
              torchUses=(torchHint and torchHint.uses) or 0,
            })
          end, part, fixing, fixer, idx, broken, fxBundle, glBundle, glKeep, torchGlobal)
        else
          option = sub:addOption(label, nil, nil); option.notAvailable = true
        end

        local tip = ISToolTip:new()
        addFixerTooltip(tip, playerObj, part, fixing, fixer, idx, broken)
        option.toolTip = tip
      end
    end
  end

  if parent and not rendered and isSubmenuEmpty(parent) then
    parent.notAvailable = true
  end
end

----------------------------------------------------------------
-- G) Inventory repairs (vanilla-style submenu; attach to existing)
----------------------------------------------------------------
local function resolveInvItemFromContext(items)
  if not items or #items==0 then return nil end
  local first = items[1]
  if instanceof(first,"InventoryItem") then return first end
  if type(first)=="table" then
    if first.items and #first.items>0 and instanceof(first.items[1],"InventoryItem") then return first.items[1] end
    if first.item and instanceof(first.item,"InventoryItem") then return first.item end
  end
  for i = 1, #items do
    local v = items[i]
    if instanceof(v, "InventoryItem") then
      return v
    end
    if type(v) == "table" then
      local arr = v.items
      if arr and arr[1] ~= nil and instanceof(arr[1], "InventoryItem") then
        return arr[1]
      end
      if v.item and instanceof(v.item, "InventoryItem") then
        return v.item
      end
    end
  end
  return nil
end

local function invRepairLabel(item)
  local nm = (getItemNameFromFullType and getItemNameFromFullType(item:getFullType()))
           or (item.getDisplayName and item:getDisplayName())
           or (item.getType and item:getType()) or "Item"
  return getText("ContextMenu_Repair") .. "" .. nm
end

local function addInventoryFixOptions(playerObj, context, broken)
  if VRO_UseVanillaFixingRecipes() then return end
  if not isRepairableFromInventory(broken) then return end
  local ft = broken:getFullType(); if not ft then return end

  -- Does any VRO recipe apply to this fullType?
  local any = false
  for __ri = 1, #VRO.Recipes do
    local fx = VRO.Recipes[__ri]
    local set = resolveRequireSet(fx)
    if set[ft] then any = true; break end
  end
  if not any then return end

  -- Attach under vanilla's "Repair <item>" entry (or create it)
  local expectedLabel = invRepairLabel(broken)
  local parent = findRepairParentOption(context, function(n) return n == expectedLabel end)
  if not parent then parent = context:addOption(expectedLabel, nil, nil) end
  local sub = ensureSubMenu(context, parent); if not sub then return end

  -- Normalize single-or-list globals to an array
  local function _normalizeGlobals(fixr, fixg)
    local giList = (fixr and fixr.globalItems) or (fixg and fixg.globalItems)
    if giList and type(giList) == "table" then
      if giList[1] then return giList else return { giList } end
    end
    local single = (fixr and fixr.globalItem) or (fixg and fixg.globalItem)
    if single then return { single } end
    return nil
  end

  -- Gather globals into two bundles:
  --   * consumeFlat (for consumed uses)
  --   * keepFlat    (for not-consumed concrete items + flags)
  local function _gatherMultiGlobals(inv, list)
    if not list then return true, nil, nil end
    if type(list) == "table" and not list[1] and (list.item or list.tag or list.tags) then
      list = { list }
    end
    if type(list) ~= "table" or #list == 0 then return true, nil, nil end

    local allOK, consumeFlat, keepFlat = true, {}, {}

    for i = 1, #list do
      local gi = list[i]; if type(gi) ~= "table" then allOK = false; break end

      if gi.consume == false then
        -- Use the shared chooser so de-dulling & flags are consistent everywhere
        local chosen, flags = _pickNonConsumedChoice(inv, gi)
        if chosen then
          keepFlat[#keepFlat+1] = { item = chosen, flags = flags }
        else
          allOK = false; break
        end
      else
        local need = gi.uses or 1
        local tags = normalizeTagsField(gi)
        if tags then
          local it = findBestByTags(inv, tags, need)
          if it and (not isDrainable(it) or drainableUses(it) >= need) then
            consumeFlat[#consumeFlat+1] = { item = it, takeUses = isDrainable(it) and need or 1 }
          else allOK = false; break end
        elseif gi.tag then
          local it = findBestByTag(inv, gi.tag, need)
          if it and (not isDrainable(it) or drainableUses(it) >= need) then
            consumeFlat[#consumeFlat+1] = { item = it, takeUses = isDrainable(it) and need or 1 }
          else allOK = false; break end
        elseif gi.item then
          local b = gatherRequiredItems(inv, gi.item, need)
          if b then
            for i3 = 1, #b do
              consumeFlat[#consumeFlat + 1] = b[i3]
            end
          else
            allOK = false
            break
          end
        else
          allOK = false
          break
        end
      end
    end

    if #consumeFlat == 0 then consumeFlat = nil end
    if #keepFlat    == 0 then keepFlat    = nil end
    return allOK, consumeFlat, keepFlat
  end

  -- Are equip (primary/secondary) requirements satisfied? (fullType or tag)
  local function _equipRequirementsOK(inv, eq)
    if not eq then return true end
    local ok = true
    if eq.wearTag then
      ok = ok and hasTag(inv, eq.wearTag)
    elseif eq.wear then
      ok = ok and (findFirstTypeRecurse(inv, eq.wear) ~= nil)
    end
    if eq.primaryTag then
      ok = ok and hasTag(inv, eq.primaryTag)
    elseif eq.primary then
      ok = ok and (findFirstTypeRecurse(inv, eq.primary) ~= nil)
    end
    if eq.secondaryTag and eq.secondaryTag ~= eq.primaryTag then
      ok = ok and hasTag(inv, eq.secondaryTag)
    elseif eq.secondary and eq.secondary ~= eq.primary then
      ok = ok and (findFirstTypeRecurse(inv, eq.secondary) ~= nil)
    end
    return ok
  end

  -- Pick a torch-like global entry (for equipping/anim hint)
  local function _pickTorchGlobal(list, fallbackSingle)
    if list and list[1] ~= nil then
      for i = 1, #list do
        local gi = list[i]
        if gi then
          -- direct tag
          if gi.tag == "BlowTorch" then return gi end

          -- tags array
          local gTags = normalizeTagsField(gi)
          if gTags and gTags[1] ~= nil then
            for j = 1, #gTags do
              if gTags[j] == "BlowTorch" then return gi end
            end
          end

          -- item full type / name contains "BlowTorch"
          local it = gi.item
          if it and (it == "Base.BlowTorch" or (type(it) == "string" and string.find(it, "BlowTorch", 1, true))) then
            return gi
          end
        end
      end
    end
    return fallbackSingle
  end

  local rendered = false
  for __ri = 1, #VRO.Recipes do
    local fixing = VRO.Recipes[__ri]
    local applies = resolveRequireSet(fixing)[ft] == true
    if applies then
      local fixers = fixing.fixers or {}
      for idx = 1, #fixers do
        local fixer = fixers[idx]
        local inv = playerObj:getInventory()
        local fxBundle = gatherRequiredItems(inv, fixer.item, fixer.uses or 1)
        -- global items (list or single), multi-tag aware
        local multiList = _normalizeGlobals(fixer, fixing)
        local glOK, glBundle, glKeep = true, nil, nil

        if multiList then
          glOK, glBundle, glKeep = _gatherMultiGlobals(inv, multiList)
        else
          -- single global fallback (wrap into same bundles/logic)
          local gi = (fixer and fixer.globalItem) or (fixing and fixing.globalItem)
          if gi then
            if gi.consume == false then
              local chosen, flags = _pickNonConsumedChoice(inv, gi)
              glOK   = chosen ~= nil
              glKeep = chosen and { { item = chosen, flags = flags } } or nil
            else
              local need = gi.uses or 1
              local tags = normalizeTagsField(gi)
              if tags then
                local it = findBestByTags(inv, tags, need)
                if it and (not isDrainable(it) or drainableUses(it) >= need) then
                  glBundle = { { item = it, takeUses = isDrainable(it) and need or 1 } }
                  glOK = true
                else glOK = false end
              elseif gi.tag then
                local it = findBestByTag(inv, gi.tag, need)
                if it and (not isDrainable(it) or drainableUses(it) >= need) then
                  glBundle = { { item = it, takeUses = isDrainable(it) and need or 1 } }
                  glOK = true
                else glOK = false end
              else
                glBundle = gatherRequiredItems(inv, gi.item, need)
                glOK = (glBundle ~= nil)
              end
            end
          end
        end

        local skillsOK = true
        if fixer.skills then
          for name, req in pairs(fixer.skills) do
            if perkLevel(playerObj, name) < req then skillsOK = false; break end
          end
        end

        local eq = mergeEquip(fixer.equip, fixing.equip)
        local wearOK = true
        if eq.wearTag then
          local hasWear = (inv.getFirstTagRecurse and inv:getFirstTagRecurse(eq.wearTag)) or hasTag(inv, eq.wearTag)
          wearOK = (hasWear ~= nil)
        elseif eq.wear then
          wearOK = (findFirstTypeRecurse(inv, eq.wear) ~= nil)
        end

        if glKeep and glKeep[1] ~= nil then
          for i = 1, #glKeep do
            local k = glKeep[i]
            if k and hasFlag(k.flags, "IsNotDull") and isItemDull(k.item) then
              glOK = false
              break
            end
          end
        end

        local equipOK = _equipRequirementsOK(inv, eq)

        -- figure out if THIS recipe actually wants a blowtorch and if we have one torch
        -- with enough uses right now
        local singleFallback = (fixer and fixer.globalItem) or (fixing and fixing.globalItem)
        local torchGlobal    = _pickTorchGlobal(multiList, singleFallback)

        -- only enforce torch if this global is ACTUALLY a blowtorch
        local torchOK = true
        if torchGlobal then
          local isTorch = false

          -- item form
          if torchGlobal.item == "Base.BlowTorch" then
            isTorch = true
          end

          -- single tag form
          if torchGlobal.tag == "BlowTorch" then
            isTorch = true
          end

          -- multi-tag form
          local gtags = normalizeTagsField(torchGlobal)
          if gtags then
            for i = 1, #gtags do
              if gtags[i] == "BlowTorch" then
                isTorch = true
                break
              end
            end
          end

          if isTorch and torchGlobal.uses and torchGlobal.uses > 0 then
            torchOK = hasTorchWithUses(inv, torchGlobal.uses)
          end
        end

        local haveAll = fxBundle and glOK and skillsOK and wearOK and equipOK and torchOK
        local raw   = displayNameFromFullType(fixer.item)
        local label = tostring(fixer.uses or 1) .. " " .. humanizeForMenuLabel(raw)

        local option
        if haveAll then
          rendered = true
          -- we already have torchGlobal above; pass it through
          option = sub:addOption(label, playerObj, function(p, fixg, fixr, idx_, brk, fxB, glB, glK, torchHint)
            local chosenP, chosenS, equipKeep, err =
              queueEquipActions(p, mergeEquip(fixr.equip, fixg.equip), torchHint)
            if err == "need_torch_uses" then
              return
            end

            local tm    = resolveTime(fixr, fixg, p, brk)
            local anim  = resolveInvAnim(fixr, fixg)
            local sfx   = resolveSound(fixr, fixg)
            local sfxOK = resolveSuccessSound(fixr, fixg)
            local showM = resolveShowModel(fixr, fixg)
            local noHands = not (eq.primary or eq.primaryTag or eq.secondary or eq.secondaryTag)
            if noHands then showM = false end
            ISTimedActionQueue.add(VRO.DoFixAction:new{
              character=p, part=nil, fixing=fixg, fixer=fixr, fixerIndex=idx_,
              brokenItem=brk, fixerBundle=fxB, globalBundle=glB, globalKeep=glK,
              equipKeep=equipKeep, time=tm, anim=anim, sfx=sfx, successSfx=sfxOK,
              showModel=showM, expectedPrimary=chosenP, expectedSecondary=chosenS,
              torchUses=(torchHint and torchHint.uses) or 0,
            })
          end, fixing, fixer, idx, broken, fxBundle, glBundle, glKeep, torchGlobal)
        else
          option = sub:addOption(label, nil, nil); option.notAvailable = true
        end

        local tip = ISToolTip:new()
        addFixerTooltip(tip, playerObj, nil, fixing, fixer, idx, broken)
        option.toolTip = tip
      end
    end
  end

  if parent and not rendered and isSubmenuEmpty(parent) then
    parent.notAvailable = true
  end
end

local function OnFillInventoryObjectContextMenu(playerNum, context, items)
  local playerObj = getSpecificPlayer(playerNum); if not playerObj then return end
  local item = resolveInvItemFromContext(items)
  if not isRepairableFromInventory(item) then return end   -- mirror vanilla: only when damaged
  addInventoryFixOptions(playerObj, context, item)
end

-- Guard re-registering on hot-reload
do
  VRO.handlers = VRO.handlers or {}
  local prev = VRO.handlers.invMenu

  if prev and Events.OnFillInventoryObjectContextMenu.Remove then
    Events.OnFillInventoryObjectContextMenu.Remove(prev)
  end

  -- Point the stable slot at the *current* function, then add it
  VRO.handlers.invMenu = OnFillInventoryObjectContextMenu
  Events.OnFillInventoryObjectContextMenu.Add(VRO.handlers.invMenu)
end

----------------------------------------------------------------
-- H) Public API
----------------------------------------------------------------
function VRO.addRecipe(recipe) table.insert(VRO.Recipes, recipe) end
VRO.API = { addRecipe = VRO.addRecipe }
VRO.Module = VRO
return VRO