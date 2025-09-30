---@diagnostic disable: undefined-field, param-type-mismatch
require "Vehicles/ISUI/ISVehicleMechanics"
require "ISUI/ISToolTip"
require "TimedActions/ISBaseTimedAction"
require "TimedActions/ISPathFindAction"
require "TimedActions/ISEquipWeaponAction"

local VRO = {}
VRO.__index = VRO

----------------------------------------------------------------
-- A) Recipes (edit these)
-- You can put defaults on the recipe itself:
--   equip = { primary="Base.BlowTorch", wearTag="WeldingMask" }
--   anim  = "Welding"
--   sound = "BlowTorch"
--   time  = function(player, brokenItem) return 160 end  -- or a number
----------------------------------------------------------------
VRO.Recipes = {
  {
    name = "Fix Gas Tank Welding",
    require = {
      "Base.NormalGasTank1","Base.BigGasTank1","Base.NormalGasTank2","Base.BigGasTank2",
      "Base.NormalGasTank3","Base.BigGasTank3","Base.NormalGasTank8","Base.BigGasTank8",
      "Base.U1550LGasTank2","Base.MH_MkIIgastank1","Base.MH_MkIIgastank2","Base.MH_MkIIgastank3",
      "Base.M35FuelTank2","Base.NivaGasTank1","Base.97BushGasTank2","Base.ShermanGasTank2","Base.87fordF700GasTank2",
    },
    -- Global item: drives propane usage requirement
    globalItem = { item="Base.BlowTorch", uses=3 },
    conditionModifier = 0.8,

    -- RECIPE-LEVEL defaults:
    equip = { primary="Base.BlowTorch", wearTag="WeldingMask" },
    anim  = "Welding",
    sound = "BlowTorch",
    time  = function() return 160 end,

    -- Fixers can override equip/anim/sound/time per entry if needed:
    fixers = {
      { item="Base.SheetMetal",        uses=1, skills={ MetalWelding=3, Mechanics=3 } },
      { item="Base.SmallSheetMetal",   uses=2, skills={ MetalWelding=3, Mechanics=3 } },
      { item="Base.CopperSheet",       uses=1, skills={ MetalWelding=3, Mechanics=3 } },
      { item="Base.SmallCopperSheet",  uses=2, skills={ MetalWelding=3, Mechanics=3 } },
      { item="Base.GoldSheet",         uses=1, skills={ MetalWelding=3, Mechanics=3 } },
      { item="Base.SilverSheet",       uses=1, skills={ MetalWelding=3, Mechanics=3 } },
      { item="Base.SmallArmorPlate",   uses=2, skills={ MetalWelding=3, Mechanics=3 } },
      { item="Base.AluminumScrap",     uses=8, skills={ MetalWelding=3, Mechanics=3 } },
      { item="Base.BrassScrap",        uses=8, skills={ MetalWelding=3, Mechanics=3 } },
      { item="Base.CopperScrap",       uses=8, skills={ MetalWelding=3, Mechanics=3 } },
      { item="Base.IronScrap",         uses=8, skills={ MetalWelding=3, Mechanics=3 } },
      { item="Base.ScrapMetal",        uses=8, skills={ MetalWelding=3, Mechanics=3 } },
      { item="Base.SteelScrap",        uses=8, skills={ MetalWelding=3, Mechanics=3 } },
      { item="Base.UnusableMetal",     uses=8, skills={ MetalWelding=3, Mechanics=3 } },
    },
  },
}

----------------------------------------------------------------
-- B) Helpers
----------------------------------------------------------------
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

-- Recursive lookups (full type)
local function findFirstTypeRecurse(inv, fullType)
  local bagged = ArrayList.new()
  inv:getAllTypeRecurse(fullType, bagged)
  if bagged:isEmpty() then return nil end
  return bagged:get(0)
end

local function gatherRequiredItems(inv, fullType, needUses)
  local bagged = ArrayList.new()
  inv:getAllTypeRecurse(fullType, bagged)
  if bagged:isEmpty() then return nil end
  local list, total = {}, 0
  for i = 1, bagged:size() do
    local it = bagged:get(i-1)
    local u  = drainableUses(it)
    if u > 0 then
      local take = math.min(u, needUses - total)
      table.insert(list, { item = it, takeUses = take })
      total = total + take
      if total >= needUses then return list end
    end
  end
  return nil
