require "Vehicles/ISUI/ISVehicleMechanics"
require "TimedActions/ISPathFindAction"
require "TimedActions/ISEquipWeaponAction"
require "ISUI/ISToolTip"

local VRO = {}
VRO.__index = VRO

----------------------------------------------------------------
--  A) RECIPE DEFINITIONS (EDIT THIS TABLE)
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
    globalItem = { item="Base.BlowTorch", uses=3 },
    conditionModifier = 0.8,
    fixers = {
      { item="Base.SheetMetal",        uses=1, skills={ MetalWelding=3, Mechanics=3 },
        equip={ primary="Base.BlowTorch", wear="Base.WeldingMask" }, anim="Welding", sound="BlowTorch" },
      { item="Base.SmallSheetMetal",   uses=2, skills={ MetalWelding=3, Mechanics=3 },
        equip={ primary="Base.BlowTorch", wear="Base.WeldingMask" }, anim="Welding", sound="BlowTorch" },
      { item="Base.CopperSheet",       uses=1, skills={ MetalWelding=3, Mechanics=3 },
        equip={ primary="Base.BlowTorch", wear="Base.WeldingMask" }, anim="Welding", sound="BlowTorch" },
      { item="Base.SmallCopperSheet",  uses=2, skills={ MetalWelding=3, Mechanics=3 },
        equip={ primary="Base.BlowTorch", wear="Base.WeldingMask" }, anim="Welding", sound="BlowTorch" },
      { item="Base.GoldSheet",         uses=1, skills={ MetalWelding=3, Mechanics=3 },
        equip={ primary="Base.BlowTorch", wear="Base.WeldingMask" }, anim="Welding", sound="BlowTorch" },
      { item="Base.SilverSheet",       uses=1, skills={ MetalWelding=3, Mechanics=3 },
        equip={ primary="Base.BlowTorch", wear="Base.WeldingMask" }, anim="Welding", sound="BlowTorch" },
      { item="Base.SmallArmorPlate",   uses=2, skills={ MetalWelding=3, Mechanics=3 },
        equip={ primary="Base.BlowTorch", wear="Base.WeldingMask" }, anim="Welding", sound="BlowTorch" },
      { item="Base.AluminumScrap",     uses=8, skills={ MetalWelding=3, Mechanics=3 },
        equip={ primary="Base.BlowTorch", wear="Base.WeldingMask" }, anim="Welding", sound="BlowTorch" },
      { item="Base.BrassScrap",        uses=8, skills={ MetalWelding=3, Mechanics=3 },
        equip={ primary="Base.BlowTorch", wear="Base.WeldingMask" }, anim="Welding", sound="BlowTorch" },
      { item="Base.CopperScrap",       uses=8, skills={ MetalWelding=3, Mechanics=3 },
        equip={ primary="Base.BlowTorch", wear="Base.WeldingMask" }, anim="Welding", sound="BlowTorch" },
      { item="Base.IronScrap",         uses=8, skills={ MetalWelding=3, Mechanics=3 },
        equip={ primary="Base.BlowTorch", wear="Base.WeldingMask" }, anim="Welding", sound="BlowTorch" },
      { item="Base.ScrapMetal",        uses=8, skills={ MetalWelding=3, Mechanics=3 },
        equip={ primary="Base.BlowTorch", wear="Base.WeldingMask" }, anim="Welding", sound="BlowTorch" },
      { item="Base.SteelScrap",        uses=8, skills={ MetalWelding=3, Mechanics=3 },
        equip={ primary="Base.BlowTorch", wear="Base.WeldingMask" }, anim="Welding", sound="BlowTorch" },
      { item="Base.UnusableMetal",     uses=8, skills={ MetalWelding=3, Mechanics=3 },
        equip={ primary="Base.BlowTorch", wear="Base.WeldingMask" }, anim="Welding", sound="BlowTorch" },
    },
  },
}

----------------------------------------------------------------
--  B) HELPERS (inventory, drainables, names, HBR, tooltip icon)
----------------------------------------------------------------

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
  if name:sub(1,6) == "Small " then return name:sub(7) .. " - Small" end
  return name
end

-- Persist HaveBeenRepaired on the part if the backing item doesn’t implement it
local function getHBR(part, invItem)
  if invItem and invItem.getHaveBeenRepaired then return invItem:getHaveBeenRepaired() end
  local md = part and part:getModData() or {}
  return md.VRO_HaveBeenRepaired or 0
end
local function setHBR(part, invItem, val)
  if invItem and invItem.setHaveBeenRepaired then invItem:setHaveBeenRepaired(val) end
  if part then part:getModData().VRO_HaveBeenRepaired = val end
end

