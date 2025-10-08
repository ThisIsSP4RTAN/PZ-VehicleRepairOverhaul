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

----------------------------------------------------------------
-- A) Recipes (edit these)
-- You can put defaults on the recipe itself:
--   equip = {
--     primary="Base.BlowTorch",  -- or primaryTag="BlowTorch"
--     secondary="Base.Hammer",   -- or secondaryTag="Hammer"
--     wearTag="WeldingMask"      -- or wear="Base.WelderMask"
--   }
--   anim  = "Welding"
--   sound = "BlowTorch"          -- loops during repair (if set)
--   successSound = "SomeEvent"   -- plays after a successful repair (optional)
--   time  = function(player, brokenItem) return 160 end  -- or a number
--
-- globalItem supports:
--   { item="<FullType>", uses=3, consume=true }
--   { tag ="<TagName>",  uses=3, consume=true }
-- If consume=false, the item is required but NOT consumed.
----------------------------------------------------------------
VRO.Recipes = {
--[[  (recipes may be injected via VRO_Recipes.lua)  ]]
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
-- B) Helpers
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

-- Best single item by tag (favor meeting needUses for drainables; else fullest)
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
      end
    )
    if best then return best end
  end
  return firstTagItem(inv, tag)
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
  if tag == "WeldingMask" then return "Welding Mask" end
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
      end
    )
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

----------------------------------------------------------------
-- C) Perks + math
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

----------------------------------------------------------------
-- D) Path & facing
----------------------------------------------------------------
local function queuePathToPartArea(playerObj, part)
  local vehicle = part and part:getVehicle()
  if not playerObj or not vehicle then return end
  local area = (part and part.getArea and part:getArea()) or "Engine"
  ISTimedActionQueue.add(ISPathFindAction:pathToVehicleArea(playerObj, vehicle, tostring(area)))
end

----------------------------------------------------------------
-- E) Tooltip (dynamic color + icon)
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

local function addFixerTooltip(tip, player, part, fixing, fixer, fixerIndex, brokenItem)
  tip:initialise(); tip:setVisible(false)
  setTooltipIconFromFullType(tip, fixer.item)
  tip:setName(displayNameFromFullType(fixer.item))

  local hbr     = getHBR(part, brokenItem)
  local pot     = math.ceil(condRepairedPercent(brokenItem, player, fixing, fixer, hbr, fixerIndex))
  local success = 100 - math.ceil(chanceOfFail(brokenItem, player, fixing, fixer, hbr))

  local c1 = interpColorTag((pot or 0)/100)
  local c2 = interpColorTag((success or 0)/100)

  local desc = ""
  desc = desc .. " " .. c1 .. " " .. getText("Tooltip_potentialRepair") .. " " .. (pot or 0) .. "%"
  desc = desc .. " <LINE> " .. c2 .. " " .. getText("Tooltip_chanceSuccess") .. " " .. (success or 0) .. "%"
  desc = desc .. " <LINE> <LINE> <RGB:1,1,1> " .. getText("Tooltip_craft_Needs") .. ": <LINE> <LINE>"

  -- We'll track "seen" so we don't duplicate lines (e.g., primary==global)
  local seen = {}
  local effGlobal = fixer.globalItem or fixing.globalItem
  if effGlobal then
    if effGlobal.tag then seen["tag:"..tostring(effGlobal.tag)] = true
    elseif effGlobal.item then seen["item:"..tostring(effGlobal.item)] = true end
  end

  do
    local need = fixer.uses or 1
    local have = 0
    local bundles = gatherRequiredItems(player:getInventory(), fixer.item, need)
    if bundles then for _,b in ipairs(bundles) do have = have + (b.takeUses or 0) end end
    local nm  = displayNameFromFullType(fixer.item)
    local rgb = (have >= need) and "0,1,0" or "1,0,0"
    desc = addNeedsLine(desc, rgb, nm, have, need)
  end

  if effGlobal then
    local gi = effGlobal
    if gi.consume == false then
      if gi.tag then
        local present = hasTag(player:getInventory(), gi.tag)
        local nm  = displayNameForTag(player:getInventory(), gi.tag)
        local rgb = present and "0,1,0" or "1,0,0"
        desc = addNeedsLine(desc, rgb, nm, present and 1 or 0, 1)
      else
        local present = countTypeRecurse(player:getInventory(), gi.item) > 0
        local nm  = displayNameFromFullType(gi.item)
        local rgb = present and "0,1,0" or "1,0,0"
        desc = addNeedsLine(desc, rgb, nm, present and 1 or 0, 1)
      end
    else
      local need = gi.uses or 1
      local have = 0
      if gi.tag then
        local it = findBestByTag(player:getInventory(), gi.tag, need)
        if it then have = isDrainable(it) and math.min(drainableUses(it), need) or 1 end
        local nm  = displayNameForTag(player:getInventory(), gi.tag)
        local rgb = (have >= need) and "0,1,0" or "1,0,0"
        desc = addNeedsLine(desc, rgb, nm, have, need)
      else
        local bundles = gatherRequiredItems(player:getInventory(), gi.item, need)
        if bundles then for _,b in ipairs(bundles) do have = have + (b.takeUses or 0) end end
        local nm  = displayNameFromFullType(gi.item)
        local rgb = (have >= need) and "0,1,0" or "1,0,0"
        desc = addNeedsLine(desc, rgb, nm, have, need)
      end
    end
  end

  -- Wear requirement (merged equip, not consumed)
  local eq = mergeEquip(fixer.equip, fixing.equip)
  if eq.wearTag then
    local ok  = hasTag(player:getInventory(), eq.wearTag)
    local it  = firstTagItem(player:getInventory(), eq.wearTag)
    local name = it and it:getDisplayName() or fallbackNameForTag(eq.wearTag)
    desc = addNeedsLine(desc, ok and "0,1,0" or "1,0,0", name, ok and 1 or 0, 1)
  elseif eq.wear then
    local it = findFirstTypeRecurse(player:getInventory(), eq.wear)
    local nm = (it and it.getDisplayName) and it:getDisplayName() or displayNameFromFullType(eq.wear)
    desc = addNeedsLine(desc, it and "0,1,0" or "1,0,0", nm, it and 1 or 0, 1)
  end

  -- Primary / Secondary (merged equip, not consumed) + tag support + de-dup with global
  local function showEquipLineByItem(fullType)
    local key = "item:"..tostring(fullType)
    if seen[key] then return end
    local present = countTypeRecurse(player:getInventory(), fullType) > 0
    local nm  = displayNameFromFullType(fullType)
    local rgb = present and "0,1,0" or "1,0,0"
    desc = addNeedsLine(desc, rgb, nm, present and 1 or 0, 1)
    seen[key] = true
  end
  local function showEquipLineByTag(tag)
    local key = "tag:"..tostring(tag)
    if seen[key] then return end
    local present = hasTag(player:getInventory(), tag)
    local nm  = displayNameForTag(player:getInventory(), tag)
    local rgb = present and "0,1,0" or "1,0,0"
    desc = addNeedsLine(desc, rgb, nm, present and 1 or 0, 1)
    seen[key] = true
  end

  if eq.primaryTag then showEquipLineByTag(eq.primaryTag)
  elseif eq.primary then showEquipLineByItem(eq.primary) end

  if eq.secondaryTag then showEquipLineByTag(eq.secondaryTag)
  elseif eq.secondary then
    -- avoid duplicate if same as primary
    if not (eq.primary and eq.primary == eq.secondary) and not (eq.primaryTag and eq.primaryTag == eq.secondary) then
      showEquipLineByItem(eq.secondary)
    end
  end

  -- Skills
  if fixer.skills then
    for name,req in pairs(fixer.skills) do
      local lvl = perkLevel(player, name)
      local ok  = lvl >= req
      local perkLabel = (getText and getText("IGUI_perks_" .. name)) or name
      if perkLabel == ("IGUI_perks_" .. name) then perkLabel = name end
      desc = addNeedsLine(desc, ok and "0,1,0" or "1,0,0", perkLabel, lvl, req)
    end
  end

  tip.description = desc