end

local function consumeItems(chr, bundles)
  if not bundles then return end
  for _,b in ipairs(bundles) do
    local it, uses = b.item, b.takeUses or 0
    if isDrainable(it) then for _=1,uses do it:Use() end
    else chr:getInventory():Remove(it) end
  end
end

local function displayNameFromFullType(fullType)
  if getItemNameFromFullType then
    local nm = getItemNameFromFullType(fullType)
    if nm and nm ~= "" then return nm end
  end
  return fullType
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
local function setHBR(part, invItem, val)
  if invItem and invItem.setHaveBeenRepaired then invItem:setHaveBeenRepaired(val) end
  if part then part:getModData().VRO_HaveBeenRepaired = val end
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

-- Tag helpers (heater parity)
local function firstTagItem(inv, tag) return inv:getFirstTagRecurse(tag) end
local function hasTag(inv, tag) return inv:containsTag(tag) end
local function fallbackNameForTag(tag)
  if tag == "WeldingMask" then return "Welding Mask" end
  return tag
end

-- Blowtorch helpers ----------------------------------------------------------
local function isTorchItem(it)
  if not it then return false end
  if it.hasTag and it:hasTag("BlowTorch") then return true end
  local t = it.getType and it:getType() or ""
  if t == "BlowTorch" then return true end
  local ft = it.getFullType and it:getFullType() or ""
  return ft == "Base.BlowTorch"
end

local function scriptFullTypeHasTorchTag(fullType)
  local sm = ScriptManager and ScriptManager.instance
  if not (sm and sm.getItem) then return false end
  local si = sm:getItem(fullType)
  return si and si:hasTag("BlowTorch") or false
end

local function isFullTypeBlowTorch(fullType)
  if not fullType then return false end
  if fullType == "Base.BlowTorch" or string.find(fullType, "BlowTorch", 1, true) then return true end
  return scriptFullTypeHasTorchTag(fullType)
end

-- Prefer a torch with >= needUses; otherwise the fullest non-empty torch.
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
-- ---------------------------------------------------------------------------

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
-- E) Timed Action
----------------------------------------------------------------
VRO.DoFixAction = ISBaseTimedAction:derive("VRO_DoFixAction")

local function defaultAnimForPart(part)
  if not part then return "VehicleWorkOnMid" end
  if part.getWheelIndex and part:getWheelIndex() ~= -1 then return "VehicleWorkOnTire" end
  local id = part.getId and part:getId() or ""
  id = tostring(id)
  if string.find(id, "Brake", 1, true) then return "VehicleWorkOnTire" end
  return "VehicleWorkOnMid"
end

function VRO.DoFixAction:isValid()
  return self.part and self.part:getVehicle() ~= nil
end

function VRO.DoFixAction:waitToStart()
  local veh = self.part and self.part:getVehicle()
  if veh then self.character:faceThisObject(veh) end
  return self.character:shouldBeTurning()
end

function VRO.DoFixAction:update()
  local veh = self.part and self.part:getVehicle()
  if veh then self.character:faceThisObject(veh) end
end

function VRO.DoFixAction:start()
  local anim = self.actionAnim or defaultAnimForPart(self.part)
  if anim and self.setActionAnim then self:setActionAnim(anim) end
  if self.setOverrideHandModels then
    self:setOverrideHandModels(self.character:getPrimaryHandItem(), nil)
  end
  if self.fxSound then
    self._soundHandle = self.character:getEmitter():playSound(self.fxSound)
  end
end

function VRO.DoFixAction:stop()
  if self._soundHandle then
    self.character:getEmitter():stopSound(self._soundHandle)
    self._soundHandle = nil
  end
  if self.setOverrideHandModels then
    self:setOverrideHandModels(nil, nil)
  end
  ISBaseTimedAction.stop(self)
end

