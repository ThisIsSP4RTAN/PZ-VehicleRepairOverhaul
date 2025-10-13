---@diagnostic disable: undefined-field, param-type-mismatch, redundant-parameter

require "Vehicles/ISUI/ISVehicleMechanics"
require "ISUI/ISToolTip"
require "ISUI/ISInventoryPaneContextMenu"
require "TimedActions/ISBaseTimedAction"
require "TimedActions/ISPathFindAction"
require "TimedActions/ISEquipWeaponAction"
require "VRO_DoFixAction"

local VRO = rawget(_G, "VRO") or {}
VRO.__index = VRO
_G.VRO = VRO
VRO.Recipes = {
--[[  (recipes injected via VRO_Recipes.lua)  ]]
}

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
-- Optional external recipe loader (keeps existing list; append from another file if present)
local function _appendRecipesFrom(source)
  if type(source) == "table" then
    if source.recipes and type(source.recipes) == "table" then
      for _, r in ipairs(source.recipes) do table.insert(VRO.Recipes, r) end
    elseif source[1] then
      for _, r in ipairs(source) do table.insert(VRO.Recipes, r) end
    elseif source.name then
      table.insert(VRO.Recipes, source)
    end
  elseif type(source) == "function" then
    local ok, tbl = pcall(source)
    if ok and type(tbl) == "table" then _appendRecipesFrom(tbl) end
  end
end

local function VRO_LoadExternalRecipes()
  local ok, mod = pcall(require, "VRO_Recipes")
  if ok and mod then _appendRecipesFrom(mod) end
  if _G.VRO_Recipes  then _appendRecipesFrom(_G.VRO_Recipes)  end
  if _G.VRO_RECIPES  then _appendRecipesFrom(_G.VRO_RECIPES)  end
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
  if _G.VRO_PartLists and type(_G.VRO_PartLists)=="table" then
    for k,v in pairs(_G.VRO_PartLists) do VRO.PartLists[k] = v end
  end
  if _G.VRO_PART_LISTS and type(_G.VRO_PART_LISTS)=="table" then
    for k,v in pairs(_G.VRO_PART_LISTS) do VRO.PartLists[k] = v end
  end
end
VRO_LoadPartLists()

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
          for _,ft in ipairs(lst) do out_set[ft] = true end
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
        for _,name in ipairs(fixing.requireLists) do
          _expandRequireEntry("@"..tostring(name), set)
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
    if it.getCurrentUses     then return it:getCurrentUses() end
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
  for _,t in ipairs(tags) do if it:hasTag(t) then return true end end
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
  for _,t in ipairs(tags) do
    local it = firstTagItem(inv, t)
    if it then return it end
  end
  return nil
end

local function invHasAnyTag(inv, tags)
  if inv.getFirstEvalRecurse then
    local it = inv:getFirstEvalRecurse(function(item)
      return item and item.hasTag and itemHasAnyTag(item, tags)
    end)
    return it ~= nil
  end
  for _,t in ipairs(tags) do
    if inv:containsTag(t) then return true end
  end
  return false
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
  for _,t in ipairs(tags) do
    local it = firstTagItem(inv, t)
    if it and it.getDisplayName then return it:getDisplayName() end
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

-- Tooltip icon from script data (ISToolTip in 5.1 expects string path)
local function setTooltipIconFromFullType(tip, fullType)
  local sm = ScriptManager and ScriptManager.instance
  if sm and sm.FindItem then
    local script = sm:FindItem(fullType)
    if script and script.getIcon and script:getIcon() then
      tip:setTexture("Item_" .. script:getIcon())
    end
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

-- Prefer a torch with >= needUses; otherwise fullest non-empty torch
local function findBestBlowtorch(inv, needUses)
  if inv.getFirstEvalRecurse then
    local it = inv:getFirstEvalRecurse(function(item)
      return isTorchItem(item) and drainableUses(item) >= (needUses or 1)
    end)
    if it then return it end
  end
  if inv.getBestEvalRecurse then
    local best = inv:getBestEvalRecurse(
      function(item) return isTorchItem(item) and drainableUses(item) > 0 end,
      function(a,b)
        local ua = (a and a.getDrainableUsesInt) and a:getDrainableUsesInt() or drainableUses(a)
        local ub = (b and b.getDrainableUsesInt) and b:getDrainableUsesInt() or drainableUses(b)
        return ua - ub
      end)
    if best then return best end
  end
  local bagged = ArrayList.new()
  inv:getAllTypeRecurse("Base.BlowTorch", bagged)
  local best, most = nil, -1
  for i = 1, bagged:size() do
    local it = bagged:get(i-1)
    local u  = drainableUses(it)
    if u > most then most = u; best = it end
  end
  return best