-- Tooltip icon from full type (Texture vs string-safe)
local function setTooltipIconFromFullType(tip, fullType)
  local sm = ScriptManager and ScriptManager.instance
  if sm and sm.FindItem then
    local script = sm:FindItem(fullType)
    if script and script.getIcon and script:getIcon() then
      tip:setTexture("Item_" .. script:getIcon())
    end
  end
end

----------------------------------------------------------------
--  C) PERKS + VANILLA MATH
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

-- chance of fail (0..100)
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

-- “Potentially repairs: X%”
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
--  D) TIMED ACTION
----------------------------------------------------------------
VRO.DoFixAction = ISBaseTimedAction:derive("VRO_DoFixAction")

function VRO.DoFixAction:isValid()
  return self.part and self.part:getVehicle() ~= nil
end

function VRO.DoFixAction:update()
  -- optional: progress hooks / loop sfx
end

function VRO.DoFixAction:start()
  if self.actionAnim and self.setActionAnim then self:setActionAnim(self.actionAnim) end
  -- Heater parity: force the equipped item to render in-hand
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

-- Constructor takes a SINGLE args table to avoid Kahlua vararg issues
function VRO.DoFixAction:new(args)
  local o = ISBaseTimedAction.new(self, args.character)
  o.maxTime      = args.time or 160
  o.character    = args.character
  o.part         = args.part
  o.fixing       = args.fixing
  o.fixer        = args.fixer
  o.fixerIndex   = args.fixerIndex or 1
  o.brokenItem   = args.brokenItem
  o.fixerBundle  = args.fixerBundle
  o.globalBundle = args.globalBundle
  o.fxSound      = args.sfx
  o.actionAnim   = args.anim
  o.stopOnWalk   = true
  o.stopOnRun    = true
  return o
end