function VRO.DoFixAction:perform()
  local part     = self.part
  local broken   = self.brokenItem
  local hbr      = getHBR(part, broken)

  local fail     = chanceOfFail(broken, self.character, self.fixing, self.fixer, hbr)
  local success  = ZombRand(100) >= fail

  local partMax  = (part.getConditionMax and part:getConditionMax()) or 100
  local partCur  = math.min(part:getCondition(), partMax)

  if success then
    local pct      = condRepairedPercent(broken, self.character, self.fixing, self.fixer, hbr, self.fixerIndex)
    local missing  = partMax - partCur
    local gain     = math.floor((missing * (pct / 100.0)) + 0.5)
    if gain < 1 then gain = 1 end

    part:setCondition(math.min(partMax, partCur + gain))
    if part.getVehicle and part:getVehicle() and part:getVehicle().transmitPartCondition then
      part:getVehicle():transmitPartCondition(part)
    end

    if broken then
      local itemMax = (broken.getConditionMax and broken:getConditionMax()) or 100
      local newItem = math.min(itemMax, broken:getCondition() + gain)
      if broken.setConditionNoSound then broken:setConditionNoSound(newItem) else broken:setCondition(newItem) end
      broken:syncItemFields()
    end

    setHBR(part, broken, hbr + 1)

    if self.fixer.skills then
      for perkName,_ in pairs(self.fixer.skills) do
        local perk = resolvePerk(perkName)
        if perk then self.character:getXp():AddXP(perk, ZombRand(3,6)) end
      end
    end
  else
    if partCur > 0 then
      part:setCondition(partCur - 1)
      if part.getVehicle and part:getVehicle() and part:getVehicle().transmitPartCondition then
        part:getVehicle():transmitPartCondition(part)
      end
      if broken then
        local newItem = math.max(0, broken:getCondition() - 1)
        if broken.setConditionNoSound then broken:setConditionNoSound(newItem) else broken:setCondition(newItem) end
        broken:syncItemFields()
      end
    end
    self.character:getEmitter():playSound("FixingItemFailed")
  end

  consumeItems(self.character, self.fixerBundle)
  if self.globalBundle then consumeItems(self.character, self.globalBundle) end

  if self._soundHandle then
    self.character:getEmitter():stopSound(self._soundHandle)
    self._soundHandle = nil
  end
  if self.setOverrideHandModels then
    self:setOverrideHandModels(nil, nil)
  end

  ISBaseTimedAction.perform(self)
end

function VRO.DoFixAction:new(args)
  local o = ISBaseTimedAction.new(self, args.character)
  o.stopOnWalk   = true
  o.stopOnRun    = true
  o.character    = args.character
  o.part         = args.part
  o.fixing       = args.fixing
  o.fixer        = args.fixer
  o.fixerIndex   = args.fixerIndex or 1
  o.brokenItem   = args.brokenItem
  o.fixerBundle  = args.fixerBundle
  o.globalBundle = args.globalBundle
  o.maxTime      = args.time or 150
  o.actionAnim   = args.anim
  o.fxSound      = args.sfx
  return o
end

----------------------------------------------------------------
-- F) Tooltip helpers (vanilla-style color interp)
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
  out.primary   = pick(fixEq.primary,   recEq.primary)
  out.secondary = pick(fixEq.secondary, recEq.secondary)
  out.wearTag   = pick(fixEq.wearTag,   recEq.wearTag)
  out.wear      = pick(fixEq.wear,      recEq.wear)
  return out