end

----------------------------------------------------------------
-- F) Context Menu Injection (attach to vanilla "Repair")
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
    if (globalItem.item and isFullTypeBlowTorch(globalItem.item)) or (globalItem.tag == "BlowTorch") then
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

  -- If sandbox is set to use vanilla only, do not add our Lua rows.
  if VRO_UseVanillaFixingRecipes() then return end

  local playerObj = getSpecificPlayer(self.playerNum)
  if not playerObj or not part then return end
  if not part:getItemType() or part:getItemType():isEmpty() then return end
  local broken = part:getInventoryItem(); if not broken then return end
  if part:getCondition() >= 100 then return end

  local ft, any = broken:getFullType(), false
  for _,fx in ipairs(VRO.Recipes) do
    local set = resolveRequireSet(fx)
    if set[ft] then any=true break end
  end
  if not any then return end

  self.context = self.context or ISContextMenu.get(self.playerNum, x + self:getAbsoluteX(), y + self:getAbsoluteY())

  local repairTxt = getText("ContextMenu_Repair")
  local parent = findRepairParentOption(self.context, function(n) return n == repairTxt end)
  if not parent then parent = self.context:addOption(repairTxt, nil, nil) end
  local sub = ensureSubMenu(self.context, parent); if not sub then return end

  local rendered  = false
  for _,fixing in ipairs(VRO.Recipes) do
    local applies = resolveRequireSet(fixing)[ft] == true
    if applies then
      for idx, fixer in ipairs(fixing.fixers or {}) do
        local fxBundle  = gatherRequiredItems(playerObj:getInventory(), fixer.item, fixer.uses or 1)

        local effGlobal = fixer.globalItem or fixing.globalItem

        local glOK, glBundle = true, nil
        if effGlobal then
          local gi = effGlobal
          if gi.consume == false then
            if gi.tag then
              glOK = hasTag(playerObj:getInventory(), gi.tag)
            else
              glOK = countTypeRecurse(playerObj:getInventory(), gi.item) > 0
            end
          else
            if gi.tag then
              local it = findBestByTag(playerObj:getInventory(), gi.tag, gi.uses or 1)
              if it and (not isDrainable(it) or drainableUses(it) >= (gi.uses or 1)) then
                glOK = true
                glBundle = { { item = it, takeUses = isDrainable(it) and (gi.uses or 1) or 1 } }
              else
                glOK = false
              end
            else
              glBundle = gatherRequiredItems(playerObj:getInventory(), gi.item, gi.uses or 1)
              glOK = (glBundle ~= nil)
            end
          end
        end

        local skillsOK = true
        if fixer.skills then
          for name,req in pairs(fixer.skills) do
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
        local raw = displayNameFromFullType(fixer.item)
        local label = tostring(fixer.uses or 1) .. " " .. humanizeForMenuLabel(raw)

        local option
        if haveAll then
          rendered = true
          option = sub:addOption(label, playerObj, function(p, prt, fixg, fixr, idx_, brk, fxB, glB, gItem)
            queuePathToPartArea(p, prt)
            local chosenP, chosenS = queueEquipActions(p, mergeEquip(fixr.equip, fixg.equip), gItem)
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
          end, part, fixing, fixer, idx, broken, fxBundle, glBundle, effGlobal)
        else
          option = sub:addOption(label, nil, nil); option.notAvailable = true
        end
        local tip = ISToolTip:new(); addFixerTooltip(tip, playerObj, part, fixing, fixer, idx, broken); option.toolTip = tip
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
  for _,v in ipairs(items) do
    if instanceof(v,"InventoryItem") then return v end
    if type(v)=="table" then
      if v.items and #v.items>0 and instanceof(v.items[1],"InventoryItem") then return v.items[1] end
      if v.item and instanceof(v.item,"InventoryItem") then return v.item end
    end
  end
  return nil