----------------------------------------------------------------
--  E) CONTEXT MENU HOOK (single “Repair >” parent)
----------------------------------------------------------------
local old_doPart = ISVehicleMechanics.doPartContextMenu
function ISVehicleMechanics:doPartContextMenu(part, x, y)
  old_doPart(self, part, x, y)

  local playerObj = getSpecificPlayer(self.playerNum)
  if not playerObj or not part then return end
  if part:getCondition() >= 100 then return end

  local broken = part:getInventoryItem()
  local fullType = broken and broken:getFullType() or nil

  if not self.context then
    self.context = ISContextMenu.get(self.playerNum, x + self:getAbsoluteX(), y + self:getAbsoluteY())
  end

  local parent = self.context:addOption(getText("ContextMenu_Repair"), nil, nil)
  local subMenu = ISContextMenu:getNew(self.context)
  self.context:addSubMenu(parent, subMenu)

  local any = false

  for _,fixing in ipairs(VRO.Recipes) do
    local applies = false
    if fullType then
      for _,req in ipairs(fixing.require or {}) do
        if req == fullType then applies = true; break end
      end
    end
    if applies then
      for idx,fixer in ipairs(fixing.fixers or {}) do
        local fixerBundle  = gatherRequiredItems(playerObj:getInventory(), fixer.item, fixer.uses or 1)
        local globalBundle = nil
        if fixing.globalItem then
          globalBundle = gatherRequiredItems(playerObj:getInventory(), fixing.globalItem.item, fixing.globalItem.uses or 1)
        end

        local skillsOK = true
        if fixer.skills then
          for name,req in pairs(fixer.skills) do
            if perkLevel(playerObj, name) < req then skillsOK = false break end
          end
        end
        local haveAll = (fixerBundle ~= nil) and (fixing.globalItem == nil or globalBundle ~= nil) and skillsOK

        -- "<uses> <ItemName>" label, with small suffix moved to end
        local rawName = displayNameFromFullType(fixer.item)
        local label   = tostring(fixer.uses or 1) .. " " .. humanizeForMenuLabel(rawName)

        local option
        if haveAll then
          any = true
          option = subMenu:addOption(label, playerObj, function(playerObj_, part_, fixing_, fixer_, idx_, broken_, fixerBundle_, globalBundle_)
            -- 1) Path first (heater flow)
            ISTimedActionQueue.add(ISPathFindAction:pathToVehicleArea(playerObj_, part_:getVehicle(), "Engine"))

            -- 2) Equip AFTER path so it appears in-hand
            local eq = fixer_.equip or {}
            if eq.primary then
              local it = playerObj_:getInventory():FindAndReturn(eq.primary)
              if it then
                if ISVehiclePartMenu and ISVehiclePartMenu.toPlayerInventory then
                  ISVehiclePartMenu.toPlayerInventory(playerObj_, it)
                end
                ISTimedActionQueue.add(ISEquipWeaponAction:new(playerObj_, it, 50, true, false))
              end
            end
            if eq.secondary then
              local it = playerObj_:getInventory():FindAndReturn(eq.secondary)
              if it then
                if ISVehiclePartMenu and ISVehiclePartMenu.toPlayerInventory then
                  ISVehiclePartMenu.toPlayerInventory(playerObj_, it)
                end
                ISTimedActionQueue.add(ISEquipWeaponAction:new(playerObj_, it, 50, false, false))
              end
            end
            if eq.wear then
              local it = playerObj_:getInventory():FindAndReturn(eq.wear)
              if it then ISInventoryPaneContextMenu.wearItem(it, playerObj_:getPlayerNum()) end
            end

            -- 3) Timed action
            local tm   = (fixer_.time and fixer_.time(playerObj_, broken_)) or 160
            local anim = fixer_.anim
            local sfx  = fixer_.sound
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
          option = subMenu:addOption(label, nil, nil); option.notAvailable = true
        end

        -- Tooltip (name + icon + vanilla-style color interpolation + needs)
        local hbr = getHBR(part, broken)
        local fail = chanceOfFail(broken, playerObj, fixing, fixer, hbr)
        local success = math.max(0, math.min(100, 100 - fail))
        local pot = condRepairedPercent(broken, playerObj, fixing, fixer, hbr, idx)

        local tip = ISToolTip:new()
        tip:initialise(); tip:setVisible(false)
        option.toolTip = tip

        tip:setName(humanizeForMenuLabel(rawName))
        setTooltipIconFromFullType(tip, fixer.item)

        -- Vanilla-style gradient using Core bad→good highlight colors
        local repairedCol = ColorInfo.new(0,0,0,1)
        local successCol  = ColorInfo.new(0,0,0,1)
        getCore():getBadHighlitedColor():interp(getCore():getGoodHighlitedColor(), (pot or 0)/100, repairedCol)
        getCore():getBadHighlitedColor():interp(getCore():getGoodHighlitedColor(), (success or 0)/100, successCol)

        local color1 = string.format("<RGB:%s,%s,%s>", repairedCol:getR(), repairedCol:getG(), repairedCol:getB())
        local color2 = string.format("<RGB:%s,%s,%s>", successCol:getR(),  successCol:getG(),  successCol:getB())

        tip.description = ""
        tip.description = tip.description .. " " .. color1 .. " " .. getText("Tooltip_potentialRepair") .. " " .. math.ceil(pot or 0) .. "% <LINE>"
        tip.description = tip.description .. " " .. color2 .. " " .. getText("Tooltip_chanceSuccess")   .. " " .. math.ceil(success or 0) .. "% <LINE><LINE>"
        tip.description = tip.description .. " <RGB:1,1,1> " .. getText("Tooltip_craft_Needs") .. ": <LINE><LINE>"

        -- Skills
        if fixer.skills then
          local function perkLabel(pn)
            local txt = getText("IGUI_perks_" .. pn)
            return (not txt or txt == ("IGUI_perks_" .. pn)) and pn or txt
          end
          for name,req in pairs(fixer.skills) do
            local lvl = perkLevel(playerObj, name)
            local ok = lvl >= req
            tip.description = tip.description .. string.format(" <RGB:%s>%s %d/%d <LINE>", ok and "0,1,0" or "1,0,0", perkLabel(name), lvl, req)
          end
        end

        -- Fixer item line
        do
          local have = 0
          if fixerBundle then for _,b in ipairs(fixerBundle) do have = have + (b.takeUses or 0) end end
          local need = fixer.uses or 1
          local disp = displayNameFromFullType(fixer.item)
          local ok   = have >= need
          tip.description = tip.description .. string.format(" <RGB:%s>%s %d/%d <LINE>", ok and "0,1,0" or "1,0,0", disp, have, need)
        end

        -- Global item line
        if fixing.globalItem then
          local gi = fixing.globalItem
          local have = 0
          if globalBundle then for _,b in ipairs(globalBundle) do have = have + (b.takeUses or 0) end end
          local disp = displayNameFromFullType(gi.item)
          local ok = have >= (gi.uses or 1)
          tip.description = tip.description .. string.format(" <RGB:%s>%s %d/%d <LINE>", ok and "0,1,0" or "1,0,0", disp, have, (gi.uses or 1))
        end
      end
    end
  end

  -- Optional: remove empty parent if nothing applied
  -- if not any then self.context:removeOptionByName(getText("ContextMenu_Repair")) end
end

----------------------------------------------------------------
--  F) PUBLIC API
----------------------------------------------------------------
function VRO.addRecipe(recipe) table.insert(VRO.Recipes, recipe) end
VRO.API = { addRecipe = VRO.addRecipe }
VRO.Module = VRO
return VRO