end
local function resolveAnim(fixer, fixing) return pick(fixer.anim, fixing.anim) end
local function resolveSound(fixer, fixing) return pick(fixer.sound, fixing.sound) end
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

  -- Fixer item
  do
    local need = fixer.uses or 1
    local have = 0
    local bundles = gatherRequiredItems(player:getInventory(), fixer.item, need)
    if bundles then for _,b in ipairs(bundles) do have = have + (b.takeUses or 0) end end
    local nm  = displayNameFromFullType(fixer.item)
    local rgb = (have >= need) and "0,1,0" or "1,0,0"
    desc = addNeedsLine(desc, rgb, nm, have, need)
  end

  -- Global item (e.g., blowtorch uses)
  if fixing.globalItem then
    local need = fixing.globalItem.uses or 1
    local have = 0
    local bundles = gatherRequiredItems(player:getInventory(), fixing.globalItem.item, need)
    if bundles then for _,b in ipairs(bundles) do have = have + (b.takeUses or 0) end end
    local nm  = displayNameFromFullType(fixing.globalItem.item)
    local rgb = (have >= need) and "0,1,0" or "1,0,0"
    desc = addNeedsLine(desc, rgb, nm, have, need)
  end

  -- Wear requirement (merged equip, not consumed)
  local eq = mergeEquip(fixer.equip, fixing.equip)
  if eq.wearTag then
    local ok  = hasTag(player:getInventory(), eq.wearTag)
    local it  = firstTagItem(player:getInventory(), eq.wearTag)
    local name = it and it:getDisplayName() or fallbackNameForTag(eq.wearTag)
    desc = addNeedsLine(desc, ok and "0,1,0" or "1,0,0", name, ok and 1 or 0, 1)
  elseif eq.wear then
    local need, have = 1, 0
    local it = findFirstTypeRecurse(player:getInventory(), eq.wear)
    if it then have = 1 end
    local name = (it and it.getDisplayName) and it:getDisplayName() or displayNameFromFullType(eq.wear)
    desc = addNeedsLine(desc, (have>=need) and "0,1,0" or "1,0,0", name, have, need)
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
-- G) Context Menu Injection (under "Repair >")
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

-- Equip logic:
--  - If primary is a blowtorch and the recipe globalItem needs uses,
--    equip the best torch meeting that need (or the fullest non-empty).
local function queueEquipActions(playerObj, eq, globalItem)
  if not eq then return end

  local needTorchUses = nil
  local torchRequested = false
  if globalItem and globalItem.item and (isFullTypeBlowTorch(globalItem.item)) then
    needTorchUses = globalItem.uses or 1
  end
  if eq.primary and isFullTypeBlowTorch(eq.primary) then
    torchRequested = true
  end

  if torchRequested then
    local bestTorch = findBestBlowtorch(playerObj:getInventory(), needTorchUses or 1)
    if bestTorch then
      toPlayerInventory(playerObj, bestTorch)
      ISTimedActionQueue.add(ISEquipWeaponAction:new(playerObj, bestTorch, 50, true, false))
    else
      local it = findFirstTypeRecurse(playerObj:getInventory(), eq.primary)
      if it then toPlayerInventory(playerObj, it); ISTimedActionQueue.add(ISEquipWeaponAction:new(playerObj, it, 50, true, false)) end
    end
  elseif eq.primary then
    local it = findFirstTypeRecurse(playerObj:getInventory(), eq.primary)
    if it then toPlayerInventory(playerObj, it); ISTimedActionQueue.add(ISEquipWeaponAction:new(playerObj, it, 50, true, false)) end
  end

  if eq.secondary then
    local it = findFirstTypeRecurse(playerObj:getInventory(), eq.secondary)
    if it then toPlayerInventory(playerObj, it); ISTimedActionQueue.add(ISEquipWeaponAction:new(playerObj, it, 50, false, false)) end
  end

  if eq.wearTag and ISInventoryPaneContextMenu and ISInventoryPaneContextMenu.wearItem then
    local it = firstTagItem(playerObj:getInventory(), eq.wearTag)
    if it then toPlayerInventory(playerObj, it); ISInventoryPaneContextMenu.wearItem(it, playerObj:getPlayerNum()) end
  elseif eq.wear and ISInventoryPaneContextMenu and ISInventoryPaneContextMenu.wearItem then
    local it = findFirstTypeRecurse(playerObj:getInventory(), eq.wear)
    if it then toPlayerInventory(playerObj, it); ISInventoryPaneContextMenu.wearItem(it, playerObj:getPlayerNum()) end
  end
end

