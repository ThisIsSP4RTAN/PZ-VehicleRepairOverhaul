---@diagnostic disable: undefined-field, param-type-mismatch, redundant-parameter
require "TimedActions/ISBaseTimedAction"
local VRO = require "VRO/Core"

----------------------------------------------------------------
-- Minimal helpers the action relies on
----------------------------------------------------------------
local function isDrainable(it) return it and instanceof(it, "DrainableComboItem") end

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

local function consumeItems(character, bundles)
  if not bundles or bundles[1] == nil then return end
  for i = 1, #bundles do
    local b = bundles[i]
    if b then
      local it, take = b.item, b.takeUses or 0
      if it and take > 0 then
        if isDrainable(it) then
          if it.Use then
            for _ = 1, take do
              if drainableUses(it) <= 0 then break end
              it:Use()
            end
          elseif it.getUseDelta and it.getUsedDelta and it.setUsedDelta then
            local step = it:getUseDelta()
            it:setUsedDelta(math.min(1.0, it:getUsedDelta() + step * take))
          end
          if drainableUses(it) <= 0 then
            local con = (it.getContainer and it:getContainer()) or (character and character:getInventory()) or nil
            if con then con:Remove(it) end
          end
        else
          local con = (it.getContainer and it:getContainer()) or (character and character:getInventory()) or nil
          if con then con:Remove(it) end
        end
      end
    end
  end
end

-- HaveBeenRepaired persistence helpers (supports part modData or loose item HBR)
local function getHBR(part, invItem)
  if invItem and invItem.getHaveBeenRepaired then return invItem:getHaveBeenRepaired() end
  local md = part and part:getModData() or {}
  return md.VRO_HaveBeenRepaired or 0
end

local function setHBR(part, invItem, val)
  if invItem and invItem.setHaveBeenRepaired then invItem:setHaveBeenRepaired(val) end
  if part then part:getModData().VRO_HaveBeenRepaired = val end
end

-- Returns true only if the part has a real inventory item with a module-qualified full type
-- (e.g., "Base.Something"). Parts like TruckBed (no item) will return false.
local function _partHasModuleItem(part)
  if not part then return false end
  if not (part.getInventoryItem and part:getInventoryItem()) then return false end
  local inv = part:getInventoryItem()
  local ft  = inv and inv.getFullType and inv:getFullType() or nil
  -- Must contain a '.' to be a module-qualified type (e.g., "Base.Foo")
  return (ft ~= nil) and (string.find(ft, ".", 1, true) ~= nil)
end

-- Perk helpers + repair math
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

local function chanceOfFail(chr, fixer, hbr)
  local fail = 3.0
  if fixer and fixer.skills then
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

local function condRepairedPercent(chr, fixing, fixer, hbr, fixerIndex)
  local base = (fixerIndex == 1) and 50.0 or ((fixerIndex == 2) and 20.0 or 10.0)
  base = base * (1.0 / (hbr + 1))
  if fixer and fixer.skills then
    for name,req in pairs(fixer.skills) do
      local lvl = perkLevel(chr, name)
      if lvl > req then base = base + math.min((lvl - req) * 5, 25)
      else              base = base - (req - lvl) * 15 end
    end
  end
  base = base * ((fixing and fixing.conditionModifier) or 1.0)
  if base < 0 then base = 0 elseif base > 100 then base = 100 end
  return base
end

-- Keep-flag application (mirror vanilla)
local function _normalizeFlags(f)
  if f == nil then return nil end

  -- Map-like table: keep as-is (no iteration needed here)
  if type(f) == "table" and f[1] == nil then
    return f
  end

  -- Array-of-strings → { flag=true, ... } using indexing
  if type(f) == "table" then
    local m, n = {}, 0
    for i = 1, #f do
      local k = f[i]
      if type(k) == "string" then
        m[k] = true
        n = n + 1
      end
    end
    return (n > 0) and m or nil  -- no `next`
  end
  return nil
end

local function _perkLevel(chr, name)
  return (perkLevel and perkLevel(chr, name)) or 0
end

local function _maintenanceMod(chr)
  local m = _perkLevel(chr, "Maintenance")
  local w = (chr and chr.getWeaponLevel and (chr:getWeaponLevel() or 0)) or 0
  return m + math.floor(w/2)
end