end

local function isInventoryItemBroken(item)
  if not item then return false end
  if item.isBroken and item:isBroken() then return true end
  if item.getCondition and item.getConditionMax then return item:getCondition() <= 0 end
  return false
end

local function invRepairLabel(item)
  local nm = (getItemNameFromFullType and getItemNameFromFullType(item:getFullType()))
           or (item.getDisplayName and item:getDisplayName())
           or (item.getType and item:getType()) or "Item"
  return getText("ContextMenu_Repair") .. nm
end

local function addInventoryFixOptions(playerObj, context, broken)
  if VRO_UseVanillaFixingRecipes() then return end -- sandbox toggle
  if not broken or isInventoryItemBroken(broken) then return end -- vanilla: only when NOT broken
  local ft = broken:getFullType(); if not ft then return end

  local any=false
  for _,fx in ipairs(VRO.Recipes) do
    local set = resolveRequireSet(fx)
    if set[ft] then any=true break end
  end
  if not any then return end

  local repairPrefix = getText("ContextMenu_Repair")
  local parent = findRepairParentOption(context, function(n)
    return string.sub(n, 1, string.len(repairPrefix)) == repairPrefix
  end)
  if not parent then parent = context:addOption(invRepairLabel(broken), nil, nil) end
  local sub = ensureSubMenu(context, parent); if not sub then return end

  local rendered=false
  for _,fixing in ipairs(VRO.Recipes) do
    local applies = resolveRequireSet(fixing)[ft] == true
    if applies then
      for idx,fixer in ipairs(fixing.fixers or {}) do
        local fxBundle  = gatherRequiredItems(playerObj:getInventory(), fixer.item, fixer.uses or 1)

        local effGlobal = fixer.globalItem or fixing.globalItem
        -- global item presence/consumption logic (supports tag or item)
        local glOK, glBundle = true, nil
        if effGlobal then
          local gi = effGlobal
          if gi.consume == false then
            if gi.tag then
              glOK = hasTag(playerObj:getInventory(), gi.tag)
            else
              glOK = countTypeRecurse(playerObj:getInventory(), gi.item) > 0
            end
          else
            if gi.tag then
              local it = findBestByTag(playerObj:getInventory(), gi.tag, gi.uses or 1)
              if it and (not isDrainable(it) or drainableUses(it) >= (gi.uses or 1)) then
                glOK = true
                glBundle = { { item = it, takeUses = isDrainable(it) and (gi.uses or 1) or 1 } }
              else
                glOK = false
              end
            else
              glBundle = gatherRequiredItems(playerObj:getInventory(), gi.item, gi.uses or 1)
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
            local anim  = resolveAnim(fixr, fixg)
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
  local broken = resolveInvItemFromContext(items); if not broken then return end
  addInventoryFixOptions(playerObj, context, broken)
end

-- Guard re-registering on hot-reload
if not _G.VRO_InvHooked then
  Events.OnFillInventoryObjectContextMenu.Add(OnFillInventoryObjectContextMenu)
  _G.VRO_InvHooked = true
end

----------------------------------------------------------------
-- H) Public API
----------------------------------------------------------------
function VRO.addRecipe(recipe) table.insert(VRO.Recipes, recipe) end
VRO.API = { addRecipe = VRO.addRecipe }
VRO.Module = VRO
return VRO