end

-- Item must be NOT broken and strictly below max condition to be repairable from inventory
local function isRepairableFromInventory(it)
  if not it then return false end
  if it.isBroken and it:isBroken() then return false end
  local max = it.getConditionMax and it:getConditionMax() or 100
  local cur = it.getCondition   and it:getCondition()    or max
  return cur < max
end

-- Normalize single/global into a list (fixer overrides recipe)
local function resolveGlobalList(fixer, fixing)
  -- fixer.globalItems overrides; else fixing.globalItems; else single globalItem on fixer/recipe
  local gi = (fixer and fixer.globalItems) or (fixing and fixing.globalItems)
  if gi and type(gi) == "table" then
    if gi[1] then return gi end
    return { gi }
  end
  local single = (fixer and fixer.globalItem) or (fixing and fixing.globalItem)
  if single then return { single } end
  return nil
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
local function _appendOneOfTagsList(desc, inv, tags, need)
  local added = {}   -- fullType -> true (avoid dupes across tags)
  local lines = {}
  local needStr = tostring(math.max(1, tonumber(need) or 1)) .. "/"

  for _, tag in ipairs(tags) do
    local arr = _getScriptsForTag(tag)
    if arr and arr.size and arr:size() > 0 then
      for i = 1, arr:size() do
        local si = arr:get(i-1)
        local ft = _scriptFullType(si)
        if ft and not added[ft] then
          added[ft] = true
          local have = (countTypeRecurse(inv, ft) > 0)
          local rgb  = have and "0,1,0" or "1,0,0"
          local nm   = _scriptDispName(si)
          -- show "x/need" where x is 1 if we have at least one, else 0
          local haveStr = (have and "1" or "0") .. "/" .. tostring(math.max(1, tonumber(need) or 1))
          table.insert(lines,
            string.format(" <INDENT:20> <RGB:%s>%s %s <LINE> <INDENT:0> ", rgb, nm, haveStr))
        end
      end
    end
  end

  if #lines > 0 then
    desc = desc .. " " .. getText("IGUI_CraftUI_OneOf") .. " <LINE> "
    for _, L in ipairs(lines) do desc = desc .. L end
  end
  return desc
end

----------------------------------------------------------------
-- C) Path & facing
----------------------------------------------------------------
local function queuePathToPartArea(playerObj, part)
  local vehicle = part and part:getVehicle()
  if not playerObj or not vehicle then return end
  local area = (part and part.getArea and part:getArea()) or "Engine"
  ISTimedActionQueue.add(ISPathFindAction:pathToVehicleArea(playerObj, vehicle, tostring(area)))
end

----------------------------------------------------------------
-- D) Tooltip (dynamic color + icon)
----------------------------------------------------------------
local function interpColorTag(frac)
  local c = ColorInfo.new(0,0,0,1)
  getCore():getBadHighlitedColor():interp(getCore():getGoodHighlitedColor(), math.max(0, math.min(1, frac or 0)), c)
  return string.format("<RGB:%s,%s,%s>", c:getR(), c:getG(), c:getB())
end

local function addNeedsLine(desc, rgb, name, have, need)
  return desc .. string.format(" <RGB:%s>%s %d/%d <LINE> ", rgb, name, have, need)
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
  if f == nil then f = true end
  return f
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