local function _highestRelevantSkill(chr, fixing, fixer)
  local maxv = 0
  local tbl  = (fixer and fixer.skills) or (fixing and fixing.skills) or nil
  if tbl then
    for n,_ in pairs(tbl) do maxv = math.max(maxv, _perkLevel(chr, n)) end
  end
  return maxv
end

local function _applyKeepFlags(chr, item, flags, hiSkill)
  if not (item and flags) then return end
  local fl = _normalizeFlags(flags)
  if not fl then return end

  local skill = (hiSkill or 0) + _maintenanceMod(chr)

  local function dmg(factor)
    if item.damageCheck then item:damageCheck(skill, factor, false) end
  end
  local function sharp()
    if item.hasSharpness and item:hasSharpness() and item.sharpnessCheck then
      item:sharpnessCheck(skill, 1.0, false)
    else
      dmg(6.0)
    end
  end

  if     fl.MayDegradeHeavy     then dmg(1.0)
  elseif fl.MayDegrade          then dmg(2.0)
  elseif fl.MayDegradeLight     then dmg(3.0)
  elseif fl.MayDegradeVeryLight then dmg(6.0)
  end

  if fl.SharpnessCheck then sharp() end
end

local function defaultAnimForPart(part)
  if not part then return "VehicleWorkOnMid" end
  if part.getWheelIndex and part:getWheelIndex() ~= -1 then return "VehicleWorkOnTire" end
  local id = tostring(part.getId and part:getId() or "")
  if string.find(id, "Brake", 1, true) then return "VehicleWorkOnTire" end
  return "VehicleWorkOnMid"
end

-- Build a job label like: "Repair Car Seat"
local function buildJobType(part, brokenItem)
  local label = getText("ContextMenu_Repair")
  local name
  if brokenItem and brokenItem.getDisplayName then
    name = brokenItem:getDisplayName()
  elseif part and part.getInventoryItem and part:getInventoryItem() then
    local inv = part:getInventoryItem()
    if inv and inv.getDisplayName then name = inv:getDisplayName() end
  end
  if name and name ~= "" then
    return label .. "" .. name
  end
  return label
end