local old_doPart = ISVehicleMechanics.doPartContextMenu
function ISVehicleMechanics:doPartContextMenu(part, x, y)
  old_doPart(self, part, x, y)

  local playerObj = getSpecificPlayer(self.playerNum)
  if not playerObj or not part then return end
  if part:getCondition() >= 100 then return end

  local broken = part:getInventoryItem()
  local fullType = broken and broken:getFullType() or nil
  if not fullType then return end

  if not self.context then
    self.context = ISContextMenu.get(self.playerNum, x + self:getAbsoluteX(), y + self:getAbsoluteY())
  end

  local parent, subMenu
  local function ensureSubMenu()
    if not parent then
      parent  = self.context:addOption(getText("ContextMenu_Repair"), nil, nil)
      subMenu = ISContextMenu:getNew(self.context)
      self.context:addSubMenu(parent, subMenu)
    end
  end

  local any = false

  for _, fixing in ipairs(VRO.Recipes) do
    local applies = false
    for _, req in ipairs(fixing.require or {}) do
      if req == fullType then applies = true; break end
    end

    if applies then
      for idx, fixer in ipairs(fixing.fixers or {}) do
        local fixerBundle  = gatherRequiredItems(playerObj:getInventory(), fixer.item, fixer.uses or 1)
        local globalBundle = nil
        if fixing.globalItem then
          globalBundle = gatherRequiredItems(playerObj:getInventory(), fixing.globalItem.item, fixing.globalItem.uses or 1)
        end

        local skillsOK = true
        if fixer.skills then
          for name,req in pairs(fixer.skills) do
            if perkLevel(playerObj, name) < req then skillsOK = false; break end
          end
        end

        -- merged equip (recipe defaults + fixer overrides)
        local eq = mergeEquip(fixer.equip, fixing.equip)

        -- Wear requirement presence (TAG or specific full type). NOT consumed.
        local wearOK = true
        if eq.wearTag then
          wearOK = hasTag(playerObj:getInventory(), eq.wearTag)
        elseif eq.wear then
          wearOK = (findFirstTypeRecurse(playerObj:getInventory(), eq.wear) ~= nil)
        end

        local haveAll = (fixerBundle ~= nil)
                      and (fixing.globalItem == nil or globalBundle ~= nil)
                      and skillsOK
                      and wearOK

        local rawName = displayNameFromFullType(fixer.item)
        local label   = tostring(fixer.uses or 1) .. " " .. humanizeForMenuLabel(rawName)

        ensureSubMenu()
        local option
        if haveAll then
          any = true
          option = subMenu:addOption(label, playerObj, function(playerObj_, part_, fixing_, fixer_, idx_, broken_, fixerBundle_, globalBundle_)
            queuePathToPartArea(playerObj_, part_)

            -- merged equip + smart blowtorch
            local eq_   = mergeEquip(fixer_.equip, fixing_.equip)
            queueEquipActions(playerObj_, eq_, fixing_.globalItem)

            -- resolve time/anim/sound (fixer overrides recipe)
            local tm    = resolveTime(fixer_, fixing_, playerObj_, broken_)
            local anim  = resolveAnim(fixer_, fixing_)
            local sfx   = resolveSound(fixer_, fixing_)

            local act  = VRO.DoFixAction:new({
              character    = playerObj_,
              part         = part_,
              fixing       = fixing_,
              fixer        = fixer_,
              fixerIndex   = idx_,
              brokenItem   = broken_,
              fixerBundle  = fixerBundle_,
              globalBundle = globalBundle_,
              time         = tm,
              anim         = anim,
              sfx          = sfx,
            })
            ISTimedActionQueue.add(act)
          end, part, fixing, fixer, idx, broken, fixerBundle, globalBundle)
        else
          option = subMenu:addOption(label, nil, nil)
          option.notAvailable = true
        end

        local tip = ISToolTip:new()
        addFixerTooltip(tip, playerObj, part, fixing, fixer, idx, broken)
        option.toolTip = tip
      end
    end
  end

  if parent and not any then parent.notAvailable = true end
end

----------------------------------------------------------------
-- H) Public API
----------------------------------------------------------------
function VRO.addRecipe(recipe) table.insert(VRO.Recipes, recipe) end
VRO.API = { addRecipe = VRO.addRecipe }
VRO.Module = VRO
return VRO