-- Replaces the existing addFixerTooltip
local function addFixerTooltip(tip, player, part, fixing, fixer, fixerIndex, brokenItem)
  tip:initialise(); tip:setVisible(false)
  setTooltipIconFromFullType(tip, fixer.item)
  tip:setName(displayNameFromFullType(fixer.item))

  local hbr     = getHBR(part, brokenItem)
  local pot     = math.ceil(condRepairedPercent(brokenItem, player, fixing, fixer, hbr, fixerIndex))
  local success = 100 - math.ceil(chanceOfFail(brokenItem, player, fixing, fixer, hbr))

  local c1 = interpColorTag((pot or 0)/100)
  local c2 = interpColorTag((success or 0)/100)

  -- We’ll build 3 buckets, then concatenate in order:
  --  1) reqLines: all “normal” lines (appear first)
  --  2) oneOfBlocks: any “One of:” expansions (only when player lacks a multi-tag item)
  --  3) skillLines: perk lines (always last)
  local reqLines, oneOfBlocks, skillLines = {}, {}, {}

  local function lineStr(rgb, name, have, need)
    return string.format(" <RGB:%s>%s %d/%d <LINE> ", rgb, name, have, need)
  end

  local function pushReq(rgb, name, have, need)
    reqLines[#reqLines+1] = lineStr(rgb, name, have, need)
  end
  local function pushSkill(rgb, name, have, need)
    skillLines[#skillLines+1] = lineStr(rgb, name, have, need)
  end
  local function pushOneOfBlock(textBlock)
    if textBlock and textBlock ~= "" then oneOfBlocks[#oneOfBlocks+1] = textBlock end
  end

  -- De-dup across globals/equip (e.g., BlowTorch both places)
  local seenFull = {}   -- fullType set
  local function markSeenItemFT(ft) if ft then seenFull[ft] = true end end
  local function wasSeenFT(ft) return ft and seenFull[ft] == true end

  local inv = player:getInventory()

  -- Helper: count total “uses” we own for a fullType, capping at need (handles drainables)
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

  -- Header
  local desc = ""
  desc = desc .. " " .. c1 .. " " .. getText("Tooltip_potentialRepair") .. " " .. (pot or 0) .. "%"
  desc = desc .. " <LINE> " .. c2 .. " " .. getText("Tooltip_chanceSuccess") .. " " .. (success or 0) .. "%"
  desc = desc .. " <LINE> <LINE> <RGB:1,1,1> " .. getText("Tooltip_craft_Needs") .. ": <LINE> <LINE>"

  -- 1) Fixer item (like vanilla)
  do
    local need = fixer.uses or 1
    local have = invHaveForFullType(fixer.item, need)
    local nm   = displayNameFromFullType(fixer.item)
    local rgb  = (have >= need) and "0,1,0" or "1,0,0"
    pushReq(rgb, nm, have, need)
    if have > 0 and (have >= need) then markSeenItemFT(fixer.item) end
  end

  -- 2) Global items (consumed or not), multi-tag aware, and de-duped
  do
    local effGlobals = resolveGlobalList(fixer, fixing)
    if effGlobals and #effGlobals > 0 then
      for _,gi in ipairs(effGlobals) do
        local tags = normalizeTagsField(gi)
        -- NOT CONSUMED
        if gi.consume == false then
          if tags then
            -- If any matching item exists, show a single normal line for the *chosen* item; else only the “One of:” block (no combined Scissors/SharpKnife line).
            local chosen = findBestByTags(inv, tags, 1)
            if chosen then
              local nm = chosen:getDisplayName() or displayNameForTags(inv, tags)
              pushReq("0,1,0", nm, 1, 1)
              markSeenItemFT(chosen:getFullType())
            else
              local need = gi.uses or 1
              pushOneOfBlock(_appendOneOfTagsList("", inv, tags, need))
            end
          elseif gi.tag then
            local present = hasTag(inv, gi.tag)
            if present then
              local it  = firstTagItem(inv, gi.tag)
              local nm  = (it and it.getDisplayName and it:getDisplayName()) or displayNameForTag(inv, gi.tag)
              pushReq("0,1,0", nm, 1, 1)
              if it and it.getFullType then markSeenItemFT(it:getFullType()) end
            else
              local need = gi.uses or 1
              pushOneOfBlock(_appendOneOfTagsList("", inv, { gi.tag }, need))
            end
          elseif gi.item then
            local present = countTypeRecurse(inv, gi.item) > 0
            local nm  = displayNameFromFullType(gi.item)
            pushReq(present and "0,1,0" or "1,0,0", nm, present and 1 or 0, 1)
            if present then markSeenItemFT(gi.item) end
          end

        -- CONSUMED
        else
          local need = gi.uses or 1
          if tags then
            local it   = findBestByTags(inv, tags, need)
            if it then
              local have = isDrainable(it) and math.min(drainableUses(it), need) or 1
              local nm   = it:getDisplayName() or displayNameForTags(inv, tags)
              pushReq((have >= need) and "0,1,0" or "1,0,0", nm, have, need)
              if have >= need then markSeenItemFT(it:getFullType()) end
            else
              -- No base “Scissors/SharpKnife 0/1” line; only the OneOf block
              pushOneOfBlock(_appendOneOfTagsList("", inv, tags, need))
            end
          elseif gi.tag then
            local it   = findBestByTag(inv, gi.tag, need)
            if it then
              local have = isDrainable(it) and math.min(drainableUses(it), need) or 1
              local nm   = it:getDisplayName() or displayNameForTag(inv, gi.tag)
              pushReq((have >= need) and "0,1,0" or "1,0,0", nm, have, need)
              if have >= need then markSeenItemFT(it:getFullType()) end
            else
              -- keep vanilla style for single-tag
              pushOneOfBlock(_appendOneOfTagsList("", inv, { gi.tag }, need))
            end
          elseif gi.item then
            local have = invHaveForFullType(gi.item, need)
            local nm   = displayNameFromFullType(gi.item)
            pushReq((have >= need) and "0,1,0" or "1,0,0", nm, have, need)
            if have >= need then markSeenItemFT(gi.item) end
          end
        end
      end
    end
  end

  -- 3) Wear requirement (not consumed); for multi-tag wear only show OneOf block when missing
  do
    local eq = mergeEquip(fixer.equip, fixing.equip)
    if eq.wearTag then
      local present = hasTag(inv, eq.wearTag)
      if present then
        local it  = firstTagItem(inv, eq.wearTag)
        local nm  = (it and it.getDisplayName and it:getDisplayName()) or fallbackNameForTag(eq.wearTag)
        pushReq("0,1,0", nm, 1, 1)
        if it and it.getFullType then markSeenItemFT(it:getFullType()) end
      else
        -- keep a single “Welding Mask 0/1” + OneOf block (single tag)
        pushOneOfBlock(_appendOneOfTagsList("", inv, { eq.wearTag }, 1))
      end
    elseif eq.wear then
      local it  = findFirstTypeRecurse(inv, eq.wear)
      local nm  = (it and it.getDisplayName and it:getDisplayName()) or displayNameFromFullType(eq.wear)
      pushReq(it and "0,1,0" or "1,0,0", nm, it and 1 or 0, 1)
      if it and it.getFullType then markSeenItemFT(it:getFullType()) end
    end
  end

  -- 4) Primary / Secondary (not consumed) — skip if we already showed the same item (de-dup vs globals)
  do
    local eq = mergeEquip(fixer.equip, fixing.equip)

    local function showEquipByItem(fullType)
      if not fullType then return end
      if wasSeenFT(fullType) then return end
      local present = countTypeRecurse(inv, fullType) > 0
      local nm  = displayNameFromFullType(fullType)
      pushReq(present and "0,1,0" or "1,0,0", nm, present and 1 or 0, 1)
      if present then markSeenItemFT(fullType) end
    end

    local function showEquipByTag(tag)
      if not tag then return end
      -- try to resolve the chosen item for de-dup
      local it = findBestByTag(inv, tag, 1)
      if it and wasSeenFT(it:getFullType()) then return end
      if it then
        pushReq("0,1,0", it:getDisplayName() or fallbackNameForTag(tag), 1, 1)
        markSeenItemFT(it:getFullType())
      else
        -- (optional) show OneOf for equip tags; keep your previous behavior
        pushOneOfBlock(_appendOneOfTagsList("", inv, { tag }, 1))
      end
    end

    if eq.primary   then showEquipByItem(eq.primary)
    elseif eq.primaryTag then showEquipByTag(eq.primaryTag) end

    if eq.secondary and eq.secondary ~= eq.primary then showEquipByItem(eq.secondary)
    elseif eq.secondaryTag and eq.secondaryTag ~= eq.primaryTag then showEquipByTag(eq.secondaryTag) end
  end

  -- 5) Skills (always last)
  if fixer.skills then
    for name,req in pairs(fixer.skills) do
      local lvl = perkLevel(player, name)
      local ok  = lvl >= req
      local perkLabel = (getText and getText("IGUI_perks_" .. name)) or name
      if perkLabel == ("IGUI_perks_" .. name) then perkLabel = name end
      pushSkill(ok and "0,1,0" or "1,0,0", perkLabel, lvl, req)
    end
  end

  -- Stitch all sections together
  desc = desc .. table.concat(reqLines)
  if #oneOfBlocks > 0 then
    -- Each _appendOneOfTagsList() already includes “One of:” header + lines.
    for _,blk in ipairs(oneOfBlocks) do desc = desc .. " " .. blk end
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

