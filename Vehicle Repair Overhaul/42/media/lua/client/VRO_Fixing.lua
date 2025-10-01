---@diagnostic disable: undefined-field, param-type-mismatch

require "Vehicles/ISUI/ISVehicleMechanics"
require "ISUI/ISToolTip"
require "ISUI/ISInventoryPaneContextMenu"
require "TimedActions/ISBaseTimedAction"
require "TimedActions/ISPathFindAction"
require "TimedActions/ISEquipWeaponAction"

local VRO = {}
VRO.__index = VRO

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
    if u>0 then
      local take = math.min(u, needUses-total)
      list[#list+1] = { item=it, takeUses=take }
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

-- Tag helpers
local function firstTagItem(inv, tag) return inv:getFirstTagRecurse(tag) end
local function hasTag(inv, tag) return inv:containsTag(tag) end
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
  local id = tostring(part.getId and part:getId() or "")
  if string.find(id, "Brake", 1, true) then return "VehicleWorkOnTire" end
  return "VehicleWorkOnMid"
end

function VRO.DoFixAction:isValid()
  if self.part and self.part:getVehicle() then return true end
  if self.brokenItem then return true end
  return false
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
  local part   = self.part
  local broken = self.brokenItem
  local hbr    = getHBR(part, broken)

  local fail    = chanceOfFail(broken, self.character, self.fixing, self.fixer, hbr)
  local success = ZombRand(100) >= fail

  -- Compute target stats from either the installed part or the loose item.
  local targetMax, targetCur
  if part then
    targetMax = (part.getConditionMax and part:getConditionMax()) or 100
    targetCur = math.min(part:getCondition(), targetMax)
  else
    targetMax = (broken and broken.getConditionMax and broken:getConditionMax()) or 100
    targetCur = broken and broken:getCondition() or 0
  end

  if success then
    local pct     = condRepairedPercent(broken, self.character, self.fixing, self.fixer, hbr, self.fixerIndex)
    local missing = math.max(0, targetMax - targetCur)
    local gain    = math.floor((missing * (pct / 100.0)) + 0.5)
    if gain < 1 then gain = 1 end

    if part then
      part:setCondition(math.min(targetMax, targetCur + gain))
      if part.getVehicle and part:getVehicle() and part:getVehicle().transmitPartCondition then
        part:getVehicle():transmitPartCondition(part)
      end
    end
    if broken then
      local newVal = math.min(targetMax, targetCur + gain)
      if broken.setConditionNoSound then broken:setConditionNoSound(newVal) else broken:setCondition(newVal) end
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
    if part and targetCur > 0 then
      part:setCondition(targetCur - 1)
      if part.getVehicle and part:getVehicle() and part:getVehicle().transmitPartCondition then
        part:getVehicle():transmitPartCondition(part)
      end
    end
    if broken then
      local newVal = math.max(0, targetCur - 1)
      if broken.setConditionNoSound then broken:setConditionNoSound(newVal) else broken:setCondition(newVal) end
      broken:syncItemFields()
    end
    self.character:getEmitter():playSound("FixingItemFailed")
  end

  consumeItems(self.character, self.fixerBundle)
  if self.globalBundle then consumeItems(self.character, self.globalBundle) end

  if self._soundHandle then self.character:getEmitter():stopSound(self._soundHandle) end
  if self.setOverrideHandModels then self:setOverrideHandModels(nil,nil) end
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
-- F) Tooltip (dynamic color + icon)
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

  -- Global item
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
    local it = findFirstTypeRecurse(player:getInventory(), eq.wear)
    local nm = (it and it.getDisplayName) and it:getDisplayName() or displayNameFromFullType(eq.wear)
    desc = addNeedsLine(desc, it and "0,1,0" or "1,0,0", nm, it and 1 or 0, 1)
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