----------------------------------------------------------------
-- Progress helpers: show bars on every used item
----------------------------------------------------------------
-- Progress helpers: show bars on the EXACT items we actually use/keep
local function collectProgressItems(self)
  local list, seen = {}, {}
  local function add(it)
    if it and it.setJobDelta and not seen[it] then
      seen[it] = true
      list[#list + 1] = it
    end
  end

  local function addBundle(bundle)
    if not (bundle and bundle[1] ~= nil) then return end
    for i = 1, #bundle do
      local b = bundle[i]
      if b then add(b.item) end
    end
  end

  -- Consumed stuff
  addBundle(self.fixerBundle)
  addBundle(self.globalBundle)

  -- Not-consumed items we explicitly chose for flags/damage (globals keep + equip keep)
  local keep = self.keepFlagTargets
  if keep and keep[1] ~= nil then
    for i = 1, #keep do
      local k = keep[i]
      if k then add(k.item) end
    end
  end

  -- Hands we told the TA to show (in case they weren’t in keepFlagTargets)
  add(self.expectedPrimary)
  add(self.expectedSecondary)

  -- The loose broken item (inventory repair)
  add(self.brokenItem)

  return list
end

----------------------------------------------------------------
-- Timed Action (shared)
----------------------------------------------------------------
VRO.DoFixAction = ISBaseTimedAction:derive("VRO_DoFixAction")

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

  -- Drive all progress bars
  local items = self._progressItems
  if items and items[1] ~= nil then
    local jd = self:getJobDelta()
    for i = 1, #items do
      local it = items[i]
      if it and it.setJobDelta then it:setJobDelta(jd) end
    end
  end

  if self.setMetabolicTarget then
    self.character:setMetabolicTarget(Metabolics.UsingTools)
  end
end

function VRO.DoFixAction:start()
  local anim = self.actionAnim or defaultAnimForPart(self.part)
  if anim and self.setActionAnim then self:setActionAnim(anim) end

  if self.setOverrideHandModels then
    if self.showModel ~= false then
      local p = self.expectedPrimary   or self.character:getPrimaryHandItem()
      local s = self.expectedSecondary or self.character:getSecondaryHandItem()
      self:setOverrideHandModels(p, s)
    else
      self:setOverrideHandModels(nil, nil)
    end
    self._didOverride = true
  end

  -- Set up all items to show progress bars + text
  self._progressItems = collectProgressItems(self)
  local job = self.jobType or buildJobType(self.part, self.brokenItem)
  local list = self._progressItems
  if list and list[1] ~= nil then
    for i = 1, #list do
      local it = list[i]
      if it then
        if it.setJobType  then it:setJobType(job) end
        if it.setJobDelta then it:setJobDelta(0)  end
      end
    end
  end

  if self.fxSound then
    self._soundHandle = self.character:getEmitter():playSound(self.fxSound)
  end
end

function VRO.DoFixAction:stop()
  local items = self._progressItems
  if items and items[1] ~= nil then
    for i = 1, #items do
      local it = items[i]
      if it and it.setJobDelta then it:setJobDelta(0) end
    end
  end

  if self._soundHandle then
    self.character:getEmitter():stopSound(self._soundHandle)
    self._soundHandle = nil
  end
  if self._didOverride and self.setOverrideHandModels then
    self:setOverrideHandModels(nil, nil)
    self._didOverride = nil
  end
  ISBaseTimedAction.stop(self)
end

function VRO.DoFixAction:perform()
  local part   = self.part
  local broken = self.brokenItem
  local hbr    = getHBR(part, broken)
  local failPct   = chanceOfFail(self.character, self.fixer, hbr)
  local success   = ZombRand(100) >= failPct
  local pctRepair = condRepairedPercent(self.character, self.fixing, self.fixer, hbr, self.fixerIndex)

  -- Target condition (installed part or loose item)
  local targetMax, targetCur
  if part then
    targetMax = (part.getConditionMax and part:getConditionMax()) or 100
    targetCur = math.min(part:getCondition(), targetMax)
  else
    targetMax = (broken and broken.getConditionMax and broken:getConditionMax()) or 100
    targetCur = broken and broken:getCondition() or 0
  end

  if success then
    local missing = math.max(0, targetMax - targetCur)
    local gain    = math.floor((missing * (pctRepair / 100.0)) + 0.5)
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

    -- >>> HBR RECORDING RULES <<<
    -- * Loose inventory repairs always record HBR on the item.
    -- * Installed parts only record HBR when they have a real inventory item with a module-qualified full type.
    -- local shouldRecordHBR =
    --   (broken ~= nil) or
    --   (part ~= nil and _partHasModuleItem(part))

    -- if shouldRecordHBR then
    setHBR(part, broken, hbr + 1)
    -- end

    if self._soundHandle then
      self.character:getEmitter():stopSound(self._soundHandle)
      self._soundHandle = nil
    end
    if self.successSfx then
      self.character:getEmitter():playSound(self.successSfx)
    end

    if self.fixer and self.fixer.skills then
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

  if self.fixerBundle then consumeItems(self.character, self.fixerBundle) end
  if self.globalBundle then consumeItems(self.character, self.globalBundle) end

  local hi   = _highestRelevantSkill(self.character, self.fixing, self.fixer)
  local keep = self.keepFlagTargets
  if keep and keep[1] ~= nil then
    for i = 1, #keep do
      local k = keep[i]
      if k then _applyKeepFlags(self.character, k.item, k.flags, hi) end
    end
  end

  -- Clear all progress bars
  local items = self._progressItems
  if items and items[1] ~= nil then
    for i = 1, #items do
      local it = items[i]
      if it and it.setJobDelta then it:setJobDelta(0) end
    end
  end

  if self._soundHandle then self.character:getEmitter():stopSound(self._soundHandle) end
  if self._didOverride and self.setOverrideHandModels then
    self:setOverrideHandModels(nil,nil)
    self._didOverride = nil
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
  o.successSfx   = args.successSfx
  o.showModel    = (args.showModel ~= false)
  o.expectedPrimary   = args.expectedPrimary
  o.expectedSecondary = args.expectedSecondary
  o.caloriesModifier  = 4
  o.jobType           = args.jobType or buildJobType(args.part, args.brokenItem)

  -- Fold any keep-lists (globals keep + equip keep + direct)
  local keep = {}
  local function append(lst) if lst then for i=1,#lst do keep[#keep+1] = lst[i] end end end
  append(args.globalKeep)
  append(args.equipKeep)
  append(args.keepFlagTargets)
  o.keepFlagTargets = (#keep > 0) and keep or nil

  return o
end

return VRO