local function isFullTypeBlowTorch(fullType)
  if not fullType then return false end
  if fullType == "Base.BlowTorch" or string.find(fullType, "BlowTorch", 1, true) then return true end
  local sm = ScriptManager and ScriptManager.instance
  if sm and sm.getItem then
    local si = sm:getItem(fullType)
    if si and si:hasTag("BlowTorch") then return true end
  end
  return false
end

-- helper to DRY up fullType/tag selection
local function _pickByFullOrTag(inv, fullType, tag, needUses)
  if fullType then
    return findFirstTypeRecurse(inv, fullType)
  elseif tag then
    return findBestByTag(inv, tag, needUses or 1)
  end
  return nil
end

-- returns (chosenPrimary, chosenSecondary)
local function queueEquipActions(playerObj, eq, globalItem)
  if not eq then return end
  local chosenPrimary, chosenSecondary = nil, nil

  local needTorchUses = nil
  local torchRequested = false

  if globalItem then
    local gTags = normalizeTagsField(globalItem)
    if (globalItem.item and isFullTypeBlowTorch(globalItem.item))
       or (globalItem.tag == "BlowTorch")
       or (gTags and (function()
            for _,t in ipairs(gTags) do if t == "BlowTorch" then return true end end
            return false
          end)())
    then
      needTorchUses = globalItem.uses or 1
    end
  end
  if (eq.primary and isFullTypeBlowTorch(eq.primary)) or (eq.primaryTag == "BlowTorch") then
    torchRequested = true
  end

  -- PRIMARY
  do
    local inv = playerObj:getInventory()
    local desiredPrimary = nil
    if torchRequested then
      desiredPrimary = findBestBlowtorch(inv, needTorchUses or 1)
      if not desiredPrimary then
        desiredPrimary = _pickByFullOrTag(inv, eq.primary, eq.primaryTag, 1)
      end
    else
      desiredPrimary = _pickByFullOrTag(inv, eq.primary, eq.primaryTag, 1)
    end

    if desiredPrimary then
      chosenPrimary = desiredPrimary
      toPlayerInventory(playerObj, desiredPrimary)
      ISTimedActionQueue.add(ISEquipWeaponAction:new(playerObj, desiredPrimary, 50, true, false))
    end
  end

  -- SECONDARY
  do
    local inv = playerObj:getInventory()
    local desiredSecondary = _pickByFullOrTag(inv, eq.secondary, eq.secondaryTag, 1)
    if desiredSecondary then
      chosenSecondary = desiredSecondary
      toPlayerInventory(playerObj, desiredSecondary)
      ISTimedActionQueue.add(ISEquipWeaponAction:new(playerObj, desiredSecondary, 50, false, false))
    end
  end

  -- WEAR
  if eq.wearTag and ISInventoryPaneContextMenu and ISInventoryPaneContextMenu.wearItem then
    local it = firstTagItem(playerObj:getInventory(), eq.wearTag)
    if it then toPlayerInventory(playerObj, it); ISInventoryPaneContextMenu.wearItem(it, playerObj:getPlayerNum()) end
  elseif eq.wear and ISInventoryPaneContextMenu and ISInventoryPaneContextMenu.wearItem then
    local it = findFirstTypeRecurse(playerObj:getInventory(), eq.wear)
    if it then toPlayerInventory(playerObj, it); ISInventoryPaneContextMenu.wearItem(it, playerObj:getPlayerNum()) end
  end

  return chosenPrimary, chosenSecondary
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
  local sub = parent.subOption
  local opts = sub.options
  if type(opts) == "table" then
    return next(opts) == nil
  end
  if opts and opts.size then
    return opts:size() == 0
  end
  return true