-- Equip logic (smart torch):
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
  if not part:getItemType() or part:getItemType():isEmpty() then return end
  local broken = part:getInventoryItem(); if not broken then return end
  if part:getCondition() >= 100 then return end

  local ft, any = broken:getFullType(), false
  for _,fx in ipairs(VRO.Recipes) do
    for _,req in ipairs(fx.require or {}) do if req==ft then any=true break end end
    if any then break end
  end
  if not any then return end

  self.context = self.context or ISContextMenu.get(self.playerNum, x + self:getAbsoluteX(), y + self:getAbsoluteY())
  local fixParent = self.context:addOption(getText("ContextMenu_Repair"), nil, nil)
  local subMenu   = ISContextMenu:getNew(self.context); self.context:addSubMenu(fixParent, subMenu)
  local rendered  = false

  for _,fixing in ipairs(VRO.Recipes) do
    local applies=false
    for _,req in ipairs(fixing.require or {}) do if req==ft then applies=true break end end
    if applies then
      for idx, fixer in ipairs(fixing.fixers or {}) do
        local fxBundle  = gatherRequiredItems(playerObj:getInventory(), fixer.item, fixer.uses or 1)
        local glBundle  = fixing.globalItem and gatherRequiredItems(playerObj:getInventory(), fixing.globalItem.item, fixing.globalItem.uses or 1) or nil

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

        local haveAll = fxBundle and (not fixing.globalItem or glBundle) and skillsOK and wearOK
        local raw = displayNameFromFullType(fixer.item)
        local label = tostring(fixer.uses or 1) .. " " .. humanizeForMenuLabel(raw)

        local option
        if haveAll then
          rendered = true
          option = subMenu:addOption(label, playerObj, function(p, prt, fixg, fixr, idx_, brk, fxB, glB)
            queuePathToPartArea(p, prt)
            queueEquipActions(p, mergeEquip(fixr.equip, fixg.equip), fixg.globalItem)
            local tm   = resolveTime(fixr, fixg, p, brk)
            local anim = resolveAnim(fixr, fixg)
            local sfx  = resolveSound(fixr, fixg)
            ISTimedActionQueue.add(VRO.DoFixAction:new{
              character=p, part=prt, fixing=fixg, fixer=fixr, fixerIndex=idx_,
              brokenItem=brk, fixerBundle=fxB, globalBundle=glB, time=tm, anim=anim, sfx=sfx,
            })
          end, part, fixing, fixer, idx, broken, fxBundle, glBundle)
        else
          option = subMenu:addOption(label, nil, nil); option.notAvailable = true
        end
        local tip = ISToolTip:new(); addFixerTooltip(tip, playerObj, part, fixing, fixer, idx, broken); option.toolTip = tip
      end
    end
  end

  if not rendered then fixParent.notAvailable = true end
end

----------------------------------------------------------------
-- I) Inventory repairs (vanilla-style submenu creation)
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
  if not broken or isInventoryItemBroken(broken) then return end -- vanilla: only when NOT broken
  local ft = broken:getFullType(); if not ft then return end

  local any=false
  for _,fx in ipairs(VRO.Recipes) do
    for _,req in ipairs(fx.require or {}) do if req==ft then any=true break end end
    if any then break end
  end
  if not any then return end

  local parent = context:addOption(invRepairLabel(broken), nil, nil)
  local sub    = ISContextMenu:getNew(context); context:addSubMenu(parent, sub)

  local rendered=false
  for _,fixing in ipairs(VRO.Recipes) do
    local applies=false
    for _,req in ipairs(fixing.require or {}) do if req==ft then applies=true break end end
    if applies then
      for idx,fixer in ipairs(fixing.fixers or {}) do
        local fxBundle  = gatherRequiredItems(playerObj:getInventory(), fixer.item, fixer.uses or 1)
        local glBundle  = fixing.globalItem and gatherRequiredItems(playerObj:getInventory(), fixing.globalItem.item, fixing.globalItem.uses or 1) or nil
        local skillsOK = true
        if fixer.skills then
          for name,req in pairs(fixer.skills) do if perkLevel(playerObj,name) < req then skillsOK=false break end end
        end
        local eq = mergeEquip(fixer.equip, fixing.equip)
        local wearOK = true
        if eq.wearTag then wearOK = hasTag(playerObj:getInventory(), eq.wearTag)
        elseif eq.wear then wearOK = (findFirstTypeRecurse(playerObj:getInventory(), eq.wear) ~= nil) end

        local haveAll = fxBundle and (not fixing.globalItem or glBundle) and skillsOK and wearOK
        local raw = displayNameFromFullType(fixer.item)
        local label = tostring(fixer.uses or 1) .. " " .. humanizeForMenuLabel(raw)

        local option
        if haveAll then
          rendered=true
          option = sub:addOption(label, playerObj, function(p, fixg, fixr, idx_, brk, fxB, glB)
            queueEquipActions(p, mergeEquip(fixr.equip, fixg.equip), fixg.globalItem)
            local tm   = resolveTime(fixr, fixg, p, brk)
            local anim = resolveAnim(fixr, fixg)
            local sfx  = resolveSound(fixr, fixg)
            ISTimedActionQueue.add(VRO.DoFixAction:new{
              character=p, part=nil, fixing=fixg, fixer=fixr, fixerIndex=idx_,
              brokenItem=brk, fixerBundle=fxB, globalBundle=glB, time=tm, anim=anim, sfx=sfx,
            })
          end, fixing, fixer, idx, broken, fxBundle, glBundle)
        else
          option = sub:addOption(label, nil, nil); option.notAvailable = true
        end
        local tip = ISToolTip:new(); addFixerTooltip(tip, playerObj, nil, fixing, fixer, idx, broken); option.toolTip = tip
      end
    end
  end

  if not rendered then parent.notAvailable = true end
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
-- J) Public API
----------------------------------------------------------------
function VRO.addRecipe(recipe) table.insert(VRO.Recipes, recipe) end
VRO.API = { addRecipe = VRO.addRecipe }
VRO.Module = VRO
return VRO