end

-- Mechanics window: attach our rows to vanilla "Repair" submenu if present, otherwise create it.
local old_doPart = ISVehicleMechanics.doPartContextMenu
function ISVehicleMechanics:doPartContextMenu(part, x, y)
  old_doPart(self, part, x, y)

  if VRO_UseVanillaFixingRecipes() then return end

  local playerObj = getSpecificPlayer(self.playerNum)
  if not playerObj or not part then return end
  if not part:getItemType() or part:getItemType():isEmpty() then return end
  local broken = part:getInventoryItem(); if not broken then return end
  if part:getCondition() >= 100 then return end

  local ft, any = broken:getFullType(), false
  for _,fx in ipairs(VRO.Recipes) do
    local set = resolveRequireSet(fx)
    if set[ft] then any = true; break end
  end
  if not any then return end

  self.context = self.context or ISContextMenu.get(self.playerNum, x + self:getAbsoluteX(), y + self:getAbsoluteY())

  local repairTxt = getText("ContextMenu_Repair")
  local parent = findRepairParentOption(self.context, function(n) return n == repairTxt end)
  if not parent then parent = self.context:addOption(repairTxt, nil, nil) end
  local sub = ensureSubMenu(self.context, parent); if not sub then return end

  -- Local helpers (scoped to this function only)
  local function _normalizeGlobals(fixer, fixing)
    local giList = (fixer and fixer.globalItems) or (fixing and fixing.globalItems)
    if giList and type(giList) == "table" then
      if giList[1] then return giList end
      return { giList }
    end
    local single = (fixer and fixer.globalItem) or (fixing and fixing.globalItem)
    if single then return { single } end
    return nil
  end

  local function _gatherMultiGlobals(inv, list)
    if not list then return true, nil end
    if type(list) == "table" and not list[1] and (list.item or list.tag or list.tags) then
      list = { list }
    end
    if type(list) ~= "table" or #list == 0 then
      return true, nil
    end

    local allOK, flat = true, {}

    for i = 1, #list do
      local gi = list[i]
      if type(gi) ~= "table" then
        allOK = false; break
      end

      local tags = normalizeTagsField(gi)

      if gi.consume == false then
        if tags then
          if not invHasAnyTag(inv, tags) then allOK = false; break end
        elseif gi.tag then
          if not hasTag(inv, gi.tag) then allOK = false; break end
        elseif gi.item then
          if countTypeRecurse(inv, gi.item) <= 0 then allOK = false; break end
        else
          allOK = false; break
        end
      else
        local need = gi.uses or 1
        if tags then
          local it = findBestByTags(inv, tags, need)
          if it and (not isDrainable(it) or drainableUses(it) >= need) then
            flat[#flat+1] = { item = it, takeUses = isDrainable(it) and need or 1 }
          else
            allOK = false; break
          end
        elseif gi.tag then
          local it = findBestByTag(inv, gi.tag, need)
          if it and (not isDrainable(it) or drainableUses(it) >= need) then
            flat[#flat+1] = { item = it, takeUses = isDrainable(it) and need or 1 }
          else
            allOK = false; break
          end
        elseif gi.item then
          local b = gatherRequiredItems(inv, gi.item, need)
          if b then for _,entry in ipairs(b) do flat[#flat+1] = entry end
          else allOK = false; break end
        else
          allOK = false; break
        end
      end
    end

    if flat[1] then return allOK, flat else return allOK, nil end
  end

  local function _pickTorchGlobal(list, fallbackSingle)
    if list then
      for _,gi in ipairs(list) do
        local gTags = normalizeTagsField(gi)
        if gi.tag == "BlowTorch" then return gi end
        if gTags then
          for _,t in ipairs(gTags) do if t == "BlowTorch" then return gi end end
        end
        if gi.item and (gi.item == "Base.BlowTorch" or gi.item:find("BlowTorch", 1, true)) then return gi end
      end
    end
    return fallbackSingle
  end

  local rendered = false
  for _,fixing in ipairs(VRO.Recipes) do
    local applies = resolveRequireSet(fixing)[ft] == true
    if applies then
      for idx, fixer in ipairs(fixing.fixers or {}) do
        local fxBundle = gatherRequiredItems(playerObj:getInventory(), fixer.item, fixer.uses or 1)

        local multiList = _normalizeGlobals(fixer, fixing)
        local glOK, glBundle = true, nil

        if multiList then
          glOK, glBundle = _gatherMultiGlobals(playerObj:getInventory(), multiList)
        else
          local gi = (fixer and fixer.globalItem) or (fixing and fixing.globalItem)
          if gi then
            local tags = normalizeTagsField(gi)
            if gi.consume == false then
              if tags then
                glOK = invHasAnyTag(playerObj:getInventory(), tags)
              elseif gi.tag then
                glOK = hasTag(playerObj:getInventory(), gi.tag)
              else
                glOK = countTypeRecurse(playerObj:getInventory(), gi.item) > 0
              end
            else
              local need = gi.uses or 1
              if tags then
                local it = findBestByTags(playerObj:getInventory(), tags, need)
                if it and (not isDrainable(it) or drainableUses(it) >= need) then
                  glBundle = { { item = it, takeUses = isDrainable(it) and need or 1 } }
                  glOK = true
                else
                  glOK = false
                end
              elseif gi.tag then
                local it = findBestByTag(playerObj:getInventory(), gi.tag, need)
                if it and (not isDrainable(it) or drainableUses(it) >= need) then
                  glBundle = { { item = it, takeUses = isDrainable(it) and need or 1 } }
                  glOK = true
                else
                  glOK = false
                end
              else
                glBundle = gatherRequiredItems(playerObj:getInventory(), gi.item, need)
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
          wearOK = hasTag(playerObj:getInventory(), eq.wearTag)
        elseif eq.wear then
          wearOK = (findFirstTypeRecurse(playerObj:getInventory(), eq.wear) ~= nil)
        end

        local haveAll = fxBundle and glOK and skillsOK and wearOK
        local raw   = displayNameFromFullType(fixer.item)
        local label = tostring(fixer.uses or 1) .. " " .. humanizeForMenuLabel(raw)

        local option
        if haveAll then
          rendered = true

          local singleFallback = (fixer and fixer.globalItem) or (fixing and fixing.globalItem)
          local torchGlobal    = _pickTorchGlobal(multiList, singleFallback)

          option = sub:addOption(label, playerObj, function(p, prt, fixg, fixr, idx_, brk, fxB, glB, torchHint)
            queuePathToPartArea(p, prt)
            local chosenP, chosenS = queueEquipActions(p, mergeEquip(fixr.equip, fixg.equip), torchHint)
            local tm    = resolveTime(fixr, fixg, p, brk)
            local anim  = resolveAnim(fixr, fixg)
            local sfx   = resolveSound(fixr, fixg)
            local sfxOK = resolveSuccessSound(fixr, fixg)
            local showM = resolveShowModel(fixr, fixg)
            ISTimedActionQueue.add(VRO.DoFixAction:new{
              character=p, part=prt, fixing=fixg, fixer=fixr, fixerIndex=idx_,
              brokenItem=brk, fixerBundle=fxB, globalBundle=glB,
              time=tm, anim=anim, sfx=sfx, successSfx=sfxOK, showModel=showM,
              expectedPrimary=chosenP, expectedSecondary=chosenS,
            })
          end, part, fixing, fixer, idx, broken, fxBundle, glBundle, torchGlobal)

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
-- F) Inventory repairs (vanilla-style submenu; attach to existing)
----------------------------------------------------------------
local function resolveInvItemFromContext(items)
  if not items or #items==0 then return nil end
  local first = items[1]
  if instanceof(first,"InventoryItem") then return first end
  if type(first)=="table" then
    if first.items and #first.items>0 and instanceof(first.items[1],"InventoryItem") then return first.items[1] end
    if first.item and instanceof(first.item,"InventoryItem") then return first.item end
  end
  for _,v in ipairs(items) do
    if instanceof(v,"InventoryItem") then return v end
    if type(v)=="table" then
      if v.items and #v.items>0 and instanceof(v.items[1],"InventoryItem") then return v.items[1] end
      if v.item and instanceof(v.item,"InventoryItem") then return v.item end
    end
  end
  return nil
end

local function invRepairLabel(item)
  local nm = (getItemNameFromFullType and getItemNameFromFullType(item:getFullType()))
           or (item.getDisplayName and item:getDisplayName())
           or (item.getType and item:getType()) or "Item"
  return getText("ContextMenu_Repair") .. nm
end

local function addInventoryFixOptions(playerObj, context, broken)
  if VRO_UseVanillaFixingRecipes() then return end
  if not isRepairableFromInventory(broken) then return end
  local ft = broken:getFullType(); if not ft then return end

  local any=false
  for _,fx in ipairs(VRO.Recipes) do
    local set = resolveRequireSet(fx)
    if set[ft] then any=true break end
  end
  if not any then return end

  local expectedLabel = invRepairLabel(broken)
  local parent = findRepairParentOption(context, function(n) return n == expectedLabel end)
  if not parent then parent = context:addOption(expectedLabel, nil, nil) end
  local sub = ensureSubMenu(context, parent); if not sub then return end

  local rendered = false
  for _,fixing in ipairs(VRO.Recipes) do
    local applies = resolveRequireSet(fixing)[ft] == true
    if applies then
      for idx, fixer in ipairs(fixing.fixers or {}) do
        local fxBundle  = gatherRequiredItems(playerObj:getInventory(), fixer.item, fixer.uses or 1)

        local effGlobal = fixer.globalItem or fixing.globalItem
        local glOK, glBundle = true, nil
        if effGlobal then
          local gi = effGlobal
          local tags = normalizeTagsField(gi)
          if gi.consume == false then
            if tags then
              glOK = invHasAnyTag(playerObj:getInventory(), tags)
            elseif gi.tag then
              glOK = hasTag(playerObj:getInventory(), gi.tag)
            else
              glOK = countTypeRecurse(playerObj:getInventory(), gi.item) > 0
            end
          else
            local need = gi.uses or 1
            if tags then
              local it = findBestByTags(playerObj:getInventory(), tags, need)
              if it and (not isDrainable(it) or drainableUses(it) >= need) then
                glBundle = { { item = it, takeUses = isDrainable(it) and need or 1 } }
                glOK = true
              else
                glOK = false
              end
            elseif gi.tag then
              local it = findBestByTag(playerObj:getInventory(), gi.tag, need)
              if it and (not isDrainable(it) or drainableUses(it) >= need) then
                glBundle = { { item = it, takeUses = isDrainable(it) and need or 1 } }
                glOK = true
              else
                glOK = false
              end
            else
              glBundle = gatherRequiredItems(playerObj:getInventory(), gi.item, need)
              glOK = (glBundle ~= nil)
            end
          end
        end

        local skillsOK = true
        if fixer.skills then
          for name,req in pairs(fixer.skills) do if perkLevel(playerObj,name) < req then skillsOK=false break end end
        end
        local eq = mergeEquip(fixer.equip, fixing.equip)
        local wearOK = true
        if eq.wearTag then wearOK = hasTag(playerObj:getInventory(), eq.wearTag)
        elseif eq.wear then wearOK = (findFirstTypeRecurse(playerObj:getInventory(), eq.wear) ~= nil) end

        local haveAll = fxBundle and glOK and skillsOK and wearOK
        local raw = displayNameFromFullType(fixer.item)
        local label = tostring(fixer.uses or 1) .. " " .. humanizeForMenuLabel(raw)

        local option
        if haveAll then
          rendered=true
          option = sub:addOption(label, playerObj, function(p, fixg, fixr, idx_, brk, fxB, glB, gItem)
            local chosenP, chosenS = queueEquipActions(p, mergeEquip(fixr.equip, fixg.equip), gItem)
            local tm    = resolveTime(fixr, fixg, p, brk)
            local anim  = resolveInvAnim(fixr, fixg)
            local sfx   = resolveSound(fixr, fixg)
            local sfxOK = resolveSuccessSound(fixr, fixg)
            local showM = resolveShowModel(fixr, fixg)
            ISTimedActionQueue.add(VRO.DoFixAction:new{
              character=p, part=nil, fixing=fixg, fixer=fixr, fixerIndex=idx_,
              brokenItem=brk, fixerBundle=fxB, globalBundle=glB,
              time=tm, anim=anim, sfx=sfx, successSfx=sfxOK, showModel=showM,
              expectedPrimary=chosenP, expectedSecondary=chosenS,
            })
          end, fixing, fixer, idx, broken, fxBundle, glBundle, effGlobal)
        else
          option = sub:addOption(label, nil, nil); option.notAvailable = true
        end
        local tip = ISToolTip:new(); addFixerTooltip(tip, playerObj, nil, fixing, fixer, idx, broken); option.toolTip = tip
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
if not _G.VRO_InvHooked then
  Events.OnFillInventoryObjectContextMenu.Add(OnFillInventoryObjectContextMenu)
  _G.VRO_InvHooked = true
end

----------------------------------------------------------------
-- G) Public API
----------------------------------------------------------------
function VRO.addRecipe(recipe) table.insert(VRO.Recipes, recipe) end
VRO.API = { addRecipe = VRO.addRecipe }
VRO.Module = VRO
return VRO
